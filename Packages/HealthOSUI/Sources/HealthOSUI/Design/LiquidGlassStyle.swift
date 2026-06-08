import SwiftUI

public struct GlassCard: ViewModifier {
    public init() {}
    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.glassBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

public struct GlassChip: ViewModifier {
    public init() {}
    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
    }
}

public struct GlassButton: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

public extension View {
    func glassCard() -> some View {
        self.modifier(GlassCard())
    }
    
    func glassChip() -> some View {
        self.modifier(GlassChip())
    }
}
