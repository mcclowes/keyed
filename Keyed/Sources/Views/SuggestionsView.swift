import SwiftData
import SwiftUI

struct SuggestionsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(SuggestionStore.self) private var suggestionStore
    @Environment(SnippetStore.self) private var snippetStore
    @Query private var suggestions: [PhraseSuggestion]
    @State private var promotingSuggestion: PhraseSuggestion?
    @State private var errorMessage: String?

    private var visible: [PhraseSuggestion] {
        suggestions
            .filter { !$0.isDismissed && $0.count >= settings.suggestionThreshold }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !settings.smartSuggestionsEnabled {
                ContentUnavailableView {
                    Label("Smart Suggestions Off", systemImage: "wand.and.stars.inverse")
                } description: {
                    Text(
                        "Enable smart suggestions in Settings → Suggestions to start detecting repeatedly-typed phrases."
                    )
                }
            } else if visible.isEmpty {
                ContentUnavailableView {
                    Label("No Suggestions Yet", systemImage: "sparkles")
                } description: {
                    Text(
                        "Keep typing. Phrases you repeat \(settings.suggestionThreshold) or more times will show up here."
                    )
                }
            } else {
                list
            }
        }
        .sheet(item: $promotingSuggestion) { suggestion in
            PromoteSuggestionSheet(suggestion: suggestion) { abbreviation in
                promote(suggestion, abbreviation: abbreviation)
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

    private var list: some View {
        List(visible) { suggestion in
            SuggestionRow(
                suggestion: suggestion,
                onPromote: { promotingSuggestion = suggestion },
                onDismiss: { dismiss(suggestion) }
            )
        }
    }

    private func dismiss(_ suggestion: PhraseSuggestion) {
        do {
            try suggestionStore.dismiss(suggestion)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func promote(_ suggestion: PhraseSuggestion, abbreviation: String) {
        do {
            _ = try snippetStore.addSnippet(
                abbreviation: abbreviation,
                expansion: suggestion.text,
                label: "",
                groupID: nil
            )
            try suggestionStore.delete(suggestion)
            promotingSuggestion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: PhraseSuggestion
    let onPromote: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(suggestion.text)
                .font(.body)
                .lineLimit(3)
            HStack(spacing: 12) {
                Label("\(suggestion.count)×", systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Last seen \(suggestion.lastSeen, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Create snippet", action: onPromote)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PromoteSuggestionSheet: View {
    let suggestion: PhraseSuggestion
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var abbreviation = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Abbreviation") {
                    TextField("e.g. :greet", text: $abbreviation)
                        .font(.system(.body, design: .monospaced))
                }
                Section("Expansion") {
                    Text(suggestion.text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    let trimmed = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onCreate(trimmed)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 320)
    }
}
