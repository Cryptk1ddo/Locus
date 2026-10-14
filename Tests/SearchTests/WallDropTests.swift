import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import Search

final class WallDropTests: XCTestCase {
    private func file() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("locus-drop-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("workspace.json")
    }

    private func provider(_ address: String, title: String = "", delay: Double = 0) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = title
        provider.registerObject(ofClass: NSURL.self, visibility: .all) { complete in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { complete(NSURL(string: address), nil) }
            return Progress(totalUnitCount: 1)
        }
        return provider
    }

    func testDropCoordinatesInvertPanAndZoomAndRejectInvalidGeometry() {
        XCTAssertEqual(WallViewport(x: 50, y: -30, zoom: 1.25).worldPoint(CGPoint(x: 175, y: 220)), CGPoint(x: 100, y: 200))
        XCTAssertEqual(WallViewport(x: -40, y: 80, zoom: 0.25).worldPoint(CGPoint(x: 10, y: 30)), CGPoint(x: 200, y: -200))
        XCTAssertEqual(WallViewport(zoom: 2).worldPoint(CGPoint(x: 80, y: 100)), CGPoint(x: 40, y: 50))
        XCTAssertNil(WallViewport(zoom: 0).worldPoint(.zero))
        XCTAssertNil(WallViewport(x: .infinity).worldPoint(.zero))
        XCTAssertNil(WallViewport().worldPoint(CGPoint(x: CGFloat.nan, y: 0)))
        XCTAssertNil(WallViewport(zoom: 0.25).worldPoint(CGPoint(x: 1_000_000, y: 0)))
    }

    @MainActor func testBatchSavesObjectsAndSpatialLayoutInOneRevision() throws {
        let path = try file(), space = UUID(), store = WorkspaceStore(space: space, file: path)
        let links = (0..<4).map { WallDroppedLink(url: URL(string: "https://dribbble.com/shots/\($0)")!, title: "Shot \($0)") }
        XCTAssertTrue(store.addDroppedLinks(links, at: CGPoint(x: -120, y: 75)))
        XCTAssertEqual(store.snapshot.revision, 1)
        XCTAssertEqual(store.snapshot.objects.map(\.title), ["Shot 0", "Shot 1", "Shot 2", "Shot 3"])
        XCTAssertEqual(store.snapshot.placements.map { CGPoint(x: $0.x, y: $0.y) },
                       [CGPoint(x: -120, y: 75), CGPoint(x: 160, y: 75), CGPoint(x: 440, y: 75), CGPoint(x: -120, y: 275)])
        XCTAssertEqual(store.snapshot, WorkspaceStore(space: space, file: path).snapshot)
        XCTAssertTrue(store.snapshot.objects.allSatisfy { $0.type == "inspiration" && $0.snapshotID == nil && $0.relationships.isEmpty })
    }

    @MainActor func testCurrentWriteFailureAndCapacityLimitRollBackEntireBatch() throws {
        let path = try file(), space = UUID(), store = WorkspaceStore(space: space, file: path)
        store.add(LocusObject(type: "note", title: "Keep", content: [:]))
        let before = store.snapshot, bytes = try Data(contentsOf: path)
        let failing = WorkspaceStore(space: space, file: path, write: { data, target in
            if target == path { throw CocoaError(.fileWriteNoPermission) }
            try WorkspaceFiles.write(data, to: target)
        })
        let links = [WallDroppedLink(url: URL(string: "https://example.com/")!, title: "Drop")]
        XCTAssertFalse(failing.addDroppedLinks(links, at: .zero))
        XCTAssertEqual(failing.snapshot, before)
        XCTAssertEqual(try Data(contentsOf: path), bytes)
        XCTAssertTrue(store.mutate { next in
            next.objects += (0..<1_998).map { LocusObject(type: "note", title: "\($0)", content: [:]) }
        })
        let full = store.snapshot
        XCTAssertFalse(store.addDroppedLinks(links + links, at: .zero))
        XCTAssertEqual(store.snapshot, full)
        XCTAssertEqual(WorkspaceStore(space: space, file: path).snapshot, full)
    }

    @MainActor func testNativeProvidersKeepInputOrderCleanCredentialsAndCoalesceBatchDuplicates() async throws {
        let store = WorkspaceStore(space: UUID(), file: try file())
        let done = expectation(description: "drop saved")
        let providers = [provider("https://www.pinterest.com/pin/123/", title: "First", delay: 0.08),
                         provider("https://user:secret@www.pinterest.com/pin/123/", title: "Duplicate"),
                         provider("javascript:alert(1)"), provider("file:///tmp/private"),
                         provider("https://www.are.na/alex/design", title: "Second")]
        XCTAssertNotNil(WallLinkDrop.start(providers, at: CGPoint(x: 175, y: 220),
            viewport: WallViewport(x: 50, y: -30, zoom: 1.25), store: store, valid: { true }) { result in
                XCTAssertEqual(result, .saved(2, skipped: 3)); done.fulfill()
            })
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(store.snapshot.objects.map(\.title), ["First", "Second"])
        XCTAssertEqual(store.snapshot.objects.map { $0.content["provider"] }, [.string("pinterest"), .string("arena")])
        XCTAssertEqual(store.snapshot.revision, 1)
        XCTAssertEqual(store.snapshot.placements.first?.x, 100)
        XCTAssertEqual(store.snapshot.placements.first?.y, 200)
        XCTAssertTrue(store.snapshot.objects.allSatisfy { $0.url?.user == nil && $0.url?.password == nil })
        let id = store.snapshot.objects[0].id, again = expectation(description: "another deliberate drop")
        _ = WallLinkDrop.start([providers[0]], at: .zero, viewport: WallViewport(), store: store, valid: { true }) { _ in again.fulfill() }
        await fulfillment(of: [again], timeout: 3)
        XCTAssertEqual(store.snapshot.objects.count, 3)
        XCTAssertNotEqual(store.snapshot.objects.last?.id, id)
    }

    @MainActor func testInvalidAndOversizedAddressesNeverPublish() async throws {
        let store = WorkspaceStore(space: UUID(), file: try file()), done = expectation(description: "invalid drop")
        _ = WallLinkDrop.start([provider("locus://wall/\(UUID())"), provider("data:text/html,hi"),
                              provider("https://example.com/" + String(repeating: "a", count: 8_192))],
            at: .zero, viewport: WallViewport(), store: store, valid: { true }) { result in
                XCTAssertEqual(result, .invalid); done.fulfill()
            }
        await fulfillment(of: [done], timeout: 3)
        XCTAssertTrue(store.snapshot.objects.isEmpty)
        XCTAssertEqual(store.snapshot.revision, 0)
    }

    @MainActor func testTargetInvalidationAndExplicitCancellationPreventLatePublication() async throws {
        for explicit in [false, true] {
            let store = WorkspaceStore(space: UUID(), file: try file())
            var current = true
            let done = expectation(description: "cancelled \(explicit)")
            let request = try XCTUnwrap(WallLinkDrop.start([provider("https://example.com/", delay: 0.08)],
                at: .zero, viewport: WallViewport(), store: store, valid: { current }) { result in
                    XCTAssertEqual(result, .cancelled); done.fulfill()
                })
            if explicit { request.cancel(); current = true } else { current = false }
            await fulfillment(of: [done], timeout: 3)
            try await Task.sleep(for: .milliseconds(150))
            request.expire()
            XCTAssertTrue(store.snapshot.objects.isEmpty)
            XCTAssertEqual(store.snapshot.revision, 0)
        }
    }

    @MainActor func testDeadlineIsFinalEvenWhenProviderLaterReturns() async throws {
        let store = WorkspaceStore(space: UUID(), file: try file()), done = expectation(description: "expired")
        var replies = 0
        let request = try XCTUnwrap(WallLinkDrop.start([provider("https://example.com/", delay: 0.08)],
            at: .zero, viewport: WallViewport(), store: store, valid: { true }) { result in
                replies += 1; XCTAssertEqual(result, .timedOut); done.fulfill()
            })
        request.expire()
        await fulfillment(of: [done], timeout: 3)
        try await Task.sleep(for: .milliseconds(150))
        request.cancel(); request.expire()
        XCTAssertEqual(replies, 1)
        XCTAssertTrue(store.snapshot.objects.isEmpty)
    }

    @MainActor func testAcceptanceBoundsAndUnavailableStore() throws {
        let item = provider("https://example.com/")
        XCTAssertTrue(WallLinkDrop.accepts(Array(repeating: item, count: 20)))
        XCTAssertFalse(WallLinkDrop.accepts(Array(repeating: item, count: 21)))
        XCTAssertFalse(WallLinkDrop.accepts([]))
        // NSString's writer deliberately advertises public.url for this address.
        XCTAssertTrue(WallLinkDrop.accepts([NSItemProvider(object: "https://example.com/" as NSString)]))
        let text = NSItemProvider()
        text.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { complete in
            complete(Data("https://example.com/".utf8), nil); return nil
        }
        XCTAssertFalse(WallLinkDrop.accepts([text]))
        let store = WorkspaceStore(space: UUID(), file: try file())
        XCTAssertNil(WallLinkDrop.start([item], at: .zero, viewport: WallViewport(), store: store, valid: { false }) { _ in XCTFail("Rejected request completed") })
        store.erase()
        XCTAssertNil(WallLinkDrop.start([item], at: .zero, viewport: WallViewport(), store: store, valid: { true }) { _ in XCTFail("Unavailable store completed") })
    }
}
