import AppKit
import SwiftUI
import Combine
import WebKit
import PDFKit
import AVKit

struct NativeCanvas: NSViewRepresentable {
    @ObservedObject var controller: CanvasController
    @ObservedObject var store: WorkspaceStore
    func makeNSView(context: Context) -> CanvasSurface { CanvasSurface(controller) }
    func updateNSView(_ view: CanvasSurface, context: Context) { view.scheduleUpdate() }
    static func dismantleNSView(_ view: CanvasSurface, coordinator: ()) { view.finishEditing(); view.shutdown(); view.controller.remember() }
}

/// Gesture state is transient. Only mouse-up writes the final geometry.
@MainActor
final class CanvasSurface: NSView, NSTextViewDelegate {
    let controller: CanvasController
    private var watching: [AnyCancellable] = []
    private var benchUpdates: [String: Int] = [:]
    private(set) var benchFileProbes = 0
    private(set) var benchLayoutPasses = 0
    private(set) var benchEdgeDecodes = 0
    func resetPerformanceCounters() { benchFileProbes = 0; benchLayoutPasses = 0; benchEdgeDecodes = 0; benchUpdates.removeAll() }
    var performanceCounters: [String: Int] { ["fileProbes": benchFileProbes, "layoutPasses": benchLayoutPasses, "edgeDecodes": benchEdgeDecodes].merging(benchUpdates) { _, new in new } }
    private enum Gesture {
        case pan(CGPoint, WallViewport)
        case marquee(CGPoint, Set<UUID>)
        case move(CGPoint, [WallPlacement], Bool)
        case resize(CGPoint, WallPlacement, Int, Int)
        case connect(UUID, CanvasSide, CGPoint)
        case reconnect(CanvasEdge, Bool, CGPoint)
    }
    private var gesture: Gesture?
    private var preview: [WallPlacement] = [] { didSet { renderCards = nil; renderIndex = nil } }
    private var renderRevision: Int?
    private var renderEdges: [CanvasEdge] = []
    private var renderObjects: [UUID: LocusObject] = [:]
    private var renderCards: [WallPlacement]?
    private var renderIndex: [UUID: WallPlacement]?
    private func synchronizeRender() {
        guard renderRevision != controller.store.snapshot.revision else { return }
        renderRevision = controller.store.snapshot.revision
        renderObjects = Dictionary(uniqueKeysWithValues: controller.store.snapshot.objects.map { ($0.id, $0) })
        renderCards = nil; renderIndex = nil
        if Store.testing { benchEdgeDecodes += 1 }
        renderEdges = controller.store.snapshot.wall.edges.compactMap(CanvasEdge.init)
    }
    private var marquee: CGRect?
    private var spaceHeld = false
    private var editor: NSScrollView?
    private let editorUndo = UndoManager()
    private var editing: (UUID, LocusObject)?
    private var editingEdge: CanvasEdge?
    private var fileDraft: CanvasFileDraft?
    private var fileEditBar: NSStackView?
    private var fileEditStatus: NSTextField?
    var fileEditorStatus: String? { fileEditStatus?.stringValue }
    private var autosaveTimer: Timer?
    private var autosaveBlocked = false
    private let monitorClientID = UUID()
    private var monitoring = false
    private var updatePending = false
    private var contentPending = false
    private var stopped = false
    private struct FileObservation { let bookmark: String; let watcher: CanvasFileWatcher? }
    private var fileObservations: [UUID: FileObservation] = [:]
    private var richRevision = 0
    private var readPreviews: [UUID: CanvasTextPreview] = [:]
    private var embeds: [UUID: CanvasWebEmbed] = [:]
    private var activeEmbed: UUID?
    private var filePreviews = CanvasResourceCache<NSImage>(costLimit: 64_000_000)
    private var fileTexts = CanvasResourceCache<String>(costLimit: 8_000_000)
    private var mediaView: NSView?
    private var mediaAccess: URL?
    private var mediaCard: UUID?
    private var hover: UUID?
    private var tracking: NSTrackingArea?
    private static weak var colorOwner: CanvasSurface?
    private var colorSelection: (Set<UUID>, Set<UUID>)?
    init(_ controller: CanvasController) {
        self.controller = controller; super.init(frame: .zero); controller.surface = self
        watching = [controller.objectWillChange.sink { [weak self] _ in self?.scheduleUpdate() },
                    controller.store.objectWillChange.sink { [weak self] _ in self?.scheduleUpdate(content: true, reason: "store") },
                    controller.vault.objectWillChange.sink { [weak self] _ in self?.scheduleUpdate(content: true, reason: "vault") }]
        watching.append(NotificationCenter.default.publisher(for: .canvasFilesChanged).sink { [weak self] _ in self?.scheduleUpdate(content: true, reason: "fileNotification") })
        watching.append(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification).sink { [weak self] note in
            guard let self, note.object as? NSWindow === self.window else { return }; self.scheduleUpdate(content: true, reason: "focus")
        })
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff, NSPasteboard.PasteboardType("com.locus.canvas.new-card")])
        setAccessibilityIdentifier("locus.canvas.surface")
        setAccessibilityLabel("Canvas")
        setAccessibilityRole(.group)
    }
    func scheduleUpdate(content: Bool = false, reason: String = "geometry") {
        if Store.testing { benchUpdates["request:" + reason, default: 0] += 1 }
        guard !stopped else { return }
        contentPending = contentPending || content
        guard !updatePending else { return }; updatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.updatePending = false
            if self.contentPending {
                self.richRevision += 1; self.fileTexts.removeAll(); self.filePreviews.removeAll(); self.contentPending = false
                self.fileObservations = self.fileObservations.filter { $0.value.watcher != nil }
            }
            if !self.controller.store.writable, self.monitoring { self.monitoring = false; self.controller.vault.releaseMonitor(self.monitorClientID); self.stopFileObservations() }
            self.needsDisplay = true; self.layoutEditor(); self.layoutEmbeds()
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, !monitoring, !stopped, controller.store.writable { monitoring = true; controller.vault.acquireMonitor(monitorClientID) }
        else if window == nil, monitoring { monitoring = false; controller.vault.releaseMonitor(monitorClientID); stopFileObservations() }
    }
    func shutdown() {
        stopped = true; watching.removeAll(); stopFileObservations()
        if monitoring { monitoring = false; controller.vault.releaseMonitor(monitorClientID) }
        autosaveTimer?.invalidate(); autosaveTimer = nil
        fileDraft?.retainForReopening(workspace: controller.store.file)
        for view in readPreviews.values { view.removeFromSuperview() }; readPreviews = [:]
        deactivateMedia(); for view in embeds.values { view.stopLoading(); view.removeFromSuperview() }; embeds = [:]
        if Self.colorOwner === self { NSColorPanel.shared.close(); NSColorPanel.shared.setTarget(nil); NSColorPanel.shared.setAction(nil); Self.colorOwner = nil }; colorSelection = nil
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool { spaceHeld = false; NSCursor.arrow.set(); return super.resignFirstResponder() }
    func releaseKey(_ event: NSEvent) { if event.keyCode == 49 { spaceHeld = false; NSCursor.arrow.set() } }
    override var mouseDownCanMoveWindow: Bool { false }
    override func layout() { super.layout(); controller.size = bounds.size; layoutEditor(); layoutEmbeds() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking!)
    }
    var cards: [WallPlacement] {
        synchronizeRender()
        if let renderCards { return renderCards }
        let changes = Dictionary(uniqueKeysWithValues: preview.map { ($0.id, $0) })
        let values = controller.store.snapshot.placements.map { changes[$0.id] ?? $0 }; renderCards = values; return values
    }
    private var objects: [UUID: LocusObject] { synchronizeRender(); return renderObjects }
    private var cardIndex: [UUID: WallPlacement] {
        synchronizeRender(); if let renderIndex { return renderIndex }
        let index = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) }); renderIndex = index; return index
    }
    private var edges: [CanvasEdge] { synchronizeRender(); return renderEdges }
    private func world(_ point: CGPoint) -> CGPoint { controller.viewport.worldPoint(point) ?? .zero }
    private func screen(_ point: CGPoint) -> CGPoint { point * controller.viewport.zoom + CGPoint(x: controller.viewport.x, y: controller.viewport.y) }
    private func screen(_ rect: CGRect) -> CGRect { CGRect(origin: screen(rect.origin), size: CGSize(width: rect.width * controller.viewport.zoom, height: rect.height * controller.viewport.zoom)) }
    private func point(_ event: NSEvent) -> CGPoint { world(convert(event.locationInWindow, from: nil)) }
    private func card(at point: CGPoint) -> WallPlacement? {
        // A group's interior is empty ground; only its frame/label receives clicks.
        cards.reversed().first { card in
            guard card.rect.insetBy(dx: -6 / controller.viewport.zoom, dy: -6 / controller.viewport.zoom).contains(point) else { return false }
            if objects[card.objectID]?.type == "group" {
                return !card.rect.insetBy(dx: 10 / controller.viewport.zoom, dy: 10 / controller.viewport.zoom).contains(point) || point.y < card.y + 28
            }
            return true
        }
    }
    private func curve(_ edge: CanvasEdge) -> CanvasCurve? {
        guard let a = cardIndex[edge.from], let b = cardIndex[edge.to] else { return nil }
        return CanvasCurve(from: a.rect, side: edge.fromSide, to: b.rect, toSide: edge.toSide)
    }
    private func edge(at point: CGPoint) -> CanvasEdge? {
        let margin = 9 / controller.viewport.zoom
        return edges.reversed().first { edge in
            guard let curve = curve(edge), curve.controlBounds.insetBy(dx: -margin, dy: -margin).contains(point) else { return false }
            return curve.distance(to: point) < margin
        }
    }
    private func drawText(_ text: String, rect: CGRect, font: NSFont = .systemFont(ofSize: 14), color: NSColor = Palette.NS.ink) {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
    override func draw(_ dirtyRect: NSRect) {
        Palette.NS.wash.setFill(); bounds.fill()
        let view = controller.viewport
        let step = max(12, 20 * view.zoom)
        guard let context = NSGraphicsContext.current else { return }
        context.cgContext.setFillColor(Palette.NS.faint.withAlphaComponent(0.5).cgColor)
        context.cgContext.beginPath()
        var x = view.x.truncatingRemainder(dividingBy: step)
        while x < bounds.width {
            var y = view.y.truncatingRemainder(dividingBy: step)
            while y < bounds.height { context.cgContext.addEllipse(in: CGRect(x: x, y: y, width: 1.3, height: 1.3)); y += step }
            x += step
        }
        context.cgContext.fillPath()
        context.saveGraphicsState()
        let transform = AffineTransform(translationByX: view.x, byY: view.y); (transform as NSAffineTransform).concat()
        let scale = AffineTransform(scale: view.zoom); (scale as NSAffineTransform).concat()
        let visible = CGRect(x: -view.x / view.zoom, y: -view.y / view.zoom, width: bounds.width / view.zoom, height: bounds.height / view.zoom).insetBy(dx: -100, dy: -100)
        for card in cards where objects[card.objectID]?.type == "group" && visible.intersects(card.rect) { drawCard(card) }
        for edge in edges {
            guard let curve = curve(edge), curve.controlBounds.insetBy(dx: -max(100, 10 / view.zoom), dy: -max(100, 10 / view.zoom)).intersects(visible) else { continue }
            let selected = controller.selectedEdges.contains(edge.id)
            (selected ? NSColor.controlAccentColor : (edge.color == nil ? Palette.NS.muted : CanvasColor.ns(edge.color))).setStroke(); let path = curve.path; path.lineWidth = (selected ? 3 : 2) / view.zoom; path.stroke()
            if edge.toArrow { arrow(at: curve.d, direction: curve.d - curve.c, color: edge.color == nil ? Palette.NS.muted : CanvasColor.ns(edge.color)) }
            if edge.fromArrow { arrow(at: curve.a, direction: curve.a - curve.b, color: edge.color == nil ? Palette.NS.muted : CanvasColor.ns(edge.color)) }
            if !edge.label.isEmpty {
                let p = curve.point(0.5), width = min(180, (edge.label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width + 16); let r = CGRect(x: p.x - width / 2, y: p.y - 13, width: width, height: 26)
                Palette.NS.wash.setFill(); NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill(); drawText(edge.label, rect: r.insetBy(dx: 7, dy: 4), font: .systemFont(ofSize: 12))
            }
            if selected { for p in [curve.a, curve.d] { handle(p) } }
        }
        for card in cards where objects[card.objectID]?.type != "group" && visible.intersects(card.rect) { drawCard(card) }
        if let gesture {
            switch gesture {
            case .connect(let id, let side, let end):
                if let card = cards.first(where: { $0.id == id }) { drawPending(from: side.point(on: card.rect), side: side, to: end) }
            case .reconnect(let edge, let from, let end):
                if let curve = curve(edge) { drawPending(from: from ? curve.d : curve.a, side: from ? edge.toSide : edge.fromSide, to: end) }
            default: break
            }
        }
        if let marquee {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill(); marquee.fill()
            NSColor.controlAccentColor.setStroke(); let path = NSBezierPath(rect: marquee); path.lineWidth = 1 / view.zoom; path.stroke()
        }
        context.restoreGraphicsState()
    }
    private func arrow(at p: CGPoint, direction: CGPoint, color: NSColor) {
        let length = max(0.001, hypot(direction.x, direction.y)), d = direction * (8 / controller.viewport.zoom / length)
        let normal = CGPoint(x: -d.y * 0.55, y: d.x * 0.55)
        let path = NSBezierPath(); path.move(to: p); path.line(to: p - d + normal); path.line(to: p - d - normal); path.close(); color.setFill(); path.fill()
    }
    private func handle(_ point: CGPoint) {
        let r = 5 / controller.viewport.zoom
        Palette.NS.ground.setFill(); let path = NSBezierPath(ovalIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)); path.fill(); NSColor.controlAccentColor.setStroke(); path.lineWidth = 1.5 / controller.viewport.zoom; path.stroke()
    }
    private func drawPending(from: CGPoint, side: CanvasSide, to: CGPoint) {
        let path = NSBezierPath(); path.move(to: from); path.curve(to: to, controlPoint1: from + side.direction * 80, controlPoint2: to); NSColor.controlAccentColor.setStroke(); path.lineWidth = 2 / controller.viewport.zoom; path.stroke()
    }
    private func drawCard(_ card: WallPlacement) {
        guard let object = objects[card.objectID] else { return }
        let selected = controller.selected.contains(card.id), group = object.type == "group"
        let path = NSBezierPath(roundedRect: card.rect, xRadius: 5, yRadius: 5)
        if group { CanvasColor.ns(card.color).withAlphaComponent(0.07).setFill() }
        else { Palette.NS.ground.setFill() }
        path.fill()
        if group, let image = filePreview(object) {
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            let style = object.content["backgroundStyle"]?.text ?? "cover"
            let ratio = style == "ratio" ? min(card.width / max(1, image.size.width), card.height / max(1, image.size.height)) : max(card.width / max(1, image.size.width), card.height / max(1, image.size.height))
            if style == "repeat" {
                NSGraphicsContext.current?.cgContext.setPatternPhase(CGSize(width: card.x, height: card.y))
                NSColor(patternImage: image).withAlphaComponent(0.6).setFill(); path.fill()
            } else { image.draw(in: CGRect(x: card.rect.midX - image.size.width * ratio / 2, y: card.rect.midY - image.size.height * ratio / 2, width: image.size.width * ratio, height: image.size.height * ratio), from: .zero, operation: .sourceOver, fraction: 0.6, respectFlipped: true, hints: nil) }
            NSGraphicsContext.restoreGraphicsState()
        }
        (selected ? NSColor.controlAccentColor : CanvasColor.ns(card.color)).setStroke(); path.lineWidth = (selected ? 2 : 1) / controller.viewport.zoom; path.stroke()
        let contentRect = card.rect.insetBy(dx: min(16, max(0, (card.width - 1) / 2)), dy: min(16, max(0, (card.height - 1) / 2)))
        if group { drawText(object.title, rect: CGRect(x: card.x + 12, y: card.y + 5, width: card.width - 24, height: 24), font: .systemFont(ofSize: 14, weight: .medium)) }
        else if editing?.0 != card.id && readPreviews[card.id] == nil {
            if !object.supported {
                drawText(object.title, rect: contentRect, font: .systemFont(ofSize: 15, weight: .medium))
                drawText("Object from a newer version", rect: CGRect(x: contentRect.minX, y: contentRect.minY + 40, width: contentRect.width, height: max(1, contentRect.height - 40)), font: .systemFont(ofSize: 12), color: Palette.NS.muted)
            } else if let image = WorkspaceImage.thumbnail(object, store: controller.store) ?? filePreview(object) {
                let ratio = min(contentRect.width / max(1, image.size.width), contentRect.height / max(1, image.size.height))
                let imageRect = CGRect(x: contentRect.midX - image.size.width * ratio / 2, y: contentRect.midY - image.size.height * ratio / 2, width: image.size.width * ratio, height: image.size.height * ratio)
                image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else if ["note", "aiOutput"].contains(object.type) {
                CanvasMarkdown.render(object.text.isEmpty ? "" : object.text).draw(with: contentRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            } else if object.type == "file", let text = fileText(object) {
                CanvasMarkdown.render(text).draw(with: contentRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            } else {
                drawText(object.title, rect: contentRect, font: .systemFont(ofSize: 15, weight: .medium))
                drawText(object.url?.absoluteString ?? object.content["file"]?.text ?? object.kindTitle, rect: CGRect(x: contentRect.minX, y: contentRect.minY + 45, width: contentRect.width, height: contentRect.height - 45), font: .systemFont(ofSize: 12), color: Palette.NS.muted)
            }
        }
        if !group && object.type != "note" { drawText(object.title, rect: CGRect(x: card.x + 4, y: card.y - 25, width: card.width - 8, height: 22), font: .systemFont(ofSize: 12), color: Palette.NS.muted) }
        if controller.writable && (selected || hover == card.id) {
            for side in CanvasSide.allCases { handle(side.point(on: card.rect)) }
        }
    }
    override func mouseMoved(with event: NSEvent) {
        let p = point(event); let card = card(at: p); hover = card?.id; needsDisplay = true
        if spaceHeld { NSCursor.openHand.set() }
        else if let card, controller.writable {
            let tolerance = 7 / controller.viewport.zoom
            if CanvasSide.allCases.contains(where: { $0.point(on: card.rect).distance(to: p) <= tolerance }) { NSCursor.crosshair.set() }
            else if abs(p.x - card.rect.minX) <= tolerance || abs(p.x - card.rect.maxX) <= tolerance { NSCursor.resizeLeftRight.set() }
            else if abs(p.y - card.rect.minY) <= tolerance || abs(p.y - card.rect.maxY) <= tolerance { NSCursor.resizeUpDown.set() }
            else { NSCursor.arrow.set() }
        } else { NSCursor.arrow.set() }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true; NSCursor.arrow.set() }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard finishEditing() else { return nil }; let p = point(event); return controller.menu(at: p, card: card(at: p), edge: edge(at: p))
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }; return }
        for view in readPreviews.values {
            if view.activateLink(at: view.convert(event.locationInWindow, from: nil), external: event.modifierFlags.contains(.command)) { return }
        }
        guard finishEditing() else { return }; deactivateMedia(); activeEmbed = nil; layoutEmbeds(); window?.makeFirstResponder(self)
        let p = point(event), local = convert(event.locationInWindow, from: nil), shift = event.modifierFlags.contains(.shift)
        if spaceHeld { gesture = .pan(local, controller.viewport); return }
        // Selected edge endpoint handles take priority over the underlying card.
        if controller.writable {
            for edge in edges where controller.selectedEdges.contains(edge.id) {
                if let curve = curve(edge) {
                    if curve.a.distance(to: p) < 9 / controller.viewport.zoom { gesture = .reconnect(edge, true, p); return }
                    if curve.d.distance(to: p) < 9 / controller.viewport.zoom { gesture = .reconnect(edge, false, p); return }
                }
            }
            for card in cards.reversed() where controller.selected.contains(card.id) || hover == card.id {
                if let side = CanvasSide.allCases.first(where: { $0.point(on: card.rect).distance(to: p) < 8 / controller.viewport.zoom }) {
                    gesture = .connect(card.id, side, p); return
                }
            }
        }
        if let card = card(at: p) {
            if event.clickCount == 2 {
                if ["note", "group"].contains(objects[card.objectID]?.type ?? "") { edit(card.id) }
                else if let object = objects[card.objectID], object.supported {
                    if object.type == "web", let embed = embeds[card.id] { activeEmbed = card.id; embed.interactive = true; window?.makeFirstResponder(embed) }
                    else if object.type == "file" { activateFile(card, object: object) }
                    else if object.type == "page" { controller.open(object) }
                    else if ["uiCapture", "inspiration", "aiOutput"].contains(object.type) { controller.inspect(object) }
                }
                return
            }
            controller.selectedEdges = []
            if shift { if controller.selected.contains(card.id) { controller.selected.remove(card.id) } else { controller.selected.insert(card.id) } }
            else if !controller.selected.contains(card.id) { controller.selected = [card.id] }
            guard controller.writable else { return }
            let r = card.rect, tolerance = 7 / controller.viewport.zoom
            let h = abs(p.x - r.minX) < tolerance ? -1 : abs(p.x - r.maxX) < tolerance ? 1 : 0
            let v = abs(p.y - r.minY) < tolerance ? -1 : abs(p.y - r.maxY) < tolerance ? 1 : 0
            if h != 0 || v != 0 { gesture = .resize(p, card, h, v) }
            else { gesture = .move(p, cards.filter { controller.expandedSelection().contains($0.id) }, event.modifierFlags.contains(.option)) }
        } else if let edge = edge(at: p) {
            controller.selected = []
            if shift && controller.selectedEdges.contains(edge.id) { controller.selectedEdges.remove(edge.id) }
            else { if !shift { controller.selectedEdges = [] }; controller.selectedEdges.insert(edge.id) }
            if event.clickCount == 2 { editEdge(edge) }
        } else {
            if event.clickCount == 2 { controller.text(at: p); return }
            let prior = shift ? controller.selected : []; controller.selected = prior; controller.selectedEdges = []
            gesture = .marquee(p, prior)
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let gesture else { return }
        let p = point(event), shift = event.modifierFlags.contains(.shift)
        switch gesture {
        case .pan(let start, let view):
            NSCursor.closedHand.set()
            let d = convert(event.locationInWindow, from: nil) - start
            controller.viewport = WallViewport(x: max(-1_000_000, min(1_000_000, view.x + d.x)), y: max(-1_000_000, min(1_000_000, view.y + d.y)), zoom: view.zoom)
        case .marquee(let start, let prior):
            let r = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y)); marquee = r
            controller.selected = prior.union(cards.filter { r.intersects($0.rect) }.map(\.id))
        case .move(let start, let original, _):
            let other = controller.snapObjects && !spaceHeld ? cards.filter { !controller.expandedSelection().contains($0.id) } : []
            preview = CanvasGeometry.moved(original, delta: p - start, constrained: shift, grid: controller.snapGrid && !spaceHeld, objects: other, zoom: controller.viewport.zoom)
        case .resize(let start, let card, let h, let v): preview = [CanvasGeometry.resized(card, horizontal: h, vertical: v, delta: p - start, aspect: shift, snap: controller.snapGrid && !spaceHeld)]
        case .connect(let id, let side, _): self.gesture = .connect(id, side, p)
        case .reconnect(let edge, let from, _): self.gesture = .reconnect(edge, from, p)
        }
        needsDisplay = true
    }
    private func isNavigationGesture(_ gesture: Gesture) -> Bool {
        switch gesture { case .pan, .marquee: return true; default: return false }
    }
    static func inView(_ view: NSView?) -> CanvasSurface? {
        guard let view else { return nil }; if let canvas = view as? CanvasSurface { return canvas }
        for child in view.subviews { if let canvas = inView(child) { return canvas } }; return nil
    }
    override func mouseUp(with event: NSEvent) {
        guard let gesture else { return }
        let p = point(event)
        if !controller.writable, !isNavigationGesture(gesture) { self.gesture = nil; preview = []; marquee = nil; needsDisplay = true; return }
        switch gesture {
        case .move(_, let originals, let duplicate):
            if !preview.isEmpty && preview != originals {
                if duplicate {
                    let delta = CGPoint(x: preview[0].x - originals[0].x, y: preview[0].y - originals[0].y)
                    if let ids = controller.store.duplicateCanvas(Set(originals.map(\.id)), offset: delta) { controller.selected = ids }
                } else { _ = controller.store.mutate { next in
                    let changes = Dictionary(uniqueKeysWithValues: self.preview.map { ($0.id, $0) })
                    let moved = next.placements.compactMap { changes[$0.id] }
                    next.placements.removeAll { changes[$0.id] != nil }; next.placements += moved
                } }
            }
        case .resize(_, let card, _, _): if !preview.isEmpty && preview != [card] { _ = controller.store.setCanvasCards(preview) }
        case .connect(let id, let side, let end):
            if let target = card(at: end) {
                if target.id != id { _ = controller.store.saveCanvasEdge(CanvasEdge(from: id, to: target.id, fromSide: side, toSide: CanvasSide.nearest(to: end, on: target.rect))) }
            } else if end.distance(to: side.point(on: cards.first(where: { $0.id == id })?.rect ?? .zero)) > 12 / controller.viewport.zoom { controller.text(at: end, connectedTo: (id, side)) }
        case .reconnect(var edge, let from, _):
            if let target = card(at: p), target.id != (from ? edge.to : edge.from) {
                if from { edge.from = target.id; edge.fromSide = CanvasSide.nearest(to: p, on: target.rect) }
                else { edge.to = target.id; edge.toSide = CanvasSide.nearest(to: p, on: target.rect) }
                _ = controller.store.saveCanvasEdge(edge)
            }
        case .pan: controller.remember()
        default: break
        }
        self.gesture = nil; preview = []; marquee = nil; needsDisplay = true
    }
    override func otherMouseDown(with event: NSEvent) { guard finishEditing() else { return }; window?.makeFirstResponder(self); gesture = .pan(convert(event.locationInWindow, from: nil), controller.viewport) }
    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { mouseUp(with: event) }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || spaceHeld { controller.zoom(exp(-Double(event.scrollingDeltaY) * 0.01), at: convert(event.locationInWindow, from: nil)) }
        else {
            let shift = event.modifierFlags.contains(.shift)
            controller.viewport.x += shift ? event.scrollingDeltaY : event.scrollingDeltaX
            controller.viewport.y += shift ? 0 : event.scrollingDeltaY
            controller.viewport.x = min(1_000_000, max(-1_000_000, controller.viewport.x)); controller.viewport.y = min(1_000_000, max(-1_000_000, controller.viewport.y)); controller.remember()
        }
    }
    override func magnify(with event: NSEvent) { controller.zoom(1 + Double(event.magnification), at: convert(event.locationInWindow, from: nil)) }
    static func owning(_ responder: NSResponder?) -> CanvasSurface? {
        var responder = responder
        while let current = responder { if let canvas = current as? CanvasSurface { return canvas }; responder = current.nextResponder }
        return nil
    }
    func take(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command), shift = event.modifierFlags.contains(.shift), chars = event.charactersIgnoringModifiers ?? ""
        if activeEmbed != nil || mediaView != nil {
            if event.keyCode == 53 { activeEmbed = nil; deactivateMedia(); layoutEmbeds(); window?.makeFirstResponder(self); return true }
            return false
        }
        if editor != nil {
            if cmd, chars.lowercased() == "z" {
                let history = (editor?.documentView as? NSTextView)?.undoManager ?? editorUndo
                if shift { if history.canRedo { history.redo() } }
                else if history.canUndo { history.undo() }
                if fileDraft != nil { textDidChange(Notification(name: NSText.didChangeNotification)) }
                return true
            }
            if fileDraft != nil, cmd, chars.lowercased() == "s" { saveFile(); return true }
            if fileDraft != nil, cmd, event.keyCode == 36 { if saveFile() { finishEditing() }; return true }
            if event.keyCode == 53 || (cmd && event.keyCode == 36) || (editing?.1.type == "group" && event.keyCode == 36) || (editingEdge != nil && event.keyCode == 36) { finishEditing(); return true }
            return false
        }
        if cmd {
            switch chars.lowercased() {
            case "a": controller.selected = Set(cards.map(\.id)); controller.selectedEdges = []; return true
            case "z": if shift { controller.redo() } else { controller.undo() }; return true
            case "c": copySelection(); return true
            case "x": if controller.writable { copySelection(); controller.remove() }; return true
            case "v": paste(at: controller.center); return true
            case "d": controller.duplicate(); return true
            case "+", "=": controller.zoom(1.2); return true
            case "-": controller.zoom(1 / 1.2); return true
            case "0": controller.reset(); return true
            default: return false
            }
        }
        if shift && event.keyCode == 18 { controller.fit(); return true }
        if shift && event.keyCode == 19 { controller.fit(selection: true); return true }
        if event.keyCode == 49 { spaceHeld = true; NSCursor.openHand.set(); return true }
        if event.keyCode == 53 { gesture = nil; preview = []; marquee = nil; controller.selected = []; controller.selectedEdges = []; return true }
        if event.keyCode == 51 || event.keyCode == 117 { controller.remove(); return true }
        if event.keyCode == 36, let id = controller.selected.first { edit(id); return true }
        if [123,124,125,126].contains(event.keyCode), controller.writable, !controller.selected.isEmpty {
            let amount: CGFloat = shift ? 20 : 1
            let delta = CGPoint(x: event.keyCode == 123 ? -amount : event.keyCode == 124 ? amount : 0, y: event.keyCode == 126 ? -amount : event.keyCode == 125 ? amount : 0)
            _ = controller.store.setCanvasCards(CanvasGeometry.moved(cards.filter { controller.expandedSelection().contains($0.id) }, delta: delta, constrained: false, grid: false)); return true
        }
        return false
    }
    override func keyDown(with event: NSEvent) { if !take(event) { super.keyDown(with: event) } }
    override func keyUp(with event: NSEvent) { if event.keyCode == 49 { releaseKey(event) } else { super.keyUp(with: event) } }
    private func filePreview(_ object: LocusObject) -> NSImage? {
        guard ["file", "group"].contains(object.type) else { return nil }
        let cached = filePreviews.lookup(object.id); if cached.found { return cached.value }
        if Store.testing { benchFileProbes += 1 }
        let value = CanvasFiles.preview(object)
        let pixels = value.map { $0.size.width * $0.size.height * 4 } ?? 0
        let cost = pixels.isFinite && pixels >= 0 ? Int(min(64_000_001, pixels)) : 64_000_001
        filePreviews.insert(value, for: object.id, cost: cost); return value
    }
    private func fileText(_ object: LocusObject) -> String? {
        let cached = fileTexts.lookup(object.id); if cached.found { return cached.value }
        if Store.testing { benchFileProbes += 1 }
        let value = CanvasFiles.text(object); fileTexts.insert(value, for: object.id, cost: value.map { max($0.utf8.count, $0.utf16.count * 2) } ?? 0); return value
    }
    private func stopFileObservations() { for entry in fileObservations.values { entry.watcher?.stop() }; fileObservations.removeAll() }
    private func observeVisibleFiles() {
        guard window != nil, !stopped, controller.store.writable else { stopFileObservations(); return }
        let visible = cards.filter { screen($0.rect).intersects(bounds) }.compactMap { objects[$0.objectID] }.filter { ["file", "group"].contains($0.type) && $0.content["bookmark"]?.text != nil }
        // Small fixed descriptor budget, regardless of total Wall size.
        let observed = Array(visible.prefix(32)), ids = Set(observed.map(\.id))
        for id in Array(fileObservations.keys) where !ids.contains(id) { fileObservations.removeValue(forKey: id)?.watcher?.stop() }
        for object in observed {
            guard let bookmark = object.content["bookmark"]?.text else { continue }
            if fileObservations[object.id]?.bookmark == bookmark { continue }
            fileObservations.removeValue(forKey: object.id)?.watcher?.stop()
            // An unobserved file may have changed while its card was offscreen.
            if fileTexts.lookup(object.id).found || filePreviews.lookup(object.id).found {
                fileTexts.remove(object.id); filePreviews.remove(object.id); richRevision += 1
            }
            let watcher = CanvasFiles.withURL(object) { url in CanvasFileWatcher(url: url) { [weak self] in
                Task { @MainActor in
                    guard let self, !self.stopped else { return }
                    self.fileObservations.removeValue(forKey: object.id)?.watcher?.stop()
                    self.scheduleUpdate(content: true, reason: "fileEvent")
                }
            } }
            fileObservations[object.id] = FileObservation(bookmark: bookmark, watcher: watcher)
        }
    }
    func layoutEmbeds() {
        if Store.testing { benchLayoutPasses += 1 }
        observeVisibleFiles()
        let visible = cards.filter { let rect = screen($0.rect); return rect.intersects(bounds) && rect.width <= 8192 && rect.height <= 8192 && objects[$0.objectID]?.type == "web" }
        let ids = Set(visible.map(\.id))
        for id in Array(embeds.keys) where !ids.contains(id) { embeds[id]?.stopLoading(); embeds[id]?.removeFromSuperview(); embeds[id] = nil }
        for card in visible {
            guard let object = objects[card.objectID], let url = object.url.flatMap(SavedPageAddress.clean) else { continue }
            let embed: CanvasWebEmbed
            if let existing = embeds[card.id] { embed = existing }
            else {
                // Bounded live previews; remaining cards keep their native placeholder.
                guard embeds.count < 8 else { continue }
                embed = CanvasWebEmbed(frame: .zero, configuration: Web.configuration(space: controller.store.snapshot.spaceID)); embed.navigationDelegate = embed; embed.customUserAgent = nil
                embeds[card.id] = embed; addSubview(embed); embed.load(URLRequest(url: url))
            }
            embed.frame = screen(card.rect.insetBy(dx: 2, dy: 2)); embed.interactive = activeEmbed == card.id
        }
        if let mediaCard, let card = cards.first(where: { $0.id == mediaCard }) {
            let frame = screen(card.rect.insetBy(dx: 2, dy: 2)); mediaView?.isHidden = frame.width > 8192 || frame.height > 8192
            if mediaView?.isHidden == false { mediaView?.frame = frame } else { (mediaView as? AVPlayerView)?.player?.pause() }
        }
        let accessibility = cards.filter { screen($0.rect).intersects(bounds) }.compactMap { card -> NSAccessibilityElement? in
            guard let window, let object = objects[card.objectID] else { return nil }
            let frame = window.convertToScreen(convert(screen(card.rect), to: nil))
            let element = NSAccessibilityElement(); element.setAccessibilityRole(.group); element.setAccessibilityFrame(frame); element.setAccessibilityLabel(object.title + ", " + object.kindTitle + (controller.selected.contains(card.id) ? ", selected" : "")); element.setAccessibilityParent(self); return element
        }
        setAccessibilityChildren(accessibility + subviews)
        let readable = cards.filter { let rect = screen($0.rect); return controller.selected.contains($0.id) && editing?.0 != $0.id && rect.intersects(bounds) && rect.width <= 8192 && rect.height <= 8192 }
        let readableIDs = Set(readable.map(\.id))
        for id in Array(readPreviews.keys) where !readableIDs.contains(id) { readPreviews[id]?.removeFromSuperview(); readPreviews[id] = nil }
        for card in readable {
            guard let object = objects[card.objectID], object.supported else { continue }
            let source: String?
            if ["note", "aiOutput"].contains(object.type) { source = object.text }
            else if object.type == "file" { source = fileText(object) } else { source = nil }
            guard let source else { continue }
            let view = readPreviews[card.id] ?? CanvasTextPreview(); readPreviews[card.id] = view; view.frame = screen(card.rect.insetBy(dx: 3, dy: 3)); view.objectID = object.id; view.openURL = controller.openURL
            view.renderRich = { [weak self] source, width in
                guard let self else { return CanvasMarkdown.render(source) }
                return CanvasRichMarkdown.render(source, object: object, snapshot: self.controller.store.snapshot, vault: self.controller.vault, width: width)
            }
            view.openReference = { [weak self] reference in self?.follow(reference, source: object) }
            view.toggleTask = { [weak self] offset, expected in
                guard let self, self.controller.writable, object.type == "note", let changed = CanvasDocument.togglingTask(expected, offset: offset) else { return }
                _ = self.controller.store.mutate { next in
                    guard let i = next.objects.firstIndex(where: { $0.id == object.id }), next.objects[i] == object, next.objects[i].text == expected else { throw WorkspaceError.unavailable }
                    next.objects[i].editNote(title: object.title, text: changed)
                }
            }
             if view.superview == nil { addSubview(view) }; view.update(source, zoom: controller.viewport.zoom, revision: richRevision)
        }
        if let editor { addSubview(editor, positioned: .above, relativeTo: nil) }
    }
    private func follow(_ reference: CanvasReference, source: LocusObject) {
        let known = reference.resolve(in: controller.store.snapshot, source: source)
        let resolved = known ?? controller.vault.object(reference.target, source: source)
        guard let object = resolved else {
            let alert = NSAlert(); alert.messageText = "Note not found"; alert.informativeText = "No unique note named “\(reference.target)” exists in this Space."
            if let window { alert.beginSheetModal(for: window) }; return
        }
        if known == nil {
            guard controller.writable else { CanvasFiles.open(object); return }
            let existing = self.controller.store.snapshot.objects.first { current in current.supported && current.type == "file" && CanvasFiles.withURL(current) { a in CanvasFiles.withURL(object) { b in CanvasFileDraft.sameFile(a, b) } } == true }
            if let existing, let card = cards.first(where: { $0.objectID == existing.id }) { controller.go(to: card.id); layoutEmbeds(); if let fragment = reference.fragment { readPreviews[card.id]?.reveal(fragment) }; return }
            if let existing {
                guard let id = controller.store.addCanvasReference(existing.id, at: controller.center) else { return }; controller.go(to: id); layoutEmbeds(); if let fragment = reference.fragment { readPreviews[id]?.reveal(fragment) }; return
            }
            guard controller.store.add(object, at: controller.center), let card = controller.store.snapshot.placements.last else { return }
            controller.go(to: card.id); layoutEmbeds(); if let fragment = reference.fragment { readPreviews[card.id]?.reveal(fragment) }; return
        }
        let id = cards.first(where: { $0.objectID == object.id })?.id ?? (controller.writable ? controller.store.addCanvasReference(object.id, at: controller.center) : nil)
        guard let id else { return }; controller.go(to: id); layoutEmbeds()
        if let fragment = reference.fragment { readPreviews[id]?.reveal(fragment) }
    }
    private func deactivateMedia() {
        (mediaView as? AVPlayerView)?.player?.pause(); mediaView?.removeFromSuperview(); mediaView = nil; mediaCard = nil
        mediaAccess?.stopAccessingSecurityScopedResource(); mediaAccess = nil
    }
    private func activateFile(_ card: WallPlacement, object: LocusObject) {
        guard object.supported else { return }
        if CanvasFiles.editable(object), controller.writable { edit(card.id); return }
        guard screen(card.rect).width <= 8192, screen(card.rect).height <= 8192 else { CanvasFiles.open(object); return }
        guard let encoded = object.content["bookmark"]?.text, let data = Data(base64Encoded: encoded) else { CanvasFiles.replace(object, store: controller.store); return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        if url.startAccessingSecurityScopedResource() { mediaAccess = url }
        if url.pathExtension.lowercased() == "pdf" { let pdf = PDFView(); pdf.document = PDFDocument(url: url); pdf.autoScales = true; mediaView = pdf }
        else if ["mp4", "mov", "m4v", "mp3", "m4a", "wav", "aiff"].contains(url.pathExtension.lowercased()) { let player = AVPlayerView(); player.player = AVPlayer(url: url); mediaView = player }
        else { CanvasFiles.open(object); mediaAccess?.stopAccessingSecurityScopedResource(); mediaAccess = nil; return }
        mediaCard = card.id; if let mediaView { addSubview(mediaView) }; layoutEmbeds()
    }
    func edit(_ id: UUID) {
        guard controller.writable, let card = cards.first(where: { $0.id == id }), let object = objects[card.objectID], object.supported, ["note", "group", "file"].contains(object.type) else { return }
        guard finishEditing() else { return }; controller.selected = [id]; controller.selectedEdges = []; editing = (id, object)
        if object.type == "file" {
            do {
                guard CanvasFiles.editable(object) else { throw CanvasFileEditError.unsupported }
                let bytes = CanvasFiles.withURL(object) { try? CanvasFileDraft.read($0) }
                let draft = try CanvasFileDraft.open(object: object, workspace: controller.store.file, original: bytes)
                fileDraft = draft; autosaveBlocked = draft.changed; beginEditor(draft.record.text); installFileEditBar()
            } catch { editing = nil; reportFileError(error); return }
        } else { beginEditor(object.type == "group" ? object.title : object.text) }
        layoutEditor()
    }
    func editEdge(_ edge: CanvasEdge) { guard controller.writable, finishEditing() else { return }; editingEdge = edge; beginEditor(edge.label); layoutEditor() }
    private func beginEditor(_ text: String) {
        editorUndo.removeAllActions()
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = true; scroll.backgroundColor = Palette.NS.ground
        let input = NSTextView(); input.delegate = self; input.isRichText = false; input.allowsUndo = true; input.font = .systemFont(ofSize: 14); input.textColor = Palette.NS.ink; input.backgroundColor = Palette.NS.ground; input.insertionPointColor = Palette.NS.ink; input.textContainerInset = CGSize(width: 8, height: 8); input.isVerticallyResizable = true; input.autoresizingMask = [.width]; input.textContainer?.widthTracksTextView = true; input.string = text; input.delegate = self
        input.setAccessibilityIdentifier("locus.canvas.editor"); scroll.documentView = input; editor = scroll; addSubview(scroll); window?.makeFirstResponder(input); input.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
    }
    func layoutEditor() {
        guard let editor else { return }
        if let editing, let card = cards.first(where: { $0.id == editing.0 }) {
            editor.frame = screen(editing.1.type == "group" ? CGRect(x: card.x + 8, y: card.y + 2, width: card.width - 16, height: 28) : card.rect.insetBy(dx: 8, dy: 8))
        } else if let edge = editingEdge, let curve = curve(edge) { let p = screen(curve.point(0.5)); editor.frame = CGRect(x: p.x - 100, y: p.y - 18, width: 200, height: 36) }
        if let bar = fileEditBar {
            let frame = editor.frame; bar.frame = CGRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
            editor.frame.size.height = max(0, frame.height - 30)
        }
        let clipped = editor.frame.intersection(bounds); editor.frame = clipped.isNull ? .zero : clipped
        (editor.documentView as? NSTextView)?.setFrameSize(CGSize(width: editor.contentSize.width, height: max(editor.contentSize.height, editor.documentView?.frame.height ?? 0)))
    }
    @discardableResult func finishEditing() -> Bool {
        guard let editor, let input = editor.documentView as? NSTextView else { return true }
        let text = input.string
        autosaveTimer?.invalidate(); autosaveTimer = nil
        if fileDraft != nil, !autosaveBlocked, let editing, controller.writable, controller.vault.canAutosave(editing.1), text != CanvasFileDraft.decode(fileDraft!.record.original) { _ = saveFile(automatic: true) }
        if let draft = fileDraft {
            do { try draft.pause(text) }
            catch { draft.retainForReopening(workspace: controller.store.file); reportFileError(error); return false }
            draft.retainForReopening(workspace: controller.store.file)
        }
        if fileDraft == nil, let editing, let current = objects[editing.1.id], text != (editing.1.type == "group" ? editing.1.title : editing.1.text) {
            _ = controller.store.mutate { next in
                guard current == editing.1, let i = next.objects.firstIndex(where: { $0.id == current.id }), next.objects[i] == current else { throw WorkspaceError.unavailable }
                next.objects[i].editNote(title: current.type == "group" ? String(text.prefix(300)) : String((text.split(separator: "\n").first.map(String.init) ?? "Untitled").prefix(300)), text: current.type == "group" ? current.text : text)
            }
        } else if var edge = editingEdge, text != edge.label { edge.label = String(text.prefix(300)); _ = controller.store.saveCanvasEdge(edge) }
        fileEditBar?.removeFromSuperview(); fileEditBar = nil; fileEditStatus = nil; fileDraft = nil
        editor.removeFromSuperview(); self.editor = nil; editing = nil; editingEdge = nil; window?.makeFirstResponder(self); layoutEmbeds(); needsDisplay = true; return true
    }
    private func installFileEditBar() {
        let message = autosaveBlocked ? "Recovered draft · Save to resume" : (editing.map { controller.vault.canAutosave($0.1) } == true ? "Autosave on" : "Draft · ⌘S to save")
        let label = NSTextField(labelWithString: message); label.font = .systemFont(ofSize: 10); label.lineBreakMode = .byTruncatingTail; fileEditStatus = label
        let save = NSButton(title: "Save", target: self, action: #selector(saveFileAction)); save.bezelStyle = .inline
        let more = NSPopUpButton(frame: .zero, pullsDown: true); more.bezelStyle = .inline
        more.addItem(withTitle: "•••"); more.setAccessibilityLabel("File draft actions")
        let copy = NSMenuItem(title: "Save copy…", action: #selector(saveFileCopy), keyEquivalent: ""); copy.target = self; more.menu?.addItem(copy)
        let discard = NSMenuItem(title: "Discard draft…", action: #selector(discardFileDraft), keyEquivalent: ""); discard.target = self; more.menu?.addItem(discard)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [label, save, more]); bar.orientation = .horizontal; bar.spacing = 8; bar.distribution = .fill
        fileEditBar = bar; addSubview(bar, positioned: .above, relativeTo: nil)
    }
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard fileDraft != nil, let replacementString else { return true }
        guard let range = Range(affectedCharRange, in: textView.string) else { return false }
        let next = textView.string.replacingCharacters(in: range, with: replacementString)
        guard next.utf8.count <= CanvasFileDraft.textLimit else { NSSound.beep(); return false }; return true
    }
    func undoManager(for view: NSTextView) -> UndoManager? { editorUndo }
    func textDidChange(_ notification: Notification) {
        guard let draft = fileDraft, let input = editor?.documentView as? NSTextView else { return }
        do { try draft.persist(input.string); fileEditStatus?.stringValue = autosaveBlocked ? "Draft kept · Save to resume" : "Draft kept"; fileEditStatus?.toolTip = nil; scheduleAutosave() }
        catch { fileEditStatus?.stringValue = "Draft not stored · Save copy"; fileEditStatus?.toolTip = error.localizedDescription }
    }
    private func scheduleAutosave() {
        autosaveTimer?.invalidate(); autosaveTimer = nil
        guard !autosaveBlocked, fileDraft?.changed == true, controller.writable, let editing, controller.vault.canAutosave(editing.1) else { return }
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in _ = self?.saveFile(automatic: true) }
    }
    private func reportFileError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "File could not be saved"; alert.informativeText = error.localizedDescription
        if let window, window.attachedSheet == nil { alert.beginSheetModal(for: window) }
    }
    @objc private func saveFileAction() { _ = saveFile() }
    @discardableResult private func saveFile(automatic: Bool = false) -> Bool {
        autosaveTimer?.invalidate(); autosaveTimer = nil
        if automatic { guard !autosaveBlocked, let editing, controller.vault.canAutosave(editing.1), fileDraft?.changed == true else { return false } }
        guard controller.writable, let draft = fileDraft, let editing, let input = editor?.documentView as? NSTextView,
              controller.store.snapshot.objects.first(where: { $0.id == editing.1.id }) == editing.1 else {
            autosaveBlocked = true
            if !automatic { reportFileError(CanvasFileEditError.conflict) }; return false
        }
        do {
            guard let saved = try CanvasFiles.withURL(editing.1, { url -> Bool? in try draft.save(to: url, text: input.string); return true }), saved else { throw CanvasFileEditError.unsupported }
            autosaveBlocked = false; fileEditStatus?.stringValue = automatic ? "Autosaved" : "Saved"; fileEditStatus?.toolTip = nil; NotificationCenter.default.post(name: .canvasFilesChanged, object: nil); fileTexts.removeAll(); filePreviews.removeAll(); layoutEmbeds(); needsDisplay = true; return true
        } catch { autosaveBlocked = true; fileEditStatus?.stringValue = "Save paused · Draft kept"; fileEditStatus?.toolTip = error.localizedDescription; if !automatic { reportFileError(error) }; return false }
    }
    @objc private func saveFileCopy() {
        guard let input = editor?.documentView as? NSTextView, let draft = fileDraft, let window else { return }
        let original = editing?.1
        let text = input.string, panel = NSSavePanel(); panel.nameFieldStringValue = editing?.1.title ?? "Draft.md"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                // A copy must never overwrite the original and bypass conflict checks.
                let isSource = original.flatMap { CanvasFiles.withURL($0) { CanvasFileDraft.sameFile($0, url) } } ?? false
                guard !isSource else { throw CanvasFileEditError.conflict }
                try draft.encodedText(text).write(to: url, options: .atomic)
                self?.fileEditStatus?.stringValue = "Copy saved · Original draft kept"
            } catch { self?.reportFileError(error) }
        }
    }
    @objc private func discardFileDraft() {
        guard let draft = fileDraft, let window else { return }
        let alert = NSAlert(); alert.messageText = "Discard this file draft?"; alert.informativeText = "The source file will stay as it is."; alert.addButton(withTitle: "Discard"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            do { try draft.discard(); (self?.editor?.documentView as? NSTextView)?.string = draft.record.text; self?.finishEditing() }
            catch { self?.reportFileError(error) }
        }
    }
    func chooseColor() {
        Self.colorOwner = self
        colorSelection = (controller.selected, controller.selectedEdges)
        let panel = NSColorPanel.shared; panel.isContinuous = false; panel.showsAlpha = false; panel.setTarget(self); panel.setAction(#selector(applyColor)); panel.orderFront(nil)
    }
    @objc private func applyColor(_ sender: NSColorPanel) {
        guard controller.writable, let selection = colorSelection, let color = sender.color.usingColorSpace(.sRGB) else { return }
        let hex = String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
        _ = controller.store.colorCanvas(cards: selection.0, edges: selection.1, color: hex)
    }
    func copySelection() {
        guard !controller.selected.isEmpty, let data = try? CanvasJSON.export(controller.store.snapshot, selection: controller.expandedSelection()) else { return }
        NSPasteboard.general.clearContents(); let envelope: [String: ObjectValue] = ["space": .string(controller.store.snapshot.spaceID.uuidString), "placements": .array(controller.expandedSelection().map { .string($0.uuidString) }), "canvas": .string(String(data: data, encoding: .utf8) ?? "")]
        NSPasteboard.general.setData(try? JSONEncoder().encode(envelope), forType: NSPasteboard.PasteboardType("com.locus.canvas.selection")); NSPasteboard.general.setString(String(data: data, encoding: .utf8) ?? "", forType: .string)
    }
    func paste(at point: CGPoint) {
        guard controller.writable else { return }
        let board = NSPasteboard.general
        if let data = board.data(forType: NSPasteboard.PasteboardType("com.locus.canvas.selection")) {
            if let fields = try? JSONDecoder().decode([String: ObjectValue].self, from: data), let canvas = fields["canvas"]?.text {
                if fields["space"]?.text == controller.store.snapshot.spaceID.uuidString, case .array(let values) = fields["placements"] {
                    let ids = Set(values.compactMap { $0.text.flatMap(UUID.init(uuidString:)) })
                    let current = cards.filter { ids.contains($0.id) }
                    if current.count == ids.count, let x = current.map(\.x).min(), let y = current.map(\.y).min(), let copied = controller.store.duplicateCanvas(ids, offset: CGPoint(x: point.x - x, y: point.y - y)) { controller.selected = copied; return }
                }
                if let ids = try? CanvasJSON.importData(Data(canvas.utf8), into: controller.store, at: point) { controller.selected = ids }
            }; return
        }
        if let urls = board.readObjects(forClasses: [NSURL.self]) as? [URL], urls.contains(where: \.isFileURL) { CanvasFiles.add(urls.filter(\.isFileURL), to: controller.store, at: point); return }
        if CanvasFiles.addImage(board, to: controller.store, at: point) { return }
        if let text = board.string(forType: .string) {
            if let url = URL(string: text), let clean = SavedPageAddress.clean(url) { _ = controller.store.add(LocusObject(type: "web", title: clean.host ?? "Web page", content: ["url": .string(clean.absoluteString)]), at: point) }
            else { _ = controller.store.add(LocusObject(type: "note", title: String(text.prefix(80)), content: ["text": .string(text)]), at: point) }
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { controller.writable ? .copy : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard controller.writable else { return false }; let point = world(convert(sender.draggingLocation, from: nil))
        if let kind = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("com.locus.canvas.new-card")) {
            switch kind { case "text": return controller.text(at: point) != nil; case "note": controller.findObject(point); return true; case "media": controller.files(point); return true; default: return false }
        }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        if urls.contains(where: \.isFileURL) { return CanvasFiles.add(urls.filter(\.isFileURL), to: controller.store, at: point) }
        if CanvasFiles.addImage(sender.draggingPasteboard, to: controller.store, at: point) { return true }
        if !urls.isEmpty {
            guard urls.count <= WallLinkDrop.limit else { return false }
            var seen: Set<String> = []
            let links = urls.compactMap(SavedPageAddress.clean).filter { seen.insert($0.absoluteString).inserted }.map { WallDroppedLink(url: $0, title: $0.host ?? "Web page") }
            return !links.isEmpty && controller.store.addDroppedLinks(links, at: point)
        }
        if let text = sender.draggingPasteboard.string(forType: .string) { return controller.store.add(LocusObject(type: "note", title: String(text.prefix(80)), content: ["text": .string(text)]), at: point) }
        return false
    }
}
