import XCTest
import WebKit
@testable import Search

final class WallTabTests: XCTestCase {
    func testSessionMarkerRoundTripAndOldRows() throws {
        let space = UUID()
        let shape = Session.Shape(tabs: [
            .init(url: "https://example.test", title: "Page", objectID: UUID()),
            .init(url: "locus://wall/\(space.uuidString)", title: "Wall", nativeKind: "wall")
        ], active: 1)
        let read = try JSONDecoder().decode(Session.Shape.self, from: JSONEncoder().encode(shape))
        XCTAssertNil(read.tabs[0].nativeKind)
        XCTAssertEqual(read.tabs[0].objectID, shape.tabs[0].objectID)
        XCTAssertEqual(read.tabs[1].nativeKind, "wall")
        XCTAssertEqual(read.active, 1)
        let old = Data(#"{"tabs":[{"url":"https://example.test","title":"Page"}],"active":0}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Session.Shape.self, from: old).tabs[0].nativeKind)
    }

    func testMalformedNativeMarkersDoNotQuarantineOrdinarySession() throws {
        for marker in ["42", "true", "{}", "[]", "\"future-kind\""] {
            let data = Data("{\"tabs\":[{\"url\":\"https://example.test\",\"title\":\"Page\"},{\"url\":\"locus://wall/unknown\",\"title\":\"Future\",\"nativeKind\":\(marker)}],\"active\":0}".utf8)
            let read = try JSONDecoder().decode(Session.Shape.self, from: data)
            XCTAssertEqual(read.tabs.count, 2)
            XCTAssertEqual(read.tabs[0].url, "https://example.test")
            XCTAssertNotNil(read.tabs[1].nativeKind)
        }
    }

    @MainActor func testNativeTabNeverBuildsPageThroughWebControls() {
        let space = UUID()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let tab = Tab(configuration: configuration, wallSpace: space)
        let identity = tab.id
        XCTAssertTrue(tab.isWall)
        XCTAssertFalse(tab.isBlank)
        XCTAssertEqual(tab.address, Tab.wallAddress(space))
        XCTAssertNil(tab.pageAddress)
        XCTAssertNil(tab.pending)
        XCTAssertFalse(tab.hollow)
        XCTAssertFalse(tab.wake())
        tab.revive(); tab.reload(); tab.reload(fromOrigin: true)
        tab.back(); tab.forward(); tab.stop()
        tab.magnify(by: 1.2); tab.resetZoom(); tab.applyRememberedZoom()
        tab.startPicking(); tab.stopPicking(); tab.unpeek(""); tab.adoptIcon()
        tab.go(to: URL(string: "https://example.test")!)
        tab.restore(url: URL(string: "https://example.test")!, title: "Page")
        tab.toggleReader { XCTAssertFalse($0) }
        XCTAssertEqual(tab.id, identity)
        XCTAssertEqual(tab.address, Tab.wallAddress(space))
        XCTAssertEqual(tab.label, "Wall")
        XCTAssertNotNil(tab.icon)
        XCTAssertNil(tab.built)
    }
}
