@testable import Keyed
import SwiftData
import XCTest

@MainActor
final class SuggestionStoreTests: XCTestCase {
    private var store: SuggestionStore!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PhraseSuggestion.self, configurations: config)
        store = SuggestionStore(modelContext: container.mainContext)
    }

    func test_recordPhrase_createsNewEntry() {
        store.recordPhrase(text: "Thanks for your time", normalized: "thanks for your time")
        XCTAssertEqual(store.allSuggestions().count, 1)
        XCTAssertEqual(store.allSuggestions().first?.count, 1)
    }

    func test_recordPhrase_incrementsExistingEntry() {
        store.recordPhrase(text: "Thanks for your time", normalized: "thanks for your time")
        store.recordPhrase(text: "Thanks for your time", normalized: "thanks for your time")
        store.recordPhrase(text: "Thanks for your time", normalized: "thanks for your time")
        XCTAssertEqual(store.allSuggestions().count, 1)
        XCTAssertEqual(store.allSuggestions().first?.count, 3)
    }

    func test_pendingSuggestions_filtersByCount() {
        store.recordPhrase(text: "a a a a a", normalized: "a a a a a")
        store.recordPhrase(text: "b b b b b", normalized: "b b b b b")
        store.recordPhrase(text: "b b b b b", normalized: "b b b b b")
        store.recordPhrase(text: "b b b b b", normalized: "b b b b b")

        let pending = store.pendingSuggestions(minCount: 3)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.normalizedText, "b b b b b")
    }

    func test_pendingSuggestions_excludesDismissed() throws {
        store.recordPhrase(text: "x x x x x", normalized: "x x x x x")
        store.recordPhrase(text: "x x x x x", normalized: "x x x x x")
        store.recordPhrase(text: "x x x x x", normalized: "x x x x x")

        let suggestion = try XCTUnwrap(store.allSuggestions().first)
        try store.dismiss(suggestion)

        XCTAssertTrue(store.pendingSuggestions(minCount: 2).isEmpty)
    }

    func test_recordPhrase_doesNotResurrectDismissed() throws {
        store.recordPhrase(text: "y y y y y", normalized: "y y y y y")
        let suggestion = try XCTUnwrap(store.allSuggestions().first)
        try store.dismiss(suggestion)

        store.recordPhrase(text: "y y y y y", normalized: "y y y y y")

        XCTAssertEqual(store.allSuggestions().first?.count, 1) // unchanged
        XCTAssertTrue(store.allSuggestions().first?.isDismissed ?? false)
    }

    func test_clearAll_removesEverything() throws {
        store.recordPhrase(text: "a a a a a", normalized: "a a a a a")
        store.recordPhrase(text: "b b b b b", normalized: "b b b b b")
        try store.clearAll()
        XCTAssertTrue(store.allSuggestions().isEmpty)
    }

    func test_delete_removesSingleSuggestion() throws {
        store.recordPhrase(text: "a a a a a", normalized: "a a a a a")
        store.recordPhrase(text: "b b b b b", normalized: "b b b b b")
        let first = try XCTUnwrap(store.allSuggestions().first)
        try store.delete(first)
        XCTAssertEqual(store.allSuggestions().count, 1)
    }
}
