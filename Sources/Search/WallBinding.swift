import Foundation

/// A live reference to a durable page, scoped to its workspace rather than its URL.
struct WallBinding: Equatable {
    let spaceID: UUID
    let objectID: UUID

    func resolved(in snapshot: WorkspaceSnapshot) -> WallBinding? {
        guard spaceID == snapshot.spaceID else { return nil }
        return Self.resolve(objectID, in: snapshot)
    }

    static func resolve(_ objectID: UUID?, in snapshot: WorkspaceSnapshot) -> WallBinding? {
        guard let objectID, snapshot.objects.contains(where: { $0.id == objectID && $0.supported && $0.type == "page" }) else { return nil }
        return WallBinding(spaceID: snapshot.spaceID, objectID: objectID)
    }

    /// Retain a session's identity while its workspace cannot be read. This is
    /// serialization state only: action lookup still requires a valid page.
    @MainActor static func restore(_ objectID: UUID?, in store: WorkspaceStore) -> WallBinding? {
        guard let objectID else { return nil }
        if store.preservesUnresolvedBindings { return WallBinding(spaceID: store.snapshot.spaceID, objectID: objectID) }
        return resolve(objectID, in: store.snapshot)
    }
}

enum SavedPageAddress {
    static func clean(_ url: URL) -> URL? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.isEmpty == false else { return nil }
        components.user = nil
        components.password = nil
        return components.url
    }
}

extension Tab {
    @MainActor
    func sessionWallObjectID(in space: UUID) -> UUID? {
        guard !shy, !bench, held == nil, let binding = wallBinding, binding.spaceID == space else { return nil }
        return WallBinding.restore(binding.objectID, in: WorkspaceStore.shared(for: space))?.objectID
    }

    @MainActor
    func wallObjectID(in space: UUID) -> UUID? {
        guard !shy, !bench, held == nil, let binding = wallBinding, binding.spaceID == space else { return nil }
        return WallBinding.resolve(binding.objectID, in: WorkspaceStore.shared(for: space).snapshot)?.objectID
    }
}
