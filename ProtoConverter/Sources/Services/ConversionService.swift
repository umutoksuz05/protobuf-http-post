import Foundation
import SwiftProtobuf

enum ConversionFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case binaryBase64 = "Binary (Base64)"
    case textFormat = "Text Format"
    
    var id: String { rawValue }
}

enum ConversionError: LocalizedError {
    case invalidInput(String)
    case conversionFailed(String)
    case unsupportedConversion(String)
    case invalidJson(String)
    case invalidBase64
    case invalidTextFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .conversionFailed(let message):
            return "Conversion failed: \(message)"
        case .unsupportedConversion(let message):
            return "Unsupported conversion: \(message)"
        case .invalidJson(let message):
            return "Invalid JSON: \(message)"
        case .invalidBase64:
            return "Invalid Base64 encoding"
        case .invalidTextFormat(let message):
            return "Invalid text format: \(message)"
        }
    }
}

class ConversionService {
    
    // Cache of all known message types for resolving nested types from imports
    private var allKnownTypes: [MessageTypeInfo] = []
    
    /// Set all available message types (for resolving types from imported files)
    func setAllMessageTypes(_ types: [MessageTypeInfo]) {
        self.allKnownTypes = types
    }
    
    // MARK: - Generate Example JSON from Proto
    
    /// Generate example JSON from a message type's proto definition
    func generateExampleJson(for messageType: MessageTypeInfo, allMessageTypes: [MessageTypeInfo]? = nil) -> String {
        let types = allMessageTypes ?? allKnownTypes
        let example = generateExampleObject(for: messageType.descriptor, allTypes: types, depth: 0)
        
        if let data = try? JSONSerialization.data(withJSONObject: example, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        
        return "{}"
    }
    
    private func generateExampleObject(
        for descriptor: Google_Protobuf_DescriptorProto,
        allTypes: [MessageTypeInfo],
        depth: Int
    ) -> [String: Any] {
        guard depth < 5 else {
            return ["_note": "max depth reached"]
        }
        
        var result: [String: Any] = [:]
        
        for field in descriptor.field {
            let fieldName = field.name
            let value = generateExampleValue(for: field, allTypes: allTypes, depth: depth)
            
            if field.label == .repeated {
                result[fieldName] = [value]
            } else {
                result[fieldName] = value
            }
        }
        
        return result
    }
    
    private func generateExampleValue(
        for field: Google_Protobuf_FieldDescriptorProto,
        allTypes: [MessageTypeInfo],
        depth: Int
    ) -> Any {
        switch field.type {
        case .double:
            return 0.0
        case .float:
            return 0.0
        case .int64, .sint64, .sfixed64:
            return 0
        case .uint64, .fixed64:
            return 0
        case .int32, .sint32, .sfixed32:
            return 0
        case .uint32, .fixed32:
            return 0
        case .bool:
            return false
        case .string:
            return "string"
        case .bytes:
            return ""
        case .enum:
            return 0
        case .message:
            let typeName = field.typeName
            if let nestedType = findMessageType(named: typeName, in: allTypes) {
                return generateExampleObject(for: nestedType.descriptor, allTypes: allTypes, depth: depth + 1)
            }
            return [String: Any]()
            
        default:
            return ""
        }
    }
    
    private func findMessageType(named typeName: String, in types: [MessageTypeInfo]) -> MessageTypeInfo? {
        var cleanName = typeName
        if cleanName.hasPrefix(".") {
            cleanName = String(cleanName.dropFirst())
        }
        
        if let match = types.first(where: { $0.fullName == cleanName }) {
            return match
        }
        
        let simpleName = cleanName.components(separatedBy: ".").last ?? cleanName
        if let match = types.first(where: { $0.fullName.hasSuffix(".\(simpleName)") || $0.fullName == simpleName }) {
            return match
        }
        
        return nil
    }
    
    /// Convert input data from one format to another
    func convert(
        input: String,
        from inputFormat: ConversionFormat,
        to outputFormat: ConversionFormat,
        messageType: MessageTypeInfo,
        allMessageTypes: [MessageTypeInfo]? = nil
    ) throws -> String {
        let typesToUse = allMessageTypes ?? allKnownTypes
        let parsedFields = try parseInput(input, format: inputFormat, messageType: messageType, allMessageTypes: typesToUse)
        return try serializeOutput(parsedFields, format: outputFormat, messageType: messageType, allMessageTypes: typesToUse)
    }
    
    // MARK: - Parsing
    
    private func parseInput(
        _ input: String,
        format: ConversionFormat,
        messageType: MessageTypeInfo,
        allMessageTypes: [MessageTypeInfo]
    ) throws -> [String: Any] {
        switch format {
        case .json:
            return try parseJson(input)
        case .binaryBase64:
            return try parseBinaryBase64(input, messageType: messageType, allMessageTypes: allMessageTypes)
        case .textFormat:
            return try parseTextFormat(input)
        }
    }
    
    private func parseJson(_ input: String) throws -> [String: Any] {
        guard let data = input.data(using: .utf8) else {
            throw ConversionError.invalidInput("Could not encode input as UTF-8")
        }
        
        do {
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConversionError.invalidJson("Root must be an object")
            }
            return dict
        } catch let error as ConversionError {
            throw error
        } catch {
            throw ConversionError.invalidJson(error.localizedDescription)
        }
    }
    
    /// Build a complete descriptor map from all known message types
    private func buildAllDescriptors(messageType: MessageTypeInfo, allMessageTypes: [MessageTypeInfo]) -> [String: Google_Protobuf_DescriptorProto] {
        var allDescriptors: [String: Google_Protobuf_DescriptorProto] = [:]
        
        for typeInfo in allMessageTypes {
            allDescriptors[typeInfo.fullName] = typeInfo.descriptor
            allDescriptors[".\(typeInfo.fullName)"] = typeInfo.descriptor
            let simpleName = typeInfo.fullName.components(separatedBy: ".").last ?? typeInfo.fullName
            if allDescriptors[simpleName] == nil {
                allDescriptors[simpleName] = typeInfo.descriptor
            }
        }
        
        // Also add nested types from the current file
        func addNestedDescriptors(_ messages: [Google_Protobuf_DescriptorProto], prefix: String) {
            for msg in messages {
                let fullName = "\(prefix).\(msg.name)"
                allDescriptors[fullName] = msg
                if fullName.hasPrefix(".") {
                    allDescriptors[String(fullName.dropFirst())] = msg
                }
                addNestedDescriptors(msg.nestedType, prefix: fullName)
            }
        }
        
        let packagePrefix = messageType.fileDescriptor.package.isEmpty ? "" : ".\(messageType.fileDescriptor.package)"
        addNestedDescriptors(messageType.fileDescriptor.messageType, prefix: packagePrefix)
        
        return allDescriptors
    }
    
    private func parseBinaryBase64(_ input: String, messageType: MessageTypeInfo, allMessageTypes: [MessageTypeInfo]) throws -> [String: Any] {
        let cleanedInput = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        guard let binaryData = Data(base64Encoded: cleanedInput) else {
            throw ConversionError.invalidBase64
        }
        
        let allDescriptors = buildAllDescriptors(messageType: messageType, allMessageTypes: allMessageTypes)
        return try decodeBinaryProto(binaryData, descriptor: messageType.descriptor, allDescriptors: allDescriptors)
    }
    
    private func parseTextFormat(_ input: String) throws -> [String: Any] {
        var result: [String: Any] = [:]
        let lines = input.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let fieldName = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                    value = value.replacingOccurrences(of: "\\n", with: "\n")
                    value = value.replacingOccurrences(of: "\\t", with: "\t")
                    value = value.replacingOccurrences(of: "\\\"", with: "\"")
                    value = value.replacingOccurrences(of: "\\\\", with: "\\")
                    result[fieldName] = value
                } else if value == "true" {
                    result[fieldName] = true
                } else if value == "false" {
                    result[fieldName] = false
                } else if let intValue = Int64(value) {
                    result[fieldName] = intValue
                } else if let doubleValue = Double(value) {
                    result[fieldName] = doubleValue
                } else {
                    result[fieldName] = value
                }
            }
        }
        
        return result
    }
    
    // MARK: - Serialization
    
    private func serializeOutput(
        _ fields: [String: Any],
        format: ConversionFormat,
        messageType: MessageTypeInfo,
        allMessageTypes: [MessageTypeInfo]
    ) throws -> String {
        switch format {
        case .json:
            return try serializeToJson(fields)
        case .binaryBase64:
            return try serializeToBinaryBase64(fields, messageType: messageType, allMessageTypes: allMessageTypes)
        case .textFormat:
            return serializeToTextFormat(fields, messageType: messageType)
        }
    }
    
    private func serializeToJson(_ fields: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: fields,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ConversionError.conversionFailed("Could not encode JSON as UTF-8")
        }
        return jsonString
    }
    
    private func serializeToBinaryBase64(_ fields: [String: Any], messageType: MessageTypeInfo, allMessageTypes: [MessageTypeInfo]) throws -> String {
        let allDescriptors = buildAllDescriptors(messageType: messageType, allMessageTypes: allMessageTypes)
        let binaryData = try encodeBinaryProto(fields, descriptor: messageType.descriptor, allDescriptors: allDescriptors)
        return binaryData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
    }
    
    private func serializeToTextFormat(_ fields: [String: Any], messageType: MessageTypeInfo) -> String {
        var lines: [String] = []
        
        let sortedKeys = fields.keys.sorted()
        for key in sortedKeys {
            guard let value = fields[key] else { continue }
            
            if let stringValue = value as? String {
                let escaped = stringValue
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\t", with: "\\t")
                lines.append("\(key): \"\(escaped)\"")
            } else if let boolValue = value as? Bool {
                lines.append("\(key): \(boolValue)")
            } else if let arrayValue = value as? [Any] {
                for element in arrayValue {
                    if let strElement = element as? String {
                        let escaped = strElement
                            .replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "\"", with: "\\\"")
                        lines.append("\(key): \"\(escaped)\"")
                    } else {
                        lines.append("\(key): \(element)")
                    }
                }
            } else if let dictValue = value as? [String: Any] {
                lines.append("\(key) {")
                let nestedText = serializeToTextFormat(dictValue, messageType: messageType)
                let indentedLines = nestedText.components(separatedBy: .newlines).map { "  \($0)" }
                lines.append(contentsOf: indentedLines)
                lines.append("}")
            } else {
                lines.append("\(key): \(value)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Binary Proto Decoding
    
    private func decodeBinaryProto(_ data: Data, descriptor: Google_Protobuf_DescriptorProto, allDescriptors: [String: Google_Protobuf_DescriptorProto] = [:]) throws -> [String: Any] {
        var result: [String: Any] = [:]
        var offset = 0
        let bytes = [UInt8](data)
        
        // Build a map of field number to descriptor for quick lookup
        var fieldMap: [Int: Google_Protobuf_FieldDescriptorProto] = [:]
        for field in descriptor.field {
            fieldMap[Int(field.number)] = field
        }
        
        // Initialize all fields with default values using the original proto field name
        for field in descriptor.field {
            let name = field.name
            
            if field.label == .repeated {
                result[name] = [Any]()
            } else {
                switch field.type {
                case .bool:
                    result[name] = false
                case .string:
                    result[name] = ""
                case .bytes:
                    result[name] = ""
                case .int32, .int64, .uint32, .uint64, .sint32, .sint64, .fixed32, .fixed64, .sfixed32, .sfixed64:
                    result[name] = 0
                case .float, .double:
                    result[name] = 0.0
                case .enum:
                    result[name] = 0
                case .message:
                    break
                default:
                    break
                }
            }
        }
        
        while offset < bytes.count {
            let (tag, tagSize) = try readVarint(from: bytes, at: offset)
            offset += tagSize
            
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x7)
            
            let fieldDescriptor = fieldMap[fieldNumber]
            // Always use field.name -- the original name from the proto file
            let fieldName = fieldDescriptor?.name ?? "field_\(fieldNumber)"
            let isRepeated = fieldDescriptor?.label == .repeated
            
            var values: [Any] = []
            
            switch wireType {
            case 0: // Varint
                let (varint, varintSize) = try readVarint(from: bytes, at: offset)
                offset += varintSize
                
                if let fd = fieldDescriptor {
                    switch fd.type {
                    case .bool:
                        values.append(varint != 0)
                    case .enum:
                        values.append(Int(varint))
                    case .sint32:
                        let decoded = Int32(bitPattern: UInt32(truncatingIfNeeded: (varint >> 1) ^ (0 &- (varint & 1))))
                        values.append(decoded)
                    case .sint64:
                        let decoded = Int64(bitPattern: (varint >> 1) ^ (0 &- (varint & 1)))
                        values.append(decoded)
                    default:
                        values.append(Int64(bitPattern: varint))
                    }
                } else {
                    values.append(Int64(bitPattern: varint))
                }
                
            case 1: // 64-bit
                guard offset + 8 <= bytes.count else {
                    throw ConversionError.invalidInput("Unexpected end of data")
                }
                var val: UInt64 = 0
                for i in 0..<8 {
                    val |= UInt64(bytes[offset + i]) << (i * 8)
                }
                offset += 8
                
                if let fd = fieldDescriptor, fd.type == .double {
                    values.append(Double(bitPattern: val))
                } else {
                    values.append(Int64(bitPattern: val))
                }
                
            case 2: // Length-delimited
                let (length, lengthSize) = try readVarint(from: bytes, at: offset)
                offset += lengthSize
                
                guard offset + Int(length) <= bytes.count else {
                    throw ConversionError.invalidInput("Unexpected end of data")
                }
                
                let fieldData = Data(bytes[offset..<(offset + Int(length))])
                offset += Int(length)
                
                if let fd = fieldDescriptor {
                    switch fd.type {
                    case .string:
                        values.append(String(data: fieldData, encoding: .utf8) ?? "")
                    case .bytes:
                        values.append(fieldData.base64EncodedString())
                    case .message:
                        let typeName = fd.typeName
                        if let nestedDesc = allDescriptors[typeName] ?? findNestedDescriptor(named: typeName, in: descriptor) {
                            let nestedResult = try decodeBinaryProto(fieldData, descriptor: nestedDesc, allDescriptors: allDescriptors)
                            values.append(nestedResult)
                        } else {
                            values.append(["_raw": fieldData.base64EncodedString()])
                        }
                    default:
                        if isRepeated && isPackableType(fd.type) {
                            let packedValues = try decodePackedField(fieldData, type: fd.type)
                            values.append(contentsOf: packedValues)
                        } else {
                            values.append(String(data: fieldData, encoding: .utf8) ?? fieldData.base64EncodedString())
                        }
                    }
                } else {
                    if let str = String(data: fieldData, encoding: .utf8), str.allSatisfy({ $0.isASCII || $0.isLetter || $0.isNumber || $0.isWhitespace || $0.isPunctuation }) {
                        values.append(str)
                    } else {
                        values.append(fieldData.base64EncodedString())
                    }
                }
                
            case 5: // 32-bit
                guard offset + 4 <= bytes.count else {
                    throw ConversionError.invalidInput("Unexpected end of data")
                }
                var val: UInt32 = 0
                for i in 0..<4 {
                    val |= UInt32(bytes[offset + i]) << (i * 8)
                }
                offset += 4
                
                if let fd = fieldDescriptor, fd.type == .float {
                    values.append(Float(bitPattern: val))
                } else {
                    values.append(Int32(bitPattern: val))
                }
                
            default:
                throw ConversionError.invalidInput("Unknown wire type: \(wireType)")
            }
            
            // Add values to result
            for value in values {
                if isRepeated {
                    if var array = result[fieldName] as? [Any] {
                        array.append(value)
                        result[fieldName] = array
                    } else {
                        result[fieldName] = [value]
                    }
                } else {
                    result[fieldName] = value
                }
            }
        }
        
        return result
    }
    
    private func isPackableType(_ type: Google_Protobuf_FieldDescriptorProto.TypeEnum) -> Bool {
        switch type {
        case .int32, .int64, .uint32, .uint64, .sint32, .sint64, .bool, .enum, .fixed32, .fixed64, .sfixed32, .sfixed64, .float, .double:
            return true
        default:
            return false
        }
    }
    
    private func decodePackedField(_ data: Data, type: Google_Protobuf_FieldDescriptorProto.TypeEnum) throws -> [Any] {
        var values: [Any] = []
        var offset = 0
        let bytes = [UInt8](data)
        
        while offset < bytes.count {
            switch type {
            case .int32, .int64, .uint32, .uint64, .enum:
                let (varint, size) = try readVarint(from: bytes, at: offset)
                offset += size
                values.append(Int64(bitPattern: varint))
            case .sint32:
                let (varint, size) = try readVarint(from: bytes, at: offset)
                offset += size
                let decoded = Int32(bitPattern: UInt32(truncatingIfNeeded: (varint >> 1) ^ (0 &- (varint & 1))))
                values.append(decoded)
            case .sint64:
                let (varint, size) = try readVarint(from: bytes, at: offset)
                offset += size
                let decoded = Int64(bitPattern: (varint >> 1) ^ (0 &- (varint & 1)))
                values.append(decoded)
            case .bool:
                let (varint, size) = try readVarint(from: bytes, at: offset)
                offset += size
                values.append(varint != 0)
            case .fixed32, .sfixed32:
                guard offset + 4 <= bytes.count else { break }
                var val: UInt32 = 0
                for i in 0..<4 { val |= UInt32(bytes[offset + i]) << (i * 8) }
                offset += 4
                values.append(Int32(bitPattern: val))
            case .fixed64, .sfixed64:
                guard offset + 8 <= bytes.count else { break }
                var val: UInt64 = 0
                for i in 0..<8 { val |= UInt64(bytes[offset + i]) << (i * 8) }
                offset += 8
                values.append(Int64(bitPattern: val))
            case .float:
                guard offset + 4 <= bytes.count else { break }
                var val: UInt32 = 0
                for i in 0..<4 { val |= UInt32(bytes[offset + i]) << (i * 8) }
                offset += 4
                values.append(Float(bitPattern: val))
            case .double:
                guard offset + 8 <= bytes.count else { break }
                var val: UInt64 = 0
                for i in 0..<8 { val |= UInt64(bytes[offset + i]) << (i * 8) }
                offset += 8
                values.append(Double(bitPattern: val))
            default:
                break
            }
        }
        
        return values
    }
    
    // MARK: - Binary Proto Encoding
    
    private func encodeBinaryProto(_ fields: [String: Any], descriptor: Google_Protobuf_DescriptorProto, allDescriptors: [String: Google_Protobuf_DescriptorProto]) throws -> Data {
        var result = Data()
        
        for field in descriptor.field {
            // Look up using the original proto field name first, then try jsonName as fallback
            // This way we accept both snake_case and camelCase input
            guard let value = fields[field.name] ?? fields[field.jsonName] else {
                continue
            }
            
            let fieldNumber = UInt64(field.number)
            
            // Handle repeated fields
            let values: [Any]
            if let array = value as? [Any] {
                values = array
            } else {
                values = [value]
            }
            
            for val in values {
                switch field.type {
                case .int32, .int64, .uint32, .uint64, .sint32, .sint64, .enum:
                    let intVal = toInt64(val)
                    let tag = (fieldNumber << 3) | 0
                    result.append(contentsOf: encodeVarint(tag))
                    result.append(contentsOf: encodeVarint(UInt64(bitPattern: intVal)))
                    
                case .bool:
                    let boolVal = toBool(val)
                    let tag = (fieldNumber << 3) | 0
                    result.append(contentsOf: encodeVarint(tag))
                    result.append(contentsOf: encodeVarint(boolVal ? 1 : 0))
                    
                case .string:
                    let strVal = toString(val)
                    let strData = strVal.data(using: .utf8) ?? Data()
                    let tag = (fieldNumber << 3) | 2
                    result.append(contentsOf: encodeVarint(tag))
                    result.append(contentsOf: encodeVarint(UInt64(strData.count)))
                    result.append(strData)
                    
                case .bytes:
                    let bytesData: Data
                    if let str = val as? String, let decoded = Data(base64Encoded: str) {
                        bytesData = decoded
                    } else if let data = val as? Data {
                        bytesData = data
                    } else {
                        bytesData = Data()
                    }
                    let tag = (fieldNumber << 3) | 2
                    result.append(contentsOf: encodeVarint(tag))
                    result.append(contentsOf: encodeVarint(UInt64(bytesData.count)))
                    result.append(bytesData)
                    
                case .double:
                    let doubleVal = toDouble(val)
                    var bits = doubleVal.bitPattern
                    let tag = (fieldNumber << 3) | 1
                    result.append(contentsOf: encodeVarint(tag))
                    withUnsafeBytes(of: &bits) { result.append(contentsOf: $0) }
                    
                case .float:
                    let floatVal = Float(toDouble(val))
                    var bits = floatVal.bitPattern
                    let tag = (fieldNumber << 3) | 5
                    result.append(contentsOf: encodeVarint(tag))
                    withUnsafeBytes(of: &bits) { result.append(contentsOf: $0) }
                    
                case .fixed32, .sfixed32:
                    var intVal = UInt32(truncatingIfNeeded: toInt64(val))
                    let tag = (fieldNumber << 3) | 5
                    result.append(contentsOf: encodeVarint(tag))
                    withUnsafeBytes(of: &intVal) { result.append(contentsOf: $0) }
                    
                case .fixed64, .sfixed64:
                    var intVal = UInt64(bitPattern: toInt64(val))
                    let tag = (fieldNumber << 3) | 1
                    result.append(contentsOf: encodeVarint(tag))
                    withUnsafeBytes(of: &intVal) { result.append(contentsOf: $0) }
                    
                case .message:
                    if let dictVal = val as? [String: Any] {
                        // Look up nested descriptor from allDescriptors (handles imported types)
                        // Fall back to searching parent's nestedType for truly nested messages
                        let typeName = field.typeName
                        if let nestedDesc = allDescriptors[typeName] ?? findNestedDescriptor(named: typeName, in: descriptor) {
                            let nestedData = try encodeBinaryProto(dictVal, descriptor: nestedDesc, allDescriptors: allDescriptors)
                            let tag = (fieldNumber << 3) | 2
                            result.append(contentsOf: encodeVarint(tag))
                            result.append(contentsOf: encodeVarint(UInt64(nestedData.count)))
                            result.append(nestedData)
                        }
                    }
                    
                default:
                    let strVal = toString(val)
                    let strData = strVal.data(using: .utf8) ?? Data()
                    let tag = (fieldNumber << 3) | 2
                    result.append(contentsOf: encodeVarint(tag))
                    result.append(contentsOf: encodeVarint(UInt64(strData.count)))
                    result.append(strData)
                }
            }
        }
        
        return result
    }
    
    // MARK: - Helper Methods
    
    private func readVarint(from bytes: [UInt8], at offset: Int) throws -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift = 0
        var bytesRead = 0
        
        while offset + bytesRead < bytes.count {
            let byte = bytes[offset + bytesRead]
            bytesRead += 1
            
            result |= UInt64(byte & 0x7F) << shift
            
            if (byte & 0x80) == 0 {
                return (result, bytesRead)
            }
            
            shift += 7
            if shift >= 64 {
                throw ConversionError.invalidInput("Varint too long")
            }
        }
        
        throw ConversionError.invalidInput("Unexpected end of data while reading varint")
    }
    
    private func encodeVarint(_ value: UInt64) -> [UInt8] {
        var result: [UInt8] = []
        var v = value
        
        while v > 0x7F {
            result.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        result.append(UInt8(v))
        
        return result.isEmpty ? [0] : result
    }
    
    private func findNestedDescriptor(named typeName: String, in parent: Google_Protobuf_DescriptorProto) -> Google_Protobuf_DescriptorProto? {
        let simpleName = typeName.components(separatedBy: ".").last ?? typeName
        return parent.nestedType.first { $0.name == simpleName }
    }
    
    private func toInt64(_ value: Any) -> Int64 {
        if let i = value as? Int64 { return i }
        if let i = value as? Int { return Int64(i) }
        if let i = value as? Int32 { return Int64(i) }
        if let u = value as? UInt64 { return Int64(bitPattern: u) }
        if let u = value as? UInt { return Int64(u) }
        if let d = value as? Double { return Int64(d) }
        if let s = value as? String, let i = Int64(s) { return i }
        return 0
    }
    
    private func toDouble(_ value: Any) -> Double {
        if let d = value as? Double { return d }
        if let f = value as? Float { return Double(f) }
        if let i = value as? Int64 { return Double(i) }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String, let d = Double(s) { return d }
        return 0
    }
    
    private func toBool(_ value: Any) -> Bool {
        if let b = value as? Bool { return b }
        if let i = value as? Int { return i != 0 }
        if let i = value as? Int64 { return i != 0 }
        if let s = value as? String { return s.lowercased() == "true" || s == "1" }
        return false
    }
    
    private func toString(_ value: Any) -> String {
        if let s = value as? String { return s }
        return "\(value)"
    }
}
