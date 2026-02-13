import Foundation

/// Holds the runtime state for a request tab (not persisted to disk)
class RequestTabState: ObservableObject, Identifiable {
    let id: UUID
    
    // Request configuration
    @Published var url: String = ""
    @Published var method: String = "POST"
    @Published var headers: [TabHeader] = [TabHeader(key: "Content-Type", value: "application/json", enabled: true)]
    @Published var requestBody: String = ""
    @Published var requestFormat: String = "json"
    @Published var responseFormat: String = "json"
    @Published var selectedRequestTypeName: String?
    @Published var selectedResponseTypeName: String?
    
    // Authorization
    @Published var authType: String = "none"       // "none", "bearer", "basic"
    @Published var authBearerToken: String = ""
    @Published var authBasicUsername: String = ""
    @Published var authBasicPassword: String = ""
    
    // Scripts
    @Published var preRequestScript: String = ""
    @Published var postResponseScript: String = ""
    @Published var scriptConsoleOutput: String = ""
    
    // Response data
    @Published var responseBody: String = ""
    @Published var responseStatus: String = ""
    @Published var responseHeaders: String = ""
    @Published var responseTime: TimeInterval? = nil  // Response time in seconds
    
    // State tracking
    @Published var hasUnsavedChanges: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // Associated saved request (if any)
    @Published var savedRequest: SavedRequest?
    
    // Internal flag to prevent sync loops
    var isSyncingAuth = false
    
    var title: String {
        if hasUnsavedChanges {
            return (savedRequest?.name ?? "New Request") + " *"
        }
        return savedRequest?.name ?? "New Request"
    }
    
    var displayTitle: String {
        savedRequest?.name ?? "New Request"
    }
    
    init(id: UUID = UUID(), savedRequest: SavedRequest? = nil) {
        self.id = id
        self.savedRequest = savedRequest
        
        if let saved = savedRequest {
            loadFromSavedRequest(saved)
        }
    }
    
    func loadFromSavedRequest(_ saved: SavedRequest) {
        savedRequest = saved
        url = saved.url
        method = saved.method
        requestBody = saved.requestBody
        requestFormat = saved.requestFormat
        responseFormat = saved.responseFormat
        selectedRequestTypeName = saved.requestMessageType
        selectedResponseTypeName = saved.responseMessageType
        headers = saved.headers.map { TabHeader(key: $0.key, value: $0.value, enabled: $0.enabled) }
        authType = saved.authType
        authBearerToken = saved.authBearerToken
        authBasicUsername = saved.authBasicUsername
        authBasicPassword = saved.authBasicPassword
        preRequestScript = saved.preRequestScript
        postResponseScript = saved.postResponseScript
        
        // If authType is "none" but there's an Authorization header, sync from it
        // This handles old saved requests that have an auth header but no authType fields
        if authType == "none" && authBearerToken.isEmpty && authBasicUsername.isEmpty {
            if headers.contains(where: { $0.key.lowercased() == "authorization" && $0.enabled && !$0.value.isEmpty }) {
                syncHeadersToAuth()
            }
        }
        
        hasUnsavedChanges = false
    }
    
    func applyWorkspaceDefaults(baseUrl: String, authToken: String) {
        if savedRequest == nil {
            // Only apply to new requests
            if !baseUrl.isEmpty {
                url = baseUrl
            }
            
            if !authToken.isEmpty {
                if !headers.contains(where: { $0.key.lowercased() == "authorization" }) {
                    headers.append(TabHeader(key: "Authorization", value: authToken, enabled: true))
                }
            }
        }
    }
    
    func markAsChanged() {
        hasUnsavedChanges = true
    }
    
    func markAsSaved(with saved: SavedRequest) {
        savedRequest = saved
        hasUnsavedChanges = false
    }
    
    func syncAuthToken(_ token: String) {
        if let index = headers.firstIndex(where: { $0.key.lowercased() == "authorization" }) {
            headers[index].value = token
            headers[index].enabled = true
        } else {
            headers.append(TabHeader(key: "Authorization", value: token, enabled: true))
        }
        markAsChanged()
    }
    
    // MARK: - Auth <-> Header Sync
    
    /// Called when auth tab fields change. Updates the Authorization header in headers list.
    func syncAuthToHeaders() {
        guard !isSyncingAuth else { return }
        isSyncingAuth = true
        defer { isSyncingAuth = false }
        
        switch authType {
        case "bearer":
            let value = authBearerToken
            setAuthorizationHeader(value: value, enabled: !value.isEmpty)
        case "basic":
            let user = authBasicUsername
            let pass = authBasicPassword
            if !user.isEmpty || !pass.isEmpty {
                // Store as Basic <base64> -- but if it contains {{variables}}, keep raw
                let hasVariables = user.contains("{{") || pass.contains("{{")
                if hasVariables {
                    // Store a placeholder that will be resolved at send time
                    setAuthorizationHeader(value: "Basic {{_basic_auth_}}", enabled: true)
                } else {
                    let credentials = "\(user):\(pass)"
                    if let data = credentials.data(using: .utf8) {
                        setAuthorizationHeader(value: "Basic \(data.base64EncodedString())", enabled: true)
                    }
                }
            } else {
                removeAuthorizationHeader()
            }
        default: // "none"
            removeAuthorizationHeader()
        }
    }
    
    /// Called when the Authorization header is edited directly in the headers list. Syncs back to auth tab.
    func syncHeadersToAuth() {
        guard !isSyncingAuth else { return }
        isSyncingAuth = true
        defer { isSyncingAuth = false }
        
        if let authHeader = headers.first(where: { $0.key.lowercased() == "authorization" && $0.enabled }) {
            let value = authHeader.value.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("Basic ") {
                let base64Part = String(value.dropFirst(6))
                if let data = Data(base64Encoded: base64Part),
                   let decoded = String(data: data, encoding: .utf8),
                   let colonIndex = decoded.firstIndex(of: ":") {
                    authType = "basic"
                    authBasicUsername = String(decoded[decoded.startIndex..<colonIndex])
                    authBasicPassword = String(decoded[decoded.index(after: colonIndex)...])
                } else {
                    // Can't decode -- could be a variable placeholder or invalid
                    authType = "bearer"
                    authBearerToken = value
                }
            } else if !value.isEmpty {
                authType = "bearer"
                authBearerToken = value
            } else {
                authType = "none"
                authBearerToken = ""
            }
        } else {
            // No Authorization header found or it's disabled
            // Don't reset auth type if user just disabled the header
        }
    }
    
    private func setAuthorizationHeader(value: String, enabled: Bool) {
        if let index = headers.firstIndex(where: { $0.key.lowercased() == "authorization" }) {
            headers[index].value = value
            headers[index].enabled = enabled
        } else if enabled {
            headers.append(TabHeader(key: "Authorization", value: value, enabled: true))
        }
    }
    
    private func removeAuthorizationHeader() {
        headers.removeAll { $0.key.lowercased() == "authorization" }
    }
}

struct TabHeader: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
    var enabled: Bool = true
}
