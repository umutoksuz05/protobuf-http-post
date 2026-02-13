import SwiftUI
import UniformTypeIdentifiers

struct ProtoFileListView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDraggingOver = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Proto Files")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                if appState.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
                
                Button(action: refreshProtoFiles) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .help("Refresh Proto Files")
                .disabled(appState.isLoading)
                
                Button(action: addProtoFiles) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .help("Add Proto Files")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            // Error message
            if let error = appState.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.warning)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    Button("Dismiss") {
                        withAnimation(Theme.smooth) {
                            appState.errorMessage = nil
                        }
                    }
                    .font(.caption)
                    .buttonStyle(HoverButtonStyle())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.warning.opacity(0.08))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // File list
            if let workspace = appState.selectedWorkspace {
                if workspace.protoFiles.isEmpty {
                    emptyState
                } else {
                    fileList(workspace.protoFiles)
                }
            } else {
                noWorkspaceState
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .strokeBorder(isDraggingOver ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .animation(Theme.smooth, value: isDraggingOver)
        .animation(Theme.smooth, value: appState.errorMessage != nil)
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(Theme.textTertiary)
            
            Text("No Proto Files")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            
            Text("Drop .proto files here or click + to add")
                .font(.caption)
                .foregroundColor(Theme.textTertiary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
    
    private var noWorkspaceState: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 32))
                .foregroundColor(Theme.textTertiary)
            
            Text("No Workspace Selected")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private func fileList(_ files: [ProtoFile]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(files) { file in
                    ProtoFileRow(file: file) {
                        withAnimation(Theme.snappy) {
                            appState.removeProtoFile(file)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func addProtoFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "proto") ?? .plainText
        ]
        panel.message = "Select .proto files to add to the workspace"
        
        if panel.runModal() == .OK {
            appState.addProtoFiles(urls: panel.urls)
        }
    }
    
    private func refreshProtoFiles() {
        appState.refreshProtoFiles()
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }
                
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.pathExtension.lowercased() == "proto" {
                    urls.append(url)
                }
            }
        }
        
        group.notify(queue: .main) {
            if !urls.isEmpty {
                appState.addProtoFiles(urls: urls)
            }
        }
        
        return true
    }
}

struct ProtoFileRow: View {
    let file: ProtoFile
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            if file.exists {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.success)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.warning)
            }
            
            // File icon
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
            
            // File info
            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                Text(file.directoryPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            // Delete button
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Remove from workspace")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovering ? Theme.surfaceHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Theme.quick) { isHovering = hovering }
        }
        .padding(.horizontal, 6)
    }
}

#Preview {
    ProtoFileListView()
        .environmentObject(AppState())
        .frame(width: 350, height: 300)
}
