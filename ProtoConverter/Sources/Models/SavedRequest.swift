import Foundation

struct SavedRequest: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var url: String
    var method: String
    var headers: [SavedHeader]
    var requestBody: String
    var requestFormat: String  // "json" or "protobuf"
    var responseFormat: String
    var requestMessageType: String?  // Full name of the message type
    var responseMessageType: String?
    var groupId: UUID  // The group this request belongs to
    var authType: String          // "none", "bearer", "basic"
    var authBearerToken: String
    var authBasicUsername: String
    var authBasicPassword: String
    var preRequestScript: String
    var postResponseScript: String
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        url: String = "",
        method: String = "POST",
        headers: [SavedHeader] = [SavedHeader(key: "Content-Type", value: "application/json", enabled: true)],
        requestBody: String = "",
        requestFormat: String = "json",
        responseFormat: String = "json",
        requestMessageType: String? = nil,
        responseMessageType: String? = nil,
        groupId: UUID = RequestGroup.defaultGroupId,
        authType: String = "none",
        authBearerToken: String = "",
        authBasicUsername: String = "",
        authBasicPassword: String = "",
        preRequestScript: String = "",
        postResponseScript: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.method = method
        self.headers = headers
        self.requestBody = requestBody
        self.requestFormat = requestFormat
        self.responseFormat = responseFormat
        self.requestMessageType = requestMessageType
        self.responseMessageType = responseMessageType
        self.groupId = groupId
        self.authType = authType
        self.authBearerToken = authBearerToken
        self.authBasicUsername = authBasicUsername
        self.authBasicPassword = authBasicPassword
        self.preRequestScript = preRequestScript
        self.postResponseScript = postResponseScript
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Custom Codable for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, name, url, method, headers, requestBody, requestFormat, responseFormat
        case requestMessageType, responseMessageType, groupId
        case useBasicAuth  // old field for migration
        case authType, authBearerToken, authBasicUsername, authBasicPassword
        case preRequestScript, postResponseScript
        case createdAt, updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        method = try container.decode(String.self, forKey: .method)
        headers = try container.decode([SavedHeader].self, forKey: .headers)
        requestBody = try container.decode(String.self, forKey: .requestBody)
        requestFormat = try container.decode(String.self, forKey: .requestFormat)
        responseFormat = try container.decode(String.self, forKey: .responseFormat)
        requestMessageType = try container.decodeIfPresent(String.self, forKey: .requestMessageType)
        responseMessageType = try container.decodeIfPresent(String.self, forKey: .responseMessageType)
        groupId = try container.decodeIfPresent(UUID.self, forKey: .groupId) ?? RequestGroup.defaultGroupId
        
        // Migrate from old useBasicAuth -> new authType
        if let newAuthType = try container.decodeIfPresent(String.self, forKey: .authType) {
            authType = newAuthType
        } else {
            let oldUseBasicAuth = try container.decodeIfPresent(Bool.self, forKey: .useBasicAuth) ?? false
            authType = oldUseBasicAuth ? "basic" : "none"
        }
        authBearerToken = try container.decodeIfPresent(String.self, forKey: .authBearerToken) ?? ""
        authBasicUsername = try container.decodeIfPresent(String.self, forKey: .authBasicUsername) ?? ""
        authBasicPassword = try container.decodeIfPresent(String.self, forKey: .authBasicPassword) ?? ""
        
        preRequestScript = try container.decodeIfPresent(String.self, forKey: .preRequestScript) ?? ""
        postResponseScript = try container.decodeIfPresent(String.self, forKey: .postResponseScript) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(method, forKey: .method)
        try container.encode(headers, forKey: .headers)
        try container.encode(requestBody, forKey: .requestBody)
        try container.encode(requestFormat, forKey: .requestFormat)
        try container.encode(responseFormat, forKey: .responseFormat)
        try container.encodeIfPresent(requestMessageType, forKey: .requestMessageType)
        try container.encodeIfPresent(responseMessageType, forKey: .responseMessageType)
        try container.encode(groupId, forKey: .groupId)
        try container.encode(authType, forKey: .authType)
        try container.encode(authBearerToken, forKey: .authBearerToken)
        try container.encode(authBasicUsername, forKey: .authBasicUsername)
        try container.encode(authBasicPassword, forKey: .authBasicPassword)
        try container.encode(preRequestScript, forKey: .preRequestScript)
        try container.encode(postResponseScript, forKey: .postResponseScript)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    static func == (lhs: SavedRequest, rhs: SavedRequest) -> Bool {
        lhs.id == rhs.id
    }
}

struct SavedHeader: Codable, Equatable {
    var key: String
    var value: String
    var enabled: Bool
}
