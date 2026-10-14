import XCTest
@testable import Search

final class InspirationGraphTests: XCTestCase {
    private func file() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("locus-graph-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("workspace.json")
    }
    private var png: Data { Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII=")! }

    func testSourceRecognitionAndURLBoundary() throws {
        let pin = try XCTUnwrap(InspirationSource.object(url: URL(string: "https://user:secret@www.pinterest.com/pin/12345/")!, title: "Pin"))
        XCTAssertEqual(pin.content["provider"], .string("pinterest"))
        XCTAssertEqual(pin.content["resourceKind"], .string("pin"))
        XCTAssertEqual(pin.content["remoteID"], .string("12345"))
        XCTAssertNil(pin.url?.user); XCTAssertNil(pin.url?.password)
        XCTAssertEqual(InspirationSource.identify(URL(string: "https://www.pinterest.com.evil.example/pin/12/")!), .web)
        XCTAssertEqual(InspirationSource.identify(URL(string: "https://notpinterest.com/")!), .web)
        for (address, provider) in [("https://www.are.na/alex/design", "arena"), ("https://dribbble.com/shots/123", "dribbble"), ("https://www.behance.net/gallery/123", "behance"), ("https://www.awwwards.com/", "awwwards")] {
            XCTAssertEqual(InspirationSource.object(url: URL(string: address)!, title: "")?.content["provider"], .string(provider))
        }
        for address in ["javascript:alert(1)", "file:///tmp/secret", "https:///", "data:text/html,hi"] {
            XCTAssertNil(InspirationSource.object(url: URL(string: address)!, title: "Bad"))
        }
    }

    @MainActor func testOwnedPreviewAndSourceCommitTogetherAndDeleteCleanup() throws {
        let path = try file(), space = UUID(), store = WorkspaceStore(space: space, file: path)
        let page = LocusObject(type: "page", title: "Source", content: ["url": .string("https://example.com/")])
        let inspiration = try XCTUnwrap(InspirationSource.object(url: page.url!, title: "Design", screenshotStatus: "captured"))
        XCTAssertTrue(store.addInspiration(inspiration, png: png, sourcePage: page))
        let saved = try XCTUnwrap(store.snapshot.objects.first { $0.id == inspiration.id })
        XCTAssertEqual(saved.relationshipTarget("collectedFrom"), page.id)
        let asset = store.assetURL(try XCTUnwrap(saved.snapshotID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        let loaded = WorkspaceStore(space: space, file: path)
        XCTAssertEqual(store.snapshot, loaded.snapshot)
        loaded.deleteObject(saved.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        XCTAssertEqual(loaded.snapshot.objects.map(\.id), [page.id])
        loaded.place(page.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path), "Undo retains deleted preview bytes")
        loaded.discardCanvasHistory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: asset.path))
    }

    @MainActor func testFailedPreviewCommitRollsBackAssetAndSource() throws {
        let path = try file(), store = WorkspaceStore(space: UUID(), file: path, write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        let object = try XCTUnwrap(InspirationSource.object(url: URL(string: "https://example.com/")!, title: "Clip"))
        let source = LocusObject(type: "page", title: "Source", content: ["url": .string("https://example.com/")])
        XCTAssertFalse(store.addInspiration(object, png: png, sourcePage: source))
        XCTAssertTrue(store.snapshot.objects.isEmpty)
        let assets = path.deletingLastPathComponent().appendingPathComponent("assets")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: assets.path), [])
        XCTAssertFalse(store.addInspiration(object, png: Data("not png".utf8)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    @MainActor func testSemanticLinksSurvivePlacementRemovalAndRestoreFirstProjection() throws {
        let path = try file(), space = UUID(), store = WorkspaceStore(space: space, file: path)
        let a = LocusObject(type: "note", title: "Research", content: [:]), b = LocusObject(type: "note", title: "Design", content: [:])
        store.add(a); store.add(b)
        XCTAssertTrue(store.connect(a.id, to: b.id, kind: "inspiredBy", label: "Pattern"))
        let revision = store.snapshot.revision
        XCTAssertFalse(store.connect(a.id, to: b.id, kind: "inspiredBy"))
        XCTAssertEqual(store.snapshot.revision, revision)
        XCTAssertEqual(WallGraph.wires(in: store.snapshot).count, 1)
        store.place(b.id)
        XCTAssertEqual(WallGraph.wires(in: store.snapshot).count, 1)
        for p in store.snapshot.placements where p.objectID == b.id { store.removePlacement(p.id) }
        XCTAssertEqual(WallGraph.wires(in: store.snapshot).count, 0)
        XCTAssertEqual(store.snapshot.objects[0].relationshipTarget("inspiredBy"), b.id)
        store.place(b.id)
        let loaded = WorkspaceStore(space: space, file: path)
        XCTAssertEqual(WallGraph.wires(in: loaded.snapshot).count, 1)
        loaded.deleteObject(b.id)
        XCTAssertTrue(loaded.snapshot.objects[0].relationships.isEmpty)
    }

    @MainActor func testRelationshipAuthorityAndGeometryValidation() throws {
        let store = WorkspaceStore(space: UUID(), file: try file())
        let a = LocusObject(type: "note", title: "A", content: [:]), b = LocusObject(type: "note", title: "B", content: [:])
        store.add(a); store.add(b)
        for (target, kind) in [(a.id, "relatedTo"), (UUID(), "relatedTo"), (b.id, "generatedFrom"), (b.id, "runAgent")] {
            XCTAssertFalse(store.connect(a.id, to: target, kind: kind))
        }
        XCTAssertTrue(store.connect(a.id, to: b.id, kind: "supports", label: String(repeating: "a", count: 500)))
        XCTAssertEqual(store.snapshot.objects[0].relationships[0].label.count, 200)
        let placement = try XCTUnwrap(store.snapshot.placements.first)
        store.resize(placement.id, width: 340, height: 230)
        let before = store.snapshot
        store.resize(placement.id, width: .infinity, height: 10)
        XCTAssertEqual(store.snapshot, before)
        XCTAssertTrue(store.disconnect(a.id, from: b.id, kind: "supports"))
        XCTAssertFalse(store.disconnect(a.id, from: b.id, kind: "generatedFrom"))
    }

    func testKnownDanglingRelationshipsAreRejectedButFutureDataSurvives() throws {
        let object = LocusObject(type: "note", title: "Evidence", content: [:])
        var fields = object.fields
        fields["relationships"] = .array([.dictionary(["kind": .string("futureLink"), "targetID": .string(UUID().uuidString), "future": .bool(true)])])
        var restored = try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))
        var snapshot = WorkspaceSnapshot(spaceID: UUID(), objects: [restored])
        XCTAssertNoThrow(try snapshot.validate())
        restored.appendRelationship(kind: "relatedTo", target: UUID())
        snapshot.objects = [restored]
        XCTAssertThrowsError(try snapshot.validate())
        fields["relationships"] = .array([.dictionary(["kind": .string("relatedTo")])])
        snapshot.objects = [try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))]
        XCTAssertThrowsError(try snapshot.validate())
        fields["payloadVersion"] = .number(2)
        snapshot.objects = [try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))]
        XCTAssertNoThrow(try snapshot.validate()) // Unknown payload shape remains opaque.
    }

    func testViewportValidatesAndSeparatesWindowsAndSpaces() throws {
        let name = "locus.viewport.tests.\(UUID())", settings = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { settings.removePersistentDomain(forName: name) }
        let window = UUID(), space = UUID(), value = WallViewport(x: -123, y: 83, zoom: 0.5)
        value.save(window: window, space: space, settings: settings)
        XCTAssertEqual(WallViewport.load(window: window, space: space, settings: settings), value)
        XCTAssertEqual(WallViewport.load(window: UUID(), space: space, settings: settings), WallViewport())
        XCTAssertEqual(WallViewport.load(window: window, space: UUID(), settings: settings), WallViewport())
        WallViewport(x: .infinity, y: 0, zoom: 1).save(window: window, space: space, settings: settings)
        XCTAssertEqual(WallViewport.load(window: window, space: space, settings: settings), value)
        settings.set(Data("{\"x\":0,\"y\":0,\"zoom\":99}".utf8), forKey: WallViewport.key(window: window, space: space))
        XCTAssertEqual(WallViewport.load(window: window, space: space, settings: settings), WallViewport())
    }

    @MainActor func testAIOutputIsCompletedEvidenceWithAttributionAndNoPageBody() throws {
        var turn = Assistant.Turn(question: "What pattern?")
        let url = URL(string: "https://example.com/reference")!
        func object() -> LocusObject? { AIWall.object(turn: turn, provider: "ollama", model: "fixture", title: "Reference", url: url, readAt: "2026-10-01", addressed: true, sourceTruncated: true) }
        turn.answer = "A quiet primary action."
        XCTAssertNil(object())
        turn.done = true; XCTAssertNil(object())
        turn.checked = true; turn.failed = "failed"; XCTAssertNil(object())
        turn.failed = nil; turn.strays = ["Unexpected address"]
        let output = try XCTUnwrap(object())
        XCTAssertTrue(output.supported); XCTAssertEqual(output.type, "aiOutput")
        XCTAssertEqual(output.content["provider"], .string("ollama"))
        XCTAssertEqual(output.content["addressedAI"], .bool(true))
        XCTAssertEqual(output.content["sourceTruncated"], .bool(true))
        XCTAssertNil(output.content["pageText"]); XCTAssertNil(output.content["messages"]); XCTAssertNil(output.content["key"])
        XCTAssertNil(output.url) // AI text cannot become a navigation target.
        let store = WorkspaceStore(space: UUID(), file: try file())
        let source = LocusObject(type: "page", title: "Reference", content: ["url": .string(url.absoluteString)])
        XCTAssertTrue(store.addAIOutput(output, sourcePage: source))
        XCTAssertEqual(store.snapshot.objects.last?.relationshipTarget("generatedFrom"), source.id)
        XCTAssertEqual(WorkspaceObjectSearch.results(in: store.snapshot, query: "quiet").count, 1)
    }

    @MainActor func testStaleSourceAndAnnotationCannotOverwriteEvidence() throws {
        let store = WorkspaceStore(space: UUID(), file: try file())
        let page = LocusObject(type: "page", title: "Old", content: ["url": .string("https://example.com/old")])
        store.add(page)
        XCTAssertTrue(store.updatePage(page, title: "New", url: URL(string: "https://example.com/new")!))
        let object = try XCTUnwrap(InspirationSource.object(url: page.url!, title: "Clip"))
        let before = store.snapshot
        XCTAssertFalse(store.addInspiration(object, png: nil, sourcePage: page))
        XCTAssertEqual(store.snapshot, before)
        XCTAssertTrue(store.addInspiration(object, png: nil))
        XCTAssertTrue(store.editInspiration(object, title: "Annotated", text: "Use the rhythm"))
        XCTAssertFalse(store.editInspiration(object, title: "Stale", text: "Overwrite"))
        XCTAssertEqual(store.snapshot.objects.last?.title, "Annotated")
        XCTAssertEqual(store.snapshot.objects.last?.url, object.url)
    }
}
