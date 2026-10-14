import AppKit
import ImageIO

extension NSAttributedString.Key { static let canvasLiteral = NSAttributedString.Key("locus.canvas.literal") }

/// Native, non-executable previews with explicit file grants and bounded expansion.
@MainActor enum CanvasRichMarkdown {
    static let embedPattern = try! NSRegularExpression(pattern: "!\\[\\[([^\\]\\n]+)\\]\\]")
    final class Budget { var embeds = 0; var bytes = 0; var images = 0 }
    static func render(_ source: String, object: LocusObject, snapshot: WorkspaceSnapshot, vault: CanvasVault, width: Double) -> NSAttributedString {
        render(source, object: object, snapshot: snapshot, vault: vault, width: width, seen: [identity(object)], depth: 0, budget: Budget())
    }
    private static func identity(_ object: LocusObject) -> String {
        if object.type == "file", let path = CanvasFiles.withURL(object, { $0.resolvingSymlinksInPath().path }) { return "file:" + path }
        return object.id.uuidString
    }
    static func resolve(_ target: String, source: LocusObject, snapshot: WorkspaceSnapshot, vault: CanvasVault) -> LocusObject? {
        guard let url = CanvasReference.url(target), let reference = CanvasReference(url) else { return nil }
        if reference.target.isEmpty, source.supported, ["note", "file"].contains(source.type) { return source }
        return reference.resolve(in: snapshot, source: source) ?? vault.object(reference.target, source: source)
    }
    private static func render(_ source: String, object: LocusObject, snapshot: WorkspaceSnapshot, vault: CanvasVault, width: Double, seen: Set<String>, depth: Int, budget: Budget) -> NSAttributedString {
        budget.bytes += source.utf8.count
        guard budget.bytes <= 1_000_000 else { return message("Embed size limit reached") }
        let output = NSMutableAttributedString(attributedString: CanvasMarkdown.render(source))
        // Foundation retains Markdown image URLs as attributes; no network loader is used.
        var images: [(NSRange, URL, String)] = []
        output.enumerateAttribute(.imageURL, in: NSRange(location: 0, length: output.length)) { value, range, _ in
            guard let url = value as? URL else { return }; images.append((range, url, (output.string as NSString).substring(with: range)))
        }
        for (range, url, label) in images.reversed() {
            guard output.attribute(.canvasLiteral, at: range.location, effectiveRange: nil) == nil else { continue }
            if url.scheme == nil, let target = resolve(url.relativeString.removingPercentEncoding ?? url.relativeString, source: object, snapshot: snapshot, vault: vault), let image = image(target, budget: budget) {
                output.replaceCharacters(in: range, with: attachment(image, width: width, caption: label))
            } else { output.replaceCharacters(in: range, with: message("Image unavailable: " + label)) }
        }
        let plain = output.string as NSString
        let matches = embedPattern.matches(in: output.string, range: NSRange(location: 0, length: plain.length))
        let raw = source as NSString
        var flags: [String: [Bool]] = [:], occurrences: [String: Int] = [:]
        for match in embedPattern.matches(in: source, range: NSRange(location: 0, length: raw.length)) {
            var slashes = 0, before = match.range.location - 1
            while before >= 0 && raw.character(at: before) == 92 { slashes += 1; before -= 1 }
            flags[raw.substring(with: match.range), default: []].append(slashes % 2 == 0)
        }
        let allowed = matches.map { match -> Bool in
            let key = plain.substring(with: match.range), index = occurrences[key, default: 0]; occurrences[key] = index + 1
            return flags[key].flatMap { index < $0.count ? $0[index] : nil } ?? false
        }
        for (index, match) in matches.enumerated().reversed() {
            guard allowed[index] else { continue }
            guard output.attribute(.canvasLiteral, at: match.range.location, effectiveRange: nil) == nil else { continue }
            let parts = plain.substring(with: match.range(at: 1)).components(separatedBy: "|"), targetName = parts[0]
            budget.embeds += 1
            guard budget.embeds <= 16, depth < 3 else { output.replaceCharacters(in: match.range, with: message("Embed limit reached: " + targetName)); continue }
            guard let target = resolve(targetName, source: object, snapshot: snapshot, vault: vault) else { output.replaceCharacters(in: match.range, with: message("Embed not found: " + targetName)); continue }
            let sectionID = targetName.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let targetID = identity(target) + (sectionID.count == 2 ? "#" + sectionID[1].lowercased() : ""), linkName = target.type == "file" ? (vault.relativePath(target) ?? target.title) : target.title
            let link = CanvasReference.url(linkName + (targetName.contains("#") ? "#" + String(targetName.split(separator: "#", maxSplits: 1).last ?? "") : ""))
            if seen.contains(targetID) { output.replaceCharacters(in: match.range, with: message("Cyclic embed: " + target.title)); continue }
            let embedded = NSMutableAttributedString()
            let heading = NSMutableAttributedString(string: target.title + "\n", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: Palette.NS.muted])
            if let link { heading.addAttribute(.link, value: link, range: NSRange(location: 0, length: heading.length)) }; embedded.append(heading)
            if target.type == "note" || (target.type == "file" && CanvasFiles.editable(target)) {
                let raw = target.type == "note" ? target.text : CanvasFiles.withURL(target) { url in (try? CanvasFileDraft.read(url)).flatMap(CanvasFileDraft.decode) }
                let fragment = targetName.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                guard let raw, let content = fragment.count == 2 ? CanvasDocument.section(raw, subpath: "#" + fragment[1]) : raw else { output.replaceCharacters(in: match.range, with: message("Embed section not found: " + targetName)); continue }
                let body = NSMutableAttributedString(attributedString: render(content, object: target, snapshot: snapshot, vault: vault, width: width, seen: seen.union([targetID]), depth: depth + 1, budget: budget))
                var redirected: [(NSRange, URL)] = []
                body.enumerateAttribute(.link, in: NSRange(location: 0, length: body.length)) { value, range, _ in
                    guard let value = value as? URL else { return }
                    if value.scheme == "locus-task", let link { redirected.append((range, link)) }
                    else if let reference = CanvasReference(value) {
                        let destination: String?
                        if reference.target.isEmpty { destination = linkName }
                        else if let resolved = resolve(reference.target, source: target, snapshot: snapshot, vault: vault) {
                            destination = resolved.type == "file" ? (vault.relativePath(resolved) ?? resolved.title) : resolved.title
                        } else { destination = nil }
                        if let destination, let local = CanvasReference.url(destination + (reference.fragment.map { "#" + $0 } ?? "")) { redirected.append((range, local)) }
                    }
                }
                for (range, value) in redirected { body.addAttribute(.link, value: value, range: range) }
                embedded.append(body)
            } else if let image = image(target, budget: budget) {
                let requested = parts.count > 1 ? Double(parts[1].split(separator: "x").first ?? "") : nil
                embedded.append(attachment(image, width: min(width, max(40, requested ?? width)), caption: ""))
            } else { embedded.append(message("Open source to view this file")) }
            output.replaceCharacters(in: match.range, with: embedded)
        }
        return output
    }
    private static func message(_ text: String) -> NSAttributedString { NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Palette.NS.muted]) }
    private static func attachment(_ image: NSImage, width: Double, caption: String) -> NSAttributedString {
        let attachment = NSTextAttachment(); let ratio = min(1, max(40, width) / max(1, image.size.width))
        let scaled = NSImage(size: CGSize(width: image.size.width * ratio, height: image.size.height * ratio))
        scaled.lockFocus(); image.draw(in: CGRect(origin: .zero, size: scaled.size)); scaled.unlockFocus()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: scaled)
        let text = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        if !caption.isEmpty { text.append(message("\n" + caption)) }; text.append(NSAttributedString(string: "\n")); text.addAttribute(.canvasLiteral, value: true, range: NSRange(location: 0, length: text.length)); return text
    }
    private static func image(_ object: LocusObject, budget: Budget) -> NSImage? {
        guard budget.images < 8 else { return nil }
        return CanvasFiles.withURL(object) { url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 25_000_000,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 16_000_000,
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
            budget.images += 1; return NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
        }
    }
}
