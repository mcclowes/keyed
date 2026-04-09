@testable import Keyed
import SwiftData
import XCTest

@MainActor
final class SnippetStoreTests: XCTestCase {
    private var store: SnippetStore!
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: Snippet.self, SnippetGroup.self, AppExclusion.self, configurations: config)
        store = SnippetStore(modelContext: container.mainContext)
    }

    // MARK: - Add snippet

    func test_addSnippet_createsSnippet() throws {
        let snippet = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com")
        XCTAssertEqual(snippet.abbreviation, ":email")
        XCTAssertEqual(snippet.expansion, "test@example.com")
        XCTAssertEqual(snippet.usageCount, 0)
    }

    func test_addSnippet_updatesAbbreviationMap() throws {
        _ = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com")
        XCTAssertEqual(store.abbreviationMap[":email"], "test@example.com")
    }

    func test_addSnippet_emptyAbbreviation_throws() {
        XCTAssertThrowsError(try store.addSnippet(abbreviation: "", expansion: "text")) { error in
            XCTAssertTrue(error is SnippetStoreError)
        }
    }

    func test_addSnippet_duplicateAbbreviation_throws() throws {
        _ = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com")
        XCTAssertThrowsError(try store.addSnippet(abbreviation: ":email", expansion: "other@example.com")) { error in
            XCTAssertTrue(error is SnippetStoreError)
        }
    }

    // MARK: - Update snippet

    func test_updateSnippet_changesExpansion() throws {
        let snippet = try store.addSnippet(abbreviation: ":email", expansion: "old@example.com")
        try store.updateSnippet(snippet, expansion: "new@example.com")
        XCTAssertEqual(snippet.expansion, "new@example.com")
        XCTAssertEqual(store.abbreviationMap[":email"], "new@example.com")
    }

    func test_updateSnippet_changesAbbreviation() throws {
        let snippet = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com")
        try store.updateSnippet(snippet, abbreviation: ":mail")
        XCTAssertNil(store.abbreviationMap[":email"])
        XCTAssertEqual(store.abbreviationMap[":mail"], "test@example.com")
    }

    // MARK: - Delete snippet

    func test_deleteSnippet_removesFromStore() throws {
        let snippet = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com")
        try store.deleteSnippet(snippet)
        XCTAssertTrue(store.allSnippets().isEmpty)
        XCTAssertNil(store.abbreviationMap[":email"])
    }

    // MARK: - Search

    func test_searchSnippets_findsByAbbreviation() throws {
        _ = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com", label: "")
        _ = try store.addSnippet(abbreviation: ":sig", expansion: "Best regards", label: "Signature")
        let results = store.searchSnippets(query: "email")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.abbreviation, ":email")
    }

    func test_searchSnippets_findsByLabel() throws {
        _ = try store.addSnippet(abbreviation: ":sig", expansion: "Best regards", label: "Signature")
        let results = store.searchSnippets(query: "Signature")
        XCTAssertEqual(results.count, 1)
    }

    func test_searchSnippets_emptyQuery_returnsAll() throws {
        _ = try store.addSnippet(abbreviation: ":a", expansion: "aaa")
        _ = try store.addSnippet(abbreviation: ":b", expansion: "bbb")
        XCTAssertEqual(store.searchSnippets(query: "").count, 2)
    }

    // MARK: - Usage count

    func test_incrementUsageCount_incrementsCount() throws {
        let snippet = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com")
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
        let snippet = try store.addSnippet(abbreviation: ":email", expansion: "test@example.com", groupID: group.id)
        try store.deleteGroup(group)
        XCTAssertNil(snippet.groupID)
    }
}
