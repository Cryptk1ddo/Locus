import Foundation

struct ObjectRelationship: Equatable {
    static let editable = ["relatedTo", "inspiredBy", "supports", "contradicts"]
    static let provenance = ["capturedFrom", "derivedFrom", "collectedFrom", "generatedFrom"]
    static let known = editable + provenance
    let kind: String
    let target: UUID
    let label: String

    init?(_ value: ObjectValue) {
        guard case .dictionary(let link) = value, let kind = link["kind"]?.text,
              let target = link["targetID"]?.text.flatMap(UUID.init(uuidString:)) else { return nil }
        self.kind = kind
        self.target = target
        label = link["label"]?.text ?? ""
    }

    static func title(_ kind: String) -> String {
        switch kind {
        case "relatedTo": return "Related to"
        case "inspiredBy": return "Inspired by"
        case "supports": return "Supports"
        case "contradicts": return "Contradicts"
        case "capturedFrom": return "Captured from"
        case "derivedFrom": return "Derived from"
        case "collectedFrom": return "Collected from"
        case "generatedFrom": return "Generated from"
        default: return kind
        }
    }
}

/// Geometry is a projection of object links, never another source of graph truth.
enum WallGraph {
    struct Wire: Identifiable {
        let source: UUID
        let link: ObjectRelationship
        let from: WallPlacement
        let to: WallPlacement
        var id: String { "\(source):\(link.kind):\(link.target)" }
    }

    static func wires(in snapshot: WorkspaceSnapshot) -> [Wire] {
        var first: [UUID: WallPlacement] = [:]
        for placement in snapshot.placements where first[placement.objectID] == nil {
            first[placement.objectID] = placement
        }
        return snapshot.objects.filter(\.supported).flatMap { object -> [Wire] in
            guard let from = first[object.id] else { return [] }
            return object.relationships.compactMap { link in
                guard ObjectRelationship.known.contains(link.kind), let to = first[link.target], link.target != object.id else { return nil }
                return Wire(source: object.id, link: link, from: from, to: to)
            }
        }
    }
}

struct WallViewport: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0
    var zoom: Double = 1
    var valid: Bool {
        [x, y, zoom].allSatisfy(\.isFinite) && abs(x) <= 1_000_000 && abs(y) <= 1_000_000 && (0.05...4).contains(zoom)
    }
    static func key(window: UUID, space: UUID) -> String { "locus.wall.viewport.\(window).\(space)" }
    static func load(window: UUID, space: UUID, settings: UserDefaults) -> Self {
        guard let data = settings.data(forKey: key(window: window, space: space)),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.valid else { return Self() }
        return value
    }
    func save(window: UUID, space: UUID, settings: UserDefaults) {
        guard valid, let data = try? JSONEncoder().encode(self) else { return }
        settings.set(data, forKey: Self.key(window: window, space: space))
    }
}
