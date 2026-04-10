import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SnippetStore.self) private var store
    @State private var importedSnippets: [ImportedSnippet] = []
    @State private var selectedIndices: Set<Int> = []
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var importSummary: String?

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
                                if isOn {
                                    selectedIndices.insert(index)
                                } else {
                                    selectedIndices.remove(index)
                                }
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

            if let importSummary {
                Text(importSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
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
            UTType(filenameExtension: "csv") ?? .commaSeparatedText,
            UTType(filenameExtension: "textexpander") ?? .data,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            if url.pathExtension.lowercased() == "csv" {
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
        var groupMap: [String: UUID] = [:]
        var imported = 0
        var skipped = 0

        for group in store.allGroups() {
            groupMap[group.name.lowercased()] = group.id
        }

        for index in selectedIndices.sorted() {
            let item = importedSnippets[index]
            var groupID: UUID?
            if let groupName = item.groupName, !groupName.isEmpty {
                if let existing = groupMap[groupName.lowercased()] {
                    groupID = existing
                } else if let group = try? store.addGroup(name: groupName) {
                    groupMap[groupName.lowercased()] = group.id
                    groupID = group.id
                }
            }
            do {
                _ = try store.addSnippet(
                    abbreviation: item.abbreviation,
                    expansion: item.expansion,
                    label: item.label,
                    groupID: groupID
                )
                imported += 1
            } catch {
                skipped += 1
            }
        }

        if skipped > 0 {
            importSummary = "Imported \(imported), skipped \(skipped) duplicates."
        } else {
            dismiss()
        }
    }
}
