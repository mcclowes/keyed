@testable import Keyed
import XCTest

@MainActor
final class ExpansionEngineTests: XCTestCase {
    private var monitor: MockKeystrokeMonitor!
    private var injector: MockTextInjector!
    private var engine: ExpansionEngine!

    override func setUp() {
        super.setUp()
        monitor = MockKeystrokeMonitor()
        injector = MockTextInjector()
        engine = ExpansionEngine(monitor: monitor, injector: injector, bufferCapacity: 64)
        engine.updateAbbreviations([":email": "test@example.com", ":sig": "Best regards,\nJohn"])
        engine.start()
    }

    override func tearDown() {
        engine.stop()
        super.tearDown()
    }

    // MARK: - Basic expansion

    func test_typingAbbreviation_triggersExpansion() async {
        typeString(":email")
        await waitForInjector()
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.abbreviationLength, 6)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "test@example.com")
    }

    func test_typingNonAbbreviation_doesNotTrigger() async {
        typeString("hello")
        await waitForInjector()
        XCTAssertTrue(injector.replaceTextCalls.isEmpty)
    }

    func test_partialAbbreviation_doesNotTrigger() async {
        typeString(":ema")
        await waitForInjector()
        XCTAssertTrue(injector.replaceTextCalls.isEmpty)
    }

    // MARK: - Word boundary

    func test_abbreviationInsideWord_doesNotExpand() async {
        // ":email" sits after "a" (a letter). No word boundary before ":", so no expansion.
        // (Abbreviation starts with ":" which is itself non-alphanumeric, so the preceding char matters.)
        engine.updateAbbreviations(["foo": "bar"])
        typeString("xfoo")
        await waitForInjector()
        XCTAssertTrue(injector.replaceTextCalls.isEmpty)
    }

    func test_abbreviationAfterSpace_expands() async {
        engine.updateAbbreviations(["foo": "bar"])
        typeString("x foo")
        await waitForInjector()
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
    }

    func test_abbreviationAtBufferStart_expands() async {
        engine.updateAbbreviations(["foo": "bar"])
        typeString("foo")
        await waitForInjector()
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
    }

    // MARK: - Ambiguous prefixes

    /// Without boundary-triggered expansion, the engine fires as soon as any suffix matches.
    /// So when both ":sig" and ":signature" exist, ":sig" fires before the user can finish
    /// typing ":signature". True longest-match would need the engine to wait for a terminator.
    /// Documenting current behavior here as a regression guard.
    func test_ambiguousAbbreviations_shorterFiresFirst() async {
        engine.updateAbbreviations([":sig": "short", ":signature": "long"])
        typeString(":sig")
        await waitForInjector()
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "short")
    }

    // MARK: - Disabled state

    func test_disabled_doesNotExpand() async {
        engine.setEnabled(false)
        typeString(":email")
        await waitForInjector()
        XCTAssertTrue(injector.replaceTextCalls.isEmpty)
    }

    func test_reEnabled_expandsAgain() async {
        engine.setEnabled(false)
        engine.setEnabled(true)
        typeString(":email")
        await waitForInjector()
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
    }

    // MARK: - Boundary keys reset buffer

    func test_boundaryKey_resetsBuffer() async {
        typeString(":ema")
        engine.handleKeystrokeForTesting(.boundaryKey)
        typeString("il")
        await waitForInjector()
        XCTAssertTrue(injector.replaceTextCalls.isEmpty)
    }

    // MARK: - Modified keys ignored

    func test_modifiedKey_doesNotAffectBuffer() async {
        typeString(":emai")
        engine.handleKeystrokeForTesting(.modifiedKey)
        typeString("l")
        await waitForInjector()
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
    }

    // MARK: - Backspace

    func test_backspace_removesFromBuffer() async {
        typeString(":emaix")
        engine.handleKeystrokeForTesting(.backspace)
        typeString("l")
        await waitForInjector()
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "test@example.com")
    }

    // MARK: - Monitor lifecycle

    func test_start_callsMonitorStart() {
        XCTAssertEqual(monitor.startCallCount, 1)
    }

    func test_stop_callsMonitorStop() {
        engine.stop()
        XCTAssertEqual(monitor.stopCallCount, 1)
    }

    // MARK: - Abbreviation updates

    func test_updateAbbreviations_newMapTakesPrecedence() async {
        engine.updateAbbreviations([":hi": "Hello there!"])
        typeString(":hi")
        await waitForInjector()
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "Hello there!")
    }

    func test_updateAbbreviations_oldAbbreviationsNoLongerWork() async {
        engine.updateAbbreviations([":hi": "Hello there!"])
        typeString(":email")
        await waitForInjector()
        XCTAssertTrue(injector.replaceTextCalls.isEmpty)
    }

    // MARK: - Case matching

    func test_allCapsAbbreviation_expandsInAllCaps() async {
        typeString(":EMAIL")
        await waitForInjector()
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "TEST@EXAMPLE.COM")
    }

    func test_titleCaseAbbreviation_expandsInTitleCase() async {
        engine.updateAbbreviations([":sig": "best regards"])
        typeString(":Sig")
        await waitForInjector()
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "Best regards")
    }

    func test_lowercaseAbbreviation_expandsAsIs() async {
        typeString(":email")
        await waitForInjector()
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "test@example.com")
    }

    // MARK: - Direct injection (pinned snippets)

    func test_injectSnippet_postsExpansionWithZeroBackspaces() async {
        let snippet = Snippet(abbreviation: ":hi", expansion: "Hello there!")
        await engine.injectSnippet(snippet)
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.abbreviationLength, 0)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "Hello there!")
    }

    func test_injectSnippet_resolvesCursorPlaceholder() async {
        let snippet = Snippet(abbreviation: ":wrap", expansion: "<b>{cursor}</b>")
        await engine.injectSnippet(snippet)
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "<b></b>")
        XCTAssertEqual(injector.replaceTextCalls.first?.cursorOffset, 4)
    }

    func test_injectSnippet_doesNotAffectTypedBuffer() async {
        typeString(":ema")
        let snippet = Snippet(abbreviation: ":pinned", expansion: "pinned text")
        await engine.injectSnippet(snippet)
        // After direct injection, buffer is reset, so ":il" typed next should not complete ":email".
        typeString("il")
        await waitForInjector()
        // Only the direct injection call should have happened.
        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "pinned text")
    }

    // MARK: - Helpers

    private func typeString(_ text: String) {
        for char in text {
            engine.handleKeystrokeForTesting(.character(String(char)))
        }
    }

    private func waitForInjector() async {
        // Give the expansion Task a couple of runloop ticks to flush through the MainActor.
        for _ in 0..<5 {
            await Task.yield()
        }
    }
}
