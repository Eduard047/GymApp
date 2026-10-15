import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

/// Flat tonal palette (DESIGN.md "Live status surface"), duplicated here (not
/// shared with `GymTheme`) because the widget extension needs a tiny,
/// dependency-free color set and `GymTheme` pulls in app-only helpers. Keep in
/// sync with `ios/GymApp-iOS/GymApp/UI/Theme/GymTheme.swift`.
private enum LiveActivityColor {
    /// `tonal-hero` background of the lock-screen card.
    static let surface = adaptive(light: 0xEEF4FF, dark: 0x10233A)
    /// `hairline-hero`: card border and progress track.
    static let hairline = adaptive(light: 0xDCE5F2, dark: 0x22395A)
    /// `text-on-hero`.
    static let text = adaptive(light: 0x10233F, dark: 0xF2F6FC)
    /// `text-muted` (supporting text on the hero surface).
    static let textMuted = adaptive(light: 0x596881, dark: 0xA7B6CB)
    /// `tonal-hero-tile`: secondary capsule fill.
    static let tile = adaptive(light: 0xFFFFFF, dark: 0x172C47)
    /// `accent-mark`: progress fill, glyphs, countdown.
    static let mark = adaptive(light: 0x216BD7, dark: 0x7FB2FF)
    /// `accent-text-hero` / `accent-text`: secondary capsule label.
    static let actionText = adaptive(light: 0x1F64C9, dark: 0x8BB9FF)
    /// `accent-fill`: primary capsule, carries white text.
    static let fill = adaptive(light: 0x216BD7, dark: 0x2E72D2)
    static let onFill = Color.white

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        func ui(_ rgb: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

/// Capsule action button for the Live Activity (lock screen and Dynamic
/// Island): `accent-fill` with white text, or a `tonal-hero-tile` capsule with
/// a hairline and accent text for the secondary action. 44pt tall target.
private struct LiveActivityCapsuleButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(prominent ? LiveActivityColor.onFill : LiveActivityColor.actionText)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(prominent ? LiveActivityColor.fill : LiveActivityColor.tile, in: Capsule())
            .overlay {
                if !prominent {
                    Capsule().strokeBorder(LiveActivityColor.hairline, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

/// Flat capsule progress bar: `hairline-hero` track, `accent-mark` fill.
private struct LiveActivityProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(1, max(0, configuration.fractionCompleted ?? 0))
        Capsule()
            .fill(LiveActivityColor.hairline)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(LiveActivityColor.mark)
                        .frame(width: max(6, proxy.size.width * fraction))
                }
            }
            .accessibilityElement()
            .accessibilityValue("\(Int((fraction * 100).rounded()))%")
    }
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenLiveActivityView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(LiveActivityColor.surface)
                .activitySystemActionForegroundColor(LiveActivityColor.actionText)
        } dynamicIsland: { context in
            DynamicIsland {
                // Leading/trailing sit in the island's rounded top corners next
                // to the camera cutout, so they carry only compact glyphs. All
                // text lives in the center and bottom regions, which span the
                // full width and are never clipped by the corner curve.
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title3)
                        .foregroundStyle(LiveActivityColor.mark)
                        .accessibilityHidden(true)
                }
                .contentMargins(.leading, 4)
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isResting, let restEndsAt = context.state.restEndsAt {
                        Text(timerInterval: Date()...restEndsAt, countsDown: true)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(LiveActivityColor.mark)
                            .frame(maxWidth: 64, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Image(systemName: "checkmark.circle")
                            .font(.title3)
                            .foregroundStyle(LiveActivityColor.mark)
                            .accessibilityHidden(true)
                    }
                }
                .contentMargins(.trailing, 4)
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.exerciseName)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(
                            context.state.setProgressLabel
                                ?? "\(context.attributes.setLabel) \(context.state.setIndex)/\(context.state.setCount)"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    .multilineTextAlignment(.center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Text("\(context.attributes.nextLabel) \(context.state.nextSetSummary)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        HStack(spacing: 12) {
                            Button(intent: RecordCurrentSetIntent(
                                workoutID: context.attributes.workoutID,
                                setID: context.state.currentSetID
                            )) {
                                Label(context.state.resolvedRecordSetButtonTitle, systemImage: "checkmark")
                            }
                            .accessibilityLabel(context.state.resolvedRecordSetButtonTitle)
                            .buttonStyle(LiveActivityCapsuleButtonStyle(prominent: true))
                            if context.state.isResting, let restEndsAt = context.state.restEndsAt {
                                Button(intent: SkipRestIntent(
                                    workoutID: context.attributes.workoutID,
                                    restEndsAt: restEndsAt
                                )) {
                                    Label(context.state.resolvedSkipRestButtonTitle, systemImage: "forward.fill")
                                }
                                .accessibilityLabel(context.state.resolvedSkipRestButtonTitle)
                                .buttonStyle(LiveActivityCapsuleButtonStyle(prominent: false))
                            }
                        }
                        .labelStyle(.titleOnly)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(LiveActivityColor.mark)
            } compactTrailing: {
                if context.state.isResting, let restEndsAt = context.state.restEndsAt {
                    Text(timerInterval: Date()...restEndsAt, countsDown: true)
                        .monospacedDigit()
                        .font(.caption2)
                        .frame(width: 40)
                } else {
                    Text("\(context.state.setIndex)/\(context.state.setCount)")
                        .font(.caption2)
                }
            } minimal: {
                if context.state.isResting, let restEndsAt = context.state.restEndsAt {
                    Text(timerInterval: Date()...restEndsAt, countsDown: true)
                        .monospacedDigit()
                        .font(.caption2)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(LiveActivityColor.mark)
                }
            }
            .widgetURL(URL(string: "com.setforge.gymapp.ios://active-workout"))
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.exerciseName)
                        .font(.headline)
                        .foregroundStyle(LiveActivityColor.text)
                        .lineLimit(1)
                    Text(state.setProgressLabel ?? "\(attributes.setLabel) \(state.setIndex)/\(state.setCount)")
                        .font(.subheadline)
                        .foregroundStyle(LiveActivityColor.textMuted)
                }
                Spacer()
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(LiveActivityColor.mark)
                    .accessibilityHidden(true)
            }

            if state.isResting, let restEndsAt = state.restEndsAt {
                Text(timerInterval: Date()...restEndsAt, countsDown: true)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LiveActivityColor.text)
            } else {
                Text("\(attributes.nextLabel) \(state.nextSetSummary)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(LiveActivityColor.text)
            }

            ProgressView(value: state.progress)
                .progressViewStyle(LiveActivityProgressStyle())

            HStack(spacing: 10) {
                Button(intent: RecordCurrentSetIntent(
                    workoutID: attributes.workoutID,
                    setID: state.currentSetID
                )) {
                    Label(state.resolvedRecordSetButtonTitle, systemImage: "checkmark")
                }
                .buttonStyle(LiveActivityCapsuleButtonStyle(prominent: true))
                .accessibilityLabel(state.resolvedRecordSetButtonTitle)
                if state.isResting, let restEndsAt = state.restEndsAt {
                    Button(intent: SkipRestIntent(
                        workoutID: attributes.workoutID,
                        restEndsAt: restEndsAt
                    )) {
                        Label(state.resolvedSkipRestButtonTitle, systemImage: "forward.fill")
                    }
                    .buttonStyle(LiveActivityCapsuleButtonStyle(prominent: false))
                    .accessibilityLabel(state.resolvedSkipRestButtonTitle)
                }
            }
            .labelStyle(.titleOnly)
        }
        .padding(16)
        // Flat tonal card: the system draws the `tonal-hero` tint (see
        // `activityBackgroundTint`); the hairline follows the container corners.
        .background {
            ContainerRelativeShape()
                .strokeBorder(LiveActivityColor.hairline, lineWidth: 1)
        }
    }
}
