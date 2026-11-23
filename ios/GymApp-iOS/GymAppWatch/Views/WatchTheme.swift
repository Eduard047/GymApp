import SwiftUI

/// Flat tonal tokens (watch UI spec §2). No gradients, glow or shadows.
enum WatchTheme {
    static let background = Color(hex: 0x000000)
    static let surface = Color(hex: 0x1C1C1E)
    static let surfaceHigh = Color(hex: 0x2C2C2E)
    static let accent = Color(hex: 0x0A84FF)
    static let accentTonal = Color(hex: 0x02203D)
    static let text = Color(hex: 0xFFFFFF)
    static let textSecondary = Color(hex: 0xAEAEB2)
    static let destructive = Color(hex: 0xFF453A)
    static let destructiveTonal = Color(hex: 0x330E0C)
    static let success = Color(hex: 0x30D158)
    static let warning = Color(hex: 0xFF9F0A)

    static func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return Color(hex: 0x8E8E93)
        case 2: return Color(hex: 0x64D2FF)
        case 3: return Color(hex: 0x30D158)
        case 4: return Color(hex: 0xFF9F0A)
        default: return Color(hex: 0xFF453A)
        }
    }

    static let heroWork = Font.system(.title2, design: .rounded).weight(.semibold)
    static let heroRest = Font.system(.largeTitle, design: .rounded).weight(.semibold)
}

extension Color {
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

/// Full-width tonal button fill used for secondary and destructive actions.
struct TonalButtonStyle: ButtonStyle {
    var fill: Color = WatchTheme.surfaceHigh
    var foreground: Color = WatchTheme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The single filled accent button on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(WatchTheme.text)
            .multilineTextAlignment(.center)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(WatchTheme.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
