import SwiftUI

/// Reusable content surface with a quiet fill and restrained depth.
public struct GymPanel<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let highlighted: Bool
    private let contentPadding: EdgeInsets
    private let content: Content

    public init(
        highlighted: Bool = false,
        contentPadding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        @ViewBuilder content: () -> Content
    ) {
        self.highlighted = highlighted
        self.contentPadding = contentPadding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                panelBackground
            }
            .overlay {
                RoundedRectangle(cornerRadius: GymTheme.panelCornerRadius, style: .continuous)
                    .strokeBorder(
                        borderColor,
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : GymTheme.hairlineWidth
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: GymTheme.panelCornerRadius, style: .continuous))
            .shadow(
                color: highlighted
                    ? Color.black.opacity(reduceTransparency ? 0.025 : 0.055)
                    : .clear,
                radius: highlighted ? 8 : 0,
                x: 0,
                y: highlighted ? 4 : 0
            )
    }

    @ViewBuilder
    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: GymTheme.panelCornerRadius, style: .continuous)
        shape.fill(highlighted ? GymTheme.heroSurface : GymTheme.surface)
    }

    private var borderColor: Color {
        if highlighted {
            return colorSchemeContrast == .increased ? GymTheme.primary : GymTheme.heroOutline
        }
        return GymTheme.outlineSoft.opacity(colorSchemeContrast == .increased ? 1 : 0.68)
    }
}

/// High-emphasis flat tonal card for the single focal message on a screen.
public struct GymHeroPanel<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let contentPadding: EdgeInsets
    private let content: Content

    public init(
        contentPadding: EdgeInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
        @ViewBuilder content: () -> Content
    ) {
        self.contentPadding = contentPadding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(GymTheme.onHero)
            .background { lensShape.fill(GymTheme.heroSurface) }
            .overlay {
                lensShape.strokeBorder(
                    GymTheme.heroOutline,
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
            }
            .clipShape(lensShape)
            .shadow(
                color: Color.black.opacity(reduceTransparency ? 0.025 : 0.055),
                radius: 8,
                x: 0,
                y: 4
            )
    }

    private var lensShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 26,
            bottomLeadingRadius: 26,
            bottomTrailingRadius: 38,
            topTrailingRadius: 48,
            style: .continuous
        )
    }
}

/// Flat tonal progress bar for `GymTheme.heroSurface`: Hero Outline track,
/// Hero Accent fill, no gradient.
public struct GymHeroProgressStyle: ProgressViewStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let fraction = min(1, max(0, configuration.fractionCompleted ?? 0))
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(GymTheme.heroOutline)
                Capsule()
                    .fill(GymTheme.heroAccent)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}

public struct GymBrandMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 76) {
        self.size = size
    }

    public var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A consistent top-of-screen rhythm for the training log. It collapses the
/// trailing control below the title when Dynamic Type or a narrow phone needs
/// the width, instead of squeezing either element.
public struct GymScreenHeader<Trailing: View>: View {
    @Environment(\.locale) private var locale

    private let eyebrow: String?
    private let title: String
    private let supporting: String?
    private let trailing: Trailing

    public init(
        eyebrow: String? = nil,
        title: String,
        supporting: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.supporting = supporting
        self.trailing = trailing()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: GymTheme.Spacing.medium) {
                copy
                Spacer(minLength: GymTheme.Spacing.small)
                trailing
            }

            VStack(alignment: .leading, spacing: GymTheme.Spacing.medium) {
                copy
                trailing
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: GymTheme.Spacing.xSmall) {
            if let eyebrow {
                Text(gymLocalized(eyebrow, locale: locale))
                    .font(GymTheme.TypeScale.utility)
                    .foregroundStyle(GymTheme.primary)
                    .textCase(.uppercase)
                    .tracking(0.55)
            }
            Text(gymLocalized(title, locale: locale))
                .font(GymTheme.TypeScale.screenTitle)
                .tracking(-0.45)
                .foregroundStyle(GymTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let supporting {
                Text(gymLocalized(supporting, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

public extension GymScreenHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, supporting: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, supporting: supporting) {
            EmptyView()
        }
    }
}

/// Directional empty/help copy that sits inside a section without introducing
/// another card. The slim rail is the quiet counterpart to the live Spotter Lens.
public struct GymInlineState: View {
    @Environment(\.locale) private var locale

    private let text: String
    private let systemImage: String
    private let accent: Color

    public init(
        _ text: String,
        systemImage: String = "circle.dashed",
        accent: Color = GymTheme.primary
    ) {
        self.text = text
        self.systemImage = systemImage
        self.accent = accent
    }

    public var body: some View {
        HStack(alignment: .top, spacing: GymTheme.Spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(gymLocalized(text, locale: locale))
                .font(.subheadline)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, GymTheme.Spacing.medium)
        .padding(.vertical, GymTheme.Spacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accent.opacity(0.72))
                .frame(width: 3)
        }
        .accessibilityElement(children: .combine)
    }
}

public struct GymMetricTile: View {
    @Environment(\.locale) private var locale

    private let label: String
    private let value: String
    private let emphasized: Bool
    private let onHero: Bool
    private let labelUppercase: Bool
    private let compactValue: Bool
    private let singleLineLabel: Bool

    public init(
        label: String,
        value: String,
        emphasized: Bool = false,
        onHero: Bool = false,
        labelUppercase: Bool = false,
        compactValue: Bool = false,
        singleLineLabel: Bool = false
    ) {
        self.label = label
        self.value = value
        self.emphasized = emphasized
        self.onHero = onHero
        self.labelUppercase = labelUppercase
        self.compactValue = compactValue
        self.singleLineLabel = singleLineLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                if singleLineLabel {
                    // Reserves one full-size line so a scaled-down label keeps the value on the row's shared baseline.
                    Text("Ag")
                        .font(.caption.weight(.semibold))
                        .hidden()
                        .accessibilityHidden(true)
                }
                Text(gymLocalized(label, locale: locale))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(onHero ? GymTheme.onHeroSecondary : GymTheme.textSecondary)
                    .textCase(labelUppercase ? .uppercase : nil)
                    .tracking(labelUppercase ? 0.35 : 0)
                    .lineLimit(singleLineLabel ? 1 : 2)
                    .minimumScaleFactor(singleLineLabel ? 0.7 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(gymLocalized(value, locale: locale))
                .font(compactValue ? .headline.bold() : (emphasized ? .title2.bold() : GymTheme.TypeScale.metric))
                .foregroundStyle(onHero ? GymTheme.onHero : GymTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: !compactValue)
        }
        .padding(GymTheme.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 74, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                .fill(onHero ? GymTheme.heroTile : GymTheme.surfaceVariant.opacity(0.58))
        )
        .overlay {
            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(
                    onHero ? GymTheme.heroOutline : GymTheme.outlineSoft.opacity(0.62),
                    lineWidth: GymTheme.hairlineWidth
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gymLocalized(label, locale: locale))
        .accessibilityValue(gymLocalized(value, locale: locale))
    }
}

public struct GymInfoPill: View {
    @Environment(\.locale) private var locale

    private let text: String
    private let systemImage: String?
    private let accent: Color

    public init(_ text: String, systemImage: String? = nil, accent: Color = GymTheme.primary) {
        self.text = text
        self.systemImage = systemImage
        self.accent = accent
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(gymLocalized(text, locale: locale))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(accent)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(accent.opacity(0.08)))
        .overlay { Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

public struct GymSectionTitle: View {
    @Environment(\.locale) private var locale

    private let eyebrow: String?
    private let title: String
    private let supporting: String?

    public init(eyebrow: String? = nil, title: String, supporting: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.supporting = supporting
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow {
                Text(gymLocalized(eyebrow, locale: locale))
                    .font(GymTheme.TypeScale.utility)
                    .foregroundStyle(GymTheme.primary)
                    .textCase(.uppercase)
                    .tracking(0.55)
            }
            Text(gymLocalized(title, locale: locale))
                .font(GymTheme.TypeScale.sectionTitle)
                .foregroundStyle(GymTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let supporting {
                Text(gymLocalized(supporting, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

public struct GymStatusBanner: View {
    @Environment(\.locale) private var locale

    private let message: String
    private let isError: Bool

    public init(message: String, isError: Bool) {
        self.message = message
        self.isError = isError
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? GymTheme.error : GymTheme.primary)
                .accessibilityHidden(true)

            Text(gymLocalized(message, locale: locale))
                .font(.subheadline)
                .foregroundStyle(GymTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                .fill(GymTheme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                .strokeBorder((isError ? GymTheme.error : GymTheme.primary).opacity(0.36), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isError
                ? "\(gymLocalized("Error", locale: locale)): \(gymLocalized(message, locale: locale))"
                : "\(gymLocalized("Status", locale: locale)): \(gymLocalized(message, locale: locale))"
        )
    }
}

public struct GymTextFieldChrome: ViewModifier {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init() {}

    public func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                    .fill(GymTheme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                    .strokeBorder(
                        GymTheme.outline.opacity(colorSchemeContrast == .increased ? 1 : 0.72),
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                    )
            }
    }
}

public extension View {
    func gymTextFieldChrome() -> some View {
        modifier(GymTextFieldChrome())
    }
}

/// Shared motion tokens (DESIGN.md `motion`). `standard` is the critically damped
/// default for layout and state changes; `quick` is the shorter spring for
/// small toggles (disclosure, expand/collapse); `gentle` is the softer spring for
/// content that changes in place (progress arcs, image frames); `intro` is the
/// splash fade. `fade` is the opacity-only 150 ms ease-out, which is also what
/// Reduce Motion falls back to.
enum GymMotion {
    static let standard: Animation = .snappy(duration: 0.3)
    static let quick: Animation = .snappy(duration: 0.2)
    static let gentle: Animation = .smooth(duration: 0.35)
    static let intro: Animation = .easeOut(duration: 0.25)
    static let fadeDuration: TimeInterval = 0.15
    static let fade: Animation = .easeOut(duration: fadeDuration)

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : standard
    }

    /// `animation` as is, or the opacity fade under Reduce Motion.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }

    /// `transition` as is, or a plain opacity fade under Reduce Motion.
    static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

/// Applies `GymMotion.transition` using the view's own Reduce Motion setting, for
/// call sites (like the `App` body) that cannot hold the environment value.
private struct GymReduceMotionTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let transition: AnyTransition

    func body(content: Content) -> some View {
        content.transition(GymMotion.transition(transition, reduceMotion: reduceMotion))
    }
}

extension View {
    func gymTransition(_ transition: AnyTransition) -> some View {
        modifier(GymReduceMotionTransition(transition: transition))
    }
}

/// Wall-clock rest countdown for a `TimelineView`: one entry per whole second
/// boundary of the deadline (so the digits change exactly when the second does),
/// then one entry `endHighlightSeconds` after the deadline that ends the
/// rest-end highlight.
struct GymRestCountdownSchedule: TimelineSchedule {
    static let endHighlightSeconds: TimeInterval = 0.6

    let deadline: Date

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] {
        Self.entryDates(deadline: deadline, from: startDate)
    }

    static func entryDates(deadline: Date, from start: Date) -> [Date] {
        var dates = [start]
        let remaining = deadline.timeIntervalSince(start)
        if remaining > 0 {
            for secondsToGo in stride(from: Int(remaining.rounded(.up)) - 1, through: 0, by: -1) {
                dates.append(deadline.addingTimeInterval(-TimeInterval(secondsToGo)))
            }
        }
        let highlightEnd = deadline.addingTimeInterval(endHighlightSeconds)
        if highlightEnd > start { dates.append(highlightEnd) }
        return dates
    }

    /// Whole seconds left, rounded up (the value the readout shows).
    static func remainingSeconds(deadline: Date, at date: Date) -> Int {
        max(0, Int(ceil(deadline.timeIntervalSince(date))))
    }

    /// True from the moment the countdown hits 0 until the highlight ends.
    static func isEndHighlighted(deadline: Date, at date: Date) -> Bool {
        let sinceEnd = date.timeIntervalSince(deadline)
        return sinceEnd >= 0 && sinceEnd < endHighlightSeconds
    }
}

/// Shared press feedback (DESIGN.md `motion.press`): scale 0.97 in 100 ms ease-out,
/// released with a snappy spring.
enum GymPressFeedback {
    static let scale: CGFloat = 0.97
    /// Opacity while pressed when Reduce Motion is on (no scale).
    static let reducedMotionOpacity = 0.7

    static func animation(isPressed: Bool) -> Animation {
        isPressed ? .easeOut(duration: 0.1) : .snappy(duration: 0.2)
    }
}

/// Pressed-state fill for a control whose visible capsule is drawn outside its
/// Button (step buttons, rest pills): `side` picks the half of the capsule it
/// covers, `height` the capsule height (nil = the label's own height), `inset`
/// keeps it inside a border.
struct GymPressHighlight {
    enum Side { case whole, leading, trailing }

    var side: Side = .whole
    var color: Color
    var height: CGFloat?
    var inset: CGFloat = 0

    @ViewBuilder
    fileprivate func fill(isPressed: Bool, reduceMotion: Bool) -> some View {
        let radius = max(0, (height ?? 44) / 2 - inset)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: side == .trailing ? 0 : radius,
            bottomLeadingRadius: side == .trailing ? 0 : radius,
            bottomTrailingRadius: side == .leading ? 0 : radius,
            topTrailingRadius: side == .leading ? 0 : radius,
            style: .continuous
        )
        shape
            .fill(color)
            .padding(inset)
            .frame(height: height)
            .opacity(isPressed ? 1 : 0)
            // Reduce Motion: the fill appears and clears without animation.
            .animation(reduceMotion ? nil : GymPressFeedback.animation(isPressed: isPressed), value: isPressed)
    }
}

/// Press feedback for the small `.plain` controls (step buttons, rest capsules,
/// Undo, trash): the label scales to 0.97, or dims to 0.7 under Reduce Motion.
/// An optional `highlight` fills the pressed part of a capsule drawn outside the
/// button. Adds no shape or color of its own otherwise. `onPressChange` reports
/// the pressed state (used by the hold-to-repeat steppers).
struct GymPressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var highlight: GymPressHighlight?
    var onPressChange: ((Bool) -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? GymPressFeedback.scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? GymPressFeedback.reducedMotionOpacity : 1)
            .animation(GymPressFeedback.animation(isPressed: configuration.isPressed), value: configuration.isPressed)
            .background {
                if let highlight {
                    highlight.fill(isPressed: configuration.isPressed, reduceMotion: reduceMotion)
                }
            }
            .onChange(of: configuration.isPressed) { _, pressed in onPressChange?(pressed) }
    }
}

/// Solid `accent-fill` capsule (radius 999 per DESIGN.md); carries white text.
public struct GymPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let fillColor: Color

    public init(fillColor: Color = GymTheme.primaryAction) {
        self.fillColor = fillColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(GymTheme.onPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                Capsule()
                    .fill(fillColor)
                    .brightness(configuration.isPressed ? -0.055 : 0)
            )
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed && !reduceMotion ? GymPressFeedback.scale : 1)
            .animation(reduceMotion ? nil : GymPressFeedback.animation(isPressed: configuration.isPressed), value: configuration.isPressed)
    }
}

/// Outline capsule: `surface` fill, 1px accent (or error) at 40%, accent text.
public struct GymSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Error-toned variant for destructive secondary actions (revoke, reset).
    public let isDestructive: Bool

    public init(destructive: Bool = false) { isDestructive = destructive }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isDestructive ? GymTheme.error : GymTheme.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? GymTheme.surfaceVariant : GymTheme.surface)
            )
            .overlay {
                Capsule()
                    .strokeBorder((isDestructive ? GymTheme.error : GymTheme.primary).opacity(0.4), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed && !reduceMotion ? GymPressFeedback.scale : 1)
            .animation(reduceMotion ? nil : GymPressFeedback.animation(isPressed: configuration.isPressed), value: configuration.isPressed)
    }
}
