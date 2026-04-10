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
                await self?.awaitTrustChange()
            }
        }
    }

    /// Polls `AXIsProcessTrusted` until it disagrees with the cached value or a short
    /// deadline elapses. Replaces a fixed 150ms sleep that was racy on slower machines.
    /// The poll interval doubles each step (20ms → 40ms → …) capped at ~640ms so the
    /// first change is picked up quickly and no single sleep is load-bearing.
    private func awaitTrustChange(maxTotalMilliseconds: Int = 2000) async {
        var elapsed = 0
        var interval = 20
        while elapsed < maxTotalMilliseconds {
            let current = AXIsProcessTrusted()
            if current != isTrusted {
                refresh()
                return
            }
            try? await Task.sleep(for: .milliseconds(interval))
            elapsed += interval
            interval = min(interval * 2, 640)
        }
        refresh()
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
