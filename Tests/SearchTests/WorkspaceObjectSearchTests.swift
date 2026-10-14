import XCTest
@testable import Search

final class WorkspaceObjectSearchTests: XCTestCase {
    func testExplicitScopeAndOrdinaryInputs() {
        XCTAssertEqual(WorkspaceObjectSearch.query(from: " WALL: Café "), "Café")
        XCTAssertEqual(WorkspaceObjectSearch.query(from: "wall:"), "")
        for text in ["wall art", "wall", "wallpaper", "https://wall.test", "wall://host", "wall:example"] {
            XCTAssertNil(WorkspaceObjectSearch.query(from: text), text)
        }
        XCTAssertEqual(WorkspaceObjectSearch.query(from: "wall: " + String(repeating: "a", count: 500))?.count, 256)
    }

    func testTitleRankingTermsAndDiacritics() {
        let exact = LocusObject(type: "note", title: "Café", content: [:])
        let prefix = LocusObject(type: "note", title: "Cafe research", content: [:])
        let body = LocusObject(type: "note", title: "Notes", content: ["text": .string("cafe research")])
        let page = LocusObject(type: "page", title: "Reference", content: ["url": .string("https://cafe.test/research")])
        let snapshot = WorkspaceSnapshot(spaceID: UUID(), objects: [body, page, prefix, exact])
        let results = WorkspaceObjectSearch.results(in: snapshot, query: "cafe")
        XCTAssertEqual(Array(results.prefix(2).map(\.key)), ["Café", "Cafe research"])
        XCTAssertEqual(WorkspaceObjectSearch.results(in: snapshot, query: "research cafe").count, 3)
        XCTAssertTrue(WorkspaceObjectSearch.results(in: snapshot, query: "cafe absent").isEmpty)
    }

    @MainActor
    func testTypedTargetsDistinctIdentitiesAndNoCompletion() {
        let space = UUID()
        let objects = (0..<10).map { _ in LocusObject(type: "note", title: "www.same", content: [:]) }
        let snapshot = WorkspaceSnapshot(spaceID: space, objects: objects)
        let results = WorkspaceObjectSearch.results(in: snapshot, query: "", limit: 100)
        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(Set(results.map(\.id)).count, 5)
        for result in results {
            XCTAssertNil(result.url)
            XCTAssertEqual(result.displayKey, "www.same")
            guard case .object(let targetSpace, let id) = result.kind else { return XCTFail("missing typed target") }
            XCTAssertEqual(targetSpace, space)
            XCTAssertTrue(objects.contains { $0.id == id })
        }
        XCTAssertNil(History().completion(for: "www", among: results))
        XCTAssertNil(Suggestion.command(.openWall).url)
        XCTAssertTrue(WorkspaceObjectSearch.results(in: snapshot, query: "", limit: -1).isEmpty)
    }

    func testOpaqueCaptureAndUnknownPayloadsAreNotSearched() {
        let capture = LocusObject(type: "uiCapture", title: "Button", content: ["dom": .string("hidden capture words"), "text": .string("hidden"), "description": .string("hidden")])
        let unknown = LocusObject(type: "future", title: "hidden capture words", content: [:])
        let longNote = LocusObject(type: "note", title: "Long", content: ["text": .string(String(repeating: "x", count: 8_192) + " unseen")])
        let snapshot = WorkspaceSnapshot(spaceID: UUID(), objects: [capture, unknown, longNote])
        XCTAssertTrue(WorkspaceObjectSearch.results(in: snapshot, query: "hidden").isEmpty)
        XCTAssertTrue(WorkspaceObjectSearch.results(in: snapshot, query: "unseen").isEmpty)
        XCTAssertEqual(WorkspaceObjectSearch.results(in: snapshot, query: "button").first?.key, "Button")
    }

    @MainActor
    func testIndexTracksOnlyCommittedRevisions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("locus-object-search-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var rejectWrites = false
        let store = WorkspaceStore(space: UUID(), file: root.appendingPathComponent("workspace.json")) { data, url in
            if rejectWrites { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        XCTAssertTrue(store.suggestions(for: "").isEmpty)
        let note = LocusObject(type: "note", title: "Original", content: [:])
        store.add(note)
        XCTAssertEqual(store.suggestions(for: "original").count, 1)
        rejectWrites = true
        XCTAssertFalse(store.editNote(note.id, title: "Uncommitted", text: ""))
        XCTAssertTrue(store.suggestions(for: "uncommitted").isEmpty)
        XCTAssertEqual(store.suggestions(for: "original").count, 1)
        rejectWrites = false
        XCTAssertTrue(store.editNote(note.id, title: "Renamed", text: ""))
        XCTAssertTrue(store.suggestions(for: "original").isEmpty)
        XCTAssertEqual(store.suggestions(for: "renamed").count, 1)
        store.deleteObject(note.id)
        XCTAssertTrue(store.suggestions(for: "renamed").isEmpty)
    }
}
