import XCTest
import AppKit
@testable import Search

final class CanvasImportTests: XCTestCase {
    @MainActor func fixture() throws -> (URL, WorkspaceStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-import-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, WorkspaceStore(space: UUID(), file: root.appendingPathComponent("workspace.json")))
    }
    func document(_ root: URL, references: [(String,String)]) throws {
        let nodes = references.enumerated().map { index, row -> [String: Any] in
            var node: [String: Any] = ["id": String(index), "type": row.0, "x": index * 300, "y": 0, "width": 240, "height": 200, "subpath": "#Heading"]
            node[row.0 == "group" ? "background" : "file"] = row.1; return node
        }
        try JSONSerialization.data(withJSONObject: ["nodes": nodes]).write(to: root.appendingPathComponent("Wall.canvas"))
    }
    @MainActor func testDirectFilesAndGroupBackgroundsImportAsOneUndo() throws {
        let (root, store) = try fixture()
        try Data("# Heading\nGranted note".utf8).write(to: root.appendingPathComponent("Note.md"))
        try Data("image fixture".utf8).write(to: root.appendingPathComponent("Image.png"))
        try document(root, references: [("file","Note.md"),("group","Image.png")])
        let before = store.snapshot
        let result = try CanvasImport.portable(root, into: store, at: CGPoint(x: 100,y: 80))
        XCTAssertEqual(result.granted, 2); XCTAssertEqual(result.unresolved, 0); XCTAssertEqual(result.selected.count, 2)
        XCTAssertEqual(store.snapshot.placements[0].x, 100); XCTAssertEqual(store.snapshot.placements[0].y, 80)
        for object in store.snapshot.objects {
            XCTAssertNotNil(object.content["bookmark"]); XCTAssertNotNil(CanvasFiles.withURL(object) { $0 })
        }
        XCTAssertTrue(store.undoCanvas()); XCTAssertEqual(store.snapshot.objects, before.objects)
        XCTAssertTrue(store.redoCanvas()); XCTAssertEqual(store.snapshot.objects.count, 2)
        let output = try String(decoding: CanvasJSON.export(store.snapshot), as: UTF8.self)
        XCTAssertTrue(output.contains("#Heading")); XCTAssertFalse(output.contains("bookmark"))
    }
    @MainActor func testMissingTraversalAbsoluteAndSymlinkReferencesStayUnresolved() throws {
        let (root, store) = try fixture()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
        try document(root, references: [("file","missing.md"),("file","../outside"),("file","/etc/passwd"),("group","linked")])
        let result = try CanvasImport.portable(root, into: store)
        XCTAssertEqual(result.unresolved, 4); XCTAssertEqual(result.granted, 0)
        XCTAssertTrue(store.snapshot.objects.allSatisfy { $0.content["bookmark"] == nil })
    }
    @MainActor func testOversizeAndInvalidDocumentDoNotMutateWorkspace() throws {
        let (root, store) = try fixture(), large = root.appendingPathComponent("large.bin")
        FileManager.default.createFile(atPath: large.path, contents: Data())
        let handle = try FileHandle(forWritingTo: large); try handle.truncate(atOffset: UInt64(CanvasExport.assetLimit + 1)); try handle.close()
        try document(root, references: [("file","large.bin")]); let before = store.snapshot
        XCTAssertThrowsError(try CanvasImport.portable(root, into: store)); XCTAssertEqual(store.snapshot, before)
        try Data(#"{"nodes":[{"id":"invalid","type":"file","file":"large.bin"}]}"#.utf8).write(to: root.appendingPathComponent("Wall.canvas"))
        XCTAssertThrowsError(try CanvasImport.portable(root, into: store)); XCTAssertEqual(store.snapshot, before)
    }
    @MainActor func testPortableExportImportRoundTripAndNoSourceWrites() throws {
        let (root, store) = try fixture(), note = root.appendingPathComponent("Note.md")
        let text = Data("Source remains unchanged".utf8); try text.write(to: note)
        XCTAssertTrue(CanvasFiles.add([note], to: store, at: .zero))
        let destination = root.appendingPathComponent("Portable")
        try CanvasExport.portable(store.snapshot, store: store, to: destination)
        let second = WorkspaceStore(space: UUID(), file: root.appendingPathComponent("second.json"))
        let result = try CanvasImport.portable(destination, into: second)
        XCTAssertEqual(result.granted, 1)
        let object = try XCTUnwrap(second.snapshot.objects.first)
        XCTAssertEqual(try CanvasFiles.withURL(object) { try Data(contentsOf: $0) }, text)
        XCTAssertEqual(try Data(contentsOf: note), text)
        XCTAssertFalse(CanvasVault.shared(workspace: second.file).connected)
    }
    @MainActor func testManifestCannotGrantExternalAccessAndCanvasSymlinkIsRejected() throws {
        let (root, store) = try fixture()
        try document(root, references: [("file","/etc/passwd")])
        try Data(#"{"previews":[{"file":"/etc/passwd"}],"bookmark":"forged"}"#.utf8).write(to: root.appendingPathComponent("manifest.json"))
        XCTAssertEqual(try CanvasImport.portable(root, into: store).granted, 0)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Wall.canvas"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Wall.canvas"), withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
        let before = store.snapshot; XCTAssertThrowsError(try CanvasImport.portable(root, into: store)); XCTAssertEqual(store.snapshot, before)
    }
    func previewFixture(_ root: URL, rows: [[String: Any]]? = nil, valid: Bool = true) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.systemBlue, atX: x, y: y) } }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try (valid ? png : Data("invalid".utf8)).write(to: root.appendingPathComponent("preview.png"))
        try JSONSerialization.data(withJSONObject: ["nodes": [["id":"link", "type":"link", "url":"https://example.com/design?utm_source=test", "x":0, "y":0, "width":320, "height":240]]]).write(to: root.appendingPathComponent("Wall.canvas"))
        try JSONSerialization.data(withJSONObject: ["version":1,"previews": rows ?? [["node":"link","file":"preview.png","title":"Design reference"]]]).write(to: root.appendingPathComponent("manifest.json"))
        return png
    }
    @MainActor func testOwnedLinkPreviewSurvivesSourceRemovalAndUndoRedo() throws {
        let (root, store) = try fixture(); let png = try previewFixture(root)
        let result = try CanvasImport.portable(root, into: store)
        XCTAssertEqual(result.previews, 1); XCTAssertEqual(result.unresolved, 0)
        let object = try XCTUnwrap(store.snapshot.objects.first); XCTAssertEqual(object.type, "inspiration"); XCTAssertEqual(object.title, "Design reference")
        let id = try XCTUnwrap(object.snapshotID)
        XCTAssertEqual(try Data(contentsOf: store.assetURL(id)), png)
        try FileManager.default.removeItem(at: root.appendingPathComponent("preview.png"))
        XCTAssertNotNil(WorkspaceImage.image(object, store: store))
        XCTAssertTrue(store.undoCanvas()); XCTAssertTrue(store.snapshot.objects.isEmpty)
        XCTAssertTrue(store.redoCanvas()); XCTAssertEqual(store.snapshot.objects[0].snapshotID, id)
        XCTAssertEqual(try CanvasExport.owned(store.snapshot.objects[0], store: store), png)
        let document = try String(decoding: CanvasJSON.export(store.snapshot), as: UTF8.self)
        XCTAssertTrue(document.contains("link")); XCTAssertFalse(document.contains("assetID"))
    }
    @MainActor func testPreviewOutsideGrantSymlinkAndInvalidPNGRemainLinks() throws {
        for path in ["/etc/passwd", "../outside.png", "linked.png", "preview.png"] {
            let (root, store) = try fixture(); _ = try previewFixture(root, rows: [["node":"link","file":path]], valid: false)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.png"), withDestinationURL: root.appendingPathComponent("preview.png"))
            let result = try CanvasImport.portable(root, into: store)
            XCTAssertEqual(result.previews, 0); XCTAssertEqual(result.unresolved, 1)
            XCTAssertEqual(store.snapshot.objects[0].type, "web"); XCTAssertNil(store.snapshot.objects[0].snapshotID)
        }
    }
    @MainActor func testDuplicatePreviewMappingDoesNotPickArbitraryImage() throws {
        let (root, store) = try fixture()
        _ = try previewFixture(root, rows: [["node":"link","file":"preview.png"],["node":"link","file":"preview.png"]])
        let result = try CanvasImport.portable(root, into: store)
        XCTAssertEqual(result.previews, 0); XCTAssertEqual(result.unresolved, 1)
        XCTAssertEqual(store.snapshot.objects[0].type, "web")
    }
    @MainActor func testInvalidDocumentCleansStagedPreviewAssets() throws {
        let (root, store) = try fixture(); _ = try previewFixture(root)
        var data = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Wall.canvas"))) as! [String: Any]
        data["edges"] = [["id":"bad","fromNode":"link","toNode":"missing"]]
        try JSONSerialization.data(withJSONObject: data).write(to: root.appendingPathComponent("Wall.canvas"))
        let before = store.snapshot
        XCTAssertThrowsError(try CanvasImport.portable(root, into: store)); XCTAssertEqual(store.snapshot, before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.assetURL(UUID()).deletingLastPathComponent().path).count, 0)
    }
    @MainActor func testSavedPreviewExportImportRoundTripKeepsTitleAndImage() throws {
        let (root, store) = try fixture(); let png = try previewFixture(root)
        try CanvasImport.portable(root, into: store)
        let destination = root.appendingPathComponent("RoundTrip")
        XCTAssertEqual(try CanvasExport.portable(store.snapshot, store: store, to: destination), 0)
        let second = WorkspaceStore(space: UUID(), file: root.appendingPathComponent("other/workspace.json"))
        XCTAssertEqual(try CanvasImport.portable(destination, into: second).previews, 1)
        XCTAssertEqual(second.snapshot.objects[0].title, "Design reference")
        XCTAssertEqual(try CanvasExport.owned(second.snapshot.objects[0], store: second), png)
    }

}
