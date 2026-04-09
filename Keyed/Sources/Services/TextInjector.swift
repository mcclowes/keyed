import AppKit
import Carbon
import Foundation

protocol TextInjecting: Sendable {
    func replaceText(abbreviationLength: Int, expansion: String, cursorOffset: Int?) async
}

extension TextInjecting {
    func replaceText(abbreviationLength: Int, expansion: String) async {
        await replaceText(abbreviationLength: abbreviationLength, expansion: expansion, cursorOffset: nil)
    }
}

final class ClipboardTextInjector: TextInjecting, @unchecked Sendable {
    private let pasteboard = NSPasteboard.general

    func replaceText(abbreviationLength: Int, expansion: String, cursorOffset: Int?) async {
        // Save current clipboard
        let savedItems = savePasteboard()

        // Delete the abbreviation with backspaces
        for _ in 0..<abbreviationLength {
            postKeyEvent(keyCode: UInt16(kVK_Delete), keyDown: true)
            postKeyEvent(keyCode: UInt16(kVK_Delete), keyDown: false)
            try? await Task.sleep(for: .milliseconds(5))
        }

        // Brief pause to let backspaces process
        try? await Task.sleep(for: .milliseconds(20))

        // Set expansion text on clipboard
        pasteboard.clearContents()
        pasteboard.setString(expansion, forType: .string)

        // Paste via Cmd+V
        postKeyEvent(keyCode: UInt16(kVK_ANSI_V), keyDown: true, flags: .maskCommand)
        postKeyEvent(keyCode: UInt16(kVK_ANSI_V), keyDown: false, flags: .maskCommand)

        // Wait for paste to complete
        try? await Task.sleep(for: .milliseconds(100))

        // Move cursor if needed
        if let offset = cursorOffset, offset > 0 {
            try? await Task.sleep(for: .milliseconds(20))
            for _ in 0..<offset {
                postKeyEvent(keyCode: UInt16(kVK_LeftArrow), keyDown: true)
                postKeyEvent(keyCode: UInt16(kVK_LeftArrow), keyDown: false)
                try? await Task.sleep(for: .milliseconds(3))
            }
        }

        // Restore clipboard
        try? await Task.sleep(for: .milliseconds(50))
        restorePasteboard(savedItems)
    }

    private func postKeyEvent(keyCode: UInt16, keyDown: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func savePasteboard() -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.compactMap { item in
            let saved = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    saved.setData(data, forType: type)
                }
            }
            return saved
        } ?? []
    }

    private func restorePasteboard(_ items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if items.isEmpty { return }
        pasteboard.writeObjects(items)
    }
}
