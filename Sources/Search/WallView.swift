import SwiftUI
import UniformTypeIdentifiers

/// Canvas controls live entirely inside the native Wall tab.
struct WallView: View {
    @ObservedObject var browser: Browser
    @ObservedObject var store: WorkspaceStore
    @ObservedObject private var vault: CanvasVault
    @StateObject private var canvas: CanvasController
    @State private var dialog: WallDialog?
    @State private var recovering = false
    @State private var deleting: LocusObject?
    @State private var failure: String?
    init(browser: Browser, store: WorkspaceStore) {
        self.browser = browser; self.store = store; self.vault = CanvasVault.shared(workspace: store.file)
        _canvas = StateObject(wrappedValue: CanvasController(store: store, window: browser.record.id))
    }
    var body: some View {
        ZStack {
            NativeCanvas(controller: canvas, store: store)
            if store.snapshot.placements.isEmpty {
                Text("Double-click to add a card").font(.system(size: 14)).foregroundStyle(Palette.muted).allowsHitTesting(false)
            }
            if !canvas.selected.isEmpty || !canvas.selectedEdges.isEmpty {
                GeometryReader { geometry in
                    selectionTools.position(x: min(geometry.size.width - 84, max(84, selectionCenter.x)), y: max(24, min(geometry.size.height - 72, selectionCenter.y)))
                }
            }
            VStack {
                HStack(alignment: .top) {
                    if let problem = store.problem ?? vault.problem {
                        HStack {
                            Text(problem).font(.system(size: 12))
                            if store.recovery != nil { Button("Recover Previous Wall…") { recovering = true } }
                        }.padding(10).background(Palette.ground, in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        Menu { settings } label: { Image(systemName: "gearshape") }.menuStyle(.borderlessButton).frame(width: 32, height: 32).background(Palette.ground, in: RoundedRectangle(cornerRadius: 5)).help("Canvas settings")
                        VStack(spacing: 0) {
                            tool("plus", "Zoom in") { canvas.zoom(1.2) }
                            tool("1.magnifyingglass", "Reset zoom") { canvas.reset() }
                            tool("arrow.up.left.and.arrow.down.right", "Zoom to fit · ⇧1") { canvas.fit() }
                            tool("minus", "Zoom out") { canvas.zoom(1 / 1.2) }
                        }.background(Palette.ground, in: RoundedRectangle(cornerRadius: 5))
                        VStack(spacing: 0) {
                            tool("arrow.uturn.backward", "Undo · ⌘Z", enabled: canvas.writable && store.canUndo) { canvas.undo() }
                            tool("arrow.uturn.forward", "Redo · ⇧⌘Z", enabled: canvas.writable && store.canRedo) { canvas.redo() }
                        }.background(Palette.ground, in: RoundedRectangle(cornerRadius: 5))
                        tool("questionmark", "Canvas help") { canvas.help.toggle() }.background(Palette.ground, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                Spacer()
                HStack(spacing: 2) {
                    tool("rectangle", "Add card", enabled: canvas.writable) { canvas.text(at: canvas.center) }
                        .onDrag { creationDrag("text") }
                    tool("doc.text", "Add note from Space", enabled: canvas.writable) { canvas.findObject(canvas.center) }
                        .onDrag { creationDrag("note") }
                    tool("photo", "Add media", enabled: canvas.writable) { CanvasFiles.choose(store: store, at: canvas.center) }
                        .onDrag { creationDrag("media") }
                }.padding(5).background(Palette.ground, in: RoundedRectangle(cornerRadius: 6))
            }.padding(16)
        }
        .foregroundStyle(Palette.ink).background(Palette.ground)
        .sheet(item: $dialog) { _ in WallDialogContent(dialog: $dialog, store: store, browser: browser) }
        .popover(isPresented: $canvas.help) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Canvas").font(.headline)
                Text("Double-click ground: add card\nDouble-click card: edit or open\nDrag ground: select · Shift: add to selection\nSpace-drag or middle-drag: pan\n⌘-scroll or pinch: zoom\nDrag a side dot: connect cards\nDrag any edge: resize · Shift: preserve ratio\nOption-drag: duplicate · Space: bypass snapping\n⇧1: fit all · ⇧2: fit selection\n⌘Z / ⇧⌘Z: undo / redo\nRight-click: more actions")
                    .font(.system(size: 12)).textSelection(.enabled)
            }.padding(20)
        }
        .alert("Recover previous Wall?", isPresented: $recovering) {
            Button("Recover") { _ = store.recoverPrevious() }; Button("Cancel", role: .cancel) {}
        } message: { Text("Restore the previous save. The damaged file will be preserved.") }
        .alert("Canvas", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button("OK") { failure = nil } } message: { Text(failure ?? "") }
        .alert("Delete “\(String((deleting?.title ?? "object").prefix(80)))”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Object", role: .destructive) { if let object = deleting { store.deleteObject(object.id) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("Delete this saved object from the Space and its \(store.snapshot.placements.filter { $0.objectID == deleting?.id }.count) cards and connections. Undo can restore the object.") }
        .onAppear {
            canvas.objectActions = { object in
                var items: [NSMenuItem] = []
                if object.type == "page" { items.append(WallMenuItem("Update from Live Tab", enabled: canvas.writable && browser.canUpdateWallPage(object)) { browser.updateWallPage(object) }) }
                if object.type == "uiCapture" { items.append(WallMenuItem("Recapture UI…", enabled: canvas.writable && browser.canRecaptureUI(object)) { browser.recaptureUI(object) }) }
                if object.type == "inspiration" { items.append(WallMenuItem("Edit Note…", enabled: canvas.writable) { dialog = .edit(object) }) }
                if object.type == "aiOutput" { items.append(WallMenuItem("Open Read Source") { browser.openAIReadSource(object) }) }
                if let url = object.url ?? object.content["url"]?.text.flatMap(URL.init(string:)).flatMap(SavedPageAddress.clean) {
                    items.append(WallMenuItem("Copy Source Address") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) })
                }
                items.append(WallMenuItem("Delete Saved Object…", enabled: canvas.writable) { deleting = object })
                return items
            }
            canvas.inspect = { dialog = .inspect($0) }
            canvas.openURL = { _ = browser.open($0, foreground: true) }
            canvas.open = { object in if object.type == "file" { CanvasFiles.open(object) } else { browser.openWallPage(object) } }
            canvas.addLink = { canvas.web(at: $0) }
            canvas.findObject = { dialog = .objects($0) }
            canvas.connections = { dialog = .connections($0) }
            canvas.files = { CanvasFiles.choose(store: store, at: $0) }
            DispatchQueue.main.async { reveal() }
        }
        .onChange(of: browser.wallReveal) { _, _ in reveal() }
        .onChange(of: canvas.readOnly) { _, _ in canvas.surface?.finishEditing(); canvas.remember() }
        .onDisappear {
            canvas.surface?.finishEditing(); canvas.remember(); dialog = nil; deleting = nil; canvas.selected = []; canvas.selectedEdges = []
            canvas.inspect = { _ in }; canvas.open = { _ in }; canvas.openURL = { _ in }; canvas.objectActions = { _ in [] }; canvas.connections = { _ in }; canvas.addLink = { _ in }; canvas.findObject = { _ in }; canvas.files = { _ in }
        }
        .accessibilityIdentifier("locus.wall")
    }
    private var selectionCenter: CGPoint {
        let cards = store.snapshot.placements.filter { canvas.selected.contains($0.id) }
        guard !cards.isEmpty else {
            if let edge = store.snapshot.wall.edges.compactMap(CanvasEdge.init).first(where: { canvas.selectedEdges.contains($0.id) }), let a = store.snapshot.placements.first(where: { $0.id == edge.from }), let b = store.snapshot.placements.first(where: { $0.id == edge.to }) {
                let point = CanvasCurve(from: a.rect, side: edge.fromSide, to: b.rect, toSide: edge.toSide).point(0.5)
                return CGPoint(x: point.x * canvas.viewport.zoom + canvas.viewport.x, y: point.y * canvas.viewport.zoom + canvas.viewport.y - 28)
            }
            return CGPoint(x: canvas.size.width / 2, y: 24)
        }
        let rect = cards.reduce(CGRect.null) { $0.union($1.rect) }
        return CGPoint(x: rect.midX * canvas.viewport.zoom + canvas.viewport.x, y: rect.minY * canvas.viewport.zoom + canvas.viewport.y - 28)
    }
    private var selectionTools: some View {
                    HStack(spacing: 4) {
                        Menu {
                            Button("Default color") { canvas.color(nil) }
                            ForEach(CanvasColor.presets, id: \.self) { color in
                                Button(CanvasColor.name(color)) { canvas.color(color) }
                            }
                            Divider()
                            Button("Custom color…") { canvas.surface?.chooseColor() }
                        } label: {
                            Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: CanvasColor.ns(selectionColor))).frame(width: 32, height: 32)
                        }.menuStyle(.borderlessButton).frame(width: 32).disabled(!canvas.writable).help("Set color").accessibilityLabel("Set color")
                        if let edge = store.snapshot.wall.edges.compactMap(CanvasEdge.init).first(where: { canvas.selectedEdges.contains($0.id) }) {
                            tool("pencil", "Edit connection label", enabled: canvas.writable) { canvas.surface?.editEdge(edge) }
                            Menu {
                                Button("No arrows") { canvas.arrows(source: false, target: false) }
                                Button("Arrow at target") { canvas.arrows(source: false, target: true) }
                                Button("Arrow at source") { canvas.arrows(source: true, target: false) }
                                Button("Arrows at both ends") { canvas.arrows(source: true, target: true) }
                            } label: { Image(systemName: "arrow.right").frame(width: 32, height: 32) }.menuStyle(.borderlessButton).frame(width: 32).disabled(!canvas.writable).help("Line endings")
                        }
                        if !canvas.selected.isEmpty {
                            tool("rectangle.3.group", "Create group", enabled: canvas.writable) { canvas.group(at: canvas.center) }
                        }
                        tool("trash", "Remove selection", enabled: canvas.writable) { canvas.remove() }
                    }.buttonStyle(.plain).padding(4).background(Palette.ground, in: RoundedRectangle(cornerRadius: 6))
    }
    private var selectionColor: String? {
        if let edge = store.snapshot.wall.edges.compactMap(CanvasEdge.init).first(where: { canvas.selectedEdges.contains($0.id) }) { return edge.color }
        return store.snapshot.placements.first(where: { canvas.selected.contains($0.id) })?.color
    }
    private func creationDrag(_ kind: String) -> NSItemProvider {
        let provider = NSItemProvider(); provider.registerDataRepresentation(forTypeIdentifier: "com.locus.canvas.new-card", visibility: .all) { complete in complete(Data(kind.utf8), nil); return nil }; return provider
    }
    private func tool(_ symbol: String, _ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14)).frame(width: 32, height: 32) }.buttonStyle(.plain).disabled(!enabled).help(title).accessibilityLabel(title)
    }
    @ViewBuilder private var settings: some View {
        Toggle("Snap to grid", isOn: $canvas.snapGrid).onChange(of: canvas.snapGrid) { _, _ in canvas.remember() }
        Toggle("Snap to objects", isOn: $canvas.snapObjects).onChange(of: canvas.snapObjects) { _, _ in canvas.remember() }
        Toggle("Read-only", isOn: $canvas.readOnly)
        Divider()
        Button(vault.connected ? "Reconnect vault…" : "Connect vault…") { vault.choose(window: canvas.surface?.window) }.disabled(!canvas.writable)
        if vault.connected {
            Toggle("Autosave vault notes", isOn: Binding(get: { vault.autosave }, set: { vault.setAutosave($0) })).disabled(!canvas.writable)
            Button("Add note from vault…") { vault.chooseNote(store: store, at: canvas.center, window: canvas.surface?.window) }.disabled(!canvas.writable)
            Button("Locate imported files in vault") { vault.bindImportedFiles(store: store) }.disabled(!canvas.writable)
            Button("Disconnect vault") { vault.disconnect() }.disabled(!canvas.writable)
            Divider()
        }
        Button("Add web page…") { canvas.web(at: canvas.center) }.disabled(!canvas.writable)
        Button("Save inspiration link…") { dialog = .link(canvas.center) }.disabled(!canvas.writable)
        Button("Find object…") { browser.searchWallObjects() }
        Button("Zoom to selection · ⇧2") { canvas.fit(selection: true) }.disabled(canvas.selected.isEmpty)
        Divider()
        Menu("Import") {
            Button("JSON Canvas…") { importCanvas() }
            Button("Portable folder…") { importCanvas(portable: true) }
        }.disabled(!canvas.writable)
        Menu("Export") {
            ForEach(CanvasExport.Format.allCases, id: \.rawValue) { format in Button(format.title) { exportCanvas(format) } }
            if !canvas.selected.isEmpty {
                Divider()
                Menu("Selection") { ForEach(CanvasExport.Format.allCases, id: \.rawValue) { format in Button(format.title) { exportCanvas(format, selection: true) } } }
            }
        }
        Divider()
        Button("Save source page") { browser.saveWallSourcePage() }.disabled(browser.wallSourceTab == nil || !canvas.writable)
        Button("Collect inspiration from page") { browser.collectWallSource() }.disabled(!browser.canCaptureWallSource || !canvas.writable)
        Button("Capture UI…") { browser.captureWallSource() }.disabled(!browser.canCaptureWallSource || !canvas.writable)
        Menu("Find inspiration") {
            ForEach(InspirationSource.allCases.filter { $0 != .web }, id: \.rawValue) { source in Button(source.title) { if let url = source.address { _ = browser.open(url, foreground: true) } } }
        }
    }
    private func reveal() {
        guard let id = browser.wallReveal, let card = store.snapshot.placements.first(where: { $0.objectID == id }) else { return }; canvas.go(to: card.id)
    }
    private func importCanvas(portable: Bool = false) {
        guard canvas.writable, let window = browser.window else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.canChooseDirectories = portable; panel.canChooseFiles = !portable
        if portable { panel.message = "Choose a portable Canvas folder containing Wall.canvas. Its referenced local assets will be connected; notes use manual saving unless you connect a vault." }
        else { panel.allowedContentTypes = [UTType(filenameExtension: "canvas") ?? .json] }
        let point = canvas.center
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                if portable {
                    let imported = try CanvasImport.portable(url, into: store, at: point)
                    canvas.selected = imported.selected
                    browser.announce(imported.unresolved == 0 ? (imported.previews == 0 ? "Canvas imported" : "Canvas imported with \(imported.previews) saved previews") : "Imported with \(imported.unresolved) unresolved file references")
                } else {
                    canvas.selected = try CanvasJSON.importData(CanvasFileDraft.read(url, limit: CanvasJSON.limit), into: store, at: point)
                }
                canvas.fit(selection: true)
            } catch { failure = error.localizedDescription }
        }
    }
    private func exportCanvas(_ format: CanvasExport.Format, selection: Bool = false) {
        guard let window = browser.window else { return }
        let snapshot = store.snapshot, selected: Set<UUID>? = selection ? canvas.expandedSelection() : nil
        let panel = NSSavePanel()
        panel.nameFieldStringValue = browser.space.name + (format == .portable ? "-export" : "." + (format == .json ? "canvas" : format.rawValue))
        if format != .portable { panel.allowedContentTypes = [format == .json ? (UTType(filenameExtension: "canvas") ?? .json) : format == .png ? .png : .pdf] }
        else { panel.message = "Choose a new folder name. Granted files and saved previews will be copied; unresolved references are listed in a manifest." }
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                if format == .portable {
                    let missing = try CanvasExport.portable(snapshot, store: store, selection: selected, to: url)
                    browser.announce(missing == 0 ? "Portable Canvas exported" : "Exported with \(missing) unresolved references — see manifest.json")
                } else {
                    let data = try format == .json ? CanvasJSON.export(snapshot, selection: selected) : CanvasExport.overview(snapshot, store: store, selection: selected, format: format)
                    try data.write(to: url, options: .atomic); browser.announce("Canvas exported")
                }
            } catch { failure = error.localizedDescription }
        }
    }
}

private enum WallDialog: Identifiable {
    case objects(CGPoint), newNote(CGPoint?), link(CGPoint?), edit(LocusObject), inspect(LocusObject), connections(LocusObject)
    var id: String {
        switch self {
        case .objects: return "objects"
        case .newNote: return "newNote"
        case .link: return "link"
        case .edit(let object): return "edit:\(object.id)"
        case .inspect(let object): return "inspect:\(object.id)"
        case .connections(let object): return "connections:\(object.id)"
        }
    }
}

private struct WallDialogContent: View {
    @Binding var dialog: WallDialog?
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var browser: Browser
    var body: some View {
        Group {
            switch dialog {
            case .objects(let point): CanvasObjectPicker(store: store, point: point) { dialog = nil }
            case .newNote(let point): WallNoteEditor(object: nil, at: point, store: store) { dialog = nil }
            case .edit(let object): WallNoteEditor(object: object, store: store) { dialog = nil }
            case .link(let point): InspirationLinkEditor(store: store, point: point) { dialog = nil }
            case .connections(let object): WallConnections(object: object, store: store) { dialog = nil }
            case .inspect(let object):
                if object.type == "uiCapture" { UICaptureInspector(object: object, store: store) { dialog = nil } }
                else { WallEvidenceInspector(object: object, store: store, browser: browser, edit: { dialog = .edit(object) }) { dialog = nil } }
            case nil: EmptyView()
            }
        }.id(dialog?.id)
    }
}

private struct WallNoteEditor: View {
    let object: LocusObject?
    let point: CGPoint?
    @ObservedObject var store: WorkspaceStore
    let close: () -> Void
    @State private var title: String
    @State private var text: String
    @State private var conflict = false
    @FocusState private var titleFocused: Bool
    private var emptyDraft: Bool {
        object == nil && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(object: LocusObject?, at point: CGPoint? = nil, store: WorkspaceStore, close: @escaping () -> Void) {
        self.object = object; self.point = point
        self.store = store; self.close = close
        _title = State(initialValue: object?.title ?? "")
        _text = State(initialValue: object?.text ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(object == nil ? "New note" : object?.type == "inspiration" ? "Edit inspiration note" : "Edit note")
                .font(.system(size: 15, weight: .medium))
            TextField("Title", text: $title).textFieldStyle(.roundedBorder).focused($titleFocused)
                .accessibilityLabel("Note title")
            Text("Note").font(.system(size: 12)).foregroundStyle(Palette.muted)
            TextEditor(text: $text).font(.system(size: 13)).frame(minHeight: 220)
                .accessibilityLabel("Note text")
            if conflict { Text("This object changed in another window. Reopen it before editing.").font(.system(size: 12)) }
            if let problem = store.problem { Text(problem).font(.system(size: 12)) }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save") {
                    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let nameOrDefault = name.isEmpty ? "Untitled" : name
                    let saved: Bool
                    if let object {
                        guard store.snapshot.objects.first(where: { $0.id == object.id }) == object else {
                            conflict = true; return
                        }
                        saved = object.type == "inspiration" ? store.editInspiration(object, title: nameOrDefault, text: text)
                            : store.editNote(object.id, title: nameOrDefault, text: text)
                    } else {
                        saved = store.add(LocusObject(type: "note", title: nameOrDefault, content: ["text": .string(text)]), at: point)
                    }
                    if saved { close() }
                }.keyboardShortcut(.defaultAction).disabled(!store.writable || conflict || emptyDraft)
            }
        }.padding(20).frame(width: 460).foregroundStyle(Palette.ink).background(Palette.ground)
            .onAppear { titleFocused = true }
    }
}

private struct CanvasObjectPicker: View {
    @ObservedObject var store: WorkspaceStore
    let point: CGPoint
    let close: () -> Void
    @State private var query = ""
    @FocusState private var focused: Bool
    private var objects: [LocusObject] {
        store.snapshot.objects.filter { $0.supported && $0.type != "group" && (query.isEmpty || $0.title.localizedStandardContains(query) || $0.text.localizedStandardContains(query)) }
            .sorted { a, b in a.type == "note" && b.type != "note" || a.type == b.type && a.title.localizedStandardCompare(b.title) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add note or object from Space").font(.headline)
            TextField("Search Space objects", text: $query).textFieldStyle(.roundedBorder).focused($focused)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(objects) { object in
                        Button { if store.addCanvasReference(object.id, at: point) != nil { close() } } label: {
                            HStack { Text(object.title).lineLimit(2); Spacer(); Text(object.kindTitle).foregroundStyle(Palette.muted) }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).disabled(!store.writable)
                    }
                    if objects.isEmpty { Text("No matching objects").foregroundStyle(Palette.muted).padding(16) }
                }
            }.frame(height: 260)
            HStack { if let problem = store.problem { Text(problem).font(.caption) }; Spacer(); Button("Cancel", action: close).keyboardShortcut(.cancelAction) }
        }.padding(20).frame(width: 420).onAppear { focused = true }
    }
}
