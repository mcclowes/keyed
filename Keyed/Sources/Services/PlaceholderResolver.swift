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

    /// Maximum number of characters pulled from the clipboard by `{clipboard}`.
    /// Clipboard contents above this length are truncated rather than injected wholesale.
    static let clipboardCharacterLimit = 10000

    /// Resolution result used by callers that also need the cursor offset derived from
    /// the *resolved* text (not the template). `cursorOffset` counts graphemes from the
    /// end of `text` back to where the caret should land, or nil if there was no `{cursor}`.
    struct Resolved {
        let text: String
        let cursorOffset: Int?
    }

    func resolve(_ text: String) -> String {
        resolve(text, now: Date()).text
    }

    func resolveWithCursor(_ text: String) -> Resolved {
        resolve(text, now: Date())
    }

    private func resolve(_ text: String, now: Date) -> Resolved {
        guard mayContainPlaceholder(text) else { return Resolved(text: text, cursorOffset: nil) }

        var result = text

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
            var clipboardContent = NSPasteboard.general.string(forType: .string) ?? ""
            if clipboardContent.count > Self.clipboardCharacterLimit {
                clipboardContent = String(clipboardContent.prefix(Self.clipboardCharacterLimit))
            }
            result = result.replacingOccurrences(of: "{clipboard}", with: clipboardContent)
        }

        // Measure the cursor offset AFTER placeholder resolution so that expansions whose
        // pre-cursor text contains {date}/{datetime}/{clipboard} land the caret in the
        // right spot regardless of how long those substitutions turn out to be.
        let cursorOffset: Int?
        if let cursorRange = result.range(of: "{cursor}") {
            let afterCursor = result[cursorRange.upperBound...]
            cursorOffset = afterCursor.count
            result.removeSubrange(cursorRange)
        } else {
            cursorOffset = nil
        }

        return Resolved(text: result, cursorOffset: cursorOffset)
    }

    /// Cheap early-out: if there is no `{` anywhere, no placeholder can possibly match.
    private func mayContainPlaceholder(_ text: String) -> Bool {
        text.contains("{")
    }
}
