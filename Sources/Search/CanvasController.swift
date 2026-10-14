import SwiftUI
import AppKit

@MainActor
final class CanvasController: ObservableObject {
    let store: WorkspaceStore
    let vault: CanvasVault
    let windowID: UUID
    private let settings: UserDefaults
    @Published var selected: Set<UUID> = []
    @Published var selectedEdges: Set<UUID> = []
    @Published var viewport: WallViewport
    @Published var readOnly = false
    @Published var snapGrid = false
    @Published var snapObjects = true
    @Published var help = false
    var size = CGSize.zero
    weak var surface: CanvasSurface?
    var inspect: (LocusObject) -> Void = { _ in }
    var objectActions: (LocusObject) -> [NSMenuItem] = { _ in [] }
    var connections: (LocusObject) -> Void = { _ in }
    var openURL: (URL) -> Void = { _ in }
    var open: (LocusObject) -> Void = { _ in }
    var addLink: (CGPoint) -> Void = { _ in }
    var findObject: (CGPoint) -> Void = { _ in }
    var files: (CGPoint) -> Void = { _ in }
    private var key: String { "locus.canvas.options.\(windowID).\(store.snapshot.spaceID)" }
    var writable: Bool { store.writable && !readOnly }
    init(store: WorkspaceStore, window: UUID, settings: UserDefaults = Store.settings) {
        self.store = store; vault = CanvasVault.shared(workspace: store.file); windowID = window; self.settings = settings
        viewport = WallViewport.load(window: window, space: store.snapshot.spaceID, settings: settings)
        let key = "locus.canvas.options.\(window).\(store.snapshot.spaceID)"
        readOnly = settings.bool(forKey: key + ".readOnly")
        snapGrid = settings.bool(forKey: key + ".grid")
        snapObjects = settings.object(forKey: key + ".objects") as? Bool ?? true
    }
    func remember() {
        viewport.save(window: windowID, space: store.snapshot.spaceID, settings: settings)
        settings.set(readOnly, forKey: key + ".readOnly")
        settings.set(snapGrid, forKey: key + ".grid")
        settings.set(snapObjects, forKey: key + ".objects")
    }
    var center: CGPoint { viewport.worldPoint(CGPoint(x: size.width / 2, y: size.height / 2)) ?? .zero }
    func reset() { zoom(1 / viewport.zoom) }
    func fit(selection: Bool = false) {
        let cards = store.snapshot.placements.filter { !selection || selected.contains($0.id) }
        if let view = WallLayout.fit(cards, in: size) { viewport = view; remember() }
    }
    func zoom(_ factor: Double, at point: CGPoint? = nil) {
        let point = point ?? CGPoint(x: size.width / 2, y: size.height / 2)
        guard let world = viewport.worldPoint(point) else { return }
        let z = min(4, max(0.05, viewport.zoom * factor))
        viewport = WallViewport(x: max(-1_000_000, min(1_000_000, point.x - world.x * z)), y: max(-1_000_000, min(1_000_000, point.y - world.y * z)), zoom: z); remember()
    }
    func expandedSelection() -> Set<UUID> {
        var ids = selected
        let groups = Set(store.snapshot.objects.filter { $0.type == "group" }.map(\.id))
        for card in store.snapshot.placements where selected.contains(card.id) && groups.contains(card.objectID) {
            ids.formUnion(CanvasGeometry.contained(in: card, placements: store.snapshot.placements))
        }
        return ids
    }
    @discardableResult func text(at point: CGPoint, connectedTo source: (UUID, CanvasSide)? = nil) -> UUID? {
        guard writable else { return nil }
        let object = LocusObject(type: "note", title: "Untitled", content: ["text": .string("")])
        let card = WallPlacement(objectID: object.id, x: point.x, y: point.y, width: 300, height: 200)
        guard store.mutate({ next in
            next.objects.append(object); next.placements.append(card)
            if let source { next.wall.edges.append(CanvasEdge(from: source.0, to: card.id, fromSide: source.1).value) }
        }) else { return nil }
        selected = [card.id]; selectedEdges = []; surface?.edit(card.id); return card.id
    }
    func web(at point: CGPoint) {
        guard writable, let window = surface?.window else { return }
        surface?.finishEditing()
        let alert = NSAlert(); alert.messageText = "Add web page"; alert.informativeText = "Enter the page's URL."; alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 360, height: 24)); field.placeholderString = "https://"; field.setAccessibilityLabel("Web page URL"); alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn, self.writable, let url = URL(string: field.stringValue), let url = SavedPageAddress.clean(url) else { return }
            _ = self.store.add(LocusObject(type: "web", title: url.host ?? url.absoluteString, content: ["url": .string(url.absoluteString)]), at: point)
        }
    }
    func group(at point: CGPoint) {
        guard writable, let id = store.addCanvasGroup(enclosing: selected, at: point) else { return }
        selected = [id]; selectedEdges = []
    }
    func remove() {
        guard writable, !selected.isEmpty || !selectedEdges.isEmpty else { return }
        if store.removeCanvasSelection(cards: selected, edges: selectedEdges) { selected = []; selectedEdges = [] }
    }
    func duplicate() {
        guard writable, let ids = store.duplicateCanvas(expandedSelection()) else { return }
        selected = ids; selectedEdges = []
    }
    func color(_ value: String?) {
        guard writable else { return }; _ = store.colorCanvas(cards: selected, edges: selectedEdges, color: value)
    }
    func arrows(source: Bool, target: Bool) {
        guard writable else { return }
        _ = store.mutate { next in
            for i in next.wall.edges.indices {
                if var edge = CanvasEdge(next.wall.edges[i]), self.selectedEdges.contains(edge.id) { edge.fromArrow = source; edge.toArrow = target; next.wall.edges[i] = edge.value }
            }
        }
    }
    func undo() { guard writable else { return }; guard surface?.finishEditing() != false else { return }; _ = store.undoCanvas(); selected = []; selectedEdges = [] }
    func redo() { guard writable else { return }; guard surface?.finishEditing() != false else { return }; _ = store.redoCanvas(); selected = []; selectedEdges = [] }
    func go(to id: UUID) {
        guard let card = store.snapshot.placements.first(where: { $0.id == id }) else { return }
        selected = [id]; selectedEdges = []; viewport = WallViewport(x: max(-1_000_000, min(1_000_000, size.width / 2 - card.rect.midX * viewport.zoom)), y: max(-1_000_000, min(1_000_000, size.height / 2 - card.rect.midY * viewport.zoom)), zoom: viewport.zoom); remember()
    }
    func menu(at point: CGPoint, card: WallPlacement?, edge: CanvasEdge?) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        func item(_ title: String, enabled: Bool = true, _ action: @escaping () -> Void) { menu.addItem(WallMenuItem(title, enabled: enabled, act: action)) }
        if let edge {
            selected = []; selectedEdges = [edge.id]
            item("Edit label", enabled: writable) { self.surface?.editEdge(edge) }
            item("Go to source") { self.go(to: edge.from) }
            item("Go to target") { self.go(to: edge.to) }
            item(edge.fromArrow ? "Remove source arrow" : "Add source arrow", enabled: writable) { var changed = edge; changed.fromArrow.toggle(); _ = self.store.saveCanvasEdge(changed) }
            item(edge.toArrow ? "Remove target arrow" : "Add target arrow", enabled: writable) { var changed = edge; changed.toArrow.toggle(); _ = self.store.saveCanvasEdge(changed) }
            item("Reverse direction", enabled: writable) {
                var changed = edge; swap(&changed.from, &changed.to); swap(&changed.fromSide, &changed.toSide); _ = self.store.saveCanvasEdge(changed)
            }
        } else if let card {
            if !selected.contains(card.id) { selected = [card.id] }; selectedEdges = []
            if let object = store.snapshot.objects.first(where: { $0.id == card.objectID }) {
                if object.supported && (["note", "group"].contains(object.type) || (CanvasFiles.editable(object))) { item(object.type == "group" ? "Rename group" : "Edit", enabled: writable) { self.surface?.edit(card.id) } }
                else { if object.supported && (object.url != nil || object.type == "file") { item("Open") { self.open(object) } }; if object.supported && ["uiCapture", "inspiration", "aiOutput"].contains(object.type) { item("Inspect") { self.inspect(object) } } }
                for action in objectActions(object).filter({ object.supported || $0.title == "Delete Saved Object…" }) { menu.addItem(action) }
                if object.supported && object.type == "group" {
                    item("Set background…", enabled: writable) { CanvasFiles.background(object, store: self.store) }
                    for style in ["cover", "ratio", "repeat"] {
                        item("Background: " + style.capitalized, enabled: writable) {
                            _ = self.store.mutate { next in
                                guard let i = next.objects.firstIndex(where: { $0.id == object.id }), next.objects[i] == object else { throw WorkspaceError.unavailable }
                                var fields = object.fields, content = object.content; content["backgroundStyle"] = .string(style); fields["content"] = .dictionary(content)
                                next.objects[i] = try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))
                            }
                        }
                    }
                }
                item("Knowledge connections…", enabled: object.supported) { self.connections(object) }
                if object.supported && object.type == "note" { item(vault.connected ? "Save note to vault…" : "Convert to file…", enabled: writable) { CanvasFiles.convert(object, store: self.store) } }
                if object.supported && object.type == "file" { item("Swap file…", enabled: writable) { CanvasFiles.replace(object, store: self.store) } }
                item("Copy") { self.surface?.copySelection() }
                item("Duplicate", enabled: writable) { self.duplicate() }
                item("Create group", enabled: writable) { self.group(at: point) }
            }
        } else {
            item("Add card", enabled: writable) { self.text(at: point) }
            item("Add note from Space", enabled: writable) { self.findObject(point) }
            item("Add media", enabled: writable) { self.files(point) }
            item("Add web page", enabled: writable) { self.addLink(point) }
            item("Create group", enabled: writable) { self.selected = []; self.group(at: point) }
            item("Paste", enabled: writable) { self.surface?.paste(at: point) }
            menu.addItem(.separator())
            for (title, checked, action) in [("Snap to grid", snapGrid, { self.snapGrid.toggle(); self.remember() }), ("Snap to objects", snapObjects, { self.snapObjects.toggle(); self.remember() }), ("Read-only", readOnly, { self.readOnly.toggle(); self.remember() })] {
                let entry = WallMenuItem(title, act: action); entry.state = checked ? .on : .off; menu.addItem(entry)
            }
            item("Zoom to fit") { self.fit() }
            return menu
        }
        let colors = NSMenu()
        for value in [nil] + CanvasColor.presets.map(Optional.some) { colors.addItem(WallMenuItem(CanvasColor.name(value), enabled: writable) { self.color(value) }) }
        colors.addItem(WallMenuItem("Custom…", enabled: writable) { self.surface?.chooseColor() })
        let entry = NSMenuItem(title: "Set color", action: nil, keyEquivalent: ""); entry.submenu = colors; menu.addItem(entry)
        menu.addItem(.separator()); item("Remove", enabled: writable) { self.remove() }
        return menu
    }
}
