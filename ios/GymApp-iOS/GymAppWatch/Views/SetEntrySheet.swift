import SwiftUI

private enum EntryRoute: Hashable {
    case picker
}

private enum EntryField: Hashable {
    case weight
    case reps
}

/// Exercise row, weight and reps wheels (Digital Crown drives the focused one), Save set.
/// In a free workout with no exercise yet, the sheet opens on the picker first.
struct SetEntrySheet: View {
    @EnvironmentObject private var model: WatchAppModel
    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    @State private var path: [EntryRoute] = WatchDebugSeed.isScreen("picker") ? [.picker] : []
    #else
    @State private var path: [EntryRoute] = []
    #endif
    @State private var weight = 0.0
    @State private var reps = 10
    @FocusState private var focus: EntryField?

    var body: some View {
        NavigationStack(path: $path) {
            entry
                .containerBackground(WatchTheme.background, for: .navigation)
                .navigationDestination(for: EntryRoute.self) { _ in
                    ExercisePickerView { name in
                        model.selectExercise(name)
                        loadDraft()
                        path.removeAll()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(model.text(.close))
                    }
                }
        }
        .presentationBackground(WatchTheme.background)
        .onAppear {
            loadDraft()
            if model.workout?.exerciseName == nil { path = [.picker] }
            focus = .weight
        }
    }

    private var exerciseName: String? { model.workout?.exerciseName }

    private var entry: some View {
        VStack(spacing: 4) {
            Button {
                path.append(.picker)
            } label: {
                HStack(spacing: 4) {
                    Text(exerciseName ?? model.text(.chooseExercise))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.forward")
                        .font(.footnote)
                        .foregroundStyle(WatchTheme.textSecondary)
                }
            }
            .buttonStyle(TonalButtonStyle())
            .accessibilityLabel((exerciseName.map { $0 + ", " } ?? "") + model.text(.a11yChangeExercise))
            HStack(spacing: 6) {
                wheel(
                    title: model.text(.unitKg),
                    field: .weight,
                    label: model.text(.labelWeight)
                ) {
                    Picker(selection: $weight) {
                        ForEach(weightOptions, id: \.self) { value in
                            Text(WatchCrownSteps.formatWeight(value, language: model.language))
                                .monospacedDigit()
                                .foregroundStyle(focus == .weight ? WatchTheme.accent : WatchTheme.text)
                                .tag(value)
                        }
                    } label: {
                        Text(model.text(.labelWeight))
                    }
                    // The "kg" title above the wheel is hidden from VoiceOver, so the value
                    // carries the unit ("Weight, 20 kg"), like Wear OS.
                    .accessibilityValue(
                        "\(WatchCrownSteps.formatWeight(weight, language: model.language)) \(model.text(.unitKg))"
                    )
                }
                Text(verbatim: "×")
                    .foregroundStyle(WatchTheme.textSecondary)
                    .accessibilityHidden(true)
                wheel(
                    title: model.text(.unitReps),
                    field: .reps,
                    label: model.text(.labelReps)
                ) {
                    Picker(selection: $reps) {
                        ForEach(repsOptions, id: \.self) { value in
                            Text(String(value))
                                .monospacedDigit()
                                .foregroundStyle(focus == .reps ? WatchTheme.accent : WatchTheme.text)
                                .tag(value)
                        }
                    } label: {
                        Text(model.text(.labelReps))
                    }
                }
            }
            Button(model.text(.saveSet)) {
                model.logSet(weight: weight, reps: reps)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(exerciseName == nil)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func wheel<Content: View>(
        title: String,
        field: EntryField,
        label: String,
        @ViewBuilder picker: () -> Content
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(WatchTheme.textSecondary)
                .accessibilityHidden(true)
            picker()
                .pickerStyle(.wheel)
                .labelsHidden()
                .focused($focus, equals: field)
                .frame(minHeight: 56)
                .background(
                    focus == field ? WatchTheme.surfaceHigh : WatchTheme.surface,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity)
    }

    private var weightOptions: [Double] {
        var extras = [weight]
        if let workout = model.workout, let name = workout.exerciseName,
           let planned = WatchWorkoutModel.plannedNextSet(workout, exercise: name) {
            extras.append(planned.weight)
        }
        return WatchCrownSteps.weightOptions(step: model.weightStep, including: extras)
    }

    private var repsOptions: [Int] { WatchCrownSteps.repsOptions(including: [reps]) }

    private func loadDraft() {
        guard let workout = model.workout else { return }
        weight = WatchCrownSteps.normalizedWeight(workout.draftWeight)
        reps = WatchCrownSteps.normalizedReps(workout.draftReps)
    }
}
