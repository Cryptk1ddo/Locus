import Foundation

/// Interoperability uses placement IDs. Unknown node/edge fields round-trip in
/// their original JSON envelope; imported file paths are never access grants.
enum CanvasJSON {
    struct SavedPreview { let id: UUID; let bytes: Int; let sha256: String; let title: String? }
    static let limit = 2_000_000
    @MainActor static func export(_ snapshot: WorkspaceSnapshot, selection: Set<UUID>? = nil) throws -> Data {
        let objects = Dictionary(uniqueKeysWithValues: snapshot.objects.map { ($0.id, $0) })
        let placements = snapshot.placements.filter { selection == nil || selection!.contains($0.id) }
        let ids = Set(placements.map(\.id))
        var nodes: [ObjectValue] = []
        var external: [UUID: String] = [:]
        var used: Set<String> = []
        func identity(_ proposed: String, fallback: UUID, used: inout Set<String>) -> String {
            if !proposed.isEmpty, used.insert(proposed).inserted { return proposed }
            var candidate = fallback.uuidString, suffix = 1
            while !used.insert(candidate).inserted { suffix += 1; candidate = fallback.uuidString + "-" + String(suffix) }
            return candidate
        }
        for card in placements {
            let proposed = objects[card.objectID]?.content["canvasID"]?.text ?? card.id.uuidString
            external[card.id] = identity(proposed, fallback: card.id, used: &used)
        }
        for card in placements {
            guard let object = objects[card.objectID] else { continue }
            var node: [String: ObjectValue] = [:]
            if case .dictionary(let original) = object.content["canvasNode"] { node = original }
            node.merge(["id": .string(external[card.id]!), "x": .number(card.x.rounded()), "y": .number(card.y.rounded()), "width": .number(card.width.rounded()), "height": .number(card.height.rounded())]) { _, new in new }
            node.removeValue(forKey: "color"); if let color = card.color { node["color"] = .string(color) }
            switch object.type {
            case "group": node["type"] = .string("group"); node["label"] = .string(object.title); if let background = object.content["background"] { node["background"] = background }; if let style = object.content["backgroundStyle"] { node["backgroundStyle"] = style }
            case "file": node["type"] = .string("file"); node["file"] = object.content["file"] ?? .string("")
            case "note", "aiOutput": node["type"] = .string("text"); node["text"] = .string(object.text)
            default:
                if let url = object.url { node["type"] = .string("link"); node["url"] = .string(url.absoluteString) }
                else { node["type"] = .string("text"); node["text"] = .string(object.title + "\n\n" + object.text) }
            }
            nodes.append(.dictionary(node))
        }
        var usedEdges: Set<String> = []
        let edges = snapshot.wall.edges.compactMap { value -> ObjectValue? in
            guard let edge = CanvasEdge(value), ids.contains(edge.from), ids.contains(edge.to) else { return nil }
            var fields: [String: ObjectValue] = [:]
            if case .dictionary(let original) = edge.extra["canvasEdge"] { fields = original }
            let proposed = edge.extra["canvasID"]?.text ?? edge.id.uuidString
            let externalID = identity(proposed, fallback: edge.id, used: &usedEdges)
            fields.merge(["id": .string(externalID), "fromNode": .string(external[edge.from]!), "toNode": .string(external[edge.to]!), "fromSide": .string(edge.fromSide.rawValue), "toSide": .string(edge.toSide.rawValue), "fromEnd": .string(edge.fromArrow ? "arrow" : "none"), "toEnd": .string(edge.toArrow ? "arrow" : "none")]) { _, new in new }
            fields.removeValue(forKey: "color"); fields.removeValue(forKey: "label")
            if let color = edge.color { fields["color"] = .string(color) }; if !edge.label.isEmpty { fields["label"] = .string(edge.label) }
            return .dictionary(fields)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var document = snapshot.wall.canvasExtras ?? [:]; document["nodes"] = .array(nodes); document["edges"] = .array(edges)
        let data = try encoder.encode(document); guard data.count <= limit else { throw WorkspaceError.tooLarge }; return data
    }
    @MainActor @discardableResult static func importData(_ data: Data, into store: WorkspaceStore, at point: CGPoint? = nil, grants: [String: Data] = [:], previews: [String: SavedPreview] = [:], dependencies: [LocusObject] = [], portableContext: String? = nil) throws -> Set<UUID> {
        guard data.count <= limit else { throw WorkspaceError.tooLarge }
        let fields = try JSONDecoder().decode([String: ObjectValue].self, from: data)
        let nodes: [ObjectValue], edges: [ObjectValue]
        if case .array(let list) = fields["nodes"] { nodes = list } else if fields["nodes"] == nil { nodes = [] } else { throw WorkspaceError.invalid }
        if case .array(let list) = fields["edges"] { edges = list } else if fields["edges"] == nil { edges = [] } else { throw WorkspaceError.invalid }
        guard nodes.count <= 2_000, edges.count <= 8_000 else { throw WorkspaceError.tooLarge }
        var objects: [LocusObject] = [], cards: [WallPlacement] = [], mapped: [String: UUID] = [:], visual: [ObjectValue] = []
        func number(_ value: ObjectValue?) -> Double? { if case .number(let v) = value, v.isFinite { return v }; return nil }
        for value in nodes {
            guard case .dictionary(let node) = value, let id = node["id"]?.text, !id.isEmpty, mapped[id] == nil,
                  let type = node["type"]?.text, ["text", "group", "file", "link"].contains(type),
                  let x = number(node["x"]), let y = number(node["y"]), let w = number(node["width"]), let h = number(node["height"]),
                  w >= 1, h >= 1, node["color"] == nil || node["color"]?.text.map(CanvasColor.valid) == true else { throw WorkspaceError.invalid }
            var content: [String: ObjectValue] = ["canvasID": .string(id), "canvasNode": .dictionary(node)]
            if let portableContext { content["portableContext"] = .string(portableContext) }
            let title: String, native: String
            switch type {
            case "text": guard let text = node["text"]?.text else { throw WorkspaceError.invalid }; content["text"] = .string(text); title = String(text.prefix(80)); native = "note"
            case "group": title = node["label"]?.text ?? "Group"; native = "group"; content["background"] = node["background"]; content["backgroundStyle"] = node["backgroundStyle"]
            case "file": guard let file = node["file"]?.text else { throw WorkspaceError.invalid }; content["file"] = .string(file); title = URL(fileURLWithPath: file).lastPathComponent; native = "file"
            default: guard let address = node["url"]?.text, let url = URL(string: address), let clean = SavedPageAddress.clean(url) else { throw WorkspaceError.invalid }; content["url"] = .string(clean.absoluteString); var safeNode = node; safeNode["url"] = .string(clean.absoluteString); content["canvasNode"] = .dictionary(safeNode); title = clean.host ?? clean.absoluteString; native = previews[id] == nil ? "web" : "inspiration"
            }
            // Grants come only from the explicit native folder picker, never document fields.
            if let reference = content[native == "group" ? "background" : "file"]?.text, let grant = grants[reference], ["file", "group"].contains(native) {
                content["bookmark"] = .string(grant.base64EncodedString())
            }
            if native == "inspiration" { content["screenshot"] = .dictionary(["origin": .string("portable")]) }
            var object = LocusObject(type: native, title: previews[id]?.title ?? title, content: content)
            if native == "inspiration", let preview = previews[id] { object.attachSnapshot(preview.id, bytes: preview.bytes, sha256: preview.sha256) }
            let card = WallPlacement(objectID: object.id, x: x, y: y, width: w, height: h, color: node["color"]?.text)
            objects.append(object); cards.append(card); mapped[id] = card.id
        }
        var edgeIDs: Set<String> = []
        for value in edges {
            guard case .dictionary(let fields) = value, let id = fields["id"]?.text, edgeIDs.insert(id).inserted,
                  let from = fields["fromNode"]?.text.flatMap({ mapped[$0] }), let to = fields["toNode"]?.text.flatMap({ mapped[$0] }),
                  fields["color"] == nil || fields["color"]?.text.map(CanvasColor.valid) == true,
                  (fields["fromEnd"] == nil || ["arrow","none"].contains(fields["fromEnd"]?.text ?? "")),
                  (fields["toEnd"] == nil || ["arrow","none"].contains(fields["toEnd"]?.text ?? "")),
                  (fields["label"] == nil || fields["label"]?.text != nil),
                  (fields["fromSide"] == nil || fields["fromSide"]?.text != nil),
                  (fields["toSide"] == nil || fields["toSide"]?.text != nil) else { throw WorkspaceError.invalid }
            let a = fields["fromSide"]?.text ?? "right", b = fields["toSide"]?.text ?? "left"
            guard let fromSide = CanvasSide(rawValue: a), let toSide = CanvasSide(rawValue: b) else { throw WorkspaceError.invalid }
            var edge = CanvasEdge(from: from, to: to, fromSide: fromSide, toSide: toSide); edge.fromArrow = fields["fromEnd"]?.text == "arrow"; edge.toArrow = fields["toEnd"]?.text != "none"; edge.label = fields["label"]?.text ?? ""; edge.color = fields["color"]?.text; edge.extra = ["canvasID": .string(id), "canvasEdge": .dictionary(fields)]; visual.append(edge.value)
        }
        if let point, let minX = cards.map(\.x).min(), let minY = cards.map(\.y).min() {
            for i in cards.indices { cards[i].x += point.x - minX; cards[i].y += point.y - minY }
        }
        guard store.mutate({ next in next.objects += objects + dependencies; next.placements += cards; next.wall.edges += visual; next.wall.canvasExtras = (next.wall.canvasExtras ?? [:]).merging(fields.filter { !["nodes", "edges"].contains($0.key) }) { _, new in new } }) else { throw WorkspaceError.unavailable }
        return Set(cards.map(\.id))
    }
}
