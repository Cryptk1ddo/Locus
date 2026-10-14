import AppKit
import UniformTypeIdentifiers
import ImageIO

extension Notification.Name { static let canvasFilesChanged = Notification.Name("locus.canvas.filesChanged") }

/// Markdown is rendered as native attributed text; editing always keeps source.
enum CanvasMarkdown {
    private static let taskPattern = try! NSRegularExpression(pattern: "^([ \t]*)(?:[-*+] )\\[([ xX])\\] ")
    private static let wikiPattern = try! NSRegularExpression(pattern: "(?<!!)\\[\\[([^\\]\\n]+)\\]\\]")
    private static let cache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>(); cache.countLimit = 64; cache.totalCostLimit = 8_000_000; return cache
    }()
    static func render(_ source: String) -> NSAttributedString {
        if let cached = cache.object(forKey: source as NSString) { return cached }
        let output = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle(); paragraph.paragraphSpacing = 8
        var code = false, sourceOffset = 0
        let lines = source.components(separatedBy: "\n"), tables = CanvasTable.layout(source.components(separatedBy: "\n"))
        var fence: String?
        for (index, line) in lines.enumerated() {
            defer { sourceOffset += line.utf16.count + 1 }
            if tables.separators.contains(index) { continue }
            if let row = tables.rows[index] { output.append(CanvasTable.render(row)); continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3)); if fence == marker { fence = nil } else if fence == nil { fence = marker }
                code = fence != nil; continue
            }
            var text = line, font = NSFont.systemFont(ofSize: 14)
            if code { font = .monospacedSystemFont(ofSize: 13, weight: .regular) }
            else if line.hasPrefix("#") {
                let level = min(6, line.prefix(while: { $0 == "#" }).count)
                if line.dropFirst(level).first == " " { text = String(line.dropFirst(level + 1)); font = .systemFont(ofSize: CGFloat(26 - level * 2), weight: .bold) }
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") { text = "• " + line.dropFirst(2) }
            var task: (Int, Int)?
            if !code, let match = taskPattern.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
                let raw = line as NSString, indent = raw.substring(with: match.range(at: 1))
                let checked = raw.substring(with: match.range(at: 2)) != " "
                text = indent + (checked ? "☑ " : "☐ ") + raw.substring(from: match.range.length)
                task = (sourceOffset + match.range(at: 2).location - 1, indent.utf16.count)
            }
            if !code {
                let original = text as NSString, literal = CanvasDocument.inlineCodeRanges(text)
                for match in wikiPattern.matches(in: text, range: NSRange(location: 0, length: original.length)).reversed() {
                    guard !literal.contains(where: { NSIntersectionRange($0, match.range).length > 0 }), match.range.location == 0 || original.character(at: match.range.location - 1) != 92 else { continue }
                    let value = original.substring(with: match.range(at: 1)).components(separatedBy: "|")
                    guard let url = CanvasReference.url(value[0]) else { continue }
                    let label = (value.count > 1 ? value[1] : value[0]).replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                    if let range = Range(match.range, in: text) { text.replaceSubrange(range, with: "[" + label + "](" + url.absoluteString + ")") }
                }
            }
            let attributed: NSMutableAttributedString
            if !code, let inline = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                attributed = NSMutableAttributedString(attributedString: NSAttributedString(inline))
                attributed.addAttributes([.font: font, .foregroundColor: Palette.NS.ink, .paragraphStyle: paragraph], range: NSRange(location: 0, length: attributed.length))
                let plain = String(inline.characters)
                for run in inline.runs {
                    let start = inline.characters.distance(from: inline.startIndex, to: run.range.lowerBound)
                    let end = inline.characters.distance(from: inline.startIndex, to: run.range.upperBound)
                    let range = NSRange(plain.index(plain.startIndex, offsetBy: start)..<plain.index(plain.startIndex, offsetBy: end), in: plain)
                    var styled = font
                    if let intent = run.inlinePresentationIntent {
                        if intent.contains(.stronglyEmphasized) { styled = NSFontManager.shared.convert(styled, toHaveTrait: .boldFontMask) }
                        if intent.contains(.emphasized) { styled = NSFontManager.shared.convert(styled, toHaveTrait: .italicFontMask) }
                        if intent.contains(.code) { attributed.addAttribute(.canvasLiteral, value: true, range: range); styled = .monospacedSystemFont(ofSize: 13, weight: .regular); attributed.addAttribute(.backgroundColor, value: Palette.NS.wash, range: range) }
                        if intent.contains(.strikethrough) { attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
                    }
                    attributed.addAttribute(.font, value: styled, range: range)
                    if run.link != nil { attributed.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range) }
                }
            } else { attributed = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: Palette.NS.ink, .paragraphStyle: paragraph]) }
            if code { attributed.addAttribute(.canvasLiteral, value: true, range: NSRange(location: 0, length: attributed.length)) }
            if let (offset, location) = task, location < attributed.length, let url = URL(string: "locus-task://toggle?offset=\(offset)") {
                attributed.addAttribute(.link, value: url, range: NSRange(location: location, length: 1))
            }
            output.append(attributed); output.append(NSAttributedString(string: "\n", attributes: [.font: font]))
        }
        let result = NSAttributedString(attributedString: output); cache.setObject(result, forKey: source as NSString, cost: max(1, source.utf16.count * 16)); return result
    }
}

@MainActor
enum CanvasFiles {
    static func choose(store: WorkspaceStore, at point: CGPoint) {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true; panel.message = "Add files to Canvas"
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window) { result in if result == .OK { _ = add(panel.urls, to: store, at: point) } } }
    }
    @discardableResult static func add(_ urls: [URL], to store: WorkspaceStore, at point: CGPoint) -> Bool {
        guard !urls.isEmpty, urls.count <= 100, store.writable else { return false }
        var files: [URL] = [], grants: [URL] = []
        defer { grants.forEach { $0.stopAccessingSecurityScopedResource() } }
        for url in urls.prefix(100) {
            if url.startAccessingSecurityScopedResource() { grants.append(url) }
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return false }
                for case let file as URL in enumerator {
                    let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values?.isRegularFile == true && values?.isSymbolicLink != true { files.append(file) }
                    if files.count > 100 { return false }
                }
            } else { files.append(url) }
        }
        guard !files.isEmpty, files.count <= 100 else { return false }
        do {
            let objects = try files.map { url -> LocusObject in
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                return LocusObject(type: "file", title: url.lastPathComponent, content: ["file": .string(url.path), "bookmark": .string(bookmark.base64EncodedString())])
            }
            return store.mutate { next in
                for (i, object) in objects.enumerated() {
                    next.objects.append(object); next.placements.append(WallPlacement(objectID: object.id, x: point.x + Double(i % 3) * 340, y: point.y + Double(i / 3) * 260, width: 320, height: 240))
                }
            }
        } catch { return false }
    }
    @discardableResult static func addImage(_ board: NSPasteboard, to store: WorkspaceStore, at point: CGPoint) -> Bool {
        guard board.availableType(from: [.png, .tiff]) != nil, store.writable,
              let data = board.data(forType: .png) ?? board.data(forType: .tiff), data.count <= 25_000_000,
              let image = CGImageSourceCreateWithData(data as CFData, nil),
              let info = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = info[kCGImagePropertyPixelWidth] as? Int, let height = info[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 16_000_000 else { return false }
        let png: Data
        if CGImageSourceGetType(image) as String? == "public.png" { png = data }
        else {
            guard let cg = CGImageSourceCreateImageAtIndex(image, 0, nil), let encoded = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]), encoded.count <= 25_000_000 else { return false }; png = encoded
        }
        let folder = store.file.deletingLastPathComponent().appendingPathComponent("files")
        let url = folder.appendingPathComponent(UUID().uuidString + ".png")
        do {
            try WorkspaceAssets.permit(png.count, in: folder); try WorkspaceFiles.write(png, to: url)
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let object = LocusObject(type: "file", title: "Image", content: ["file": .string(url.path), "bookmark": .string(bookmark.base64EncodedString()), "origin": .string("clipboard")])
            if store.add(object, at: point) { return true }
            try? FileManager.default.removeItem(at: url); return false
        } catch { if (try? WorkspaceFiles.checkPath(url)) != nil { try? FileManager.default.removeItem(at: url) }; return false }
    }
    /// Only user-granted bookmarks authorize reading. JSON Canvas paths alone do not.
    static func withURL<T>(_ object: LocusObject, _ body: (URL) throws -> T?) rethrows -> T? {
        guard object.supported, ["file", "group"].contains(object.type), let encoded = object.content["bookmark"]?.text, let data = Data(base64Encoded: encoded) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
    static func editable(_ object: LocusObject) -> Bool {
        guard object.supported, object.type == "file", object.content["bookmark"]?.text != nil else { return false }
        let extensions = ["md", "markdown", "txt"]
        return withURL(object) { extensions.contains($0.pathExtension.lowercased()) }
            ?? object.content["file"]?.text.map { extensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) } ?? false
    }
    static func preview(_ object: LocusObject) -> NSImage? {
        withURL(object) { url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 25_000_000 else { return nil }
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) { return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)) }
            if ["pdf", "svg"].contains(url.pathExtension.lowercased()) { return NSImage(contentsOf: url) }
            return nil
        }
    }
    static func open(_ object: LocusObject) { _ = withURL(object) { url in NSWorkspace.shared.open(url) } }
}
