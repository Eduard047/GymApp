import ActivityKit
import SwiftUI
import WidgetKit

/// Brand colors, duplicated here (not shared with `GymTheme`) because the
/// widget extension needs a tiny, dependency-free color set and `GymTheme`
/// pulls in app-only helpers. Keep in sync with
/// `ios/GymApp-iOS/GymApp/UI/Theme/GymTheme.swift` `primary`/`brandFill`.
private enum LiveActivityColor {
    static let brand = Color(red: 0x21 / 255, green: 0x6B / 255, blue: 0xD7 / 255)
    static let onBrand = Color.white
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenLiveActivityView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(LiveActivityColor.brand)
                .activitySystemActionForegroundColor(LiveActivityColor.onBrand)
        } dynamicIsland: { context in
            DynamicIsland {
                // Leading/trailing sit in the island's rounded top corners next
                // to the camera cutout, so they carry only compact glyphs. All
                // text lives in the center and bottom regions, which span the
                // full width and are never clipped by the corner curve.
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title3)
                        .foregroundStyle(LiveActivityColor.brand)
                        .accessibilityHidden(true)
                }
                .contentMargins(.leading, 4)
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isResting, let restEndsAt = context.state.restEndsAt {
                        Text(timerInterval: Date()...restEndsAt, countsDown: true)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(LiveActivityColor.brand)
                            .frame(maxWidth: 64, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Image(systemName: "checkmark.circle")
                            .font(.title3)
                            .foregroundStyle(LiveActivityColor.brand)
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
                            .tint(LiveActivityColor.brand)
                            if context.state.isResting, let restEndsAt = context.state.restEndsAt {
                                Button(intent: SkipRestIntent(
                                    workoutID: context.attributes.workoutID,
                                    restEndsAt: restEndsAt
                                )) {
                                    Label(context.state.resolvedSkipRestButtonTitle, systemImage: "forward.fill")
                                }
                                .accessibilityLabel(context.state.resolvedSkipRestButtonTitle)
                                .tint(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)
                        .labelStyle(.titleOnly)
                        .font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(LiveActivityColor.brand)
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
                        .foregroundStyle(LiveActivityColor.brand)
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
                        .foregroundStyle(LiveActivityColor.onBrand)
                        .lineLimit(1)
                    Text(state.setProgressLabel ?? "\(attributes.setLabel) \(state.setIndex)/\(state.setCount)")
                        .font(.subheadline)
                        .foregroundStyle(LiveActivityColor.onBrand.opacity(0.8))
                }
                Spacer()
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(LiveActivityColor.onBrand)
            }

            if state.isResting, let restEndsAt = state.restEndsAt {
                Text(timerInterval: Date()...restEndsAt, countsDown: true)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LiveActivityColor.onBrand)
            } else {
                Text("\(attributes.nextLabel) \(state.nextSetSummary)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(LiveActivityColor.onBrand)
            }

            ProgressView(value: state.progress)
                .tint(LiveActivityColor.onBrand)

            HStack(spacing: 10) {
                Button(intent: RecordCurrentSetIntent(
                    workoutID: attributes.workoutID,
                    setID: state.currentSetID
                )) {
                    Label(state.resolvedRecordSetButtonTitle, systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(state.resolvedRecordSetButtonTitle)
                if state.isResting, let restEndsAt = state.restEndsAt {
                    Button(intent: SkipRestIntent(
                        workoutID: attributes.workoutID,
                        restEndsAt: restEndsAt
                    )) {
                        Label(state.resolvedSkipRestButtonTitle, systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel(state.resolvedSkipRestButtonTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(LiveActivityColor.onBrand.opacity(0.22))
            .font(.footnote)
            .labelStyle(.titleOnly)
        }
        .padding(16)
    }
}
