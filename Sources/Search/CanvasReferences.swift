import Foundation

/// These links resolve existing Space objects. A title is never a file grant.
struct CanvasReference: Equatable {
    let target: String
    let fragment: String?
    init?(_ url: URL) {
        guard url.scheme == "locus-note", url.host == "resolve", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = components.queryItems?.first(where: { $0.name == "target" })?.value, target.count <= 1000,
              !target.isEmpty || components.fragment?.isEmpty == false else { return nil }
        self.target = target; fragment = components.fragment
    }
    static func url(_ target: String) -> URL? {
        let parts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        var components = URLComponents(); components.scheme = "locus-note"; components.host = "resolve"
        components.queryItems = [URLQueryItem(name: "target", value: String(parts[0]))]
        if parts.count == 2 { components.fragment = String(parts[1]) }
        return components.url
    }
    func resolve(in snapshot: WorkspaceSnapshot, source: LocusObject? = nil) -> LocusObject? {
        let documents = snapshot.objects.filter { $0.supported && ["note", "file"].contains($0.type) }
        if target.isEmpty { return documents.first { $0.id == source?.id } }
        func name(_ text: String) -> String {
            let path = text as NSString
            let value = ["md", "markdown", "txt", "pdf", "canvas"].contains(path.pathExtension.lowercased()) ? path.deletingPathExtension : text
            return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        if let context = source?.content["portableContext"]?.text {
            let scoped = documents.filter { $0.content["portableContext"]?.text == context }
            let parent = (source?.content["file"]?.text ?? "") as NSString
            let directory = parent.deletingLastPathComponent
            var paths: [String] = []
            for base in [directory, ""] {
                if let path = CanvasPortableReferences.relative(target, parent: base) {
                    paths.append(path)
                    if (path as NSString).pathExtension.isEmpty { paths += [path + ".md", path + ".markdown"] }
                }
            }
            guard !paths.isEmpty else { return nil }
            for path in paths {
                let matches = scoped.filter { $0.content["file"]?.text == path }
                // Multiple Canvas cards may bookmark the same file in this import.
                if let match = matches.first { return match }
            }
            let matches = scoped.filter { name($0.title) == name((target as NSString).lastPathComponent) }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { return nil }
            return nil
        }
        let exact = documents.filter { name($0.title) == name(target) }
        if exact.count == 1 { return exact[0] }
        if exact.count > 1 { return nil }
        let short = name((target as NSString).lastPathComponent)
        let matches = documents.filter { name($0.title) == short }
        return matches.count == 1 ? matches[0] : nil
    }
}

enum CanvasDocument {
    static func inlineCodeRanges(_ source: String) -> [NSRange] {
        let text = source as NSString
        var ranges: [NSRange] = [], opening: (Int, Int)?, index = 0
        while index < text.length {
            guard text.character(at: index) == 96 else { index += 1; continue }
            var slashes = 0, before = index - 1
            while before >= 0 && text.character(at: before) == 92 { slashes += 1; before -= 1 }
            if slashes % 2 == 1 { index += 1; continue }
            let start = index
            while index < text.length && text.character(at: index) == 96 { index += 1 }
            let count = index - start
            if let (position, length) = opening {
                if length == count { ranges.append(NSRange(location: position, length: index - position)); opening = nil }
            } else { opening = (start, count) }
        }
        return ranges
    }
    private static func sectionBounds(_ lines: [String], subpath: String) -> Range<Int>? {
        let reference = String(subpath.drop(while: { $0 == "#" }))
        guard !reference.isEmpty else { return 0..<lines.count }
        if reference.hasPrefix("^") {
            let marker = " " + reference
            guard let found = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasSuffix(marker) }) else { return nil }
            var start = found
            while start > 0 && !lines[start - 1].trimmingCharacters(in: .whitespaces).isEmpty { start -= 1 }
            return start..<(found + 1)
        }
        var code = false, start: Int?, level = 0, end = lines.count
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.toggle(); continue }
            guard !code else { continue }
            let count = line.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(count), line.dropFirst(count).first == " " else { continue }
            let title = line.dropFirst(count + 1).trimmingCharacters(in: CharacterSet(charactersIn: " #\t"))
            if start != nil && count <= level { end = index; break }
            if start == nil && title.localizedCaseInsensitiveCompare(reference) == .orderedSame { start = index; level = count }
        }
        return start.map { $0..<end }
    }
    static func section(_ source: String, subpath: String) -> String? {
        let lines = source.components(separatedBy: "\n")
        guard let bounds = sectionBounds(lines, subpath: subpath) else { return nil }
        var selected = Array(lines[bounds])
        let reference = String(subpath.drop(while: { $0 == "#" }))
        if reference.hasPrefix("^"), !selected.isEmpty { selected[selected.count - 1] = String(selected.last!.trimmingCharacters(in: .whitespaces).dropLast(reference.count + 1)) }
        return selected.joined(separator: "\n")
    }
    static func fragmentOffset(_ source: String, subpath: String) -> Int? {
        let lines = source.components(separatedBy: "\n")
        guard let bounds = sectionBounds(lines, subpath: subpath) else { return nil }
        return lines.prefix(bounds.lowerBound).reduce(0) { $0 + $1.utf16.count + 1 }
    }
    static func togglingTask(_ source: String, offset: Int) -> String? {
        let text = source as NSString
        guard offset >= 0, offset <= text.length - 3 else { return nil }
        let range = NSRange(location: offset, length: 3), marker = text.substring(with: range)
        guard ["[ ]", "[x]", "[X]"].contains(marker), let swiftRange = Range(range, in: source) else { return nil }
        var result = source; result.replaceSubrange(swiftRange, with: marker == "[ ]" ? "[x]" : "[ ]"); return result
    }
}
