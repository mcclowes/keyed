@testable import Keyed
import XCTest

@MainActor
final class SuggestionTrackerTests: XCTestCase {
    private var store: MockSuggestionStore!
    private var tracker: SuggestionTracker!

    override func setUp() {
        super.setUp()
        store = MockSuggestionStore()
        tracker = SuggestionTracker(store: store)
    }

    // MARK: - extractPhrase (pure helpers)

    func test_extractPhrase_acceptsValidPhrase() {
        let result = SuggestionTracker.extractPhrase(
            from: "thanks for your time this week",
            config: .init()
        )
        XCTAssertEqual(result?.display, "thanks for your time this week")
        XCTAssertEqual(result?.normalized, "thanks for your time this week")
    }

    func test_extractPhrase_rejectsTooShort() {
        XCTAssertNil(SuggestionTracker.extractPhrase(from: "too short", config: .init()))
    }

    func test_extractPhrase_rejectsTooFewWords() {
        // Long enough character-wise but only two words.
        XCTAssertNil(SuggestionTracker.extractPhrase(from: "supercalifragilistic expialidocious", config: .init()))
    }

    func test_extractPhrase_rejectsPureSymbols() {
        XCTAssertNil(SuggestionTracker.extractPhrase(from: "!!! !!! !!! !!!", config: .init()))
    }

    func test_extractPhrase_normalizesToLowercase() {
        let result = SuggestionTracker.extractPhrase(from: "Thanks For Your Message", config: .init())
        XCTAssertEqual(result?.display, "Thanks For Your Message")
        XCTAssertEqual(result?.normalized, "thanks for your message")
    }

    func test_extractPhrase_collapsesInternalWhitespace() {
        let result = SuggestionTracker.extractPhrase(from: "hello   world   how   are   you", config: .init())
        XCTAssertEqual(result?.display, "hello world how are you")
    }

    // MARK: - isTerminator

    func test_isTerminator_detectsSentenceEndings() {
        XCTAssertTrue(SuggestionTracker.isTerminator("."))
        XCTAssertTrue(SuggestionTracker.isTerminator("!"))
        XCTAssertTrue(SuggestionTracker.isTerminator("?"))
        XCTAssertTrue(SuggestionTracker.isTerminator("\n"))
    }

    func test_isTerminator_ignoresRegularCharacters() {
        XCTAssertFalse(SuggestionTracker.isTerminator("a"))
        XCTAssertFalse(SuggestionTracker.isTerminator(" "))
        XCTAssertFalse(SuggestionTracker.isTerminator(","))
    }

    // MARK: - Streaming behavior

    func test_typingPhraseThenPeriod_recordsPhrase() {
        typeString("thanks for your message today")
        tracker.observe(.character("."))
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.normalized, "thanks for your message today")
    }

    func test_typingSamePhraseTwice_recordsTwice() {
        typeString("thanks for your message today")
        tracker.observe(.character("."))
        typeString("thanks for your message today")
        tracker.observe(.character("."))
        XCTAssertEqual(store.records.count, 2)
    }

    func test_boundaryKey_flushesBuffer() {
        typeString("thanks for your message today")
        tracker.observe(.boundaryKey)
        XCTAssertEqual(store.records.count, 1)
    }

    func test_shortTypingBelowMinimum_recordsNothing() {
        typeString("too short")
        tracker.observe(.character("."))
        XCTAssertTrue(store.records.isEmpty)
    }

    func test_disabled_doesNotRecord() {
        tracker.isEnabled = false
        typeString("thanks for your message today")
        tracker.observe(.character("."))
        XCTAssertTrue(store.records.isEmpty)
    }

    func test_backspace_removesLastCharacter() {
        typeString("thanks for your message todax")
        tracker.observe(.backspace)
        tracker.observe(.character("y"))
        tracker.observe(.character("."))
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.normalized, "thanks for your message today")
    }

    func test_reset_clearsBuffer() {
        typeString("thanks for your message today")
        tracker.reset()
        tracker.observe(.character("."))
        XCTAssertTrue(store.records.isEmpty)
    }

    private func typeString(_ text: String) {
        for char in text {
            tracker.observe(.character(String(char)))
        }
    }
}

// MARK: - Mock

@MainActor
final class MockSuggestionStore: SuggestionStoring {
    struct Record: Equatable {
        let text: String
        let normalized: String
    }

    var records: [Record] = []

    func recordPhrase(text: String, normalized: String) {
        records.append(Record(text: text, normalized: normalized))
    }

    func pendingSuggestions(minCount _: Int) -> [PhraseSuggestion] {
        []
    }

    func allSuggestions() -> [PhraseSuggestion] {
        []
    }

    func dismiss(_: PhraseSuggestion) throws {}
    func delete(_: PhraseSuggestion) throws {}
    func clearAll() throws {}
}
