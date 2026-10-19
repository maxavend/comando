import SwiftUI

/// A circular Liquid Glass button with an exact size, so it lines up with the
/// composer field. System glass button styles size themselves from their label.
struct GlassCircleButtonStyle: ButtonStyle {
    enum Role: Equatable {
        case standard
        case prominent
        case destructive
        /// Apple Intelligence will answer: filled with its colors.
        /// `working` while it answers.
        case intelligence(working: Bool)
    }

    var role: Role = .standard

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: Metrics.composerControlSize, height: Metrics.composerControlSize)
            .background {
                // Lit while it answers too, when there's nothing to send.
                if case .intelligence(let working) = role {
                    IntelligenceFill(isWorking: working)
                }
            }
            .contentShape(.circle)
            .glassEffect(glass, in: .circle)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    private var glass: Glass {
        switch role {
        case .prominent where isEnabled: .regular.tint(.accentColor).interactive()
        // Clear glass keeps the colors underneath vivid.
        case .intelligence: .clear.interactive()
        default: .regular.interactive()
        }
    }

    private var foreground: AnyShapeStyle {
        if case .intelligence = role { return AnyShapeStyle(.white) }
        guard isEnabled else { return AnyShapeStyle(.tertiary) }
        switch role {
        case .standard: return AnyShapeStyle(.primary)
        case .prominent, .intelligence: return AnyShapeStyle(.white)
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
