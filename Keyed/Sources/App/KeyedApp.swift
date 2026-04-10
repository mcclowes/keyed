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
                .environment(appDelegate.suggestionStore)
        }
        .modelContainer(appDelegate.modelContainer)

        Settings {
            SettingsView()
                .environment(appDelegate.settingsManager)
                .environment(appDelegate.snippetStore)
                .environment(appDelegate.suggestionStore)
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
    private(set) var suggestionStore: SuggestionStore!
    private(set) var suggestionTracker: SuggestionTracker!
    let settingsManager = SettingsManager()
    let accessibilityService = AccessibilityService()
    let modelContainer: ModelContainer

    override init() {
        do {
            modelContainer = try ModelContainer(
                for: Snippet.self, SnippetGroup.self, AppExclusion.self, PhraseSuggestion.self
            )
        } catch {
            // Fallback: reset the store if schema migration fails. Pre-1.0; no meaningful data loss risk yet.
            logger
                .error(
                    "ModelContainer creation failed: \(error.localizedDescription, privacy: .public) — using in-memory fallback"
                )
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                modelContainer = try ModelContainer(
                    for: Snippet.self, SnippetGroup.self, AppExclusion.self, PhraseSuggestion.self,
                    configurations: config
                )
            } catch {
                fatalError("Could not create any ModelContainer: \(error)")
            }
        }
        super.init()
        snippetStore = SnippetStore(modelContext: modelContainer.mainContext)
        suggestionStore = SuggestionStore(modelContext: modelContainer.mainContext)
        suggestionTracker = SuggestionTracker(store: suggestionStore)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(
            settingsManager: settingsManager,
            snippetStore: snippetStore
        )

        let monitor = CGEventTapMonitor()
        let injector = UnicodeEventTextInjector()
        let engine = ExpansionEngine(monitor: monitor, injector: injector)
        engine.updateAbbreviations(snippetStore.abbreviationMap)
        engine.updateExcludedApps(snippetStore.excludedBundleIDs)
        engine.delegate = self
        engine.keystrokeObserver = suggestionTracker
        expansionEngine = engine

        suggestionTracker.isEnabled = settingsManager.smartSuggestionsEnabled

        if accessibilityService.isTrusted() {
            engine.start()
        }

        observeSettingsLoop()
        observeAbbreviationsLoop()
        observeExclusionsLoop()
        observeSuggestionsSettingLoop()
        observeAccessibilityChanges()

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        snippetStore?.flushPendingWrites()
        expansionEngine?.stop()
    }

    // MARK: - Observers

    private func observeSettingsLoop() {
        withObservationTracking {
            _ = settingsManager.isEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.expansionEngine?.setEnabled(self.settingsManager.isEnabled)
                self.observeSettingsLoop()
            }
        }
    }

    private func observeAbbreviationsLoop() {
        withObservationTracking {
            _ = snippetStore.abbreviationMap
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.expansionEngine?.updateAbbreviations(self.snippetStore.abbreviationMap)
                self.observeAbbreviationsLoop()
            }
        }
    }

    private func observeSuggestionsSettingLoop() {
        withObservationTracking {
            _ = settingsManager.smartSuggestionsEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.suggestionTracker.isEnabled = self.settingsManager.smartSuggestionsEnabled
                if !self.settingsManager.smartSuggestionsEnabled {
                    self.suggestionTracker.reset()
                }
                self.observeSuggestionsSettingLoop()
            }
        }
    }

    private func observeExclusionsLoop() {
        withObservationTracking {
            _ = snippetStore.excludedBundleIDs
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.expansionEngine?.updateExcludedApps(self.snippetStore.excludedBundleIDs)
                self.observeExclusionsLoop()
            }
        }
    }

    private func observeAccessibilityChanges() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.accessibilityService.isTrusted() {
                    self.expansionEngine?.start()
                } else {
                    self.expansionEngine?.stop()
                }
            }
        }
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView(accessibilityService: accessibilityService)
            .environment(settingsManager)
            .environment(snippetStore)

        let controller = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Welcome to Keyed"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 400))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}

extension AppDelegate: ExpansionEngineDelegate {
    func expansionEngine(_ engine: ExpansionEngine, didExpand abbreviation: String, to expansion: String) {
        snippetStore.incrementUsageCount(for: abbreviation)
    }
}
