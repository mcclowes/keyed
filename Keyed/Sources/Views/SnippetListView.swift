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
    @State private var showingImportSheet = false
    @State private var showingAddGroup = false
    @State private var newGroupName = ""

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
        .sheet(isPresented: $showingImportSheet) {
            ImportView()
        }
        .alert("New Group", isPresented: $showingAddGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Cancel", role: .cancel) { newGroupName = "" }
            Button("Add") {
                guard !newGroupName.isEmpty else { return }
                let maxOrder = groups.map(\.sortOrder).max() ?? -1
                let group = SnippetGroup(name: newGroupName, sortOrder: maxOrder + 1)
                modelContext.insert(group)
                try? modelContext.save()
                newGroupName = ""
            }
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
                    .contextMenu {
                        Button("Rename...") {
                            // Simple rename via alert would need additional state;
                            // for now, editing in-place is deferred to v1.x
                        }
                        Button("Delete Group", role: .destructive) {
                            deleteGroup(group)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        deleteGroup(groups[index])
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 160)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showingAddGroup = true }) {
                    Label("Add Group", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    private var snippetList: some View {
        List(filteredSnippets, selection: $selectedSnippetID) { snippet in
            SnippetRowView(snippet: snippet)
                .tag(snippet.persistentModelID)
                .contextMenu {
                    Button("Duplicate") {
                        duplicateSnippet(snippet)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        deleteSnippet(snippet)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        deleteSnippet(snippet)
                    }
                }
        }
        .frame(minWidth: 220)
        .overlay {
            if filteredSnippets.isEmpty {
                ContentUnavailableView {
                    Label("No Snippets", systemImage: "text.badge.plus")
                } description: {
                    Text("Add a snippet to get started.")
                } actions: {
                    Button("Add Snippet") { showingAddSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddSheet = true }) {
                    Label("Add Snippet", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button(action: { showingImportSheet = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    private func deleteSnippet(_ snippet: Snippet) {
        if snippet.persistentModelID == selectedSnippetID {
            selectedSnippetID = nil
        }
        modelContext.delete(snippet)
        try? modelContext.save()
    }

    private func duplicateSnippet(_ snippet: Snippet) {
        let copy = Snippet(
            abbreviation: snippet.abbreviation + "_copy",
            expansion: snippet.expansion,
            label: snippet.label,
            groupID: snippet.groupID
        )
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func deleteGroup(_ group: SnippetGroup) {
        // Unassign snippets from this group
        let groupID = group.id
        for snippet in snippets where snippet.groupID == groupID {
            snippet.groupID = nil
        }
        if selectedGroupID == groupID {
            selectedGroupID = nil
        }
        modelContext.delete(group)
        try? modelContext.save()
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
