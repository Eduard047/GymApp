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
    public static let primaryAction = adaptive(light: 0x216BD7, dark: 0x2E72D2)
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
    /// Text/icons on a solid `error` fill (`on-destructive` in DESIGN.md): white on
    /// light #B42318, deep red #690005 on the pale dark-mode #FFB4AC.
    public static let onError = adaptive(light: 0xFFFFFF, dark: 0x690005)
    /// Caution (`warning` in DESIGN.md): light #C87908, dark #FFC56B.
    public static let warning = adaptive(light: 0xC87908, dark: 0xFFC56B)

    /// Flat tonal hero/brand surface (no gradient): light #EEF4FF, dark #10233A.
    public static let heroSurface = adaptive(light: 0xEEF4FF, dark: 0x10233A)
    /// Hairline border of the tonal hero surface; also the progress track on it.
    public static let heroOutline = adaptive(light: 0xDCE5F2, dark: 0x22395A)
    /// Title and key numbers on `heroSurface` (Clear Label).
    public static let onHero = adaptive(light: 0x10233F, dark: 0xF2F6FC)
    /// Supporting text on `heroSurface` (Muted Label), >= 5.0:1 in both modes
    /// (light #596881 is 5.11:1 on #EEF4FF; same hue as #60708A, darker only).
    public static let onHeroSecondary = adaptive(light: 0x596881, dark: 0xA7B6CB)
    /// Inner tiles, pills and chips sitting on `heroSurface`.
    public static let heroTile = adaptive(light: 0xFFFFFF, dark: 0x172C47)
    /// The single emphasised value, progress fill and link-like label on `heroSurface`.
    public static let heroAccent = adaptive(light: 0x216BD7, dark: 0x7FB2FF)
    /// Emphasised or link-like *text* on `heroSurface` / `heroTile`. Use this instead of
    /// `heroAccent` for glyphs; `heroAccent` stays the fill/stroke colour. Light
    /// #1F64C9 is 5.11:1 on #EEF4FF (same hue as #216BD7, darker only).
    public static let heroAccentText = adaptive(light: 0x1F64C9, dark: 0x7FB2FF)
    /// Secondary action label on `heroSurface` / `heroTile`, >= 5.0:1 on both
    /// (light #1F64C9 is 5.11:1 on #EEF4FF). Dark is the shared `accent-text`
    /// #8BB9FF (the former #8AB8FF collapsed into it).
    public static let heroActionLabel = adaptive(light: 0x1F64C9, dark: 0x7FB2FF)

    // MARK: One blue heat scale (activity heatmap and muscle map)
    // Five opaque steps on `heroSurface`: 0 = empty, 1...4 = load. Single hue,
    // lightness monotone (deeper in light, brighter in dark). No gradients or alpha.

    private static let heatLightFills: [UInt32] = [0xFFFFFF, 0xC4D9F8, 0x7FAAEB, 0x216BD7, 0x164396]
    private static let heatDarkFills: [UInt32] = [0x172C47, 0x1E4378, 0x2B63B0, 0x4A8EEF, 0x7FB2FF]
    private static let heatLightText: [UInt32] = [0x10233F, 0x10233F, 0x10233F, 0xFFFFFF, 0xFFFFFF]
    private static let heatDarkText: [UInt32] = [0xF2F6FC, 0xF2F6FC, 0xF2F6FC, 0x071321, 0x071321]

    /// Maps a 0...1 intensity to a heat step: (0, .25] -> 1 ... (.75, 1] -> 4; 0 -> 0.
    public static func heatStep(intensity: Double) -> Int {
        guard intensity > 0 else { return 0 }
        return min(4, max(1, Int((intensity * 4 - 1e-9).rounded(.up))))
    }

    /// Cell, region and legend swatch fill for a heat step.
    public static func heatFill(step: Int) -> Color {
        let index = min(4, max(0, step))
        return adaptive(light: heatLightFills[index], dark: heatDarkFills[index])
    }

    /// Day number / selected-region outline colour with >= 4.5:1 against `heatFill(step:)`.
    public static func heatText(step: Int) -> Color {
        let index = min(4, max(0, step))
        return adaptive(light: heatLightText[index], dark: heatDarkText[index])
    }

    /// "Today" ring drawn outside the cell (Active Current mark).
    public static let heatRing = adaptive(light: 0x216BD7, dark: 0x7FB2FF)

    /// Hairline between muscle-map regions (Muted Label at 55% light, 45% dark).
    public static let heatRegionStroke = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: 0xA7B6CB, alpha: 0.45)
                : UIColor(rgb: 0x60708A, alpha: 0.55)
        }
    )

    public static let panelCornerRadius: CGFloat = 26
    public static let compactCornerRadius: CGFloat = 20
    public static let controlCornerRadius: CGFloat = 18
    public static let screenHorizontalInset: CGFloat = 16
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
