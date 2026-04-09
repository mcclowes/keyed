import SwiftData
import SwiftUI

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
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private(set) var expansionEngine: ExpansionEngine?
    private(set) var snippetStore: SnippetStore!
    let settingsManager = SettingsManager()
    let accessibilityService = AccessibilityService()
    let modelContainer: ModelContainer

    override init() {
        do {
            modelContainer = try ModelContainer(for: Snippet.self, SnippetGroup.self, AppExclusion.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        snippetStore = nil
        super.init()
        snippetStore = SnippetStore(modelContext: modelContainer.mainContext)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up status bar
        statusBarController = StatusBarController(settingsManager: settingsManager, modelContainer: modelContainer)

        // Set up expansion engine
        let monitor = CGEventTapMonitor()
        let injector = ClipboardTextInjector()
        let engine = ExpansionEngine(monitor: monitor, injector: injector)
        engine.updateAbbreviations(snippetStore.abbreviationMap)
        engine.delegate = self
        self.expansionEngine = engine

        // Only start if accessibility is trusted
        if accessibilityService.isTrusted() {
            engine.start()
        }

        // Observe settings changes
        observeSettings()

        // Show onboarding on first launch
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        expansionEngine?.stop()
    }

    private func observeSettings() {
        // Poll for settings and snippet changes using a timer
        // (withObservationTracking would be ideal but requires careful setup)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.expansionEngine?.setEnabled(self.settingsManager.isEnabled)
                self.expansionEngine?.updateAbbreviations(self.snippetStore.abbreviationMap)

                // Update excluded apps from SwiftData
                let descriptor = FetchDescriptor<AppExclusion>()
                if let exclusions = try? self.modelContainer.mainContext.fetch(descriptor) {
                    let bundleIDs = Set(exclusions.map(\.bundleIdentifier))
                    self.expansionEngine?.updateExcludedApps(bundleIDs)
                }
            }
        }
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView(accessibilityService: accessibilityService)
            .environment(settingsManager)
            .modelContainer(modelContainer)

        let controller = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Welcome to Keyed"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 400))
        window.center()
        window.makeKeyAndOrderFront(nil)

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}

extension AppDelegate: ExpansionEngineDelegate {
    func expansionEngine(_ engine: ExpansionEngine, didExpand abbreviation: String, to expansion: String) {
        snippetStore.incrementUsageCount(for: abbreviation)
    }
}
