import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "com.mcclowes.keyed", category: "App")

@main
struct KeyedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Keyed", id: "main") {
            SnippetListView()
                .environment(appDelegate.settingsManager)
                .environment(appDelegate.snippetStore)
        }
        .modelContainer(appDelegate.modelContainer)

        Settings {
            SettingsView()
                .environment(appDelegate.settingsManager)
                .environment(appDelegate.snippetStore)
                .modelContainer(appDelegate.modelContainer)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var onboardingWindow: NSWindow?
    private(set) var expansionEngine: ExpansionEngine?
    private(set) var snippetStore: SnippetStore!
    let settingsManager = SettingsManager()
    let accessibilityService = AccessibilityService()
    let modelContainer: ModelContainer

    /// Non-nil when the on-disk SwiftData store could not be opened and we fell back to a
    /// transient in-memory store. Surfaced in the UI so the user understands why their
    /// snippets are missing and can choose to quit rather than start editing a ghost store.
    private(set) var persistenceFailure: PersistenceFailure?

    struct PersistenceFailure {
        let underlyingErrorDescription: String
        /// Path the original store was moved to (if the move succeeded). Nil means the
        /// move failed or the original file did not exist.
        let quarantinedPath: String?
    }

    override init() {
        let (container, failure) = Self.makeModelContainer()
        modelContainer = container
        persistenceFailure = failure
        super.init()
        snippetStore = SnippetStore(modelContext: modelContainer.mainContext)
    }

    private static func makeModelContainer() -> (ModelContainer, PersistenceFailure?) {
        do {
            return try (ModelContainer(for: Snippet.self, SnippetGroup.self, AppExclusion.self), nil)
        } catch {
            let errorDescription = error.localizedDescription
            logger.error("ModelContainer creation failed: \(errorDescription, privacy: .public)")

            // Move the existing store aside so the next launch has a clean slate but the user's
            // original data is still recoverable from disk. Only touches the default store location;
            // anything exotic is left alone.
            let quarantinedPath = Self.quarantineDefaultStore()

            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                let fallback = try ModelContainer(
                    for: Snippet.self, SnippetGroup.self, AppExclusion.self,
                    configurations: config
                )
                let failure = PersistenceFailure(
                    underlyingErrorDescription: errorDescription,
                    quarantinedPath: quarantinedPath
                )
                return (fallback, failure)
            } catch {
                fatalError("Could not create any ModelContainer: \(error)")
            }
        }
    }

    /// Attempts to rename the default SwiftData store to a timestamped sibling so it is
    /// not silently overwritten on the next successful launch. Returns the new path on
    /// success, nil if the file was missing or the move failed.
    private static func quarantineDefaultStore() -> String? {
        let fileManager = FileManager.default
        guard let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }
        // SwiftData's default store is named "default.store" in the app's Application Support folder.
        let storeURL = appSupport.appendingPathComponent("default.store")
        guard fileManager.fileExists(atPath: storeURL.path) else { return nil }

        let timestamp = Int(Date().timeIntervalSince1970)
        let quarantinedURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("default.store.corrupt-\(timestamp)")
        do {
            try fileManager.moveItem(at: storeURL, to: quarantinedURL)
            logger.notice("Quarantined unreadable store to \(quarantinedURL.path, privacy: .public)")
            return quarantinedURL.path
        } catch {
            logger.error("Failed to quarantine store: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let failure = persistenceFailure {
            presentPersistenceFailureAlert(failure)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )

        seedDefaultExclusionsIfNeeded()
        seedDefaultSnippetsIfNeeded()

        let monitor = CGEventTapMonitor()
        let injector = UnicodeEventTextInjector()
        let engine = ExpansionEngine(monitor: monitor, injector: injector)
        engine.updateAbbreviations(snippetStore.abbreviationMap)
        engine.updateExcludedApps(snippetStore.excludedBundleIDs)
        engine.delegate = self
        expansionEngine = engine

        statusBarController = StatusBarController(
            settingsManager: settingsManager,
            snippetStore: snippetStore,
            accessibilityService: accessibilityService,
            expansionEngine: engine,
            modelContainer: modelContainer
        )

        if accessibilityService.isTrusted {
            engine.start()
        }

        startObservers()

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding(initialStep: .welcome)
        } else if !accessibilityService.isTrusted {
            showOnboarding(initialStep: .accessibility)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        snippetStore?.flushPendingWrites()
        expansionEngine?.stop()
    }

    @objc private func handleWillResignActive() {
        // Also flush on backgrounding — willTerminate isn't guaranteed to run (crash, force-quit,
        // power loss) and the usage-count batching window is small enough that losing a few counts
        // on resign-active is the worst realistic outcome.
        snippetStore?.flushPendingWrites()
    }

    private func seedDefaultExclusionsIfNeeded() {
        // Don't persist the seed-flag if we're running on the transient in-memory fallback —
        // the next real launch should still seed once the on-disk store is recovered.
        guard persistenceFailure == nil else { return }
        let key = "hasSeededDefaultExclusions"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        snippetStore.seedDefaultExclusions()
        UserDefaults.standard.set(true, forKey: key)
    }

    private func seedDefaultSnippetsIfNeeded() {
        guard persistenceFailure == nil else { return }
        let key = "hasSeededDefaultSnippets"
        // Gate on both the flag and an empty store — handles "user wiped app support but
        // kept preferences" (see review §3) without re-injecting on top of imported content.
        if UserDefaults.standard.bool(forKey: key), !snippetStore.allSnippets().isEmpty {
            return
        }
        if snippetStore.allSnippets().isEmpty {
            snippetStore.seedDefaultSnippets()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Observers

    /// Wires an `@Observable` read to a handler that re-subscribes itself, so changes to
    /// any property touched inside `track` call `onChange` for as long as `self` is alive.
    /// Mirrors the documented `withObservationTracking` pattern but removes four copies of
    /// the same boilerplate.
    private func observeForever(
        track: @escaping @MainActor () -> Void,
        onChange: @escaping @MainActor () -> Void
    ) {
        withObservationTracking {
            track()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                onChange()
                self.observeForever(track: track, onChange: onChange)
            }
        }
    }

    private func startObservers() {
        observeForever(
            track: { [weak self] in _ = self?.settingsManager.isEnabled },
            onChange: { [weak self] in
                guard let self else { return }
                expansionEngine?.setEnabled(settingsManager.isEnabled)
            }
        )
        observeForever(
            track: { [weak self] in _ = self?.snippetStore.abbreviationMap },
            onChange: { [weak self] in
                guard let self else { return }
                expansionEngine?.updateAbbreviations(snippetStore.abbreviationMap)
            }
        )
        observeForever(
            track: { [weak self] in _ = self?.snippetStore.excludedBundleIDs },
            onChange: { [weak self] in
                guard let self else { return }
                expansionEngine?.updateExcludedApps(snippetStore.excludedBundleIDs)
            }
        )
        observeForever(
            track: { [weak self] in _ = self?.accessibilityService.isTrusted },
            onChange: { [weak self] in
                guard let self else { return }
                if accessibilityService.isTrusted {
                    expansionEngine?.start()
                    onboardingWindow?.close()
                } else {
                    expansionEngine?.stop()
                    if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                        showOnboarding(initialStep: .accessibility)
                    }
                }
            }
        )
    }

    private func presentPersistenceFailureAlert(_ failure: PersistenceFailure) {
        let alert = NSAlert()
        alert.messageText = "Keyed couldn't open its snippet library"
        var informativeText = """
        Keyed wasn't able to read your snippet database, so it's running with an empty temporary store. \
        Any changes you make in this session won't persist.

        Details: \(failure.underlyingErrorDescription)
        """
        if let quarantinedPath = failure.quarantinedPath {
            informativeText += "\n\nYour original store has been moved to:\n\(quarantinedPath)"
        }
        alert.informativeText = informativeText
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Continue Anyway")
        alert.addButton(withTitle: "Quit Keyed")
        if alert.runModal() == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private func showOnboarding(initialStep: OnboardingView.OnboardingStep) {
        // If already showing, just bring it to front — don't stack windows.
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView(
            accessibilityService: accessibilityService,
            initialStep: initialStep
        )
        .environment(settingsManager)
        .environment(snippetStore)

        let controller = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: controller)
        window.title = initialStep == .accessibility ? "Keyed — Permission Required" : "Welcome to Keyed"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 400))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}

extension AppDelegate: ExpansionEngineDelegate {
    func expansionEngine(_ engine: ExpansionEngine, didExpand abbreviation: String, to expansion: String) {
        snippetStore.incrementUsageCount(for: abbreviation)
    }
}
