import SwiftUI
import UIKit

/// Shared visual tokens for the native GymApp interface.
///
/// Neutral Apple system palette: black / grouped-gray grounds with system blue
/// reserved for focus, selection, and progress. Material stays on the functional layer.
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

    /// Accent tint and small accent text. Apple system blue, split by contrast:
    /// light #0062CC (system blue #007AFF darkened, same hue) is 5.2:1 on #F2F2F7
    /// and 4.62:1 on #E5E5EA; dark #409CFF is 6.0:1 on #1C1C1E and 4.92:1 on #2C2C2E.
    public static let primary = adaptive(light: 0x0062CC, dark: 0x409CFF)
    public static let primaryAction = adaptive(light: 0x007AFF, dark: 0x0A84FF)
    /// Apple system blue as a *fill* that carries `onPrimary` (white) text/icons
    /// directly on top of it, e.g. a solid button or hero card background. Filled
    /// button labels need 3:1: white is 4.02:1 on light #007AFF and 3.65:1 on dark
    /// #0A84FF. `primary` is the text-safe variant for small text and tints.
    public static let brandFill = adaptive(light: 0x007AFF, dark: 0x0A84FF)
    public static let onPrimary = Color.white
    /// Recovery / success. Text-safe in both appearances: light #1C7430 (system green
    /// #34C759 darkened) is 5.24:1 on #F2F2F7; dark #30D158 is 6.89:1 on #2C2C2E.
    public static let secondary = adaptive(light: 0x1C7430, dark: 0x30D158)
    /// Momentum violet. Light system indigo #5856D6 (5.06:1 on #F2F2F7); dark #7D7AFF
    /// is the text-safe indigo (4.94:1 on #1C1C1E).
    public static let tertiary = adaptive(light: 0x5856D6, dark: 0x7D7AFF)
    /// Effort coral (`record` in DESIGN.md): PR / record marks only.
    public static let record = adaptive(light: 0xFF6961, dark: 0xFF6961)
    /// Label on a solid `record` fill: black (7.45:1 on #FF6961).
    public static let onRecord = adaptive(light: 0x000000, dark: 0x000000)

    public static let background = adaptive(light: 0xF2F2F7, dark: 0x000000)
    public static let surface = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    public static let surfaceVariant = adaptive(light: 0xE5E5EA, dark: 0x2C2C2E)

    public static let textPrimary = adaptive(light: 0x000000, dark: 0xFFFFFF)
    /// Light #666669 is 5.13:1 on #F2F2F7 and 4.56:1 on #E5E5EA (system gray #6C6C70
    /// is 4.16:1 there); dark #98989F is 5.94:1 on #1C1C1E and 4.86:1 on #2C2C2E.
    public static let textSecondary = adaptive(light: 0x666669, dark: 0x98989F)
    public static let outline = adaptive(light: 0xC6C6C8, dark: 0x545458)
    public static let outlineSoft = adaptive(light: 0xE5E5EA, dark: 0x38383A)
    /// Destructive / error. Text-safe: light #D70015 (system red text variant) is 4.83:1 on
    /// #F2F2F7 (4.29:1 on #E5E5EA); dark #FF6961 is the accessible system red (4.94:1 on #2C2C2E).
    public static let error = adaptive(light: 0xD70015, dark: 0xFF6961)
    /// Text/icons on a solid `error` fill (`on-destructive` in DESIGN.md): white on
    /// light #D70015, black on dark #FF6961 (7.45:1; white would be 2.6:1).
    public static let onError = adaptive(light: 0xFFFFFF, dark: 0x000000)
    /// Caution (`warning` in DESIGN.md): light #BD3100 (system orange text variant,
    /// 5.22:1 on #F2F2F7), dark #FF9F0A (8.28:1 on #1C1C1E).
    public static let warning = adaptive(light: 0xBD3100, dark: 0xFF9F0A)

    /// Flat hero/brand surface (no gradient): light #FFFFFF, dark #1C1C1E.
    public static let heroSurface = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// Hairline border of the hero surface; also the progress track on it.
    public static let heroOutline = adaptive(light: 0xE5E5EA, dark: 0x38383A)
    /// Title and key numbers on `heroSurface` (Clear Label).
    public static let onHero = adaptive(light: 0x000000, dark: 0xFFFFFF)
    /// Supporting text on `heroSurface` (Muted Label), >= 4.5:1 on `heroSurface` and
    /// `heroTile` in both modes (same values as `textSecondary`).
    public static let onHeroSecondary = adaptive(light: 0x666669, dark: 0x98989F)
    /// Inner tiles, pills and chips sitting on `heroSurface`.
    public static let heroTile = adaptive(light: 0xF2F2F7, dark: 0x2C2C2E)
    /// The single emphasised value, progress fill and link-like label on `heroSurface`
    /// (fill/stroke colour: system blue, 4.02:1 on white and 4.66:1 on #1C1C1E).
    public static let heroAccent = adaptive(light: 0x007AFF, dark: 0x0A84FF)
    /// Emphasised or link-like *text* on `heroSurface` / `heroTile`. Use this instead of
    /// `heroAccent` for glyphs. Light #0062CC is 5.8:1 on white and 5.2:1 on #F2F2F7;
    /// dark #409CFF is 6.0:1 on #1C1C1E and 4.92:1 on #2C2C2E.
    public static let heroAccentText = adaptive(light: 0x0062CC, dark: 0x409CFF)
    /// Secondary action label on `heroSurface` / `heroTile` (same values as
    /// `heroAccentText`).
    public static let heroActionLabel = adaptive(light: 0x0062CC, dark: 0x409CFF)

    // MARK: One blue heat scale (activity heatmap and muscle map)
    // Five opaque steps on `heroSurface`: 0 = empty, 1...4 = load. Single hue,
    // lightness monotone (deeper in light, brighter in dark). No gradients or alpha.

    private static let heatLightFills: [UInt32] = [0xE5E5EA, 0xCCE4FF, 0x99C9FF, 0x4DA3FF, 0x007AFF]
    private static let heatDarkFills: [UInt32] = [0x2C2C2E, 0x0B3A6E, 0x0A5AAE, 0x0A73E6, 0x0A84FF]
    private static let heatLightText: [UInt32] = [0x000000, 0x000000, 0x000000, 0x000000, 0x000000]
    private static let heatDarkText: [UInt32] = [0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0x000000]

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
    public static let heatRing = adaptive(light: 0x007AFF, dark: 0x0A84FF)

    /// Hairline between muscle-map regions (Muted Label at 55% light, 45% dark).
    public static let heatRegionStroke = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: 0x98989F, alpha: 0.45)
                : UIColor(rgb: 0x666669, alpha: 0.55)
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
        // `primary` is the pale accent-text blue in dark mode; a switch track
        // carries a white thumb, so it takes the accent-fill blue instead.
        .toggleStyle(SwitchToggleStyle(tint: GymTheme.primaryAction))
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


// MARK: - Top banner inset for pushed screens

private struct GymTopBannerKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

extension EnvironmentValues {
    /// The resume / invitation banner the tab shell pins above the tabs. Tab roots draw it
    /// themselves; screens pushed onto a tab's stack read it here via `gymTopBannerInset()`.
    var gymTopBanner: AnyView? {
        get { self[GymTopBannerKey.self] }
        set { self[GymTopBannerKey.self] = newValue }
    }
}

private struct GymTopBannerInset: ViewModifier {
    @Environment(\.gymTopBanner) private var banner

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let banner { banner }
        }
    }
}

extension View {
    /// Keeps the shell's banner above a pushed screen and lays the screen out below it, so the
    /// resume bar stays visible on every screen of a tab, as on Android.
    func gymTopBannerInset() -> some View {
        modifier(GymTopBannerInset())
    }
}
