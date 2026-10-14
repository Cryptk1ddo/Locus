import AppKit
import Combine

/// One explicit folder grant per Space. Configuration is independent of Canvas undo.
@MainActor final class CanvasVault: ObservableObject {
    private static var vaults: [String: CanvasVault] = [:]
    static func shared(workspace: URL) -> CanvasVault {
        let key = workspace.standardizedFileURL.path
        if let vault = vaults[key] { return vault }
        let vault = CanvasVault(workspace: workspace); vaults[key] = vault; return vault
    }
    static func retire(workspace: URL) {
        guard let vault = vaults.removeValue(forKey: workspace.standardizedFileURL.path) else { return }
        vault.monitorClients.removeAll(); vault.stopMonitoring(); vault.fields = [:]; vault.entries = []; vault.stamp = [:]; vault.editable = false; vault.revision += 1
    }
    let file: URL
    @Published private(set) var revision = 0
    @Published private(set) var problem: String?
    private var fields: [String: ObjectValue] = [:]
    private var expected: Data?
    private var editable = true
    private(set) var entries: [String] = []
    private var monitorClients: Set<UUID> = []
    private var watcher: VaultWatcher?
    private var monitorURL: URL?
    private var monitorAccess = false
    private var pendingRefresh: DispatchWorkItem?
    private var scanTicket: VaultScanTicket?
    private var scanAgain = false
    private var changedHint = false
    private var fallback: Timer?
    private var asyncScans = 0
    var monitoringDiagnostics: [String: Any] { ["clients": monitorClients.count, "watching": watcher != nil, "scanning": scanTicket != nil, "asyncScans": asyncScans, "fallback": fallback != nil] }
    private var stamp: [String: String] = [:]
    var connected: Bool { fields["bookmark"]?.text != nil }
    var title: String { fields["title"]?.text ?? "Vault" }
    var autosave: Bool { connected && fields["autosave"] == .bool(true) }
    init(workspace: URL) {
        file = workspace.deletingLastPathComponent().appendingPathComponent("vault.json")
        do {
            try WorkspaceFiles.checkPath(file)
            if WorkspaceFiles.exists(file) {
                let data = try CanvasFileDraft.read(file, limit: 16_384)
                let fields = try JSONDecoder().decode([String: ObjectValue].self, from: data)
                guard fields["version"] == .number(1), fields["bookmark"]?.text != nil, fields["autosave"] == .bool(true) || fields["autosave"] == .bool(false) else { throw WorkspaceError.futureVersion }
                self.fields = fields; expected = data
            }
        } catch { editable = false; problem = error.localizedDescription }
    }
    @discardableResult func connect(_ url: URL) -> Bool {
        do {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw WorkspaceError.invalid }
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            var next = fields; next["version"] = .number(1); next["bookmark"] = .string(bookmark.base64EncodedString()); next["title"] = .string(String(url.lastPathComponent.prefix(300))); next["autosave"] = .bool(true); try commit(next)
            stopMonitoring(); entries = []; stamp = [:]
            if monitorClients.isEmpty { refresh() } else { startMonitoring() }; return true
        } catch { problem = error.localizedDescription; return false }
    }
    func choose(window: NSWindow?) {
        guard let window else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "Connect this Space to a vault. Notes edited here will save automatically; external changes keep a recovery draft."
        panel.beginSheetModal(for: window) { result in if result == .OK, let url = panel.url { _ = self.connect(url) } }
    }
    func setAutosave(_ value: Bool) {
        guard connected else { return }
        do { var next = fields; next["autosave"] = .bool(value); try commit(next) }
        catch { problem = error.localizedDescription }
    }
    func disconnect() {
        do { try commit(nil); stopMonitoring(); entries = []; stamp = [:] }
        catch { problem = error.localizedDescription }
    }
    private func commit(_ next: [String: ObjectValue]?) throws {
        guard editable else { throw WorkspaceError.unavailable }
        try WorkspaceFiles.checkPath(file)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordination: NSError?, failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordination) { url in
            do {
                let current = WorkspaceFiles.exists(url) ? try CanvasFileDraft.read(url, limit: 16_384) : nil
                guard current == self.expected else { throw WorkspaceError.externalChange }
                if let next {
                    let data = try JSONEncoder().encode(next); guard data.count <= 16_384 else { throw WorkspaceError.tooLarge }
                    try WorkspaceFiles.write(data, to: url); self.expected = data
                } else { if current != nil { try FileManager.default.removeItem(at: url) }; self.expected = nil }
            } catch { failure = error }
        }
        if let failure { throw failure }; if let coordination { throw coordination }
        fields = next ?? [:]; problem = nil; revision += 1
    }
    func withRoot<T>(_ body: (URL) throws -> T?) rethrows -> T? {
        guard let encoded = fields["bookmark"]?.text, let data = Data(base64Encoded: encoded) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try body(url.standardizedFileURL.resolvingSymlinksInPath())
    }
    static func safeURL(_ relative: String, root: URL) -> URL? {
        guard !relative.isEmpty, relative.count <= 2000, !relative.hasPrefix("/"), !relative.contains(":"),
              !relative.components(separatedBy: "/").contains(where: { $0 == ".." || $0.isEmpty }) else { return nil }
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let raw = root.appendingPathComponent(relative)
        guard (try? WorkspaceFiles.checkPath(raw)) != nil else { return nil }
        let url = raw.standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else { return nil }; return url
    }
    func contains(_ url: URL) -> Bool {
        withRoot { root in
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            guard canonical.path.hasPrefix(root.path + "/"), (try? WorkspaceFiles.checkPath(url)) != nil else { return false }
            return true
        } ?? false
    }
    func canAutosave(_ object: LocusObject) -> Bool {
        autosave && CanvasFiles.editable(object) && (CanvasFiles.withURL(object) { contains($0) } ?? false)
    }
    func acquireMonitor(_ client: UUID) { monitorClients.insert(client); startMonitoring() }
    func releaseMonitor(_ client: UUID) { monitorClients.remove(client); if monitorClients.isEmpty { stopMonitoring() } }
    private func startMonitoring() {
        guard !monitorClients.isEmpty, connected, monitorURL == nil,
              let encoded = fields["bookmark"]?.text, let data = Data(base64Encoded: encoded) else { return }
        var stale = false
        guard let root = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        let access = root.startAccessingSecurityScopedResource()
        guard (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { if access { root.stopAccessingSecurityScopedResource() }; return }
        monitorURL = root; monitorAccess = access
        watcher = VaultWatcher(root: root) { [weak self] in Task { @MainActor in self?.scheduleRefresh(changed: true) } }
        if watcher == nil {
            let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.scheduleRefresh(changed: true) } }
            timer.tolerance = 5; RunLoop.main.add(timer, forMode: .common); fallback = timer
        }
        scheduleRefresh()
    }
    private func stopMonitoring() {
        pendingRefresh?.cancel(); pendingRefresh = nil; scanTicket?.cancel(); scanTicket = nil; scanAgain = false; changedHint = false
        watcher?.stop(); watcher = nil; fallback?.invalidate(); fallback = nil
        if monitorAccess { monitorURL?.stopAccessingSecurityScopedResource() }; monitorURL = nil; monitorAccess = false
    }
    private func scheduleRefresh(changed: Bool = false) {
        guard !monitorClients.isEmpty, monitorURL != nil else { return }
        changedHint = changedHint || changed
        if scanTicket != nil { scanAgain = true; return }
        guard pendingRefresh == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.beginScan() }
        pendingRefresh = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    private func beginScan() {
        pendingRefresh = nil
        guard !monitorClients.isEmpty, let root = monitorURL else { return }
        let ticket = VaultScanTicket(); scanTicket = ticket
        let force = changedHint; changedHint = false
        if Store.testing { asyncScans += 1 }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let access = root.startAccessingSecurityScopedResource()
            let next = Self.scan(root, ticket: ticket)
            if access { root.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                guard let self, self.scanTicket === ticket else { return }
                self.scanTicket = nil; self.publishScan(next, force: force)
                if self.scanAgain { self.scanAgain = false; self.scheduleRefresh() }
            }
        }
    }
    nonisolated static func scan(_ root: URL, ticket: VaultScanTicket? = nil) -> [String: String]? {
        guard ticket?.isCancelled != true, (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              let scan = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var found: [String: String] = [:], visits = 0
        for case let url as URL in scan {
            if ticket?.isCancelled == true { return nil }
            visits += 1; if visits > 10_000 || found.count >= 2000 { break }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]) else { continue }
            if values.isSymbolicLink == true { scan.skipDescendants(); continue }
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            guard values.isRegularFile == true, canonical.path.hasPrefix(root.path + "/") else { continue }
            let path = String(canonical.path.dropFirst(root.path.count + 1))
            found[path] = "\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        return found
    }
    private func publishScan(_ next: [String: String]?, force: Bool = false) {
        guard let next else { if problem == nil { problem = "The vault folder is unavailable. Reconnect it in Canvas settings." }; return }
        if problem == "The vault folder is unavailable. Reconnect it in Canvas settings." { problem = nil }
        if next != stamp || force { stamp = next; entries = next.keys.sorted(); revision += 1 }
    }
    func refresh() {
        guard connected else { return }
        // Explicit callers need a fresh answer; automatic monitoring never scans on main.
        scanTicket?.cancel(); scanTicket = nil; pendingRefresh?.cancel(); pendingRefresh = nil; scanAgain = false
        publishScan(withRoot { Self.scan($0) })
    }
    func relativePath(_ object: LocusObject) -> String? {
        CanvasFiles.withURL(object) { url in self.withRoot { root in
            guard self.contains(url) else { return nil }
            return String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
        } }
    }
    func resolve(_ reference: String, source: LocusObject? = nil) -> URL? {
        guard !reference.isEmpty, reference.count <= 1000, !reference.hasPrefix("/"), !reference.contains(":"), !reference.components(separatedBy: "/").contains("..") else { return nil }
        return withRoot { root in
            var candidates = [reference]
            if (reference as NSString).pathExtension.isEmpty { candidates += [reference + ".md", reference + ".markdown"] }
            if let source, let path = self.relativePath(source) {
                let parent = (path as NSString).deletingLastPathComponent
                if !parent.isEmpty { candidates = candidates.map { parent + "/" + $0 } + candidates }
            }
            for path in candidates {
                if let url = Self.safeURL(path, root: root), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return url }
            }
            let names = Set(candidates.map { ($0 as NSString).lastPathComponent.lowercased() })
            let matches = self.entries.filter { names.contains(($0 as NSString).lastPathComponent.lowercased()) }
            guard matches.count == 1 else { return nil }; return Self.safeURL(matches[0], root: root)
        }
    }
    func object(_ reference: String, source: LocusObject? = nil) -> LocusObject? {
        withRoot { _ in
            guard let url = resolve(reference, source: source), let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
            return LocusObject(type: "file", title: url.lastPathComponent, content: ["file": .string(url.path), "bookmark": .string(bookmark.base64EncodedString())])
        }
    }
    func chooseNote(store: WorkspaceStore, at point: CGPoint, window: NSWindow?) {
        guard store.writable, let window else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.directoryURL = withRoot { $0 }; panel.message = "Add notes or media from this vault"
        panel.beginSheetModal(for: window) { response in
            if response == .OK { _ = CanvasFiles.add(panel.urls.filter { self.contains($0) }, to: store, at: point) }
        }
    }
    func bindImportedFiles(store: WorkspaceStore) {
        guard store.writable else { return }
        var updates: [UUID: String] = [:]
        _ = withRoot { root in
            for object in store.snapshot.objects where object.supported && object.type == "file" && object.content["bookmark"] == nil {
                guard let path = object.content["file"]?.text, let url = Self.safeURL(path, root: root), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { continue }
                updates[object.id] = data.base64EncodedString()
            }
            return true
        }
        guard !updates.isEmpty else { return }
        _ = store.mutate { next in for i in next.objects.indices {
            let object = next.objects[i]; guard let bookmark = updates[object.id] else { continue }
            var fields = object.fields, content = object.content; content["bookmark"] = .string(bookmark); fields["content"] = .dictionary(content)
            next.objects[i] = try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))
        } }
    }
}
