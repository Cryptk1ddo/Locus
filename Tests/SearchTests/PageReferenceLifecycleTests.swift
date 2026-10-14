import XCTest
@testable import Search

final class PageReferenceLifecycleTests: XCTestCase {
    private func file() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("page-lifecycle-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("workspace.json")
    }
    private var png: Data { Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII=")! }
    private func page(_ title: String = "Original") -> LocusObject {
        LocusObject(type: "page", title: title, content: ["url": .string("https://example.test/original")])
    }
    private func capture() -> LocusObject {
        LocusObject(type: "uiCapture", title: "Button", content: ["url": .string("https://example.test/original"), "screenshot": .dictionary(["status": .string("captured")])])
    }

    func testClosedBindingNeverResolvesInAnotherSpaceEvenWithSameObjectID() {
        let object = page(), space = UUID()
        let binding = WallBinding(spaceID: space, objectID: object.id)
        XCTAssertEqual(binding.resolved(in: WorkspaceSnapshot(spaceID: space, objects: [object])), binding)
        XCTAssertNil(binding.resolved(in: WorkspaceSnapshot(spaceID: UUID(), objects: [object])))
        XCTAssertNil(binding.resolved(in: WorkspaceSnapshot(spaceID: space)))
    }

    @MainActor
    func testExplicitUpdatePreservesUnknownFieldsAndCaptureEvidence() throws {
        let store = WorkspaceStore(space: UUID(), file: try file())
        var fields = page().fields
        fields["futureEnvelope"] = .string("kept")
        fields["source"] = .dictionary(["url": .string("https://example.test/original"), "futureSource": .bool(true)])
        fields["content"] = .dictionary(["url": .string("https://example.test/original"), "futureContent": .number(42)])
        let original = try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))
        store.add(original)
        XCTAssertTrue(store.addCapture(capture(), png: png, sourcePage: original))
        let evidence = try XCTUnwrap(store.snapshot.objects.first { $0.type == "uiCapture" })
        let asset = try XCTUnwrap(evidence.snapshotID)
        XCTAssertTrue(store.updatePage(original, title: "Updated", url: URL(string: "https://user:secret@example.test/new?q=kept#fragment")!))
        let updated = try XCTUnwrap(store.snapshot.objects.first { $0.id == original.id })
        XCTAssertEqual(updated.url?.absoluteString, "https://example.test/new?q=kept#fragment")
        XCTAssertEqual(updated.fields["futureEnvelope"], .string("kept"))
        XCTAssertEqual(updated.content["futureContent"], .number(42))
        guard case .dictionary(let source) = updated.fields["source"] else { return XCTFail("missing source") }
        XCTAssertEqual(source["futureSource"], .bool(true))
        XCTAssertEqual(source["url"], .string(updated.url!.absoluteString))
        XCTAssertEqual(store.snapshot.objects.first { $0.id == evidence.id }, evidence)
        XCTAssertEqual(try Data(contentsOf: store.assetURL(asset)), png)
        XCTAssertEqual(store.suggestions(for: "updated").count, 1)
        let snapshot = store.snapshot, data = try Data(contentsOf: store.file)
        XCTAssertFalse(store.updatePage(original, title: "Stale", url: URL(string: "https://stale.test")!))
        XCTAssertEqual(store.snapshot, snapshot)
        XCTAssertEqual(try Data(contentsOf: store.file), data)
    }

    @MainActor
    func testUpdateFailureAndUnsupportedAddressDoNotPublish() throws {
        let path = try file(), space = UUID(), object = page()
        let store = WorkspaceStore(space: space, file: path)
        store.add(object)
        let data = try Data(contentsOf: path)
        let failing = WorkspaceStore(space: space, file: path, write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertFalse(failing.updatePage(object, title: "Failed", url: URL(string: "https://new.test")!))
        XCTAssertEqual(failing.snapshot, store.snapshot)
        XCTAssertEqual(try Data(contentsOf: path), data)
        for text in ["file:///tmp/private", "javascript:alert(1)", "http:relative"] {
            XCTAssertFalse(store.updatePage(object, title: "Invalid", url: URL(string: text)!))
        }
        XCTAssertEqual(try Data(contentsOf: path), data)
    }

    @MainActor
    func testRecaptureRetainsOriginalAssetAndBothRelationships() throws {
        let store = WorkspaceStore(space: UUID(), file: try file()), source = page()
        XCTAssertTrue(store.addCapture(capture(), png: png, sourcePage: source))
        let original = try XCTUnwrap(store.snapshot.objects.first { $0.type == "uiCapture" })
        let originalAsset = try XCTUnwrap(original.snapshotID)
        XCTAssertTrue(store.addCapture(capture(), png: png, sourcePage: source, derivedFrom: original.id))
        let new = try XCTUnwrap(store.snapshot.objects.last)
        XCTAssertEqual(new.relationshipTarget("capturedFrom"), source.id)
        XCTAssertEqual(new.relationshipTarget("derivedFrom"), original.id)
        XCTAssertNotEqual(new.snapshotID, original.snapshotID)
        XCTAssertEqual(store.snapshot.objects.first { $0.id == original.id }, original)
        XCTAssertEqual(try Data(contentsOf: store.assetURL(originalAsset)), png)
        let loaded = WorkspaceStore(space: store.snapshot.spaceID, file: store.file)
        XCTAssertEqual(loaded.snapshot, store.snapshot)
    }

    @MainActor
    func testMissingOrWrongRecaptureSourceDoesNotStageAnAsset() throws {
        let store = WorkspaceStore(space: UUID(), file: try file()), source = page(), wrong = page("Other")
        XCTAssertTrue(store.addCapture(capture(), png: png, sourcePage: source))
        let original = try XCTUnwrap(store.snapshot.objects.first { $0.type == "uiCapture" })
        let assets = store.file.deletingLastPathComponent().appendingPathComponent("assets")
        let files = try FileManager.default.contentsOfDirectory(atPath: assets.path)
        let before = store.snapshot
        XCTAssertFalse(store.addCapture(capture(), png: png, sourcePage: wrong, derivedFrom: original.id))
        XCTAssertEqual(store.snapshot, before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: assets.path), files)
        store.deleteObject(source.id)
        let deleted = store.snapshot
        XCTAssertFalse(store.addCapture(capture(), png: png, sourcePage: source, derivedFrom: original.id))
        XCTAssertEqual(store.snapshot, deleted)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: assets.path), files)
    }
}
