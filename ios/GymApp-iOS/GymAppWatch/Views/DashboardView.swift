import SwiftUI

/// Working: exercise, weight × reps hero, set line, Log set. Resting: countdown with Undo/+15 s and Skip.
struct DashboardView: View {
    @EnvironmentObject private var model: WatchAppModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    #if DEBUG
    @State private var showEntry = WatchDebugSeed.isScreen("set-entry", "picker")
    #else
    @State private var showEntry = false
    #endif

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if let workout = model.workout {
                content(workout, nowMillis: WatchAppModel.millis(timeline.date))
            }
        }
        .sheet(isPresented: $showEntry) {
            SetEntrySheet()
        }
    }

    private func content(_ workout: WatchActiveWorkout, nowMillis: Int64) -> some View {
        let elapsedSeconds = WatchWorkoutModel.activeMillis(workout, nowMillis: nowMillis) / 1_000
        let elapsed = isLuminanceReduced
            ? WatchCrownSteps.formatDuration(seconds: elapsedSeconds - elapsedSeconds % 60).dropLast(3).description
            : WatchCrownSteps.formatDuration(seconds: elapsedSeconds)
        return VStack(alignment: .leading, spacing: 4) {
            HeartRateRow(health: model.health, elapsed: elapsed)
            if let remaining = WatchWorkoutModel.restRemainingSeconds(workout, nowMillis: nowMillis) {
                resting(workout, remaining: remaining, nowMillis: nowMillis)
            } else {
                working(workout)
            }
        }
        .foregroundStyle(isLuminanceReduced ? WatchTheme.textSecondary : WatchTheme.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scenePadding(.horizontal)
    }

    @ViewBuilder
    private func working(_ workout: WatchActiveWorkout) -> some View {
        if let name = workout.exerciseName {
            Text(name)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(name)
        } else {
            Text(model.text(.exercise))
                .font(.headline)
                .foregroundStyle(WatchTheme.textSecondary)
        }
        Text(WatchText.weightReps(weight: workout.draftWeight, reps: workout.draftReps, model.language))
            .font(WatchTheme.heroWork)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(model.format(
                .a11ySetValues,
                WatchCrownSteps.formatWeight(workout.draftWeight, language: model.language),
                workout.draftReps
            ))
        if let position = WatchWorkoutModel.setPosition(workout) {
            Text(WatchText.setLine(position, model.language))
                .font(.footnote)
                .foregroundStyle(WatchTheme.textSecondary)
        }
        Spacer(minLength: 0)
        if !isLuminanceReduced {
            Button(model.text(.logSet)) { showEntry = true }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private func resting(_ workout: WatchActiveWorkout, remaining: Int, nowMillis: Int64) -> some View {
        let canUndo = WatchWorkoutModel.canUndo(workout, nowMillis: nowMillis)
        Text(model.text(canUndo ? .setSaved : .rest))
            .font(.footnote)
            .foregroundStyle(WatchTheme.textSecondary)
        Text(WatchCrownSteps.formatDuration(seconds: Int64(remaining)))
            .font(WatchTheme.heroRest)
            .monospacedDigit()
            .accessibilityLabel(WatchText.restAccessibility(seconds: remaining, model.language))
        if workout.exerciseName != nil {
            Text(model.format(.next, WatchText.weightReps(weight: workout.draftWeight, reps: workout.draftReps, model.language)))
                .font(.footnote)
                .foregroundStyle(WatchTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        Spacer(minLength: 0)
        if !isLuminanceReduced {
            HStack(spacing: 6) {
                if canUndo {
                    Button(model.text(.undo)) { model.undo() }
                        .buttonStyle(TonalButtonStyle())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Button(model.text(.restAdd)) { model.addRest() }
                        .buttonStyle(TonalButtonStyle())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Button(model.text(.skip)) { model.skipRest() }
                    .buttonStyle(TonalButtonStyle())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
            }
        }
    }
}
