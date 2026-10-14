import Foundation

/// Bounded sidecar reads. Opaque JSON survives commit and explicit recovery.
struct WorkspaceCommit {
    let data: Data
    let fields: [String: ObjectValue]
    let snapshot: WorkspaceSnapshot

    init(data: Data, space: UUID) throws {
        guard data.count <= WorkspaceStore.byteLimit else { throw WorkspaceError.tooLarge }
        do { fields = try JSONDecoder().decode([String: ObjectValue].self, from: data) }
        catch { throw WorkspaceError.invalid }
        guard let version = fields["schemaVersion"] else { throw WorkspaceError.invalid }
        guard version == .number(1) else { throw WorkspaceError.futureVersion }
        do { snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data) }
        catch { throw WorkspaceError.invalid }
        guard snapshot.spaceID == space else { throw WorkspaceError.wrongSpace }
        try snapshot.validate()
        self.data = data
    }

    static func read(_ file: URL, space: UUID) throws -> WorkspaceCommit {
        try WorkspaceFiles.checkPath(file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw WorkspaceError.unsafePath }
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= WorkspaceStore.byteLimit else { throw WorkspaceError.tooLarge }
        return try WorkspaceCommit(data: Data(contentsOf: file), space: space)
    }
}

struct WorkspaceRecovery: Equatable {
    let revision: Int
    let objectCount: Int
}

enum WorkspaceFiles {
    /// Check existing path components without resolving user-controlled links.
    /// macOS's system /var and /tmp aliases are outside workspace ownership.
    static func checkPath(_ url: URL) throws {
        var path = ""
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            path += "/" + component
            guard !["/var", "/tmp", "/etc"].contains(path) else { continue }
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else { throw WorkspaceError.unsafePath }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile { break }
        }
    }

    static func write(_ data: Data, to url: URL) throws {
        try checkPath(url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func exists(_ url: URL) -> Bool {
        // lstat-style attributes also see dangling symlinks, unlike fileExists.
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}

enum WorkspaceAssets {
    static let byteLimit = 256_000_000
    static let entryLimit = 4_000

    static func permit(_ bytes: Int, in directory: URL) throws {
        try WorkspaceFiles.checkPath(directory)
        guard WorkspaceFiles.exists(directory) else { return }
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard entries.count < entryLimit else { throw WorkspaceError.assetLimit }
        var total = bytes
        for url in entries {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if attributes[.type] as? FileAttributeType == .typeRegular {
                let size = (attributes[.size] as? NSNumber)?.intValue ?? Int.max
                guard size >= 0, size <= byteLimit - total else { throw WorkspaceError.assetLimit }
                total += size
            }
        }
        guard total <= byteLimit else { throw WorkspaceError.assetLimit }
    }

    /// A file/background card can explicitly reference an existing capture PNG.
    /// Retention is data-only: this does not read a path or grant file access.
    static func ownedPreviewIDs(_ snapshot: WorkspaceSnapshot, in directory: URL) -> Set<UUID> {
        var ids = Set(snapshot.objects.compactMap(\.snapshotID))
        for object in snapshot.objects where ["file", "group"].contains(object.type) {
            guard let path = object.content[object.type == "file" ? "file" : "background"]?.text else { continue }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if url.deletingLastPathComponent() == directory.standardizedFileURL, url.pathExtension == "png", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) { ids.insert(id) }
        }
        return ids
    }
    static func reconcile(in directory: URL, current: WorkspaceSnapshot, previous: WorkspaceSnapshot?, history: Set<UUID> = []) {
        let snapshots = [current] + (previous.map { [$0] } ?? [])
        // Future payloads may contain asset references we do not understand.
        guard snapshots.allSatisfy({ $0.objects.allSatisfy(\.supported) }),
              (try? WorkspaceFiles.checkPath(directory)) != nil,
              let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
              entries.count <= entryLimit else { return }
        let retained = Set(snapshots.flatMap { ownedPreviewIDs($0, in: directory) }).union(history)
        for url in entries {
            guard url.pathExtension == "png", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  !retained.contains(id),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
