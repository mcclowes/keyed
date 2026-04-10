import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mcclowes.keyed", category: "ExpansionEngine")

@MainActor
protocol ExpansionEngineDelegate: AnyObject {
    func expansionEngine(_ engine: ExpansionEngine, didExpand abbreviation: String, to expansion: String)
}

@MainActor
final class ExpansionEngine {
    private var buffer: KeystrokeBuffer
    private let monitor: KeystrokeMonitoring
    private let injector: TextInjecting
    private let placeholderResolver = PlaceholderResolver()

    /// Abbreviations sorted by descending length so the first-matching suffix is always the longest.
    private var sortedAbbreviations: [String] = []
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
        buffer = KeystrokeBuffer(capacity: bufferCapacity)
    }

    func updateAbbreviations(_ map: [String: String]) {
        abbreviationMap = map
        sortedAbbreviations = map.keys.sorted { $0.count > $1.count }
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
        let handler: @Sendable (KeystrokeEvent) -> Void = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeystroke(event)
            }
        }
        monitor.onKeystroke = handler
        monitor.start()
        logger.info("Expansion engine started")
    }

    func stop() {
        monitor.stop()
        monitor.onKeystroke = nil
        buffer.reset()
        logger.info("Expansion engine stopped")
    }

    private func handleKeystroke(_ event: KeystrokeEvent) {
        guard isEnabled, !isExpanding else { return }

        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           excludedBundleIDs.contains(bundleID)
        {
            return
        }

        switch event {
        case let .character(char):
            buffer.append(char)
            checkForMatch()

        case .backspace:
            buffer.backspace()

        case .boundaryKey, .tapReset:
            buffer.reset()

        case .modifiedKey:
            break
        }
    }

    private func checkForMatch() {
        guard let matched = buffer.longestSuffixMatch(in: sortedAbbreviations) else { return }
        guard let expansion = abbreviationMap[matched] else { return }
        guard buffer.hasWordBoundaryBefore(suffixLength: matched.count) else { return }

        let typed = buffer.typedSuffix(length: matched.count)
        let casePattern = CaseTransform.detect(typed: typed, abbreviation: matched)
        let caseExpansion = CaseTransform.apply(casePattern, to: expansion)

        let resolved = placeholderResolver.resolveWithCursor(caseExpansion)

        logger.info("Expanding \(matched.count, privacy: .public) char abbreviation")
        isExpanding = true
        buffer.reset()

        let matchedCharCount = matched.count
        // Disable the tap while we inject so our synthetic events cannot feed back into
        // the buffer, then re-enable it once injection has fully drained. The isExpanding
        // flag is a belt-and-braces guard in case pause/resume races with a late-arriving
        // event that was already in the queue when we disabled the tap.
        monitor.pause()
        Task { [weak self] in
            guard let self else { return }
            await injector.replaceText(
                abbreviationLength: matchedCharCount,
                expansion: resolved.text,
                cursorOffset: resolved.cursorOffset
            )
            await MainActor.run {
                self.monitor.resume()
                self.isExpanding = false
                self.delegate?.expansionEngine(self, didExpand: matched, to: resolved.text)
            }
        }
    }

    /// Injects a snippet's expansion directly at the current cursor position without
    /// requiring a typed abbreviation. Used by the menu bar pinned-snippets feature.
    /// Resolves placeholders and honors `{cursor}` positioning, but does not apply
    /// case transformation (there is no typed input to derive a case from).
    ///
    /// Returns `true` if the snippet was actually injected. The call is a no-op when the
    /// engine is disabled or the frontmost app is on the exclusion list — UI callers can
    /// use the return value to surface an explanation.
    @discardableResult
    func injectSnippet(_ snippet: Snippet) async -> Bool {
        guard isEnabled else {
            logger.info("injectSnippet skipped: engine disabled")
            return false
        }
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           excludedBundleIDs.contains(bundleID)
        {
            logger.info("injectSnippet skipped: frontmost app excluded")
            return false
        }

        let resolved = placeholderResolver.resolveWithCursor(snippet.expansion)

        isExpanding = true
        buffer.reset()
        monitor.pause()
        await injector.replaceText(
            abbreviationLength: 0,
            expansion: resolved.text,
            cursorOffset: resolved.cursorOffset
        )
        monitor.resume()
        isExpanding = false
        delegate?.expansionEngine(self, didExpand: snippet.abbreviation, to: resolved.text)
        return true
    }
}
