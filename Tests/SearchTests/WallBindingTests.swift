import XCTest
@testable import Search

final class WallBindingTests: XCTestCase {
    func testOldAndMalformedObjectIDsDoNotDiscardSessionRows() throws {
        for field in ["", ",\"objectID\":null", ",\"objectID\":123", ",\"objectID\":true", ",\"objectID\":\"not-a-uuid\""] {
            let json = "{\"tabs\":[{\"url\":\"https://example.test\",\"title\":\"Kept\"\(field)}],\"active\":0,\"splits\":[]}"
            let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(json.utf8))
            XCTAssertEqual(shape.tabs.count, 1)
            XCTAssertEqual(shape.tabs[0].title, "Kept")
            XCTAssertNil(shape.tabs[0].objectID)
        }
    }

    func testRoundTripPreservesBindingGroupPinAndSplitIdentity() throws {
        let first = UUID(), second = UUID(), group = UUID(), pin = UUID()
        let shape = Session.Shape(tabs: [
            Session.Entry(url: "https://same.test", title: "One", groupID: group, objectID: first),
            Session.Entry(url: "https://same.test", title: "Two", groupID: group, objectID: second),
            Session.Entry(url: "https://pin.test", title: "Pin", pin: "P", pinID: pin, objectID: UUID())
        ], active: 1, splits: [Session.Split(tabs: [0, 1], sizes: [0.4, 0.6], focused: 1)])
        let loaded = try JSONDecoder().decode(Session.Shape.self, from: JSONEncoder().encode(shape))
        XCTAssertEqual(loaded.tabs.map(\.objectID), shape.tabs.map(\.objectID))
        XCTAssertEqual(loaded.tabs[0].groupID, group)
        XCTAssertEqual(loaded.tabs[2].pinID, pin)
        XCTAssertEqual(loaded.splits[0].tabs, [0, 1])
        XCTAssertEqual(loaded.splits[0].focused, 1)
    }

    func testResolveUsesDurablePageIdentityAndSpace() {
        let page = LocusObject(type: "page", title: "Page", content: ["url": .string("https://same.test")])
        let equalURL = LocusObject(type: "page", title: "Other", content: page.content)
        let note = LocusObject(type: "note", title: "Note", content: [:])
        let unknown = LocusObject(type: "future", title: "Future", content: [:])
        let snapshot = WorkspaceSnapshot(spaceID: UUID(), objects: [page, equalURL, note, unknown])
        XCTAssertEqual(WallBinding.resolve(page.id, in: snapshot), WallBinding(spaceID: snapshot.spaceID, objectID: page.id))
        XCTAssertNotEqual(WallBinding.resolve(page.id, in: snapshot), WallBinding.resolve(equalURL.id, in: snapshot))
        for id in [nil, UUID(), note.id, unknown.id] { XCTAssertNil(WallBinding.resolve(id, in: snapshot)) }
        XCTAssertNil(WallBinding.resolve(page.id, in: WorkspaceSnapshot(spaceID: UUID())))
    }

    func testWindowRecordsKeepPerWindowPinBindingsIndependent() throws {
        let space = UUID(), pin = UUID(), one = UUID(), two = UUID()
        var first = WindowRecord(space: space), second = WindowRecord(space: space)
        first.rows[space.uuidString] = Session.Shape(tabs: [Session.Entry(url: "https://pin.test", title: "Pin", pin: "P", pinID: pin, objectID: one)], active: 0)
        second.rows[space.uuidString] = Session.Shape(tabs: [Session.Entry(url: "https://pin.test", title: "Pin", pin: "P", pinID: pin, objectID: two)], active: 0)
        let loaded = try JSONDecoder().decode([WindowRecord].self, from: JSONEncoder().encode([first, second]))
        XCTAssertEqual(loaded[0].rows[space.uuidString]?.tabs[0].objectID, one)
        XCTAssertEqual(loaded[1].rows[space.uuidString]?.tabs[0].objectID, two)
        XCTAssertEqual(loaded[0].rows[space.uuidString]?.tabs[0].pinID, pin)
    }
}
