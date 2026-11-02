import SwiftUI

enum AppPalette {
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x0A1014) : Color(nsColor: .windowBackgroundColor)
    }

    static func chrome(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x10181D) : Color(nsColor: .windowBackgroundColor)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x19262B) : Color(nsColor: .controlBackgroundColor)
    }

    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x121D22) : Color(nsColor: .controlBackgroundColor)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x86C9BB) : .accentColor
    }

    static func base(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x6C7B8B) : .secondary
    }

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? base(scheme).opacity(0.32) : Color.secondary.opacity(0.18)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x97A7AC) : .secondary
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
