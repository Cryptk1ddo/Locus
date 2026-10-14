import SwiftUI
import UniformTypeIdentifiers
import Combine

struct WallDroppedLink {
    let url: URL
    let title: String
}

extension WallViewport {
    /// DropInfo locations are in the untransformed canvas, not inside a card.
    func worldPoint(_ point: CGPoint) -> CGPoint? {
        guard valid, point.x.isFinite, point.y.isFinite else { return nil }
        let result = CGPoint(x: (point.x - x) / zoom, y: (point.y - y) / zoom)
        guard abs(result.x) <= 1_000_000, abs(result.y) <= 1_000_000 else { return nil }
        return result
    }
}

extension WorkspaceStore {
    /// One drop is one durable revision, never add-then-move intermediate writes.
    @discardableResult
    func addDroppedLinks(_ links: [WallDroppedLink], at point: CGPoint) -> Bool {
        guard !links.isEmpty, links.count <= WallLinkDrop.limit else { return false }
        let objects = links.compactMap {
            InspirationSource.object(url: $0.url, title: $0.title, reason: "Dropped web link; no page preview requested")
        }
        guard objects.count == links.count else { return false }
        return mutate { next in
            for (index, object) in objects.enumerated() {
                next.objects.append(object)
                next.placements.append(WallPlacement(objectID: object.id,
                    x: point.x + Double(index % 3) * 280, y: point.y + Double(index / 3) * 200))
            }
        }
    }
}

/// Reads native URL drag data without opening a browser view. The deadline owns
/// the request; provider callbacks are weak so a broken source cannot retain it.
@MainActor
final class WallLinkDrop {
    static let limit = 20
    enum Result: Equatable {
        case saved(Int, skipped: Int), invalid, cancelled, timedOut, failed(String)
    }
    private let store: WorkspaceStore
    private let point: CGPoint
    private let valid: () -> Bool
    private let complete: (Result) -> Void
    private var links: [WallDroppedLink?]
    private var received: Set<Int> = []
    private var progress: [Progress] = []
    private var watching: [AnyCancellable] = []
    private var finished = false

    private init(count: Int, store: WorkspaceStore, point: CGPoint,
                 valid: @escaping () -> Bool, complete: @escaping (Result) -> Void) {
        self.store = store; self.point = point; self.valid = valid; self.complete = complete
        links = Array(repeating: nil, count: count)
    }

    static func accepts(_ providers: [NSItemProvider]) -> Bool {
        !providers.isEmpty && providers.count <= limit && providers.allSatisfy {
            // Foundation can coerce a plain string into URL. Require a URL
            // representation advertised by the source, not just that coercion.
            $0.registeredTypeIdentifiers.contains { UTType($0)?.conforms(to: .url) == true }
                && $0.canLoadObject(ofClass: URL.self)
        }
    }

    static func start(_ providers: [NSItemProvider], at location: CGPoint, viewport: WallViewport,
                      store: WorkspaceStore, valid: @escaping () -> Bool,
                      complete: @escaping (Result) -> Void) -> WallLinkDrop? {
        guard store.writable, valid(), accepts(providers), let point = viewport.worldPoint(location) else { return nil }
        let request = WallLinkDrop(count: providers.count, store: store, point: point, valid: valid, complete: complete)
        for (index, provider) in providers.enumerated() {
            let title = String((provider.suggestedName ?? "").prefix(300))
            let task = provider.loadObject(ofClass: URL.self) { [weak request] url, _ in
                DispatchQueue.main.async { request?.receive(url, title: title, index: index) }
            }
            request.progress.append(task)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { request.expire() }
        return request
    }

    func watch(_ subscription: AnyCancellable) { if !finished { watching.append(subscription) } }
    func cancel() { finish(.cancelled) }
    func expire() { finish(valid() && store.writable ? .timedOut : .cancelled) }

    private func receive(_ url: URL?, title: String, index: Int) {
        guard !finished else { return }
        guard valid(), store.writable else { cancel(); return }
        guard received.insert(index).inserted else { return }
        if let url, url.absoluteString.count <= 8_192, let clean = SavedPageAddress.clean(url) {
            links[index] = WallDroppedLink(url: clean, title: title)
        }
        guard received.count == links.count else { return }
        var seen: Set<String> = []
        let accepted = links.compactMap { $0 }.filter { seen.insert($0.url.absoluteString).inserted }
        guard !accepted.isEmpty else { finish(.invalid); return }
        if store.addDroppedLinks(accepted, at: point) {
            finish(.saved(accepted.count, skipped: links.count - accepted.count))
        } else { finish(.failed(store.problem ?? "This Wall cannot be changed")) }
    }

    private func finish(_ result: Result) {
        guard !finished else { return }
        finished = true
        progress.forEach { $0.cancel() }; progress.removeAll()
        watching.removeAll(); links.removeAll()
        complete(result)
    }
}

extension Browser {
    func canDropLinks(on store: WorkspaceStore) -> Bool {
        spaceID == store.snapshot.spaceID && active?.wallSpaceID == spaceID
            && !(CanvasSurface.inView(window?.contentView)?.controller.readOnly ?? false)
            && store.writable && canOpenWall && !editing && window?.attachedSheet == nil
    }

    @discardableResult
    func dropWallLinks(_ providers: [NSItemProvider], at location: CGPoint, viewport: WallViewport,
                       store: WorkspaceStore) -> Bool {
        guard canDropLinks(on: store), let wall = active else { return false }
        let space = spaceID
        guard let request = WallLinkDrop.start(providers, at: location, viewport: viewport, store: store,
            valid: { [weak self, weak wall] in
                guard let self, let wall else { return false }
                return self.canDropLinks(on: store) && self.active === wall
                    && self.tabs.contains(where: { $0 === wall })
            }, complete: { [weak self] result in
                switch result {
                case .saved(let count, let skipped):
                    self?.announce("\(count == 1 ? "Link" : "\(count) links") saved to Wall" + (skipped > 0 ? " · \(skipped) skipped" : ""))
                case .invalid: self?.announce("Drop an HTTP or HTTPS web link")
                case .timedOut: self?.announce("The drag source did not provide its links in time")
                case .failed(let message): self?.announce(message)
                case .cancelled: break
                }
            }) else {
            announce("Drop up to \(WallLinkDrop.limit) web links at a time")
            return false
        }
        request.watch($activeID.filter { $0 != wall.id }.sink { [weak request] _ in request?.cancel() })
        request.watch($spaceID.filter { $0 != space }.sink { [weak request] _ in request?.cancel() })
        return true
    }
}

struct WallDropTarget: DropDelegate {
    let browser: Browser
    let store: WorkspaceStore
    let viewport: WallViewport
    @Binding var landing: Bool

    func validateDrop(info: DropInfo) -> Bool {
        browser.canDropLinks(on: store) && WallLinkDrop.accepts(info.itemProviders(for: [UTType.url]))
    }
    func dropEntered(info: DropInfo) { landing = validateDrop(info: info) }
    func dropExited(info: DropInfo) { landing = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .copy : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        landing = false
        return browser.dropWallLinks(info.itemProviders(for: [UTType.url]), at: info.location, viewport: viewport, store: store)
    }
}
