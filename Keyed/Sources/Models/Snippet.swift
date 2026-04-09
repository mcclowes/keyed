import Foundation
import SwiftData

@Model
final class Snippet {
    var id: UUID
    var abbreviation: String
    var expansion: String
    var label: String
    var groupID: UUID?
    var usageCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        abbreviation: String,
        expansion: String,
        label: String = "",
        groupID: UUID? = nil
    ) {
        id = UUID()
        self.abbreviation = abbreviation
        self.expansion = expansion
        self.label = label
        self.groupID = groupID
        usageCount = 0
        createdAt = .now
        updatedAt = .now
    }
}
