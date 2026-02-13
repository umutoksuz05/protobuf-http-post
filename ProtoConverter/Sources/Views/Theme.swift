import SwiftUI
import AppKit

// MARK: - Theme Colors

struct Theme {
    
    // MARK: Surfaces
    static var windowBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var surface: Color { Color(nsColor: .controlBackgroundColor) }
    static var surfaceElevated: Color { Color(nsColor: .textBackgroundColor) }
    static var surfaceHover: Color { Color.primary.opacity(0.06) }
    static var surfaceActive: Color { Color.accentColor.opacity(0.12) }
    
    // MARK: Borders & Separators
    static var border: Color { Color.primary.opacity(0.08) }
    static var borderSubtle: Color { Color.primary.opacity(0.05) }
    static var borderActive: Color { Color.accentColor.opacity(0.4) }
    
    // MARK: Text
    static var textPrimary: Color { Color.primary }
    static var textSecondary: Color { Color.secondary }
    static var textTertiary: Color { Color.secondary.opacity(0.6) }
    static var textOnAccent: Color { Color.white }
    
    // MARK: Status Colors
    static var success: Color { Color(red: 0.2, green: 0.78, blue: 0.45) }
    static var error: Color { Color(red: 0.95, green: 0.3, blue: 0.3) }
    static var warning: Color { Color(red: 1.0, green: 0.72, blue: 0.25) }
    static var info: Color { Color(red: 0.35, green: 0.6, blue: 0.95) }
    
    // MARK: HTTP Method Colors
    static func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return Color(red: 0.35, green: 0.6, blue: 0.95)
        case "POST": return Color(red: 0.2, green: 0.78, blue: 0.45)
        case "PUT": return Color(red: 1.0, green: 0.72, blue: 0.25)
        case "PATCH": return Color(red: 0.65, green: 0.45, blue: 0.95)
        case "DELETE": return Color(red: 0.95, green: 0.3, blue: 0.3)
        default: return Color.gray
        }
    }
    
    // MARK: Status Code Colors
    static func statusColor(for status: String) -> Color {
        if status.hasPrefix("2") { return success }
        if status.hasPrefix("3") { return info }
        if status.hasPrefix("4") { return warning }
        if status.hasPrefix("5") { return error }
        return Color.gray
    }
    
    // MARK: JSON Tree Colors
    static var jsonKey: Color { Color(red: 0.65, green: 0.45, blue: 0.95) }
    static var jsonString: Color { Color(red: 0.2, green: 0.78, blue: 0.45) }
    static var jsonNumber: Color { Color(red: 0.35, green: 0.6, blue: 0.95) }
    static var jsonBool: Color { Color(red: 1.0, green: 0.72, blue: 0.25) }
    static var jsonNull: Color { Color.gray }
    
    // MARK: NSColor equivalents for syntax highlighting
    static var nsJsonKey: NSColor { NSColor(red: 0.65, green: 0.45, blue: 0.95, alpha: 1.0) }
    static var nsJsonString: NSColor { NSColor(red: 0.2, green: 0.78, blue: 0.45, alpha: 1.0) }
    static var nsJsonNumber: NSColor { NSColor(red: 0.35, green: 0.6, blue: 0.95, alpha: 1.0) }
    static var nsJsonBool: NSColor { NSColor(red: 1.0, green: 0.72, blue: 0.25, alpha: 1.0) }
    static var nsJsonNull: NSColor { NSColor.gray }
    static var nsJsonBrace: NSColor { NSColor.secondaryLabelColor }
    
    // MARK: Gradients
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static func statusGradient(for status: String) -> LinearGradient {
        let color = statusColor(for: status)
        return LinearGradient(
            colors: [color.opacity(0.2), color.opacity(0.1)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    static func methodGradient(_ method: String) -> LinearGradient {
        let color = methodColor(method)
        return LinearGradient(
            colors: [color, color.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: Shadows
    static var shadowSubtle: some View {
        Color.black.opacity(0.06)
    }
    
    // MARK: Animation Presets
    static let snappy: Animation = .spring(response: 0.3, dampingFraction: 0.8)
    static let smooth: Animation = .easeInOut(duration: 0.2)
    static let quick: Animation = .easeOut(duration: 0.15)
    
    // MARK: Corner Radii
    static let radiusSmall: CGFloat = 4
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 12
}

// MARK: - Custom Button Styles

struct HoverButtonStyle: ButtonStyle {
    @State private var isHovering = false
    var cornerRadius: CGFloat = Theme.radiusSmall
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(configuration.isPressed ? Theme.surfaceActive :
                            isHovering ? Theme.surfaceHover : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(Theme.quick, value: configuration.isPressed)
            .animation(Theme.quick, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

struct AccentButtonStyle: ButtonStyle {
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(Theme.accentGradient)
                    .opacity(configuration.isPressed ? 0.8 : isHovering ? 0.9 : 1.0)
            )
            .shadow(color: Color.accentColor.opacity(isHovering ? 0.3 : 0.15), radius: isHovering ? 6 : 3, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : isHovering ? 1.02 : 1.0)
            .animation(Theme.snappy, value: configuration.isPressed)
            .animation(Theme.smooth, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

struct ToolbarIconButtonStyle: ButtonStyle {
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundColor(isHovering ? .primary : .secondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Theme.surfaceActive :
                            isHovering ? Theme.surfaceHover : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(Theme.quick, value: configuration.isPressed)
            .animation(Theme.quick, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

struct StatusBadgeStyle: ViewModifier {
    let color: Color
    @State private var appeared = false
    
    func body(content: Content) -> some View {
        content
            .font(.system(.caption, design: .monospaced).weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.2), color.opacity(0.1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .foregroundColor(color)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
            )
            .scaleEffect(appeared ? 1.0 : 0.8)
            .opacity(appeared ? 1.0 : 0)
            .onAppear {
                withAnimation(Theme.snappy) {
                    appeared = true
                }
            }
    }
}

extension View {
    func statusBadge(color: Color) -> some View {
        modifier(StatusBadgeStyle(color: color))
    }
    
    func cardStyle(padding: CGFloat = 0) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .strokeBorder(Theme.border, lineWidth: 0.5)
            )
    }
    
    func panelHeader() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.8))
    }
    
    func subtleShadow() -> some View {
        self.shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
