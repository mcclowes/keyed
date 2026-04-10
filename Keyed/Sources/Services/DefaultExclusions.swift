import Foundation

/// Apps where text expansion is almost always unwanted or unsafe: password managers
/// (snippets firing into secret fields) and terminals (snippets becoming shell commands).
/// Seeded once on first launch; users can remove any of these from Settings.
enum DefaultExclusions {
    struct Entry {
        let bundleIdentifier: String
        let appName: String
    }

    static let entries: [Entry] = [
        // Password managers
        Entry(bundleIdentifier: "com.1password.1password", appName: "1Password 7"),
        Entry(bundleIdentifier: "com.1password.1password8", appName: "1Password"),
        Entry(bundleIdentifier: "com.agilebits.onepassword4", appName: "1Password"),
        Entry(bundleIdentifier: "com.bitwarden.desktop", appName: "Bitwarden"),
        Entry(bundleIdentifier: "com.dashlane.Dashlane", appName: "Dashlane"),
        Entry(bundleIdentifier: "com.apple.keychainaccess", appName: "Keychain Access"),

        // Terminals — expansion here becomes a shell command
        Entry(bundleIdentifier: "com.apple.Terminal", appName: "Terminal"),
        Entry(bundleIdentifier: "com.googlecode.iterm2", appName: "iTerm"),
        Entry(bundleIdentifier: "dev.warp.Warp-Stable", appName: "Warp"),
        Entry(bundleIdentifier: "com.github.wez.wezterm", appName: "WezTerm"),
        Entry(bundleIdentifier: "net.kovidgoyal.kitty", appName: "kitty"),
        Entry(bundleIdentifier: "io.alacritty", appName: "Alacritty"),
    ]
}
