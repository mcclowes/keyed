import AppKit
import Foundation

protocol AccessibilityChecking: Sendable {
    func isTrusted() -> Bool
    func requestTrust()
}

struct AccessibilityService: AccessibilityChecking {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
