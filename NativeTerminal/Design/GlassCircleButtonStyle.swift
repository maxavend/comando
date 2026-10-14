import SwiftUI

/// A circular Liquid Glass button with an exact size, so it lines up with the
/// composer field. System glass button styles size themselves from their label.
struct GlassCircleButtonStyle: ButtonStyle {
    enum Role {
        case standard
        case prominent
        case destructive
    }

    var role: Role = .standard

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: Metrics.composerControlSize, height: Metrics.composerControlSize)
            .contentShape(.circle)
            .glassEffect(glass, in: .circle)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    private var glass: Glass {
        role == .prominent && isEnabled
            ? .regular.tint(.accentColor).interactive()
            : .regular.interactive()
    }

    private var foreground: AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(.tertiary) }
        switch role {
        case .standard: return AnyShapeStyle(.primary)
        case .prominent: return AnyShapeStyle(.white)
        case .destructive: return AnyShapeStyle(.red)
        }
    }
}

extension ButtonStyle where Self == GlassCircleButtonStyle {
    static var glassCircle: GlassCircleButtonStyle { GlassCircleButtonStyle() }

    static func glassCircle(_ role: GlassCircleButtonStyle.Role) -> GlassCircleButtonStyle {
        GlassCircleButtonStyle(role: role)
    }
}
