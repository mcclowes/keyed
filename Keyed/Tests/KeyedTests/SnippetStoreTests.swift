@testable import Keyed
import SwiftData
import XCTest

@MainActor
final class SnippetStoreTests: XCTestCase {
    private var store: SnippetStore!
    private var container: ModelContainer!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Snippet.self,
            SnippetGroup.self,
            AppExclusion.self,
            configurations: config
        )
        store = SnippetStore(modelContext: container.mainContext)
    }

    // MARK: - Add snippet

    func test_addSnippet_createsSnippet() throws {
        let snippet = try store.addSnippet(
            abbreviation: ":email",
            expansion: "test@example.com",
            label: "",
            groupID: nil
        )
        XCTAssertEqual(snippet.abbreviation, ":email")
        XCTAssertEqual(snippet.expansion, "test@example.com")
        XCTAssertEqual(snippet.usageCount, 0)
    }

    func test_addSnippet_updatesAbbreviationMap() throws {
        _ = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com", label: "", groupID: nil)
        XCTAssertEqual(store.abbreviationMap[":email"], "test@example.com")
    }

    func test_addSnippet_emptyAbbreviation_throws() {
        XCTAssertThrowsError(try store.addSnippet(abbreviation: "", expansion: "text", label: "", groupID: nil))
    }

    func test_addSnippet_whitespaceOnly_throws() {
        XCTAssertThrowsError(try store.addSnippet(abbreviation: "   ", expansion: "text", label: "", groupID: nil))
    }

    func test_addSnippet_duplicateAbbreviation_throws() throws {
        _ = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com", label: "", groupID: nil)
        XCTAssertThrowsError(
            try store.addSnippet(abbreviation: ":email", expansion: "other@example.com", label: "", groupID: nil)
        )
    }

    func test_addSnippet_caseInsensitiveDuplicate_throws() throws {
        _ = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com", label: "", groupID: nil)
        XCTAssertThrowsError(
            try store.addSnippet(abbreviation: ":EMAIL", expansion: "other@example.com", label: "", groupID: nil)
        )
    }

    // MARK: - Update snippet

    func test_updateSnippet_changesExpansion() throws {
        let snippet = try store.addSnippet(
            abbreviation: ":email",
            expansion: "old@example.com",
            label: "",
            groupID: nil
        )
        try store.updateSnippet(snippet, abbreviation: nil, expansion: "new@example.com", label: nil, groupID: nil)
        XCTAssertEqual(snippet.expansion, "new@example.com")
        XCTAssertEqual(store.abbreviationMap[":email"], "new@example.com")
    }

    func test_updateSnippet_changesAbbreviation() throws {
        let snippet = try store.addSnippet(
            abbreviation: ":email",
            expansion: "test@example.com",
            label: "",
            groupID: nil
        )
        try store.updateSnippet(snippet, abbreviation: ":mail", expansion: nil, label: nil, groupID: nil)
        XCTAssertNil(store.abbreviationMap[":email"])
        XCTAssertEqual(store.abbreviationMap[":mail"], "test@example.com")
    }

    // MARK: - Delete snippet

    func test_deleteSnippet_removesFromStore() throws {
        let snippet = try store.addSnippet(
            abbreviation: ":email",
            expansion: "test@example.com",
            label: "",
            groupID: nil
        )
        try store.deleteSnippet(snippet)
        XCTAssertTrue(store.allSnippets().isEmpty)
        XCTAssertNil(store.abbreviationMap[":email"])
    }

    // MARK: - Duplicate snippet

    func test_duplicateSnippet_avoidsCollision() throws {
        let snippet = try store.addSnippet(abbreviation: ":a", expansion: "x", label: "", groupID: nil)
        let first = try store.duplicateSnippet(snippet)
        let second = try store.duplicateSnippet(snippet)
        XCTAssertNotEqual(first.abbreviation, second.abbreviation)
        XCTAssertEqual(first.abbreviation, ":a_copy")
        XCTAssertEqual(second.abbreviation, ":a_copy2")
    }

    // MARK: - Search

    func test_searchSnippets_findsByAbbreviation() throws {
        _ = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com", label: "", groupID: nil)
        _ = try store.addSnippet(abbreviation: ":sig", expansion: "Best regards", label: "Signature", groupID: nil)
        let results = store.searchSnippets(query: "email")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.abbreviation, ":email")
    }

    func test_searchSnippets_findsByLabel() throws {
        _ = try store.addSnippet(abbreviation: ":sig", expansion: "Best regards", label: "Signature", groupID: nil)
        let results = store.searchSnippets(query: "Signature")
        XCTAssertEqual(results.count, 1)
    }

    func test_searchSnippets_emptyQuery_returnsAll() throws {
        _ = try store.addSnippet(abbreviation: ":a", expansion: "aaa", label: "", groupID: nil)
        _ = try store.addSnippet(abbreviation: ":b", expansion: "bbb", label: "", groupID: nil)
        XCTAssertEqual(store.searchSnippets(query: "").count, 2)
    }

    // MARK: - Usage count

    func test_incrementUsageCount_incrementsCount() throws {
        let snippet = try store.addSnippet(
            abbreviation: ":email",
            expansion: "test@example.com",
            label: "",
            groupID: nil
        )
        store.incrementUsageCount(for: ":email")
        XCTAssertEqual(snippet.usageCount, 1)
        store.incrementUsageCount(for: ":email")
        XCTAssertEqual(snippet.usageCount, 2)
    }

    // MARK: - Groups

    func test_addGroup_createsGroup() throws {
        let group = try store.addGroup(name: "Work")
        XCTAssertEqual(group.name, "Work")
    }

    func test_deleteGroup_unassignsSnippets() throws {
        let group = try store.addGroup(name: "Work")
        let snippet = try store.addSnippet(
            abbreviation: ":email",
            expansion: "test@example.com",
            label: "",
            groupID: group.id
        )
        try store.deleteGroup(group)
        XCTAssertNil(snippet.groupID)
    }

    // MARK: - Exclusions

    func test_addExclusion_appearsInBundleIDs() throws {
        _ = try store.addExclusion(bundleIdentifier: "com.example.app", appName: "Example")
        XCTAssertTrue(store.excludedBundleIDs.contains("com.example.app"))
    }

    func test_removeExclusion_removesFromBundleIDs() throws {
        let exclusion = try store.addExclusion(bundleIdentifier: "com.example.app", appName: "Example")
        try store.removeExclusion(exclusion)
        XCTAssertFalse(store.excludedBundleIDs.contains("com.example.app"))
    }

    func test_addExclusion_duplicate_returnsExisting() throws {
        let first = try store.addExclusion(bundleIdentifier: "com.example.app", appName: "Example")
        let second = try store.addExclusion(bundleIdentifier: "com.example.app", appName: "Example")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.allExclusions().count, 1)
    }

    func test_seedDefaultExclusions_addsAllEntriesOnEmptyStore() {
        let entries = [
            DefaultExclusions.Entry(bundleIdentifier: "com.apple.Terminal", appName: "Terminal"),
            DefaultExclusions.Entry(bundleIdentifier: "com.bitwarden.desktop", appName: "Bitwarden"),
        ]
        let inserted = store.seedDefaultExclusions(entries)
        XCTAssertEqual(inserted, 2)
        XCTAssertTrue(store.excludedBundleIDs.contains("com.apple.Terminal"))
        XCTAssertTrue(store.excludedBundleIDs.contains("com.bitwarden.desktop"))
    }

    func test_seedDefaultExclusions_skipsAlreadyPresent() throws {
        _ = try store.addExclusion(bundleIdentifier: "com.apple.Terminal", appName: "Terminal")
        let entries = [
            DefaultExclusions.Entry(bundleIdentifier: "com.apple.Terminal", appName: "Terminal"),
            DefaultExclusions.Entry(bundleIdentifier: "com.bitwarden.desktop", appName: "Bitwarden"),
        ]
        let inserted = store.seedDefaultExclusions(entries)
        XCTAssertEqual(inserted, 1)
        XCTAssertEqual(store.allExclusions().count, 2)
    }

    func test_seedDefaultExclusions_bundledListIsNonEmptyAndUnique() {
        let ids = DefaultExclusions.entries.map(\.bundleIdentifier)
        XCTAssertFalse(ids.isEmpty)
        XCTAssertEqual(Set(ids).count, ids.count, "Default exclusion list must have unique bundle IDs")
    }

    // MARK: - Default snippets

    func test_seedDefaultSnippets_addsAllEntriesOnEmptyStore() {
        let entries = [
            DefaultSnippets.Entry(abbreviation: ";date", expansion: "{date}", label: "Today's date"),
            DefaultSnippets.Entry(abbreviation: ";tm", expansion: "™", label: "Trademark"),
        ]
        let inserted = store.seedDefaultSnippets(entries)
        XCTAssertEqual(inserted, 2)
        XCTAssertEqual(store.abbreviationMap[";date"], "{date}")
        XCTAssertEqual(store.abbreviationMap[";tm"], "™")
    }

    func test_seedDefaultSnippets_skipsAlreadyPresentCaseInsensitive() throws {
        _ = try store.addSnippet(abbreviation: ";DATE", expansion: "mine", label: "", groupID: nil)
        let entries = [
            DefaultSnippets.Entry(abbreviation: ";date", expansion: "{date}", label: "Today's date"),
            DefaultSnippets.Entry(abbreviation: ";tm", expansion: "™", label: "Trademark"),
        ]
        let inserted = store.seedDefaultSnippets(entries)
        XCTAssertEqual(inserted, 1)
        XCTAssertEqual(store.abbreviationMap[";DATE"], "mine", "User's snippet must not be overwritten")
        XCTAssertEqual(store.abbreviationMap[";tm"], "™")
    }

    func test_seedDefaultSnippets_bundledListIsNonEmptyAndUnique() {
        let abbrevs = DefaultSnippets.entries.map { $0.abbreviation.lowercased() }
        XCTAssertFalse(abbrevs.isEmpty)
        XCTAssertEqual(Set(abbrevs).count, abbrevs.count, "Default snippet list must have unique abbreviations")
    }

    func test_seedDefaultSnippets_bundledListCanBeInsertedWithoutErrors() {
        let inserted = store.seedDefaultSnippets()
        XCTAssertEqual(inserted, DefaultSnippets.entries.count)
        XCTAssertEqual(store.allSnippets().count, DefaultSnippets.entries.count)
    }

    // MARK: - Pinned snippets

    func test_newSnippet_defaultsToUnpinned() throws {
        let snippet = try store.addSnippet(
            abbreviation: ":email",
            expansion: "test@example.com",
            label: "",
            groupID: nil
        )
        XCTAssertFalse(snippet.isPinned)
    }

    func test_setPinned_true_marksSnippetPinned() throws {
        let snippet = try store.addSnippet(
            abbreviation: ":email",
            expansion: "test@example.com",
            label: "",
            groupID: nil
        )
        try store.setPinned(snippet, isPinned: true)
        XCTAssertTrue(snippet.isPinned)
    }

    func test_setPinned_false_unmarksSnippet() throws {
        let snippet = try store.addSnippet(
            abbreviation: ":email",
            expansion: "test@example.com",
            label: "",
            groupID: nil
        )
        try store.setPinned(snippet, isPinned: true)
        try store.setPinned(snippet, isPinned: false)
        XCTAssertFalse(snippet.isPinned)
    }

    func test_pinnedSnippets_returnsOnlyPinned() throws {
        let pinned = try store.addSnippet(abbreviation: ":a", expansion: "aaa", label: "", groupID: nil)
        _ = try store.addSnippet(abbreviation: ":b", expansion: "bbb", label: "", groupID: nil)
        try store.setPinned(pinned, isPinned: true)

        let result = store.pinnedSnippets
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.abbreviation, ":a")
    }

    func test_pinnedSnippets_preservesInsertionOrder() throws {
        let first = try store.addSnippet(abbreviation: ":b", expansion: "x", label: "", groupID: nil)
        let second = try store.addSnippet(abbreviation: ":a", expansion: "y", label: "", groupID: nil)
        let third = try store.addSnippet(abbreviation: ":c", expansion: "z", label: "", groupID: nil)
        try store.setPinned(first, isPinned: true)
        try store.setPinned(second, isPinned: true)
        try store.setPinned(third, isPinned: true)

        let result = store.pinnedSnippets
        XCTAssertEqual(result.map(\.abbreviation), [":b", ":a", ":c"])
    }

    func test_deletePinnedSnippet_removesFromPinned() throws {
        let snippet = try store.addSnippet(
            abbreviation: ":email",
            expansion: "test@example.com",
            label: "",
            groupID: nil
        )
        try store.setPinned(snippet, isPinned: true)
        try store.deleteSnippet(snippet)
        XCTAssertTrue(store.pinnedSnippets.isEmpty)
    }

    func test_setPinned_idempotent() throws {
        let snippet = try store.addSnippet(abbreviation: ":a", expansion: "x", label: "", groupID: nil)
        try store.setPinned(snippet, isPinned: true)
        let firstOrder = snippet.pinnedSortOrder
        try store.setPinned(snippet, isPinned: true)
        XCTAssertEqual(snippet.pinnedSortOrder, firstOrder)
    }

    // MARK: - Staleness (regression test for the unified-mutation bug)

    func test_deleteViaStore_removesFromAbbreviationMap() throws {
        let snippet = try store.addSnippet(abbreviation: ":gone", expansion: "bye", label: "", groupID: nil)
        XCTAssertNotNil(store.abbreviationMap[":gone"])
        try store.deleteSnippet(snippet)
        XCTAssertNil(store.abbreviationMap[":gone"])
    }
}
