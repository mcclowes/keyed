import SwiftData
import SwiftUI

struct AddSnippetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingSnippets: [Snippet]
    @State private var abbreviation = ""
    @State private var expansion = ""
    @State private var label = ""
    @State private var errorMessage: String?
    @State private var showingDuplicateAlert = false
    @State private var existingSnippet: Snippet?
    let groupID: UUID?

    private var isDuplicate: Bool {
        existingSnippets.contains { $0.abbreviation.lowercased() == abbreviation.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Abbreviation", text: $abbreviation)
                    .font(.system(.body, design: .monospaced))
                if isDuplicate, !abbreviation.isEmpty {
                    Text("A snippet with this abbreviation already exists.")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
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
        .alert("Duplicate Abbreviation", isPresented: $showingDuplicateAlert) {
            Button("Replace") { replaceExisting() }
            Button("Keep Both") { addWithSuffix() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A snippet with abbreviation '\(abbreviation)' already exists. What would you like to do?")
        }
    }

    private func addSnippet() {
        if let existing = existingSnippets.first(where: { $0.abbreviation.lowercased() == abbreviation.lowercased() }) {
            existingSnippet = existing
            showingDuplicateAlert = true
            return
        }
        let snippet = Snippet(abbreviation: abbreviation, expansion: expansion, label: label, groupID: groupID)
        modelContext.insert(snippet)
        try? modelContext.save()
        dismiss()
    }

    private func replaceExisting() {
        if let existing = existingSnippet {
            existing.expansion = expansion
            existing.label = label.isEmpty ? existing.label : label
            existing.updatedAt = .now
            try? modelContext.save()
        }
        dismiss()
    }

    private func addWithSuffix() {
        let snippet = Snippet(abbreviation: abbreviation + "2", expansion: expansion, label: label, groupID: groupID)
        modelContext.insert(snippet)
        try? modelContext.save()
        dismiss()
    }
}
