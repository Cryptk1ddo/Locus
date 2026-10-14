import AppKit

/// The selected folder is the authority boundary; its JSON/manifest are data.
@MainActor enum CanvasImport {
    enum Failure: LocalizedError {
        case tooLarge
        var errorDescription: String? { "This portable import exceeds the file count or size limit. Import a smaller Canvas." }
    }
    struct Result { let selected: Set<UUID>; let unresolved: Int; let granted: Int; let previews: Int }
    static func portable(_ folder: URL, into store: WorkspaceStore, at point: CGPoint? = nil) throws -> Result {
        guard store.writable else { throw WorkspaceError.unavailable }
        try WorkspaceFiles.checkPath(folder)
        guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw WorkspaceError.invalid }
        let access = folder.startAccessingSecurityScopedResource(); defer { if access { folder.stopAccessingSecurityScopedResource() } }
        guard let canvas = CanvasVault.safeURL("Wall.canvas", root: folder) else { throw WorkspaceError.unsafePath }
        let data = try CanvasFileDraft.read(canvas, limit: CanvasJSON.limit)
        let fields = try JSONDecoder().decode([String: ObjectValue].self, from: data)
        guard case .array(let nodes) = fields["nodes"], nodes.count <= 2000 else { throw WorkspaceError.invalid }
        var references: Set<String> = []
        for node in nodes {
            guard case .dictionary(let fields) = node else { throw WorkspaceError.invalid }
            let key = fields["type"] == .string("file") ? "file" : fields["type"] == .string("group") ? "background" : ""
            if let path = fields[key]?.text { references.insert(path) }
        }
        var grants: [String: Data] = [:], unresolved = 0, total = 0
        var counted: Set<String> = []
        for reference in references.sorted() {
            guard let url = CanvasVault.safeURL(reference, root: folder),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { unresolved += 1; continue }
            guard let size = values.fileSize, size <= CanvasExport.assetLimit, size <= CanvasExport.totalLimit - total, grants.count < CanvasExport.countLimit else { throw Failure.tooLarge }
            grants[reference] = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            total += size; counted.insert(url.path)
        }
        var previews: [String: CanvasJSON.SavedPreview] = [:], copied: [String: CanvasJSON.SavedPreview] = [:], staged: [URL] = []
        var committed = false
        defer { if !committed { staged.forEach { try? FileManager.default.removeItem(at: $0) } } }
        let manifest = folder.appendingPathComponent("manifest.json")
        if WorkspaceFiles.exists(manifest) {
            let payload: [String: ObjectValue]? = (try? WorkspaceFiles.checkPath(manifest)) != nil ?
                (try? JSONDecoder().decode([String: ObjectValue].self, from: CanvasFileDraft.read(manifest, limit: 256_000))) : nil
            if let payload, payload["version"] == .number(1), case .array(let entries) = payload["previews"] {
                guard entries.count <= CanvasExport.countLimit else { throw Failure.tooLarge }
                let linkIDs = Set(nodes.compactMap { node -> String? in
                    guard case .dictionary(let value) = node, value["type"] == .string("link") else { return nil }; return value["id"]?.text
                })
                var grouped: [String: [[String: ObjectValue]]] = [:]
                for entry in entries {
                    guard case .dictionary(let value) = entry, let id = value["node"]?.text else { unresolved += 1; continue }
                    // Capture file nodes already use their directly granted PNG.
                    if linkIDs.contains(id) { grouped[id, default: []].append(value) }
                }
                for id in grouped.keys.sorted() {
                    guard let rows = grouped[id], rows.count == 1, let row = rows.first, let reference = row["file"]?.text,
                          let url = CanvasVault.safeURL(reference, root: folder),
                          let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true,
                          let size = values.fileSize, size <= 4_000_000 else { unresolved += 1; continue }
                    let title = row["title"]?.text.map { String($0.prefix(300)) }
                    if let saved = copied[url.path] {
                        previews[id] = .init(id: saved.id, bytes: saved.bytes, sha256: saved.sha256, title: title); continue
                    }
                    if !counted.contains(url.path) {
                        guard counted.count < CanvasExport.countLimit, size <= CanvasExport.totalLimit - total else { throw Failure.tooLarge }
                    }
                    guard let png = try? CanvasFileDraft.read(url, limit: 4_000_000), WorkspaceImage.validPNG(png) else { unresolved += 1; continue }
                    if counted.insert(url.path).inserted { total += png.count }
                    let assetID = UUID(), destination = store.assetURL(assetID)
                    try WorkspaceAssets.permit(png.count, in: destination.deletingLastPathComponent())
                    guard !WorkspaceFiles.exists(destination) else { throw WorkspaceError.invalid }
                    staged.append(destination); try WorkspaceFiles.write(png, to: destination)
                    let saved = CanvasJSON.SavedPreview(id: assetID, bytes: png.count, sha256: WorkspaceImage.digest(png), title: title)
                    copied[url.path] = saved; previews[id] = saved
                }
            } else { unresolved += 1 }
        }
        let selected = try CanvasJSON.importData(data, into: store, at: point, grants: grants, previews: previews)
        committed = true
        return Result(selected: selected, unresolved: unresolved, granted: grants.count, previews: previews.count)
    }
}
