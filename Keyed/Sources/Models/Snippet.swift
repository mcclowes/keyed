import Foundation
import SwiftData

/// All non-optional properties carry inline defaults and no `@Attribute(.unique)`
/// so the model is compatible with SwiftData + CloudKit sync. Uniqueness of
/// abbreviations is enforced at the store layer (case-insensitive) instead.
@Model
final class Snippet {
    var id = UUID()
    var abbreviation: String = ""
    var expansion: String = ""
    var label: String = ""
    var groupID: UUID?
    var usageCount: Int = 0
    var createdAt = Date.now
    var updatedAt = Date.now

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
