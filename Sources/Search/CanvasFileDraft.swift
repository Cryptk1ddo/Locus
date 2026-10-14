import Foundation

enum CanvasFileEditError: LocalizedError {
    case unsupported, conflict, draftConflict, invalidDraft, tooLarge
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Only granted UTF-8 Markdown and text files up to 1 MB can be edited here."
        case .conflict: return "The file changed outside Locus. Your draft is kept. Save a copy to keep both versions."
        case .draftConflict: return "Another editor changed this draft. Your current text is still open; save a copy before closing."
        case .invalidDraft: return "The saved draft could not be read or belongs to a different file. It has been left untouched."
        case .tooLarge: return "The file or draft exceeds the editing limit. Save a copy before closing."
        }
    }
}

/// Draft authority is the object's explicit bookmark, never an imported Canvas path.
final class CanvasFileDraft {
    @MainActor private static var live: [String: CanvasFileDraft] = [:]
    @MainActor static func open(object: LocusObject, workspace: URL, original: Data?) throws -> CanvasFileDraft {
        guard object.supported, object.type == "file", object.content["bookmark"]?.text != nil else { throw CanvasFileEditError.unsupported }
        let key = workspace.path + "/" + object.id.uuidString
        if let draft = live[key] {
            guard draft.record.bookmark == object.content["bookmark"]?.text else { throw CanvasFileEditError.invalidDraft }
            live[key] = nil
            return draft
        }
        live = live.filter { $0.value.changed }
        guard live.count < 16 else { throw CanvasFileEditError.tooLarge }
        return try CanvasFileDraft(object: object, workspace: workspace, original: original)
    }
    @MainActor func retainForReopening(workspace: URL) {
        let key = workspace.path + "/" + record.object.uuidString
        if needsMemoryRecovery { Self.live[key] = self }
    }
    struct Record: Codable {
        var version = 1
        let object: UUID
        let bookmark: String
        var original: Data
        var text: String
    }
    let file: URL
    private(set) var record: Record
    private var expected: Data?
    private var needsMemoryRecovery = false
    static let textLimit = 1_000_000
    static let draftLimit = 3_000_000
    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        if a.resolvingSymlinksInPath().standardizedFileURL == b.resolvingSymlinksInPath().standardizedFileURL { return true }
        guard let left = try? FileManager.default.attributesOfItem(atPath: a.path), let right = try? FileManager.default.attributesOfItem(atPath: b.path) else { return false }
        return left[.systemNumber] as? NSNumber == right[.systemNumber] as? NSNumber && left[.systemFileNumber] as? NSNumber == right[.systemFileNumber] as? NSNumber
    }

    init(object: LocusObject, workspace: URL, original: Data?) throws {
        guard object.supported, object.type == "file", let bookmark = object.content["bookmark"]?.text else { throw CanvasFileEditError.unsupported }
        file = workspace.deletingLastPathComponent().appendingPathComponent("drafts/\(object.id.uuidString).json")
        try WorkspaceFiles.checkPath(file)
        if WorkspaceFiles.exists(file) {
            let data = try Self.read(file, limit: Self.draftLimit)
            guard let loaded = try? JSONDecoder().decode(Record.self, from: data), loaded.version == 1, loaded.object == object.id, loaded.bookmark == bookmark,
                  loaded.original.count <= Self.textLimit, loaded.text.utf8.count <= Self.textLimit, Self.decode(loaded.original) != nil else { throw CanvasFileEditError.invalidDraft }
            record = loaded; expected = data
        } else {
            guard let original, original.count <= Self.textLimit, let text = Self.decode(original) else { throw CanvasFileEditError.unsupported }
            record = Record(object: object.id, bookmark: bookmark, original: original, text: text)
        }
    }
    static func read(_ url: URL, limit: Int = textLimit) throws -> Data {
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, let size = info.fileSize, size <= limit else { throw CanvasFileEditError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CanvasFileEditError.tooLarge }; return data
    }
    static func decode(_ data: Data) -> String? {
        let bytes = data.starts(with: [0xef, 0xbb, 0xbf]) ? data.dropFirst(3) : data[...]
        guard let text = String(data: bytes, encoding: .utf8) else { return nil }
        // Preserve a uniform CRLF file while providing native editor line endings.
        if text.contains("\r\n"), !text.replacingOccurrences(of: "\r\n", with: "").contains("\n") { return text.replacingOccurrences(of: "\r\n", with: "\n") }
        return text
    }
    var changed: Bool { record.text != Self.decode(record.original) }
    var hasStoredDraft: Bool { expected != nil }
    func pause(_ text: String) throws {
        if text != record.text || changed { try persist(text) }
        // Undo may bring the live text back to the baseline before its last
        // draft notification. Recheck after persisting, rather than before.
        if !changed, hasStoredDraft { try discard() }
    }
    func encodedText(_ text: String) throws -> Data {
        guard text.utf8.count <= Self.textLimit else { throw CanvasFileEditError.tooLarge }
        let original = String(data: record.original, encoding: .utf8) ?? ""
        let crlf = original.contains("\r\n") && !original.replacingOccurrences(of: "\r\n", with: "").contains("\n")
        let value = crlf ? text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n") : text
        var bytes = Data(value.utf8)
        if record.original.starts(with: [0xef, 0xbb, 0xbf]) { bytes.insert(contentsOf: [0xef, 0xbb, 0xbf], at: 0) }
        guard bytes.count <= Self.textLimit else { throw CanvasFileEditError.tooLarge }; return bytes
    }
    func persist(_ text: String) throws {
        guard text.utf8.count <= Self.textLimit else { throw CanvasFileEditError.tooLarge }
        // Also retain a bounded live draft if storage becomes unavailable.
        record.text = text; needsMemoryRecovery = true
        let next = record
        let data = try JSONEncoder().encode(next)
        guard data.count <= Self.draftLimit else { throw CanvasFileEditError.tooLarge }
        try WorkspaceFiles.checkPath(file)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinated(file) { url in
            try self.checkExpected(url)
            let entries = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: [.fileSizeKey])
            let total = try entries.filter { $0 != url }.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Self.draftLimit) }
            guard total + data.count <= 16_000_000 else { throw CanvasFileEditError.tooLarge }
            try WorkspaceFiles.write(data, to: url)
        }
        record = next; expected = data; needsMemoryRecovery = false
    }
    private func checkExpected(_ url: URL) throws {
        try WorkspaceFiles.checkPath(url)
        let current = WorkspaceFiles.exists(url) ? try Self.read(url, limit: Self.draftLimit) : nil
        guard current == expected else { throw CanvasFileEditError.draftConflict }
    }
    func discard() throws {
        try coordinated(file) { url in
            try self.checkExpected(url)
            if WorkspaceFiles.exists(url) { try FileManager.default.removeItem(at: url) }
        }
        expected = nil
        record.text = Self.decode(record.original) ?? ""
        needsMemoryRecovery = false
    }
    func save(to url: URL, text: String) throws {
        // Persist first, so even failed replacement has a restart-recoverable draft.
        try persist(text)
        let bytes = try encodedText(text)
        try coordinated(url) { target in
            guard try Self.read(target) == self.record.original else { throw CanvasFileEditError.conflict }
            try bytes.write(to: target, options: .atomic)
        }
        // Keep a valid clean baseline even if sidecar cleanup fails.
        record.original = bytes
        try persist(text)
        try discard()
    }
    private func coordinated(_ url: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?, operationError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try body(target) } catch { operationError = error }
        }
        if let operationError { throw operationError }; if let coordinationError { throw coordinationError }
    }
}
