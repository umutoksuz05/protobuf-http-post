import SwiftUI

/// A TextField that shows a dropdown of {{variable}} suggestions when the user types "{{".
/// It reads available variable keys from the workspace via AppState.
struct VariableTextField: View {
    @Binding var text: String
    var placeholder: String = ""
    var font: Font = .system(size: 12, design: .monospaced)
    
    @EnvironmentObject var appState: AppState
    @State private var showSuggestions = false
    @State private var suggestions: [String] = []
    @State private var cursorVariableRange: Range<String.Index>?
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(font)
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    updateSuggestions(for: newValue)
                }
            
            if showSuggestions && !suggestions.isEmpty && isFocused {
                suggestionsDropdown
            }
        }
    }
    
    private var suggestionsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions, id: \.self) { variable in
                Button(action: {
                    applySuggestion(variable)
                }) {
                    HStack(spacing: 6) {
                        Text("{{\(variable)}}")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.jsonKey)
                        
                        Spacer()
                        
                        // Show the value preview if available
                        if let value = appState.selectedWorkspace?.allVariables()[variable] {
                            Text(value.count > 30 ? String(value.prefix(30)) + "..." : value)
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.clear)
                .onHover { hovering in
                    // Hover effect handled by the background below
                }
                
                if variable != suggestions.last {
                    Divider()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.surfaceElevated)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.border, lineWidth: 0.5)
        )
        .frame(maxHeight: 200)
        .zIndex(100)
    }
    
    private func updateSuggestions(for text: String) {
        // Find the last occurrence of "{{" that isn't closed
        guard let openIndex = findOpenVariableToken(in: text) else {
            showSuggestions = false
            suggestions = []
            return
        }
        
        let partialKey = String(text[text.index(openIndex, offsetBy: 2)...])
        let allKeys = availableVariableKeys()
        
        if partialKey.isEmpty {
            suggestions = allKeys
        } else {
            suggestions = allKeys.filter { $0.lowercased().contains(partialKey.lowercased()) }
        }
        
        showSuggestions = !suggestions.isEmpty
    }
    
    private func findOpenVariableToken(in text: String) -> String.Index? {
        // Look for the last "{{" that doesn't have a matching "}}"
        guard let lastOpen = text.range(of: "{{", options: .backwards)?.lowerBound else {
            return nil
        }
        
        let afterOpen = text[text.index(lastOpen, offsetBy: 2)...]
        // If there's a "}}" after the last "{{", it's closed
        if afterOpen.contains("}}") {
            return nil
        }
        
        return lastOpen
    }
    
    private func applySuggestion(_ variable: String) {
        // Find the last "{{" and replace from there to end with "{{variable}}"
        if let lastOpen = text.range(of: "{{", options: .backwards) {
            let prefix = String(text[text.startIndex..<lastOpen.lowerBound])
            text = prefix + "{{\(variable)}}"
        }
        showSuggestions = false
        suggestions = []
    }
    
    private func availableVariableKeys() -> [String] {
        guard let workspace = appState.selectedWorkspace else { return [] }
        
        var keys: [String] = []
        
        // Workspace settings variables
        if !workspace.settings.baseUrl.isEmpty {
            keys.append("baseUrl")
            keys.append("base_url")
        }
        if !workspace.settings.authToken.isEmpty {
            keys.append("authToken")
            keys.append("auth_token")
        }
        if !workspace.settings.basicAuthUsername.isEmpty {
            keys.append("basicAuthUsername")
            keys.append("basic_auth_username")
        }
        if !workspace.settings.basicAuthPassword.isEmpty {
            keys.append("basicAuthPassword")
            keys.append("basic_auth_password")
        }
        
        // Environment variables
        if let env = workspace.selectedEnvironment {
            for variable in env.variables where variable.enabled && !variable.key.isEmpty {
                if !keys.contains(variable.key) {
                    keys.append(variable.key)
                }
            }
        }
        
        return keys
    }
}

#Preview {
    VariableTextField(text: .constant("{{"), placeholder: "Enter value...")
        .environmentObject(AppState())
        .frame(width: 300)
        .padding()
}
