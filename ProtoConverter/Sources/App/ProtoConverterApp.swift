import SwiftUI
import AppKit

@main
struct ProtoPostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @AppStorage("appAppearance") private var appearance: String = "system"
    
    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 650)
                .preferredColorScheme(colorScheme)
                .onAppear {
                    // Activate the app and bring to front
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    // Make sure the window becomes key
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Workspace") {
                    appState.showNewWorkspaceSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activate the app
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure window is key when app becomes active
        NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var workspaces: [Workspace] = []
    @Published var selectedWorkspace: Workspace?
    @Published var showNewWorkspaceSheet = false
    @Published var showWorkspaceSettings = false
    @Published var messageTypes: [MessageTypeInfo] = []
    @Published var selectedMessageType: MessageTypeInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let workspaceManager = WorkspaceManager()
    private let protoCompiler = ProtoCompilerService()
    
    init() {
        loadWorkspaces()
    }
    
    func loadWorkspaces() {
        workspaces = workspaceManager.loadWorkspaces()
        // Migrate all workspaces to have groups and environments
        for i in workspaces.indices {
            workspaces[i].migrateRequestsToGroups()
            workspaces[i].migrateEnvironments()
            workspaceManager.saveWorkspace(workspaces[i])
        }
        if selectedWorkspace == nil, let first = workspaces.first {
            selectWorkspace(first)
        }
    }
    
    func createWorkspace(name: String) {
        let workspace = workspaceManager.createWorkspace(name: name)
        workspaces.append(workspace)
        selectWorkspace(workspace)
    }
    
    func deleteWorkspace(_ workspace: Workspace) {
        workspaceManager.deleteWorkspace(workspace)
        workspaces.removeAll { $0.id == workspace.id }
        if selectedWorkspace?.id == workspace.id {
            selectedWorkspace = workspaces.first
            if let ws = selectedWorkspace {
                selectWorkspace(ws)
            } else {
                messageTypes = []
            }
        }
    }
    
    func selectWorkspace(_ workspace: Workspace) {
        selectedWorkspace = workspace
        refreshProtoFiles()
    }
    
    func addProtoFiles(urls: [URL]) {
        guard var workspace = selectedWorkspace else { return }
        
        for url in urls {
            if !workspace.protoFiles.contains(where: { $0.path == url.path }) {
                let protoFile = ProtoFile(
                    path: url.path,
                    bookmark: createBookmark(for: url)
                )
                workspace.protoFiles.append(protoFile)
            }
        }
        
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
        refreshProtoFiles()
    }
    
    func removeProtoFile(_ protoFile: ProtoFile) {
        guard var workspace = selectedWorkspace else { return }
        workspace.protoFiles.removeAll { $0.id == protoFile.id }
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
        refreshProtoFiles()
    }
    
    func refreshProtoFiles() {
        guard let workspace = selectedWorkspace else {
            messageTypes = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let types = try await protoCompiler.compileAndExtractTypes(from: workspace.protoFiles)
                await MainActor.run {
                    self.messageTypes = types
                    self.selectedMessageType = types.first
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.messageTypes = []
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Workspace Settings
    
    func updateWorkspaceSettings(_ settings: WorkspaceSettings) {
        guard var workspace = selectedWorkspace else { return }
        workspace.settings = settings
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    // MARK: - Request Groups
    
    func createGroup(name: String) {
        guard var workspace = selectedWorkspace else { return }
        let group = RequestGroup(name: name)
        workspace.requestGroups.append(group)
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    func renameGroup(_ group: RequestGroup, to newName: String) {
        guard var workspace = selectedWorkspace else { return }
        if let index = workspace.requestGroups.firstIndex(where: { $0.id == group.id }) {
            workspace.requestGroups[index].name = newName
            workspace.requestGroups[index].updatedAt = Date()
            workspaceManager.saveWorkspace(workspace)
            updateWorkspace(workspace)
        }
    }
    
    func deleteGroup(_ group: RequestGroup) {
        guard var workspace = selectedWorkspace else { return }
        guard group.id != RequestGroup.defaultGroupId else { return } // Can't delete default group
        
        // Move requests to default group
        if let groupIndex = workspace.requestGroups.firstIndex(where: { $0.id == group.id }) {
            let requestIds = workspace.requestGroups[groupIndex].requestIds
            
            if let defaultIndex = workspace.requestGroups.firstIndex(where: { $0.id == RequestGroup.defaultGroupId }) {
                workspace.requestGroups[defaultIndex].requestIds.append(contentsOf: requestIds)
            }
            
            workspace.requestGroups.remove(at: groupIndex)
            workspaceManager.saveWorkspace(workspace)
            updateWorkspace(workspace)
        }
    }
    
    func moveRequest(_ request: SavedRequest, toGroup targetGroup: RequestGroup, atIndex index: Int? = nil) {
        guard var workspace = selectedWorkspace else { return }
        
        // Remove from current group
        for i in workspace.requestGroups.indices {
            workspace.requestGroups[i].requestIds.removeAll { $0 == request.id }
        }
        
        // Add to target group
        if let targetIndex = workspace.requestGroups.firstIndex(where: { $0.id == targetGroup.id }) {
            if let index = index, index < workspace.requestGroups[targetIndex].requestIds.count {
                workspace.requestGroups[targetIndex].requestIds.insert(request.id, at: index)
            } else {
                workspace.requestGroups[targetIndex].requestIds.append(request.id)
            }
        }
        
        // Update request's groupId
        if let reqIndex = workspace.savedRequests.firstIndex(where: { $0.id == request.id }) {
            workspace.savedRequests[reqIndex].groupId = targetGroup.id
        }
        
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    // MARK: - Saved Requests
    
    func saveRequest(_ request: SavedRequest, inGroup group: RequestGroup) {
        guard var workspace = selectedWorkspace else { return }
        
        var updatedRequest = request
        updatedRequest.groupId = group.id
        
        if let index = workspace.savedRequests.firstIndex(where: { $0.id == request.id }) {
            updatedRequest.updatedAt = Date()
            workspace.savedRequests[index] = updatedRequest
        } else {
            workspace.savedRequests.append(updatedRequest)
            
            // Add to group
            if let groupIndex = workspace.requestGroups.firstIndex(where: { $0.id == group.id }) {
                workspace.requestGroups[groupIndex].requestIds.append(updatedRequest.id)
            }
        }
        
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    func saveRequest(_ request: SavedRequest) {
        guard var workspace = selectedWorkspace else { return }
        
        if let index = workspace.savedRequests.firstIndex(where: { $0.id == request.id }) {
            var updated = request
            updated.updatedAt = Date()
            workspace.savedRequests[index] = updated
        } else {
            workspace.savedRequests.append(request)
            
            // Add to the request's group (or default)
            let groupId = request.groupId
            if let groupIndex = workspace.requestGroups.firstIndex(where: { $0.id == groupId }) {
                if !workspace.requestGroups[groupIndex].requestIds.contains(request.id) {
                    workspace.requestGroups[groupIndex].requestIds.append(request.id)
                }
            } else if let defaultIndex = workspace.requestGroups.firstIndex(where: { $0.id == RequestGroup.defaultGroupId }) {
                workspace.requestGroups[defaultIndex].requestIds.append(request.id)
            }
        }
        
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    func deleteRequest(_ request: SavedRequest) {
        guard var workspace = selectedWorkspace else { return }
        workspace.savedRequests.removeAll { $0.id == request.id }
        
        // Remove from all groups
        for i in workspace.requestGroups.indices {
            workspace.requestGroups[i].requestIds.removeAll { $0 == request.id }
        }
        
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    private func updateWorkspace(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        }
        selectedWorkspace = workspace
    }
    
    private func createBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
    
    // MARK: - Environments
    
    func selectEnvironment(_ environment: WorkspaceEnvironment) {
        guard var workspace = selectedWorkspace else { return }
        workspace.selectedEnvironmentId = environment.id
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    func createEnvironment(name: String) {
        guard var workspace = selectedWorkspace else { return }
        let env = WorkspaceEnvironment(name: name)
        workspace.environments.append(env)
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    func updateEnvironment(_ environment: WorkspaceEnvironment) {
        guard var workspace = selectedWorkspace else { return }
        if let index = workspace.environments.firstIndex(where: { $0.id == environment.id }) {
            var updated = environment
            updated.updatedAt = Date()
            workspace.environments[index] = updated
            workspaceManager.saveWorkspace(workspace)
            updateWorkspace(workspace)
        }
    }
    
    func deleteEnvironment(_ environment: WorkspaceEnvironment) {
        guard var workspace = selectedWorkspace else { return }
        guard environment.id != WorkspaceEnvironment.defaultEnvironmentId else { return } // Can't delete default
        
        workspace.environments.removeAll { $0.id == environment.id }
        
        // If deleted environment was selected, select first available
        if workspace.selectedEnvironmentId == environment.id {
            workspace.selectedEnvironmentId = workspace.environments.first?.id
        }
        
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    // MARK: - Scripting Helpers
    
    func setEnvironmentVariable(key: String, value: String) {
        guard var workspace = selectedWorkspace else { return }
        guard let envId = workspace.selectedEnvironmentId,
              let envIndex = workspace.environments.firstIndex(where: { $0.id == envId }) else { return }
        
        if let varIndex = workspace.environments[envIndex].variables.firstIndex(where: { $0.key == key }) {
            workspace.environments[envIndex].variables[varIndex].value = value
            workspace.environments[envIndex].variables[varIndex].enabled = true
        } else {
            let newVar = EnvironmentVariable(key: key, value: value, enabled: true)
            workspace.environments[envIndex].variables.append(newVar)
        }
        workspace.environments[envIndex].updatedAt = Date()
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    func unsetEnvironmentVariable(key: String) {
        guard var workspace = selectedWorkspace else { return }
        guard let envId = workspace.selectedEnvironmentId,
              let envIndex = workspace.environments.firstIndex(where: { $0.id == envId }) else { return }
        
        workspace.environments[envIndex].variables.removeAll { $0.key == key }
        workspace.environments[envIndex].updatedAt = Date()
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    func updateWorkspaceAuthToken(_ token: String) {
        guard var workspace = selectedWorkspace else { return }
        workspace.settings.authToken = token
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    func updateWorkspaceBaseUrl(_ url: String) {
        guard var workspace = selectedWorkspace else { return }
        workspace.settings.baseUrl = url
        workspaceManager.saveWorkspace(workspace)
        updateWorkspace(workspace)
    }
    
    // MARK: - Import/Export
    
    func exportWorkspace(to url: URL) throws {
        guard let workspace = selectedWorkspace else {
            throw NSError(domain: "AppState", code: 1, userInfo: [NSLocalizedDescriptionKey: "No workspace selected"])
        }
        try workspaceManager.exportWorkspace(workspace, to: url)
    }
    
    func importWorkspace(from url: URL) throws {
        let imported = try workspaceManager.importWorkspace(from: url)
        workspaces.append(imported)
        workspaces.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectWorkspace(imported)
    }
}
