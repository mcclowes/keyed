import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.mcclowes.keyed", category: "SnippetStore")

@MainActor
protocol SnippetStoring {
    var abbreviationMap: [String: String] { get }
    func addSnippet(abbreviation: String, expansion: String, label: String, groupID: UUID?) throws -> Snippet
    func deleteSnippet(_ snippet: Snippet) throws
    func allSnippets() -> [Snippet]
    func findSnippet(byAbbreviation abbreviation: String) -> Snippet?
    func searchSnippets(query: String) -> [Snippet]
    func incrementUsageCount(for abbreviation: String)
    func allGroups() -> [SnippetGroup]
    func addGroup(name: String) throws -> SnippetGroup
    func deleteGroup(_ group: SnippetGroup) throws
}

@MainActor
@Observable
final class SnippetStore: SnippetStoring {
    private let modelContext: ModelContext
    private(set) var abbreviationMap: [String: String] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        rebuildAbbreviationMap()
    }

    // MARK: - Snippet CRUD

    func addSnippet(
        abbreviation: String,
        expansion: String,
        label: String = "",
        groupID: UUID? = nil
    ) throws -> Snippet {
        guard !abbreviation.isEmpty else {
            throw SnippetStoreError.emptyAbbreviation
        }
        if findSnippet(byAbbreviation: abbreviation) != nil {
            throw SnippetStoreError.duplicateAbbreviation(abbreviation)
        }
        let snippet = Snippet(abbreviation: abbreviation, expansion: expansion, label: label, groupID: groupID)
        modelContext.insert(snippet)
        try modelContext.save()
        rebuildAbbreviationMap()
        logger.info("Added snippet: \(abbreviation)")
        return snippet
    }

    func updateSnippet(
        _ snippet: Snippet,
        abbreviation: String? = nil,
        expansion: String? = nil,
        label: String? = nil,
        groupID: UUID?? = nil
    ) throws {
        if let abbreviation {
            guard !abbreviation.isEmpty else {
                throw SnippetStoreError.emptyAbbreviation
            }
            if abbreviation != snippet.abbreviation, findSnippet(byAbbreviation: abbreviation) != nil {
                throw SnippetStoreError.duplicateAbbreviation(abbreviation)
            }
            snippet.abbreviation = abbreviation
        }
        if let expansion { snippet.expansion = expansion }
        if let label { snippet.label = label }
        if let groupID { snippet.groupID = groupID }
        snippet.updatedAt = .now
        try modelContext.save()
        rebuildAbbreviationMap()
    }

    func deleteSnippet(_ snippet: Snippet) throws {
        logger.info("Deleting snippet: \(snippet.abbreviation)")
        modelContext.delete(snippet)
        try modelContext.save()
        rebuildAbbreviationMap()
    }

    func incrementUsageCount(for abbreviation: String) {
        guard let snippet = findSnippet(byAbbreviation: abbreviation) else { return }
        snippet.usageCount += 1
        try? modelContext.save()
    }

    // MARK: - Queries

    func allSnippets() -> [Snippet] {
        let descriptor = FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\.abbreviation)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func findSnippet(byAbbreviation abbreviation: String) -> Snippet? {
        let descriptor = FetchDescriptor<Snippet>(predicate: #Predicate { $0.abbreviation == abbreviation })
        return try? modelContext.fetch(descriptor).first
    }

    func searchSnippets(query: String) -> [Snippet] {
        guard !query.isEmpty else { return allSnippets() }
        let descriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate {
                $0.abbreviation.localizedStandardContains(query) ||
                    $0.label.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.abbreviation)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Groups

    func allGroups() -> [SnippetGroup] {
        let descriptor = FetchDescriptor<SnippetGroup>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func addGroup(name: String) throws -> SnippetGroup {
        let maxOrder = allGroups().map(\.sortOrder).max() ?? -1
        let group = SnippetGroup(name: name, sortOrder: maxOrder + 1)
        modelContext.insert(group)
        try modelContext.save()
        return group
    }

    func deleteGroup(_ group: SnippetGroup) throws {
        // Unassign snippets from this group
        let groupID = group.id
        let descriptor = FetchDescriptor<Snippet>(predicate: #Predicate { $0.groupID == groupID })
        if let snippets = try? modelContext.fetch(descriptor) {
            for snippet in snippets {
                snippet.groupID = nil
            }
        }
        modelContext.delete(group)
        try modelContext.save()
    }

    // MARK: - Abbreviation Map

    private func rebuildAbbreviationMap() {
        var map: [String: String] = [:]
        for snippet in allSnippets() {
            map[snippet.abbreviation] = snippet.expansion
        }
        abbreviationMap = map
    }
}

enum SnippetStoreError: LocalizedError {
    case emptyAbbreviation
    case duplicateAbbreviation(String)

    var errorDescription: String? {
        switch self {
        case .emptyAbbreviation:
            "Abbreviation cannot be empty."
        case let .duplicateAbbreviation(abbrev):
            "A snippet with abbreviation '\(abbrev)' already exists."
        }
    }
}
