import Foundation

/// Where the active workout moves its current-set focus after the user records one set.
/// Mirrors Android `NextSetFocus`; both run shared/next-set-focus-v1.json.
enum NextSetFocus {
    struct SetPosition: Equatable, Hashable {
        var exerciseIndex: Int
        var setIndex: Int
    }

    struct SetState: Equatable {
        var exerciseIndex: Int
        var setIndex: Int
        var completed: Bool
    }

    /// The first incomplete set after `recorded` in workout order (rest of its exercise, then the
    /// following exercises); when none is left, the first incomplete set before it; nil when every set
    /// is complete (no focus change). Fully completed exercises hold no incomplete set, so they are
    /// skipped on their own.
    static func next(in sets: [SetState], after recorded: SetPosition) -> SetPosition? {
        let ordered = sets.sorted {
            ($0.exerciseIndex, $0.setIndex) < ($1.exerciseIndex, $1.setIndex)
        }
        let key = (recorded.exerciseIndex, recorded.setIndex)
        let target = ordered.first { !$0.completed && ($0.exerciseIndex, $0.setIndex) > key }
            ?? ordered.first { !$0.completed && ($0.exerciseIndex, $0.setIndex) < key }
        return target.map { SetPosition(exerciseIndex: $0.exerciseIndex, setIndex: $0.setIndex) }
    }

    /// The set to move to after `recordedSetID` was recorded in `draft`, or nil.
    static func nextSetID(in draft: ActiveWorkoutDraft, afterRecorded recordedSetID: UUID) -> UUID? {
        var states: [SetState] = []
        var recorded: SetPosition?
        var ids: [SetPosition: UUID] = [:]
        for (exerciseIndex, exercise) in draft.exercises.enumerated() {
            for (setIndex, set) in exercise.sets.enumerated() {
                let position = SetPosition(exerciseIndex: exerciseIndex, setIndex: setIndex)
                states.append(SetState(exerciseIndex: exerciseIndex, setIndex: setIndex, completed: set.isCompleted))
                ids[position] = set.id
                if set.id == recordedSetID { recorded = position }
            }
        }
        guard let recorded, let target = next(in: states, after: recorded) else { return nil }
        return ids[target]
    }
}
