import SwiftUI
import AppKit

enum JsonViewMode: String, CaseIterable, Identifiable {
    case text = "Text"
    case tree = "Tree"
    
    var id: String { rawValue }
}

struct SmartJsonEditor: View {
    @Binding var text: String
    var placeholder: String = "Enter JSON..."
    var isEditable: Bool = true
    
    @State private var viewMode: JsonViewMode = .text
    @State private var jsonError: String?
    @State private var parsedJson: Any?
    @State private var isValid: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                // View mode picker
                Picker("", selection: $viewMode) {
                    ForEach(JsonViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                
                Divider()
                    .frame(height: 16)
                
                // Validation indicator
                HStack(spacing: 4) {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isValid ? Theme.success : Theme.error)
                        .font(.system(size: 11))
                    Text(isValid ? "Valid" : "Invalid")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isValid ? Theme.success : Theme.error)
                }
                
                Spacer()
                
                // Action buttons
                if isEditable {
                    Button(action: formatJson) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Format JSON")
                    .disabled(text.isEmpty)
                    
                    Button(action: minifyJson) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Minify JSON")
                    .disabled(text.isEmpty)
                }
                
                Button(action: { copyToClipboard(text) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .help("Copy")
                .disabled(text.isEmpty)
                
                if isEditable {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(ToolbarIconButtonStyle())
                    .help("Clear")
                    .disabled(text.isEmpty)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.surface.opacity(0.8))
            
            Divider()
            
            // Error message
            if let error = jsonError, !isValid {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.warning)
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.warning.opacity(0.06))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Content
            Group {
                switch viewMode {
                case .text:
                    if isEditable {
                        MacTextEditor(text: $text, placeholder: placeholder, jsonHighlighting: true)
                            .onChange(of: text) { _, _ in
                                validateJson()
                            }
                    } else {
                        ScrollView {
                            Text(text.isEmpty ? placeholder : text)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(text.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                    }
                    
                case .tree:
                    if let json = parsedJson {
                        ScrollView {
                            JsonTreeView(value: json, key: "root", depth: 0)
                                .padding(8)
                        }
                    } else {
                        VStack {
                            Spacer()
                            Text("Enter valid JSON to see tree view")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textTertiary)
                            Spacer()
                        }
                    }
                }
            }
            .animation(Theme.smooth, value: viewMode)
        }
        .animation(Theme.smooth, value: isValid)
        .onAppear {
            validateJson()
        }
    }
    
    private func validateJson() {
        guard !text.isEmpty else {
            isValid = true
            jsonError = nil
            parsedJson = nil
            return
        }
        
        guard let data = text.data(using: .utf8) else {
            isValid = false
            jsonError = "Invalid UTF-8 encoding"
            parsedJson = nil
            return
        }
        
        do {
            parsedJson = try JSONSerialization.jsonObject(with: data)
            isValid = true
            jsonError = nil
        } catch let error as NSError {
            isValid = false
            jsonError = error.localizedDescription
            parsedJson = nil
        }
    }
    
    private func formatJson() {
        guard let data = text.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return
        }
        text = prettyString
    }
    
    private func minifyJson() {
        guard let data = text.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let minifiedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.withoutEscapingSlashes]),
              let minifiedString = String(data: minifiedData, encoding: .utf8) else {
            return
        }
        text = minifiedString
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - JSON Tree View

struct JsonTreeView: View {
    let value: Any
    let key: String
    let depth: Int
    
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let dict = value as? [String: Any] {
                objectView(dict)
            } else if let array = value as? [Any] {
                arrayView(array)
            } else {
                primitiveView
            }
        }
    }
    
    private func objectView(_ dict: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button(action: {
                    withAnimation(Theme.quick) { isExpanded.toggle() }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
                
                if key != "root" {
                    Text("\"\(key)\":")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Theme.jsonKey)
                }
                
                Text("{")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                
                if !isExpanded {
                    Text("...}")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Theme.textTertiary)
                }
                
                Text("\(dict.count) keys")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.surfaceHover))
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(dict.keys.sorted(), id: \.self) { childKey in
                        if let childValue = dict[childKey] {
                            JsonTreeView(value: childValue, key: childKey, depth: depth + 1)
                                .padding(.leading, 16)
                        }
                    }
                }
                
                Text("}")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.leading, 12)
            }
        }
    }
    
    private func arrayView(_ array: [Any]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button(action: {
                    withAnimation(Theme.quick) { isExpanded.toggle() }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
                
                if key != "root" {
                    Text("\"\(key)\":")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Theme.jsonKey)
                }
                
                Text("[")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                
                if !isExpanded {
                    Text("...]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Theme.textTertiary)
                }
                
                Text("\(array.count) items")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.surfaceHover))
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(array.enumerated()), id: \.offset) { index, childValue in
                        JsonTreeView(value: childValue, key: "[\(index)]", depth: depth + 1)
                            .padding(.leading, 16)
                    }
                }
                
                Text("]")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.leading, 12)
            }
        }
    }
    
    private var primitiveView: some View {
        HStack(spacing: 4) {
            Spacer()
                .frame(width: 12)
            
            if key != "root" && !key.hasPrefix("[") {
                Text("\"\(key)\":")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.jsonKey)
            } else if key.hasPrefix("[") {
                Text("\(key):")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            }
            
            valueText
        }
    }
    
    @ViewBuilder
    private var valueText: some View {
        if let string = value as? String {
            Text("\"\(string)\"")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.jsonString)
        } else if let number = value as? NSNumber {
            if number === kCFBooleanTrue || number === kCFBooleanFalse {
                Text(number.boolValue ? "true" : "false")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundColor(Theme.jsonBool)
            } else {
                Text("\(number)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.jsonNumber)
            }
        } else if value is NSNull {
            Text("null")
                .font(.system(.caption, design: .monospaced).italic())
                .foregroundColor(Theme.jsonNull)
        } else {
            Text("\(String(describing: value))")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
        }
    }
}

#Preview {
    SmartJsonEditor(text: .constant("""
    {
        "name": "John",
        "age": 30,
        "active": true,
        "address": {
            "city": "New York",
            "zip": "10001"
        },
        "tags": ["developer", "swift"]
    }
    """))
    .frame(width: 400, height: 400)
}
