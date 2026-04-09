import SwiftData
import SwiftUI

struct SnippetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Snippet.abbreviation) private var snippets: [Snippet]
    @Query(sort: \SnippetGroup.sortOrder) private var groups: [SnippetGroup]
    @State private var selectedSnippetID: PersistentIdentifier?
    @State private var selectedGroupID: UUID?
    @State private var searchText = ""
    @State private var showingAddSheet = false

    private var filteredSnippets: [Snippet] {
        var result = snippets
        if let groupID = selectedGroupID {
            result = result.filter { $0.groupID == groupID }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.abbreviation.localizedStandardContains(searchText) ||
                $0.label.localizedStandardContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            snippetList
        } detail: {
            if let selectedID = selectedSnippetID,
               let snippet = snippets.first(where: { $0.persistentModelID == selectedID }) {
                SnippetDetailView(snippet: snippet)
            } else {
                ContentUnavailableView("Select a snippet", systemImage: "text.cursor", description: Text("Choose a snippet from the list to view or edit it."))
            }
        }
        .searchable(text: $searchText, prompt: "Search snippets")
        .navigationTitle("Keyed")
        .sheet(isPresented: $showingAddSheet) {
            AddSnippetView(groupID: selectedGroupID)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedGroupID) {
            NavigationLink(value: nil as UUID?) {
                Label("All Snippets", systemImage: "tray.full")
            }

            Section("Groups") {
                ForEach(groups) { group in
                    NavigationLink(value: group.id) {
                        Label(group.name, systemImage: "folder")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 160)
    }

    private var snippetList: some View {
        List(filteredSnippets, selection: $selectedSnippetID) { snippet in
            SnippetRowView(snippet: snippet)
                .tag(snippet.persistentModelID)
        }
        .frame(minWidth: 220)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddSheet = true }) {
                    Label("Add Snippet", systemImage: "plus")
                }
            }
        }
    }
}

struct SnippetRowView: View {
    let snippet: Snippet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snippet.abbreviation)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
            if !snippet.label.isEmpty {
                Text(snippet.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(snippet.expansion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
