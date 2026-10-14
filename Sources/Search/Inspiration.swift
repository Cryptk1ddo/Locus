import AppKit
import WebKit

/// Source references are useful without an account API. Classification never fetches a URL.
enum InspirationSource: String, CaseIterable {
    case pinterest, arena, behance, dribbble, awwwards, web
    var title: String {
        switch self {
        case .pinterest: return "Pinterest"
        case .arena: return "Are.na"
        case .behance: return "Behance"
        case .dribbble: return "Dribbble"
        case .awwwards: return "Awwwards"
        case .web: return "Web"
        }
    }
    var address: URL? {
        switch self {
        case .pinterest: return URL(string: "https://www.pinterest.com/")
        case .arena: return URL(string: "https://www.are.na/")
        case .behance: return URL(string: "https://www.behance.net/")
        case .dribbble: return URL(string: "https://dribbble.com/")
        case .awwwards: return URL(string: "https://www.awwwards.com/")
        case .web: return nil
        }
    }
    static func identify(_ url: URL) -> Self {
        let host = url.host?.lowercased() ?? ""
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if ["pinterest.com", "pinterest.it", "pinterest.fr", "pinterest.de", "pinterest.es", "pinterest.co.uk", "pin.it"].contains(where: matches) { return .pinterest }
        if matches("are.na") { return .arena }
        if matches("behance.net") { return .behance }
        if matches("dribbble.com") { return .dribbble }
        if matches("awwwards.com") { return .awwwards }
        return .web
    }

    static func object(url: URL, title: String, description: String = "", text: String = "", screenshotStatus: String = "unavailable", reason: String = "Saved link; no page preview requested") -> LocusObject? {
        guard url.absoluteString.count <= 8_192, let url = SavedPageAddress.clean(url) else { return nil }
        let provider = identify(url), parts = url.pathComponents.filter { $0 != "/" }
        var kind = "page", remoteID: String?
        if provider == .pinterest {
            if parts.first == "pin", parts.count >= 2, parts[1].allSatisfy(\.isNumber) { kind = "pin"; remoteID = parts[1] }
            else if parts.count >= 2 { kind = "board" }
        } else if provider == .arena {
            kind = parts.first == "block" ? "block" : parts.count >= 2 ? "channel" : "page"
        } else if provider == .dribbble, parts.first == "shots" { kind = "shot" }
        else if provider == .behance, parts.first == "gallery" { kind = "project" }
        var content: [String: ObjectValue] = ["url": .string(url.absoluteString), "provider": .string(provider.rawValue),
            "resourceKind": .string(kind), "description": .string(String(description.prefix(2_000))), "text": .string(String(text.prefix(16_000))),
            "collectedAt": .string(ISO8601DateFormatter().string(from: Date())),
            "screenshot": .dictionary(["status": .string(screenshotStatus), "reason": .string(reason), "value": .null])]
        if let remoteID { content["remoteID"] = .string(String(remoteID.prefix(128))) }
        return LocusObject(type: "inspiration", title: title.isEmpty ? url.host ?? "Inspiration" : title, content: content)
    }

    static let script = #"""
    (() => {
      const visible = e => { const r = e.getBoundingClientRect(), s = getComputedStyle(e); return r.width > 0 && r.height > 0 && r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth && s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0'; };
      const fields = [...document.querySelectorAll('input, textarea, [contenteditable], iframe')].slice(0, 2000);
      const elements = [...document.querySelectorAll('*')].slice(0, 4000);
      const opaqueComponent = elements.length >= 4000 || elements.some(e => e.localName?.includes('-') && visible(e));
      const sensitive = opaqueComponent || fields.length >= 2000 || fields.some(e => visible(e) && (e.tagName === 'IFRAME' || e.type === 'password' || (e.isContentEditable ? e.textContent.trim() : !['button','submit','reset','checkbox','radio','hidden'].includes(e.type) && e.value)));
      const description = document.querySelector('meta[property="og:description"]')?.content || document.querySelector('meta[name="description"]')?.content || '';
      const title = document.querySelector('meta[property="og:title"]')?.content || document.title || '';
      return {title: title.slice(0,300), description: description.slice(0,2000), screenshotAllowed: !sensitive};
    })()
    """#
}

/// One explicit collection, pinned to a committed document, never a second web view.
@MainActor final class InspirationCollection {
    private weak var browser: Browser?
    private weak var tab: Tab?
    private weak var web: PageView?
    private let space: UUID
    private let document: UUID
    private let url: URL
    private var finished = false
    private var metadataAt = ""
    private var snapshotAt: String?

    init?(browser: Browser) {
        guard browser.canCollectInspiration, let tab = browser.active, let web = tab.built, let url = tab.pageAddress else { return nil }
        self.browser = browser; self.tab = tab; self.web = web
        space = browser.spaceID; document = tab.captureDocumentID; self.url = url
    }
    private var current: Bool {
        guard !finished, let browser, let tab, let web else { return false }
        return browser.inspirationCollection === self && browser.spaceID == space && browser.activeID == tab.id
            && browser.tabs.contains(where: { $0 === tab }) && tab.built === web && tab.captureDocumentID == document
            && tab.pageAddress == url && web.url == url && !web.isLoading && !tab.shy && !tab.bench && tab.held == nil
            && web.configuration.websiteDataStore.isPersistent && WorkspaceStore.shared(for: space).writable
    }
    func start(delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.cancel() }
        // An isolated probe can hold the request before extraction to exercise
        // document/Space invalidation deterministically. Production starts now.
        if Store.testing, delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + min(1, delay)) { [weak self] in self?.readPage() }
        } else { readPage() }
    }
    private func readPage() {
        guard current, let web else { cancel(); return }
        web.evaluateJavaScript(InspirationSource.script, in: nil, in: Web.world) { [weak self] result in
            guard let self else { return }
            guard self.current else { self.cancel(); return }
            guard let metadata = (try? result.get()) as? [String: Any] else { self.cancel(); self.browser?.announce("This page could not be collected"); return }
            self.metadataAt = ISO8601DateFormatter().string(from: Date())
            let title = metadata["title"] as? String ?? "", description = metadata["description"] as? String ?? ""
            guard metadata["screenshotAllowed"] as? Bool == true, web.magnification == 1, !web.bounds.isEmpty else {
                self.commit(title: title, description: description, png: nil, reason: "Preview omitted: editable content, embedded frame, opaque component or native magnification")
                return
            }
            let config = WKSnapshotConfiguration()
            config.rect = web.bounds
            config.snapshotWidth = NSNumber(value: min(1_000, web.bounds.width))
            web.takeSnapshot(with: config) { [weak self] image, _ in
                guard let self else { return }
                guard self.current else { self.cancel(); return }
                self.snapshotAt = ISO8601DateFormatter().string(from: Date())
                guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    self.commit(title: title, description: description, png: nil, reason: "WebKit preview unavailable"); return
                }
                Task { @MainActor [weak self] in
                    let data = await Task.detached(priority: .utility) { WorkspaceImage.png(cg) }.value
                    guard let self else { return }
                    guard self.current else { self.cancel(); return }
                    self.commit(title: title, description: description, png: data, reason: data == nil ? "Preview exceeded encoding limits" : "Visible viewport; page metadata and pixels have separate timestamps")
                }
            }
        }
    }
    private func commit(title: String, description: String, png: Data?, reason: String) {
        guard current, let browser, let tab,
              let cleanURL = SavedPageAddress.clean(url),
              let draft = InspirationSource.object(url: url, title: title, description: description, screenshotStatus: png == nil ? "unavailable" : "captured", reason: reason) else { cancel(); return }
        var content = draft.content
        content["metadataAt"] = .string(metadataAt)
        if let snapshotAt { content["snapshotAt"] = .string(snapshotAt) }
        let object = LocusObject(type: "inspiration", title: draft.title, content: content)
        let store = WorkspaceStore.shared(for: space)
        // A bound reference may have an older saved address; don't misattribute the clip to it.
        let existing = tab.wallObjectID(in: space).flatMap { id in store.snapshot.objects.first { $0.id == id && $0.url == SavedPageAddress.clean(url) } }
        let source = existing ?? LocusObject(type: "page", title: tab.title, content: ["url": .string(cleanURL.absoluteString)])
        let saved = store.addInspiration(object, png: png, sourcePage: source)
        cancel()
        if saved { browser.openWall(); browser.announce("Inspiration saved to Wall") }
        else { browser.announce(store.problem ?? "This Wall cannot be changed") }
    }
    func cancel() {
        guard !finished else { return }; finished = true
        if browser?.inspirationCollection === self { browser?.inspirationCollection = nil; browser?.collectingInspiration = false }
    }
}

extension Browser {
    var canCollectInspiration: Bool { canCaptureUI && !collectingInspiration && WorkspaceStore.shared(for: spaceID).writable }
    func collectInspiration(delay: TimeInterval = 0) {
        guard let collection = InspirationCollection(browser: self) else { announce("Load a normal web page before collecting inspiration"); return }
        uiCapture?.cancel()
        inspirationCollection = collection; collectingInspiration = true
        collection.start(delay: delay)
    }
}
