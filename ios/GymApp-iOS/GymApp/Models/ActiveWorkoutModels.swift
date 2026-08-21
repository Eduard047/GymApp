import Foundation

/// Device-local workout progress. This type is intentionally absent from
/// `WorkoutDataSnapshot`, `GymBackup`, and the cloud extension envelope.
struct ActiveWorkoutSet: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var weight: Double
    var reps: Int
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        weight: Double,
        reps: Int,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.weight = weight == 0 ? 0.0 : weight
        self.reps = reps
        self.completedAt = completedAt
    }

    var isCompleted: Bool { completedAt != nil }
}

struct ActiveWorkoutExercise: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var exerciseID: UUID
    /// Stable local identity used to rebind the draft when an authoritative cloud
    /// restore recreates iOS UUIDs. These fields never enter the shared backup.
    let exerciseName: String?
    let exerciseCatalogKey: String?
    var sets: [ActiveWorkoutSet]

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        exerciseName: String? = nil,
        exerciseCatalogKey: String? = nil,
        sets: [ActiveWorkoutSet]
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.exerciseCatalogKey = exerciseCatalogKey
        self.sets = sets
    }
}

/// Frozen, device-local completion intent. Once persisted, the active draft is
/// read-only until the history commit is confirmed and the companion file is cleared.
/// This never enters `WorkoutDataSnapshot`, `GymBackup`, or the cloud envelope.
struct ActiveWorkoutCommitExercise: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let preferredExerciseID: UUID
    let exerciseName: String
    let exerciseCatalogKey: String?
    let sets: [WorkoutSet]
}

struct ActiveWorkoutCommitIntent: Codable, Equatable, Sendable {
    let workoutID: UUID
    let workoutDate: Date
    let note: String?
    let preparedAt: Date
    let durationSeconds: Int?
    let exercises: [ActiveWorkoutCommitExercise]

    init(
        workoutID: UUID,
        workoutDate: Date,
        note: String?,
        preparedAt: Date,
        durationSeconds: Int? = nil,
        exercises: [ActiveWorkoutCommitExercise]
    ) {
        self.workoutID = workoutID
        self.workoutDate = workoutDate
        self.note = note
        self.preparedAt = preparedAt
        self.durationSeconds = durationSeconds
        self.exercises = exercises
    }
}

/// Local-only stopwatch state. The workout's editable envelope remains backward
/// compatible because older app builds ignore this optional field, while current
/// builds can restore active time without counting a persisted rest interval.
struct ActiveWorkoutTimingState: Codable, Equatable, Sendable {
    var accumulatedActiveSeconds: Double
    var activeSince: Date?
    var restingUntil: Date?

    init(
        accumulatedActiveSeconds: Double = 0,
        activeSince: Date? = nil,
        restingUntil: Date? = nil
    ) {
        self.accumulatedActiveSeconds = accumulatedActiveSeconds
        self.activeSince = activeSince
        self.restingUntil = restingUntil
    }
}

struct ActiveWorkoutDraft: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    var workoutDate: Date
    var note: String?
    var exercises: [ActiveWorkoutExercise]
    /// The single completion that can still be undone. Clearing it after undo keeps
    /// every earlier completion immutable instead of enabling cascading undo.
    var undoableSetID: UUID?
    var revision: UInt64
    var lastModifiedAt: Date
    var commitIntent: ActiveWorkoutCommitIntent?
    /// Optional so active drafts written by releases before the active stopwatch
    /// continue to decode without a schema-version change.
    var timing: ActiveWorkoutTimingState?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        workoutDate: Date,
        note: String? = nil,
        exercises: [ActiveWorkoutExercise],
        undoableSetID: UUID? = nil,
        revision: UInt64 = 0,
        lastModifiedAt: Date = Date(),
        commitIntent: ActiveWorkoutCommitIntent? = nil,
        timing: ActiveWorkoutTimingState? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.workoutDate = workoutDate
        self.note = note
        self.exercises = exercises
        self.undoableSetID = undoableSetID
        self.revision = revision
        self.lastModifiedAt = lastModifiedAt
        self.commitIntent = commitIntent
        self.timing = timing
    }

    var completedSetCount: Int {
        exercises.reduce(0) { count, exercise in
            count + exercise.sets.lazy.filter(\.isCompleted).count
        }
    }

    var plannedSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    /// User-facing workout duration. It is a continuous wall-clock value from
    /// the durable workout start and intentionally includes rest intervals.
    func totalElapsedSeconds(at date: Date = Date()) -> TimeInterval {
        max(0, date.timeIntervalSince(startedAt))
    }

    func activeElapsedSeconds(at date: Date = Date()) -> TimeInterval {
        guard let timing else {
            return max(0, date.timeIntervalSince(startedAt))
        }
        let runningSeconds: TimeInterval
        if let activeSince = timing.activeSince {
            runningSeconds = max(0, date.timeIntervalSince(activeSince))
        } else if let restingUntil = timing.restingUntil, date > restingUntil {
            runningSeconds = max(0, date.timeIntervalSince(restingUntil))
        } else {
            runningSeconds = 0
        }
        return max(0, timing.accumulatedActiveSeconds + runningSeconds)
    }
}
