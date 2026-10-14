import SwiftUI

enum WallLayout {
    /// Fit every card, including culled/offscreen ones, without moving objects.
    static func fit(_ placements: [WallPlacement], in size: CGSize) -> WallViewport? {
        guard !placements.isEmpty, size.width.isFinite, size.height.isFinite,
              size.width > 80, size.height > 80 else { return nil }
        let bounds = placements.reduce(CGRect.null) { bounds, card in
            bounds.union(CGRect(x: card.x, y: card.y, width: card.width, height: card.height))
        }
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return nil }
        let zoom = min(4, max(0.05, min((size.width - 80) / bounds.width, (size.height - 80) / bounds.height)))
        let view = WallViewport(x: min(1_000_000, max(-1_000_000, size.width / 2 - bounds.midX * zoom)),
                                y: min(1_000_000, max(-1_000_000, size.height / 2 - bounds.midY * zoom)), zoom: zoom)
        return view.valid ? view : nil
    }
}

enum WallConnectionTargets {
    static func matching(_ objects: [LocusObject], excluding id: UUID, query: String) -> [LocusObject] {
        let query = String(query.prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
        return objects.filter {
            $0.supported && $0.id != id && (query.isEmpty || $0.title.localizedStandardContains(query) || $0.kindTitle.localizedStandardContains(query))
        }
    }
}

final class WallMenuItem: NSMenuItem {
    private let act: () -> Void
    init(_ title: String, enabled: Bool = true, act: @escaping () -> Void) {
        self.act = act
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self; isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { act() }
}
