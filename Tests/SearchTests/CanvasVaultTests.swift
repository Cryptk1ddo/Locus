import XCTest
@testable import Search

final class CanvasVaultTests: XCTestCase {
    func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("locus-vault-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root.appendingPathComponent("Notes"), root.appendingPathComponent("space/workspace.json"))
    }
    @MainActor func testConnectionPersistsPerSpaceWithAutosaveAndDisconnect() throws {
        let (root, workspace) = try fixture(), vault = CanvasVault(workspace: workspace)
        XCTAssertTrue(vault.connect(root)); XCTAssertTrue(vault.autosave)
        let loaded = CanvasVault(workspace: workspace); XCTAssertTrue(loaded.connected); XCTAssertTrue(loaded.contains(root.appendingPathComponent("Note.md")))
        loaded.setAutosave(false); XCTAssertFalse(CanvasVault(workspace: workspace).autosave)
        let other = CanvasVault(workspace: workspace.deletingLastPathComponent().appendingPathComponent("other/workspace.json")); XCTAssertFalse(other.connected)
        loaded.disconnect(); XCTAssertFalse(loaded.connected); XCTAssertFalse(CanvasVault(workspace: workspace).connected)
    }
    @MainActor func testGrantedMembershipRejectsOutsideFilesAndSymlinks() throws {
        let (root, workspace) = try fixture(), vault = CanvasVault(workspace: workspace)
        let inside = root.appendingPathComponent("Note.md"), outside = root.deletingLastPathComponent().appendingPathComponent("Outside.md")
        try Data("Note".utf8).write(to: inside); try Data("Outside".utf8).write(to: outside)
        XCTAssertTrue(vault.connect(root)); XCTAssertTrue(vault.contains(inside)); XCTAssertFalse(vault.contains(outside))
        let link = root.appendingPathComponent("Alias.md"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertFalse(vault.contains(link)); XCTAssertNil(CanvasVault.safeURL("Alias.md", root: root))
        XCTAssertNil(CanvasVault.safeURL("../Outside.md", root: root)); XCTAssertNil(CanvasVault.safeURL(outside.path, root: root))
    }
    @MainActor func testIndexResolvesUniqueFilesAndRejectsAmbiguousBasenames() throws {
        let (root, workspace) = try fixture(), vault = CanvasVault(workspace: workspace)
        for folder in ["A", "B"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true); try Data("# Duplicate".utf8).write(to: root.appendingPathComponent(folder + "/Duplicate.md")) }
        try Data("# Unique".utf8).write(to: root.appendingPathComponent("Unique.md"))
        XCTAssertTrue(vault.connect(root))
        XCTAssertEqual(vault.entries.count, 3)
        XCTAssertEqual(vault.resolve("Unique")?.lastPathComponent, "Unique.md"); XCTAssertNil(vault.resolve("Duplicate"))
        XCTAssertEqual(vault.resolve("A/Duplicate.md")?.deletingLastPathComponent().lastPathComponent, "A")
        let object = try XCTUnwrap(vault.object("Unique")); XCTAssertTrue(vault.canAutosave(object))
        vault.setAutosave(false); XCTAssertFalse(vault.canAutosave(object))
    }
    @MainActor func testRefreshDetectsExternalChangesAndMissingFiles() throws {
        let (root, workspace) = try fixture(), vault = CanvasVault(workspace: workspace), source = root.appendingPathComponent("Note.md")
        try Data("One".utf8).write(to: source); XCTAssertTrue(vault.connect(root)); let revision = vault.revision
        try Data("Changed externally".utf8).write(to: source, options: .atomic); vault.refresh(); XCTAssertGreaterThan(vault.revision, revision)
        try FileManager.default.removeItem(at: source); vault.refresh(); XCTAssertTrue(vault.entries.isEmpty)
    }
    @MainActor func testStaleConfigWriterCannotChangeConnectedRoot() throws {
        let (root, workspace) = try fixture(), first = CanvasVault(workspace: workspace), second = CanvasVault(workspace: workspace)
        XCTAssertTrue(first.connect(root)); XCTAssertFalse(second.connect(root)); XCTAssertNotNil(second.problem)
        XCTAssertFalse(second.connected); XCTAssertTrue(CanvasVault(workspace: workspace).connected)
    }
    @MainActor func testReconnectToEmptyVaultDropsOldIndex() throws {
        let (root, workspace) = try fixture(), vault = CanvasVault(workspace: workspace)
        try Data("Note".utf8).write(to: root.appendingPathComponent("Old.md"))
        XCTAssertTrue(vault.connect(root)); XCTAssertEqual(vault.entries, ["Old.md"])
        let empty = root.deletingLastPathComponent().appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertTrue(vault.connect(empty)); XCTAssertTrue(vault.entries.isEmpty); XCTAssertNil(vault.resolve("Old"))
    }
    @MainActor func testInvalidAndFutureConfigPreserved() throws {
        let (_, workspace) = try fixture(), file = workspace.deletingLastPathComponent().appendingPathComponent("vault.json")
        for text in ["invalid", "{\"version\":99}"] {
            try WorkspaceFiles.write(Data(text.utf8), to: file)
            let vault = CanvasVault(workspace: workspace); XCTAssertNotNil(vault.problem); vault.setAutosave(true); vault.disconnect()
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), text)
        }
    }
    @MainActor func testImportBindsOnlyRelativeExistingGrantedFiles() throws {
        let (root, workspace) = try fixture(), vault = CanvasVault(workspace: workspace), store = WorkspaceStore(space: UUID(), file: workspace)
        try Data("# Granted".utf8).write(to: root.appendingPathComponent("Granted.md"))
        let safe = LocusObject(type: "file", title: "Granted", content: ["file": .string("Granted.md")]), outside = LocusObject(type: "file", title: "Outside", content: ["file": .string("../Outside.md")])
        _ = store.add(safe); _ = store.add(outside); XCTAssertNil(CanvasFiles.text(safe)); XCTAssertTrue(vault.connect(root)); vault.bindImportedFiles(store: store)
        let bound = try XCTUnwrap(store.snapshot.objects.first { $0.id == safe.id }); XCTAssertEqual(CanvasFiles.text(bound), "# Granted")
        XCTAssertNil(store.snapshot.objects.first { $0.id == outside.id }?.content["bookmark"])
    }
}
