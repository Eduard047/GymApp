import SwiftUI

/// The exercise whose custom rest is being edited (see `ExerciseRestTimeStore`).
struct ExerciseRestEditTarget: Identifiable, Equatable {
    let identityKey: String
    let exerciseName: String
    let customSeconds: Int?
    let defaultSeconds: Int
    var id: String { identityKey }
}

/// "m:ss" like the rest labels elsewhere in the workout screen.
private func gymExerciseRestClock(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}

/// Small sheet to pick one exercise's rest: a 15 s stepper from 0:15 to 10:00, "Use default", Save, Cancel.
struct ExerciseRestTimeEditorSheet: View {
    let target: ExerciseRestEditTarget
    /// Takes the chosen seconds, or nil for "Use default"; returns the store result.
    let onSave: (Int?) -> ExerciseRestSaveResult
    let onCancel: () -> Void

    @State private var seconds: Int
    @State private var limitReached = false

    init(target: ExerciseRestEditTarget, onSave: @escaping (Int?) -> ExerciseRestSaveResult, onCancel: @escaping () -> Void) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        let start = target.customSeconds ?? target.defaultSeconds
        _seconds = State(initialValue: min(max(start, ExerciseRestTime.minimumSeconds), ExerciseRestTime.maximumSeconds))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(target.exerciseName)) {
                    Stepper(
                        value: $seconds,
                        in: ExerciseRestTime.minimumSeconds...ExerciseRestTime.maximumSeconds,
                        step: ExerciseRestTime.stepSeconds
                    ) {
                        Text(gymExerciseRestClock(seconds))
                            .font(.title2.monospacedDigit())
                    }
                    .onChange(of: seconds) { _ in limitReached = false }
                    .accessibilityLabel(gymText("Rest time", "Час відпочинку", "Время отдыха", languageCode: gymCurrentLanguageCode()))
                    if limitReached {
                        Text(gymText(
                            "Too many custom rest times. Reset some first.",
                            "Забагато власних часів відпочинку. Спершу скинь частину.",
                            "Слишком много своих времён отдыха. Сначала сбрось часть.",
                            languageCode: gymCurrentLanguageCode()
                        ))
                        .font(.caption)
                        .foregroundStyle(GymTheme.error)
                    } else if target.customSeconds != nil {
                        Text(gymText("Default: ", "За замовчуванням: ", "По умолчанию: ", languageCode: gymCurrentLanguageCode())
                            + gymExerciseRestClock(target.defaultSeconds))
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                }
                if target.customSeconds != nil {
                    Section {
                        Button {
                            limitReached = onSave(nil) == .tooMany
                        } label: {
                            Text(gymText("Use default", "За замовчуванням", "По умолчанию", languageCode: gymCurrentLanguageCode()))
                        }
                    }
                }
            }
            .navigationTitle(gymText("Rest time", "Час відпочинку", "Время отдыха", languageCode: gymCurrentLanguageCode()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(gymText("Cancel", "Скасувати", "Отмена", languageCode: gymCurrentLanguageCode()), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(gymText("Save", "Зберегти", "Сохранить", languageCode: gymCurrentLanguageCode())) {
                        if target.customSeconds == nil && seconds == min(max(target.defaultSeconds, ExerciseRestTime.minimumSeconds), ExerciseRestTime.maximumSeconds) {
                            onCancel()
                        } else {
                            limitReached = onSave(seconds) == .tooMany
                        }
                    }
                }
            }
        }
        .gymSheetPresentation(.compact)
    }
}
