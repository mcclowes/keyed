import AppKit
import Carbon
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mcclowes.keyed", category: "TextInjector")

protocol TextInjecting: Sendable {
    func replaceText(abbreviationLength: Int, expansion: String, cursorOffset: Int?) async
}

extension TextInjecting {
    func replaceText(abbreviationLength: Int, expansion: String) async {
        await replaceText(abbreviationLength: abbreviationLength, expansion: expansion, cursorOffset: nil)
    }
}

/// Inserts expansion text by deleting the abbreviation with backspaces then posting a
/// synthetic key event that carries the expansion as a Unicode string payload.
/// This avoids the clipboard entirely — no save/restore dance, no collisions with clipboard managers.
final class UnicodeEventTextInjector: TextInjecting, @unchecked Sendable {
    func replaceText(abbreviationLength: Int, expansion: String, cursorOffset: Int?) async {
        guard abbreviationLength >= 0 else { return }

        for _ in 0..<abbreviationLength {
            postKey(keyCode: UInt16(kVK_Delete))
        }

        if !expansion.isEmpty {
            postUnicodeString(expansion)
        }

        if let offset = cursorOffset, offset > 0 {
            for _ in 0..<offset {
                postKey(keyCode: UInt16(kVK_LeftArrow))
            }
        }
    }

    private func postKey(keyCode: UInt16, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            logger.error("Failed to allocate CGEvent for keyCode \(keyCode)")
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postUnicodeString(_ string: String) {
        for chunk in Self.chunkUTF16(string, maxUTF16PerEvent: Self.maxUTF16PerEvent) {
            postUTF16Chunk(chunk)
        }
    }

    /// Maximum UTF-16 code units allowed per synthetic event. Some apps impose this cap.
    static let maxUTF16PerEvent = 20

    /// Splits `string` into UTF-16 chunks whose boundaries land on grapheme clusters so that
    /// surrogate pairs, combining marks, and ZWJ sequences are never broken mid-character.
    /// A single grapheme that is itself longer than `maxUTF16PerEvent` (rare — some ZWJ emoji
    /// sequences) is emitted whole in its own chunk rather than split.
    static func chunkUTF16(_ string: String, maxUTF16PerEvent: Int) -> [[UniChar]] {
        guard maxUTF16PerEvent > 0 else { return [] }
        var chunks: [[UniChar]] = []
        var pending: [UniChar] = []
        pending.reserveCapacity(maxUTF16PerEvent)

        for character in string {
            let clusterUTF16 = Array(String(character).utf16)

            if !pending.isEmpty, pending.count + clusterUTF16.count > maxUTF16PerEvent {
                chunks.append(pending)
                pending.removeAll(keepingCapacity: true)
            }

            if clusterUTF16.count > maxUTF16PerEvent {
                chunks.append(clusterUTF16)
                continue
            }

            pending.append(contentsOf: clusterUTF16)
        }

        if !pending.isEmpty {
            chunks.append(pending)
        }
        return chunks
    }

    private func postUTF16Chunk(_ chunk: [UniChar]) {
        guard !chunk.isEmpty else { return }
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
            logger.error("Failed to allocate CGEvent for unicode string chunk")
            return
        }
        chunk.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        event.post(tap: .cghidEventTap)
    }
}
