import SwiftUI

struct SummaryView: View {
    @EnvironmentObject private var model: WatchAppModel
    @ObservedObject private var health = WatchAppModel.shared.health
    @State private var confirmDiscard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.text(.summary))
                    .font(.headline)
                if let workout = model.workout {
                    grid(workout)
                }
                if let status = model.summaryStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(WatchTheme.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(model.text(.save)) { Task { await model.saveWorkout() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isSaving)
                Button {
                    confirmDiscard = true
                } label: {
                    Text(model.text(.discard))
                        .font(.body)
                        .foregroundStyle(WatchTheme.destructive)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .scenePadding(.horizontal)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { model.backFromSummary() } label: {
                    Image(systemName: "chevron.backward").foregroundStyle(WatchTheme.text)
                }
                    .accessibilityLabel(model.text(.paused))
            }
        }
        .sheet(isPresented: $confirmDiscard) {
            DiscardConfirmView { model.discardWorkout() }
        }
    }

    private func grid(_ workout: WatchActiveWorkout) -> some View {
        let seconds = WatchWorkoutModel.activeMillis(workout, nowMillis: WatchAppModel.nowMillis()) / 1_000
        // A lost session still shows what was captured before the loss.
        let stats = workout.heartRateEnabled ? health.statistics : WorkoutSessionManager.Statistics(
            averageHeartRate: workout.lastAverageHeartRate,
            maximumHeartRate: workout.lastMaximumHeartRate,
            activeKilocalories: workout.lastActiveKilocalories
        )
        let dash = "—"
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                cell(WatchCrownSteps.formatDuration(seconds: seconds), model.text(.labelDuration))
                cell(String(workout.sets.count), model.text(.labelSets))
            }
            GridRow {
                cell(model.format(.weightKg, WatchCrownSteps.formatVolume(WatchWorkoutModel.volume(workout.sets), language: model.language)),
                     model.text(.labelVolume))
                cell(stats.activeKilocalories.map { model.format(.valueKcal, Int($0.rounded())) } ?? dash, model.text(.calories))
            }
            GridRow {
                cell(stats.averageHeartRate.map { model.format(.valueBpm, Int($0.rounded())) } ?? dash, model.text(.labelAvgHR))
                cell(stats.maximumHeartRate.map { model.format(.valueBpm, Int($0.rounded())) } ?? dash, model.text(.labelMaxHR))
            }
        }
    }

    private func cell(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.footnote)
                .foregroundStyle(WatchTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
