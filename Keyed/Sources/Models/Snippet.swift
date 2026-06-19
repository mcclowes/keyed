import Foundation
import SwiftData

@Model
final class Snippet {
    var id: UUID
    @Attribute(.unique) var abbreviation: String
    var expansion: String
    var label: String
    var groupID: UUID?
    var usageCount: Int
    var isPinned: Bool = false
    var pinnedSortOrder: Int = 0
    /// When true, the abbreviation only expands once the user types a delimiter
    /// (space, punctuation, return). When false, expansion fires immediately on
    /// match. Delimiter-triggered snippets are safer for triggers that are
    /// prefixes of real words (e.g. `teh` → `the` won't fire inside `tehran`).
    var requiresDelimiter: Bool = false
    var createdAt: Date
    var updatedAt: Date

    init(
        abbreviation: String,
        expansion: String,
        label: String = "",
        groupID: UUID? = nil,
        isPinned: Bool = false,
        pinnedSortOrder: Int = 0,
        requiresDelimiter: Bool = false
    ) {
        id = UUID()
        self.abbreviation = abbreviation
        self.expansion = expansion
        self.label = label
        self.groupID = groupID
        usageCount = 0
        self.isPinned = isPinned
        self.pinnedSortOrder = pinnedSortOrder
        self.requiresDelimiter = requiresDelimiter
        createdAt = .now
        updatedAt = .now
    }
}
