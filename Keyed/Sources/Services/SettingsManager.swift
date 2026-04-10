import Foundation
import OSLog
import ServiceManagement

private let logger = Logger(subsystem: "com.mcclowes.keyed", category: "SettingsManager")

@MainActor
protocol SettingsManaging {
    var isEnabled: Bool { get set }
    var launchAtLogin: Bool { get set }
    var playSound: Bool { get set }
    var snippetSortOrder: SnippetSortOrder { get set }
}

@MainActor
@Observable
final class SettingsManager: SettingsManaging {
    private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLoginItem()
        }
    }

    var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Keys.playSound) }
    }

    var snippetSortOrder: SnippetSortOrder {
        didSet { defaults.set(snippetSortOrder.rawValue, forKey: Keys.snippetSortOrder) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Register defaults
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.launchAtLogin: false,
            Keys.playSound: false,
            Keys.snippetSortOrder: SnippetSortOrder.alphabetical.rawValue,
        ])

        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        playSound = defaults.bool(forKey: Keys.playSound)
        snippetSortOrder = SnippetSortOrder(rawValue: defaults.string(forKey: Keys.snippetSortOrder) ?? "") ??
            .alphabetical
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // SMAppService can fail for expected reasons in debug builds (unsigned binary,
            // unregistered login item identifier). Log in all builds so a user's bug report
            // actually contains the reason their launch-at-login toggle silently reverted.
            let action = launchAtLogin ? "register" : "unregister"
            logger.error(
                "SMAppService.\(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let playSound = "playSound"
        static let snippetSortOrder = "snippetSortOrder"
    }
}

enum SnippetSortOrder: String, CaseIterable {
    case alphabetical
    case mostUsed
    case recentlyCreated

    var label: String {
        switch self {
        case .alphabetical: "Alphabetical"
        case .mostUsed: "Most used"
        case .recentlyCreated: "Recently created"
        }
    }
}
