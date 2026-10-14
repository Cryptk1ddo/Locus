import XCTest
@testable import Search

final class WallInteractionTests: XCTestCase {
    private func file() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("locus-context-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("workspace.json")
    }

    func testFitIncludesNegativeAndOffscreenCardsWithPadding() throws {
        let cards = [WallPlacement(objectID: UUID(), x: -500, y: -200),
                     WallPlacement(objectID: UUID(), x: 800, y: 400, width: 400, height: 200)]
        let size = CGSize(width: 1_000, height: 650), view = try XCTUnwrap(WallLayout.fit(cards, in: size))
        for card in cards {
            let rect = CGRect(x: card.x * view.zoom + view.x, y: card.y * view.zoom + view.y,
                              width: card.width * view.zoom, height: card.height * view.zoom)
            XCTAssertGreaterThanOrEqual(rect.minX, 40 - 0.001)
            XCTAssertGreaterThanOrEqual(rect.minY, 40 - 0.001)
            XCTAssertLessThanOrEqual(rect.maxX, size.width - 40 + 0.001)
            XCTAssertLessThanOrEqual(rect.maxY, size.height - 40 + 0.001)
        }
        XCTAssertTrue(view.valid)
    }

    func testFitRetainsViewportLimitsAndRejectsEmptyOrUnavailableCanvas() throws {
        XCTAssertNil(WallLayout.fit([], in: CGSize(width: 1_000, height: 650)))
        let small = [WallPlacement(objectID: UUID(), x: 0, y: 0, width: 100, height: 80)]
        XCTAssertEqual(WallLayout.fit(small, in: CGSize(width: 1_000, height: 650))?.zoom, 4)
        XCTAssertNil(WallLayout.fit(small, in: .zero))
        XCTAssertNil(WallLayout.fit(small, in: CGSize(width: CGFloat.infinity, height: 650)))
        let wide = [WallPlacement(objectID: UUID(), x: -1_000_000, y: -1_000_000),
                    WallPlacement(objectID: UUID(), x: 1_000_000, y: 1_000_000)]
        let view = try XCTUnwrap(WallLayout.fit(wide, in: CGSize(width: 1_000, height: 650)))
        XCTAssertEqual(view.zoom, 0.05); XCTAssertTrue(view.valid)
        let far = try XCTUnwrap(WallLayout.fit([WallPlacement(objectID: UUID(), x: 1_000_000, y: 1_000_000)], in: CGSize(width: 1_000, height: 650)))
        XCTAssertTrue(far.valid)
    }

    @MainActor func testContextCreationCommitsAtCapturedWorldPositionAndKeepsGridDefault() throws {
        let path = try file(), space = UUID(), store = WorkspaceStore(space: space, file: path)
        let point = try XCTUnwrap(WallViewport(x: 50, y: -30, zoom: 1.25).worldPoint(CGPoint(x: 175, y: 220)))
        let note = LocusObject(type: "note", title: "Research", content: ["text": .string("Draft confirmed")])
        XCTAssertTrue(store.add(note, at: point))
        XCTAssertEqual(store.snapshot.revision, 1)
        XCTAssertEqual(store.snapshot.placements.map { CGPoint(x: $0.x, y: $0.y) }, [point])
        let link = try XCTUnwrap(InspirationSource.object(url: URL(string: "https://user:secret@www.pinterest.com/pin/123/")!, title: "Reference"))
        XCTAssertTrue(store.addInspiration(link, png: nil, at: CGPoint(x: -200, y: 150)))
        XCTAssertEqual(store.snapshot.revision, 2)
        XCTAssertEqual(store.snapshot.placements.last?.x, -200)
        XCTAssertNil(store.snapshot.objects.last?.url?.user)
        XCTAssertTrue(store.add(LocusObject(type: "note", title: "Header", content: [:])))
        XCTAssertEqual(store.snapshot.placements.last?.x, 620)
        XCTAssertEqual(store.snapshot.placements.last?.y, 40)
        XCTAssertEqual(WorkspaceStore(space: space, file: path).snapshot, store.snapshot)
    }

    @MainActor func testFailedOrInvalidContextCreationDoesNotPublishObjectOrPlacement() throws {
        let path = try file(), space = UUID(), store = WorkspaceStore(space: space, file: path)
        XCTAssertTrue(store.add(LocusObject(type: "note", title: "Keep", content: [:])))
        let before = store.snapshot, bytes = try Data(contentsOf: path)
        let failing = WorkspaceStore(space: space, file: path, write: { data, target in
            if target == path { throw CocoaError(.fileWriteNoPermission) }
            try WorkspaceFiles.write(data, to: target)
        })
        XCTAssertFalse(failing.add(LocusObject(type: "note", title: "Draft", content: [:]), at: CGPoint(x: -200, y: 100)))
        XCTAssertEqual(failing.snapshot, before); XCTAssertEqual(try Data(contentsOf: path), bytes)
        let link = try XCTUnwrap(InspirationSource.object(url: URL(string: "https://example.com/")!, title: "Link"))
        XCTAssertFalse(failing.addInspiration(link, png: nil, at: .zero))
        XCTAssertFalse(store.add(LocusObject(type: "note", title: "Invalid", content: [:]), at: CGPoint(x: CGFloat.nan, y: 0)))
        XCTAssertFalse(store.addInspiration(link, png: nil, at: CGPoint(x: 1_000_001, y: 0)))
        XCTAssertEqual(store.snapshot, before); XCTAssertEqual(try Data(contentsOf: path), bytes)
        store.erase()
        XCTAssertFalse(store.add(LocusObject(type: "note", title: "Held draft", content: [:]), at: .zero))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testConnectionSearchUsesTitleAndTypeWithoutSelfOrFutureObjects() {
        let source = LocusObject(type: "note", title: "Source", content: [:])
        let objects = [source, LocusObject(type: "note", title: "Café design", content: [:]),
                       LocusObject(type: "inspiration", title: "Reference", content: [:]),
                       LocusObject(type: "futureType", title: "Design", content: [:]),
                       LocusObject(type: "note", title: "Café design", content: [:])]
        XCTAssertEqual(WallConnectionTargets.matching(objects, excluding: source.id, query: "  cafe  ").map(\.id), [objects[1].id, objects[4].id])
        XCTAssertEqual(WallConnectionTargets.matching(objects, excluding: source.id, query: "INSPIRATION").map(\.id), [objects[2].id])
        XCTAssertEqual(WallConnectionTargets.matching(objects, excluding: source.id, query: "").map(\.id), [objects[1].id, objects[2].id, objects[4].id])
        XCTAssertTrue(WallConnectionTargets.matching(objects, excluding: source.id, query: "missing").isEmpty)
    }
}
