import Foundation
import Combine

/// One writer per Space, shared by all windows. Small bounded snapshots commit
/// atomically before publication: failed writes leave both the file and UI intact.
@MainActor
final class WorkspaceStore: ObservableObject {
    private static var stores: [UUID: WorkspaceStore] = [:]
    static func shared(for space: UUID) -> WorkspaceStore {
        if let store = stores[space] { return store }
        let store = WorkspaceStore(space: space, file: Store.file("workspaces/\(space.uuidString)/workspace.json"))
        stores[space] = store
        return store
    }
    static func erase(_ space: UUID) {
        let store = shared(for: space)
        store.erase()
        stores[space] = nil
    }

    @Published private(set) var snapshot: WorkspaceSnapshot
    @Published private(set) var problem: String?
    @Published private(set) var recovery: WorkspaceRecovery?
    private(set) var writable = true
    private(set) var preservesUnresolvedBindings = false
    let file: URL
    var previousFile: URL { file.deletingLastPathComponent().appendingPathComponent("workspace.previous.json") }
    private var committedData: Data?
    private var recoveryData: Data?
    // Preserve unrecognized snapshot/placement fields too, including when notes edit.
    private var original: [String: ObjectValue] = [:]
    private var placementFields: [UUID: [String: ObjectValue]] = [:]
    private var searchRevision: Int?
    private var searchIndex: WorkspaceObjectSearch.Index?
    private struct HistoryEntry {
        let data: Data
        let assets: Set<UUID>
        let unresolved: Bool
    }
    private var undoHistory: [HistoryEntry] = []
    private var redoHistory: [HistoryEntry] = []
    var canUndo: Bool { writable && !undoHistory.isEmpty }
    var canRedo: Bool { writable && !redoHistory.isEmpty }
    private func entry(_ data: Data, _ snapshot: WorkspaceSnapshot) -> HistoryEntry {
        HistoryEntry(data: data, assets: WorkspaceAssets.ownedPreviewIDs(snapshot, in: file.deletingLastPathComponent().appendingPathComponent("assets")), unresolved: snapshot.objects.contains { !$0.supported })
    }
    func discardCanvasHistory() {
        objectWillChange.send(); undoHistory = []; redoHistory = []; reconcileAssets()
    }
    private func trimHistory() {
        while undoHistory.count > 50 || undoHistory.reduce(0, { $0 + $1.data.count }) + redoHistory.reduce(0, { $0 + $1.data.count }) > 16_000_000 {
            guard !undoHistory.isEmpty else { break }; undoHistory.removeFirst()
        }
    }
    @discardableResult func undoCanvas() -> Bool { restoreHistory(undo: true) }
    @discardableResult func redoCanvas() -> Bool { restoreHistory(undo: false) }
    private func restoreHistory(undo: Bool) -> Bool {
        guard writable, let target = (undo ? undoHistory : redoHistory).last, let current = committedData else { return false }
        do {
            let restored = try WorkspaceCommit(data: target.data, space: snapshot.spaceID)
            let before = entry(current, snapshot)
            try commit(restored.snapshot, preserving: restored.fields)
            if undo { undoHistory.removeLast(); redoHistory.append(before) }
            else { redoHistory.removeLast(); undoHistory.append(before) }
            trimHistory(); reconcileAssets(); return true
        } catch { problem = error.localizedDescription; return false }
    }
    private let write: (Data, URL) throws -> Void
    nonisolated static let byteLimit = 2_000_000

    init(space: UUID, file: URL, write: @escaping (Data, URL) throws -> Void = { try WorkspaceFiles.write($0, to: $1) }) {
        snapshot = WorkspaceSnapshot(spaceID: space)
        self.file = file
        self.write = write
        do {
            try WorkspaceFiles.checkPath(file)
            if !WorkspaceFiles.exists(file) {
                // A first workspace is empty; a missing committed file with a
                // backup must be explicitly recovered, never silently reset.
                guard WorkspaceFiles.exists(previousFile) else { return }
                throw WorkspaceError.invalid
            }
            publish(try WorkspaceCommit.read(file, space: space))
            reconcileAssets()
        } catch {
            writable = false
            preservesUnresolvedBindings = true
            problem = error.localizedDescription
            if ![WorkspaceError.futureVersion, .wrongSpace, .unsafePath, .tooLarge].contains(error as? WorkspaceError ?? .invalid),
               let backup = try? WorkspaceCommit.read(previousFile, space: space) {
                recoveryData = backup.data
                recovery = WorkspaceRecovery(revision: backup.snapshot.revision, objectCount: backup.snapshot.objects.count)
            }
        }
    }

    private func publish(_ commit: WorkspaceCommit) {
        original = commit.fields
        placementFields = [:]
        if case .dictionary(let wall) = original["wall"], case .array(let list) = wall["placements"] {
            for value in list {
                if case .dictionary(let fields) = value,
                   let id = fields["id"]?.text.flatMap(UUID.init(uuidString:)) { placementFields[id] = fields }
            }
        }
        committedData = commit.data
        searchIndex = nil
        snapshot = commit.snapshot
    }

    private func reconcileAssets() {
        // Damaged snapshots may reference assets we cannot parse. Retain those
        // bytes for manual repair; quota still bounds new preview writes.
        guard let entries = try? FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil),
              !entries.contains(where: { $0.lastPathComponent.hasPrefix("workspace.damaged-") }) else { return }
        var previous: WorkspaceSnapshot?
        if WorkspaceFiles.exists(previousFile) {
            guard let backup = try? WorkspaceCommit.read(previousFile, space: snapshot.spaceID) else { return }
            previous = backup.snapshot
        }
        guard !(undoHistory + redoHistory).contains(where: \.unresolved) else { return }
        WorkspaceAssets.reconcile(in: file.deletingLastPathComponent().appendingPathComponent("assets"), current: snapshot, previous: previous, history: Set((undoHistory + redoHistory).flatMap { $0.assets }))
    }

    /// Explicit recovery only. Keep the damaged file and never downgrade newer data.
    @discardableResult
    func recoverPrevious() -> Bool {
        guard !writable, recovery != nil, let expected = recoveryData else { return false }
        do {
            let backup = try WorkspaceCommit.read(previousFile, space: snapshot.spaceID)
            guard backup.data == expected else { throw WorkspaceError.externalChange }
            try WorkspaceFiles.checkPath(file)
            if WorkspaceFiles.exists(file) {
                do {
                    _ = try WorkspaceCommit.read(file, space: snapshot.spaceID)
                    throw WorkspaceError.externalChange
                } catch let error as WorkspaceError {
                    guard error == .invalid else { throw error }
                }
                let archive = file.deletingLastPathComponent().appendingPathComponent("workspace.damaged-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: file, to: archive)
            }
            try write(backup.data, file)
            publish(backup)
            writable = true
            preservesUnresolvedBindings = false
            recovery = nil
            recoveryData = nil
            problem = nil
            reconcileAssets()
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func mutate(_ change: (inout WorkspaceSnapshot) throws -> Void) -> Bool {
        guard writable else { return false }
        do {
            var next = snapshot
            try change(&next)
            let before = entry(try committedData ?? JSONEncoder().encode(snapshot), snapshot)
            try commit(next, preserving: original)
            undoHistory.append(before); redoHistory = []; trimHistory()
            reconcileAssets()
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// Restore or mutate against an explicit envelope; never merge a restored
    /// revision with the current revision's unknown fields.
    private func commit(_ candidate: WorkspaceSnapshot, preserving base: [String: ObjectValue]) throws {
        var next = candidate
        guard next.spaceID == snapshot.spaceID, next.schemaVersion == snapshot.schemaVersion,
              snapshot.revision < Int.max else { throw WorkspaceError.invalid }
        next.revision = snapshot.revision + 1
        try next.validate()
        var oldPlacements: [UUID: [String: ObjectValue]] = [:]
        if case .dictionary(let wall) = base["wall"], case .array(let list) = wall["placements"] {
            for value in list {
                if case .dictionary(let fields) = value, let id = fields["id"]?.text.flatMap(UUID.init(uuidString:)) { oldPlacements[id] = fields }
            }
        }
        var fields = try JSONDecoder().decode([String: ObjectValue].self, from: JSONEncoder().encode(next))
        if case .dictionary(var wall) = fields["wall"], case .array(let list) = wall["placements"] {
            wall["placements"] = .array(list.map { value in
                guard case .dictionary(let current) = value, let id = current["id"]?.text.flatMap(UUID.init(uuidString:)) else { return value }
                var old = oldPlacements[id] ?? [:]
                old.removeValue(forKey: "color") // nil must clear a previously saved colour.
                return .dictionary(old.merging(current) { _, new in new })
            })
            if case .dictionary(let old) = base["wall"] { wall = old.merging(wall) { _, new in new } }
            fields["wall"] = .dictionary(wall)
        }
        let data = try JSONEncoder().encode(base.merging(fields) { _, new in new })
        guard data.count <= Self.byteLimit else { throw WorkspaceError.tooLarge }
        try WorkspaceFiles.checkPath(file)
        if let committedData {
            guard try WorkspaceCommit.read(file, space: snapshot.spaceID).data == committedData else { throw WorkspaceError.externalChange }
            try write(committedData, previousFile)
        } else if WorkspaceFiles.exists(file) || WorkspaceFiles.exists(previousFile) { throw WorkspaceError.externalChange }
        try write(data, file)
        publish(try WorkspaceCommit(data: data, space: snapshot.spaceID)); problem = nil
    }

    @discardableResult
    func add(_ object: LocusObject, at point: CGPoint? = nil) -> Bool {
        mutate { next in
            next.objects.append(object)
            let n = next.placements.count
            next.placements.append(WallPlacement(objectID: object.id,
                x: point.map { Double($0.x) } ?? Double(n % 3) * 290 + 40, y: point.map { Double($0.y) } ?? Double(n / 3) * 210 + 40))
        }
    }

    func suggestions(for query: String) -> [Suggestion] {
        if searchRevision != snapshot.revision || searchIndex == nil {
            searchIndex = WorkspaceObjectSearch.Index(snapshot: snapshot)
            searchRevision = snapshot.revision
        }
        return searchIndex?.results(query: query) ?? []
    }
    func assetURL(_ id: UUID) -> URL {
        file.deletingLastPathComponent().appendingPathComponent("assets/\(id.uuidString).png")
    }

    @discardableResult
    func addCapture(_ object: LocusObject, png: Data?, sourcePage: LocusObject? = nil, derivedFrom: UUID? = nil) -> Bool {
        guard object.supported, object.type == "uiCapture" else { return false }
        return addVisualObject(object, png: png, sourcePage: sourcePage, sourceKind: "capturedFrom", derivedFrom: derivedFrom)
    }

    @discardableResult
    func addInspiration(_ object: LocusObject, png: Data?, sourcePage: LocusObject? = nil, at point: CGPoint? = nil) -> Bool {
        guard object.supported, object.type == "inspiration", object.url.flatMap(SavedPageAddress.clean) == object.url,
              object.url != nil else { return false }
        return addVisualObject(object, png: png, sourcePage: sourcePage, sourceKind: "collectedFrom", at: point)
    }

    @discardableResult
    func addAIOutput(_ object: LocusObject, sourcePage: LocusObject) -> Bool {
        guard object.supported, object.type == "aiOutput", !object.text.isEmpty else { return false }
        return addVisualObject(object, png: nil, sourcePage: sourcePage, sourceKind: "generatedFrom")
    }

    private func addVisualObject(_ object: LocusObject, png: Data?, sourcePage: LocusObject?, sourceKind: String, derivedFrom: UUID? = nil, at point: CGPoint? = nil) -> Bool {
        guard writable else { return false }
        var captured = object
        var asset: URL?
        do {
            if let sourcePage {
                guard sourcePage.supported, sourcePage.type == "page", let url = sourcePage.url,
                      SavedPageAddress.clean(url) == url,
                      snapshot.objects.first(where: { $0.id == sourcePage.id }).map({ $0 == sourcePage }) ?? true
                else { throw WorkspaceError.unavailable }
            }
            if let derivedFrom {
                guard let sourcePage, let previous = snapshot.objects.first(where: { $0.id == derivedFrom }),
                      previous.supported, previous.type == "uiCapture",
                      previous.relationshipTarget("capturedFrom") == sourcePage.id,
                      snapshot.objects.contains(where: { $0.id == sourcePage.id && $0.supported && $0.type == "page" }) else { throw WorkspaceError.unavailable }
            }
            if let png {
                guard WorkspaceImage.validPNG(png) else { throw WorkspaceError.invalid }
                let id = UUID(), url = assetURL(id)
                try WorkspaceAssets.permit(png.count, in: url.deletingLastPathComponent())
                try WorkspaceFiles.write(png, to: url)
                asset = url
                captured.attachSnapshot(id, bytes: png.count, sha256: WorkspaceImage.digest(png))
                guard captured.snapshotID == id else { throw WorkspaceError.invalid }
            }
            if let sourcePage { captured.appendRelationship(kind: sourceKind, target: sourcePage.id) }
            if let derivedFrom { captured.linkDerivedCapture(derivedFrom) }
            let saved = mutate { next in
                if let sourcePage, !next.objects.contains(where: { $0.id == sourcePage.id }) { next.objects.append(sourcePage) }
                next.objects.append(captured)
                let n = next.placements.count
                next.placements.append(WallPlacement(objectID: captured.id,
                    x: point.map { Double($0.x) } ?? Double(n % 3) * 290 + 40, y: point.map { Double($0.y) } ?? Double(n / 3) * 210 + 40))
            }
            if !saved, let asset { try? FileManager.default.removeItem(at: asset) }
            return saved
        } catch {
            if let asset { try? FileManager.default.removeItem(at: asset) }
            problem = error.localizedDescription
            return false
        }
    }

    func move(_ id: UUID, x: Double, y: Double) {
        mutate { next in
            guard let i = next.placements.firstIndex(where: { $0.id == id }) else { throw WorkspaceError.invalid }
            next.placements[i].x = x
            next.placements[i].y = y
        }
    }
    func resize(_ id: UUID, width: Double, height: Double) {
        mutate { next in
            guard let i = next.placements.firstIndex(where: { $0.id == id }) else { throw WorkspaceError.invalid }
            next.placements[i].width = width
            next.placements[i].height = height
        }
    }

    @discardableResult
    func connect(_ source: UUID, to target: UUID, kind: String, label: String = "") -> Bool {
        guard ObjectRelationship.editable.contains(kind) else { return false }
        // Repeating a save is harmless and must not generate another revision.
        if snapshot.objects.first(where: { $0.id == source })?.relationships.contains(where: { $0.kind == kind && $0.target == target }) == true { return false }
        return mutate { next in
            guard source != target, let i = next.objects.firstIndex(where: { $0.id == source && $0.supported }),
                  next.objects.contains(where: { $0.id == target && $0.supported }) else { throw WorkspaceError.unavailable }
            next.objects[i].appendRelationship(kind: kind, target: target, label: label)
        }
    }

    @discardableResult
    func disconnect(_ source: UUID, from target: UUID, kind: String) -> Bool {
        guard ObjectRelationship.editable.contains(kind) else { return false }
        return mutate { next in
            guard let i = next.objects.firstIndex(where: { $0.id == source && $0.supported }),
                  next.objects[i].relationships.contains(where: { $0.kind == kind && $0.target == target })
            else { throw WorkspaceError.unavailable }
            next.objects[i].removeRelationship(kind: kind, target: target)
        }
    }

    func removePlacement(_ id: UUID) {
        mutate { $0.wall.removePlacement(id) }
    }
    func deleteObject(_ id: UUID) {
        mutate { next in
            for placement in next.placements where placement.objectID == id {
                next.wall.removePlacement(placement.id)
            }
            next.objects.removeAll { $0.id == id }
            for i in next.objects.indices { next.objects[i].removeRelationships(to: id) }
        }
    }
    /// A deleted Space cannot be recreated by a held editor or queued callback.
    func erase() {
        CanvasVault.retire(workspace: file)
        objectWillChange.send()
        writable = false
        undoHistory = []; redoHistory = []
        preservesUnresolvedBindings = false
        recovery = nil
        recoveryData = nil
        do {
            let folder = file.deletingLastPathComponent()
            try WorkspaceFiles.checkPath(folder)
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
        } catch { problem = error.localizedDescription }
    }
    func place(_ id: UUID) {
        mutate { next in
            guard next.objects.contains(where: { $0.id == id }) else { throw WorkspaceError.invalid }
            let n = next.placements.count
            next.placements.append(WallPlacement(objectID: id,
                x: Double(n % 3) * 290 + 40, y: Double(n / 3) * 210 + 40))
        }
    }
    func editNote(_ id: UUID, title: String, text: String) -> Bool {
        mutate { next in
            guard let i = next.objects.firstIndex(where: { $0.id == id }),
                  next.objects[i].supported, next.objects[i].type == "note" else { throw WorkspaceError.unavailable }
            next.objects[i].editNote(title: String(title.prefix(300)), text: text)
        }
    }

    func editInspiration(_ expected: LocusObject, title: String, text: String) -> Bool {
        mutate { next in
            guard let i = next.objects.firstIndex(where: { $0.id == expected.id }),
                  next.objects[i] == expected, expected.supported, expected.type == "inspiration" else { throw WorkspaceError.unavailable }
            next.objects[i].editNote(title: String(title.prefix(300)), text: String(text.prefix(16_000)))
        }
    }

    func updatePage(_ expected: LocusObject, title: String, url: URL) -> Bool {
        guard let url = SavedPageAddress.clean(url) else { return false }
        return mutate { next in
            guard let i = next.objects.firstIndex(where: { $0.id == expected.id }),
                  next.objects[i] == expected, expected.supported, expected.type == "page" else { throw WorkspaceError.unavailable }
            next.objects[i].updatePage(title: title, url: url)
        }
    }
}
