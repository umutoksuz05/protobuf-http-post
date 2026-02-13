import Foundation

class WorkspaceManager {
    private let fileManager = FileManager.default
    
    private var workspacesDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ProtoPost", isDirectory: true)
        let workspacesDir = appDir.appendingPathComponent("Workspaces", isDirectory: true)
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
        
        // Migration: copy from old ProtoConverter directory if it exists
        let oldAppDir = appSupport.appendingPathComponent("ProtoConverter", isDirectory: true)
        let oldWorkspacesDir = oldAppDir.appendingPathComponent("Workspaces", isDirectory: true)
        if fileManager.fileExists(atPath: oldWorkspacesDir.path) {
            try? migrateFromOldDirectory(oldWorkspacesDir, to: workspacesDir)
        }
        
        return workspacesDir
    }
    
    private func migrateFromOldDirectory(_ oldDir: URL, to newDir: URL) throws {
        let files = try fileManager.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil)
        for file in files {
            let newPath = newDir.appendingPathComponent(file.lastPathComponent)
            if !fileManager.fileExists(atPath: newPath.path) {
                try fileManager.copyItem(at: file, to: newPath)
            }
        }
    }
    
    func loadWorkspaces() -> [Workspace] {
        do {
            let files = try fileManager.contentsOfDirectory(at: workspacesDirectory, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }
            
            var workspaces: [Workspace] = []
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            for file in jsonFiles {
                if let data = try? Data(contentsOf: file),
                   let workspace = try? decoder.decode(Workspace.self, from: data) {
                    workspaces.append(workspace)
                }
            }
            
            // Sort by name
            workspaces.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            // Create default workspace if none exist
            if workspaces.isEmpty {
                let defaultWorkspace = createWorkspace(name: "Default")
                workspaces.append(defaultWorkspace)
            }
            
            return workspaces
        } catch {
            print("Error loading workspaces: \(error)")
            // Return a default workspace on error
            let defaultWorkspace = createWorkspace(name: "Default")
            return [defaultWorkspace]
        }
    }
    
    func createWorkspace(name: String) -> Workspace {
        let workspace = Workspace(name: name)
        saveWorkspace(workspace)
        return workspace
    }
    
    func saveWorkspace(_ workspace: Workspace) {
        var updatedWorkspace = workspace
        updatedWorkspace.updatedAt = Date()
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(updatedWorkspace)
            let fileURL = workspacesDirectory.appendingPathComponent("\(workspace.id.uuidString).json")
            try data.write(to: fileURL)
        } catch {
            print("Error saving workspace: \(error)")
        }
    }
    
    func deleteWorkspace(_ workspace: Workspace) {
        let fileURL = workspacesDirectory.appendingPathComponent("\(workspace.id.uuidString).json")
        try? fileManager.removeItem(at: fileURL)
    }
    
    func renameWorkspace(_ workspace: Workspace, to newName: String) -> Workspace {
        var updated = workspace
        updated.name = newName
        saveWorkspace(updated)
        return updated
    }
    
    // MARK: - Import/Export
    
    /// Export workspace to a JSON file at the specified URL
    func exportWorkspace(_ workspace: Workspace, to url: URL) throws {
        let exportData = WorkspaceExport(workspace: workspace)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(exportData)
        try data.write(to: url)
    }
    
    /// Import workspace from a JSON file at the specified URL
    func importWorkspace(from url: URL) throws -> Workspace {
        let data = try Data(contentsOf: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let exportData = try decoder.decode(WorkspaceExport.self, from: data)
        
        // Create a new workspace with a new ID to avoid conflicts
        var importedWorkspace = exportData.workspace
        importedWorkspace = Workspace(
            id: UUID(), // New ID
            name: importedWorkspace.name + " (Imported)",
            protoFiles: [], // Proto files need to be re-added manually (paths are machine-specific)
            savedRequests: importedWorkspace.savedRequests,
            requestGroups: importedWorkspace.requestGroups,
            settings: importedWorkspace.settings,
            environments: importedWorkspace.environments,
            selectedEnvironmentId: importedWorkspace.selectedEnvironmentId,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Ensure migrations are applied
        importedWorkspace.migrateRequestsToGroups()
        importedWorkspace.migrateEnvironments()
        
        // Save the imported workspace
        saveWorkspace(importedWorkspace)
        
        return importedWorkspace
    }
    
    /// Get export data as JSON string (for clipboard)
    func exportWorkspaceToString(_ workspace: Workspace) throws -> String {
        let exportData = WorkspaceExport(workspace: workspace)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(exportData)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "WorkspaceManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode workspace"])
        }
        return string
    }
}

// MARK: - Export Model

struct WorkspaceExport: Codable {
    let version: Int
    let exportedAt: Date
    let workspace: Workspace
    
    init(workspace: Workspace) {
        self.version = 1
        self.exportedAt = Date()
        self.workspace = workspace
    }
}
