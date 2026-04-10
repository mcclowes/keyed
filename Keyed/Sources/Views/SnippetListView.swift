import SwiftData
import SwiftUI

struct SnippetListView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(SnippetStore.self) private var store
    @Query(sort: \Snippet.abbreviation) private var snippets: [Snippet]
    @Query(sort: \SnippetGroup.sortOrder) private var groups: [SnippetGroup]
    @State private var selectedSnippetID: PersistentIdentifier?
    @State private var selectedGroupID: UUID?
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var showingImportSheet = false
    @State private var showingAddGroup = false
    @State private var newGroupName = ""
    @State private var errorMessage: String?

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
        switch settings.snippetSortOrder {
        case .alphabetical:
            result.sort { $0.abbreviation.localizedStandardCompare($1.abbreviation) == .orderedAscending }
        case .mostUsed:
            result.sort { $0.usageCount > $1.usageCount }
        case .recentlyCreated:
            result.sort { $0.createdAt > $1.createdAt }
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
               let snippet = snippets.first(where: { $0.persistentModelID == selectedID })
            {
                SnippetDetailView(snippet: snippet)
            } else {
                ContentUnavailableView(
                    "Select a snippet",
                    systemImage: "text.cursor",
                    description: Text("Choose a snippet from the list to view or edit it.")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search snippets")
        .navigationTitle("Keyed")
        .sheet(isPresented: $showingAddSheet) {
            AddSnippetView(groupID: selectedGroupID)
                .environment(store)
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportView()
                .environment(store)
        }
        .alert("New Group", isPresented: $showingAddGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Cancel", role: .cancel) { newGroupName = "" }
            Button("Add") {
                let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                newGroupName = ""
                guard !trimmed.isEmpty else { return }
                do {
                    _ = try store.addGroup(name: trimmed)
                } catch {
                    errorMessage = error.localizedDescription
                }
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
                Button {
                    showingAddGroup = true
                } label: {
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
        .onKeyPress(.escape) {
            selectedSnippetID = nil
            return .handled
        }
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
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button {
                    showingImportSheet = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            ToolbarItem {
                Menu {
                    Picker("Sort by", selection: Bindable(settings).snippetSortOrder) {
                        ForEach(SnippetSortOrder.allCases, id: \.self) { order in
                            Text(order.label).tag(order)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func deleteSnippet(_ snippet: Snippet) {
        if snippet.persistentModelID == selectedSnippetID {
            selectedSnippetID = nil
        }
        do {
            try store.deleteSnippet(snippet)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func duplicateSnippet(_ snippet: Snippet) {
        do {
            _ = try store.duplicateSnippet(snippet)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteGroup(_ group: SnippetGroup) {
        if selectedGroupID == group.id {
            selectedGroupID = nil
        }
        do {
            try store.deleteGroup(group)
        } catch {
            errorMessage = error.localizedDescription
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
