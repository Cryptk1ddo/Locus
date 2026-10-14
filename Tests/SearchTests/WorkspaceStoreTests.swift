import XCTest
@testable import Search

final class WorkspaceStoreTests: XCTestCase {
    private func file() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("locus-wall-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("workspace.json")
    }

    @MainActor
    func testRoundTripSeparateSpacesAndPlacementRemovalKeepsObject() throws {
        let file = try file(), space = UUID()
        let store = WorkspaceStore(space: space, file: file)
        let note = LocusObject(type: "note", title: "Research", content: ["text": .string("First")])
        store.add(note)
        let id = try XCTUnwrap(store.snapshot.placements.first?.id)
        store.move(id, x: -120, y: 430)
        let loaded = WorkspaceStore(space: space, file: file)
        XCTAssertEqual(loaded.snapshot, store.snapshot)
        loaded.removePlacement(id)
        XCTAssertEqual(loaded.snapshot.objects, [note])
        XCTAssertTrue(loaded.snapshot.placements.isEmpty)
        loaded.place(note.id)
        XCTAssertEqual(loaded.snapshot.placements.count, 1)
        let wrongSpace = WorkspaceStore(space: UUID(), file: file)
        XCTAssertFalse(wrongSpace.writable)
        XCTAssertTrue(wrongSpace.snapshot.objects.isEmpty)
    }

    @MainActor
    func testWriteFailureDoesNotPublishOrOverwrite() throws {
        let file = try file(), space = UUID()
        let store = WorkspaceStore(space: space, file: file)
        store.add(LocusObject(type: "note", title: "Kept", content: [:]))
        let before = try Data(contentsOf: file)
        let failing = WorkspaceStore(space: space, file: file, write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        let snapshot = failing.snapshot
        failing.add(LocusObject(type: "note", title: "Failed", content: [:]))
        XCTAssertEqual(failing.snapshot, snapshot)
        XCTAssertNotNil(failing.problem)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    @MainActor
    func testCorruptAndFutureFilesNeverBecomeEmptyWritableWalls() throws {
        for contents in ["not json", "{\"schemaVersion\":99}"] {
            let file = try file()
            let original = Data(contents.utf8)
            try original.write(to: file)
            let store = WorkspaceStore(space: UUID(), file: file)
            XCTAssertFalse(store.writable)
            store.add(LocusObject(type: "note", title: "Do not overwrite", content: [:]))
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }

    @MainActor
    func testUnknownObjectAndEnvelopeFieldsSurviveMutation() throws {
        let file = try file(), space = UUID()
        let store = WorkspaceStore(space: space, file: file)
        store.add(LocusObject(type: "futureWidget", title: "Future", content: ["nested": .array([.bool(true)])]))
        var root = try JSONDecoder().decode([String: ObjectValue].self, from: Data(contentsOf: file))
        root["futureWorkspaceField"] = .string("kept")
        if case .dictionary(var wall) = root["wall"], case .array(var placements) = wall["placements"],
           case .dictionary(var placement) = placements[0] {
            wall["futureWallField"] = .number(42)
            placement["futurePlacementField"] = .bool(true)
            placements[0] = .dictionary(placement)
            wall["placements"] = .array(placements)
            root["wall"] = .dictionary(wall)
        }
        if case .array(var objects) = root["objects"], case .dictionary(var object) = objects[0] {
            object["futureEnvelopeField"] = .string("retained")
            objects[0] = .dictionary(object)
            root["objects"] = .array(objects)
        }
        try JSONEncoder().encode(root).write(to: file)
        let loaded = WorkspaceStore(space: space, file: file)
        XCTAssertFalse(loaded.snapshot.objects[0].supported)
        loaded.move(loaded.snapshot.placements[0].id, x: 10, y: 20)
        let after = try JSONDecoder().decode([String: ObjectValue].self, from: Data(contentsOf: file))
        XCTAssertEqual(after["futureWorkspaceField"], root["futureWorkspaceField"])
        XCTAssertEqual(after["objects"], root["objects"])
        guard case .dictionary(let wall) = after["wall"], case .array(let placements) = wall["placements"],
              case .dictionary(let placement) = placements[0] else { return XCTFail("Missing Wall") }
        XCTAssertEqual(wall["futureWallField"], .number(42))
        XCTAssertEqual(placement["futurePlacementField"], .bool(true))
    }

    @MainActor
    func testInvalidMutationLeavesCommittedSnapshotIntact() throws {
        let store = WorkspaceStore(space: UUID(), file: try file())
        let object = LocusObject(type: "note", title: "Note", content: [:])
        store.add(object)
        let before = store.snapshot
        XCTAssertFalse(store.mutate { $0.objects.append(object) })
        XCTAssertEqual(store.snapshot, before)
        store.move(before.placements[0].id, x: .infinity, y: 0)
        XCTAssertEqual(store.snapshot, before)
        XCTAssertFalse(store.mutate { $0.spaceID = UUID() })
    }

    @MainActor
    func testRepeatedWritesAndNoteEditsAreDurable() throws {
        let file = try file(), space = UUID()
        let store = WorkspaceStore(space: space, file: file)
        let note = LocusObject(type: "note", title: "Note", content: ["text": .string("")])
        store.add(note)
        for n in 0..<25 { XCTAssertTrue(store.editNote(note.id, title: "Note", text: "Revision \(n)")) }
        XCTAssertEqual(WorkspaceStore(space: space, file: file).snapshot.objects.first?.text, "Revision 24")
        XCTAssertEqual(store.snapshot.revision, 26)
    }
    @MainActor
    func testDeletingObjectRemovesPlacementsAndDeletingSpaceRejectsHeldEdits() throws {
        let file = try file()
        let store = WorkspaceStore(space: UUID(), file: file)
        let object = LocusObject(type: "note", title: "Delete", content: [:])
        store.add(object)
        store.place(object.id)
        store.deleteObject(object.id)
        XCTAssertTrue(store.snapshot.objects.isEmpty)
        XCTAssertTrue(store.snapshot.placements.isEmpty)
        store.erase()
        store.add(object)
        XCTAssertFalse(store.writable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor
    func testWindowsShareOneWriterForEachSpace() {
        let space = UUID()
        XCTAssertTrue(WorkspaceStore.shared(for: space) === WorkspaceStore.shared(for: space))
        XCTAssertFalse(WorkspaceStore.shared(for: space) === WorkspaceStore.shared(for: UUID()))
    }

    func testUnknownLargeIntegerMetadataIsPreservedExactly() throws {
        let values = ["signed": ObjectValue.integer(Int64.max), "unsigned": .unsigned(UInt64.max)]
        XCTAssertEqual(try JSONDecoder().decode([String: ObjectValue].self, from: JSONEncoder().encode(values)), values)
    }

}
