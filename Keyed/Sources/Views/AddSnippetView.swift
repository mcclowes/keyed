import SwiftData
import SwiftUI

struct AddSnippetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SnippetStore.self) private var store
    @State private var abbreviation = ""
    @State private var expansion = ""
    @State private var label = ""
    @State private var requiresDelimiter = false
    @State private var errorMessage: String?
    let groupID: UUID?

    private var trimmedAbbreviation: String {
        abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        guard !trimmedAbbreviation.isEmpty else { return false }
        let lowered = trimmedAbbreviation.lowercased()
        return store.allSnippets().contains { $0.abbreviation.lowercased() == lowered }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Abbreviation", text: $abbreviation)
                    .font(.system(.body, design: .monospaced))
                if isDuplicate {
                    Text("A snippet with this abbreviation already exists.")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                TextField("Label (optional)", text: $label)
                TextEditor(text: $expansion)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)

                Toggle("Expand after delimiter", isOn: $requiresDelimiter)
                    .help(
                        "Wait for a space, punctuation, or return before expanding. Safer for triggers that could appear inside real words (e.g. \"teh\" inside \"tehran\")."
                    )

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Snippet") { addSnippet() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedAbbreviation.isEmpty || expansion.isEmpty || isDuplicate)
            }
            .padding()
        }
        .frame(width: 400, height: 340)
    }

    private func addSnippet() {
        do {
            _ = try store.addSnippet(
                abbreviation: trimmedAbbreviation,
                expansion: expansion,
                label: label,
                groupID: groupID,
                requiresDelimiter: requiresDelimiter
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
