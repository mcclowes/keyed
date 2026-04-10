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
    var createdAt: Date
    var updatedAt: Date

    init(
        abbreviation: String,
        expansion: String,
        label: String = "",
        groupID: UUID? = nil,
        isPinned: Bool = false,
        pinnedSortOrder: Int = 0
    ) {
        id = UUID()
        self.abbreviation = abbreviation
        self.expansion = expansion
        self.label = label
        self.groupID = groupID
        usageCount = 0
        self.isPinned = isPinned
        self.pinnedSortOrder = pinnedSortOrder
        createdAt = .now
        updatedAt = .now
    }
}
