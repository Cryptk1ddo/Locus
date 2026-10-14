import AppKit

/// JSON Canvas's six colour keys; an omitted colour means the theme default.
enum CanvasColor {
    static let presets = ["1", "2", "3", "4", "5", "6"]
    static func valid(_ value: String) -> Bool {
        presets.contains(value) || (value.count == 7 && value.first == "#" && value.dropFirst().allSatisfy { "0123456789abcdefABCDEF".contains($0) })
    }
    static func name(_ value: String?) -> String {
        switch value { case "1": return "Red"; case "2": return "Orange"; case "3": return "Yellow"; case "4": return "Green"; case "5": return "Cyan"; case "6": return "Purple"; case nil: return "Default"; default: return "Custom" }
    }
    static func ns(_ value: String?) -> NSColor {
        switch value {
        case "1": return .systemRed
        case "2": return .systemOrange
        case "3": return .systemYellow
        case "4": return .systemGreen
        case "5": return .systemCyan
        case "6": return .systemPurple
        default:
            if let value, valid(value), let hex = UInt32(value.dropFirst(), radix: 16) {
                return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
            }
            return Palette.NS.hairline
        }
    }
}

enum CanvasSide: String, CaseIterable, Codable {
    case top, right, bottom, left
    var direction: CGPoint {
        switch self { case .top: return CGPoint(x: 0, y: -1); case .right: return CGPoint(x: 1, y: 0); case .bottom: return CGPoint(x: 0, y: 1); case .left: return CGPoint(x: -1, y: 0) }
    }
    func point(on rect: CGRect) -> CGPoint {
        switch self { case .top: return CGPoint(x: rect.midX, y: rect.minY); case .right: return CGPoint(x: rect.maxX, y: rect.midY); case .bottom: return CGPoint(x: rect.midX, y: rect.maxY); case .left: return CGPoint(x: rect.minX, y: rect.midY) }
    }
    static func nearest(to point: CGPoint, on rect: CGRect) -> Self {
        allCases.min { a, b in a.point(on: rect).distance(to: point) < b.point(on: rect).distance(to: point) } ?? .left
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, b: CGFloat) -> CGPoint { CGPoint(x: a.x * b, y: a.y * b) }
}

/// Canvas edges join placements. Semantic/provenance relationships remain on objects.
struct CanvasEdge: Identifiable, Equatable {
    var id = UUID()
    var from: UUID
    var to: UUID
    var fromSide: CanvasSide = .right
    var toSide: CanvasSide = .left
    var fromArrow = false
    var toArrow = true
    var color: String? = nil
    var label = ""
    var extra: [String: ObjectValue] = [:]

    init(from: UUID, to: UUID, fromSide: CanvasSide = .right, toSide: CanvasSide = .left) {
        self.from = from; self.to = to; self.fromSide = fromSide; self.toSide = toSide
    }
    init?(_ value: ObjectValue) {
        guard case .dictionary(let fields) = value, fields["kind"] == .string("canvas"),
              let id = fields["id"]?.text.flatMap(UUID.init(uuidString:)),
              let from = fields["fromPlacementID"]?.text.flatMap(UUID.init(uuidString:)),
              let to = fields["toPlacementID"]?.text.flatMap(UUID.init(uuidString:)),
              let fromSide = fields["fromSide"]?.text.flatMap(CanvasSide.init(rawValue:)),
              let toSide = fields["toSide"]?.text.flatMap(CanvasSide.init(rawValue:)),
              (fields["fromEnd"] == nil || ["none", "arrow"].contains(fields["fromEnd"]?.text ?? "")),
              (fields["toEnd"] == nil || ["none", "arrow"].contains(fields["toEnd"]?.text ?? "")),
              fields["label"] == nil || fields["label"]?.text != nil,
              fields["color"] == nil || fields["color"] == .null || fields["color"]?.text.map(CanvasColor.valid) == true
        else { return nil }
        self.id = id; self.from = from; self.to = to; self.fromSide = fromSide; self.toSide = toSide
        fromArrow = fields["fromEnd"] == .string("arrow"); toArrow = fields["toEnd"] != .string("none")
        color = fields["color"]?.text; label = fields["label"]?.text ?? ""; extra = fields
    }
    var value: ObjectValue {
        var fields = extra
        fields.merge(["kind": .string("canvas"), "id": .string(id.uuidString),
            "fromPlacementID": .string(from.uuidString), "toPlacementID": .string(to.uuidString),
            "fromSide": .string(fromSide.rawValue), "toSide": .string(toSide.rawValue),
            "fromEnd": .string(fromArrow ? "arrow" : "none"), "toEnd": .string(toArrow ? "arrow" : "none"),
            "label": .string(label), "color": color.map(ObjectValue.string) ?? .null]) { _, new in new }
        return .dictionary(fields)
    }
    static func validate(_ values: [ObjectValue], placements: Set<UUID>) throws {
        let known = values.filter { if case .dictionary(let fields) = $0 { return fields["kind"] == .string("canvas") }; return false }
        let edges = known.compactMap(Self.init)
        guard values.count <= 8_000, edges.count == known.count, Set(edges.map(\.id)).count == edges.count,
              edges.allSatisfy({ placements.contains($0.from) && placements.contains($0.to) && $0.label.count <= 300 }) else { throw WorkspaceError.invalid }
    }
}

struct CanvasCurve {
    /// A cubic stays inside the convex hull of its control points.
    var controlBounds: CGRect {
        let xs = [a.x, b.x, c.x, d.x], ys = [a.y, b.y, c.y, d.y]
        return CGRect(x: xs.min()!, y: ys.min()!, width: max(0.001, xs.max()! - xs.min()!), height: max(0.001, ys.max()! - ys.min()!))
    }

    let a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint
    init(from: CGRect, side: CanvasSide, to: CGRect, toSide: CanvasSide) {
        a = side.point(on: from); d = toSide.point(on: to)
        let distance = min(220, max(40, a.distance(to: d) * 0.4))
        b = a + side.direction * distance; c = d + toSide.direction * distance
    }
    func point(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
    }
    var path: NSBezierPath {
        let path = NSBezierPath(); path.move(to: a); path.curve(to: d, controlPoint1: b, controlPoint2: c); return path
    }
    func distance(to point: CGPoint) -> CGFloat {
        (0..<40).map { index -> CGFloat in
            let a = self.point(CGFloat(index) / 40), b = self.point(CGFloat(index + 1) / 40), d = b - a
            let length = d.x * d.x + d.y * d.y
            let t = length > 0 ? min(1, max(0, ((point.x - a.x) * d.x + (point.y - a.y) * d.y) / length)) : 0
            return point.distance(to: a + d * t)
        }.min() ?? .infinity
    }
}

/// Pure gesture geometry, shared by mouse/keyboard and tested without views.
enum CanvasGeometry {
    static func contained(in group: WallPlacement, placements: [WallPlacement]) -> Set<UUID> {
        Set(placements.filter { $0.id != group.id && group.rect.contains($0.rect) }.map(\.id))
    }
    static func moved(_ cards: [WallPlacement], delta: CGPoint, constrained: Bool, grid: Bool, objects: [WallPlacement] = [], zoom: Double = 1) -> [WallPlacement] {
        guard let first = cards.first else { return [] }
        var delta = delta
        let horizontal = abs(delta.x) >= abs(delta.y)
        if constrained { if horizontal { delta.y = 0 } else { delta.x = 0 } }
        var anchor = CGPoint(x: first.x, y: first.y) + delta
        let lockX = constrained && !horizontal, lockY = constrained && horizontal
        if grid {
            if !lockX { anchor.x = (anchor.x / 20).rounded() * 20 }
            if !lockY { anchor.y = (anchor.y / 20).rounded() * 20 }
        }
        let tolerance = 6 / zoom
        func correction(_ moving: [CGFloat], _ targets: [CGFloat]) -> CGFloat? {
            let values = moving.flatMap { a in targets.map { $0 - a } }
            guard let best = values.min(by: { abs($0) < abs($1) }), abs(best) <= tolerance else { return nil }; return best
        }
        if !lockX, let snap = correction([anchor.x, anchor.x + first.width / 2, anchor.x + first.width], objects.flatMap { [$0.rect.minX, $0.rect.midX, $0.rect.maxX] }) { anchor.x += snap }
        if !lockY, let snap = correction([anchor.y, anchor.y + first.height / 2, anchor.y + first.height], objects.flatMap { [$0.rect.minY, $0.rect.midY, $0.rect.maxY] }) { anchor.y += snap }
        let actual = anchor - CGPoint(x: first.x, y: first.y)
        return cards.map { var card = $0; card.x += actual.x; card.y += actual.y; return card }
    }
    static func resized(_ card: WallPlacement, horizontal: Int, vertical: Int, delta: CGPoint, aspect: Bool, snap: Bool) -> WallPlacement {
        var left = card.rect.minX, right = card.rect.maxX, top = card.rect.minY, bottom = card.rect.maxY
        if horizontal < 0 { left = min(right - 50, left + delta.x) }
        if horizontal > 0 { right = max(left + 50, right + delta.x) }
        if vertical < 0 { top = min(bottom - 40, top + delta.y) }
        if vertical > 0 { bottom = max(top + 40, bottom + delta.y) }
        if snap {
            if horizontal < 0 { left = min(right - 50, (left / 20).rounded() * 20) }
            if horizontal > 0 { right = max(left + 50, (right / 20).rounded() * 20) }
            if vertical < 0 { top = min(bottom - 40, (top / 20).rounded() * 20) }
            if vertical > 0 { bottom = max(top + 40, (bottom / 20).rounded() * 20) }
        }
        if aspect {
            let ratio = card.width / card.height
            if horizontal != 0 && (vertical == 0 || abs(delta.x) >= abs(delta.y)) {
                let height = max(40, (right - left) / ratio)
                if vertical < 0 { top = bottom - height } else { bottom = top + height }
            } else {
                let width = max(50, (bottom - top) * ratio)
                if horizontal < 0 { left = right - width } else { right = left + width }
            }
        }
        var result = card; result.x = left; result.y = top; result.width = right - left; result.height = bottom - top
        return result
    }
}

extension WorkspaceStore {
    @discardableResult func addCanvasReference(_ object: UUID, at point: CGPoint) -> UUID? {
        let card = WallPlacement(objectID: object, x: point.x, y: point.y)
        return mutate { next in
            guard next.objects.contains(where: { $0.id == object && $0.supported }) else { throw WorkspaceError.unavailable }
            next.placements.append(card)
        } ? card.id : nil
    }

    @discardableResult func setCanvasCards(_ cards: [WallPlacement]) -> Bool {
        let replacements = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        return mutate { next in
            guard replacements.keys.allSatisfy({ id in next.placements.contains { $0.id == id } }) else { throw WorkspaceError.unavailable }
            for i in next.placements.indices { if let card = replacements[next.placements[i].id] { next.placements[i] = card } }
        }
    }
    @discardableResult func removeCanvasSelection(cards: Set<UUID>, edges: Set<UUID>) -> Bool {
        mutate { next in
            for id in cards { next.wall.removePlacement(id) }
            next.wall.edges.removeAll { CanvasEdge($0).map { edges.contains($0.id) } ?? false }
        }
    }
    @discardableResult func saveCanvasEdge(_ edge: CanvasEdge) -> Bool {
        mutate { next in
            if let i = next.wall.edges.firstIndex(where: { CanvasEdge($0)?.id == edge.id }) { next.wall.edges[i] = edge.value }
            else { next.wall.edges.append(edge.value) }
        }
    }
    @discardableResult func colorCanvas(cards: Set<UUID>, edges: Set<UUID>, color: String?) -> Bool {
        guard color == nil || color.map(CanvasColor.valid) == true else { return false }
        return mutate { next in
            for i in next.placements.indices where cards.contains(next.placements[i].id) { next.placements[i].color = color }
            for i in next.wall.edges.indices {
                if var edge = CanvasEdge(next.wall.edges[i]), edges.contains(edge.id) { edge.color = color; next.wall.edges[i] = edge.value }
            }
        }
    }
    @discardableResult func addCanvasGroup(enclosing ids: Set<UUID>, at point: CGPoint) -> UUID? {
        let cards = snapshot.placements.filter { ids.contains($0.id) }
        let bounds = cards.isEmpty ? CGRect(x: point.x, y: point.y, width: 400, height: 300) : cards.reduce(CGRect.null) { $0.union($1.rect) }.insetBy(dx: -40, dy: -40)
        let object = LocusObject(type: "group", title: "Group", content: [:])
        let group = WallPlacement(objectID: object.id, x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
        return mutate { next in next.objects.append(object); next.placements.insert(group, at: 0) } ? group.id : nil
    }
    /// Notes and groups duplicate content; file/page references keep their object.
    @discardableResult func duplicateCanvas(_ ids: Set<UUID>, offset: CGPoint = CGPoint(x: 40, y: 40)) -> Set<UUID>? {
        var newIDs: Set<UUID> = []
        return mutate { next in
            let cards = next.placements.filter { ids.contains($0.id) }
            var placementIDs: [UUID: UUID] = [:], clonedObjects: [UUID: UUID] = [:]
            for original in cards {
                guard let object = next.objects.first(where: { $0.id == original.objectID }) else { throw WorkspaceError.invalid }
                var card = original; card.id = UUID(); card.x += offset.x; card.y += offset.y
                if object.supported && ["note", "group"].contains(object.type) {
                    if let id = clonedObjects[object.id] { card.objectID = id }
                    else {
                        var fields = object.fields; let id = UUID(); fields["id"] = .string(id.uuidString)
                        fields["createdAt"] = .string(ISO8601DateFormatter().string(from: Date()))
                        let copy = try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))
                        next.objects.append(copy); clonedObjects[object.id] = id; card.objectID = id
                    }
                }
                next.placements.append(card); placementIDs[original.id] = card.id; newIDs.insert(card.id)
            }
            for original in next.wall.edges.compactMap(CanvasEdge.init) {
                if let from = placementIDs[original.from], let to = placementIDs[original.to] {
                    var edge = original; edge.id = UUID(); edge.from = from; edge.to = to; next.wall.edges.append(edge.value)
                }
            }
        } ? newIDs : nil
    }
}
