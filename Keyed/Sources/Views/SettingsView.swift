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

            SuggestionsSettingsView()
                .tabItem { Label("Suggestions", systemImage: "wand.and.stars") }

            ExclusionSettingsView()
                .tabItem { Label("Excluded Apps", systemImage: "xmark.app") }
        }
        .frame(width: 450, height: 380)
    }
}

private struct SuggestionsSettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(SuggestionStore.self) private var suggestionStore
    @State private var showingClearConfirmation = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Enable smart suggestions", isOn: $settings.smartSuggestionsEnabled)
            } footer: {
                Text(
                    "Keyed watches for phrases you type repeatedly and offers to turn them into snippets. Detection runs entirely on-device — nothing is ever sent off your Mac. Excluded apps are skipped."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if settings.smartSuggestionsEnabled {
                Section("Threshold") {
                    Stepper(
                        "Suggest after \(settings.suggestionThreshold) repetitions",
                        value: $settings.suggestionThreshold,
                        in: 2...20
                    )
                }

                Section {
                    Button("Clear all collected phrases", role: .destructive) {
                        showingClearConfirmation = true
                    }
                } footer: {
                    Text("Deletes every phrase Keyed has observed so far, including dismissed ones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Clear all collected phrases?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                try? suggestionStore.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
