import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var importedSnippets: [ImportedSnippet] = []
    @State private var selectedIndices: Set<Int> = []
    @State private var errorMessage: String?
    @State private var hasLoaded = false

    private let importService = ImportService()

    var body: some View {
        VStack(spacing: 0) {
            if !hasLoaded {
                pickFileView
            } else if importedSnippets.isEmpty {
                noSnippetsView
            } else {
                previewView
            }
        }
        .frame(width: 500, height: 400)
    }

    private var pickFileView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Import Snippets")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Import from CSV or TextExpander (.textexpander) files.")
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Choose File...") { openFilePicker() }
                    .buttonStyle(.borderedProminent)
                Button("Cancel") { dismiss() }
            }
        }
        .padding(40)
    }

    private var noSnippetsView: some View {
        VStack(spacing: 16) {
            Text("No snippets found in the selected file.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Try Another File") {
                    hasLoaded = false
                    errorMessage = nil
                }
                Button("Cancel") { dismiss() }
            }
        }
        .padding(40)
    }

    private var previewView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(importedSnippets.count) snippets found")
                    .font(.headline)
                Spacer()
                Button("Select All") { selectedIndices = Set(importedSnippets.indices) }
                Button("Select None") { selectedIndices = [] }
            }
            .padding()

            List {
                ForEach(Array(importedSnippets.enumerated()), id: \.offset) { index, snippet in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { selectedIndices.contains(index) },
                            set: { isOn in
                                if isOn { selectedIndices.insert(index) }
                                else { selectedIndices.remove(index) }
                            }
                        ))
                        .labelsHidden()

                        VStack(alignment: .leading) {
                            Text(snippet.abbreviation)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                            Text(snippet.expansion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let group = snippet.groupName {
                            Spacer()
                            Text(group)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("\(selectedIndices.count) selected")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button("Import \(selectedIndices.count) Snippets") {
                    importSelected()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIndices.isEmpty)
            }
            .padding()
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "csv")!,
            UTType(filenameExtension: "textexpander") ?? .data,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            if url.pathExtension == "csv" {
                let content = try String(contentsOf: url, encoding: .utf8)
                importedSnippets = try importService.parseCSV(content)
            } else {
                let data = try Data(contentsOf: url)
                importedSnippets = try importService.parseTextExpanderPlist(data)
            }
            selectedIndices = Set(importedSnippets.indices)
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importSelected() {
        // Collect unique group names from selected snippets
        var groupMap: [String: UUID] = [:]

        for index in selectedIndices.sorted() {
            let imported = importedSnippets[index]

            var groupID: UUID?
            if let groupName = imported.groupName, !groupName.isEmpty {
                if let existingID = groupMap[groupName] {
                    groupID = existingID
                } else {
                    let group = SnippetGroup(name: groupName)
                    modelContext.insert(group)
                    groupMap[groupName] = group.id
                    groupID = group.id
                }
            }

            let snippet = Snippet(
                abbreviation: imported.abbreviation,
                expansion: imported.expansion,
                label: imported.label,
                groupID: groupID
            )
            modelContext.insert(snippet)
        }

        try? modelContext.save()
    }
}
