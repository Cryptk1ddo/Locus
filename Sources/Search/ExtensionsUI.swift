import SwiftUI
import WebKit

/// Settings › Extensions: what is installed, and the two ways in — a Chrome
/// Web Store link, or a folder.
struct ExtensionsPage: View {
    @ObservedObject var browser: Browser

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            NightColorsSettings(browser: browser)
            if #available(macOS 15.4, *) {
                Installer(browser: browser, extensions: .shared)
            } else {
                Card { Line("Chrome extensions", "Need macOS 15.4 or later — the version whose WebKit can run them.") { EmptyView() } }
            }
        }
    }

    @available(macOS 15.4, *)
    private struct Installer: View {
        @ObservedObject var browser: Browser
        @ObservedObject var extensions: Extensions
        @State private var link = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Add from the Chrome Web Store")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 8)
                            Pill("Open the Store") {
                                browser.tuning = false
                                browser.open(Browser.webStore, foreground: true)
                            }
                        }
                        HStack(spacing: 8) {
                            ZStack(alignment: .leading) {
                                if link.isEmpty {
                                    Text("Paste a link to an extension, or its id")
                                        .foregroundStyle(Palette.muted.opacity(0.8))
                                }
                                TextField("", text: $link)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(Palette.ink)
                                    .onSubmit(add)
                            }
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            if extensions.busy != nil {
                                Ring(size: 12)
                            } else {
                                Pill("Add", filled: true, action: add)
                                    .disabled(Crx.id(in: link) == nil)
                            }
                        }
                        Text("Or find it in the store and press Add to Search on its page.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                }

                Card {
                    Line("From another browser", "What Chrome, Arc, Brave and the others added from the Chrome Web Store — installed fresh from the store, you say yes to each one") {
                        Pill("Bring them over…") {
                            browser.tuning = false
                            browser.bringingExtensions = true
                            browser.bringingIn = ""
                        }
                    }
                }

                Card {
                    Line("Allow on private tabs", "Off by default - a private tab keeps nothing, extensions included") {
                        Switch(on: Binding(
                            get: { browser.prefs.extensionsInPrivate },
                            set: { browser.prefs.extensionsInPrivate = $0 }
                        ))
                    }
                }

                if extensions.installed.isEmpty {
                    Card { Nothing("No extensions yet.") }
                } else {
                    Card {
                        ForEach(Array(extensions.installed.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Rule() }
                            Row(item: item, extensions: extensions)
                        }
                    }
                }

                Recorders()

                Card {
                    Line("Load an unpacked extension", "A folder with a manifest.json — your own, or one exported from another browser. Reload picks up what you've changed in it since.") {
                        Pill("Choose…") { extensions.installFolder() }
                    }
                }
            }
        }

        private func add() {
            guard Crx.id(in: link) != nil else { return }
            extensions.install(from: link)
            link = ""
        }
    }

    /// The extensions you let record your screen, each one to take back.
    @available(macOS 15.4, *)
    private struct Recorders: View {
        @ObservedObject private var capture = ExtensionCapture.shared

        var body: some View {
            let ids = ExtensionCapture.allowedIDs
            if !ids.isEmpty {
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                            if index > 0 { Rule() }
                            Line(Browser.extensionName(id), "Can record your screen — macOS asks what to share each time") {
                                Pill("Remove") { ExtensionCapture.forget(id) }
                            }
                        }
                    }
                }
            }
        }
    }

    @available(macOS 15.4, *)
    private struct Row: View {
        let item: Installed
        @ObservedObject var extensions: Extensions
        @State private var hovering = false

        var body: some View {
            let context = extensions.contexts[item.id]
            HStack(spacing: 12) {
                Group {
                    if let icon = context?.webExtension.icon(for: CGSize(width: 32, height: 32)) {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "puzzlepiece.extension").foregroundStyle(Palette.muted)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(detail(context))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .help(item.source ?? "")
                }
                Spacer(minLength: 8)
                if hovering {
                    Quick(item.pinned == true ? "Unpin" : "Pin to Toolbar") {
                        extensions.setPinned(item.id, !(item.pinned ?? false))
                    }
                    if context?.overrideNewTabPageURL != nil {
                        let on = Store.settings.object(forKey: "extensions.newtab.\(item.id)") as? Bool == true
                        Quick(on ? "Stop in New Tabs" : "Show in New Tabs") {
                            Store.settings.set(!on, forKey: "extensions.newtab.\(item.id)")
                            extensions.objectWillChange.send()
                        }
                    }
                    if item.source != nil || !item.fromStore {
                        Quick("Reload") { extensions.reload(item.id) }
                    }
                    if context?.optionsPageURL != nil {
                        Quick("Options") { extensions.openOptions(item.id) }
                    }
                    Quick("Remove", tint: .red.opacity(0.75)) { extensions.remove(item.id) }
                }
                Switch(on: Binding(get: { item.enabled }, set: { extensions.setEnabled(item.id, $0) }))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(hovering ? Palette.hover : .clear)
            .onHover { hovering = $0 }
        }

        /// Where it was loaded from, by the folder's name — the whole path
        /// is in the tooltip.
        private var folder: String {
            item.source.map { "From “\(URL(fileURLWithPath: $0).lastPathComponent)”" } ?? "From a folder"
        }

        private func detail(_ context: WKWebExtensionContext?) -> String {
            var parts = ["Version \(item.version)", item.fromStore ? "Chrome Web Store" : folder]
            if item.enabled, context == nil { parts.append("couldn't start") }
            if context?.overrideNewTabPageURL != nil, Store.settings.object(forKey: "extensions.newtab.\(item.id)") as? Bool == true {
                parts.append("shows in new tabs")
            }
            if let errors = context?.errors, !errors.isEmpty { parts.append("\(errors.count) warning\(errors.count == 1 ? "" : "s")") }
            return parts.joined(separator: " · ")
        }
    }
}

/// On an extension's page in the Chrome Web Store, the offer to add it —
/// where the store's own button only says "Switch to Chrome".
struct StoreOffer: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if #available(macOS 15.4, *), let tab = browser.active {
            Watch(tab: tab, extensions: .shared)
        }
    }

    @available(macOS 15.4, *)
    private struct Watch: View {
        @ObservedObject var tab: Tab
        @ObservedObject var extensions: Extensions

        var body: some View {
            // Only where the page's own "Add to Search" isn't in place — a
            // store that has changed its markup still gets a way in.
            if let url = tab.address, let id = Crx.storeID(of: url),
               tab.storePlaced != id, !extensions.installed.contains(where: { $0.id == id }) {
                HStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    Text(extensions.busy == id ? "Adding…" : "Add this extension to Search")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.ink)
                    if extensions.busy == id {
                        Ring(size: 10)
                    } else {
                        Button("Add") { extensions.install(from: id) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.ground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Palette.ink, in: Capsule())
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .padding(.vertical, 9)
                .background(Palette.ground, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    static func isStorePage(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else { return false }
        let host = url.host()?.lowercased() ?? ""
        return host == "chromewebstore.google.com"
            || (host == "chrome.google.com" && url.path.hasPrefix("/webstore"))
    }
}

/// Built-in controls share Extensions settings without another toolbar button.
private struct NightColorsSettings: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var night = NightColors.shared
    private var tab: Tab? { browser.active }
    @State private var summary = ""
    private var summaryKey: String { "\(night.enabled):\(tab?.id.uuidString ?? ""):\(night.mode(for: tab?.pageAddress, shy: tab?.shy ?? false).rawValue):\(browser.prefs.look.rawValue)" }
    var body: some View {
        Card {
            VStack(spacing: 0) {
                Line("Night Colors · Built in", "Adapt page colors for the browser’s dark canvas. Automatic follows dark browser appearance and retains native dark sites. Photos and video keep their colors.") {
                    Switch(on: Binding(get: { night.enabled }, set: { night.setEnabled($0) }))
                }
                if night.enabled {
                    Rule()
                    if let tab, let host = NightColors.host(tab.pageAddress) {
                        Line(host, (summary.isEmpty ? "" : summary + " · ") + (tab.shy ? "This private site's choice lasts for this app session" : "This site's choice is remembered on this Mac")) {
                            Picker("Site mode", selection: Binding(get: { night.mode(for: tab.pageAddress, shy: tab.shy) }, set: { night.setMode($0, for: tab.pageAddress, shy: tab.shy) })) {
                                ForEach(NightColors.Mode.allCases) { mode in Text(mode.title).tag(mode) }
                            }.labelsHidden().frame(width: 140)
                        }
                    } else {
                        Line("Site controls", "Open a web page to choose Automatic, Always adapt or Off for its site") { EmptyView() }
                    }
                    Rule()
                    Line("Browser appearance", "Dark gives the page and browser the same canvas") {
                        Pill("Use Dark") { browser.prefs.look = .dark }
                    }
                    if !night.sites.isEmpty {
                        Rule()
                        Line("Site choices", "\(night.sites.count) remembered sites") { Pill("Reset") { night.resetSites() } }
                    }
                }
            }
        }.task(id: summaryKey) {
            guard night.enabled, let tab, let web = tab.built else { summary = ""; return }
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
            web.evaluateJavaScript("globalThis.__locusNight?.status()", in: nil, in: Web.world) { result in
                guard browser.active?.id == tab.id else { return }
                guard case .success(let value) = result, let status = value as? [String: Any] else { summary = "Loading page colors"; return }
                switch status["state"] as? String {
                case "native-dark": summary = "Native dark theme retained"
                case "waiting-dark": summary = "Waiting for dark appearance"
                case "adapted": summary = status["truncated"] as? Bool == true ? "Some page colors retain their original appearance" : "Night colors applied"
                case "error": summary = "Original page colors retained"
                case "disabled": summary = "Original page colors"
                default: summary = "Loading page colors"
                }
            }
        }
    }
}
