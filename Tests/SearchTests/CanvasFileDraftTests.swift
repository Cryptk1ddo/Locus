import XCTest
@testable import Search

final class CanvasFileDraftTests: XCTestCase {
    func fixture(_ bytes: Data = Data("# File\nOriginal".utf8)) throws -> (URL, URL, LocusObject) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-file-edit-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Note.md"); try bytes.write(to: source)
        return (source, folder.appendingPathComponent("space/workspace.json"), LocusObject(type: "file", title: "Note", content: ["bookmark": .string("explicit-test-grant"), "subpath": .string("#File")]))
    }
    func testDraftSurvivesRestartWithoutTouchingSource() throws {
        let (source, workspace, object) = try fixture(), bytes = try Data(contentsOf: source)
        let draft = try CanvasFileDraft(object: object, workspace: workspace, original: bytes)
        try draft.persist("Changed 🌿\nEntire file")
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let reopened = try CanvasFileDraft(object: object, workspace: workspace, original: bytes)
        XCTAssertEqual(reopened.record.text, "Changed 🌿\nEntire file"); XCTAssertTrue(reopened.changed)
        try reopened.save(to: source, text: reopened.record.text)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "Changed 🌿\nEntire file")
        XCTAssertFalse(WorkspaceFiles.exists(reopened.file)); XCTAssertFalse(reopened.changed)
    }
    func testExternalChangeKeepsBothFileAndRecoverableDraft() throws {
        let (source, workspace, object) = try fixture(), bytes = try Data(contentsOf: source)
        let draft = try CanvasFileDraft(object: object, workspace: workspace, original: bytes)
        try Data("External".utf8).write(to: source, options: .atomic)
        XCTAssertThrowsError(try draft.save(to: source, text: "My draft"))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "External")
        let reopened = try CanvasFileDraft(object: object, workspace: workspace, original: Data("External".utf8))
        XCTAssertEqual(reopened.record.original, bytes); XCTAssertEqual(reopened.record.text, "My draft")
    }
    func testCompetingDraftWritersCannotOverwriteOrDiscard() throws {
        let (source, workspace, object) = try fixture(), bytes = try Data(contentsOf: source)
        let first = try CanvasFileDraft(object: object, workspace: workspace, original: bytes)
        let second = try CanvasFileDraft(object: object, workspace: workspace, original: bytes)
        try first.persist("First")
        XCTAssertThrowsError(try second.persist("Second")); XCTAssertThrowsError(try second.discard())
        XCTAssertEqual(second.record.text, "Second") // kept live even when persistence fails
        XCTAssertEqual(try CanvasFileDraft(object: object, workspace: workspace, original: bytes).record.text, "First")
    }
    func testBOMAndUniformCRLFSurviveSave() throws {
        let bytes = Data([0xef, 0xbb, 0xbf]) + Data("# File\r\nOriginal\r\n".utf8)
        let (source, workspace, object) = try fixture(bytes)
        let draft = try CanvasFileDraft(object: object, workspace: workspace, original: bytes)
        XCTAssertEqual(draft.record.text, "# File\nOriginal\n")
        try draft.save(to: source, text: "# File\nEdited 🌿\n")
        XCTAssertEqual(try Data(contentsOf: source), Data([0xef, 0xbb, 0xbf]) + Data("# File\r\nEdited 🌿\r\n".utf8))
    }
    func testInvalidFutureOrWrongBookmarkDraftLeftUntouched() throws {
        let (source, workspace, object) = try fixture(), bytes = try Data(contentsOf: source)
        let draft = try CanvasFileDraft(object: object, workspace: workspace, original: bytes)
        try draft.persist("Kept")
        var record = draft.record; record.version = 2
        let future = try JSONEncoder().encode(record); try future.write(to: draft.file)
        XCTAssertThrowsError(try CanvasFileDraft(object: object, workspace: workspace, original: bytes))
        XCTAssertEqual(try Data(contentsOf: draft.file), future)
        record.version = 1
        let wrong = CanvasFileDraft.Record(object: object.id, bookmark: "other-grant", original: bytes, text: "Kept")
        let wrongData = try JSONEncoder().encode(wrong); try wrongData.write(to: draft.file)
        XCTAssertThrowsError(try CanvasFileDraft(object: object, workspace: workspace, original: bytes))
        XCTAssertEqual(try Data(contentsOf: draft.file), wrongData)
    }
    func testLimitsInvalidEncodingAndMissingGrantRejected() throws {
        let (_, workspace, object) = try fixture()
        XCTAssertThrowsError(try CanvasFileDraft(object: object, workspace: workspace, original: Data([0xff])))
        XCTAssertThrowsError(try CanvasFileDraft(object: object, workspace: workspace, original: Data(repeating: 65, count: 1_000_001)))
        XCTAssertThrowsError(try CanvasFileDraft(object: LocusObject(type: "file", title: "No grant", content: [:]), workspace: workspace, original: Data()))
        let draft = try CanvasFileDraft(object: object, workspace: workspace, original: Data("Original".utf8))
        XCTAssertThrowsError(try draft.persist(String(repeating: "a", count: 1_000_001)))
        XCTAssertFalse(WorkspaceFiles.exists(draft.file))
    }
    func testDiscardAndSaveTwiceUseUpdatedBaseline() throws {
        let (source, workspace, object) = try fixture(), bytes = try Data(contentsOf: source)
        let draft = try CanvasFileDraft(object: object, workspace: workspace, original: bytes)
        try draft.save(to: source, text: "First save"); try draft.save(to: source, text: "Second save")
        try draft.persist("Discarded"); try draft.discard()
        XCTAssertEqual(draft.record.text, "Second save"); XCTAssertFalse(WorkspaceFiles.exists(draft.file))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "Second save")
    }
    func testCopyIdentityRejectsAliasesAndHardLinks() throws {
        let (source, _, _) = try fixture(), alias = source.deletingLastPathComponent().appendingPathComponent("Alias.md")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        XCTAssertTrue(CanvasFileDraft.sameFile(source, alias))
        try FileManager.default.removeItem(at: alias); try FileManager.default.linkItem(at: source, to: alias)
        XCTAssertTrue(CanvasFileDraft.sameFile(source, alias))
        XCTAssertFalse(CanvasFileDraft.sameFile(source, source.deletingLastPathComponent().appendingPathComponent("Copy.md")))
    }
    func testMissingSourceStillAllowsRecoveringAnExistingDraft() throws {
        let (source, workspace, object) = try fixture(), bytes = try Data(contentsOf: source)
        let draft = try CanvasFileDraft(object: object, workspace: workspace, original: bytes)
        try draft.persist("Recover this"); try FileManager.default.removeItem(at: source)
        let reopened = try CanvasFileDraft(object: object, workspace: workspace, original: nil)
        XCTAssertEqual(reopened.record.text, "Recover this")
        XCTAssertThrowsError(try reopened.save(to: source, text: reopened.record.text))
        try reopened.discard()
        XCTAssertThrowsError(try CanvasFileDraft(object: object, workspace: workspace, original: nil))
    }
    func testPauseAfterUndoRemovesCleanDraftAndReadsFreshSource() throws {
        let (source, workspace, object) = try fixture(), bytes = try Data(contentsOf: source)
        let draft = try CanvasFileDraft(object: object, workspace: workspace, original: bytes)
        try draft.persist("Temporary edit")
        try draft.pause(try XCTUnwrap(CanvasFileDraft.decode(bytes)))
        XCTAssertFalse(WorkspaceFiles.exists(draft.file)); XCTAssertFalse(draft.changed)
        let external = Data("Outside edit".utf8); try external.write(to: source)
        XCTAssertEqual(try CanvasFileDraft(object: object, workspace: workspace, original: external).record.text, "Outside edit")
    }
}
