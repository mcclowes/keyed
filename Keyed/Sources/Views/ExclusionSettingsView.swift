import SwiftData
import SwiftUI

struct ExclusionSettingsView: View {
    @Environment(SnippetStore.self) private var store
    @Query(sort: \AppExclusion.appName) private var exclusions: [AppExclusion]
    @State private var showingAppPicker = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if exclusions.isEmpty {
                    Text("No excluded apps. Keyed will expand snippets in all applications.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(exclusions) { exclusion in
                        HStack {
                            Image(nsImage: appIcon(for: exclusion.bundleIdentifier))
                                .resizable()
                                .frame(width: 20, height: 20)
                            VStack(alignment: .leading) {
                                Text(exclusion.appName)
                                Text(exclusion.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                removeExclusion(exclusion)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove exclusion")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Excluded Applications")
                    Spacer()
                    Button("Add App...") { showingAppPicker = true }
                        .buttonStyle(.borderless)
                }
            } footer: {
                Text("Keyed will not expand snippets in excluded applications.")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAppPicker) {
            RunningAppPickerView(existingBundleIDs: Set(exclusions.map(\.bundleIdentifier))) { app in
                addExclusion(bundleID: app.bundleIdentifier, name: app.name)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func addExclusion(bundleID: String, name: String) {
        do {
            _ = try store.addExclusion(bundleIdentifier: bundleID, appName: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeExclusion(_ exclusion: AppExclusion) {
        do {
            try store.removeExclusion(exclusion)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appIcon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

struct RunningAppPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let existingBundleIDs: Set<String>
    let onSelect: (RunningApp) -> Void
    @State private var apps: [RunningApp] = []
    @State private var searchText = ""

    struct RunningApp: Identifiable {
        let id: String
        let name: String
        let bundleIdentifier: String
        let icon: NSImage?

        init(from nsApp: NSRunningApplication) {
            id = nsApp.bundleIdentifier ?? UUID().uuidString
            name = nsApp.localizedName ?? "Unknown"
            bundleIdentifier = nsApp.bundleIdentifier ?? ""
            icon = nsApp.icon
        }
    }

    private var filteredApps: [RunningApp] {
        let filtered = apps.filter { !existingBundleIDs.contains($0.bundleIdentifier) }
        if searchText.isEmpty { return filtered }
        return filtered.filter {
            $0.name.localizedStandardContains(searchText) ||
                $0.bundleIdentifier.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Application to Exclude")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(filteredApps) { app in
                Button {
                    onSelect(app)
                    dismiss()
                } label: {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                        }
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 400, height: 500)
        .onAppear { loadApps() }
    }

    private func loadApps() {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .map { RunningApp(from: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
