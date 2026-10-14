import XCTest
import AppKit
import PDFKit
@testable import Search

final class CanvasExportTests: XCTestCase {
    @MainActor func fixture() throws -> (URL, WorkspaceStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-export-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, WorkspaceStore(space: UUID(), file: root.appendingPathComponent("workspace.json")))
    }
    @MainActor func testPortableCopiesGrantedSourcesAndKeepsSubpaths() throws {
        let (root, store) = try fixture(), source = root.appendingPathComponent("Secret name.md")
        try Data("# Shared\nSource".utf8).write(to: source)
        XCTAssertTrue(CanvasFiles.add([source], to: store, at: .zero))
        let original = store.snapshot
        let destination = root.appendingPathComponent("Export")
        XCTAssertEqual(try CanvasExport.portable(original, store: store, to: destination), 0)
        let json = try JSONDecoder().decode([String:ObjectValue].self, from: Data(contentsOf: destination.appendingPathComponent("Wall.canvas")))
        guard case .array(let nodes) = json["nodes"], case .dictionary(let node) = nodes[0] else { return XCTFail() }
        XCTAssertEqual(node["file"], .string("assets/1.md")); XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("assets/1.md"), encoding: .utf8), "# Shared\nSource")
        XCTAssertEqual(store.snapshot, original)
    }
    @MainActor func testUntrustedImportedPathsAreListedWithoutReading() throws {
        let (root, store) = try fixture()
        let data = Data(##"{"nodes":[{"id":"one","type":"file","x":0,"y":0,"width":200,"height":100,"file":"/etc/passwd","subpath":"#Heading","plugin":"keep"}]}"##.utf8)
        try CanvasJSON.importData(data, into: store)
        let destination = root.appendingPathComponent("Export")
        XCTAssertEqual(try CanvasExport.portable(store.snapshot, store: store, to: destination), 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent("assets").path).isEmpty)
        let text = try String(contentsOf: destination.appendingPathComponent("Wall.canvas"), encoding: .utf8)
        XCTAssertTrue(text.contains("#Heading")); XCTAssertTrue(text.contains("keep"))
    }
    @MainActor func testExistingDestinationAndOversizeLeaveNoPartialExport() throws {
        let (root, store) = try fixture(), source = root.appendingPathComponent("large.bin")
        FileManager.default.createFile(atPath: source.path, contents: Data())
        let handle = try FileHandle(forWritingTo: source); try handle.truncate(atOffset: UInt64(CanvasExport.assetLimit + 1)); try handle.close()
        XCTAssertTrue(CanvasFiles.add([source], to: store, at: .zero))
        let destination = root.appendingPathComponent("Export")
        XCTAssertThrowsError(try CanvasExport.portable(store.snapshot, store: store, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".locus-export") })
        try Data("Preserve".utf8).write(to: destination)
        XCTAssertThrowsError(try CanvasExport.portable(store.snapshot, store: store, to: destination))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "Preserve")
    }
    @MainActor func testSelectionExportsOnlyContainedEdgesAndPreservesMetadata() throws {
        let (_, store) = try fixture()
        for title in ["A","B","C"] { XCTAssertTrue(store.add(LocusObject(type: "note", title: title, content: ["text": .string(title)]))) }
        let cards = store.snapshot.placements
        var a = CanvasEdge(from: cards[0].id, to: cards[1].id); a.label = "Related"; XCTAssertTrue(store.saveCanvasEdge(a))
        let b = CanvasEdge(from: cards[1].id, to: cards[2].id); XCTAssertTrue(store.saveCanvasEdge(b))
        let selection = Set(cards.prefix(2).map(\.id))
        let fields = try JSONDecoder().decode([String:ObjectValue].self, from: CanvasJSON.export(store.snapshot, selection: selection))
        guard case .array(let nodes) = fields["nodes"], case .array(let edges) = fields["edges"] else { return XCTFail() }
        XCTAssertEqual(nodes.count, 2); XCTAssertEqual(edges.count, 1)
    }
    @MainActor func testOwnedCaptureExportsImageAndIntegrityFailureIsReported() throws {
        let (root, store) = try fixture()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.systemBlue, atX: x, y: y) } }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertTrue(WorkspaceImage.validPNG(png))
        var capture = LocusObject(type: "uiCapture", title: "Capture", content: ["screenshot": .dictionary([:])])
        let id = UUID(); capture.attachSnapshot(id, bytes: png.count, sha256: WorkspaceImage.digest(png))
        try WorkspaceFiles.write(png, to: store.assetURL(id)); XCTAssertTrue(store.add(capture))
        let first = root.appendingPathComponent("First")
        XCTAssertEqual(try CanvasExport.portable(store.snapshot, store: store, to: first), 0)
        XCTAssertEqual(try Data(contentsOf: first.appendingPathComponent("assets/1.png")), png)
        try Data("Broken".utf8).write(to: store.assetURL(id))
        XCTAssertEqual(try CanvasExport.portable(store.snapshot, store: store, to: root.appendingPathComponent("Second")), 1)
    }
    @MainActor func testExportIDsRemainUniqueWhenImportedIDsCollideWithFallbacks() throws {
        let (_, store) = try fixture(), shared = UUID()
        let a = LocusObject(type: "note", title: "A", content: ["text": .string("A"), "canvasID": .string(shared.uuidString)])
        let b = LocusObject(type: "note", title: "B", content: ["text": .string("B"), "canvasID": .string(shared.uuidString)])
        var card = WallPlacement(objectID: b.id, x: 300, y: 0); card.id = shared
        XCTAssertTrue(store.mutate { next in next.objects = [a,b]; next.placements = [WallPlacement(objectID: a.id, x: 0, y: 0),card] })
        let fields = try JSONDecoder().decode([String:ObjectValue].self, from: CanvasJSON.export(store.snapshot))
        guard case .array(let nodes) = fields["nodes"] else { return XCTFail() }
        let ids = nodes.compactMap { value -> String? in if case .dictionary(let fields) = value { return fields["id"]?.text }; return nil }
        XCTAssertEqual(Set(ids).count, 2)
    }
    @MainActor func testPNGAndPDFContainBoundedOverviewWithoutChangingStore() throws {
        _ = NSApplication.shared
        let (_, store) = try fixture(); XCTAssertTrue(store.add(LocusObject(type: "note", title: "Export", content: ["text": .string("# Research\n**Native export**")])) )
        let before = store.snapshot
        let png = try CanvasExport.overview(before, store: store, format: .png)
        let image = try XCTUnwrap(NSBitmapImageRep(data: png)); XCTAssertLessThanOrEqual(image.pixelsWide, 4096); XCTAssertLessThanOrEqual(image.pixelsHigh, 4096)
        let pdf = try XCTUnwrap(PDFDocument(data: CanvasExport.overview(before, store: store, format: .pdf)))
        XCTAssertEqual(pdf.pageCount, 1); XCTAssertTrue(pdf.string?.contains("Research") == true)
        XCTAssertEqual(before, store.snapshot)
        XCTAssertThrowsError(try CanvasExport.overview(before, store: store, selection: [], format: .png))
    }
}
