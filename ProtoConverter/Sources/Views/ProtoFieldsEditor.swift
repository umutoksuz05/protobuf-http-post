import SwiftUI
import SwiftProtobuf

struct ProtoFieldsEditor: View {
    let messageType: MessageTypeInfo
    let allMessageTypes: [MessageTypeInfo]
    @Binding var jsonText: String
    var onChanged: () -> Void

    @State private var fieldValues: [String: String] = [:]
    @State private var lastTypeName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            fieldsList
        }
        .onAppear { initializeFields() }
        .onChange(of: messageType.fullName) { _, _ in
            lastTypeName = ""
            initializeFields()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 11))
                Text("\(messageType.messageName)")
                    .font(.system(size: 11, weight: .medium))
                Text("\(messageType.descriptor.field.count) fields")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
            }
            .foregroundColor(Theme.textSecondary)

            Spacer()

            Button(action: populateFromExistingJson) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 10))
                    Text("Load JSON")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(HoverButtonStyle())
            .help("Populate fields from current JSON body")

            Button(action: clearAllFields) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("Clear all fields")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surface.opacity(0.8))
    }

    // MARK: - Fields List

    private var fieldsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sortedFields, id: \.number) { field in
                    fieldRow(for: field)
                    if field.number != sortedFields.last?.number {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var sortedFields: [Google_Protobuf_FieldDescriptorProto] {
        messageType.descriptor.field.sorted { $0.number < $1.number }
    }

    // MARK: - Field Row

    private func fieldRow(for field: Google_Protobuf_FieldDescriptorProto) -> some View {
        let isLargeInput = field.type == .string || field.type == .bytes || field.type == .message
        let layout = isLargeInput ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 0))

        return layout {
            // Label area
            HStack(spacing: 0) {
                Text("\(field.number)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 1) {
                    Text(field.name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                    HStack(spacing: 4) {
                        Text(typeDisplayName(for: field))
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textTertiary)
                        if field.label == .repeated {
                            typeBadge("repeated", color: Theme.info)
                        }
                        if field.type == .bytes {
                            typeBadge("text / base64", color: Theme.warning)
                        }
                    }
                }
                .padding(.leading, 8)

                if isLargeInput { Spacer() }
            }
            .frame(width: isLargeInput ? nil : 180, alignment: .leading)

            // Input area
            fieldInput(for: field)
                .padding(.leading, isLargeInput ? 32 : 8)
                .padding(.trailing, isLargeInput ? 12 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func typeBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.1)))
    }

    // MARK: - Field Input

    @ViewBuilder
    private func fieldInput(for field: Google_Protobuf_FieldDescriptorProto) -> some View {
        let binding = Binding<String>(
            get: { fieldValues[field.name] ?? "" },
            set: { newVal in
                fieldValues[field.name] = newVal
                rebuildJson()
            }
        )

        switch field.type {
        case .bool where field.label != .repeated:
            HStack {
                Toggle("", isOn: Binding(
                    get: { fieldValues[field.name]?.lowercased() == "true" },
                    set: { newVal in
                        fieldValues[field.name] = newVal ? "true" : "false"
                        rebuildJson()
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
            }

        case .string, .bytes:
            resizableTextInput(
                text: binding,
                placeholder: placeholder(for: field),
                borderColor: field.type == .bytes ? Theme.warning.opacity(0.3) : Theme.border
            )

        case .message:
            resizableTextInput(
                text: binding,
                placeholder: placeholder(for: field),
                borderColor: Theme.info.opacity(0.3)
            )

        default:
            TextField(placeholder(for: field), text: binding)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .fill(Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .strokeBorder(Theme.border, lineWidth: 0.5)
                )
        }
    }

    private func resizableTextInput(text: Binding<String>, placeholder: String, borderColor: Color) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
            }
            TextEditor(text: text)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .frame(minHeight: 32, maxHeight: 200)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func placeholder(for field: Google_Protobuf_FieldDescriptorProto) -> String {
        if field.label == .repeated {
            return "value1, value2, ..."
        }
        switch field.type {
        case .string: return "Enter text..."
        case .bytes: return "Raw text or base64..."
        case .int32, .int64, .sint32, .sint64, .sfixed32, .sfixed64: return "0"
        case .uint32, .uint64, .fixed32, .fixed64: return "0"
        case .float, .double: return "0.0"
        case .bool: return "true / false"
        case .enum: return "0"
        case .message:
            let name = field.typeName.components(separatedBy: ".").last ?? "object"
            return "{ \(name) as JSON... }"
        default: return "Enter value..."
        }
    }

    private func typeDisplayName(for field: Google_Protobuf_FieldDescriptorProto) -> String {
        switch field.type {
        case .double: return "double"
        case .float: return "float"
        case .int64: return "int64"
        case .uint64: return "uint64"
        case .int32: return "int32"
        case .fixed64: return "fixed64"
        case .fixed32: return "fixed32"
        case .bool: return "bool"
        case .string: return "string"
        case .bytes: return "bytes"
        case .uint32: return "uint32"
        case .sfixed32: return "sfixed32"
        case .sfixed64: return "sfixed64"
        case .sint32: return "sint32"
        case .sint64: return "sint64"
        case .enum:
            return field.typeName.components(separatedBy: ".").last ?? "enum"
        case .message:
            return field.typeName.components(separatedBy: ".").last ?? "message"
        default: return "unknown"
        }
    }

    // MARK: - JSON ↔ Fields

    private func initializeFields() {
        guard messageType.fullName != lastTypeName else { return }
        lastTypeName = messageType.fullName

        var newValues: [String: String] = [:]
        for field in messageType.descriptor.field {
            newValues[field.name] = ""
        }
        fieldValues = newValues
        populateFromExistingJson()
    }

    private func populateFromExistingJson() {
        guard let data = jsonText.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        for field in messageType.descriptor.field {
            guard let value = dict[field.name] ?? dict[field.jsonName] else { continue }

            if field.label == .repeated, let arr = value as? [Any] {
                fieldValues[field.name] = arr.map { formatValue($0) }.joined(separator: ", ")
                continue
            }

            switch field.type {
            case .bytes:
                if let str = value as? String,
                   let decoded = Data(base64Encoded: str, options: .ignoreUnknownCharacters),
                   let text = String(data: decoded, encoding: .utf8) {
                    fieldValues[field.name] = text
                } else {
                    fieldValues[field.name] = value as? String ?? formatValue(value)
                }
            case .bool:
                if let b = value as? Bool {
                    fieldValues[field.name] = b ? "true" : "false"
                } else {
                    fieldValues[field.name] = formatValue(value)
                }
            case .message:
                if let nested = value as? [String: Any],
                   let nestedData = try? JSONSerialization.data(withJSONObject: nested, options: [.prettyPrinted, .sortedKeys]),
                   let nestedStr = String(data: nestedData, encoding: .utf8) {
                    fieldValues[field.name] = nestedStr
                }
            default:
                let str = formatValue(value)
                if str.hasSuffix(".0"),
                   field.type != .float && field.type != .double {
                    fieldValues[field.name] = String(str.dropLast(2))
                } else {
                    fieldValues[field.name] = str
                }
            }
        }
    }

    private func formatValue(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber {
            if n === kCFBooleanTrue { return "true" }
            if n === kCFBooleanFalse { return "false" }
        }
        return "\(value)"
    }

    private func rebuildJson() {
        var dict: [String: Any] = [:]

        for field in messageType.descriptor.field {
            let raw = fieldValues[field.name] ?? ""
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            if field.label == .repeated {
                let values = parseRepeatedValue(raw, type: field.type)
                if !values.isEmpty {
                    dict[field.name] = values
                }
            } else if let converted = convertValue(raw, type: field.type) {
                dict[field.name] = converted
            }
        }

        if dict.isEmpty {
            jsonText = "{}"
            onChanged()
            return
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            jsonText = str
            onChanged()
        }
    }

    private func convertValue(_ str: String, type: Google_Protobuf_FieldDescriptorProto.TypeEnum) -> Any? {
        switch type {
        case .string:
            return str
        case .bytes:
            return Data(str.utf8).base64EncodedString()
        case .bool:
            return str.lowercased() == "true" || str == "1"
        case .int32, .sint32, .sfixed32:
            return Int(str)
        case .int64, .sint64, .sfixed64:
            if let i = Int64(str) { return i }
            return Int(str)
        case .uint32, .fixed32:
            return UInt32(str)
        case .uint64, .fixed64:
            return UInt64(str)
        case .float:
            return Float(str)
        case .double:
            return Double(str)
        case .enum:
            return Int(str)
        case .message:
            if let data = str.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
            return nil
        default:
            return str
        }
    }

    private func parseRepeatedValue(_ str: String, type: Google_Protobuf_FieldDescriptorProto.TypeEnum) -> [Any] {
        if str.trimmingCharacters(in: .whitespaces).hasPrefix("["),
           let data = str.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return arr
        }
        let parts = str.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.compactMap { convertValue($0, type: type) }
    }

    private func clearAllFields() {
        for key in fieldValues.keys {
            fieldValues[key] = ""
        }
        jsonText = "{}"
        onChanged()
    }
}
