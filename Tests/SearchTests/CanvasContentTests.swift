import XCTest
import AppKit
@testable import Search

final class CanvasContentTests: XCTestCase {
    @MainActor func testUnicodeTasksKeepExactSourceOffsetAndSkipCode() throws {
        let source = "Emoji 🌿\n- [ ] **Find reference**\n```\n- [x] Not a task\n```\n  * [X] Review"
        let rendered = CanvasMarkdown.render(source), plain = rendered.string as NSString
        let first = plain.range(of: "☐"), second = plain.range(of: "☑")
        XCTAssertNotEqual(first.location, NSNotFound); XCTAssertNotEqual(second.location, NSNotFound)
        let link = try XCTUnwrap(rendered.attribute(.link, at: first.location, effectiveRange: nil) as? URL)
        let offset = try XCTUnwrap(Int(URLComponents(url: link, resolvingAgainstBaseURL: false)!.queryItems![0].value!))
        XCTAssertEqual((source as NSString).substring(with: NSRange(location: offset, length: 3)), "[ ]")
        XCTAssertEqual(CanvasDocument.togglingTask(source, offset: offset), source.replacingOccurrences(of: "- [ ]", with: "- [x]"))
        XCTAssertTrue(rendered.string.contains("- [x] Not a task"))
        XCTAssertNil(CanvasDocument.togglingTask(source, offset: 0)); XCTAssertNil(CanvasDocument.togglingTask(source, offset: Int.max))
    }
    @MainActor func testWikiAliasesResolveUniqueSpaceObjectsAndKeepFragments() throws {
        let rendered = CanvasMarkdown.render("[[Design notes#Spacing|Read the spacing]] and ![[Keep embed source]]")
        XCTAssertTrue(rendered.string.contains("Read the spacing")); XCTAssertTrue(rendered.string.contains("![[Keep embed source]]"))
        let link = try XCTUnwrap(rendered.attribute(.link, at: 0, effectiveRange: nil) as? URL)
        let ref = try XCTUnwrap(CanvasReference(link)); XCTAssertEqual(ref.target, "Design notes"); XCTAssertEqual(ref.fragment, "Spacing")
        let note = LocusObject(type: "note", title: "Design notes", content: ["text": .string("## Spacing")])
        var snapshot = WorkspaceSnapshot(spaceID: UUID()); snapshot.objects = [note]
        XCTAssertEqual(ref.resolve(in: snapshot), note)
        let local = try XCTUnwrap(CanvasReference(try XCTUnwrap(CanvasReference.url("#Spacing"))))
        XCTAssertEqual(local.resolve(in: snapshot, source: note), note); XCTAssertNil(local.resolve(in: snapshot))
        snapshot.objects.append(LocusObject(type: "note", title: "Design notes", content: [:])); XCTAssertNil(ref.resolve(in: snapshot))
        XCTAssertNil(CanvasReference(URL(string: "https://example.com")!))
    }
    @MainActor func testWikiSyntaxInInlineCodeRemainsLiteral() {
        let rendered = CanvasMarkdown.render("`[[Literal]]` and ``[[Also literal]]`` then [[Real]]")
        XCTAssertTrue(rendered.string.contains("[[Literal]]")); XCTAssertTrue(rendered.string.contains("[[Also literal]]"))
        let plain = rendered.string as NSString, literal = plain.range(of: "[[Literal]]")
        XCTAssertNil(rendered.attribute(.link, at: literal.location, effectiveRange: nil))
        let real = plain.range(of: "Real"); XCTAssertNotNil(rendered.attribute(.link, at: real.location, effectiveRange: nil))
    }
    func testHeadingAndBlockSubpathsExcludeOtherSectionsAndCodeHeadings() {
        let source = "# Intro\nFirst\n## Spacing\nFour units\n### Nested\nDetail\n```\n## Fake\n```\n## Color\nBlue"
        XCTAssertEqual(CanvasDocument.section(source, subpath: "#spacing"), "## Spacing\nFour units\n### Nested\nDetail\n```\n## Fake\n```")
        XCTAssertEqual(CanvasDocument.section("First\n\nA paragraph\nwith detail ^block-1\n\nNext", subpath: "#^block-1"), "A paragraph\nwith detail")
        XCTAssertNil(CanvasDocument.section(source, subpath: "#Missing"))
        let repeated = "Spacing mentioned first 🌿\n```\n## Spacing\n```\n## Spacing\nActual heading"
        XCTAssertEqual(CanvasDocument.fragmentOffset(repeated, subpath: "#Spacing"), ("Spacing mentioned first 🌿\n```\n## Spacing\n```\n" as NSString).length)
    }
}
