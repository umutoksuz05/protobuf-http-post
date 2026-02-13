import Foundation

struct WorkspaceSettings: Codable, Equatable {
    var baseUrl: String
    var authToken: String
    var basicAuthUsername: String
    var basicAuthPassword: String
    
    init(baseUrl: String = "", authToken: String = "", basicAuthUsername: String = "", basicAuthPassword: String = "") {
        self.baseUrl = baseUrl
        self.authToken = authToken
        self.basicAuthUsername = basicAuthUsername
        self.basicAuthPassword = basicAuthPassword
    }
    
    // Custom Codable for backward compatibility
    enum CodingKeys: String, CodingKey {
        case baseUrl, authToken, basicAuthUsername, basicAuthPassword
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl) ?? ""
        authToken = try container.decodeIfPresent(String.self, forKey: .authToken) ?? ""
        basicAuthUsername = try container.decodeIfPresent(String.self, forKey: .basicAuthUsername) ?? ""
        basicAuthPassword = try container.decodeIfPresent(String.self, forKey: .basicAuthPassword) ?? ""
    }
}

struct Workspace: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var protoFiles: [ProtoFile]
    var savedRequests: [SavedRequest]
    var requestGroups: [RequestGroup]
    var settings: WorkspaceSettings
    var environments: [WorkspaceEnvironment]
    var selectedEnvironmentId: UUID?
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        protoFiles: [ProtoFile] = [],
        savedRequests: [SavedRequest] = [],
        requestGroups: [RequestGroup]? = nil,
        settings: WorkspaceSettings = WorkspaceSettings(),
        environments: [WorkspaceEnvironment]? = nil,
        selectedEnvironmentId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.protoFiles = protoFiles
        self.savedRequests = savedRequests
        self.requestGroups = requestGroups ?? [RequestGroup.defaultGroup()]
        self.settings = settings
        self.environments = environments ?? [WorkspaceEnvironment.defaultEnvironment()]
        self.selectedEnvironmentId = selectedEnvironmentId ?? WorkspaceEnvironment.defaultEnvironmentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Custom Codable for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, name, protoFiles, savedRequests, requestGroups, settings
        case environments, selectedEnvironmentId
        case createdAt, updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        protoFiles = try container.decode([ProtoFile].self, forKey: .protoFiles)
        savedRequests = try container.decodeIfPresent([SavedRequest].self, forKey: .savedRequests) ?? []
        requestGroups = try container.decodeIfPresent([RequestGroup].self, forKey: .requestGroups) ?? [RequestGroup.defaultGroup()]
        settings = try container.decodeIfPresent(WorkspaceSettings.self, forKey: .settings) ?? WorkspaceSettings()
        
        // New fields with defaults for backward compatibility
        environments = try container.decodeIfPresent([WorkspaceEnvironment].self, forKey: .environments) ?? [WorkspaceEnvironment.defaultEnvironment()]
        selectedEnvironmentId = try container.decodeIfPresent(UUID.self, forKey: .selectedEnvironmentId) ?? WorkspaceEnvironment.defaultEnvironmentId
        
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(protoFiles, forKey: .protoFiles)
        try container.encode(savedRequests, forKey: .savedRequests)
        try container.encode(requestGroups, forKey: .requestGroups)
        try container.encode(settings, forKey: .settings)
        try container.encode(environments, forKey: .environments)
        try container.encode(selectedEnvironmentId, forKey: .selectedEnvironmentId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    // Get currently selected environment
    var selectedEnvironment: WorkspaceEnvironment? {
        environments.first { $0.id == selectedEnvironmentId }
    }
    
    // Get all variables from selected environment merged with base settings
    func allVariables() -> [String: String] {
        var vars: [String: String] = [:]
        
        // Add base settings as variables
        if !settings.baseUrl.isEmpty {
            vars["baseUrl"] = settings.baseUrl
            vars["base_url"] = settings.baseUrl
        }
        if !settings.authToken.isEmpty {
            vars["authToken"] = settings.authToken
            vars["auth_token"] = settings.authToken
        }
        if !settings.basicAuthUsername.isEmpty {
            vars["basicAuthUsername"] = settings.basicAuthUsername
            vars["basic_auth_username"] = settings.basicAuthUsername
        }
        if !settings.basicAuthPassword.isEmpty {
            vars["basicAuthPassword"] = settings.basicAuthPassword
            vars["basic_auth_password"] = settings.basicAuthPassword
        }
        
        // Add environment variables (override base settings if same key)
        if let env = selectedEnvironment {
            for (key, value) in env.allVariables() {
                vars[key] = value
            }
        }
        
        return vars
    }
    
    // Migration: ensure all requests are in a group
    mutating func migrateRequestsToGroups() {
        // Ensure default group exists
        if !requestGroups.contains(where: { $0.id == RequestGroup.defaultGroupId }) {
            requestGroups.insert(RequestGroup.defaultGroup(), at: 0)
        }
        
        // Find requests not in any group
        let allGroupedIds = Set(requestGroups.flatMap { $0.requestIds })
        let ungroupedRequests = savedRequests.filter { !allGroupedIds.contains($0.id) }
        
        // Add ungrouped requests to default group
        if !ungroupedRequests.isEmpty {
            if let defaultIndex = requestGroups.firstIndex(where: { $0.id == RequestGroup.defaultGroupId }) {
                requestGroups[defaultIndex].requestIds.append(contentsOf: ungroupedRequests.map { $0.id })
            }
        }
    }
    
    // Migration: ensure default environment exists
    mutating func migrateEnvironments() {
        if environments.isEmpty {
            environments = [WorkspaceEnvironment.defaultEnvironment()]
        }
        if selectedEnvironmentId == nil {
            selectedEnvironmentId = environments.first?.id
        }
        // Ensure selected environment exists
        if !environments.contains(where: { $0.id == selectedEnvironmentId }) {
            selectedEnvironmentId = environments.first?.id
        }
    }
    
    func requestsInGroup(_ group: RequestGroup) -> [SavedRequest] {
        group.requestIds.compactMap { requestId in
            savedRequests.first { $0.id == requestId }
        }
    }
    
    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.id == rhs.id
    }
}
