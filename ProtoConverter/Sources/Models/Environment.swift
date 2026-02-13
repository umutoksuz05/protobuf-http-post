import Foundation

struct EnvironmentVariable: Identifiable, Codable, Equatable {
    let id: UUID
    var key: String
    var value: String
    var enabled: Bool
    
    init(id: UUID = UUID(), key: String, value: String, enabled: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.enabled = enabled
    }
}

/// Renamed to avoid conflict with SwiftUI's @Environment
struct WorkspaceEnvironment: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var variables: [EnvironmentVariable]
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        variables: [EnvironmentVariable] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.variables = variables
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Get variable value by key
    func getValue(for key: String) -> String? {
        variables.first { $0.key == key && $0.enabled }?.value
    }
    
    /// Build a dictionary of all enabled variables
    func allVariables() -> [String: String] {
        var result: [String: String] = [:]
        for variable in variables where variable.enabled {
            result[variable.key] = variable.value
        }
        return result
    }
    
    static let defaultEnvironmentId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    
    static func defaultEnvironment() -> WorkspaceEnvironment {
        WorkspaceEnvironment(
            id: defaultEnvironmentId,
            name: "Default",
            variables: []
        )
    }
    
    static func == (lhs: WorkspaceEnvironment, rhs: WorkspaceEnvironment) -> Bool {
        lhs.id == rhs.id
    }
}
