import Foundation

/// Shared "repeat the last workout" rules. The editor's "Repeat latest" / "Copy previous"
/// (`AddWorkoutView.applyPreviousWorkout`) and the Today one-tap start both build their drafts from
/// `editorDrafts(from:)` and run `workoutEditorValidationMessage` before anything starts, so the
/// two paths cannot drift. Mirrors Android `repeatLastWorkoutSeed` / `repeatLastWorkoutDrafts`.
enum RepeatLastWorkout {
    /// Outcome of the Today one-tap start.
    enum Start {
        /// The active workout was created from the last workout.
        case started(ActiveWorkoutDraft)
        /// An active workout (or a live-room reservation) already owns the slot.
        case alreadyActive
        /// Nothing could be started directly (no workout with sets, deleted exercise, invalid
        /// values, data limit); the caller hands the repeat to the editor.
        case unavailable
    }

    /// The Today action shows only with a repeatable workout, no active workout and no kept draft.
    static func shouldShowAction(
        hasRepeatableWorkout: Bool,
        hasActiveWorkout: Bool,
        hasRetainedWorkoutDraft: Bool
    ) -> Bool {
        hasRepeatableWorkout && !hasActiveWorkout && !hasRetainedWorkoutDraft
    }

    /// Exercises and sets of `workout` in stored order; an exercise without sets keeps one blank set.
    static func editorDrafts(from workout: WorkoutSession) -> [WorkoutEditorExerciseDraft] {
        workout.exercises.map { block in
            let sets = block.sets.map { WorkoutEditorSetDraft(weight: $0.weight, reps: $0.reps) }
            return WorkoutEditorExerciseDraft(
                exerciseID: block.exerciseID,
                sets: sets.isEmpty ? [WorkoutEditorSetDraft()] : sets
            )
        }
    }

    /// Active-workout blocks for editor drafts. `exercise.id`/`set.id` may be seeded from the
    /// catalog exercise ID or a deterministic recommendation ID (Smart Coach) and are stable across
    /// separate workouts, so the active-workout block/set identity must be a fresh per-instance UUID
    /// instead, or repeating the same exercise later collides in WorkoutStore.
    static func activeExercises(from drafts: [WorkoutEditorExerciseDraft]) -> [ActiveWorkoutExercise] {
        drafts.map { exercise in
            ActiveWorkoutExercise(
                id: UUID(),
                exerciseID: exercise.exerciseID,
                sets: exercise.sets.map { set in
                    ActiveWorkoutSet(id: UUID(), weight: set.weight, reps: set.reps)
                }
            )
        }
    }

    /// Starts an active workout seeded from the latest stored workout without opening the editor.
    /// The seed is `editorDrafts(from:)`, checked by the editor's own Start validation; the store
    /// start enforces the active-workout / live-room / data-limit guards.
    @MainActor
    static func start(
        workoutStore: WorkoutStore,
        activeWorkoutStore: ActiveWorkoutStore,
        now: Date = Date()
    ) -> Start {
        guard activeWorkoutStore.draft == nil else { return .alreadyActive }
        guard let latest = workoutStore.latestWorkoutTemplate else { return .unavailable }
        let drafts = editorDrafts(from: latest)
        guard workoutEditorValidationMessage(
            drafts: drafts,
            date: now,
            now: now,
            exerciseExists: { workoutStore.exercise(id: $0) != nil }
        ) == nil else {
            return .unavailable
        }
        do {
            let active = try activeWorkoutStore.start(
                workoutDate: now,
                note: latest.note,
                exercises: activeExercises(from: drafts),
                workoutStore: workoutStore,
                now: now
            )
            return .started(active)
        } catch ActiveWorkoutStoreError.alreadyActive {
            return .alreadyActive
        } catch ActiveWorkoutStoreError.liveWorkoutReserved {
            return .alreadyActive
        } catch {
            return .unavailable
        }
    }
}

/// The editor's Start/Save validation, shared with the Today one-tap repeat. Nil means valid.
func workoutEditorValidationMessage(
    drafts: [WorkoutEditorExerciseDraft],
    date: Date,
    now: Date = Date(),
    exerciseExists: (UUID) -> Bool
) -> String? {
    guard !drafts.isEmpty else { return gymLocalized("Add at least one exercise.") }
    guard date <= now else {
        return gymText(
            "Workout date cannot be in the future.",
            "Дата тренування не може бути в майбутньому.",
            "Дата тренировки не может быть в будущем.",
            languageCode: gymCurrentLanguageCode()
        )
    }
    for draft in drafts {
        guard exerciseExists(draft.exerciseID) else {
            return gymLocalized("One selected exercise no longer exists.")
        }
        guard !draft.sets.isEmpty else {
            return gymLocalized("Every exercise needs at least one set.")
        }
        for set in draft.sets {
            guard set.isReadyForSave else {
                return gymText(
                    "Weight must be a finite number from 0 to 1,000,000.",
                    "Вага має бути скінченним числом від 0 до 1 000 000.",
                    "Вес должен быть конечным числом от 0 до 1 000 000.",
                    languageCode: gymCurrentLanguageCode()
                )
            }
            guard (1 ... 10_000).contains(set.reps) else {
                return gymLocalized("Repetitions must be at least one.")
            }
        }
    }
    return nil
}
