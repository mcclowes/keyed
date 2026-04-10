import AppKit
import Foundation

final class PlaceholderResolver {
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let dateTimeFormatter: DateFormatter

    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateStyle = .long
        dateTimeFormatter.timeStyle = .short
    }

    func resolve(_ text: String) -> String {
        guard containsPlaceholder(text) else { return text }

        var result = text
        let now = Date()

        if result.contains("{datetime}") {
            result = result.replacingOccurrences(of: "{datetime}", with: dateTimeFormatter.string(from: now))
        }
        if result.contains("{date}") {
            result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))
        }
        if result.contains("{time}") {
            result = result.replacingOccurrences(of: "{time}", with: timeFormatter.string(from: now))
        }
        if result.contains("{clipboard}") {
            let clipboardContent = NSPasteboard.general.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{clipboard}", with: clipboardContent)
        }

        return result
    }

    func cursorOffset(in text: String) -> Int? {
        guard let range = text.range(of: "{cursor}") else { return nil }
        let afterCursor = text[range.upperBound...]
        return afterCursor.count
    }

    func stripCursorPlaceholder(_ text: String) -> String {
        text.replacingOccurrences(of: "{cursor}", with: "")
    }

    private func containsPlaceholder(_ text: String) -> Bool {
        text.contains("{")
    }
}
