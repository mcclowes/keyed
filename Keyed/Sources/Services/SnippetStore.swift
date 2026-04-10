import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.mcclowes.keyed", category: "SnippetStore")

@MainActor
protocol SnippetStoring: AnyObject {
    var abbreviationMap: [String: String] { get }
    var excludedBundleIDs: Set<String> { get }
    /// Cached list of pinned snippets, sorted by `pinnedSortOrder` then abbreviation.
    /// Participates in `@Observable` tracking so SwiftUI views can read it directly.
    var pinnedSnippets: [Snippet] { get }

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
    func setPinned(_ snippet: Snippet, isPinned: Bool) throws
    func flushPendingWrites()

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
    @discardableResult
    func seedDefaultExclusions(_ entries: [DefaultExclusions.Entry]) -> Int

    /// Starter snippets
    @discardableResult
    func seedDefaultSnippets(_ entries: [DefaultSnippets.Entry]) -> Int
}

@MainActor
@Observable
final class SnippetStore: SnippetStoring {
    private let modelContext: ModelContext
    private(set) var abbreviationMap: [String: String] = [:]
    private(set) var excludedBundleIDs: Set<String> = []
    private(set) var pinnedSnippets: [Snippet] = []
    /// Lowercase-abbreviation → cached snippet reference, used by `incrementUsageCount`
    /// to avoid an O(n) fetch on every expansion.
    private var snippetByLowercaseAbbreviation: [String: Snippet] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        rebuildAbbreviationMap()
        rebuildExcludedBundleIDs()
        rebuildPinnedSnippets()
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
        rebuildPinnedSnippets()
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
        rebuildPinnedSnippets()
    }

    func deleteSnippet(_ snippet: Snippet) throws {
        logger.info("Deleting snippet: \(snippet.abbreviation, privacy: .private)")
        modelContext.delete(snippet)
        try modelContext.save()
        rebuildAbbreviationMap()
        rebuildPinnedSnippets()
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

    func setPinned(_ snippet: Snippet, isPinned: Bool) throws {
        guard snippet.isPinned != isPinned else { return }
        snippet.isPinned = isPinned
        if isPinned {
            let maxOrder = pinnedSnippets.map(\.pinnedSortOrder).max() ?? -1
            snippet.pinnedSortOrder = maxOrder + 1
        }
        snippet.updatedAt = .now
        try modelContext.save()
        rebuildPinnedSnippets()
    }

    func incrementUsageCount(for abbreviation: String) {
        guard let snippet = snippetByLowercaseAbbreviation[abbreviation.lowercased()] else { return }
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
        snippetByLowercaseAbbreviation[abbreviation.lowercased()]
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

    /// Adds the given entries, skipping any bundle ID that already exists.
    /// Returns the number of new exclusions actually inserted.
    @discardableResult
    func seedDefaultExclusions(_ entries: [DefaultExclusions.Entry] = DefaultExclusions.entries) -> Int {
        let existing = Set(allExclusions().map(\.bundleIdentifier))
        var inserted = 0
        for entry in entries where !existing.contains(entry.bundleIdentifier) {
            modelContext.insert(AppExclusion(bundleIdentifier: entry.bundleIdentifier, appName: entry.appName))
            inserted += 1
        }
        guard inserted > 0 else { return 0 }
        do {
            try modelContext.save()
            rebuildExcludedBundleIDs()
            logger.info("Seeded \(inserted, privacy: .public) default exclusions")
        } catch {
            logger.error("Failed to seed default exclusions: \(error.localizedDescription, privacy: .public)")
        }
        return inserted
    }

    // MARK: - Starter snippets

    /// Inserts the given starter snippets, skipping any whose abbreviation already exists
    /// (case-insensitive). Intended for first-launch seeding; callers should also gate on
    /// a "has seeded" flag so users who delete defaults don't see them return.
    /// Returns the number of new snippets actually inserted.
    @discardableResult
    func seedDefaultSnippets(_ entries: [DefaultSnippets.Entry] = DefaultSnippets.entries) -> Int {
        let existing = Set(allSnippets().map { $0.abbreviation.lowercased() })
        var inserted = 0
        for entry in entries where !existing.contains(entry.abbreviation.lowercased()) {
            modelContext.insert(
                Snippet(abbreviation: entry.abbreviation, expansion: entry.expansion, label: entry.label)
            )
            inserted += 1
        }
        guard inserted > 0 else { return 0 }
        do {
            try modelContext.save()
            rebuildAbbreviationMap()
            logger.info("Seeded \(inserted, privacy: .public) default snippets")
        } catch {
            logger.error("Failed to seed default snippets: \(error.localizedDescription, privacy: .public)")
        }
        return inserted
    }

    // MARK: - Caches

    private func rebuildAbbreviationMap() {
        var map: [String: String] = [:]
        var byLowercase: [String: Snippet] = [:]
        for snippet in allSnippets() {
            map[snippet.abbreviation] = snippet.expansion
            byLowercase[snippet.abbreviation.lowercased()] = snippet
        }
        abbreviationMap = map
        snippetByLowercaseAbbreviation = byLowercase
    }

    private func rebuildExcludedBundleIDs() {
        excludedBundleIDs = Set(allExclusions().map(\.bundleIdentifier))
    }

    private func rebuildPinnedSnippets() {
        let descriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.isPinned },
            sortBy: [SortDescriptor(\.pinnedSortOrder), SortDescriptor(\.abbreviation)]
        )
        pinnedSnippets = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Re-reads underlying storage and refreshes caches. Call after external writes.
    func refresh() {
        rebuildAbbreviationMap()
        rebuildExcludedBundleIDs()
        rebuildPinnedSnippets()
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
