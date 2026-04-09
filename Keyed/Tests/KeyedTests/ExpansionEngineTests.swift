import XCTest
@testable import Keyed

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

        // Allow async expansion to complete
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.abbreviationLength, 6)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "test@example.com")
    }

    func test_typingNonAbbreviation_doesNotTrigger() async {
        typeString("hello")

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(injector.replaceTextCalls.isEmpty)
    }

    func test_partialAbbreviation_doesNotTrigger() async {
        typeString(":ema")

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(injector.replaceTextCalls.isEmpty)
    }

    // MARK: - Disabled state

    func test_disabled_doesNotExpand() async {
        engine.setEnabled(false)
        typeString(":email")

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(injector.replaceTextCalls.isEmpty)
    }

    func test_reEnabled_expandsAgain() async {
        engine.setEnabled(false)
        engine.setEnabled(true)
        typeString(":email")

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(injector.replaceTextCalls.count, 1)
    }

    // MARK: - Boundary keys reset buffer

    func test_boundaryKey_resetsBuffer() async {
        typeString(":ema")
        engine.handleKeystrokeForTesting(.boundaryKey)
        typeString("il")

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(injector.replaceTextCalls.isEmpty)
    }

    // MARK: - Modified keys ignored

    func test_modifiedKey_doesNotAffectBuffer() async {
        typeString(":emai")
        engine.handleKeystrokeForTesting(.modifiedKey)
        typeString("l")

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(injector.replaceTextCalls.count, 1)
    }

    // MARK: - Backspace

    func test_backspace_removesFromBuffer() async {
        // Type something that doesn't match, backspace, then complete differently
        typeString(":emaix")
        engine.handleKeystrokeForTesting(.backspace) // removes "x" -> ":emai"
        typeString("l") // -> ":email" which should match

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "test@example.com")
    }

    // MARK: - Monitor lifecycle

    func test_start_callsMonitorStart() {
        // setUp already called start
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

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(injector.replaceTextCalls.count, 1)
        XCTAssertEqual(injector.replaceTextCalls.first?.expansion, "Hello there!")
    }

    func test_updateAbbreviations_oldAbbreviationsNoLongerWork() async {
        engine.updateAbbreviations([":hi": "Hello there!"])
        typeString(":email")

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(injector.replaceTextCalls.isEmpty)
    }

    // MARK: - Helpers

    private func typeString(_ text: String) {
        for char in text {
            engine.handleKeystrokeForTesting(.character(String(char)))
        }
    }
}
