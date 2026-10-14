import Foundation

/// JSON carried by objects is data, never executable browser authority.
indirect enum ObjectValue: Codable, Equatable {
    case string(String), number(Double), integer(Int64), unsigned(UInt64), bool(Bool), null
    case array([ObjectValue]), dictionary([String: ObjectValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) {
            self = (-9_007_199_254_740_992...9_007_199_254_740_992).contains(v) ? .number(Double(v)) : .integer(v)
        }
        else if let v = try? c.decode(UInt64.self) { self = .unsigned(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([ObjectValue].self) { self = .array(v) }
        else { self = .dictionary(try c.decode([String: ObjectValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .unsigned(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .dictionary(let v): try c.encode(v)
        }
    }
    var text: String? { if case .string(let v) = self { return v }; return nil }
}

/// Keep the full envelope so newer object types and fields survive older builds.
/// Live Tab IDs and WKWebViews deliberately do not belong here.
struct LocusObject: Codable, Identifiable, Equatable {
    let id: UUID
    private(set) var fields: [String: ObjectValue]
    var type: String { fields["type"]?.text ?? "unknown" }
    var title: String { fields["title"]?.text ?? "Untitled" }
    var supported: Bool { fields["payloadVersion"] == .number(1) && ["page", "note", "uiCapture", "inspiration", "aiOutput", "group", "file", "web"].contains(type) }
    var content: [String: ObjectValue] {
        if case .dictionary(let v) = fields["content"] { return v }
        return [:]
    }
    var url: URL? { supported && ["page", "inspiration", "web"].contains(type) ? content["url"]?.text.flatMap(URL.init(string:)) : nil }
    var text: String { content["text"]?.text ?? "" }

    init(type: String, title: String, content: [String: ObjectValue]) {
        id = UUID()
        let date = ISO8601DateFormatter().string(from: Date())
        fields = ["id": .string(id.uuidString), "type": .string(type),
                  "title": .string(String(title.prefix(300))), "payloadVersion": .number(1),
                  "createdAt": .string(date), "updatedAt": .string(date),
                  "metadata": .dictionary([:]), "content": .dictionary(content),
                  "relationships": .array([]),
                  "source": ["page", "uiCapture", "inspiration", "aiOutput", "web"].contains(type) ? .dictionary(["url": content["url"] ?? .null]) : .null,
                  "capabilities": .array([.string(["note", "group"].contains(type) ? "edit" : ["uiCapture", "inspiration", "aiOutput"].contains(type) ? "inspect" : "open")]) ]
    }

    var kindTitle: String {
        switch type {
        case "page": return "Page"
        case "note": return "Note"
        case "uiCapture": return "UI capture"
        case "inspiration": return "Inspiration"
        case "aiOutput": return "AI answer"
        case "group": return "Group"
        case "file": return "File"
        case "web": return "Web page"
        default: return "Object"
        }
    }

    var relationships: [ObjectRelationship] {
        guard case .array(let links) = fields["relationships"] else { return [] }
        return links.compactMap(ObjectRelationship.init)
    }

    mutating func appendRelationship(kind: String, target: UUID, label: String = "") {
        var links: [ObjectValue] = []
        if case .array(let existing) = fields["relationships"] { links = existing }
        var link: [String: ObjectValue] = ["kind": .string(kind), "targetID": .string(target.uuidString)]
        if !label.isEmpty { link["label"] = .string(String(label.prefix(200))) }
        links.append(.dictionary(link))
        fields["relationships"] = .array(links)
    }

    mutating func removeRelationship(kind: String, target: UUID) {
        guard case .array(let links) = fields["relationships"] else { return }
        fields["relationships"] = .array(links.filter {
            guard let link = ObjectRelationship($0) else { return true }
            return link.kind != kind || link.target != target
        })
    }

    var snapshotID: UUID? {
        guard supported, ["uiCapture", "inspiration"].contains(type), case .dictionary(let screenshot) = content["screenshot"],
              case .dictionary(let value) = screenshot["value"] else { return nil }
        return value["assetID"]?.text.flatMap(UUID.init(uuidString:))
    }

    mutating func linkCaptureSource(_ id: UUID) {
        fields["relationships"] = .array([.dictionary(["kind": .string("capturedFrom"), "targetID": .string(id.uuidString)])])
    }

    func relationshipTarget(_ kind: String) -> UUID? {
        guard case .array(let links) = fields["relationships"] else { return nil }
        return links.compactMap { value -> UUID? in
            guard case .dictionary(let link) = value, link["kind"]?.text == kind else { return nil }
            return link["targetID"]?.text.flatMap(UUID.init(uuidString:))
        }.first
    }

    mutating func linkDerivedCapture(_ id: UUID) {
        guard case .array(var links) = fields["relationships"] else { return }
        links.append(.dictionary(["kind": .string("derivedFrom"), "targetID": .string(id.uuidString)]))
        fields["relationships"] = .array(links)
    }

    mutating func updatePage(title: String, url: URL) {
        fields["title"] = .string(String(title.prefix(300)))
        var payload = content
        payload["url"] = .string(url.absoluteString)
        fields["content"] = .dictionary(payload)
        var source: [String: ObjectValue] = [:]
        if case .dictionary(let existing) = fields["source"] { source = existing }
        source["url"] = .string(url.absoluteString)
        fields["source"] = .dictionary(source)
        fields["updatedAt"] = .string(ISO8601DateFormatter().string(from: Date()))
    }

    var snapshotIntegrity: [String: ObjectValue] {
        guard snapshotID != nil, case .dictionary(let screenshot) = content["screenshot"],
              case .dictionary(let value) = screenshot["value"] else { return [:] }
        return value
    }

    mutating func attachSnapshot(_ id: UUID, bytes: Int, sha256: String) {
        var payload = content
        if case .dictionary(var screenshot) = payload["screenshot"] {
            screenshot["value"] = .dictionary(["assetID": .string(id.uuidString), "mime": .string("image/png"),
                                               "bytes": .number(Double(bytes)), "sha256": .string(sha256)])
            payload["screenshot"] = .dictionary(screenshot)
        }
        fields["content"] = .dictionary(payload)
    }

    mutating func editNote(title: String, text: String) {
        fields["title"] = .string(title)
        var payload = content
        payload["text"] = .string(text)
        fields["content"] = .dictionary(payload)
        fields["updatedAt"] = .string(ISO8601DateFormatter().string(from: Date()))
    }

    mutating func removeRelationships(to id: UUID) {
        guard case .array(let relationships) = fields["relationships"] else { return }
        fields["relationships"] = .array(relationships.filter {
            guard case .dictionary(let link) = $0 else { return true }
            return link["targetID"]?.text.flatMap(UUID.init(uuidString:)) != id
        })
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        fields = try c.decode([String: ObjectValue].self)
        guard let value = fields["id"]?.text.flatMap(UUID.init(uuidString:)),
              fields["type"]?.text != nil else { throw WorkspaceError.invalid }
        id = value
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(fields)
    }
}

struct WallPlacement: Codable, Identifiable, Equatable {
    var id = UUID()
    var objectID: UUID
    var x: Double
    var y: Double
    var width: Double = 260
    var height: Double = 180
    var color: String? = nil
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct WallDocument: Codable, Equatable {
    var id = UUID()
    var placements: [WallPlacement] = []
    var edges: [ObjectValue] = []
    var canvasExtras: [String: ObjectValue]? = nil

    mutating func removePlacement(_ id: UUID) {
        placements.removeAll { $0.id == id }
        edges.removeAll {
            guard case .dictionary(let edge) = $0 else { return false }
            return ["fromPlacementID", "toPlacementID"].contains {
                edge[$0]?.text.flatMap(UUID.init(uuidString:)) == id
            }
        }
    }
}

struct WorkspaceSnapshot: Codable, Equatable {
    var schemaVersion = 1
    var spaceID: UUID
    var revision = 0
    var objects: [LocusObject] = []
    var wall = WallDocument()
    var placements: [WallPlacement] {
        get { wall.placements }
        set { wall.placements = newValue }
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw WorkspaceError.futureVersion }
        let ids = Set(objects.map(\.id))
        for object in objects where object.supported {
            if case .array(let records) = object.fields["relationships"] {
                for record in records {
                    if case .dictionary(let fields) = record, let kind = fields["kind"]?.text, ObjectRelationship.known.contains(kind) {
                        guard ObjectRelationship(record) != nil,
                              fields["label"] == nil || fields["label"]?.text != nil else { throw WorkspaceError.invalid }
                    }
                }
            }
            let known = object.relationships.filter { ObjectRelationship.known.contains($0.kind) }
            guard known.count <= 64,
                  Set(known.map { "\($0.kind):\($0.target)" }).count == known.count,
                  known.allSatisfy({ $0.target != object.id && ids.contains($0.target) && $0.label.count <= 200 })
            else { throw WorkspaceError.invalid }
        }
        guard objects.count <= 2_000, placements.count <= 4_000,
              ids.count == objects.count,
              Set(placements.map(\.id)).count == placements.count,
              placements.allSatisfy({ p in
                  ids.contains(p.objectID) && [p.x, p.y, p.width, p.height].allSatisfy(\.isFinite)
                      && abs(p.x) <= 1_000_000 && abs(p.y) <= 1_000_000
                      && (1...1_000_000).contains(p.width) && (1...1_000_000).contains(p.height)
                      && (p.color == nil || CanvasColor.valid(p.color!))
              }) else { throw WorkspaceError.invalid }
        try CanvasEdge.validate(wall.edges, placements: Set(placements.map(\.id)))
    }
}

enum WorkspaceError: LocalizedError, Equatable {
    case invalid, futureVersion, unavailable, tooLarge, wrongSpace, unsafePath, externalChange, assetLimit
    var errorDescription: String? {
        switch self {
        case .invalid: return "This Wall contains invalid data. Its file has been preserved."
        case .futureVersion: return "This Wall needs a newer version of Locus. Its file has been preserved."
        case .unavailable: return "This Wall cannot be changed right now."
        case .tooLarge: return "This Wall has reached its storage limit."
        case .wrongSpace: return "This Wall belongs to a different Space. Its file has been preserved."
        case .unsafePath: return "This Wall's storage path contains a link or unsupported file. Its data has been preserved."
        case .externalChange: return "This Wall's file changed outside this window. Reopen Locus before saving."
        case .assetLimit: return "This Space has reached its preview storage limit (256 MB or 4,000 files)."
        }
    }
}
