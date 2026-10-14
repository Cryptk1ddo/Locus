import AppKit
import WebKit

extension Browser {
    var canOpenWall: Bool {
        !welcoming && !makingSpace && extensionPopup == nil
            && !tabs.contains { $0.built.map { $0.fullscreenState != .notInFullscreen } ?? false }
    }

    func openWall() {
        guard canOpenWall else { return }
        let source = active.flatMap { isWallSource($0) ? $0 : nil }
        uiCapture?.cancel()
        while closePanel() {}
        if peekTab != nil { closePeek() }
        closeAssistant()
        tabSwitcher.cancel()
        if veiling { toggleHiding() }
        dismiss()
        editing = false
        closeFind()
        reviewing = false
        dropChoice()
        bookmarksOpen = false
        let tab = tabs.first(where: { $0.wallSpaceID == spaceID })
            ?? Tab(configuration: Web.configuration(space: spaceID), wallSpace: spaceID)
        if !tabs.contains(where: { $0.id == tab.id }) {
            prepare(tab)
            insert(tab, at: placeForNew())
        }
        if active?.isWall != true { tab.wallSourceID = source?.id }
        select(tab, floatPrevious: false)
        window?.makeFirstResponder(nil)
    }

    func closeWall() {
        guard let tab = active, tab.isWall else { return }
        close(tab)
    }

    private func isWallSource(_ tab: Tab) -> Bool {
        !tab.isWall && !tab.shy && !tab.bench && tab.held == nil
            && (tab.pageAddress ?? tab.pending ?? tab.address).flatMap(SavedPageAddress.clean) != nil
    }

    var wallSourceTab: Tab? {
        guard let wall = active, wall.wallSpaceID == spaceID,
              let source = tabs.first(where: { $0.id == wall.wallSourceID }), isWallSource(source) else { return nil }
        return source
    }

    var canCaptureWallSource: Bool {
        canOpenWall && wallSourceTab?.built?.isLoading == false
            && wallSourceTab?.built?.configuration.websiteDataStore.isPersistent == true
            && WorkspaceStore.shared(for: spaceID).writable
    }

    func saveWallSourcePage() {
        guard let source = wallSourceTab, let wall = active else { return }
        select(source, floatPrevious: false)
        savePageToWall()
        select(wall, floatPrevious: false)
    }

    func captureWallSource(picking: Bool = true, selector: String? = nil) {
        guard canCaptureWallSource, let source = wallSourceTab else { return }
        select(source, floatPrevious: false)
        startUICapture(picking: picking, selector: selector)
    }

    func collectWallSource(delay: TimeInterval = 0) {
        guard canCaptureWallSource, !collectingInspiration, let source = wallSourceTab else { return }
        select(source, floatPrevious: false)
        collectInspiration(delay: delay)
    }

    @discardableResult
    func revealWallObject(_ id: UUID, in space: UUID) -> Bool {
        guard space == spaceID, canOpenWall else {
            announce("This object is no longer available in the current Space")
            return false
        }
        let store = WorkspaceStore.shared(for: space)
        guard store.snapshot.objects.contains(where: { $0.id == id && $0.supported }) else {
            announce("This object is no longer available in the current Space")
            return false
        }
        if !store.snapshot.placements.contains(where: { $0.objectID == id }) { store.place(id) }
        guard store.snapshot.placements.contains(where: { $0.objectID == id }) else {
            announce(store.problem ?? "This Wall cannot be changed right now")
            return false
        }
        openWall()
        typed = ""
        picked = nil
        wallReveal = id
        return true
    }

    var canSavePageToWall: Bool {
        guard let tab = active, !tab.isWall, !tab.shy, !tab.bench, tab.held == nil,
              let url = tab.pageAddress ?? tab.pending ?? tab.address else { return false }
        return SavedPageAddress.clean(url) != nil
    }

    func savePageToWall() {
        guard canSavePageToWall, let tab = active,
              let address = tab.pageAddress ?? tab.pending ?? tab.address,
              let url = SavedPageAddress.clean(address) else { return }
        let store = WorkspaceStore.shared(for: spaceID)
        if let id = tab.wallObjectID(in: spaceID) {
            if !store.snapshot.placements.contains(where: { $0.objectID == id }) { store.place(id) }
            return
        }
        let object = LocusObject(type: "page", title: tab.name ?? (tab.title.isEmpty ? url.host() ?? "Page" : tab.title),
                                 content: ["url": .string(url.absoluteString)])
        store.add(object)
        if store.snapshot.objects.contains(where: { $0.id == object.id }) { bindWallPage(object.id, to: tab) }
    }

    func openWallPage(_ object: LocusObject, savedAddress: Bool = false) {
        guard let object = WorkspaceStore.shared(for: spaceID).snapshot.objects.first(where: { $0.id == object.id }),
              let url = object.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.user == nil,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.password == nil else { return }
        if let tab = boundWallTab(object.id) {
            select(tab, floatPrevious: false)
            if savedAddress { tab.go(to: url) }
        } else {
            let tab = open(url, foreground: true)
            bindWallPage(object.id, to: tab)
        }
    }

    func bindWallPage(_ id: UUID, to tab: Tab) {
        guard !tab.isWall, !tab.shy, !tab.bench, tab.held == nil,
              let binding = WallBinding.resolve(id, in: WorkspaceStore.shared(for: spaceID).snapshot) else { return }
        tab.wallBinding = binding
        writeSession()
    }

    func restoreWallBinding(_ binding: WallBinding?, to tab: Tab) {
        guard let binding, binding.spaceID == spaceID, !tab.shy, !tab.bench, tab.held == nil else { return }
        tab.wallBinding = WallBinding.restore(binding.objectID, in: WorkspaceStore.shared(for: spaceID))
    }

    private func boundWallTab(_ id: UUID) -> Tab? {
        if let active, active.wallObjectID(in: spaceID) == id { return active }
        return tabs.filter { $0.wallObjectID(in: spaceID) == id }.max { $0.touched < $1.touched }
    }

    private func pageUpdateSnapshot(_ object: LocusObject) -> (title: String, url: URL)? {
        guard object.supported, object.type == "page",
              let tab = boundWallTab(object.id),
              tab.built?.isLoading != true,
              let address = tab.pending ?? tab.pageAddress ?? tab.address,
              let url = SavedPageAddress.clean(address) else { return nil }
        return (tab.name ?? (tab.title.isEmpty ? url.host() ?? "Page" : tab.title), url)
    }

    func canUpdateWallPage(_ object: LocusObject) -> Bool {
        WorkspaceStore.shared(for: spaceID).writable && pageUpdateSnapshot(object) != nil
    }

    func updateWallPage(_ object: LocusObject) {
        let store = WorkspaceStore.shared(for: spaceID)
        guard store.snapshot.objects.first(where: { $0.id == object.id }) == object else {
            announce("This reference changed. Reopen its menu before updating.")
            return
        }
        guard let value = pageUpdateSnapshot(object) else { announce("Load the bound page before updating its reference"); return }
        if store.updatePage(object, title: value.title, url: value.url) { announce("Saved reference updated") }
        else { announce(store.problem ?? "This Wall cannot be changed") }
    }

    func captureSourcePage(_ capture: LocusObject) -> LocusObject? {
        let objects = WorkspaceStore.shared(for: spaceID).snapshot.objects
        guard let current = objects.first(where: { $0.id == capture.id }), current.supported, current.type == "uiCapture",
              let source = current.relationshipTarget("capturedFrom") else { return nil }
        return objects.first { $0.id == source && $0.supported && $0.type == "page" }
    }

    func canRecaptureUI(_ capture: LocusObject) -> Bool {
        canCaptureUI && WorkspaceStore.shared(for: spaceID).writable
            && captureSourcePage(capture).map { active?.wallObjectID(in: spaceID) == $0.id } == true
    }

    func recaptureUI(_ capture: LocusObject) {
        guard canRecaptureUI(capture) else { announce("Open and load the source page before capturing again"); return }
        startUICapture(derivedFrom: capture.id)
    }
}
