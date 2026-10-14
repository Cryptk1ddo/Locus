import AppKit
import ImageIO
import WebKit

/// A short-lived, native WebKit inspection session, pinned to one document.
@MainActor
final class UICapture: NSObject, WKScriptMessageHandler {
    static let handler = "locusUICapture"
    let token = UUID()
    private weak var browser: Browser?
    private weak var tab: Tab?
    private weak var web: PageView?
    private let space: UUID
    private let document: UUID
    private let url: URL
    private let predecessor: UUID?
    private var finished = false
    private var received = false

    init?(browser: Browser, derivedFrom: UUID? = nil) {
        guard browser.canCaptureUI, let tab = browser.active, let web = tab.built,
              let url = tab.pageAddress else { return nil }
        self.browser = browser
        self.tab = tab
        self.web = web
        space = browser.spaceID
        document = tab.captureDocumentID
        self.url = url
        predecessor = derivedFrom
    }

    private var current: Bool {
        guard !finished, let browser, let tab, let web else { return false }
        return browser.uiCapture === self && browser.spaceID == space && browser.activeID == tab.id
            && tab.built === web && tab.captureDocumentID == document && tab.pageAddress == url
            && !web.isLoading && !tab.shy && !tab.bench && tab.held == nil
    }

    func start(picking: Bool = true, selector: String? = nil) {
        guard current, let web else { cancel(); return }
        tab?.uiCapture = self
        let controller = web.configuration.userContentController
        controller.removeScriptMessageHandler(forName: Self.handler, contentWorld: Web.world)
        controller.add(self, contentWorld: Web.world, name: Self.handler)
        web.evaluateJavaScript(UICaptureScript.install(token: token, picking: picking), in: nil, in: Web.world) { [weak self] result in
            guard let self, self.current else { return }
            if case .failure = result { self.fail("This page could not be inspected") }
            else if let selector { self.inspect(selector: selector) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.cancel() }
    }

    /// Same extraction as the picker, for the isolated test-only Bench probe.
    func inspect(selector: String) {
        guard current, let web, let data = try? JSONEncoder().encode(selector), let literal = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.__locusCapture.inspect(document.querySelector(\(literal)))", in: nil, in: Web.world) { [weak self] result in
            guard let self, self.current else { return }
            switch result {
            case .success(let value): self.receive(value)
            case .failure: self.fail("Choose a visible element outside editable fields")
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard current, message.frameInfo.isMainFrame, message.webView === web,
              let body = message.body as? [String: Any], body["token"] as? String == token.uuidString else { return }
        if body["cancelled"] as? Bool == true { cancel() }
        else if body["error"] != nil { fail("Choose a visible element outside editable fields") }
        else { receive(body["capture"]) }
    }

    private func receive(_ value: Any?) {
        guard current, !received, let value else { return }
        received = true
        cleanupPicker()
        do {
            var capture = try Self.payload(value)
            capture["nativeMagnification"] = .number(Double(web?.magnification ?? 1))
            capture["pageZoom"] = .number(Double(web?.pageZoom ?? 1))
            guard case .bool(true) = capture["screenshotAllowed"] else {
                commit(capture, image: nil)
                return
            }
            guard let web, web.magnification == 1,
                  let rect = Self.snapshotRect(capture, bounds: web.bounds) else {
                capture["screenshot"] = Self.section(status: "unavailable", reason: "No visible crop, or native magnification is active")
                commit(capture, image: nil)
                return
            }
            let configuration = WKSnapshotConfiguration()
            configuration.rect = rect
            configuration.snapshotWidth = NSNumber(value: min(rect.width, 1_000))
            web.takeSnapshot(with: configuration) { [weak self] image, error in
                guard let self, self.current else { return }
                var payload = capture
                payload["snapshotAt"] = .string(ISO8601DateFormatter().string(from: Date()))
                payload["snapshotRect"] = .dictionary(["x": .number(rect.minX), "y": .number(rect.minY),
                    "width": .number(rect.width), "height": .number(rect.height), "coordinateSpace": .string("WKWebView points")])
                guard error == nil, let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    payload["screenshot"] = Self.section(status: "failed", reason: "WebKit snapshot unavailable")
                    self.commit(payload, image: nil)
                    return
                }
                Task { @MainActor [weak self] in
                    let data = await Task.detached(priority: .utility) { Self.png(cg) }.value
                    guard let self, self.current else { return }
                    payload["screenshot"] = Self.section(status: data == nil ? "failed" : "captured",
                        reason: data == nil ? "Snapshot exceeded encoding limits" : "Visible crop; pixels and DOM have separate timestamps")
                    self.commit(payload, image: data)
                }
            }
        } catch { fail("This element exceeded capture limits or could not be read") }
    }

    static func payload(_ value: Any) throws -> [String: ObjectValue] {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard data.count <= 256_000 else { throw WorkspaceError.tooLarge }
        let payload = try JSONDecoder().decode([String: ObjectValue].self, from: data)
        guard payload["title"]?.text != nil, case .dictionary(let geometry) = payload["geometry"],
              geometry["status"]?.text == "captured", case .dictionary = geometry["value"],
              case .dictionary = payload["dom"] else { throw WorkspaceError.invalid }
        return payload
    }

    static func snapshotRect(_ payload: [String: ObjectValue], bounds: CGRect) -> CGRect? {
        guard case .dictionary(let section) = payload["geometry"], case .dictionary(let g) = section["value"] else { return nil }
        func n(_ key: String) -> Double? { if case .number(let value) = g[key], value.isFinite { return value }; return nil }
        guard let x = n("x"), let y = n("y"), let w = n("width"), let h = n("height"),
              let vw = n("viewportWidth"), let vh = n("viewportHeight"), vw > 0, vh > 0,
              w > 0, h > 0, bounds.width > 0, bounds.height > 0 else { return nil }
        let sx = bounds.width / vw, sy = bounds.height / vh
        let crop = CGRect(x: bounds.minX + x * sx, y: bounds.minY + y * sy, width: w * sx, height: h * sy).intersection(bounds)
        return crop.isNull || crop.isEmpty ? nil : crop
    }

    private static func section(status: String, reason: String) -> ObjectValue {
        .dictionary(["status": .string(status), "reason": .string(reason), "value": .null])
    }

    nonisolated private static func png(_ cg: CGImage) -> Data? {
        guard cg.width <= 2_000, cg.height <= 4_000 else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination), data.length <= 4_000_000 else { return nil }
        return data as Data
    }

    private func commit(_ payload: [String: ObjectValue], image: Data?) {
        guard current, let browser else { cancel(); return }
        let store = WorkspaceStore.shared(for: space)
        let object = LocusObject(type: "uiCapture", title: payload["title"]?.text ?? "UI capture", content: payload)
        let existing = tab.flatMap { $0.wallObjectID(in: space) }.flatMap { id in store.snapshot.objects.first { $0.id == id } }
        let source = existing ?? LocusObject(type: "page", title: tab?.title ?? "Source page",
                                            content: ["url": payload["url"] ?? .string("")])
        let saved = store.addCapture(object, png: image, sourcePage: source, derivedFrom: predecessor)
        if saved, let tab { browser.bindWallPage(source.id, to: tab) }
        cancel()
        if saved { browser.openWall(); browser.announce("UI capture saved to Wall") }
        else { browser.announce(store.problem ?? "This Wall cannot be changed") }
    }

    private func cleanupPicker() {
        guard let web else { return }
        web.evaluateJavaScript("if(window.__locusCapture?.token === '\(token.uuidString)') window.__locusCapture.stop()", in: nil, in: Web.world) { _ in }
        web.configuration.userContentController.removeScriptMessageHandler(forName: Self.handler, contentWorld: Web.world)
    }
    func cancel() {
        guard !finished else { return }
        finished = true
        cleanupPicker()
        if tab?.uiCapture === self { tab?.uiCapture = nil }
        if browser?.uiCapture === self { browser?.uiCapture = nil; browser?.capturingUI = false }
    }
    private func fail(_ message: String) { browser?.announce(message); cancel() }
}

extension Browser {
    var canCaptureUI: Bool {
        canSavePageToWall && canOpenWall && active?.built != nil && active?.built?.isLoading == false
            && active?.built?.configuration.websiteDataStore.isPersistent == true
    }
    func startUICapture(picking: Bool = true, selector: String? = nil, derivedFrom: UUID? = nil) {
        uiCapture?.cancel()
        guard canCaptureUI else { announce("Load a normal web page before capturing UI"); return }
        if let derivedFrom {
            guard let capture = WorkspaceStore.shared(for: spaceID).snapshot.objects.first(where: { $0.id == derivedFrom }),
                  canRecaptureUI(capture) else { announce("Open and load the source page before capturing again"); return }
        }
        while closePanel() {}
        if peekTab != nil { closePeek() }
        closeAssistant()
        tabSwitcher.cancel()
        if veiling { toggleHiding() }
        dismiss()
        editing = false
        closeFind()
        reviewing = false
        dropChoice()
        bookmarksOpen = false
        guard let session = UICapture(browser: self, derivedFrom: derivedFrom) else { announce("Load a normal web page before capturing UI"); return }
        uiCapture = session
        capturingUI = true
        session.start(picking: picking, selector: selector)
    }
}
