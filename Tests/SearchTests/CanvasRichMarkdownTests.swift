import XCTest
import AppKit
@testable import Search

final class CanvasRichMarkdownTests: XCTestCase {
    func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("locus-rich-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, root.appendingPathComponent("space/workspace.json"))
    }
    @MainActor func testTablesUseNativeBlocksAndKeepEscapedPipesAndCodeLiteral() throws {
        let source = "| Name | Size |\n| :--- | ---: |\n| **Spacing** | 4 |\n| `a|b` | 8 |\n\n~~~\n| Literal | Table |\n| --- | --- |\n~~~"
        let rendered = CanvasMarkdown.render(source)
        let range = (rendered.string as NSString).range(of: "Spacing")
        let style = try XCTUnwrap(rendered.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.textBlocks.count, 1); XCTAssertTrue(style.textBlocks[0] is NSTextTableBlock)
        XCTAssertTrue(rendered.string.contains("a|b")); XCTAssertTrue(rendered.string.contains("| Literal | Table |"))
        XCTAssertEqual(CanvasTable.cells("| One \\| Two | Three |"), ["One \\| Two", "Three"])
    }
    @MainActor func testTransclusionIncludesOnlyRequestedSectionAndRedirectsTasks() throws {
        let (_, workspace) = try fixture(), vault = CanvasVault(workspace: workspace)
        let target = LocusObject(type: "note", title: "Reference", content: ["text": .string("# Intro\nHidden\n## Detail\n- [ ] Embedded task\n[[#Detail]]\n## Other\nNot included")])
        let source = LocusObject(type: "note", title: "Source", content: ["text": .string("![[Reference#Detail]]\n- [ ] Own task")])
        var snapshot = WorkspaceSnapshot(spaceID: UUID()); snapshot.objects = [source, target]
        let rendered = CanvasRichMarkdown.render(source.text, object: source, snapshot: snapshot, vault: vault, width: 280)
        XCTAssertTrue(rendered.string.contains("Embedded task")); XCTAssertFalse(rendered.string.contains("Not included")); XCTAssertFalse(rendered.string.contains("Hidden"))
        let plain = rendered.string as NSString, embedded = plain.range(of: "☐"), own = plain.range(of: "☐", options: .backwards)
        let embeddedLink = try XCTUnwrap(rendered.attribute(.link, at: embedded.location, effectiveRange: nil) as? URL)
        XCTAssertEqual(CanvasReference(embeddedLink)?.target, "Reference")
        let ownLink = try XCTUnwrap(rendered.attribute(.link, at: own.location, effectiveRange: nil) as? URL)
        XCTAssertEqual(ownLink.scheme, "locus-task")
        let offset = try XCTUnwrap(Int(URLComponents(url: ownLink, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!))
        XCTAssertEqual((source.text as NSString).substring(with: NSRange(location: offset, length: 3)), "[ ]")
    }
    @MainActor func testCyclesMissingAndCodeEscapesRemainSafe() throws {
        let (_, workspace) = try fixture(), vault = CanvasVault(workspace: workspace)
        let a = LocusObject(type: "note", title: "A", content: ["text": .string("![[B]]")]), b = LocusObject(type: "note", title: "B", content: ["text": .string("![[A]]")])
        var snapshot = WorkspaceSnapshot(spaceID: UUID()); snapshot.objects = [a,b]
        XCTAssertTrue(CanvasRichMarkdown.render(a.text, object: a, snapshot: snapshot, vault: vault, width: 280).string.contains("Cyclic embed"))
        let source = "`![[B]]`\n\\![[B]]\n~~~\n![[B]]\n~~~\n![[Missing]]"
        let text = CanvasRichMarkdown.render(source, object: a, snapshot: snapshot, vault: vault, width: 280).string
        XCTAssertTrue(text.contains("![[B]]")); XCTAssertFalse(text.contains("Cyclic embed")); XCTAssertTrue(text.contains("Embed not found: Missing"))
    }
    @MainActor func testVaultSectionAndLocalImageEmbedsRequireGrant() throws {
        let (root, workspace) = try fixture(), vault = CanvasVault(workspace: workspace)
        try Data("# Note\n## Detail\nVault section".utf8).write(to: root.appendingPathComponent("Reference.md"))
        let image = NSImage(size: CGSize(width: 32, height: 24)); image.lockFocus(); NSColor.systemGreen.setFill(); CGRect(x: 0, y: 0, width: 32, height: 24).fill(); image.unlockFocus()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))); try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent("Image.png"))
        let source = LocusObject(type: "note", title: "Source", content: ["text": .string("![[Reference#Detail]]\n![[Image.png|100]]\n![Local](Image.png)\n![Remote](https://example.com/image.png)")])
        var snapshot = WorkspaceSnapshot(spaceID: UUID()); snapshot.objects = [source]
        XCTAssertTrue(CanvasRichMarkdown.render(source.text, object: source, snapshot: snapshot, vault: vault, width: 280).string.contains("Embed not found"))
        XCTAssertTrue(vault.connect(root))
        let rendered = CanvasRichMarkdown.render(source.text, object: source, snapshot: snapshot, vault: vault, width: 280)
        XCTAssertTrue(rendered.string.contains("Vault section")); XCTAssertTrue(rendered.string.contains("Image unavailable: Remote"))
        var attachments = 0; rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in if value != nil { attachments += 1 } }
        XCTAssertEqual(attachments, 2)
    }
    @MainActor func testExpansionBudgetAndUnsupportedEmbedDoNotExecuteContent() throws {
        let (_, workspace) = try fixture(), vault = CanvasVault(workspace: workspace)
        let target = LocusObject(type: "note", title: "Reference", content: ["text": .string("Content")]), source = LocusObject(type: "note", title: "Source", content: [:])
        var snapshot = WorkspaceSnapshot(spaceID: UUID()); snapshot.objects = [source,target]
        let text = CanvasRichMarkdown.render(Array(repeating: "![[Reference]]", count: 20).joined(separator: "\n"), object: source, snapshot: snapshot, vault: vault, width: 280).string
        XCTAssertTrue(text.contains("Embed limit reached"))
        XCTAssertTrue(CanvasRichMarkdown.render("![[../Outside]]", object: source, snapshot: snapshot, vault: vault, width: 280).string.contains("Embed not found"))
    }
    @MainActor func testLocalSectionEmbedIsAllowedUntilItActuallyRecurses() throws {
        let (_, workspace) = try fixture(), vault = CanvasVault(workspace: workspace)
        let source = LocusObject(type: "note", title: "Source", content: ["text": .string("# Intro\n![[#Detail]]\n## Detail\nLocal content")])
        var snapshot = WorkspaceSnapshot(spaceID: UUID()); snapshot.objects = [source]
        let text = CanvasRichMarkdown.render(source.text, object: source, snapshot: snapshot, vault: vault, width: 280).string
        XCTAssertFalse(text.contains("Cyclic embed")); XCTAssertEqual(text.components(separatedBy: "Local content").count, 3)
    }
    @MainActor func testEmbeddedRelativeLinkUsesItsSourceFolder() throws {
        let (root, workspace) = try fixture(), vault = CanvasVault(workspace: workspace)
        let folder = root.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("[[Sibling#Detail]]".utf8).write(to: folder.appendingPathComponent("Part.md"))
        try Data("## Detail\nNested sibling".utf8).write(to: folder.appendingPathComponent("Sibling.md"))
        try Data("## Detail\nWrong root sibling".utf8).write(to: root.appendingPathComponent("Sibling.md"))
        XCTAssertTrue(vault.connect(root))
        let source = LocusObject(type: "note", title: "Source", content: ["text": .string("![[Nested/Part]]")])
        var snapshot = WorkspaceSnapshot(spaceID: UUID()); snapshot.objects = [source]
        let rendered = CanvasRichMarkdown.render(source.text, object: source, snapshot: snapshot, vault: vault, width: 280)
        let range = (rendered.string as NSString).range(of: "Sibling")
        let link = try XCTUnwrap(rendered.attribute(.link, at: range.location, effectiveRange: nil) as? URL)
        XCTAssertEqual(CanvasReference(link)?.target, "Nested/Sibling.md"); XCTAssertEqual(CanvasReference(link)?.fragment, "Detail")
    }
}
