import Foundation
import SwiftProtobuf

enum ProtoCompilerError: LocalizedError {
    case protocNotFound
    case compilationFailed(String)
    case noProtoFiles
    case descriptorParsingFailed(String)
    case missingImports([String])
    
    var errorDescription: String? {
        switch self {
        case .protocNotFound:
            return "protoc compiler not found. Please install Protocol Buffers: brew install protobuf"
        case .compilationFailed(let message):
            return "Proto compilation failed: \(message)"
        case .noProtoFiles:
            return "No proto files to compile"
        case .descriptorParsingFailed(let message):
            return "Failed to parse descriptor: \(message)"
        case .missingImports(let imports):
            let importList = imports.joined(separator: "\n  - ")
            return "Missing imported proto files. Please add these files to your workspace:\n  - \(importList)"
        }
    }
}

class ProtoCompilerService {
    
    /// Parse import statements from a proto file
    private func parseImports(from fileURL: URL) -> [String] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        
        var imports: [String] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Match: import "filename.proto"; or import 'filename.proto';
            if trimmed.hasPrefix("import ") {
                // Skip public/weak imports for now, just get the filename
                var importLine = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
                
                // Handle public/weak keyword
                if importLine.hasPrefix("public ") {
                    importLine = String(importLine.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                } else if importLine.hasPrefix("weak ") {
                    importLine = String(importLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                }
                
                // Extract filename from quotes
                if let firstQuote = importLine.firstIndex(of: "\""),
                   let lastQuote = importLine.lastIndex(of: "\""),
                   firstQuote != lastQuote {
                    let start = importLine.index(after: firstQuote)
                    let filename = String(importLine[start..<lastQuote])
                    imports.append(filename)
                } else if let firstQuote = importLine.firstIndex(of: "'"),
                          let lastQuote = importLine.lastIndex(of: "'"),
                          firstQuote != lastQuote {
                    let start = importLine.index(after: firstQuote)
                    let filename = String(importLine[start..<lastQuote])
                    imports.append(filename)
                }
            }
        }
        
        return imports
    }
    
    /// Calculate the proto root directory for a file based on its import path
    /// For example: if file is at /path/to/protos/blockout/v2/common.proto
    /// and import path would be "blockout/v2/common.proto", returns /path/to/protos
    private func calculateProtoRoot(for fileURL: URL, importPaths: [String]) -> String? {
        let filePath = fileURL.path
        let filename = fileURL.lastPathComponent
        
        // Check each import to see if it matches this file's path structure
        for importPath in importPaths {
            // Skip if it's just a filename without directory
            guard importPath.contains("/") else { continue }
            
            let importFilename = (importPath as NSString).lastPathComponent
            
            // If the import filename matches our file
            if importFilename == filename {
                // Check if the file path ends with the import path
                if filePath.hasSuffix(importPath) {
                    // Calculate the root by removing the import path from the file path
                    let rootEndIndex = filePath.index(filePath.endIndex, offsetBy: -importPath.count)
                    var root = String(filePath[..<rootEndIndex])
                    // Remove trailing slash if present
                    if root.hasSuffix("/") {
                        root = String(root.dropLast())
                    }
                    return root
                }
            }
        }
        
        return nil
    }
    
    /// Collect all import paths from all proto files
    private func collectAllImports(from fileUrls: [URL]) -> [String] {
        var allImports = Set<String>()
        for url in fileUrls {
            let imports = parseImports(from: url)
            for imp in imports {
                allImports.insert(imp)
            }
        }
        return Array(allImports)
    }
    
    /// Validate that all imports are available in the workspace
    private func validateImports(protoFiles: [URL]) throws -> [String] {
        // Build a map of filename -> full paths
        var filesByName: [String: [URL]] = [:]
        for url in protoFiles {
            let name = url.lastPathComponent
            filesByName[name, default: []].append(url)
        }
        
        // Collect all imports and calculate proto roots
        let allImports = collectAllImports(from: protoFiles)
        
        // Calculate proto roots for each file
        var protoRoots = Set<String>()
        for url in protoFiles {
            if let root = calculateProtoRoot(for: url, importPaths: allImports) {
                protoRoots.insert(root)
            }
            // Also add the file's directory as a fallback
            protoRoots.insert(url.deletingLastPathComponent().path)
        }
        
        // Check imports from each file
        var missingImports = Set<String>()
        
        for fileURL in protoFiles {
            let imports = parseImports(from: fileURL)
            
            for importPath in imports {
                // Skip google protobuf well-known types (they're bundled with protoc)
                if importPath.hasPrefix("google/protobuf/") {
                    continue
                }
                
                let importFilename = (importPath as NSString).lastPathComponent
                
                // Check if we have a file with this name
                guard let matchingFiles = filesByName[importFilename], !matchingFiles.isEmpty else {
                    missingImports.insert(importPath)
                    continue
                }
                
                // Check if any matching file resolves the import path
                var found = false
                
                // For path-based imports (e.g., "blockout/v2/common.proto")
                if importPath.contains("/") {
                    for matchingFile in matchingFiles {
                        // Check if the file path ends with the import path
                        if matchingFile.path.hasSuffix(importPath) {
                            found = true
                            break
                        }
                    }
                    
                    // Also check via proto roots
                    if !found {
                        for root in protoRoots {
                            let fullPath = (root as NSString).appendingPathComponent(importPath)
                            if FileManager.default.fileExists(atPath: fullPath) {
                                found = true
                                break
                            }
                        }
                    }
                } else {
                    // Simple filename import - just check if file exists
                    found = true
                }
                
                if !found {
                    missingImports.insert(importPath)
                }
            }
        }
        
        return Array(missingImports).sorted()
    }
    
    /// Calculate include paths for protoc based on file locations and import paths
    private func calculateIncludePaths(for fileUrls: [URL]) -> Set<String> {
        var includePaths = Set<String>()
        
        // Collect all imports
        let allImports = collectAllImports(from: fileUrls)
        
        for url in fileUrls {
            // Always add the file's directory
            includePaths.insert(url.deletingLastPathComponent().path)
            
            // Calculate proto root if this file matches an import path structure
            if let root = calculateProtoRoot(for: url, importPaths: allImports) {
                includePaths.insert(root)
            }
            
            // Also try to detect proto root from the file path
            // Look for common patterns like /proto/, /protos/, /protobuf/
            let pathComponents = url.pathComponents
            for (index, component) in pathComponents.enumerated() {
                if ["proto", "protos", "protobuf", "schemas"].contains(component.lowercased()) {
                    // Use the path up to and including this component
                    let rootComponents = Array(pathComponents[0...index])
                    let root = rootComponents.joined(separator: "/")
                    if !root.isEmpty {
                        includePaths.insert(root)
                    }
                }
            }
        }
        
        return includePaths
    }
    
    /// Find protoc binary in common locations
    private func findProtoc() -> String? {
        let commonPaths = [
            "/opt/homebrew/bin/protoc",      // Homebrew on Apple Silicon
            "/usr/local/bin/protoc",          // Homebrew on Intel
            "/usr/bin/protoc",                // System install
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Try to find via which command
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["protoc"]
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                return output
            }
        } catch {
            // Ignore
        }
        
        return nil
    }
    
    func compileAndExtractTypes(from protoFiles: [ProtoFile]) async throws -> [MessageTypeInfo] {
        guard !protoFiles.isEmpty else {
            return []
        }
        
        guard let protocPath = findProtoc() else {
            throw ProtoCompilerError.protocNotFound
        }
        
        // Filter to only existing files
        let existingFiles = protoFiles.filter { $0.exists }
        guard !existingFiles.isEmpty else {
            return []
        }
        
        // Collect file URLs
        var fileUrls: [URL] = []
        for file in existingFiles {
            if let url = file.resolvedURL() {
                fileUrls.append(url)
            }
        }
        
        // Validate all imports are present in workspace
        let missingImports = try validateImports(protoFiles: fileUrls)
        if !missingImports.isEmpty {
            throw ProtoCompilerError.missingImports(missingImports)
        }
        
        // Create temp directory for descriptor output
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let descriptorPath = tempDir.appendingPathComponent("descriptor.pb")
        
        // Calculate include paths (handles path-based imports properly)
        let includePaths = calculateIncludePaths(for: fileUrls)
        
        // Collect proto file paths
        var protoFilePaths: [String] = []
        for url in fileUrls {
            protoFilePaths.append(url.path)
        }
        
        // Build protoc command
        var arguments = [String]()
        
        // Add import paths (sorted for consistent ordering)
        for importPath in includePaths.sorted() {
            arguments.append("-I\(importPath)")
        }
        
        // Add descriptor output
        arguments.append("--descriptor_set_out=\(descriptorPath.path)")
        arguments.append("--include_imports")
        
        // Add proto files
        arguments.append(contentsOf: protoFilePaths)
        
        // Run protoc
        let process = Process()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: protocPath)
        process.arguments = arguments
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ProtoCompilerError.compilationFailed(errorMessage)
        }
        
        // Parse the descriptor set
        let descriptorData = try Data(contentsOf: descriptorPath)
        let descriptorSet = try Google_Protobuf_FileDescriptorSet(serializedBytes: descriptorData)
        
        // Extract message types
        var messageTypes: [MessageTypeInfo] = []
        
        for fileDescriptor in descriptorSet.file {
            let packagePrefix = fileDescriptor.package.isEmpty ? "" : "\(fileDescriptor.package)."
            
            // Extract top-level messages
            for messageDescriptor in fileDescriptor.messageType {
                let fullName = "\(packagePrefix)\(messageDescriptor.name)"
                let typeInfo = MessageTypeInfo(
                    fullName: fullName,
                    descriptor: messageDescriptor,
                    fileDescriptor: fileDescriptor
                )
                messageTypes.append(typeInfo)
                
                // Extract nested messages
                extractNestedMessages(
                    from: messageDescriptor,
                    parentName: fullName,
                    fileDescriptor: fileDescriptor,
                    into: &messageTypes
                )
            }
        }
        
        // Sort by full name
        messageTypes.sort { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        
        return messageTypes
    }
    
    private func extractNestedMessages(
        from parent: Google_Protobuf_DescriptorProto,
        parentName: String,
        fileDescriptor: Google_Protobuf_FileDescriptorProto,
        into messageTypes: inout [MessageTypeInfo]
    ) {
        for nestedDescriptor in parent.nestedType {
            // Skip map entry types (they're auto-generated)
            if nestedDescriptor.options.mapEntry {
                continue
            }
            
            let fullName = "\(parentName).\(nestedDescriptor.name)"
            let typeInfo = MessageTypeInfo(
                fullName: fullName,
                descriptor: nestedDescriptor,
                fileDescriptor: fileDescriptor
            )
            messageTypes.append(typeInfo)
            
            // Recursively extract nested messages
            extractNestedMessages(
                from: nestedDescriptor,
                parentName: fullName,
                fileDescriptor: fileDescriptor,
                into: &messageTypes
            )
        }
    }
}
