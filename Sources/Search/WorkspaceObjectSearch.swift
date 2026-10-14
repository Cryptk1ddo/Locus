import Foundation

/// Local, bounded search over known object content. Captured DOM is never an intent.
enum WorkspaceObjectSearch {
    static func query(from typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("wall:") else { return nil }
        let rest = trimmed.dropFirst(5)
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        return String(rest.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
    }

    static func results(in snapshot: WorkspaceSnapshot, query: String, limit: Int = 5) -> [Suggestion] {
        Index(snapshot: snapshot).results(query: query, limit: limit)
    }

    /// Rebuilt only after a workspace revision changes, not on each keystroke.
    struct Index {
        private let space: UUID
        private let entries: [(object: LocusObject, title: String, text: String)]

        init(snapshot: WorkspaceSnapshot) {
            space = snapshot.spaceID
            entries = snapshot.objects.filter(\.supported).map { object in
                let title = folded(object.title)
                let detail: String
                switch object.type {
                case "note": detail = String(object.text.prefix(8_192))
                case "page": detail = object.url?.absoluteString ?? ""
                case "inspiration", "aiOutput":
                    detail = [object.content["url"]?.text ?? "", object.content["provider"]?.text ?? "",
                              object.content["description"]?.text ?? "", object.content["question"]?.text ?? "", object.text]
                        .map { String($0.prefix(4_096)) }.joined(separator: " ")
                default: detail = "" // Capture payloads and future kinds stay opaque.
                }
                return (object, title, title + " " + folded(String(detail.prefix(8_192))))
            }
        }

        func results(query: String, limit: Int = 5) -> [Suggestion] {
            let needle = folded(String(query.prefix(256)))
            let terms = needle.split(whereSeparator: \.isWhitespace).map(String.init)
            let ranked = entries.compactMap { object, title, text -> (LocusObject, Int)? in
                guard terms.allSatisfy({ text.contains($0) }) else { return nil }
                let rank = needle.isEmpty || title == needle ? 0 : title.hasPrefix(needle) ? 1
                    : terms.allSatisfy({ title.contains($0) }) ? 2 : 3
                return (object, rank)
            }.sorted {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                let left = $0.0.fields["updatedAt"]?.text ?? "", right = $1.0.fields["updatedAt"]?.text ?? ""
                if left != right { return left > right }
                return $0.0.id.uuidString < $1.0.id.uuidString
            }
            return ranked.prefix(min(5, max(0, limit))).map { object, _ in
                let kind = object.kindTitle
                return Suggestion(key: object.title, title: "\(kind) · Wall", url: nil,
                                  kind: .object(space: space, id: object.id))
            }
        }
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
