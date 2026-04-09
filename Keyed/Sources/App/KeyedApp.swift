import SwiftData
import SwiftUI

@main
struct KeyedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: Snippet.self, SnippetGroup.self, AppExclusion.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Keyed", id: "main") {
            SnippetListView()
                .environment(appDelegate.settingsManager)
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
                .environment(appDelegate.settingsManager)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var expansionEngine: ExpansionEngine?
    private var snippetStore: SnippetStore?
    let settingsManager = SettingsManager()
    private let accessibilityService = AccessibilityService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let app = NSApp.delegate as? AppDelegate,
              let keyedApp = NSApp as? NSApplication else { return }

        // Get the model container from the app
        guard let container = try? ModelContainer(for: Snippet.self, SnippetGroup.self, AppExclusion.self) else {
            return
        }

        let store = SnippetStore(modelContext: container.mainContext)
        self.snippetStore = store

        // Set up status bar
        statusBarController = StatusBarController(settingsManager: settingsManager, modelContainer: container)

        // Set up expansion engine
        let monitor = CGEventTapMonitor()
        let injector = ClipboardTextInjector()
        let engine = ExpansionEngine(monitor: monitor, injector: injector)
        engine.updateAbbreviations(store.abbreviationMap)
        self.expansionEngine = engine

        // Only start if accessibility is trusted
        if accessibilityService.isTrusted() {
            engine.start()
        }

        // Show onboarding on first launch
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        expansionEngine?.stop()
    }
}
