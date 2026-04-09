import Foundation
import SwiftData

@Model
final class SnippetGroup {
    var id: UUID
    var name: String
    var sortOrder: Int

    init(name: String, sortOrder: Int = 0) {
        id = UUID()
        self.name = name
        self.sortOrder = sortOrder
    }
}
