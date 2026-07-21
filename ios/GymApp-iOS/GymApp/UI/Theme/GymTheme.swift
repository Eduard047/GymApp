import SwiftUI
import UIKit

/// Shared visual tokens for the native GymApp interface.
///
/// Warm paper surfaces keep the light appearance calm and editorial, while the
/// dark appearance uses deep ink-blue layers. Cobalt is reserved for actions,
/// selection, and progress instead of tinting every surface.
public enum GymTheme {
    public static let primary = adaptive(light: 0x315BD9, dark: 0x89A2FF)
    public static let primaryAction = adaptive(light: 0x294FC2, dark: 0x3D5FCB)
    public static let onPrimary = Color.white
    public static let secondary = adaptive(light: 0x49677E, dark: 0x9AB8CC)
    public static let tertiary = adaptive(light: 0xA7602A, dark: 0xE7A46D)

    public static let background = adaptive(light: 0xF3F0E8, dark: 0x080F1B)
    public static let backgroundRaised = adaptive(light: 0xF8F6F0, dark: 0x0B1422)
    public static let surface = adaptive(light: 0xFFFEFA, dark: 0x111C2B)
    public static let surfaceVariant = adaptive(light: 0xECE8DE, dark: 0x1A2738)

    public static let textPrimary = adaptive(light: 0x18212C, dark: 0xF5F2EA)
    public static let textSecondary = adaptive(light: 0x626B75, dark: 0xB8C1CD)
    public static let outline = adaptive(light: 0xC8C2B6, dark: 0x455368)
    public static let outlineSoft = adaptive(light: 0xDDD7CB, dark: 0x2B394D)
    public static let error = adaptive(light: 0xB42318, dark: 0xFFB4AC)

    public static let heroLeading = adaptive(light: 0x17284A, dark: 0x182846)
    public static let heroTrailing = adaptive(light: 0x254CB3, dark: 0x294DA6)
    public static let onHero = Color.white

    public static let panelCornerRadius: CGFloat = 20
    public static let compactCornerRadius: CGFloat = 16
    public static let controlCornerRadius: CGFloat = 14

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
