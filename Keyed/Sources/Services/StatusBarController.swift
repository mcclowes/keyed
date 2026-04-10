import AppKit
import SwiftData
import SwiftUI

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private weak var expansionEngine: ExpansionEngine?
    private var previouslyActiveApp: NSRunningApplication?

    init(
        settingsManager: SettingsManager,
        snippetStore: SnippetStore,
        expansionEngine: ExpansionEngine?
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        self.expansionEngine = expansionEngine

        popover.contentSize = NSSize(width: 260, height: 320)
        popover.behavior = .transient

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyed")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Weak self used by the SwiftUI closure avoids retain cycles; the controller
        // outlives the popover contents so the closure is safe to call.
        let popoverView = MenuBarPopoverView(onInjectSnippet: { [weak self] snippet in
            self?.inject(snippet)
        })
        .environment(settingsManager)
        .environment(snippetStore)

        popover.contentViewController = NSHostingController(rootView: popoverView)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            previouslyActiveApp = NSWorkspace.shared.frontmostApplication
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func inject(_ snippet: Snippet) {
        let targetApp = previouslyActiveApp
        popover.performClose(nil)

        Task { @MainActor [weak self] in
            // Give the previous app a moment to regain focus after the popover closes.
            targetApp?.activate(options: [])
            try? await Task.sleep(for: .milliseconds(80))
            await self?.expansionEngine?.injectSnippet(snippet)
        }
    }
}
