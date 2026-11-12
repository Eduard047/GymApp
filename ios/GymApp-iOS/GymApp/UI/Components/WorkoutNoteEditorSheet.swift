import SwiftUI

func gymWorkoutNoteLabel() -> String {
    gymText("Note", "Нотатка", "Заметка", languageCode: gymCurrentLanguageCode())
}

func gymWorkoutNoteAddLabel() -> String {
    gymText("Add note", "Додати нотатку", "Добавить заметку", languageCode: gymCurrentLanguageCode())
}

/// Multiline editor for the active workout's note. `onSave` takes the raw text (the store trims it
/// and clears the note when it is blank) and the caller closes the sheet. Cancel discards silently;
/// swipe-to-dismiss is off while the text differs from what the sheet opened with.
struct WorkoutNoteEditorSheet: View {
    let initialNote: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(initialNote: String?, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialNote = initialNote
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: initialNote ?? "")
    }

    private var isDirty: Bool { text != (initialNote ?? "") }
    private var isValid: Bool { WorkoutNoteRules.isValid(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        gymText(
                            "Workout note", "Нотатка до тренування", "Заметка к тренировке",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(4...12)
                    .accessibilityLabel(gymWorkoutNoteLabel())
                    .onChange(of: text) { newValue in
                        let limited = WorkoutNoteRules.limited(newValue)
                        if limited != newValue { text = limited }
                    }
                    if !isValid {
                        Text(gymText(
                            "Note is too long", "Нотатка задовга", "Заметка слишком длинная",
                            languageCode: gymCurrentLanguageCode()
                        ))
                        .font(.caption)
                        .foregroundStyle(GymTheme.error)
                    } else {
                        Text("\(text.unicodeScalars.count) / \(WorkoutNoteRules.maxCodePoints)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                }
            }
            .navigationTitle(initialNote == nil ? gymWorkoutNoteAddLabel() : gymWorkoutNoteLabel())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(gymText("Cancel", "Скасувати", "Отмена", languageCode: gymCurrentLanguageCode()), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(gymText("Save", "Зберегти", "Сохранить", languageCode: gymCurrentLanguageCode())) {
                        onSave(text)
                    }
                    .disabled(!isValid)
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .gymSheetPresentation(.standard)
    }
}
