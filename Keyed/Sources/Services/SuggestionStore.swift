import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.mcclowes.keyed", category: "SuggestionStore")

@MainActor
protocol SuggestionStoring: AnyObject {
    func recordPhrase(text: String, normalized: String)
    func pendingSuggestions(minCount: Int) -> [PhraseSuggestion]
    func allSuggestions() -> [PhraseSuggestion]
    func dismiss(_ suggestion: PhraseSuggestion) throws
    func delete(_ suggestion: PhraseSuggestion) throws
    func clearAll() throws
}

@MainActor
@Observable
final class SuggestionStore: SuggestionStoring {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func recordPhrase(text: String, normalized: String) {
        let descriptor = FetchDescriptor<PhraseSuggestion>(
            predicate: #Predicate { $0.normalizedText == normalized }
        )
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                if existing.isDismissed { return }
                existing.count += 1
                existing.lastSeen = .now
            } else {
                let suggestion = PhraseSuggestion(text: text, normalizedText: normalized)
                modelContext.insert(suggestion)
            }
            try modelContext.save()
        } catch {
            logger.error("Failed to record phrase: \(error.localizedDescription, privacy: .public)")
        }
    }

    func pendingSuggestions(minCount: Int) -> [PhraseSuggestion] {
        let descriptor = FetchDescriptor<PhraseSuggestion>(
            predicate: #Predicate { !$0.isDismissed && $0.count >= minCount },
            sortBy: [SortDescriptor(\.count, order: .reverse), SortDescriptor(\.lastSeen, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func allSuggestions() -> [PhraseSuggestion] {
        let descriptor = FetchDescriptor<PhraseSuggestion>(
            sortBy: [SortDescriptor(\.count, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func dismiss(_ suggestion: PhraseSuggestion) throws {
        suggestion.isDismissed = true
        try modelContext.save()
    }

    func delete(_ suggestion: PhraseSuggestion) throws {
        modelContext.delete(suggestion)
        try modelContext.save()
    }

    func clearAll() throws {
        for suggestion in allSuggestions() {
            modelContext.delete(suggestion)
        }
        try modelContext.save()
    }
}
