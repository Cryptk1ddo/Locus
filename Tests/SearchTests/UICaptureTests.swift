import XCTest
@testable import Search

final class UICaptureTests: XCTestCase {
    @MainActor
    func testGeometryMapsCSSViewportToNativePointsAndClampsVisibleCrop() {
        let payload: [String: ObjectValue] = ["geometry": .dictionary(["value": .dictionary([
            "x": .number(-10), "y": .number(20), "width": .number(100), "height": .number(80),
            "viewportWidth": .number(500), "viewportHeight": .number(400)])])]
        XCTAssertEqual(UICapture.snapshotRect(payload, bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)),
                       CGRect(x: 0, y: 40, width: 180, height: 160))
        XCTAssertNil(UICapture.snapshotRect(payload, bounds: .zero))
        XCTAssertNil(UICapture.snapshotRect([:], bounds: CGRect(x: 0, y: 0, width: 100, height: 100)))
    }

    @MainActor
    func testPayloadRejectsUnboundedAndMalformedData() {
        XCTAssertThrowsError(try UICapture.payload(["text": String(repeating: "x", count: 300_000)]))
        XCTAssertThrowsError(try UICapture.payload(["title": "Malformed"]))
    }

    @MainActor
    func testCaptureAssetCommitsAndRetiresAfterPreviousRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(space: UUID(), file: root.appendingPathComponent("workspace.json"))
        let object = LocusObject(type: "uiCapture", title: "Button", content: ["screenshot": .dictionary(["status": .string("captured")])])
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII="))
        XCTAssertTrue(store.addCapture(object, png: png))
        let saved = try XCTUnwrap(store.snapshot.objects.first)
        let id = try XCTUnwrap(saved.snapshotID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetURL(id).path))
        store.deleteObject(object.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetURL(id).path))
        store.add(LocusObject(type: "note", title: "Advance backup", content: [:]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetURL(id).path), "Undo retains the capture")
        store.discardCanvasHistory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.assetURL(id).path))
    }

    @MainActor
    func testFailedSnapshotCommitRemovesStagedAssetAndDeletedSpaceRejectsCapture() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-failure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(space: UUID(), file: root.appendingPathComponent("workspace.json"),
            write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        let object = LocusObject(type: "uiCapture", title: "Button", content: ["screenshot": .dictionary([:])])
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII="))
        XCTAssertFalse(store.addCapture(object, png: png))
        XCTAssertTrue(store.snapshot.objects.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("assets").path).isEmpty)
        store.erase()
        XCTAssertFalse(store.addCapture(object, png: png))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
