import SwiftUI
import AppKit

// Custom NSTextView-based editor for better keyboard handling on macOS
struct MacTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var jsonHighlighting: Bool = false
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        textView.delegate = context.coordinator
        textView.isRichText = jsonHighlighting
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        
        // Ensure consistent typing attributes
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]
        
        // Set initial text
        textView.string = text
        
        // Apply initial highlighting
        if jsonHighlighting {
            context.coordinator.highlightJson(textView)
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // IMPORTANT: Update coordinator's parent reference to keep binding in sync
        context.coordinator.parent = self
        
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // Only update text if it actually changed from an external source
        // (not from user typing, which is handled by the coordinator)
        if textView.string != text && !context.coordinator.isUpdating {
            let selectedRange = textView.selectedRange()
            textView.string = text
            // Restore selection if possible
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
            // Re-highlight after external text change
            if jsonHighlighting {
                context.coordinator.highlightJson(textView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacTextEditor
        var isUpdating = false
        
        init(_ parent: MacTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Mark that we're updating to prevent updateNSView from reverting
            isUpdating = true
            parent.text = textView.string
            
            // Apply syntax highlighting
            if parent.jsonHighlighting {
                highlightJson(textView)
            }
            
            // Reset after a short delay to allow SwiftUI to process the update
            DispatchQueue.main.async {
                self.isUpdating = false
            }
        }
        
        // MARK: - Auto-Indent
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard parent.jsonHighlighting else { return false }
            
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                handleNewline(textView)
                return true
            }
            
            // Auto-close braces: when typing }, auto-dedent if appropriate
            return false
        }
        
        private func handleNewline(_ textView: NSTextView) {
            let text = textView.string
            let nsText = text as NSString
            let cursorLocation = textView.selectedRange().location
            
            // Find the current line
            let lineRange = nsText.lineRange(for: NSRange(location: cursorLocation > 0 ? cursorLocation - 1 : 0, length: 0))
            let currentLine = nsText.substring(with: lineRange)
            
            // Calculate leading whitespace of current line
            let leadingWhitespace = String(currentLine.prefix(while: { $0 == " " || $0 == "\t" }))
            
            // Check the character before the cursor (ignoring trailing whitespace on the line)
            let textBeforeCursor = nsText.substring(to: cursorLocation)
            let trimmedBeforeCursor = textBeforeCursor.trimmingCharacters(in: .newlines)
            let lastNonWhitespace = trimmedBeforeCursor.last(where: { !$0.isWhitespace })
            
            // Check character after cursor
            let charAfterCursor: Character? = cursorLocation < text.count
                ? text[text.index(text.startIndex, offsetBy: cursorLocation)]
                : nil
            
            let indent = "    " // 4 spaces
            var insertText: String
            
            let opensBlock = lastNonWhitespace == "{" || lastNonWhitespace == "["
            let closesBlock = charAfterCursor == "}" || charAfterCursor == "]"
            
            if opensBlock && closesBlock {
                // Cursor is between {} or [] -- insert indented line and closing line
                let innerIndent = leadingWhitespace + indent
                insertText = "\n\(innerIndent)\n\(leadingWhitespace)"
                
                textView.insertText(insertText, replacementRange: textView.selectedRange())
                
                // Place cursor on the indented middle line
                let newCursorPos = cursorLocation + 1 + innerIndent.count
                textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))
            } else if opensBlock {
                // Line ends with { or [ -- add extra indent
                insertText = "\n\(leadingWhitespace)\(indent)"
                textView.insertText(insertText, replacementRange: textView.selectedRange())
            } else {
                // Normal newline -- carry forward current indent
                insertText = "\n\(leadingWhitespace)"
                textView.insertText(insertText, replacementRange: textView.selectedRange())
            }
        }
        
        // MARK: - Syntax Highlighting
        
        func highlightJson(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            
            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            
            guard fullRange.length > 0 else { return }
            
            let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            
            // Save selection
            let selectedRange = textView.selectedRange()
            
            textStorage.beginEditing()
            
            // Reset to base style
            textStorage.setAttributes([
                .font: monoFont,
                .foregroundColor: NSColor.textColor
            ], range: fullRange)
            
            // 1. Highlight all strings first (keys + values)
            //    Pattern: "..." including escaped characters
            let stringPattern = try! NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"", options: [])
            let stringMatches = stringPattern.matches(in: text, range: fullRange)
            
            // Build a set of ranges that are keys (string followed by optional whitespace and colon)
            let keyPattern = try! NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"\\s*:", options: [])
            let keyMatches = keyPattern.matches(in: text, range: fullRange)
            
            // Collect key string ranges (just the quoted part, not the colon)
            var keyRanges: [NSRange] = []
            for match in keyMatches {
                // Find the string portion within this key match
                let matchText = (text as NSString).substring(with: match.range)
                if let quoteEnd = matchText.range(of: "\"", options: .backwards, range: matchText.index(matchText.startIndex, offsetBy: 1)..<matchText.endIndex) {
                    let endOffset = matchText.distance(from: matchText.startIndex, to: quoteEnd.upperBound)
                    let keyRange = NSRange(location: match.range.location, length: endOffset)
                    keyRanges.append(keyRange)
                }
            }
            
            // Apply colors: keys get key color, other strings get string color
            for match in stringMatches {
                let isKey = keyRanges.contains(where: { $0.location == match.range.location })
                let color = isKey ? Theme.nsJsonKey : Theme.nsJsonString
                textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
            
            // 2. Numbers (outside of strings)
            let numberPattern = try! NSRegularExpression(pattern: "(?<=[:,\\[\\s])-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?(?=[,\\s\\]\\}]|$)", options: .anchorsMatchLines)
            let numberMatches = numberPattern.matches(in: text, range: fullRange)
            for match in numberMatches {
                if !isInsideString(range: match.range, stringMatches: stringMatches) {
                    textStorage.addAttribute(.foregroundColor, value: Theme.nsJsonNumber, range: match.range)
                }
            }
            
            // 3. Booleans (outside of strings)
            let boolPattern = try! NSRegularExpression(pattern: "\\b(true|false)\\b", options: [])
            let boolMatches = boolPattern.matches(in: text, range: fullRange)
            for match in boolMatches {
                if !isInsideString(range: match.range, stringMatches: stringMatches) {
                    textStorage.addAttribute(.foregroundColor, value: Theme.nsJsonBool, range: match.range)
                }
            }
            
            // 4. Null (outside of strings)
            let nullPattern = try! NSRegularExpression(pattern: "\\bnull\\b", options: [])
            let nullMatches = nullPattern.matches(in: text, range: fullRange)
            for match in nullMatches {
                if !isInsideString(range: match.range, stringMatches: stringMatches) {
                    textStorage.addAttribute(.foregroundColor, value: Theme.nsJsonNull, range: match.range)
                }
            }
            
            // 5. Braces, brackets, colons, commas (outside of strings)
            let bracePattern = try! NSRegularExpression(pattern: "[{}\\[\\],:]", options: [])
            let braceMatches = bracePattern.matches(in: text, range: fullRange)
            for match in braceMatches {
                if !isInsideString(range: match.range, stringMatches: stringMatches) {
                    textStorage.addAttribute(.foregroundColor, value: Theme.nsJsonBrace, range: match.range)
                }
            }
            
            textStorage.endEditing()
            
            // Restore selection
            if selectedRange.location <= (text as NSString).length {
                textView.setSelectedRange(selectedRange)
            }
            
            // Ensure typing attributes stay consistent
            textView.typingAttributes = [
                .font: monoFont,
                .foregroundColor: NSColor.textColor
            ]
        }
        
        /// Check if a range falls inside any string match
        private func isInsideString(range: NSRange, stringMatches: [NSTextCheckingResult]) -> Bool {
            for strMatch in stringMatches {
                if range.location >= strMatch.range.location &&
                   NSMaxRange(range) <= NSMaxRange(strMatch.range) {
                    return true
                }
            }
            return false
        }
    }
}
