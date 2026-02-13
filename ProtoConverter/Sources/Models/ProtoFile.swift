import Foundation

struct ProtoFile: Identifiable, Codable, Equatable {
    let id: UUID
    var path: String
    var bookmark: Data?
    
    init(id: UUID = UUID(), path: String, bookmark: Data? = nil) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
    }
    
    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
    
    var directoryPath: String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }
    
    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
    
    /// Resolve the URL using security-scoped bookmark if available
    func resolvedURL() -> URL? {
        if let bookmark = bookmark {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        return URL(fileURLWithPath: path)
    }
    
    static func == (lhs: ProtoFile, rhs: ProtoFile) -> Bool {
        lhs.id == rhs.id
    }
}
