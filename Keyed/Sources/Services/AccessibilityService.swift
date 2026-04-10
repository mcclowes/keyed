import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mcclowes.keyed", category: "AccessibilityService")

@MainActor
protocol AccessibilityChecking: AnyObject {
    var isTrusted: Bool { get }
    func refresh()
    func requestTrust()
    func openSystemSettings()
}

@MainActor
@Observable
final class AccessibilityService: AccessibilityChecking {
    private(set) var isTrusted: Bool

    init() {
        isTrusted = AXIsProcessTrusted()
        // Service is owned by AppDelegate for the app lifetime — no deregistration needed.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // The system notification can fire fractionally before AXIsProcessTrusted
                // reflects the new state, so give it a beat before refreshing.
                try? await Task.sleep(for: .milliseconds(150))
                self?.refresh()
            }
        }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            logger.info("Accessibility trust changed to \(trusted, privacy: .public)")
            isTrusted = trusted
        }
    }

    func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
