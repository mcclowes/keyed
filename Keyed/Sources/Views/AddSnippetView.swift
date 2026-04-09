import SwiftUI

struct AddSnippetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var abbreviation = ""
    @State private var expansion = ""
    @State private var label = ""
    @State private var errorMessage: String?
    let groupID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Abbreviation", text: $abbreviation)
                    .font(.system(.body, design: .monospaced))
                TextField("Label (optional)", text: $label)
                TextEditor(text: $expansion)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)

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
                    .disabled(abbreviation.isEmpty || expansion.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }

    private func addSnippet() {
        let snippet = Snippet(abbreviation: abbreviation, expansion: expansion, label: label, groupID: groupID)
        modelContext.insert(snippet)
        dismiss()
    }
}
