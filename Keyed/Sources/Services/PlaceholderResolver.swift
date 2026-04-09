import AppKit
import Foundation

struct PlaceholderResolver: Sendable {
    func resolve(_ text: String) -> String {
        var result = text

        // Date/time placeholders
        result = result.replacingOccurrences(of: "{date}", with: formattedDate())
        result = result.replacingOccurrences(of: "{time}", with: formattedTime())
        result = result.replacingOccurrences(of: "{datetime}", with: formattedDateTime())

        // Clipboard
        let clipboardContent = NSPasteboard.general.string(forType: .string) ?? ""
        result = result.replacingOccurrences(of: "{clipboard}", with: clipboardContent)

        return result
    }

    /// Returns the cursor placeholder offset from end, or nil if no cursor placeholder.
    func cursorOffset(in text: String) -> Int? {
        guard let range = text.range(of: "{cursor}") else { return nil }
        let afterCursor = text[range.upperBound...]
        return afterCursor.count
    }

    func stripCursorPlaceholder(_ text: String) -> String {
        text.replacingOccurrences(of: "{cursor}", with: "")
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }

    private func formattedTime() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    private func formattedDateTime() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}
