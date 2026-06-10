import XCTest
@testable import ZoomItCore

final class DemoTypeScriptTests: XCTestCase {
    func testSingleSnippet() {
        let script = DemoTypeScript.parse("hello world")
        XCTAssertEqual(script.snippets.count, 1)
        XCTAssertEqual(script.snippets[0].plainText, "hello world")
    }

    func testSnippetsSeparatedByEnd() {
        let script = DemoTypeScript.parse("first snippet\n[end]\nsecond snippet\n[END]\nthird")
        XCTAssertEqual(script.snippets.count, 3)
        XCTAssertEqual(script.snippets[0].plainText, "first snippet")
        XCTAssertEqual(script.snippets[1].plainText, "second snippet")
        XCTAssertEqual(script.snippets[2].plainText, "third")
    }

    func testMultilineSnippetPreservesNewlines() {
        let script = DemoTypeScript.parse("line one\nline two\n[end]\nnext")
        XCTAssertEqual(script.snippets[0].plainText, "line one\nline two")
    }

    func testPauseToken() {
        let script = DemoTypeScript.parse("before[pause:5]after")
        XCTAssertEqual(script.snippets.count, 1)
        let elements = script.snippets[0].elements
        XCTAssertEqual(elements.count, 3)
        XCTAssertEqual(elements[0], .typeText("before"))
        XCTAssertEqual(elements[1], .pause(0.5))
        XCTAssertEqual(elements[2], .typeText("after"))
    }

    func testInvalidPauseTokenTypedVerbatim() {
        let script = DemoTypeScript.parse("a[pause:xyz]b")
        XCTAssertEqual(script.snippets[0].plainText, "a[pause:xyz]b")
    }

    func testWindowsLineEndings() {
        let script = DemoTypeScript.parse("one\r\n[end]\r\ntwo")
        XCTAssertEqual(script.snippets.count, 2)
        XCTAssertEqual(script.snippets[0].plainText, "one")
        XCTAssertEqual(script.snippets[1].plainText, "two")
    }

    func testEmptyFileYieldsNoSnippets() {
        XCTAssertTrue(DemoTypeScript.parse("").snippets.isEmpty)
        XCTAssertTrue(DemoTypeScript.parse("[end]\n[end]").snippets.isEmpty)
    }

    func testCursorAdvanceAndBack() {
        let script = DemoTypeScript.parse("a\n[end]\nb\n[end]\nc")
        let cursor = DemoTypeCursor(script: script)
        XCTAssertEqual(cursor.nextSnippet()?.plainText, "a")
        XCTAssertEqual(cursor.nextSnippet()?.plainText, "b")
        cursor.moveBack()
        XCTAssertEqual(cursor.nextSnippet()?.plainText, "b", "Ctrl+Shift+7 retypes the previous snippet")
        XCTAssertEqual(cursor.nextSnippet()?.plainText, "c")
        XCTAssertNil(cursor.nextSnippet(), "exhausted script returns nil")
        cursor.reset()
        XCTAssertEqual(cursor.nextSnippet()?.plainText, "a")
    }

    func testMoveBackAtStartStaysAtStart() {
        let cursor = DemoTypeCursor(script: DemoTypeScript.parse("only"))
        cursor.moveBack()
        XCTAssertEqual(cursor.nextSnippet()?.plainText, "only")
    }
}
