import AppKit

/// Read-mode content scrolls within selected cards; the card still owns normal
/// presses/drags. Command-click follows a Markdown link without entering edit mode.
@MainActor
final class CanvasTextPreview: NSScrollView, NSTextViewDelegate {
    let text = NSTextView()
    var openURL: (URL) -> Void = { _ in }
    var openReference: (CanvasReference) -> Void = { _ in }
    var toggleTask: (Int, String) -> Void = { _, _ in }
    var objectID: UUID?
    var source = ""
    var renderRich: ((String, Double) -> NSAttributedString)?
    private var revision = -1
    private var renderWidth = 0.0
    var zoom: Double = 0
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, event.type == .scrollWheel && !event.modifierFlags.contains(.command)
                || event.type == .leftMouseDown && (event.modifierFlags.contains(.command) || interactiveLink(at: point)) else { return nil }
        return super.hitTest(point)
    }
    private func interactiveLink(at point: NSPoint) -> Bool {
        guard let link = link(at: convert(point, from: superview)) else { return false }
        return ["locus-task", "locus-note"].contains(link.scheme ?? "")
    }
    private func link(at point: NSPoint) -> URL? {
        guard bounds.contains(point), let layout = text.layoutManager, let container = text.textContainer else { return nil }
        let local = text.convert(point, from: self)
        let p = NSPoint(x: local.x - text.textContainerInset.width, y: local.y - text.textContainerInset.height)
        guard p.x >= 0, p.y >= 0 else { return nil }
        let glyph = layout.glyphIndex(for: p, in: container)
        guard glyph < layout.numberOfGlyphs, layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).insetBy(dx: -2, dy: -2).contains(p) else { return nil }
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < text.string.utf16.count, let link = text.textStorage?.attribute(.link, at: index, effectiveRange: nil) as? URL else { return nil }
        return link
    }
    @discardableResult func activateLink(at point: NSPoint, external: Bool) -> Bool {
        guard let url = link(at: point), external || ["locus-task", "locus-note"].contains(url.scheme ?? "") else { return false }
        follow(url); return true
    }
    func reveal(_ fragment: String) {
        guard let offset = CanvasDocument.fragmentOffset(source, subpath: fragment),
              let range = Range(NSRange(location: 0, length: offset), in: source) else { return }
        let prefix = String(source[range])
        let location = max(0, (renderRich?(prefix, renderWidth) ?? CanvasMarkdown.render(prefix)).length - (prefix.hasSuffix("\n") ? 1 : 0))
        text.scrollRangeToVisible(NSRange(location: min(text.string.utf16.count, location), length: 0))
    }
    init() {
        super.init(frame: .zero); hasVerticalScroller = true; autohidesScrollers = true; drawsBackground = false
        text.isEditable = false; text.isSelectable = true; text.isRichText = true; text.drawsBackground = false; text.delegate = self; text.isVerticallyResizable = true; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        documentView = text
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ source: String, zoom: Double, revision: Int = 0) {
        let width = max(40, Double(contentSize.width) / max(0.05, zoom) - 24)
        if self.source != source || self.zoom != zoom || self.revision != revision || abs(renderWidth - width) > 1 {
            self.revision = revision; renderWidth = width
            self.source = source; self.zoom = zoom
            let rendered = NSMutableAttributedString(attributedString: renderRich?(source, width) ?? CanvasMarkdown.render(source))
            rendered.enumerateAttribute(.font, in: NSRange(location: 0, length: rendered.length)) { font, range, _ in
                if let font = font as? NSFont { rendered.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: font.pointSize * zoom) ?? font, range: range) }
            }
            rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
                guard let attachment = value as? NSTextAttachment, let cell = attachment.attachmentCell as? NSTextAttachmentCell, let image = cell.image else { return }
                image.size = CGSize(width: image.size.width * zoom, height: image.size.height * zoom)
            }
            text.textStorage?.setAttributedString(rendered)
        }
        text.textContainerInset = CGSize(width: 12 * zoom, height: 12 * zoom)
        text.frame.size.width = contentSize.width
        if let container = text.textContainer, let layout = text.layoutManager { layout.ensureLayout(for: container); text.frame.size.height = max(contentSize.height, layout.usedRect(for: container).height + 24 * zoom) }
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        if let url { follow(url) }; return true
    }
    private func follow(_ url: URL) {
            if let reference = CanvasReference(url) { openReference(reference) }
            else if url.scheme == "locus-task", url.host == "toggle", let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "offset" })?.value, let offset = Int(raw) { toggleTask(offset, source) }
            else if let clean = SavedPageAddress.clean(url) { openURL(clean) }
    }
}
