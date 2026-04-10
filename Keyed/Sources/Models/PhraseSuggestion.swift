import Foundation
import SwiftData

/// A repeatedly-typed phrase detected by `SuggestionTracker` and persisted so
/// the user can review and promote it to a real snippet. The text is stored
/// locally only — it is never transmitted off-device.
@Model
final class PhraseSuggestion {
    var id = UUID()
    var text: String = ""
    var normalizedText: String = ""
    var count: Int = 0
    var firstSeen = Date.now
    var lastSeen = Date.now
    var isDismissed: Bool = false

    init(text: String, normalizedText: String) {
        id = UUID()
        self.text = text
        self.normalizedText = normalizedText
        count = 1
        firstSeen = .now
        lastSeen = .now
        isDismissed = false
    }
}
