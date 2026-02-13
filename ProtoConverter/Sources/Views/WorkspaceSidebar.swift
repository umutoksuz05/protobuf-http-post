import SwiftUI

struct WorkspaceSidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var editingWorkspace: Workspace?
    @State private var editedName: String = ""
    @State private var showDeleteConfirmation = false
    @State private var workspaceToDelete: Workspace?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Workspaces")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                Button(action: { appState.showNewWorkspaceSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .help("New Workspace")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            // Workspace list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.workspaces) { workspace in
                        WorkspaceRow(
                            workspace: workspace,
                            isSelected: appState.selectedWorkspace?.id == workspace.id,
                            isEditing: editingWorkspace?.id == workspace.id,
                            editedName: $editedName,
                            onSelect: {
                                withAnimation(Theme.snappy) {
                                    appState.selectWorkspace(workspace)
                                }
                            },
                            onStartEditing: {
                                editingWorkspace = workspace
                                editedName = workspace.name
                            },
                            onFinishEditing: {
                                if !editedName.isEmpty && editedName != workspace.name {
                                    if let index = appState.workspaces.firstIndex(where: { $0.id == workspace.id }) {
                                        var updated = workspace
                                        updated.name = editedName
                                        WorkspaceManager().saveWorkspace(updated)
                                        appState.workspaces[index] = updated
                                        if appState.selectedWorkspace?.id == workspace.id {
                                            appState.selectedWorkspace = updated
                                        }
                                    }
                                }
                                editingWorkspace = nil
                            },
                            onDelete: {
                                workspaceToDelete = workspace
                                showDeleteConfirmation = true
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 180)
        .background(Theme.surface)
        .sheet(isPresented: $appState.showNewWorkspaceSheet) {
            NewWorkspaceSheet()
        }
        .alert("Delete Workspace?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                workspaceToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let workspace = workspaceToDelete {
                    withAnimation(Theme.snappy) {
                        appState.deleteWorkspace(workspace)
                    }
                }
                workspaceToDelete = nil
            }
        } message: {
            if let workspace = workspaceToDelete {
                Text("Are you sure you want to delete \"\(workspace.name)\"? This cannot be undone.")
            }
        }
    }
}

struct WorkspaceRow: View {
    let workspace: Workspace
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editedName: String
    let onSelect: () -> Void
    let onStartEditing: () -> Void
    let onFinishEditing: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .font(.system(size: 13))
                .foregroundColor(isSelected ? Theme.textOnAccent : .accentColor)
                .symbolRenderingMode(.hierarchical)
            
            if isEditing {
                TextField("Name", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        onFinishEditing()
                    }
                    .onAppear {
                        isTextFieldFocused = true
                    }
            } else {
                Text(workspace.name)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? Theme.textOnAccent : Theme.textPrimary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isHovering && !isEditing {
                Menu {
                    Button("Rename") {
                        onStartEditing()
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? Theme.textOnAccent.opacity(0.8) : Theme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor : (isHovering ? Theme.surfaceHover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                onSelect()
            }
        }
        .onHover { hovering in
            withAnimation(Theme.quick) { isHovering = hovering }
        }
        .padding(.horizontal, 6)
        .animation(Theme.smooth, value: isSelected)
    }
}

struct NewWorkspaceSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var name: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New Workspace")
                .font(.headline)
            
            TextField("Workspace Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onSubmit {
                    createWorkspace()
                }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Create") {
                    createWorkspace()
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            isTextFieldFocused = true
        }
    }
    
    private func createWorkspace() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        appState.createWorkspace(name: trimmedName)
        dismiss()
    }
}

#Preview {
    WorkspaceSidebar()
        .environmentObject(AppState())
        .frame(width: 200, height: 400)
}
