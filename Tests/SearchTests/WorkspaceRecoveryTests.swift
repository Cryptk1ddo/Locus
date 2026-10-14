import XCTest
import CoreGraphics
@testable import Search

final class WorkspaceRecoveryTests: XCTestCase {
    private func file() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("locus-recovery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("workspace.json")
    }
    private func note(_ title: String = "Research") -> LocusObject {
        LocusObject(type: "note", title: title, content: ["text": .string("Evidence")])
    }
    private func png(red: CGFloat = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0, blue: 1 - red, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return try XCTUnwrap(WorkspaceImage.png(try XCTUnwrap(context.makeImage())))
    }
    private func capture() -> LocusObject {
        LocusObject(type: "uiCapture", title: "Component", content: ["screenshot": .dictionary(["status": .string("captured")])])
    }

    @MainActor func testBackupIsExactPreviousCommitAndRecoveryKeepsDamagedBytes() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        store.add(note())
        // Recovery must preserve fields from writers this version doesn't understand.
        var fields = try JSONDecoder().decode([String: ObjectValue].self, from: Data(contentsOf: file))
        fields["futureResearchField"] = .string("keep me")
        let first = try JSONEncoder().encode(fields)
        try first.write(to: file)
        let loaded = WorkspaceStore(space: space, file: file)
        loaded.add(note("Second"))
        XCTAssertEqual(try Data(contentsOf: loaded.previousFile), first)
        let damaged = Data("interrupted snapshot".utf8)
        try damaged.write(to: file)
        let recovering = WorkspaceStore(space: space, file: file)
        XCTAssertFalse(recovering.writable)
        XCTAssertEqual(recovering.recovery, WorkspaceRecovery(revision: 1, objectCount: 1))
        XCTAssertEqual(try Data(contentsOf: file), damaged)
        XCTAssertTrue(recovering.recoverPrevious())
        XCTAssertTrue(recovering.writable)
        XCTAssertNil(recovering.recovery)
        XCTAssertEqual(try Data(contentsOf: file), first)
        XCTAssertEqual(recovering.snapshot, store.snapshot)
        let archives = try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("workspace.damaged-") }
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(archives.first)), damaged)
        recovering.add(note("After recovery"))
        XCTAssertEqual(try JSONDecoder().decode([String: ObjectValue].self, from: Data(contentsOf: file))["futureResearchField"], .string("keep me"))
    }

    @MainActor func testBackupWriteFailureRejectsMutationBeforeCurrentWrite() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        store.add(note())
        let before = try Data(contentsOf: file)
        var writes: [String] = []
        let failing = WorkspaceStore(space: space, file: file, write: { data, url in
            writes.append(url.lastPathComponent)
            if url.lastPathComponent == "workspace.previous.json" { throw CocoaError(.fileWriteNoPermission) }
            try WorkspaceFiles.write(data, to: url)
        })
        failing.add(note("Rejected"))
        XCTAssertEqual(writes, ["workspace.previous.json"])
        XCTAssertEqual(failing.snapshot, store.snapshot)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    @MainActor func testCurrentWriteFailureKeepsBothLastGoodCopiesAndUI() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        store.add(note())
        let before = try Data(contentsOf: file)
        let failing = WorkspaceStore(space: space, file: file, write: { data, url in
            if url == file { throw CocoaError(.fileWriteNoPermission) }
            try WorkspaceFiles.write(data, to: url)
        })
        failing.add(note("Rejected"))
        XCTAssertEqual(failing.snapshot, store.snapshot)
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try Data(contentsOf: failing.previousFile), before)
    }

    @MainActor func testFailedRecoveryRemainsReadOnlyAndPreservesOriginal() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        store.add(note()); store.add(note("Later"))
        let damaged = Data("damaged".utf8)
        try damaged.write(to: file)
        let failing = WorkspaceStore(space: space, file: file, write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertFalse(failing.recoverPrevious())
        XCTAssertFalse(failing.writable)
        XCTAssertNotNil(failing.recovery)
        XCTAssertEqual(try Data(contentsOf: file), damaged)
        XCTAssertTrue(failing.snapshot.objects.isEmpty)
    }

    @MainActor func testMissingCurrentOffersExplicitRecoveryAndErasedStoreCannotRecover() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        store.add(note()); store.add(note("Later"))
        try FileManager.default.removeItem(at: file)
        let missing = WorkspaceStore(space: space, file: file)
        XCTAssertFalse(missing.writable)
        XCTAssertNotNil(missing.recovery)
        missing.add(note("Cannot overwrite"))
        XCTAssertFalse(WorkspaceFiles.exists(file))
        XCTAssertTrue(missing.recoverPrevious())
        XCTAssertEqual(missing.snapshot.objects.count, 1)
        try Data("bad".utf8).write(to: file)
        let held = WorkspaceStore(space: space, file: file)
        held.erase()
        XCTAssertFalse(held.recoverPrevious())
        XCTAssertFalse(WorkspaceFiles.exists(file.deletingLastPathComponent()))
    }

    @MainActor func testUnreadableWorkspaceRetainsSessionBindingUntilRecoveryWithoutAuthorizingActions() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        let page = LocusObject(type: "page", title: "Saved page", content: ["url": .string("https://example.com/")])
        store.add(page); store.add(note())
        try Data("bad".utf8).write(to: file)
        let unreadable = WorkspaceStore(space: space, file: file)
        let binding = WallBinding(spaceID: space, objectID: page.id)
        XCTAssertEqual(WallBinding.restore(page.id, in: unreadable), binding)
        XCTAssertNil(WallBinding.resolve(page.id, in: unreadable.snapshot), "Retained IDs are not actionable")
        XCTAssertTrue(unreadable.recoverPrevious())
        XCTAssertEqual(WallBinding.restore(page.id, in: unreadable), binding)
        XCTAssertEqual(WallBinding.resolve(page.id, in: unreadable.snapshot), binding)
        unreadable.deleteObject(page.id)
        XCTAssertNil(WallBinding.restore(page.id, in: unreadable))
        try Data("bad again".utf8).write(to: file)
        let erased = WorkspaceStore(space: space, file: file)
        erased.erase()
        XCTAssertNil(WallBinding.restore(page.id, in: erased))
    }

    @MainActor func testFutureWrongSpaceAndInvalidBackupsNeverOfferRecovery() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        store.add(note()); store.add(note("Later"))
        for data in [Data("{\"schemaVersion\":99}".utf8), Data(repeating: 32, count: WorkspaceStore.byteLimit + 1), try JSONEncoder().encode(WorkspaceSnapshot(spaceID: UUID()))] {
            try data.write(to: file)
            let loaded = WorkspaceStore(space: space, file: file)
            XCTAssertNil(loaded.recovery)
            XCTAssertFalse(loaded.recoverPrevious())
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
        try Data("bad".utf8).write(to: file)
        try Data("bad backup".utf8).write(to: store.previousFile)
        XCTAssertNil(WorkspaceStore(space: space, file: file).recovery)
    }

    @MainActor func testRecoveryRejectsChangedBackupOrRepairedCurrentFile() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        store.add(note()); store.add(note("Later"))
        let current = try Data(contentsOf: file), previous = try Data(contentsOf: store.previousFile)
        try Data("bad".utf8).write(to: file)
        let recovering = WorkspaceStore(space: space, file: file)
        try current.write(to: store.previousFile)
        XCTAssertFalse(recovering.recoverPrevious())
        try previous.write(to: store.previousFile)
        try current.write(to: file)
        XCTAssertFalse(recovering.recoverPrevious())
        XCTAssertEqual(try Data(contentsOf: file), current)
    }

    @MainActor func testStaleWriterAndUnexpectedFirstFileNeverOverwriteDisk() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        store.add(note())
        let stale = WorkspaceStore(space: space, file: file)
        store.add(note("Other writer"))
        let newer = try Data(contentsOf: file), backup = try Data(contentsOf: store.previousFile)
        stale.add(note("Stale"))
        XCTAssertEqual(stale.snapshot.objects.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), newer)
        XCTAssertEqual(try Data(contentsOf: store.previousFile), backup)
        let newFile = try self.file(), fresh = WorkspaceStore(space: space, file: newFile)
        try newer.write(to: newFile)
        fresh.add(note())
        XCTAssertTrue(fresh.snapshot.objects.isEmpty)
        XCTAssertEqual(try Data(contentsOf: newFile), newer)
    }

    @MainActor func testDeletedPreviewRetainedForRecoveryThenReconciled() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file), object = capture()
        XCTAssertTrue(store.addCapture(object, png: try png()))
        let saved = try XCTUnwrap(store.snapshot.objects.first), asset = store.assetURL(try XCTUnwrap(saved.snapshotID))
        store.deleteObject(object.id)
        XCTAssertTrue(WorkspaceFiles.exists(asset))
        let deleted = WorkspaceStore(space: space, file: file)
        XCTAssertTrue(WorkspaceFiles.exists(asset))
        try Data("bad".utf8).write(to: file)
        let recovering = WorkspaceStore(space: space, file: file)
        XCTAssertTrue(recovering.recoverPrevious())
        XCTAssertEqual(recovering.snapshot.objects, [saved])
        XCTAssertNotNil(WorkspaceImage.image(saved, store: recovering))
        recovering.deleteObject(object.id)
        recovering.add(note())
        XCTAssertTrue(WorkspaceFiles.exists(asset), "A damaged archive protects assets needed for manual repair")
        XCTAssertTrue(deleted.snapshot.objects.isEmpty)
    }

    @MainActor func testReopenRemovesInterruptedStagingButKeepsUnknownFilesAndLinks() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        store.add(note())
        let orphan = store.assetURL(UUID()), directory = orphan.deletingLastPathComponent()
        try WorkspaceFiles.write(try png(), to: orphan)
        let unknown = directory.appendingPathComponent("future.pdf")
        try Data("future".utf8).write(to: unknown)
        let outside = file.deletingLastPathComponent().appendingPathComponent("outside.png")
        try png().write(to: outside)
        let link = store.assetURL(UUID())
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        _ = WorkspaceStore(space: space, file: file)
        XCTAssertFalse(WorkspaceFiles.exists(orphan))
        XCTAssertTrue(WorkspaceFiles.exists(unknown))
        XCTAssertTrue(WorkspaceFiles.exists(link))
        XCTAssertTrue(WorkspaceFiles.exists(outside))
    }

    @MainActor func testOpaqueObjectsOrInvalidBackupDisableDestructiveAssetCleanup() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        store.add(LocusObject(type: "futureWidget", title: "Opaque", content: [:]))
        let orphan = store.assetURL(UUID())
        try WorkspaceFiles.write(try png(), to: orphan)
        _ = WorkspaceStore(space: space, file: file)
        XCTAssertTrue(WorkspaceFiles.exists(orphan))
        store.deleteObject(store.snapshot.objects[0].id)
        XCTAssertTrue(WorkspaceFiles.exists(orphan), "Previous opaque snapshot is protected too")
        store.add(note())
        XCTAssertTrue(WorkspaceFiles.exists(orphan), "Opaque undo entries retain unknown asset references")
        store.discardCanvasHistory()
        XCTAssertFalse(WorkspaceFiles.exists(orphan))
        try WorkspaceFiles.write(try png(), to: orphan)
        try Data("bad backup".utf8).write(to: store.previousFile)
        _ = WorkspaceStore(space: space, file: file)
        XCTAssertTrue(WorkspaceFiles.exists(orphan))
    }

    @MainActor func testPNGIntegrityLegacyCompatibilityAndDamagedCacheInvalidation() throws {
        let file = try file(), store = WorkspaceStore(space: UUID(), file: file), data = try png(), object = capture()
        XCTAssertTrue(store.addCapture(object, png: data))
        let saved = try XCTUnwrap(store.snapshot.objects.first), id = try XCTUnwrap(saved.snapshotID)
        XCTAssertEqual(saved.snapshotIntegrity["bytes"], .number(Double(data.count)))
        XCTAssertEqual(saved.snapshotIntegrity["sha256"], .string(WorkspaceImage.digest(data)))
        XCTAssertNotNil(WorkspaceImage.thumbnail(saved, store: store))
        try png(red: 0).write(to: store.assetURL(id), options: .atomic)
        XCTAssertNil(WorkspaceImage.thumbnail(saved, store: store), "A cached verified image cannot hide a changed asset")
        try data.write(to: store.assetURL(id), options: .atomic)
        var fields = saved.fields
        fields["content"] = .dictionary(["screenshot": .dictionary(["value": .dictionary(["assetID": .string(id.uuidString), "mime": .string("image/png")])])])
        let legacy = try JSONDecoder().decode(LocusObject.self, from: JSONEncoder().encode(fields))
        XCTAssertNotNil(WorkspaceImage.thumbnail(legacy, store: store))
        try Data("bad image".utf8).write(to: store.assetURL(id), options: .atomic)
        XCTAssertNil(WorkspaceImage.image(saved, store: store))
        XCTAssertEqual(store.snapshot.objects, [saved], "Image corruption does not erase structured evidence")
        XCTAssertFalse(WorkspaceImage.validPNG(Data(data.prefix(40))))
        XCTAssertFalse(store.addCapture(capture(), png: Data(data.prefix(40))))
    }

    @MainActor func testAssetQuotaRejectsStagingWithoutPublishingAndStillAllowsNotes() throws {
        let file = try file(), store = WorkspaceStore(space: UUID(), file: file)
        let directory = store.assetURL(UUID()).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let unknown = directory.appendingPathComponent("future.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: unknown.path, contents: nil))
        let handle = try FileHandle(forWritingTo: unknown)
        try handle.truncate(atOffset: UInt64(WorkspaceAssets.byteLimit)); try handle.close()
        XCTAssertFalse(store.addCapture(capture(), png: try png()))
        XCTAssertTrue(store.snapshot.objects.isEmpty)
        XCTAssertFalse(WorkspaceFiles.exists(file))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["future.bin"])
        store.add(note())
        XCTAssertEqual(store.snapshot.objects.count, 1)
        XCTAssertTrue(WorkspaceFiles.exists(unknown))
        for index in 0..<(WorkspaceAssets.entryLimit - 1) {
            XCTAssertTrue(FileManager.default.createFile(atPath: directory.appendingPathComponent("unknown-\(index)").path, contents: nil))
        }
        XCTAssertThrowsError(try WorkspaceAssets.permit(1, in: directory))
    }

    @MainActor func testSymlinkCurrentBackupAndAssetDirectoryAreNeverFollowed() throws {
        let file = try file(), space = UUID(), store = WorkspaceStore(space: space, file: file)
        store.add(note()); store.add(note("Later"))
        let outside = file.deletingLastPathComponent().appendingPathComponent("outside.json"), before = try Data(contentsOf: file)
        try before.write(to: outside)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        let unsafe = WorkspaceStore(space: space, file: file)
        XCTAssertFalse(unsafe.writable); XCTAssertNil(unsafe.recovery)
        unsafe.add(note()); XCTAssertEqual(try Data(contentsOf: outside), before)
        try FileManager.default.removeItem(at: file); try before.write(to: file)
        let loaded = WorkspaceStore(space: space, file: file)
        try FileManager.default.removeItem(at: loaded.previousFile)
        try FileManager.default.createSymbolicLink(at: loaded.previousFile, withDestinationURL: outside)
        loaded.add(note("Rejected"))
        XCTAssertEqual(try Data(contentsOf: file), before)
        let assets = loaded.assetURL(UUID()).deletingLastPathComponent()
        let destination = file.deletingLastPathComponent().appendingPathComponent("outside-assets")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: assets, withDestinationURL: destination)
        XCTAssertFalse(loaded.addCapture(capture(), png: try png()))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }
}
