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

        case .boundaryKey:
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

        let cursorOffset = placeholderResolver.cursorOffset(in: caseExpansion)
        let resolvedExpansion = placeholderResolver.resolve(placeholderResolver.stripCursorPlaceholder(caseExpansion))

        logger.info("Expanding \(matched.count, privacy: .public) char abbreviation")
        isExpanding = true
        buffer.reset()

        let matchedCharCount = matched.count
        Task { [weak self] in
            guard let self else { return }
            await injector.replaceText(
                abbreviationLength: matchedCharCount,
                expansion: resolvedExpansion,
                cursorOffset: cursorOffset
            )
            await MainActor.run {
                self.isExpanding = false
                self.delegate?.expansionEngine(self, didExpand: matched, to: resolvedExpansion)
            }
        }
    }

    /// Injects a snippet's expansion directly at the current cursor position without
    /// requiring a typed abbreviation. Used by the menu bar pinned-snippets feature.
    /// Resolves placeholders and honors `{cursor}` positioning, but does not apply
    /// case transformation (there is no typed input to derive a case from).
    func injectSnippet(_ snippet: Snippet) async {
        let expansion = snippet.expansion
        let cursorOffset = placeholderResolver.cursorOffset(in: expansion)
        let resolved = placeholderResolver.resolve(placeholderResolver.stripCursorPlaceholder(expansion))

        isExpanding = true
        buffer.reset()
        await injector.replaceText(
            abbreviationLength: 0,
            expansion: resolved,
            cursorOffset: cursorOffset
        )
        isExpanding = false
        delegate?.expansionEngine(self, didExpand: snippet.abbreviation, to: resolved)
    }

    #if DEBUG
        func handleKeystrokeForTesting(_ event: KeystrokeEvent) {
            handleKeystroke(event)
        }
    #endif
}
