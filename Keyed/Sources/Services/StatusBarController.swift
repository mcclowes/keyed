import AppKit
import SwiftData
import SwiftUI

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let settingsManager: SettingsManager
    private let accessibilityService: AccessibilityService
    private weak var expansionEngine: ExpansionEngine?
    private var previouslyActiveApp: NSRunningApplication?

    init(
        settingsManager: SettingsManager,
        snippetStore: SnippetStore,
        accessibilityService: AccessibilityService,
        expansionEngine: ExpansionEngine?
    ) {
        self.settingsManager = settingsManager
        self.accessibilityService = accessibilityService
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        self.expansionEngine = expansionEngine

        popover.contentSize = NSSize(width: 260, height: 360)
        popover.behavior = .transient

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popoverView = MenuBarPopoverView(onInjectSnippet: { [weak self] snippet in
            self?.inject(snippet)
        }, onOpenSystemSettings: { [weak self] in
            self?.accessibilityService.openSystemSettings()
        })
        .environment(settingsManager)
        .environment(snippetStore)
        .environment(accessibilityService)

        popover.contentViewController = NSHostingController(rootView: popoverView)

        updateIcon()
        observeState()
    }

    private func observeState() {
        withObservationTracking {
            _ = accessibilityService.isTrusted
            _ = settingsManager.isEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateIcon()
                self?.observeState()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        if !accessibilityService.isTrusted {
            button.image = NSImage(
                systemSymbolName: "keyboard.badge.exclamationmark",
                accessibilityDescription: "Keyed — accessibility permission required"
            ) ?? NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Keyed")
            button.appearsDisabled = false
            button.toolTip = "Keyed — accessibility permission required"
        } else if !settingsManager.isEnabled {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyed — disabled")
            button.appearsDisabled = true
            button.toolTip = "Keyed — disabled"
        } else {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyed")
            button.appearsDisabled = false
            button.toolTip = "Keyed"
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            previouslyActiveApp = NSWorkspace.shared.frontmostApplication
            accessibilityService.refresh()
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
