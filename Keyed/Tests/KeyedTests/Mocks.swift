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

final class MockAccessibilityService: AccessibilityChecking, @unchecked Sendable {
    var trusted = true
    var requestTrustCallCount = 0

    func isTrusted() -> Bool {
        trusted
    }

    func requestTrust() {
        requestTrustCallCount += 1
    }
}
