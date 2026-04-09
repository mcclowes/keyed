import Foundation
@testable import Keyed

final class MockKeystrokeMonitor: KeystrokeMonitoring, @unchecked Sendable {
    var onKeystroke: (@Sendable (KeystrokeEvent) -> Void)?
    var startCallCount = 0
    var stopCallCount = 0

    func start() { startCallCount += 1 }
    func stop() { stopCallCount += 1 }

    func simulateKeystroke(_ event: KeystrokeEvent) {
        onKeystroke?(event)
    }
}

final class MockTextInjector: TextInjecting, @unchecked Sendable {
    var replaceTextCalls: [(abbreviationLength: Int, expansion: String)] = []

    func replaceText(abbreviationLength: Int, expansion: String) async {
        replaceTextCalls.append((abbreviationLength, expansion))
    }
}

final class MockAccessibilityService: AccessibilityChecking, @unchecked Sendable {
    var trusted = true
    var requestTrustCallCount = 0

    func isTrusted() -> Bool { trusted }
    func requestTrust() { requestTrustCallCount += 1 }
}
