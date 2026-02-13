import SwiftUI
import UniformTypeIdentifiers

struct RequestsCollectionView: View {
    @EnvironmentObject var appState: AppState
    let onOpenRequest: (SavedRequest) -> Void
    
    @State private var searchText: String = ""
    @State private var requestToDelete: SavedRequest?
    @State private var showDeleteConfirmation = false
    @State private var showNewGroupSheet = false
    @State private var newGroupName = ""
    @State private var groupToRename: RequestGroup?
    @State private var groupToDelete: RequestGroup?
    @State private var expandedGroups: Set<UUID> = []
    @State private var draggedRequest: SavedRequest?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Saved Requests")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                Button(action: { showNewGroupSheet = true }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .help("New Group")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textTertiary)
                    .font(.system(size: 11))
                TextField("Search requests...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.textTertiary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.surfaceElevated)
            
            Divider()
            
            // Groups and requests
            if let workspace = appState.selectedWorkspace {
                if workspace.requestGroups.isEmpty && workspace.savedRequests.isEmpty {
                    emptyState
                } else {
                    groupsList(workspace)
                }
            } else {
                noWorkspaceState
            }
        }
        .background(Theme.surface)
        .onAppear {
            if let workspace = appState.selectedWorkspace {
                expandedGroups = Set(workspace.requestGroups.map { $0.id })
            }
        }
        .alert("Delete Request?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { requestToDelete = nil }
            Button("Delete", role: .destructive) {
                if let request = requestToDelete {
                    withAnimation(Theme.snappy) {
                        appState.deleteRequest(request)
                    }
                }
                requestToDelete = nil
            }
        } message: {
            if let request = requestToDelete {
                Text("Are you sure you want to delete \"\(request.name)\"?")
            }
        }
        .alert("Delete Group?", isPresented: Binding(
            get: { groupToDelete != nil },
            set: { if !$0 { groupToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { groupToDelete = nil }
            Button("Delete", role: .destructive) {
                if let group = groupToDelete {
                    withAnimation(Theme.snappy) {
                        appState.deleteGroup(group)
                    }
                }
                groupToDelete = nil
            }
        } message: {
            Text("Requests in this group will be moved to Default.")
        }
        .sheet(isPresented: $showNewGroupSheet) {
            NewGroupSheet(name: $newGroupName) {
                if !newGroupName.trimmingCharacters(in: .whitespaces).isEmpty {
                    withAnimation(Theme.snappy) {
                        appState.createGroup(name: newGroupName.trimmingCharacters(in: .whitespaces))
                    }
                    newGroupName = ""
                }
                showNewGroupSheet = false
            } onCancel: {
                newGroupName = ""
                showNewGroupSheet = false
            }
        }
        .sheet(item: $groupToRename) { group in
            RenameGroupSheet(group: group) { newName in
                appState.renameGroup(group, to: newName)
                groupToRename = nil
            } onCancel: {
                groupToRename = nil
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(Theme.textTertiary)
            Text("No Saved Requests")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Text("Save a request from the HTTP Request tab")
                .font(.caption)
                .foregroundColor(Theme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var noWorkspaceState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No Workspace Selected")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private func groupsList(_ workspace: Workspace) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(workspace.requestGroups) { group in
                    GroupSection(
                        group: group,
                        requests: filteredRequests(in: group, workspace: workspace),
                        isExpanded: expandedGroups.contains(group.id),
                        onToggle: {
                            withAnimation(Theme.snappy) { toggleGroup(group) }
                        },
                        onOpenRequest: onOpenRequest,
                        onDeleteRequest: { request in
                            requestToDelete = request
                            showDeleteConfirmation = true
                        },
                        onRenameGroup: { groupToRename = group },
                        onDeleteGroup: { groupToDelete = group },
                        draggedRequest: $draggedRequest,
                        onDropRequest: { request, index in
                            withAnimation(Theme.snappy) {
                                appState.moveRequest(request, toGroup: group, atIndex: index)
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func filteredRequests(in group: RequestGroup, workspace: Workspace) -> [SavedRequest] {
        let requests = workspace.requestsInGroup(group)
        if searchText.isEmpty {
            return requests
        }
        return requests.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.url.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func toggleGroup(_ group: RequestGroup) {
        if expandedGroups.contains(group.id) {
            expandedGroups.remove(group.id)
        } else {
            expandedGroups.insert(group.id)
        }
    }
}

// MARK: - Group Section

struct GroupSection: View {
    let group: RequestGroup
    let requests: [SavedRequest]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpenRequest: (SavedRequest) -> Void
    let onDeleteRequest: (SavedRequest) -> Void
    let onRenameGroup: () -> Void
    let onDeleteGroup: () -> Void
    @Binding var draggedRequest: SavedRequest?
    let onDropRequest: (SavedRequest, Int?) -> Void
    
    @State private var isTargeted = false
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 12)
                    .rotationEffect(.degrees(isExpanded ? 0 : 0))
                
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                
                Text(group.name)
                    .font(.system(size: 12, weight: .medium))
                
                Text("\(requests.count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Theme.surfaceHover)
                    )
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isTargeted ? Color.accentColor.opacity(0.15) : isHovering ? Theme.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onRenameGroup()
            }
            .onTapGesture(count: 1) {
                onToggle()
            }
            .onHover { h in
                withAnimation(Theme.quick) { isHovering = h }
            }
            .contextMenu {
                Button("Rename") { onRenameGroup() }
                if group.id != RequestGroup.defaultGroupId {
                    Divider()
                    Button("Delete", role: .destructive) { onDeleteGroup() }
                }
            }
            .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
                handleDrop(providers, atIndex: nil)
            }
            
            // Requests in group
            if isExpanded {
                ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
                    RequestRowDraggable(
                        request: request,
                        onOpen: { onOpenRequest(request) },
                        onDelete: { onDeleteRequest(request) },
                        draggedRequest: $draggedRequest,
                        onDropAt: { droppedRequest in
                            onDropRequest(droppedRequest, index)
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, 4)
        .animation(Theme.snappy, value: isExpanded)
    }
    
    private func handleDrop(_ providers: [NSItemProvider], atIndex index: Int?) -> Bool {
        if let request = draggedRequest {
            onDropRequest(request, index)
            return true
        }
        return false
    }
}

// MARK: - Draggable Request Row

struct RequestRowDraggable: View {
    let request: SavedRequest
    let onOpen: () -> Void
    let onDelete: () -> Void
    @Binding var draggedRequest: SavedRequest?
    let onDropAt: (SavedRequest) -> Void
    
    @State private var isHovering = false
    @State private var isTargeted = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(request.method)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textOnAccent)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.methodGradient(request.method))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(request.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                
                Text(request.url.isEmpty ? "No URL" : request.url)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.error)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .padding(.leading, 16)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isTargeted ? Color.accentColor.opacity(0.15) : (isHovering ? Theme.surfaceHover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onHover { h in
            withAnimation(Theme.quick) { isHovering = h }
        }
        .onDrag {
            draggedRequest = request
            return NSItemProvider(object: request.id.uuidString as NSString)
        }
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            if let dragged = draggedRequest, dragged.id != request.id {
                onDropAt(dragged)
                return true
            }
            return false
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - New Group Sheet

struct NewGroupSheet: View {
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("New Group")
                .font(.headline)
            
            TextField("Group Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        onSave()
                    }
                }
            
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create", action: onSave)
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
        .onAppear { isFocused = true }
    }
}

// MARK: - Rename Group Sheet

struct RenameGroupSheet: View {
    let group: RequestGroup
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Group")
                .font(.headline)
            
            TextField("Group Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        onSave(name.trimmingCharacters(in: .whitespaces))
                    }
                }
            
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Rename") {
                    onSave(name.trimmingCharacters(in: .whitespaces))
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
        .onAppear {
            name = group.name
            isFocused = true
        }
    }
}

#Preview {
    RequestsCollectionView(onOpenRequest: { _ in })
        .environmentObject(AppState())
        .frame(width: 300, height: 500)
}
