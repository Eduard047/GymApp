import SwiftUI

struct PauseView: View {
    @EnvironmentObject private var model: WatchAppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onResume: () -> Void
    #if DEBUG
    @State private var confirmDiscard = WatchDebugSeed.isScreen("discard")
    #else
    @State private var confirmDiscard = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if let status = model.pauseStatus, status != model.text(.needSet) {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(WatchTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
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
                    .disabled(!canFinish)
                    if !canFinish {
                        // Zero sets: Finish is disabled and says why, right at the button.
                        Text(model.text(.needSet))
                            .font(.footnote)
                            .foregroundStyle(WatchTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        confirmDiscard = true
                    } label: {
                        pauseLabel(model.text(.discard), "trash")
                    }
                    .buttonStyle(TonalButtonStyle(fill: WatchTheme.destructiveTonal, foreground: WatchTheme.destructive))
                }
                .scenePadding(.horizontal)
            }
            // "Paused · time" sits in the status row, so all three actions fit without scrolling.
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $confirmDiscard) {
            DiscardConfirmView { model.discardWorkout() }
        }
    }

    private var canFinish: Bool { !(model.workout?.sets.isEmpty ?? true) }

    /// Icon centred against a label that may wrap to two lines (UK/RU). At accessibility sizes the
    /// icon is dropped so the words keep the full width and do not break mid-word.
    @ViewBuilder
    private func pauseLabel(_ title: String, _ systemImage: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            WholeWordLabel(title: title)
        } else {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                Text(title)
            }
        }
    }

    /// Elapsed time is frozen while paused, so no timeline is needed.
    private var title: String {
        guard let workout = model.workout else { return model.text(.paused) }
        let seconds = WatchWorkoutModel.activeMillis(workout, nowMillis: WatchAppModel.nowMillis()) / 1_000
        return model.text(.paused) + " · " + WatchCrownSteps.formatDuration(seconds: seconds)
    }
}

/// Custom sheet so the order and emphasis are fixed: Keep workout (the default) first, so the
/// safe choice is visible without scrolling on every size; Discard below it. At accessibility
/// sizes the body text moves below Keep so Keep still fits the first screen.
struct DiscardConfirmView: View {
    @EnvironmentObject private var model: WatchAppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onDiscard: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.text(.discardTitle))
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !dynamicTypeSize.isAccessibilitySize {
                    bodyText
                }
                Button { dismiss() } label: { WholeWordLabel(title: model.text(.keep)) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 2)
                if dynamicTypeSize.isAccessibilitySize {
                    bodyText
                }
                Button {
                    dismiss()
                    onDiscard()
                } label: {
                    WholeWordLabel(title: model.text(.discard)).multilineTextAlignment(.center)
                }
                .buttonStyle(TonalButtonStyle(fill: WatchTheme.destructiveTonal, foreground: WatchTheme.destructive))
            }
            .scenePadding(.horizontal)
        }
        .presentationBackground(WatchTheme.background)
    }

    private var bodyText: some View {
        Text(model.text(.discardBody))
            .font(.footnote)
            .foregroundStyle(WatchTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Button label that never breaks a word: at accessibility sizes a long UK/RU word no longer fits
/// one line and gets hyphenated, so allow one line per word and shrink the text instead.
private struct WholeWordLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(title)
                .lineLimit(max(1, title.split(separator: " ").count))
                .minimumScaleFactor(0.6)
        } else {
            Text(title)
        }
    }
}
