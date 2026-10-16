import SwiftUI

/// Dynamic Type helpers for custom sizes. At the default content size every
/// helper resolves to exactly the value passed in, so default rendering is
/// unchanged; larger sizes grow the value with `textStyle`, optionally capped
/// by `maxScale` so display numerals and rings stay inside the layout.
private struct GymScaledFontModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let baseSize: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let monospacedDigit: Bool
    private let maxScale: CGFloat?

    init(
        size: CGFloat,
        weight: Font.Weight,
        design: Font.Design,
        textStyle: Font.TextStyle,
        monospacedDigit: Bool,
        maxScale: CGFloat?
    ) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        baseSize = size
        self.weight = weight
        self.design = design
        self.monospacedDigit = monospacedDigit
        self.maxScale = maxScale
    }

    func body(content: Content) -> some View {
        let size = maxScale.map { min(scaledSize, baseSize * $0) } ?? scaledSize
        let font = Font.system(size: size, weight: weight, design: design)
        return content.font(monospacedDigit ? font.monospacedDigit() : font)
    }
}

private struct GymScaledFrameModifier: ViewModifier {
    @ScaledMetric private var scaledWidth: CGFloat
    @ScaledMetric private var scaledHeight: CGFloat
    private let hasWidth: Bool
    private let hasHeight: Bool
    private let baseWidth: CGFloat
    private let baseHeight: CGFloat
    private let maxScale: CGFloat?
    private let alignment: Alignment

    init(
        width: CGFloat?,
        height: CGFloat?,
        alignment: Alignment,
        textStyle: Font.TextStyle,
        maxScale: CGFloat?
    ) {
        _scaledWidth = ScaledMetric(wrappedValue: width ?? 0, relativeTo: textStyle)
        _scaledHeight = ScaledMetric(wrappedValue: height ?? 0, relativeTo: textStyle)
        hasWidth = width != nil
        hasHeight = height != nil
        baseWidth = width ?? 0
        baseHeight = height ?? 0
        self.maxScale = maxScale
        self.alignment = alignment
    }

    func body(content: Content) -> some View {
        content.frame(
            width: hasWidth ? capped(scaledWidth, base: baseWidth) : nil,
            height: hasHeight ? capped(scaledHeight, base: baseHeight) : nil,
            alignment: alignment
        )
    }

    private func capped(_ value: CGFloat, base: CGFloat) -> CGFloat {
        maxScale.map { min(value, base * $0) } ?? value
    }
}

extension View {
    /// `.font(.system(size:weight:design:))` that follows Dynamic Type.
    func gymScaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body,
        monospacedDigit: Bool = false,
        maxScale: CGFloat? = nil
    ) -> some View {
        modifier(
            GymScaledFontModifier(
                size: size,
                weight: weight,
                design: design,
                textStyle: textStyle,
                monospacedDigit: monospacedDigit,
                maxScale: maxScale
            )
        )
    }

    /// A fixed `.frame(width:height:)` that grows with Dynamic Type; use it for
    /// icon columns, badges and rings that must keep up with the text beside them.
    func gymScaledFrame(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        alignment: Alignment = .center,
        relativeTo textStyle: Font.TextStyle = .body,
        maxScale: CGFloat? = nil
    ) -> some View {
        modifier(
            GymScaledFrameModifier(
                width: width,
                height: height,
                alignment: alignment,
                textStyle: textStyle,
                maxScale: maxScale
            )
        )
    }
}

/// A row that turns into a column at accessibility text sizes, so labels and
/// trailing values stop competing for one line. Use `GymAdaptiveSpacer` instead
/// of `Spacer` inside it.
struct GymAdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let rowAlignment: VerticalAlignment
    private let columnAlignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let columnSpacing: CGFloat?
    private let stacksFromLargeText: Bool
    private let content: Content

    /// `stacksFromLargeText` switches to a column from `xxxLarge` instead of only
    /// at accessibility sizes, for rows whose pills already truncate there.
    init(
        stacksFromLargeText: Bool = false,
        rowAlignment: VerticalAlignment = .center,
        columnAlignment: HorizontalAlignment = .leading,
        spacing: CGFloat? = nil,
        columnSpacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.rowAlignment = rowAlignment
        self.columnAlignment = columnAlignment
        self.spacing = spacing
        self.columnSpacing = columnSpacing
        self.stacksFromLargeText = stacksFromLargeText
        self.content = content()
    }

    var body: some View {
        let stacked = stacksFromLargeText ? dynamicTypeSize.isLargeText : dynamicTypeSize.isAccessibilitySize
        let layout: AnyLayout = stacked
            ? AnyLayout(VStackLayout(alignment: columnAlignment, spacing: columnSpacing ?? spacing))
            : AnyLayout(HStackLayout(alignment: rowAlignment, spacing: spacing))
        layout { content }
    }
}

/// `Spacer` that only exists while a `GymAdaptiveStack` is laid out as a row.
struct GymAdaptiveSpacer: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var minLength: CGFloat?
    var stacksFromLargeText = false

    var body: some View {
        if !(stacksFromLargeText ? dynamicTypeSize.isLargeText : dynamicTypeSize.isAccessibilitySize) {
            Spacer(minLength: minLength)
        }
    }
}

private struct GymAccessibilityPaddingModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let value: CGFloat

    func body(content: Content) -> some View {
        content.padding(.vertical, dynamicTypeSize.isAccessibilitySize ? value : 0)
    }
}

extension View {
    /// Vertical breathing room for multi-line labels inside min-height capsules;
    /// zero at regular sizes.
    func gymAccessibilityVerticalPadding(_ value: CGFloat = 10) -> some View {
        modifier(GymAccessibilityPaddingModifier(value: value))
    }
}

private struct GymAdaptiveLineLimitModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let limit: Int
    let accessibilityLimit: Int?

    func body(content: Content) -> some View {
        content.lineLimit(dynamicTypeSize.isAccessibilitySize ? accessibilityLimit : limit)
    }
}

extension View {
    /// `lineLimit(limit)` that lifts to `accessibilityLimit` (nil = unlimited) at
    /// accessibility text sizes, so one-line subtitles wrap instead of truncating.
    func gymLineLimit(_ limit: Int, accessibility accessibilityLimit: Int? = nil) -> some View {
        modifier(GymAdaptiveLineLimitModifier(limit: limit, accessibilityLimit: accessibilityLimit))
    }
}

extension DynamicTypeSize {
    /// True from `xxxLarge` up (the largest non-accessibility size and every
    /// accessibility size): where three-column rows and side-by-side pills no
    /// longer fit a phone width.
    var isLargeText: Bool { self >= .xxxLarge }
}
