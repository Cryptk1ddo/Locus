import AppKit
import ImageIO

/// Snapshot-only exports. Imported file paths never authorize asset reads.
@MainActor enum CanvasExport {
    enum Format: String, CaseIterable { case json, portable, png, pdf
        var title: String { switch self { case .json: return "JSON Canvas…"; case .portable: return "Portable folder…"; case .png: return "PNG overview…"; case .pdf: return "PDF overview…" } }
    }
    enum Failure: LocalizedError {
        case empty, destinationExists, tooLarge, writeFailed
        var errorDescription: String? { switch self { case .empty: return "Add or select cards before exporting."; case .destinationExists: return "Choose a new folder name; an existing export will not be replaced."; case .tooLarge: return "This export exceeds the asset or image size limit. Export a smaller selection."; case .writeFailed: return "The portable folder could not be written. Choose another destination." } }
    }
    static let assetLimit = 20_000_000, totalLimit = 100_000_000, countLimit = 200
    static func cards(_ snapshot: WorkspaceSnapshot, selection: Set<UUID>?) throws -> [WallPlacement] {
        let cards = snapshot.placements.filter { selection == nil || selection!.contains($0.id) }
        guard !cards.isEmpty else { throw Failure.empty }; return cards
    }
    static func owned(_ object: LocusObject, store: WorkspaceStore) throws -> Data? {
        guard let id = object.snapshotID else { return nil }
        try WorkspaceFiles.checkPath(store.assetURL(id)); let data = try CanvasFileDraft.read(store.assetURL(id), limit: 4_000_000)
        guard WorkspaceImage.validPNG(data), object.snapshotIntegrity["sha256"].map({ $0 == .string(WorkspaceImage.digest(data)) }) ?? true,
              object.snapshotIntegrity["bytes"].map({ $0 == .number(Double(data.count)) }) ?? true else { throw WorkspaceError.invalid }
        return data
    }
    @discardableResult static func portable(_ snapshot: WorkspaceSnapshot, store: WorkspaceStore, selection: Set<UUID>? = nil, to destination: URL) throws -> Int {
        let vault = CanvasVault.shared(workspace: store.file)
        if let result = try vault.withRoot({ root in
            try writePortable(snapshot, store: store, selection: selection, to: destination, vault: vault, root: root)
        }) { return result }
        return try writePortable(snapshot, store: store, selection: selection, to: destination, vault: vault, root: nil)
    }
    private static func writePortable(_ snapshot: WorkspaceSnapshot, store: WorkspaceStore, selection: Set<UUID>?, to destination: URL, vault: CanvasVault, root: URL?) throws -> Int {
        let cards = try cards(snapshot, selection: selection), objects = Dictionary(uniqueKeysWithValues: snapshot.objects.map { ($0.id, $0) })
        try WorkspaceFiles.checkPath(destination); guard !WorkspaceFiles.exists(destination) else { throw Failure.destinationExists }
        let fm = FileManager.default, staging = destination.deletingLastPathComponent().appendingPathComponent(".locus-export-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: staging.appendingPathComponent("assets"), withIntermediateDirectories: true); defer { try? fm.removeItem(at: staging) }
        var document = try JSONDecoder().decode([String: ObjectValue].self, from: CanvasJSON.export(snapshot, selection: selection))
        guard case .array(var nodes) = document["nodes"], nodes.count == cards.count else { throw WorkspaceError.invalid }
        var unresolved: [ObjectValue] = [], previews: [ObjectValue] = [], directFiles: Set<String> = []
        let files = CanvasPortableFiles(staging: staging, snapshot: snapshot, vault: vault, root: root)
        for (index, card) in cards.enumerated() {
            guard let object = objects[card.objectID], case .dictionary(var node) = nodes[index] else { throw WorkspaceError.invalid }
            let nodeID = node["id"] ?? .string(card.id.uuidString)
            if ["file", "group"].contains(object.type) {
                let key = object.type == "file" ? "file" : "background"
                if node[key]?.text != nil {
                    do {
                        let path = try files.file(object)
                        if let path { node[key] = .string(path); directFiles.insert(path) }
                        else { unresolved.append(.dictionary(["node": nodeID, "reference": node[key]!, "reason": .string("No file access grant")])) }
                    } catch let error as Failure { throw error }
                    catch CanvasFileEditError.tooLarge { throw Failure.tooLarge }
                    catch { unresolved.append(.dictionary(["node": nodeID, "reference": node[key]!, "reason": .string("File unavailable")])) }
                }
            } else if ["note", "aiOutput"].contains(object.type) {
                node["text"] = .string(try files.note(object.text, object: object, node: nodeID))
            } else if object.snapshotID != nil {
                do {
                    if let data = try owned(object, store: store) {
                        let path = try files.saved(data, object: object)
                        previews.append(.dictionary(["node": nodeID, "file": .string(path), "title": .string(object.title)]))
                        if object.type == "uiCapture" { node["type"] = .string("file"); node["file"] = .string(path); node.removeValue(forKey: "text") }
                    }
                } catch let error as Failure { throw error }
                catch { unresolved.append(.dictionary(["node": nodeID, "reason": .string("Saved preview unavailable")])) }
            }
            nodes[index] = .dictionary(node)
        }
        unresolved += files.unresolved
        document["nodes"] = .array(nodes)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(document); guard data.count <= CanvasJSON.limit else { throw Failure.tooLarge }
        try data.write(to: staging.appendingPathComponent("Wall.canvas"))
        let manifest: [String: ObjectValue] = ["version": .number(1), "assets": .number(Double(files.count)), "bytes": .number(Double(files.total)), "unresolved": .array(unresolved), "previews": .array(previews), "dependencies": .array(files.filePaths.subtracting(directFiles).sorted().map(ObjectValue.string))]
        let manifestData = try encoder.encode(manifest); guard manifestData.count <= 256_000 else { throw Failure.tooLarge }
        try manifestData.write(to: staging.appendingPathComponent("manifest.json"))
        // Rename publishes the complete folder; a concurrent existing destination fails.
        try fm.moveItem(at: staging, to: destination); return unresolved.count
    }
    static func overview(_ snapshot: WorkspaceSnapshot, store: WorkspaceStore, selection: Set<UUID>? = nil, format: Format) throws -> Data {
        let cards = try cards(snapshot, selection: selection)
        var bounds = cards.reduce(CGRect.null) { $0.union($1.rect) }.insetBy(dx: -40, dy: -60)
        let index = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        for edge in snapshot.wall.edges.compactMap(CanvasEdge.init) {
            guard let a = index[edge.from], let b = index[edge.to] else { continue }
            let curve = CanvasCurve(from: a.rect, side: edge.fromSide, to: b.rect, toSide: edge.toSide)
            for p in [curve.a, curve.b, curve.c, curve.d] { bounds = bounds.union(CGRect(x: p.x - 30, y: p.y - 30, width: 60, height: 60)) }
            if !edge.label.isEmpty { let p = curve.point(0.5); bounds = bounds.union(CGRect(x: p.x - 110, y: p.y - 30, width: 220, height: 60)) }
        }
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0, bounds.width <= 100_000, bounds.height <= 100_000 else { throw Failure.tooLarge }
        let scale = min(1, 4096 / max(bounds.width, bounds.height), sqrt(12_000_000 / (bounds.width * bounds.height)))
        let view = CanvasExportView(snapshot: snapshot, cards: cards, store: store, world: bounds, scale: scale)
        if format == .pdf { return view.dataWithPDF(inside: view.bounds) }
        guard format == .png, let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap) else { throw WorkspaceError.invalid }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let cg = bitmapContext.cgContext; cg.translateBy(x: 0, y: view.bounds.height); cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true); view.draw(view.bounds)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw WorkspaceError.invalid }; return data
    }
}

/// Static export renderer: no editors, live embeds, Tab views or networking.
@MainActor private final class CanvasExportView: NSView {
    let snapshot: WorkspaceSnapshot, cards: [WallPlacement], store: WorkspaceStore, world: CGRect, scale: Double
    override var isFlipped: Bool { true }
    init(snapshot: WorkspaceSnapshot, cards: [WallPlacement], store: WorkspaceStore, world: CGRect, scale: Double) {
        self.snapshot = snapshot; self.cards = cards; self.store = store; self.world = world; self.scale = scale
        super.init(frame: CGRect(x: 0, y: 0, width: ceil(world.width * scale), height: ceil(world.height * scale)))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        Palette.NS.wash.setFill(); bounds.fill(); context.saveGraphicsState(); defer { context.restoreGraphicsState() }
        (AffineTransform(scale: scale) as NSAffineTransform).concat(); (AffineTransform(translationByX: -world.minX, byY: -world.minY) as NSAffineTransform).concat()
        let objects = Dictionary(uniqueKeysWithValues: snapshot.objects.map { ($0.id, $0) }), index = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        func text(_ string: String, _ rect: CGRect, size: Double = 14) { (string as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: Palette.NS.ink]) }
        func drawCard(_ card: WallPlacement) {
            guard let object = objects[card.objectID] else { return }
            let group = object.type == "group", path = NSBezierPath(roundedRect: card.rect, xRadius: 5, yRadius: 5)
            (group ? CanvasColor.ns(card.color).withAlphaComponent(0.08) : Palette.NS.ground).setFill(); path.fill(); CanvasColor.ns(card.color).setStroke(); path.lineWidth = 1; path.stroke()
            let rect = card.rect.insetBy(dx: 16, dy: 16)
            if group {
                if let image = CanvasFiles.preview(object) { NSGraphicsContext.saveGraphicsState(); path.addClip(); image.draw(in: card.rect, from: .zero, operation: .sourceOver, fraction: 0.6, respectFlipped: true, hints: nil); NSGraphicsContext.restoreGraphicsState() }
                text(object.title, CGRect(x: rect.minX, y: card.y + 5, width: rect.width, height: 24)); return
            }
            if let image = WorkspaceImage.image(object, store: store) ?? CanvasFiles.preview(object) {
                let ratio = min(rect.width / max(1, image.size.width), rect.height / max(1, image.size.height))
                image.draw(in: CGRect(x: rect.midX - image.size.width * ratio / 2, y: rect.midY - image.size.height * ratio / 2, width: image.size.width * ratio, height: image.size.height * ratio), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else if ["note", "aiOutput"].contains(object.type) { CanvasMarkdown.render(object.text).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]) }
            else if object.type == "file", let source = CanvasFiles.withURL(object, { url -> String? in
                guard ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()), let data = try? CanvasFileDraft.read(url, limit: 1_000_000) else { return nil }; return String(data: data, encoding: .utf8)
            }) { CanvasMarkdown.render(source).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]) }
            else { text(object.title + "\n\n" + (object.url?.absoluteString ?? object.content["file"]?.text ?? object.kindTitle), rect) }
        }
        var labels: [(String, CGPoint)] = []
        for card in cards where objects[card.objectID]?.type == "group" { drawCard(card) }
        for edge in snapshot.wall.edges.compactMap(CanvasEdge.init) {
            guard let a = index[edge.from], let b = index[edge.to] else { continue }
            let curve = CanvasCurve(from: a.rect, side: edge.fromSide, to: b.rect, toSide: edge.toSide), color = edge.color.map(CanvasColor.ns) ?? Palette.NS.muted
            color.setStroke(); let path = curve.path; path.lineWidth = 2; path.stroke()
            func arrow(_ p: CGPoint, _ vector: CGPoint) { let length = max(0.001, hypot(vector.x, vector.y)), d = vector * (8 / length), n = CGPoint(x: -d.y * 0.55, y: d.x * 0.55); let pth = NSBezierPath(); pth.move(to: p); pth.line(to: p - d + n); pth.line(to: p - d - n); pth.close(); color.setFill(); pth.fill() }
            if edge.toArrow { arrow(curve.d, curve.d - curve.c) }; if edge.fromArrow { arrow(curve.a, curve.a - curve.b) }
            if !edge.label.isEmpty { labels.append((edge.label, curve.point(0.5))) }
        }
        for card in cards where objects[card.objectID]?.type != "group" { drawCard(card) }
        for (label, p) in labels {
            let width = min(200, (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width + 16), rect = CGRect(x: p.x - width / 2, y: p.y - 13, width: width, height: 26)
            Palette.NS.wash.setFill(); NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill(); text(label, rect.insetBy(dx: 7, dy: 4), size: 12)
        }
    }
}
