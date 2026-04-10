import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.mcclowes.keyed", category: "SnippetStore")

@MainActor
protocol SnippetStoring: AnyObject {
    var abbreviationMap: [String: String] { get }
    var excludedBundleIDs: Set<String> { get }

    // Snippets
    @discardableResult
    func addSnippet(abbreviation: String, expansion: String, label: String, groupID: UUID?) throws -> Snippet
    func updateSnippet(
        _ snippet: Snippet,
        abbreviation: String?,
        expansion: String?,
        label: String?,
        groupID: UUID??
    ) throws
    func deleteSnippet(_ snippet: Snippet) throws
    func duplicateSnippet(_ snippet: Snippet) throws -> Snippet
    func incrementUsageCount(for abbreviation: String)

    // Queries
    func allSnippets() -> [Snippet]
    func findSnippet(byAbbreviation abbreviation: String) -> Snippet?
    func searchSnippets(query: String) -> [Snippet]

    /// Groups
    func allGroups() -> [SnippetGroup]
    @discardableResult
    func addGroup(name: String) throws -> SnippetGroup
    func deleteGroup(_ group: SnippetGroup) throws

    /// Exclusions
    func allExclusions() -> [AppExclusion]
    @discardableResult
    func addExclusion(bundleIdentifier: String, appName: String) throws -> AppExclusion
    func removeExclusion(_ exclusion: AppExclusion) throws
}

@MainActor
@Observable
final class SnippetStore: SnippetStoring {
    private let modelContext: ModelContext
    private(set) var abbreviationMap: [String: String] = [:]
    private(set) var excludedBundleIDs: Set<String> = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        rebuildAbbreviationMap()
        rebuildExcludedBundleIDs()
    }

    // MARK: - Snippet CRUD

    @discardableResult
    func addSnippet(
        abbreviation: String,
        expansion: String,
        label: String = "",
        groupID: UUID? = nil
    ) throws -> Snippet {
        let trimmed = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SnippetStoreError.emptyAbbreviation
        }
        if findSnippet(byAbbreviationCaseInsensitive: trimmed) != nil {
            throw SnippetStoreError.duplicateAbbreviation(trimmed)
        }
        let snippet = Snippet(abbreviation: trimmed, expansion: expansion, label: label, groupID: groupID)
        modelContext.insert(snippet)
        try modelContext.save()
        rebuildAbbreviationMap()
        logger.info("Added snippet: \(trimmed, privacy: .private)")
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
            let trimmed = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw SnippetStoreError.emptyAbbreviation
            }
            if trimmed.lowercased() != snippet.abbreviation.lowercased(),
               findSnippet(byAbbreviationCaseInsensitive: trimmed) != nil
            {
                throw SnippetStoreError.duplicateAbbreviation(trimmed)
            }
            snippet.abbreviation = trimmed
        }
        if let expansion { snippet.expansion = expansion }
        if let label { snippet.label = label }
        if let groupID { snippet.groupID = groupID }
        snippet.updatedAt = .now
        try modelContext.save()
        rebuildAbbreviationMap()
    }

    func deleteSnippet(_ snippet: Snippet) throws {
        logger.info("Deleting snippet: \(snippet.abbreviation, privacy: .private)")
        modelContext.delete(snippet)
        try modelContext.save()
        rebuildAbbreviationMap()
    }

    @discardableResult
    func duplicateSnippet(_ snippet: Snippet) throws -> Snippet {
        let base = snippet.abbreviation
        var candidate = base + "_copy"
        var suffix = 2
        while findSnippet(byAbbreviationCaseInsensitive: candidate) != nil {
            candidate = "\(base)_copy\(suffix)"
            suffix += 1
        }
        return try addSnippet(
            abbreviation: candidate,
            expansion: snippet.expansion,
            label: snippet.label,
            groupID: snippet.groupID
        )
    }

    func incrementUsageCount(for abbreviation: String) {
        guard let snippet = findSnippet(byAbbreviationCaseInsensitive: abbreviation) else { return }
        snippet.usageCount += 1
        pendingUsageWrites += 1
        if pendingUsageWrites >= usageWriteBatchSize {
            try? modelContext.save()
            pendingUsageWrites = 0
        }
    }

    private var pendingUsageWrites = 0
    private let usageWriteBatchSize = 10

    func flushPendingWrites() {
        guard pendingUsageWrites > 0 else { return }
        try? modelContext.save()
        pendingUsageWrites = 0
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

    private func findSnippet(byAbbreviationCaseInsensitive abbreviation: String) -> Snippet? {
        let lowered = abbreviation.lowercased()
        return allSnippets().first { $0.abbreviation.lowercased() == lowered }
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

    @discardableResult
    func addGroup(name: String) throws -> SnippetGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SnippetStoreError.emptyGroupName }
        let maxOrder = allGroups().map(\.sortOrder).max() ?? -1
        let group = SnippetGroup(name: trimmed, sortOrder: maxOrder + 1)
        modelContext.insert(group)
        try modelContext.save()
        return group
    }

    func deleteGroup(_ group: SnippetGroup) throws {
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

    // MARK: - Exclusions

    func allExclusions() -> [AppExclusion] {
        let descriptor = FetchDescriptor<AppExclusion>(sortBy: [SortDescriptor(\.appName)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addExclusion(bundleIdentifier: String, appName: String) throws -> AppExclusion {
        if let existing = allExclusions().first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return existing
        }
        let exclusion = AppExclusion(bundleIdentifier: bundleIdentifier, appName: appName)
        modelContext.insert(exclusion)
        try modelContext.save()
        rebuildExcludedBundleIDs()
        return exclusion
    }

    func removeExclusion(_ exclusion: AppExclusion) throws {
        modelContext.delete(exclusion)
        try modelContext.save()
        rebuildExcludedBundleIDs()
    }

    // MARK: - Caches

    private func rebuildAbbreviationMap() {
        var map: [String: String] = [:]
        for snippet in allSnippets() {
            map[snippet.abbreviation] = snippet.expansion
        }
        abbreviationMap = map
    }

    private func rebuildExcludedBundleIDs() {
        excludedBundleIDs = Set(allExclusions().map(\.bundleIdentifier))
    }

    /// Re-reads underlying storage and refreshes caches. Call after external writes.
    func refresh() {
        rebuildAbbreviationMap()
        rebuildExcludedBundleIDs()
    }
}

enum SnippetStoreError: LocalizedError {
    case emptyAbbreviation
    case emptyGroupName
    case duplicateAbbreviation(String)

    var errorDescription: String? {
        switch self {
        case .emptyAbbreviation:
            "Abbreviation cannot be empty."
        case .emptyGroupName:
            "Group name cannot be empty."
        case let .duplicateAbbreviation(abbrev):
            "A snippet with abbreviation '\(abbrev)' already exists."
        }
    }
}
