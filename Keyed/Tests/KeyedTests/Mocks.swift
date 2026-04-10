import Foundation
@testable import Keyed

final class MockKeystrokeMonitor: KeystrokeMonitoring, @unchecked Sendable {
    var onKeystroke: (@Sendable (KeystrokeEvent) -> Void)?
    var startCallCount = 0
    var stopCallCount = 0

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func simulateKeystroke(_ event: KeystrokeEvent) {
        onKeystroke?(event)
    }
}

struct ReplaceTextCall {
    let abbreviationLength: Int
    let expansion: String
    let cursorOffset: Int?
}

final class MockTextInjector: TextInjecting, @unchecked Sendable {
    var replaceTextCalls: [ReplaceTextCall] = []

    func replaceText(abbreviationLength: Int, expansion: String, cursorOffset: Int?) async {
        replaceTextCalls.append(ReplaceTextCall(
            abbreviationLength: abbreviationLength,
            expansion: expansion,
            cursorOffset: cursorOffset
        ))
    }
}

@MainActor
final class MockAccessibilityService: AccessibilityChecking {
    var isTrusted: Bool = true
    var requestTrustCallCount = 0
    var openSystemSettingsCallCount = 0

    func refresh() {}

    func requestTrust() {
        requestTrustCallCount += 1
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}
