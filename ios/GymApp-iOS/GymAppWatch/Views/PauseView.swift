import SwiftUI

struct PauseView: View {
    @EnvironmentObject private var model: WatchAppModel
    let onResume: () -> Void
    #if DEBUG
    @State private var confirmDiscard = WatchDebugSeed.isScreen("discard")
    #else
    @State private var confirmDiscard = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(title(nowMillis: WatchAppModel.millis(timeline.date)))
                        .font(.footnote)
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                Button(action: onResume) {
                    pauseLabel(model.text(.resume), "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    model.requestFinish()
                } label: {
                    pauseLabel(model.text(.finish), "checkmark")
                }
                .buttonStyle(TonalButtonStyle())
                Button {
                    confirmDiscard = true
                } label: {
                    pauseLabel(model.text(.discard), "trash")
                }
                .buttonStyle(TonalButtonStyle(fill: WatchTheme.destructiveTonal, foreground: WatchTheme.destructive))
                if let status = model.pauseStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(WatchTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .scenePadding(.horizontal)
        }
        .sheet(isPresented: $confirmDiscard) {
            DiscardConfirmView { model.discardWorkout() }
        }
    }

    /// Icon centred against a label that may wrap to two lines (UK/RU).
    private func pauseLabel(_ title: String, _ systemImage: String) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
        }
    }

    private func title(nowMillis: Int64) -> String {
        guard let workout = model.workout else { return model.text(.paused) }
        let seconds = WatchWorkoutModel.activeMillis(workout, nowMillis: nowMillis) / 1_000
        return model.text(.paused) + " · " + WatchCrownSteps.formatDuration(seconds: seconds)
    }
}

/// Custom sheet so the order and emphasis are fixed: Discard above, Keep workout (default) below.
struct DiscardConfirmView: View {
    @EnvironmentObject private var model: WatchAppModel
    @Environment(\.dismiss) private var dismiss
    let onDiscard: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.text(.discardTitle))
                    .font(.headline)
                Text(model.text(.discardBody))
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    dismiss()
                    onDiscard()
                } label: {
                    Text(model.text(.discard)).multilineTextAlignment(.center)
                }
                .buttonStyle(TonalButtonStyle(fill: WatchTheme.destructiveTonal, foreground: WatchTheme.destructive))
                Button(model.text(.keep)) { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .scenePadding(.horizontal)
        }
    }
}
