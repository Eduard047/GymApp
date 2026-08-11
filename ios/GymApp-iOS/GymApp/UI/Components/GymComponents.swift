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
        shape.fill(highlighted && reduceTransparency ? GymTheme.surfaceVariant : GymTheme.surface)
        if highlighted && !reduceTransparency {
            shape.fill(GymTheme.primary.opacity(0.035))
        }
    }

    private var borderColor: Color {
        if highlighted {
            return GymTheme.primary.opacity(colorSchemeContrast == .increased ? 0.9 : 0.22)
        }
        return GymTheme.outlineSoft.opacity(colorSchemeContrast == .increased ? 1 : 0.68)
    }
}

/// High-emphasis ink-and-cobalt card for the single focal message on a screen.
public struct GymHeroPanel<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(GymTheme.onHero)
            .background {
                if reduceTransparency {
                    lensShape.fill(GymTheme.heroLeading)
                } else {
                    lensShape.fill(GymTheme.heroGradient)
                }
            }
            .overlay {
                lensShape.strokeBorder(
                    Color.white.opacity(colorSchemeContrast == .increased ? 0.42 : 0.16),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
            }
            .clipShape(lensShape)
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
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

    public init(label: String, value: String, emphasized: Bool = false, onHero: Bool = false) {
        self.label = label
        self.value = value
        self.emphasized = emphasized
        self.onHero = onHero
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(gymLocalized(label, locale: locale))
                .font(.caption.weight(.semibold))
                .foregroundStyle(onHero ? Color.white.opacity(0.76) : GymTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.35)

            Text(gymLocalized(value, locale: locale))
                .font(emphasized ? .title2.bold() : GymTheme.TypeScale.metric)
                .foregroundStyle(onHero ? Color.white : GymTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(GymTheme.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                .fill(onHero ? Color.white.opacity(0.085) : GymTheme.surfaceVariant.opacity(0.58))
        )
        .overlay {
            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(
                    onHero ? Color.white.opacity(0.14) : GymTheme.outlineSoft.opacity(0.62),
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

public struct GymPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(GymTheme.onPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                    .fill(GymTheme.primaryAction)
                    .brightness(configuration.isPressed ? -0.055 : 0)
            )
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

public struct GymSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(GymTheme.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? GymTheme.surfaceVariant : GymTheme.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                    .strokeBorder(GymTheme.primary.opacity(0.4), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
