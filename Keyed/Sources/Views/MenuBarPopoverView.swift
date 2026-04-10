import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(AccessibilityService.self) private var accessibility
    @Environment(SnippetStore.self) private var store

    let onInjectSnippet: (Snippet) -> Void
    let onOpenSystemSettings: () -> Void

    /// Reads the store's cached pinned list directly. The popover is hosted through a
    /// detached `NSHostingController` which does not carry a `ModelContainer` environment
    /// value — `@Query` would silently return an empty result there, so we route through
    /// the `@Observable` store instead.
    private var pinnedSnippets: [Snippet] {
        store.pinnedSnippets
    }

    private var totalSnippetCount: Int {
        store.abbreviationMap.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                Text("Keyed")
                    .fontWeight(.semibold)
                Spacer()
                Toggle("", isOn: Bindable(settings).isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!accessibility.isTrusted)
            }

            if !accessibility.isTrusted {
                permissionBanner
            }

            Divider()

            pinnedSection

            HStack {
                Text("\(totalSnippetCount) snippets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Button("Open Keyed...") {
                openMainWindow()
            }

            Divider()

            Button("Quit Keyed") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Permission required")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            Text("Keyed can't expand text without Accessibility permission.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                onOpenSystemSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var pinnedSection: some View {
        if pinnedSnippets.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pinned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Pin a snippet from the main window for quick access here.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pinned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    ForEach(pinnedSnippets) { snippet in
                        PinnedSnippetButton(snippet: snippet) {
                            onInjectSnippet(snippet)
                        }
                    }
                }
            }
            Divider()
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Keyed" || $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Open settings window as fallback (the main window)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

private struct PinnedSnippetButton: View {
    let snippet: Snippet
    let action: () -> Void

    private var title: String {
        snippet.label.isEmpty ? snippet.abbreviation : snippet.label
    }

    private var subtitle: String {
        snippet.label.isEmpty ? snippet.expansion : snippet.abbreviation
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.caption, design: .default))
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .help("Insert \"\(snippet.abbreviation)\" at cursor")
    }
}
