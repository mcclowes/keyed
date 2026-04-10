@testable import Keyed
import SwiftData
import XCTest

@MainActor
final class SnippetStoreTests: XCTestCase {
    private var store: SnippetStore!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
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

    // MARK: - Staleness (regression test for the unified-mutation bug)

    func test_deleteViaStore_removesFromAbbreviationMap() throws {
        let snippet = try store.addSnippet(abbreviation: ":gone", expansion: "bye", label: "", groupID: nil)
        XCTAssertNotNil(store.abbreviationMap[":gone"])
        try store.deleteSnippet(snippet)
        XCTAssertNil(store.abbreviationMap[":gone"])
    }
}
