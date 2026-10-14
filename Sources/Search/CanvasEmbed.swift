import AppKit
import WebKit
import PDFKit
import AVKit

/// A canvas embed has no Tab, automation bridge, or browser navigation delegate.
/// It uses the Space's existing WebKit configuration and is released offscreen.
@MainActor
final class CanvasWebEmbed: WKWebView, WKNavigationDelegate {
    var interactive = false
    override func hitTest(_ point: NSPoint) -> NSView? { interactive ? super.hitTest(point) : nil }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { nextResponder?.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Imported addresses and page redirects cannot open local files/custom schemes.
        decisionHandler(navigationAction.request.url.map { SavedPageAddress.clean($0) == $0 } == true ? .allow : .cancel)
    }
}

extension CanvasFiles {
    static func text(_ object: LocusObject) -> String? {
        withURL(object) { url in
            guard ["md", "txt", "markdown"].contains(url.pathExtension.lowercased()),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_000_000 else { return nil }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let subpath = object.content["subpath"]?.text ?? { if case .dictionary(let fields) = object.content["canvasNode"] { return fields["subpath"]?.text }; return nil }()
            if let subpath { return CanvasDocument.section(text, subpath: subpath) ?? "Referenced section not found." }
            return text
        }
    }
    static func replace(_ object: LocusObject, store: WorkspaceStore) {
        guard object.supported, object.type == "file" else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
            _ = store.mutate { next in
                guard let i = next.objects.firstIndex(where: { $0.id == object.id }), next.objects[i] == object else { throw WorkspaceError.unavailable }
                var fields = object.fields, content = object.content
                content["file"] = .string(url.path); content["bookmark"] = .string(bookmark.base64EncodedString()); fields["title"] = .string(url.lastPathComponent); fields["content"] = .dictionary(content)
                next.objects[i] = try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))
            }
        }
    }
    static func convert(_ object: LocusObject, store: WorkspaceStore) {
        guard object.supported, object.type == "note", let window = NSApp.keyWindow else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = object.title + ".md"; panel.directoryURL = CanvasVault.shared(workspace: store.file).withRoot { $0 }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try object.text.write(to: url, atomically: true, encoding: .utf8)
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                _ = store.mutate { next in
                    guard let i = next.objects.firstIndex(where: { $0.id == object.id }), next.objects[i] == object else { throw WorkspaceError.unavailable }
                    var fields = object.fields, content = object.content
                    fields["type"] = .string("file"); content["file"] = .string(url.path); content["bookmark"] = .string(bookmark.base64EncodedString()); fields["content"] = .dictionary(content)
                    next.objects[i] = try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))
                }
            } catch { NSSound.beep() }
        }
    }
}

extension CanvasFiles {
    static func background(_ object: LocusObject, store: WorkspaceStore) {
        guard object.supported, object.type == "group", let window = NSApp.keyWindow else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
            _ = store.mutate { next in
                guard let i = next.objects.firstIndex(where: { $0.id == object.id }), next.objects[i] == object else { throw WorkspaceError.unavailable }
                var fields = object.fields, content = object.content
                content["background"] = .string(url.path); content["bookmark"] = .string(bookmark.base64EncodedString()); content["backgroundStyle"] = .string("cover"); fields["content"] = .dictionary(content)
                next.objects[i] = try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))
            }
        }
    }
}
