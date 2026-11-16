import SwiftUI

func gymWorkoutNoteLabel() -> String {
    gymText("Note", "Нотатка", "Заметка", languageCode: gymCurrentLanguageCode())
}

func gymWorkoutNoteAddLabel() -> String {
    gymText("Add note", "Додати нотатку", "Добавить заметку", languageCode: gymCurrentLanguageCode())
}

/// The message for a note save that threw, shown inside the still-open editor. A storage failure
/// gets a note-specific line; every other store error keeps its shared, localized message.
func gymWorkoutNoteSaveErrorMessage(
    _ error: Error,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    if (error as? ActiveWorkoutStoreError) == .storageUnavailable {
        return gymText(
            "The note could not be saved. Your text is still here.",
            "Нотатку не вдалося зберегти. Текст залишився тут.",
            "Заметку не удалось сохранить. Текст остался здесь.",
            languageCode: languageCode
        )
    }
    return gymErrorMessage(error, languageCode: languageCode)
}

/// Runs a note save and returns nil when it succeeded, otherwise the message to show in the editor.
/// The editor closes only on nil, so a refused save (stale revision, shared workout, storage failure)
/// keeps the typed text.
func gymWorkoutNoteSaveOutcome(
    languageCode: String = gymCurrentLanguageCode(),
    _ attempt: () throws -> Void
) -> String? {
    do {
        try attempt()
        return nil
    } catch {
        return gymWorkoutNoteSaveErrorMessage(error, languageCode: languageCode)
    }
}

/// The message under the field for a raw note that cannot be saved.
func gymWorkoutNoteFailureMessage(
    _ failure: WorkoutNoteRules.Failure,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    gymErrorMessage(ActiveWorkoutStoreError.note(failure), languageCode: languageCode)
}

/// Multiline editor for the active workout's note. `onSave` takes the raw text (the store trims it
/// and clears the note when it is blank) and returns nil when it saved, so the caller closes the
/// sheet, or the error message to show here with the typed text kept. Cancel discards silently;
/// swipe-to-dismiss is off while the text differs from what the sheet opened with.
struct WorkoutNoteEditorSheet: View {
    let initialNote: String?
    let onSave: (String) -> String?
    let onCancel: () -> Void

    @State private var text: String
    @State private var saveError: String?

    init(initialNote: String?, onSave: @escaping (String) -> String?, onCancel: @escaping () -> Void) {
        self.initialNote = initialNote
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: initialNote ?? "")
    }

    private var isDirty: Bool { text != (initialNote ?? "") }
    private var failure: WorkoutNoteRules.Failure? { WorkoutNoteRules.failure(text) }
    private var isValid: Bool { failure == nil }

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
                        saveError = nil
                        let limited = WorkoutNoteRules.limited(newValue)
                        if limited != newValue { text = limited }
                    }
                    if let failure {
                        Text(gymWorkoutNoteFailureMessage(failure))
                            .font(.caption)
                            .foregroundStyle(GymTheme.error)
                    } else if let saveError {
                        Text(saveError)
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
                        saveError = onSave(text)
                    }
                    .disabled(!isValid)
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .gymSheetPresentation(.standard)
    }
}
