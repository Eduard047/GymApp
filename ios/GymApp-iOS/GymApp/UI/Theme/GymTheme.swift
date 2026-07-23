import SwiftUI
import UIKit

/// Shared visual tokens for the native GymApp interface.
///
/// Airy blue-white surfaces keep content quiet while aquatic color is reserved
/// for focus, selection, and progress. Material stays on the functional layer.
public enum GymTheme {
    public static let primary = adaptive(light: 0x216BD7, dark: 0x8BB9FF)
    public static let primaryAction = adaptive(light: 0x175BBE, dark: 0x2E72D2)
    public static let onPrimary = Color.white
    public static let secondary = adaptive(light: 0x23815E, dark: 0x77DDB7)
    public static let tertiary = adaptive(light: 0x6753D6, dark: 0xB4A6FF)

    public static let background = adaptive(light: 0xF7FAFF, dark: 0x071321)
    public static let backgroundRaised = adaptive(light: 0xFBFDFF, dark: 0x0A1829)
    public static let surface = adaptive(light: 0xFFFFFF, dark: 0x0D1D30)
    public static let surfaceVariant = adaptive(light: 0xEAF2FF, dark: 0x142A43)

    public static let textPrimary = adaptive(light: 0x10233F, dark: 0xF4F8FF)
    public static let textSecondary = adaptive(light: 0x60708A, dark: 0xAABBD1)
    public static let outline = adaptive(light: 0xB7C4D7, dark: 0x49617D)
    public static let outlineSoft = adaptive(light: 0xDCE5F2, dark: 0x263E59)
    public static let error = adaptive(light: 0xB42318, dark: 0xFFB4AC)

    public static let heroLeading = adaptive(light: 0x1A71D8, dark: 0x124A96)
    public static let heroTrailing = adaptive(light: 0x2F91EF, dark: 0x176FC5)
    public static let onHero = Color.white

    public static let panelCornerRadius: CGFloat = 26
    public static let compactCornerRadius: CGFloat = 20
    public static let controlCornerRadius: CGFloat = 18

    public static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundRaised, background],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [heroLeading, heroTrailing],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

/// Quiet full-screen canvas shared by GymApp screens.
public struct GymBackground<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ZStack {
            Group {
                if reduceTransparency {
                    Rectangle().fill(GymTheme.background)
                } else {
                    Rectangle().fill(GymTheme.backgroundGradient)
                }
            }
            .ignoresSafeArea()

            content
        }
        .foregroundStyle(GymTheme.textPrimary)
        .tint(GymTheme.primary)
    }
}

private extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}
