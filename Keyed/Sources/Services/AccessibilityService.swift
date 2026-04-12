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
    private var pollTimer: Timer?

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
        // The distributed notification above is unreliable on recent macOS (silently dropped
        // in some releases). Re-check trust whenever the user brings Keyed back to the front —
        // that's the most common moment after granting permission in System Settings.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        startPollingIfNeeded()
    }

    /// Backstop for when the distributed notification is not delivered. Polls every 2s while
    /// trust is missing; stops automatically once trust is granted. Refresh is cheap (one TCC
    /// syscall) so the overhead is negligible and the loop runs only in the pre-trust window.
    private func startPollingIfNeeded() {
        guard !isTrusted, pollTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
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
        if trusted {
            stopPolling()
        } else {
            startPollingIfNeeded()
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
