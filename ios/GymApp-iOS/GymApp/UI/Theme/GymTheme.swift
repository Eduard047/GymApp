import SwiftUI
import UIKit

/// Shared visual tokens for the native GymApp interface.
///
/// Airy blue-white surfaces keep content quiet while aquatic color is reserved
/// for focus, selection, and progress. Material stays on the functional layer.
public enum GymTheme {
    /// Fluid Focus spacing follows a compact four-point rhythm. Screen code can
    /// use these names instead of drifting between nearly identical insets.
    public enum Spacing {
        public static let xSmall: CGFloat = 4
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 16
        public static let xLarge: CGFloat = 24
        public static let xxLarge: CGFloat = 32
    }

    /// Rounded display type gives Fluid Focus its friendly, athletic voice;
    /// body copy stays neutral and data remains quickly scannable.
    public enum TypeScale {
        public static let screenTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
        public static let sectionTitle = Font.system(.title3, design: .rounded, weight: .bold)
        public static let heroTitle = Font.system(.title2, design: .rounded, weight: .bold)
        public static let metric = Font.system(.title3, design: .rounded, weight: .bold)
        public static let utility = Font.system(.caption, design: .monospaced, weight: .semibold)
    }

    public static let primary = adaptive(light: 0x216BD7, dark: 0x8BB9FF)
    public static let primaryAction = adaptive(light: 0x175BBE, dark: 0x2E72D2)
    /// Brand blue (`active-current` in DESIGN.md) tuned as a *fill* that carries
    /// `onPrimary` (white) text/icons directly on top of it, e.g. a solid button
    /// or hero card background. Unlike `primary` (a light-mode-only accent that
    /// intentionally pales in dark mode for use as foreground/tint), this stays
    /// dark enough in both appearances for white-on-fill contrast: light
    /// #216BD7 keeps ~5.1:1, dark #2E72D2 keeps ~4.7:1 against white.
    public static let brandFill = adaptive(light: 0x216BD7, dark: 0x2E72D2)
    public static let onPrimary = Color.white
    public static let secondary = adaptive(light: 0x23815E, dark: 0x77DDB7)
    public static let tertiary = adaptive(light: 0x6753D6, dark: 0xB4A6FF)

    public static let background = adaptive(light: 0xF7FAFF, dark: 0x071321)
    public static let surface = adaptive(light: 0xFFFFFF, dark: 0x0D1D30)
    public static let surfaceVariant = adaptive(light: 0xEAF2FF, dark: 0x142A43)

    public static let textPrimary = adaptive(light: 0x10233F, dark: 0xF4F8FF)
    public static let textSecondary = adaptive(light: 0x60708A, dark: 0xAABBD1)
    public static let outline = adaptive(light: 0xB7C4D7, dark: 0x49617D)
    public static let outlineSoft = adaptive(light: 0xDCE5F2, dark: 0x263E59)
    public static let error = adaptive(light: 0xB42318, dark: 0xFFB4AC)

    /// Flat tonal hero/brand surface (no gradient): light #EEF4FF, dark #10233A.
    public static let heroSurface = adaptive(light: 0xEEF4FF, dark: 0x10233A)
    /// Hairline border of the tonal hero surface; also the progress track on it.
    public static let heroOutline = adaptive(light: 0xDCE5F2, dark: 0x22395A)
    /// Title and key numbers on `heroSurface` (Clear Label).
    public static let onHero = adaptive(light: 0x10233F, dark: 0xF2F6FC)
    /// Supporting text on `heroSurface` (Muted Label), >= 4.5:1 in both modes.
    public static let onHeroSecondary = adaptive(light: 0x60708A, dark: 0xA7B6CB)
    /// Inner tiles, pills and chips sitting on `heroSurface`.
    public static let heroTile = adaptive(light: 0xFFFFFF, dark: 0x172C47)
    /// The single emphasised value, progress fill and link-like label on `heroSurface`.
    public static let heroAccent = adaptive(light: 0x216BD7, dark: 0x7FB2FF)
    /// Secondary action label on `heroSurface` / `heroTile`.
    public static let heroActionLabel = adaptive(light: 0x216BD7, dark: 0x8AB8FF)

    public static let panelCornerRadius: CGFloat = 26
    public static let compactCornerRadius: CGFloat = 20
    public static let controlCornerRadius: CGFloat = 18
    public static let screenHorizontalInset: CGFloat = 14
    public static let screenVerticalInset: CGFloat = 10
    public static let screenBottomInset: CGFloat = 28
    public static let contentSpacing: CGFloat = 14
    public static let hairlineWidth: CGFloat = 0.75

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
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(GymTheme.background)
                .ignoresSafeArea()

            content
        }
        .foregroundStyle(GymTheme.textPrimary)
        .tint(GymTheme.primary)
    }
}

/// A small iOS 16-compatible replacement for SwiftUI's iOS 17
/// `ContentUnavailableView`.
public struct GymContentUnavailableView: View {
    private let label: AnyView
    private let description: AnyView
    private let actions: AnyView

    public init<LabelContent: View, DescriptionContent: View, ActionsContent: View>(
        @ViewBuilder label: () -> LabelContent,
        @ViewBuilder description: () -> DescriptionContent,
        @ViewBuilder actions: () -> ActionsContent
    ) {
        self.label = AnyView(label())
        self.description = AnyView(description())
        self.actions = AnyView(actions())
    }

    public init<LabelContent: View, DescriptionContent: View>(
        @ViewBuilder label: () -> LabelContent,
        @ViewBuilder description: () -> DescriptionContent
    ) {
        self.init(label: label, description: description, actions: { EmptyView() })
    }

    public init(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: Text
    ) {
        self.init(
            label: { Label(title, systemImage: systemImage) },
            description: { description },
            actions: { EmptyView() }
        )
    }

    public static func search(text: String) -> GymContentUnavailableView {
        GymContentUnavailableView {
            Label("No results", systemImage: "magnifyingglass")
        } description: {
            if text.isEmpty {
                Text("Try a different filter.")
            } else {
                Text("No results for \u{201c}\(text)\u{201d}.")
            }
        }
    }

    public var body: some View {
        VStack(spacing: GymTheme.Spacing.medium) {
            label
                .font(GymTheme.TypeScale.sectionTitle)
                .foregroundStyle(GymTheme.textPrimary)
            description
                .font(.subheadline)
                .foregroundStyle(GymTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            actions
                .padding(.top, GymTheme.Spacing.xSmall)
        }
        .padding(.horizontal, GymTheme.Spacing.large)
        .padding(.vertical, GymTheme.Spacing.xLarge)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
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
