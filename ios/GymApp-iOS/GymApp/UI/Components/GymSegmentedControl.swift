import SwiftUI

/// The app's segmented control (DESIGN.md "Chips and segments"): equal-width
/// capsules, 36pt visible inside a 44pt target, selected = brand fill with white
/// semibold text, unselected = tonal fill with primary text. Matches the Android
/// `GymSegmentedControl` and the web `.segmented` control.
///
/// At accessibility text sizes the segments no longer fit on one line, so the
/// control becomes a menu (unless `menuFallback` is off because the caller
/// supplies its own).
struct GymSegmentedControl<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String
    @Binding private var selection: Value
    private let options: [Option]
    private let menuFallback: Bool

    init(
        _ title: String,
        selection: Binding<Value>,
        options: [(value: Value, label: String)],
        menuFallback: Bool = true
    ) {
        self.title = title
        self._selection = selection
        self.options = options.map { Option(value: $0.value, label: $0.label) }
        self.menuFallback = menuFallback
    }

    private var selectedLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        if menuFallback && dynamicTypeSize.isAccessibilitySize {
            menu
        } else {
            segments
        }
    }

    private var segments: some View {
        HStack(spacing: GymTheme.Spacing.small) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    guard !isSelected else { return }
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? GymTheme.onPrimary : GymTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, GymTheme.Spacing.medium)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            Capsule().fill(isSelected ? GymTheme.brandFill : GymTheme.surfaceVariant)
                        )
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GymSegmentPressStyle())
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selection)
        .gymSensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var menu: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: GymTheme.Spacing.small) {
                Text(selectedLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: GymTheme.Spacing.small)
                Image(systemName: "chevron.up.chevron.down")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(selectedLabel)
    }
}

private struct GymSegmentPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? GymPressFeedback.scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? GymPressFeedback.reducedMotionOpacity : 1)
            .animation(
                reduceMotion ? nil : GymPressFeedback.animation(isPressed: configuration.isPressed),
                value: configuration.isPressed
            )
    }
}
