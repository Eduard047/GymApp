import SwiftUI

/// Working: exercise, weight × reps hero, set line, Log set (free workout before the first pick:
/// "Free workout" and Choose exercise). Resting: countdown with Undo/+15 s and Skip.
struct DashboardView: View {
    @EnvironmentObject private var model: WatchAppModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    @ViewBuilder
    private func content(_ workout: WatchActiveWorkout, nowMillis: Int64) -> some View {
        let elapsedSeconds = WatchWorkoutModel.activeMillis(workout, nowMillis: nowMillis) / 1_000
        let elapsed = isLuminanceReduced
            ? WatchCrownSteps.formatDuration(seconds: elapsedSeconds - elapsedSeconds % 60).dropLast(3).description
            : WatchCrownSteps.formatDuration(seconds: elapsedSeconds)
        let stack = VStack(alignment: .leading, spacing: 4) {
            HeartRateRow(health: model.health, elapsed: elapsed)
            if let remaining = WatchWorkoutModel.restRemainingSeconds(workout, nowMillis: nowMillis) {
                resting(workout, remaining: remaining, nowMillis: nowMillis)
            } else {
                working(workout)
            }
        }
        .foregroundStyle(isLuminanceReduced ? WatchTheme.textSecondary : WatchTheme.text)
        if dynamicTypeSize.isAccessibilitySize {
            // Accessibility text does not fit one fixed screen: scroll from the top (below the
            // clock) instead of centring an overflowing stack; the action stays reachable.
            ScrollView {
                stack
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .scenePadding(.horizontal)
            }
        } else {
            stack
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .scenePadding(.horizontal)
        }
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
        } else {
            // Free workout before the first pick: no "0 kg × 10" target the user never set.
            Text(model.text(.freeWorkout))
                .font(.headline)
                .foregroundStyle(WatchTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !isLuminanceReduced {
                Button(model.text(.chooseExercise)) { showEntry = true }
                    .buttonStyle(PrimaryButtonStyle())
            }
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
            // Undo and Skip are icons: the words do not fit side by side in UK/RU on any size.
            HStack(spacing: 6) {
                if canUndo {
                    Button { model.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(TonalButtonStyle())
                    .accessibilityLabel(model.text(.undo))
                } else {
                    Button(model.text(.restAdd)) { model.addRest() }
                        .buttonStyle(TonalButtonStyle())
                        .lineLimit(1)
                }
                Button { model.skipRest() } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(TonalButtonStyle())
                .accessibilityLabel(model.text(.skip))
            }
        }
    }
}
