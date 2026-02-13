import Foundation

class VariableService {
    
    /// Regex pattern to match {{variableName}}
    private static let variablePattern = try! NSRegularExpression(
        pattern: "\\{\\{([^}]+)\\}\\}",
        options: []
    )
    
    /// Replace all {{variable}} placeholders in a string with their values
    static func substitute(_ text: String, variables: [String: String]) -> String {
        guard !text.isEmpty else { return text }
        
        var result = text
        let range = NSRange(text.startIndex..., in: text)
        
        // Find all matches in reverse order to preserve indices
        let matches = variablePattern.matches(in: text, options: [], range: range)
        
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let keyRange = Range(match.range(at: 1), in: result) else {
                continue
            }
            
            let key = String(result[keyRange]).trimmingCharacters(in: .whitespaces)
            
            if let value = variables[key] {
                result.replaceSubrange(fullRange, with: value)
            }
            // If variable not found, leave it as-is (so user can see it's not resolved)
        }
        
        return result
    }
    
    /// Find all variable names used in a string
    static func findVariables(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        
        var variables: [String] = []
        let range = NSRange(text.startIndex..., in: text)
        let matches = variablePattern.matches(in: text, options: [], range: range)
        
        for match in matches {
            if let keyRange = Range(match.range(at: 1), in: text) {
                let key = String(text[keyRange]).trimmingCharacters(in: .whitespaces)
                if !variables.contains(key) {
                    variables.append(key)
                }
            }
        }
        
        return variables
    }
    
    /// Check if a string contains any variable placeholders
    static func containsVariables(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return variablePattern.firstMatch(in: text, options: [], range: range) != nil
    }
    
    /// Highlight variables in text by returning ranges of {{variable}} occurrences
    static func variableRanges(in text: String) -> [Range<String.Index>] {
        guard !text.isEmpty else { return [] }
        
        var ranges: [Range<String.Index>] = []
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = variablePattern.matches(in: text, options: [], range: nsRange)
        
        for match in matches {
            if let range = Range(match.range, in: text) {
                ranges.append(range)
            }
        }
        
        return ranges
    }
}
