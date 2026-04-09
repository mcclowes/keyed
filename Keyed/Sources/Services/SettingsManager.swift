import Foundation
import ServiceManagement

@MainActor
@Observable
final class SettingsManager {
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Register defaults
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.launchAtLogin: false,
            Keys.playSound: false,
        ])

        self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.playSound = defaults.bool(forKey: Keys.playSound)
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail — login item management can fail in debug builds
        }
    }

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let playSound = "playSound"
    }
}
