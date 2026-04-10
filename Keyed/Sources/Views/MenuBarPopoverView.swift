import SwiftData
import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(SettingsManager.self) private var settings
    @Query private var snippets: [Snippet]

    let onInjectSnippet: (Snippet) -> Void

    private var pinnedSnippets: [Snippet] {
        snippets
            .filter(\.isPinned)
            .sorted {
                if $0.pinnedSortOrder != $1.pinnedSortOrder {
                    return $0.pinnedSortOrder < $1.pinnedSortOrder
                }
                return $0.abbreviation.localizedStandardCompare($1.abbreviation) == .orderedAscending
            }
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
            }

            Divider()

            pinnedSection

            HStack {
                Text("\(snippets.count) snippets")
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
