import AppKit
import Foundation

@MainActor
protocol ExpansionEngineDelegate: AnyObject {
    func expansionEngine(_ engine: ExpansionEngine, didExpand abbreviation: String, to expansion: String)
}

@MainActor
final class ExpansionEngine: @unchecked Sendable {
    private var buffer: KeystrokeBuffer
    private let monitor: KeystrokeMonitoring
    private let injector: TextInjecting
    private var abbreviationMap: [String: String] = [:]
    private var excludedBundleIDs: Set<String> = []
    private var isExpanding = false
    private(set) var isEnabled = true

    weak var delegate: ExpansionEngineDelegate?

    init(
        monitor: KeystrokeMonitoring,
        injector: TextInjecting,
        bufferCapacity: Int = 128
    ) {
        self.monitor = monitor
        self.injector = injector
        self.buffer = KeystrokeBuffer(capacity: bufferCapacity)
    }

    func updateAbbreviations(_ map: [String: String]) {
        abbreviationMap = map
    }

    func updateExcludedApps(_ bundleIDs: Set<String>) {
        excludedBundleIDs = bundleIDs
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            buffer.reset()
        }
    }

    func start() {
        monitor.onKeystroke = { [weak self] event in
            Task { @MainActor in
                self?.handleKeystroke(event)
            }
        }
        monitor.start()
    }

    func stop() {
        monitor.stop()
        monitor.onKeystroke = nil
        buffer.reset()
    }

    private func handleKeystroke(_ event: KeystrokeEvent) {
        guard isEnabled, !isExpanding else { return }

        // Check if frontmost app is excluded
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           excludedBundleIDs.contains(bundleID) {
            return
        }

        switch event {
        case .character(let char):
            buffer.append(char)
            checkForMatch()

        case .backspace:
            buffer.backspace()

        case .boundaryKey:
            buffer.reset()

        case .modifiedKey:
            break
        }
    }

    private func checkForMatch() {
        let abbreviations = Set(abbreviationMap.keys)
        guard let matched = buffer.firstMatch(from: abbreviations),
              let expansion = abbreviationMap[matched] else {
            return
        }

        isExpanding = true
        buffer.reset()

        Task {
            await injector.replaceText(abbreviationLength: matched.count, expansion: expansion)
            await MainActor.run {
                self.isExpanding = false
                self.delegate?.expansionEngine(self, didExpand: matched, to: expansion)
            }
        }
    }

    // MARK: - Testing support

    func handleKeystrokeForTesting(_ event: KeystrokeEvent) {
        handleKeystroke(event)
    }
}
