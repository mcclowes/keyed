import SwiftUI

struct SnippetDetailView: View {
    let snippet: Snippet
    @Environment(SnippetStore.self) private var store
    @State private var abbreviation: String = ""
    @State private var expansion: String = ""
    @State private var label: String = ""
    @State private var requiresDelimiter: Bool = false
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Trigger") {
                TextField("Abbreviation", text: $abbreviation)
                    .font(.system(.body, design: .monospaced))
                TextField("Label (optional)", text: $label)
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Expansion") {
                TextEditor(text: $expansion)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
            }

            Section("Behavior") {
                Toggle("Expand after delimiter", isOn: $requiresDelimiter)
                    .help(
                        "Wait for a space, punctuation, or return before expanding. Safer for triggers that could appear inside real words."
                    )
            }

            Section("Menu Bar") {
                Toggle("Pin to Menu Bar", isOn: Binding(
                    get: { snippet.isPinned },
                    set: { togglePin(to: $0) }
                ))
                .help("Show this snippet in the menu bar popover for one-click insertion.")
            }

            Section("Stats") {
                LabeledContent("Used") {
                    Text("\(snippet.usageCount) times")
                }
                LabeledContent("Created") {
                    Text(snippet.createdAt, style: .date)
                }
                LabeledContent("Modified") {
                    Text(snippet.updatedAt, style: .date)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadFromSnippet() }
        .onChange(of: snippet.persistentModelID) { _, _ in loadFromSnippet() }
        .onChange(of: abbreviation) { _, _ in scheduleSave() }
        .onChange(of: expansion) { _, _ in scheduleSave() }
        .onChange(of: label) { _, _ in scheduleSave() }
        .onChange(of: requiresDelimiter) { _, _ in scheduleSave() }
    }

    private func loadFromSnippet() {
        abbreviation = snippet.abbreviation
        expansion = snippet.expansion
        label = snippet.label
        requiresDelimiter = snippet.requiresDelimiter
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            persist()
        }
    }

    private func togglePin(to isPinned: Bool) {
        do {
            try store.setPinned(snippet, isPinned: isPinned)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persist() {
        let trimmed = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Abbreviation cannot be empty."
            return
        }
        do {
            try store.updateSnippet(
                snippet,
                abbreviation: trimmed == snippet.abbreviation ? nil : trimmed,
                expansion: expansion == snippet.expansion ? nil : expansion,
                label: label == snippet.label ? nil : label,
                requiresDelimiter: requiresDelimiter == snippet.requiresDelimiter ? nil : requiresDelimiter
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
