import SwiftUI

struct SnippetDetailView: View {
    @Bindable var snippet: Snippet
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Trigger") {
                TextField("Abbreviation", text: $snippet.abbreviation)
                    .font(.system(.body, design: .monospaced))
                TextField("Label (optional)", text: $snippet.label)
            }

            Section("Expansion") {
                TextEditor(text: $snippet.expansion)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
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
        .onChange(of: snippet.abbreviation) { snippet.updatedAt = .now }
        .onChange(of: snippet.expansion) { snippet.updatedAt = .now }
    }
}
