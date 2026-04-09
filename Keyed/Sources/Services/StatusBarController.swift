import AppKit
import SwiftData
import SwiftUI

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private nonisolated(unsafe) var eventMonitor: Any?

    init(settingsManager: SettingsManager, modelContainer: ModelContainer) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()

        let popoverView = MenuBarPopoverView()
            .environment(settingsManager)
            .modelContainer(modelContainer)

        popover.contentSize = NSSize(width: 240, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: popoverView)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyed")
            button.action = #selector(togglePopover)
            button.target = self
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
