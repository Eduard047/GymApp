import SwiftUI

/// What the cue editor sheet is editing.
struct ExerciseCueEditTarget: Identifiable, Equatable {
    let identityKey: String
    let exerciseName: String
    let currentCue: String?
    var id: String { identityKey }
}

func gymExerciseCueLabel() -> String {
    gymText("Cue", "Підказка", "Подсказка", languageCode: gymCurrentLanguageCode())
}

/// Small editor for one exercise's cue; `onSave` takes the raw text (empty removes the cue).
struct ExerciseCueEditorSheet: View {
    let target: ExerciseCueEditTarget
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(target: ExerciseCueEditTarget, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: target.currentCue ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(target.exerciseName)) {
                    TextField(
                        gymText(
                            "Seat 4, narrow grip", "Сидіння 4, вузький хват", "Сиденье 4, узкий хват",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        text: $text
                    )
                    .accessibilityLabel(gymExerciseCueLabel())
                    .onChange(of: text) { newValue in
                        let singleLine = newValue.replacingOccurrences(of: "\n", with: " ")
                        let limited = String(String.UnicodeScalarView(
                            singleLine.unicodeScalars.prefix(ExerciseCue.maximumCodePoints)
                        ))
                        if limited != newValue { text = limited }
                    }
                    Text("\(text.unicodeScalars.count) / \(ExerciseCue.maximumCodePoints)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(GymTheme.textSecondary)
                }
                if target.currentCue != nil {
                    Section {
                        Button(role: .destructive) {
                            onSave("")
                        } label: {
                            Text(gymText("Clear", "Очистити", "Очистить", languageCode: gymCurrentLanguageCode()))
                        }
                    }
                }
            }
            .navigationTitle(
                target.currentCue == nil
                    ? gymText("Add cue", "Додати підказку", "Добавить подсказку", languageCode: gymCurrentLanguageCode())
                    : gymText("Edit cue", "Змінити підказку", "Изменить подсказку", languageCode: gymCurrentLanguageCode())
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(gymText("Cancel", "Скасувати", "Отмена", languageCode: gymCurrentLanguageCode()), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(gymText("Save", "Зберегти", "Сохранить", languageCode: gymCurrentLanguageCode())) {
                        onSave(text)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
