import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        TabView {
            Form {
                Toggle("Enable Keyed", isOn: $settings.isEnabled)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Play sound on expansion", isOn: $settings.playSound)
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gear") }

            SyncSettingsView()
                .tabItem { Label("Sync", systemImage: "icloud") }

            ExclusionSettingsView()
                .tabItem { Label("Excluded Apps", systemImage: "xmark.app") }
        }
        .frame(width: 450, height: 350)
    }
}

private struct SyncSettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @State private var showingRestartNotice = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Sync snippets via iCloud", isOn: Binding(
                    get: { settings.iCloudSyncEnabled },
                    set: { newValue in
                        settings.iCloudSyncEnabled = newValue
                        showingRestartNotice = true
                    }
                ))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keep snippets in sync across your Macs using your private iCloud database.")
                        .font(.caption)
                    Text("Your data stays in Apple's infrastructure — Keyed has no servers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showingRestartNotice {
                Section {
                    Label("Quit and reopen Keyed for this change to take effect.", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}
