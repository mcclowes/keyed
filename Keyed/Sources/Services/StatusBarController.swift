import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyed")
        }

        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Keyed is running", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Keyed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
