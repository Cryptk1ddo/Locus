import XCTest
import AppKit
@testable import Search

final class CanvasPortableDependencyTests: XCTestCase {
    @MainActor func fixture() throws -> (URL, WorkspaceStore, CanvasVault) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("portable-dependencies-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(space: UUID(), file: root.appendingPathComponent("workspace/workspace.json"))
        return (root, store, CanvasVault.shared(workspace: store.file))
    }
    func write(_ text: String, at path: String, root: URL) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url); return url
    }
    func fields(_ destination: URL, file: String) throws -> [String: ObjectValue] {
        try JSONDecoder().decode([String: ObjectValue].self, from: Data(contentsOf: destination.appendingPathComponent(file)))
    }
    func testParserIgnoresCodeEscapesAndRemoteLinksAndPreservesTargetRanges() {
        let text = """
        ![[Part#Section|alias]] ![image](<Media/a%20b.png> "title")
        [ref]: other.md#heading "title"
        `![[inline]]` \\![[escaped]] [site](https://example.com)
        ~~~md
        ![[fenced]]
        ~~~
            ![[indented]]
        """
        let refs = CanvasPortableReferences.references(text)
        XCTAssertEqual(refs.map(\.target), ["Part", "Media/a b.png", "other.md"])
        XCTAssertEqual(refs.map { (text as NSString).substring(with: $0.range) }, ["Part", "Media/a%20b.png", "other.md"])
        XCTAssertEqual(CanvasPortableReferences.references(#"[local](a\(b\).md)"#).first?.target, "a(b).md")
        XCTAssertEqual(CanvasPortableReferences.relative("../Media/a.png", parent: "Notes"), "Media/a.png")
        XCTAssertNil(CanvasPortableReferences.relative("../../outside", parent: "Notes"))
    }
    @MainActor func testRecursiveCycleAndMediaExportWithinConnectedVault() throws {
        let (root, store, vault) = try fixture(), folder = root.appendingPathComponent("Vault")
        let a = try write("# A\n![[B#Heading|alias]]\n![image](<../Media/a%20b.png> \"title\")\n", at: "Notes/A.md", root: folder)
        let b = try write("# Heading\n![[A]]\n", at: "Notes/B.md", root: folder)
        let image = try write("media fixture", at: "Media/a b.png", root: folder)
        _ = try write("must not be exported", at: "Unreferenced.md", root: folder)
        XCTAssertTrue(vault.connect(folder)); XCTAssertTrue(CanvasFiles.add([a], to: store, at: .zero))
        let before = store.snapshot, destination = root.appendingPathComponent("Export")
        XCTAssertEqual(try CanvasExport.portable(before, store: store, to: destination), 0)
        let manifest = try fields(destination, file: "manifest.json")
        XCTAssertEqual(manifest["assets"], .number(3))
        XCTAssertEqual(manifest["dependencies"], .array([.string("assets/2.md"), .string("assets/3.png")]))
        XCTAssertTrue(try String(contentsOf: destination.appendingPathComponent("assets/1.md")).contains("![[2.md#Heading|alias]]"))
        XCTAssertTrue(try String(contentsOf: destination.appendingPathComponent("assets/1.md")).contains("<3.png> \"title\""))
        XCTAssertTrue(try String(contentsOf: destination.appendingPathComponent("assets/2.md")).contains("![[1.md]]"))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("assets/3.png")), try Data(contentsOf: image))
        XCTAssertEqual(try String(contentsOf: a), "# A\n![[B#Heading|alias]]\n![image](<../Media/a%20b.png> \"title\")\n")
        XCTAssertEqual(try String(contentsOf: b), "# Heading\n![[A]]\n"); XCTAssertEqual(store.snapshot, before)
    }
    @MainActor func testIndividualFileGrantCannotAuthorizeSiblingButExistingFileGrantCan() throws {
        let (root, store, _) = try fixture()
        let a = try write("![[B]]", at: "A.md", root: root), b = try write("# B", at: "B.md", root: root)
        XCTAssertTrue(CanvasFiles.add([a], to: store, at: .zero))
        XCTAssertEqual(try CanvasExport.portable(store.snapshot, store: store, to: root.appendingPathComponent("Denied")), 1)
        XCTAssertTrue(CanvasFiles.add([b], to: store, at: CGPoint(x: 300, y: 0)))
        let selected = Set(store.snapshot.placements.prefix(1).map(\.id)), destination = root.appendingPathComponent("Granted")
        XCTAssertEqual(try CanvasExport.portable(store.snapshot, store: store, selection: selected, to: destination), 0)
        XCTAssertEqual(try fields(destination, file: "manifest.json")["assets"], .number(2))
    }
    @MainActor func testSymlinksAndTraversalAreReportedWithoutCopyingOutsideVault() throws {
        let (root, store, vault) = try fixture(), folder = root.appendingPathComponent("Vault")
        _ = try write("private", at: "outside.md", root: root)
        let a = try write("![[../../outside.md]]\n![[linked.md]]\n![[missing.md]]", at: "Notes/A.md", root: folder)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Notes/linked.md"), withDestinationURL: root.appendingPathComponent("outside.md"))
        XCTAssertTrue(vault.connect(folder)); XCTAssertTrue(CanvasFiles.add([a], to: store, at: .zero))
        let destination = root.appendingPathComponent("Export")
        XCTAssertEqual(try CanvasExport.portable(store.snapshot, store: store, to: destination), 3)
        XCTAssertEqual(try fields(destination, file: "manifest.json")["assets"], .number(1))
    }
    @MainActor func testDependenciesImportWithoutExtraCardsAndRoundTripWithUndoAndContextIsolation() throws {
        let (root, store, vault) = try fixture(), folder = root.appendingPathComponent("Vault")
        let a = try write("![[B]]", at: "A.md", root: folder); _ = try write("# B\nNested content", at: "B.md", root: folder)
        XCTAssertTrue(vault.connect(folder)); XCTAssertTrue(CanvasFiles.add([a], to: store, at: .zero))
        let destination = root.appendingPathComponent("Export")
        XCTAssertEqual(try CanvasExport.portable(store.snapshot, store: store, to: destination), 0)
        let imported = WorkspaceStore(space: UUID(), file: root.appendingPathComponent("import/workspace.json"))
        let result = try CanvasImport.portable(destination, into: imported)
        XCTAssertEqual(result.granted, 2); XCTAssertEqual(result.selected.count, 1); XCTAssertEqual(imported.snapshot.placements.count, 1)
        XCTAssertEqual(imported.snapshot.objects.count, 2)
        let source = try XCTUnwrap(imported.snapshot.objects.first { $0.title == "1.md" })
        let reference = try XCTUnwrap(CanvasReference(CanvasReference.url("2.md")!))
        let target = try XCTUnwrap(reference.resolve(in: imported.snapshot, source: source))
        XCTAssertEqual(try CanvasFiles.withURL(target) { try String(contentsOf: $0) }, "# B\nNested content")
        XCTAssertFalse(CanvasVault.shared(workspace: imported.file).connected)
        XCTAssertTrue(imported.undoCanvas()); XCTAssertTrue(imported.snapshot.objects.isEmpty)
        XCTAssertTrue(imported.redoCanvas()); XCTAssertEqual(imported.snapshot.objects.count, 2)
        XCTAssertEqual(try CanvasExport.portable(imported.snapshot, store: imported, to: root.appendingPathComponent("RoundTrip")), 0)
        _ = try CanvasImport.portable(destination, into: imported)
        XCTAssertEqual(reference.resolve(in: imported.snapshot, source: source)?.id, target.id)
        let duplicate = LocusObject(type: "file", title: target.title, content: target.content)
        XCTAssertTrue(imported.mutate { $0.objects.append(duplicate) })
        XCTAssertEqual(reference.resolve(in: imported.snapshot, source: source)?.id, target.id)
        let traversal = try XCTUnwrap(CanvasReference(CanvasReference.url("../../2.md")!))
        XCTAssertNil(traversal.resolve(in: imported.snapshot, source: source))
    }
    @MainActor func testInlineNoteDependenciesUseRootPathsAndRestoreScopedReferences() throws {
        let (root, store, vault) = try fixture(), folder = root.appendingPathComponent("Vault")
        _ = try write("# B", at: "B.md", root: folder)
        XCTAssertTrue(vault.connect(folder))
        let object = LocusObject(type: "note", title: "Inline", content: ["text": .string("![[B#Heading|alias]]")])
        XCTAssertTrue(store.mutate { next in
            next.objects.append(object)
            next.placements.append(WallPlacement(objectID: object.id, x: 0, y: 0))
        })
        let destination = root.appendingPathComponent("Export")
        XCTAssertEqual(try CanvasExport.portable(store.snapshot, store: store, to: destination), 0)
        let document = try fields(destination, file: "Wall.canvas")
        guard case .array(let nodes) = document["nodes"], case .dictionary(let node) = nodes[0] else { return XCTFail("Missing inline node") }
        XCTAssertEqual(node["text"], .string("![[assets/1.md#Heading|alias]]"))
        let imported = WorkspaceStore(space: UUID(), file: root.appendingPathComponent("import/workspace.json"))
        _ = try CanvasImport.portable(destination, into: imported)
        let source = try XCTUnwrap(imported.snapshot.objects.first { $0.type == "note" })
        let reference = try XCTUnwrap(CanvasReference(CanvasReference.url("assets/1.md")!))
        XCTAssertEqual(reference.resolve(in: imported.snapshot, source: source)?.title, "1.md")
        XCTAssertEqual(try CanvasExport.portable(imported.snapshot, store: imported, to: root.appendingPathComponent("Again")), 0)
    }
    @MainActor func testDependencyReferenceLimitAbortsExportAndRemovesStaging() throws {
        let (root, store, _) = try fixture()
        let a = try write(Array(repeating: "![[missing]]", count: 257).joined(separator: "\n"), at: "A.md", root: root)
        XCTAssertTrue(CanvasFiles.add([a], to: store, at: .zero))
        let before = store.snapshot, destination = root.appendingPathComponent("Export")
        XCTAssertThrowsError(try CanvasExport.portable(store.snapshot, store: store, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".locus-export-") })
        XCTAssertEqual(store.snapshot, before)
    }
    @MainActor func testManifestCannotAuthorizeTraversalAndDependencyOversizeRollsBack() throws {
        let (root, store, _) = try fixture()
        try Data(#"{"nodes":[{"id":"note","type":"text","text":"![[outside]]","x":0,"y":0,"width":200,"height":100}]}"#.utf8).write(to: root.appendingPathComponent("Wall.canvas"))
        try Data(#"{"version":1,"previews":[],"dependencies":["../outside","/etc/passwd"]}"#.utf8).write(to: root.appendingPathComponent("manifest.json"))
        XCTAssertEqual(try CanvasImport.portable(root, into: store).unresolved, 2)
        XCTAssertEqual(store.snapshot.objects.count, 1)
        let large = root.appendingPathComponent("large.bin"); FileManager.default.createFile(atPath: large.path, contents: Data())
        let handle = try FileHandle(forWritingTo: large); try handle.truncate(atOffset: UInt64(CanvasExport.assetLimit + 1)); try handle.close()
        try Data(#"{"version":1,"previews":[],"dependencies":["large.bin"]}"#.utf8).write(to: root.appendingPathComponent("manifest.json"))
        let before = store.snapshot
        XCTAssertThrowsError(try CanvasImport.portable(root, into: store)); XCTAssertEqual(store.snapshot, before)
    }
}
