import XCTest
import AppKit
@testable import Search

final class CanvasTests: XCTestCase {
    private func file() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("locus-canvas-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root.appendingPathComponent("workspace.json")
    }
    @MainActor func testUndoRedoIsAtomicMonotonicAndClearsBranch() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        let object = LocusObject(type: "note", title: "Text", content: ["text": .string("Original")])
        XCTAssertTrue(store.add(object)); let id = store.snapshot.placements[0].id
        store.move(id, x: 300, y: 400)
        XCTAssertTrue(store.undoCanvas()); XCTAssertEqual(store.snapshot.revision, 3); XCTAssertEqual(store.snapshot.placements[0].x, 40)
        XCTAssertTrue(store.redoCanvas()); XCTAssertEqual(store.snapshot.revision, 4); XCTAssertEqual(store.snapshot.placements[0].x, 300)
        XCTAssertTrue(store.undoCanvas()); XCTAssertTrue(store.colorCanvas(cards: [id], edges: [], color: "6")); XCTAssertFalse(store.canRedo)
        XCTAssertEqual(WorkspaceStore(space: space, file: file).snapshot, store.snapshot)
    }
    @MainActor func testFailedUndoDoesNotConsumeHistoryOrPublish() throws {
        let file = try file(); var reject = false
        let store = WorkspaceStore(space: UUID(), file: file, write: { data, target in if reject && target == file { throw CocoaError(.fileWriteNoPermission) }; try WorkspaceFiles.write(data, to: target) })
        XCTAssertTrue(store.add(LocusObject(type: "note", title: "Keep", content: [:])))
        let before = store.snapshot, data = try Data(contentsOf: file); reject = true
        XCTAssertFalse(store.undoCanvas()); XCTAssertTrue(store.canUndo); XCTAssertEqual(store.snapshot, before); XCTAssertEqual(try Data(contentsOf: file), data)
        reject = false; XCTAssertTrue(store.undoCanvas()); XCTAssertTrue(store.snapshot.objects.isEmpty)
    }
    @MainActor func testUnsupportedFilePayloadDoesNotResolveBookmarkedFilesOrCloneItsContent() throws {
        let path = try file(), source = path.deletingLastPathComponent().appendingPathComponent("selected.txt")
        try "Selected test data".write(to: source, atomically: true, encoding: .utf8)
        let bookmark = try source.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let known = LocusObject(type: "file", title: "File", content: ["file": .string(source.path), "bookmark": .string(bookmark.base64EncodedString())])
        XCTAssertEqual(CanvasFiles.withURL(known) { try? String(contentsOf: $0, encoding: .utf8) }, "Selected test data")
        var fields = known.fields; fields["payloadVersion"] = .number(2)
        let future = try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))
        XCTAssertFalse(future.supported); XCTAssertNil(CanvasFiles.withURL(future) { $0.path })
        let store = WorkspaceStore(space: UUID(), file: path); XCTAssertTrue(store.add(future))
        XCTAssertNotNil(store.duplicateCanvas([store.snapshot.placements[0].id])); XCTAssertEqual(store.snapshot.objects, [future])
    }
    @MainActor func testResetZoomPreservesWorldCentreAndPointerZoomAnchor() throws {
        let suite = "canvas-viewport-test-\(UUID())", settings = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { settings.removePersistentDomain(forName: suite) }
        let controller = CanvasController(store: WorkspaceStore(space: UUID(), file: try file()), window: UUID(), settings: settings)
        controller.size = CGSize(width: 1000, height: 700); controller.viewport = WallViewport(x: 200, y: -100, zoom: 2)
        let centre = CGPoint(x: 500, y: 350), before = controller.viewport.worldPoint(centre)
        controller.reset(); XCTAssertEqual(controller.viewport.zoom, 1); XCTAssertEqual(controller.viewport.worldPoint(centre), before)
        let pointer = CGPoint(x: 100, y: 200), anchored = controller.viewport.worldPoint(pointer)
        controller.zoom(1.5, at: pointer); XCTAssertEqual(controller.viewport.worldPoint(pointer), anchored)
    }
    @MainActor func testFileReferenceRetainsOwnedCaptureThroughDeletionAndHistory() throws {
        let store = WorkspaceStore(space: UUID(), file: try file())
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII=")!
        let capture = LocusObject(type: "uiCapture", title: "Capture", content: ["screenshot": .dictionary(["status": .string("captured")])])
        XCTAssertTrue(store.addCapture(capture, png: png))
        let id = try XCTUnwrap(store.snapshot.objects[0].snapshotID), asset = store.assetURL(id)
        let reference = LocusObject(type: "file", title: "Shared preview", content: ["file": .string(asset.path)])
        XCTAssertTrue(store.add(reference)); store.deleteObject(capture.id); store.discardCanvasHistory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        store.deleteObject(reference.id); store.add(LocusObject(type: "note", title: "Advance", content: [:]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path)); store.discardCanvasHistory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: asset.path))
    }
    @MainActor func testSpaceReferenceCreatesOnlyPlacementAndUndoKeepsOriginalObject() throws {
        let store = WorkspaceStore(space: UUID(), file: try file())
        let note = LocusObject(type: "note", title: "Shared note", content: ["text": .string("Source")])
        XCTAssertTrue(store.add(note))
        let id = try XCTUnwrap(store.addCanvasReference(note.id, at: CGPoint(x: -100, y: 200)))
        XCTAssertEqual(store.snapshot.objects.count, 1); XCTAssertEqual(store.snapshot.revision, 2)
        XCTAssertEqual(store.snapshot.placements.last?.id, id); XCTAssertEqual(store.snapshot.placements.last?.x, -100)
        XCTAssertTrue(store.undoCanvas()); XCTAssertEqual(store.snapshot.objects, [note]); XCTAssertEqual(store.snapshot.placements.count, 1)
    }
    @MainActor func testClearingColorSurvivesReloadAndUndo() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        XCTAssertTrue(store.add(LocusObject(type: "note", title: "Colour", content: [:])))
        let id = store.snapshot.placements[0].id
        XCTAssertTrue(store.colorCanvas(cards: [id], edges: [], color: "#123ABC")); XCTAssertTrue(store.colorCanvas(cards: [id], edges: [], color: nil))
        XCTAssertNil(WorkspaceStore(space: space, file: file).snapshot.placements[0].color)
        XCTAssertTrue(store.undoCanvas()); XCTAssertEqual(store.snapshot.placements[0].color, "#123ABC")
        XCTAssertTrue(store.redoCanvas()); XCTAssertNil(store.snapshot.placements[0].color)
    }
    @MainActor func testPlacementEdgesDuplicateAndDeleteWithoutSemanticChanges() throws {
        let store = WorkspaceStore(space: UUID(), file: try file())
        for title in ["A", "B"] { XCTAssertTrue(store.add(LocusObject(type: "note", title: title, content: ["text": .string(title)]))) }
        let cards = store.snapshot.placements
        var edge = CanvasEdge(from: cards[0].id, to: cards[1].id, fromSide: .bottom, toSide: .top); edge.label = "Design"; edge.extra["future"] = .string("Keep")
        XCTAssertTrue(store.saveCanvasEdge(edge)); XCTAssertTrue(store.snapshot.objects.allSatisfy { $0.relationships.isEmpty })
        let ids = try XCTUnwrap(store.duplicateCanvas(Set(cards.map(\.id))))
        XCTAssertEqual(ids.count, 2); XCTAssertEqual(store.snapshot.objects.count, 4)
        let edges = store.snapshot.wall.edges.compactMap(CanvasEdge.init); XCTAssertEqual(edges.count, 2); XCTAssertEqual(edges[1].extra["future"], .string("Keep")); XCTAssertTrue(ids.contains(edges[1].from))
        XCTAssertTrue(store.removeCanvasSelection(cards: [cards[0].id], edges: [])); XCTAssertEqual(store.snapshot.wall.edges.count, 1); XCTAssertEqual(store.snapshot.objects.count, 4)
        XCTAssertTrue(store.undoCanvas()); XCTAssertEqual(store.snapshot.wall.edges.count, 2)
    }
    func testGestureGeometryGroupsSnappingAndAspectRatio() {
        let card = WallPlacement(objectID: UUID(), x: 12, y: 23, width: 200, height: 100)
        let group = WallPlacement(objectID: UUID(), x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(CanvasGeometry.contained(in: group, placements: [group, card]), [card.id])
        let moved = CanvasGeometry.moved([card], delta: CGPoint(x: 25, y: 2), constrained: true, grid: true)[0]
        XCTAssertEqual(moved.x, 40); XCTAssertEqual(moved.y, 23)
        let resized = CanvasGeometry.resized(card, horizontal: -1, vertical: -1, delta: CGPoint(x: -100, y: -10), aspect: true, snap: false)
        XCTAssertEqual(resized.width / resized.height, 2); XCTAssertEqual(resized.rect.maxX, card.rect.maxX); XCTAssertEqual(resized.rect.maxY, card.rect.maxY)
    }
    @MainActor func testMarkdownStylesPreserveUnicodeAndWideEdgeHitTesting() {
        let rendered = CanvasMarkdown.render("Emoji 🧭 **Structure** and *motion* with `code`")
        let range = (rendered.string as NSString).range(of: "Structure")
        let font = rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false)
        XCTAssertTrue(rendered.string.contains("🧭 Structure"))
        let curve = CanvasCurve(from: CGRect(x: 0, y: 0, width: 100, height: 100), side: .right, to: CGRect(x: 20_000, y: 40, width: 100, height: 100), toSide: .left)
        XCTAssertLessThan(curve.distance(to: curve.point(0.513)), 1)
    }
    @MainActor func testJSONCanvasRoundTripAndPathDoesNotGrantAccess() throws {
        let store = WorkspaceStore(space: UUID(), file: try file())
        let json = ##"{"extension":{"preserve":true},"nodes":[{"id":"text-a","type":"text","x":-100,"y":20,"width":300,"height":200,"text":"# Title\nBody","color":"4","plugin":"keep"},{"id":"group-a","type":"group","x":-120,"y":0,"width":700,"height":400,"label":"Research","backgroundStyle":"repeat"},{"id":"file-a","type":"file","x":300,"y":20,"width":200,"height":200,"file":"secret.md","subpath":"#Heading"}],"edges":[{"id":"edge-a","fromNode":"text-a","toNode":"file-a","fromSide":"bottom","toSide":"top","fromEnd":"arrow","toEnd":"none","color":"#ABCDEF","label":"Uses","plugin":"edge"}]}"##
        XCTAssertEqual(try CanvasJSON.importData(Data(json.utf8), into: store).count, 3)
        let file = try XCTUnwrap(store.snapshot.objects.first { $0.type == "file" }); XCTAssertNil(CanvasFiles.withURL(file) { $0.path })
        let exported = try CanvasJSON.export(store.snapshot)
        let expected = try JSONDecoder().decode([String: ObjectValue].self, from: Data(json.utf8)), actual = try JSONDecoder().decode([String: ObjectValue].self, from: exported)
        XCTAssertEqual(actual, expected)
        let revision = store.snapshot.revision
        XCTAssertThrowsError(try CanvasJSON.importData(Data(#"{"nodes":[{"id":"evil","type":"link","x":0,"y":0,"width":200,"height":100,"url":"file:///etc/passwd"}]}"#.utf8), into: store))
        XCTAssertEqual(store.snapshot.revision, revision)
    }
    @MainActor func testUnknownEnvelopeSurvivesUndoAndRedo() throws {
        let path = try file(), space = UUID(), store = WorkspaceStore(space: space, file: path)
        XCTAssertTrue(store.add(LocusObject(type: "note", title: "Unknown", content: [:])))
        var fields = try JSONDecoder().decode([String: ObjectValue].self, from: Data(contentsOf: path)); fields["plugin"] = .string("Untouched")
        try JSONEncoder().encode(fields).write(to: path)
        let loaded = WorkspaceStore(space: space, file: path); loaded.move(loaded.snapshot.placements[0].id, x: 20, y: 30); XCTAssertTrue(loaded.undoCanvas()); XCTAssertTrue(loaded.redoCanvas())
        XCTAssertEqual(try JSONDecoder().decode([String: ObjectValue].self, from: Data(contentsOf: path))["plugin"], .string("Untouched"))
    }
}
