import AppKit
import Combine
import WebKit

/// Built-in first-party extension; separate from installed WKWebExtensions.
@MainActor final class NightColors: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case automatic, always, off
        var id: String { rawValue }
        var title: String { switch self { case .automatic: return "Automatic"; case .always: return "Always adapt"; case .off: return "Off" } }
    }
    static let shared = NightColors(settings: Store.settings, liveRefresh: true)
    private let settings: UserDefaults
    private let liveRefresh: Bool
    @Published private(set) var enabled: Bool
    @Published private(set) var sites: [String: String]
    private var privateSites: [String: String] = [:]
    init(settings: UserDefaults, liveRefresh: Bool = false) {
        self.liveRefresh = liveRefresh; self.settings = settings; enabled = settings.bool(forKey: "night.enabled")
        sites = Dictionary(uniqueKeysWithValues: (settings.dictionary(forKey: "night.sites") as? [String: String] ?? [:]).filter { Self.validHost($0.key) && Mode(rawValue: $0.value) != nil }.prefix(1000).map { ($0.key, $0.value) })
    }
    static func host(_ url: URL?) -> String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased() else { return nil }
        let value = host.hasSuffix(".") ? String(host.dropLast()) : host
        return validHost(value) ? value : nil
    }
    static func originURL(scheme: String, host: String) -> URL? {
        guard ["http", "https"].contains(scheme), validHost(host) else { return nil }
        var parts = URLComponents(); parts.scheme = scheme; parts.host = host; return parts.url
    }
    private static func validHost(_ host: String) -> Bool { !host.isEmpty && host.count <= 253 && !host.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "\\" }) }
    func mode(for url: URL?, shy: Bool) -> Mode {
        guard let host = Self.host(url) else { return .automatic }
        return Mode(rawValue: (shy ? privateSites[host] : sites[host]) ?? "") ?? .automatic
    }
    func setEnabled(_ value: Bool) { guard value != enabled else { return }; enabled = value; settings.set(value, forKey: "night.enabled"); refreshTabs() }
    func setMode(_ mode: Mode, for url: URL?, shy: Bool) {
        guard let host = Self.host(url) else { return }
        if shy { guard privateSites.count < 1000 || privateSites[host] != nil || mode == .automatic else { return }; if mode == .automatic { privateSites[host] = nil } else { privateSites[host] = mode.rawValue } }
        else {
            guard sites.count < 1000 || sites[host] != nil || mode == .automatic else { return }
            if mode == .automatic { sites[host] = nil } else { sites[host] = mode.rawValue }
            settings.set(sites, forKey: "night.sites")
        }
        objectWillChange.send(); refreshTabs()
    }
    func resetSites() { sites = [:]; privateSites = [:]; settings.removeObject(forKey: "night.sites"); refreshTabs() }
    private func refreshTabs() {
        guard liveRefresh else { return }
        for browser in Browsers.all {
            for tab in browser.tabs + browser.parkedTabs where tab.built != nil && !tab.isWall {
                tab.refreshNightColors()
            }
        }
    }
    func configuration(shy: Bool, token: String, url: URL?) -> String {
        let policy: [String: Any] = ["enabled": enabled && Self.host(url) != nil, "mode": mode(for: url, shy: shy).rawValue, "dark": Favicons.dark, "token": token]
        let data = (try? JSONSerialization.data(withJSONObject: policy, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
    func script(for tab: Tab) -> String {
        let initial: [String: Any] = ["enabled": false, "mode": "automatic", "token": tab.nightToken]
        let data = try! JSONSerialization.data(withJSONObject: initial)
        return NightColor.script + "\n" + NightCSS.script + "\n" + NightPage.script + "\nglobalThis.__locusNight.update(" + String(decoding: data, as: UTF8.self) + "); globalThis.__locusNight.request();"
    }
    func apply(to tab: Tab) {
        guard let web = tab.built else { return }
        // callAsyncJavaScript keeps configuration values out of executable source.
        let json = configuration(shy: tab.shy, token: tab.nightToken, url: web.url)
        web.callAsyncJavaScript("if (globalThis.__locusNight) globalThis.__locusNight.update(JSON.parse(policy), true);", arguments: ["policy": json], in: nil, in: Web.world) { _ in }
    }
}

/// Frame identity is supplied by WebKit; page messages cannot choose a hostname.
/// Replies reveal only this frame's visual policy, never the site-choice list.
@MainActor final class NightPolicyRelay: NSObject, WKScriptMessageHandlerWithReply {
    static let name = "locusNightPolicy"
    weak var tab: Tab?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let tab, message.webView === tab.built else { replyHandler(["enabled": false, "mode": "automatic"], nil); return }
        let origin = message.frameInfo.securityOrigin
        let url = NightColors.originURL(scheme: origin.protocol, host: origin.host)
        let night = NightColors.shared
        replyHandler(["enabled": night.enabled && NightColors.host(url) != nil, "mode": night.mode(for: url, shy: tab.shy).rawValue, "dark": Favicons.dark], nil)
    }
}
