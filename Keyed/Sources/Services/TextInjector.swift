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

    /// Sends a string as a single keyboard event whose payload is the Unicode text.
    /// Chunked to avoid hitting the 20-character limit some apps impose per event.
    private func postUnicodeString(_ string: String) {
        let chunkSize = 20
        let utf16 = Array(string.utf16)
        var index = 0
        while index < utf16.count {
            let end = min(index + chunkSize, utf16.count)
            let chunk = Array(utf16[index..<end])
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
            index = end
        }
    }
}
