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
        }
        .frame(width: 400, height: 200)
    }
}
