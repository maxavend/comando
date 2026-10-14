import AppKit
import SwiftUI

/// Terminal colors that adapt to light and dark appearance, so output stays
/// legible on the system bubble background in both modes.
nonisolated enum TerminalPalette {
    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? dark : light
        }
    }

    private static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// The 16 ANSI colors. Black and white are mapped to label colors so they
    /// never disappear against the bubble.
    static let ansi: [NSColor] = [
        .labelColor,                                              // 0 black
        dynamic(light: srgb(0xC4_1A_16), dark: srgb(0xFF_6B_63)), // 1 red
        dynamic(light: srgb(0x1F_8A_3B), dark: srgb(0x5F_D3_7A)), // 2 green
        dynamic(light: srgb(0x9A_6B_00), dark: srgb(0xF2_C8_4B)), // 3 yellow
        dynamic(light: srgb(0x0B_5F_D6), dark: srgb(0x6A_A9_FF)), // 4 blue
        dynamic(light: srgb(0xA2_2E_B8), dark: srgb(0xE0_8B_F0)), // 5 magenta
        dynamic(light: srgb(0x0E_7C_86), dark: srgb(0x5C_D6_E0)), // 6 cyan
        .secondaryLabelColor,                                     // 7 white
        .secondaryLabelColor,                                     // 8 bright black
        dynamic(light: srgb(0xE0_2F_28), dark: srgb(0xFF_8A_80)), // 9 bright red
        dynamic(light: srgb(0x2B_A3_4C), dark: srgb(0x8C_EE_A0)), // 10 bright green
        dynamic(light: srgb(0xB3_80_00), dark: srgb(0xFF_DE_7A)), // 11 bright yellow
        dynamic(light: srgb(0x2F_7B_F0), dark: srgb(0x9A_C5_FF)), // 12 bright blue
        dynamic(light: srgb(0xBF_4F_D4), dark: srgb(0xF0_B0_FA)), // 13 bright magenta
        dynamic(light: srgb(0x12_96_A1), dark: srgb(0x8D_EC_F2)), // 14 bright cyan
        .labelColor,                                              // 15 bright white
    ]

    static func nsColor(_ color: TermColor) -> NSColor {
        switch color {
        case .ansi(let index):
            return ansi[Int(index) & 0x0F]
        case .palette(let index):
            let value = Int(index)
            if value < 16 { return ansi[value] }
            if value >= 232 {
                let level = CGFloat(8 + (value - 232) * 10) / 255
                return NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
            }
            let cube = value - 16
            let steps: [CGFloat] = [0, 95, 135, 175, 215, 255]
            return NSColor(
                srgbRed: steps[cube / 36] / 255,
                green: steps[(cube / 6) % 6] / 255,
                blue: steps[cube % 6] / 255,
                alpha: 1
            )
        case .rgb(let r, let g, let b):
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
    }
}
