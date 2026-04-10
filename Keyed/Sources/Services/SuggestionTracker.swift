import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mcclowes.keyed", category: "SuggestionTracker")

/// Detects repeatedly-typed phrases by buffering characters between phrase
/// terminators (`.`, `!`, `?`, newline, or a hard boundary key) and recording
/// each candidate in the store. The store is responsible for persistence and
/// threshold tracking.
///
/// Privacy: everything stays on-device. The tracker never logs phrase content.
@MainActor
final class SuggestionTracker: KeystrokeObserving {
    struct Config {
        var minPhraseLength = 15
        var maxPhraseLength = 300
        var minWordCount = 3
        var maxBufferLength = 500
    }

    private let store: SuggestionStoring
    private let config: Config
    private var buffer: String = ""

    var isEnabled: Bool = true

    init(store: SuggestionStoring, config: Config = Config()) {
        self.store = store
        self.config = config
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    func observe(_ event: KeystrokeEvent) {
        guard isEnabled else { return }

        switch event {
        case let .character(char):
            handleCharacter(char)
        case .backspace:
            if !buffer.isEmpty { buffer.removeLast() }
        case .boundaryKey:
            // Return / Escape / arrow / tab — treat as a phrase break.
            flush()
        case .modifiedKey:
            break
        }
    }

    private func handleCharacter(_ char: String) {
        if SuggestionTracker.isTerminator(char) {
            flush()
            return
        }
        buffer.append(char)
        if buffer.count > config.maxBufferLength {
            // Drop the oldest half of the buffer to stay within bounds.
            buffer.removeFirst(buffer.count - config.maxBufferLength)
        }
    }

    private func flush() {
        defer { buffer.removeAll(keepingCapacity: true) }
        guard let candidate = SuggestionTracker.extractPhrase(from: buffer, config: config) else {
            return
        }
        store.recordPhrase(text: candidate.display, normalized: candidate.normalized)
    }

    // MARK: - Pure helpers (testable without state)

    static func isTerminator(_ char: String) -> Bool {
        char == "." || char == "!" || char == "?" || char == "\n" || char == "\r"
    }

    struct Candidate: Equatable {
        let display: String
        let normalized: String
    }

    static func extractPhrase(from raw: String, config: Config) -> Candidate? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= config.minPhraseLength, trimmed.count <= config.maxPhraseLength else {
            return nil
        }

        let collapsedWhitespace = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard collapsedWhitespace.count >= config.minWordCount else {
            return nil
        }

        let display = collapsedWhitespace.joined(separator: " ")
        let normalized = display.lowercased()

        // Require at least one letter — pure-symbol strings are not worth tracking.
        guard normalized.contains(where: \.isLetter) else {
            return nil
        }

        return Candidate(display: display, normalized: normalized)
    }
}
