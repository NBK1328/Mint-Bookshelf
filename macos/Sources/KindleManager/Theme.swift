import SwiftUI

enum AppPalette {
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x0B0E13) : Color(nsColor: .windowBackgroundColor)
    }

    static func chrome(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x10141B) : Color(nsColor: .windowBackgroundColor)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x171C25) : Color(nsColor: .controlBackgroundColor)
    }

    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x121720) : Color(nsColor: .controlBackgroundColor)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x7FC8B8) : .accentColor
    }

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2B3443) : Color.secondary.opacity(0.18)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xA0A9B8) : .secondary
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
