import Foundation

/// Only syntax rendered as local references is traversed; code and remote URLs stay literal.
enum CanvasPortableReferences {
    struct Reference { let range: NSRange; let target: String }
    private static let wiki = try! NSRegularExpression(pattern: #"!?\[\[([^\]\n]+)\]\]"#)
    private static let markdown = try! NSRegularExpression(pattern: #"!?\[[^\]\n]*\]\(\s*(?:<([^>\n]+)>|((?:\\.|[^\s)\n])+))(?:\s+["'][^\n]*["'])?\s*\)"#)
    private static let definition = try! NSRegularExpression(pattern: #"^\s{0,3}\[[^\]\n]+\]:\s*(?:<([^>\n]+)>|([^\s\n]+))"#)

    static func references(_ source: String) -> [Reference] {
        var result: [Reference] = [], offset = 0, fence: (Character, Int)?
        for line in source.components(separatedBy: "\n") {
            defer { offset += line.utf16.count + 1 }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, first == "`" || first == "~" {
                let count = trimmed.prefix(while: { $0 == first }).count
                if count >= 3 {
                    if let opened = fence {
                        if first == opened.0, count >= opened.1, trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                    } else { fence = (first, count) }
                    continue
                }
            }
            guard fence == nil else { continue }
            guard !line.hasPrefix("    "), !line.hasPrefix("\t") else { continue }
            let text = line as NSString, literals = CanvasDocument.inlineCodeRanges(line)
            for (pattern, isWiki) in [(wiki, true), (markdown, false), (definition, false)] {
                for match in pattern.matches(in: line, range: NSRange(location: 0, length: text.length)) {
                    guard !literals.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
                    var before = match.range.location - 1, escapes = 0
                    while before >= 0 && text.character(at: before) == 92 { escapes += 1; before -= 1 }
                    guard escapes % 2 == 0 else { continue }
                    var range = match.range(at: 1)
                    if range.location == NSNotFound { range = match.range(at: 2) }
                    var raw = text.substring(with: range)
                    if isWiki, let alias = raw.firstIndex(of: "|") { raw = String(raw[..<alias]) }
                    if let fragment = raw.firstIndex(of: "#") { raw = String(raw[..<fragment]) }
                    let leading = raw.prefix(while: { $0.isWhitespace }).utf16.count
                    raw = raw.trimmingCharacters(in: .whitespaces)
                    guard !raw.isEmpty else { continue }
                    range = NSRange(location: offset + range.location + leading, length: raw.utf16.count)
                    let target = raw.replacingOccurrences(of: #"\\([\\ ()\[\]<>])"#, with: "$1", options: .regularExpression)
                    let decoded = target.removingPercentEncoding ?? target
                    let lower = decoded.lowercased()
                    guard !["https:", "http:", "mailto:", "data:"].contains(where: { lower.hasPrefix($0) }), !decoded.hasPrefix("//") else { continue }
                    result.append(Reference(range: range, target: decoded))
                }
            }
        }
        return result.sorted { $0.range.location < $1.range.location }
    }

    /// Collapse relative parents without allowing an escape from the granted folder.
    static func relative(_ target: String, parent: String = "") -> String? {
        guard !target.isEmpty, target.count <= 2000, !target.hasPrefix("/"),
              !target.contains(":"), !target.contains("\0"), !target.contains("?") else { return nil }
        var parts = parent.split(separator: "/").map(String.init)
        for part in target.components(separatedBy: "/") {
            if part == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast() }
            else if part != "." { guard !part.isEmpty else { return nil }; parts.append(part) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }
}

/// A fixed export's grant registry and asset budget. No filesystem authority comes from Markdown.
@MainActor final class CanvasPortableFiles {
    let staging: URL, snapshot: WorkspaceSnapshot, vault: CanvasVault, root: URL?
    private var grants: [String: LocusObject] = [:]
    private var paths: [String: String] = [:]
    private(set) var filePaths: Set<String> = []
    private(set) var unresolved: [ObjectValue] = []
    private(set) var total = 0
    var count: Int { paths.count }

    init(staging: URL, snapshot: WorkspaceSnapshot, vault: CanvasVault, root: URL?) {
        self.staging = staging; self.snapshot = snapshot; self.vault = vault; self.root = root
        for object in snapshot.objects where object.supported && ["file", "group"].contains(object.type) {
            _ = CanvasFiles.withURL(object) { url in grants[url.standardizedFileURL.path] = object; return true }
        }
    }
    private func allocate(_ key: String, data: Data, ext: String) throws -> String {
        guard paths.count < CanvasExport.countLimit, data.count <= CanvasExport.assetLimit,
              data.count <= CanvasExport.totalLimit - total else { throw CanvasExport.Failure.tooLarge }
        let suffix = ext.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let path = "assets/\(paths.count + 1)." + (suffix.isEmpty ? "bin" : String(suffix.prefix(12)))
        paths[key] = path; total += data.count; return path
    }
    private func write(_ data: Data, path: String) throws {
        do { try data.write(to: staging.appendingPathComponent(path), options: .atomic) }
        catch { throw CanvasExport.Failure.writeFailed }
    }
    func saved(_ data: Data, object: LocusObject) throws -> String {
        let key = "preview:" + object.id.uuidString
        if let path = paths[key] { return path }
        let path = try allocate(key, data: data, ext: "png"); try write(data, path: path); return path
    }
    func file(_ object: LocusObject) throws -> String? {
        try CanvasFiles.withURL(object) { try file($0, object: object, depth: 0) }
    }
    private func file(_ url: URL, object: LocusObject?, depth: Int) throws -> String {
        let key = "file:" + url.standardizedFileURL.path
        if let path = paths[key] { return path }
        try WorkspaceFiles.checkPath(url)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw WorkspaceError.unsafePath }
        let original = try CanvasFileDraft.read(url, limit: CanvasExport.assetLimit)
        let path = try allocate(key, data: original, ext: url.pathExtension)
        filePaths.insert(path)
        var data = original
        if ["md", "markdown"].contains(url.pathExtension.lowercased()), let text = CanvasFileDraft.decode(original) {
            let rewritten = try rewrite(text, object: object, source: url, directory: "assets", depth: depth, origin: .string(path))
            if rewritten != text { data = Data(rewritten.utf8) }
            let extra = data.count - original.count
            guard data.count <= CanvasExport.assetLimit, extra <= CanvasExport.totalLimit - total else { throw CanvasExport.Failure.tooLarge }
            total += extra
        }
        try write(data, path: path); return path
    }
    func note(_ text: String, object: LocusObject, node: ObjectValue) throws -> String {
        try rewrite(text, object: object, source: nil, directory: "", depth: 0, origin: node)
    }
    private func resolve(_ target: String, object: LocusObject?, source: URL?) -> (URL, LocusObject?)? {
        guard !target.hasPrefix("/"), !target.contains(":"), !target.contains("\0"), !target.contains("?") else { return nil }
        if let source {
            for name in [target] + ((target as NSString).pathExtension.isEmpty ? [target + ".md", target + ".markdown"] : []) {
                let candidate = source.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
                if let grant = grants[candidate.path] { return (candidate, grant) }
                if let root, candidate.path.hasPrefix(root.path + "/"),
                   let url = CanvasVault.safeURL(String(candidate.path.dropFirst(root.path.count + 1)), root: root),
                   (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return (url, nil) }
            }
        }
        if let object, let referenceURL = CanvasReference.url(target), let reference = CanvasReference(referenceURL),
           let granted = reference.resolve(in: snapshot, source: object), let url = CanvasFiles.withURL(granted, { $0 }) { return (url, granted) }
        if root != nil, let url = vault.resolve(target, source: object) { return (url, nil) }
        return nil
    }
    private func report(_ reference: String, origin: ObjectValue, reason: String) throws {
        guard unresolved.count < 2000 else { throw CanvasExport.Failure.tooLarge }
        unresolved.append(.dictionary(["source": origin, "reference": .string(reference), "reason": .string(reason)]))
    }
    private func rewrite(_ text: String, object: LocusObject?, source: URL?, directory: String, depth: Int, origin: ObjectValue) throws -> String {
        guard text.utf8.count <= 1_000_000, depth < 32 else {
            try report("", origin: origin, reason: "Markdown dependency scan limit reached"); return text
        }
        let references = CanvasPortableReferences.references(text)
        guard references.count <= 256 else { throw CanvasExport.Failure.tooLarge }
        var changes: [(NSRange, String)] = []
        for reference in references {
            guard let (url, granted) = resolve(reference.target, object: object, source: source) else {
                try report(reference.target, origin: origin, reason: "File unavailable or outside granted access"); continue
            }
            do {
                let path: String
                if let granted {
                    guard let copied = try CanvasFiles.withURL(granted, { try file($0, object: granted, depth: depth + 1) }) else { throw WorkspaceError.unavailable }
                    path = copied
                } else { path = try file(url, object: nil, depth: depth + 1) }
                changes.append((reference.range, directory.isEmpty ? path : (path as NSString).lastPathComponent))
            } catch let error as CanvasExport.Failure { throw error }
            catch CanvasFileEditError.tooLarge { throw CanvasExport.Failure.tooLarge }
            catch { try report(reference.target, origin: origin, reason: "File unavailable") }
        }
        let result = NSMutableString(string: text)
        for (range, replacement) in changes.reversed() { result.replaceCharacters(in: range, with: replacement) }
        return result as String
    }
}
