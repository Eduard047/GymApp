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
    let exercises: [ActiveWorkoutCommitExercise]
}

struct ActiveWorkoutDraft: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    var workoutDate: Date
    var note: String?
    var exercises: [ActiveWorkoutExercise]
    var revision: UInt64
    var lastModifiedAt: Date
    var commitIntent: ActiveWorkoutCommitIntent?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        workoutDate: Date,
        note: String? = nil,
        exercises: [ActiveWorkoutExercise],
        revision: UInt64 = 0,
        lastModifiedAt: Date = Date(),
        commitIntent: ActiveWorkoutCommitIntent? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.workoutDate = workoutDate
        self.note = note
        self.exercises = exercises
        self.revision = revision
        self.lastModifiedAt = lastModifiedAt
        self.commitIntent = commitIntent
    }

    var completedSetCount: Int {
        exercises.reduce(0) { count, exercise in
            count + exercise.sets.lazy.filter(\.isCompleted).count
        }
    }

    var plannedSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }
}
