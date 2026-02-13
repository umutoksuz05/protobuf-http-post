import Foundation
import SwiftProtobuf

struct MessageTypeInfo: Identifiable, Hashable {
    let id: String
    let fullName: String
    let packageName: String
    let messageName: String
    let descriptor: Google_Protobuf_DescriptorProto
    let fileDescriptor: Google_Protobuf_FileDescriptorProto
    
    init(fullName: String, descriptor: Google_Protobuf_DescriptorProto, fileDescriptor: Google_Protobuf_FileDescriptorProto) {
        self.id = fullName
        self.fullName = fullName
        self.descriptor = descriptor
        self.fileDescriptor = fileDescriptor
        
        // Extract package and message name
        if let lastDot = fullName.lastIndex(of: ".") {
            self.packageName = String(fullName[..<lastDot])
            self.messageName = String(fullName[fullName.index(after: lastDot)...])
        } else {
            self.packageName = ""
            self.messageName = fullName
        }
    }
    
    var displayName: String {
        if packageName.isEmpty {
            return messageName
        }
        return "\(packageName).\(messageName)"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: MessageTypeInfo, rhs: MessageTypeInfo) -> Bool {
        lhs.id == rhs.id
    }
}
