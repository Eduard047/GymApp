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
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exerciseName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text("\(context.attributes.setLabel) \(context.state.setIndex)/\(context.state.setCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isResting, let restEndsAt = context.state.restEndsAt {
                        Text(timerInterval: Date()...restEndsAt, countsDown: true)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(LiveActivityColor.brand)
                    } else {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(LiveActivityColor.brand)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Text("\(context.attributes.nextLabel) \(context.state.nextSetSummary)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button(intent: RecordCurrentSetIntent(
                                workoutID: context.attributes.workoutID,
                                setID: context.state.currentSetID
                            )) {
                                Label("Записать подход", systemImage: "checkmark")
                            }
                            .tint(LiveActivityColor.brand)
                            if context.state.isResting, let restEndsAt = context.state.restEndsAt {
                                Button(intent: SkipRestIntent(
                                    workoutID: context.attributes.workoutID,
                                    restEndsAt: restEndsAt
                                )) {
                                    Label("Пропустить отдых", systemImage: "forward.fill")
                                }
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
                    Label("Записать подход", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                if state.isResting, let restEndsAt = state.restEndsAt {
                    Button(intent: SkipRestIntent(
                        workoutID: attributes.workoutID,
                        restEndsAt: restEndsAt
                    )) {
                        Label("Пропустить отдых", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                    }
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
