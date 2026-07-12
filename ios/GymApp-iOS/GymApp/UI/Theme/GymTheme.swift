import SwiftUI
import UIKit

/// Shared visual tokens for the native GymApp interface.
///
/// The palette mirrors the Android Material 3 implementation while using
/// dynamic system colors so every token responds to light and dark mode.
public enum GymTheme {
    public static let primary = adaptive(light: 0x3F806A, dark: 0x95D6BD)
    public static let secondary = adaptive(light: 0x35627E, dark: 0x79B8FF)
    public static let tertiary = adaptive(light: 0xC26E45, dark: 0xF2B183)

    public static let background = adaptive(light: 0xEAF1F5, dark: 0x04070C)
    public static let backgroundRaised = adaptive(light: 0xF4F7F8, dark: 0x09111B)
    public static let surface = adaptive(light: 0xFFFFFF, dark: 0x101824)
    public static let surfaceVariant = adaptive(light: 0xDDE7EB, dark: 0x182534)

    public static let textPrimary = adaptive(light: 0x14212D, dark: 0xF6FBFF)
    public static let textSecondary = adaptive(light: 0x5B6975, dark: 0xB9C8D4)
    public static let outline = adaptive(light: 0xB3C2CB, dark: 0x4E6A7A)
    public static let outlineSoft = adaptive(light: 0xFFFFFF, dark: 0x304354)
    public static let error = adaptive(light: 0xB3261E, dark: 0xFFB4AB)

    public static let heroLeading = adaptive(light: 0x102A42, dark: 0x132636)
    public static let heroTrailing = adaptive(light: 0x35627E, dark: 0x214C40)
    public static let onHero = Color.white

    public static let panelCornerRadius: CGFloat = 28
    public static let compactCornerRadius: CGFloat = 18
    public static let controlCornerRadius: CGFloat = 16

    public static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundRaised, background, surfaceVariant.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
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

/// Full-screen adaptive gradient and glass glow used behind GymApp screens.
public struct GymBackground<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(GymTheme.backgroundGradient)
                .ignoresSafeArea()

            if !reduceTransparency {
                GeometryReader { proxy in
                    ZStack {
                        Circle()
                            .fill(GymTheme.primary.opacity(0.17))
                            .frame(width: min(proxy.size.width * 0.92, 420))
                            .blur(radius: 68)
                            .offset(x: proxy.size.width * 0.34, y: -proxy.size.height * 0.28)

                        Circle()
                            .fill(GymTheme.secondary.opacity(0.13))
                            .frame(width: min(proxy.size.width * 0.82, 360))
                            .blur(radius: 74)
                            .offset(x: -proxy.size.width * 0.36, y: proxy.size.height * 0.32)

                        Circle()
                            .fill(GymTheme.tertiary.opacity(0.09))
                            .frame(width: min(proxy.size.width * 0.64, 290))
                            .blur(radius: 62)
                            .offset(x: proxy.size.width * 0.36, y: proxy.size.height * 0.42)
                    }
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }

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
