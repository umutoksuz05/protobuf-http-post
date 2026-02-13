import Foundation

struct RequestGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var requestIds: [UUID]  // Order of requests in this group
    let createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, requestIds: [UUID] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.requestIds = requestIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    static let defaultGroupId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    
    static func defaultGroup() -> RequestGroup {
        RequestGroup(id: defaultGroupId, name: "Default")
    }
    
    static func == (lhs: RequestGroup, rhs: RequestGroup) -> Bool {
        lhs.id == rhs.id
    }
}
