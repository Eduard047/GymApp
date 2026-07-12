import Foundation

// MARK: - Persistent workout models

public struct Exercise: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public struct WorkoutSet: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var weight: Double
    public var reps: Int

    public init(id: UUID = UUID(), weight: Double, reps: Int) {
        self.id = id
        self.weight = weight
        self.reps = reps
    }

    public var volume: Double {
        weight * Double(reps)
    }

    public var estimatedOneRepMax: Double {
        weight * (1 + Double(reps) / 30)
    }
}

public struct WorkoutExercise: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let exerciseID: UUID
    public var sets: [WorkoutSet]

    public init(id: UUID = UUID(), exerciseID: UUID, sets: [WorkoutSet]) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
    }

    public var volume: Double {
        sets.reduce(0) { $0 + $1.volume }
    }
}

public struct WorkoutSession: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var date: Date
    public var note: String?
    public var exercises: [WorkoutExercise]

    public init(
        id: UUID = UUID(),
        date: Date,
        note: String? = nil,
        exercises: [WorkoutExercise]
    ) {
        self.id = id
        self.date = date
        self.note = note
        self.exercises = exercises
    }

    public var setCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    public var totalVolume: Double {
        exercises.reduce(0) { $0 + $1.volume }
    }
}

public struct WorkoutSetDraft: Codable, Hashable, Sendable {
    public var weight: Double
    public var reps: Int

    public init(weight: Double, reps: Int) {
        self.weight = weight
        self.reps = reps
    }
}

public struct WorkoutExerciseDraft: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID { exerciseID }
    public let exerciseID: UUID
    public var sets: [WorkoutSetDraft]

    public init(exerciseID: UUID, sets: [WorkoutSetDraft]) {
        self.exerciseID = exerciseID
        self.sets = sets
    }
}

public struct NamedWorkoutSetDraft: Codable, Hashable, Sendable {
    public var exerciseName: String
    public var weight: Double
    public var reps: Int

    public init(exerciseName: String, weight: Double, reps: Int) {
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
    }
}

public struct WorkoutDraft: Codable, Hashable, Sendable {
    public var date: Date
    public var note: String?
    public var exercises: [WorkoutExerciseDraft]

    public init(date: Date, note: String? = nil, exercises: [WorkoutExerciseDraft]) {
        self.date = date
        self.note = note
        self.exercises = exercises
    }
}

// MARK: - Read models and statistics

public struct WorkoutSessionSummary: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID { workoutID }
    public let workoutID: UUID
    public let date: Date
    public let note: String?
    public let exerciseCount: Int
    public let setCount: Int
    public let totalVolume: Double

    public init(
        workoutID: UUID,
        date: Date,
        note: String?,
        exerciseCount: Int,
        setCount: Int,
        totalVolume: Double
    ) {
        self.workoutID = workoutID
        self.date = date
        self.note = note
        self.exerciseCount = exerciseCount
        self.setCount = setCount
        self.totalVolume = totalVolume
    }
}

public struct ExerciseHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID { setID }
    public let setID: UUID
    public let workoutID: UUID
    public let sessionDate: Date
    public let exerciseID: UUID
    public let exerciseName: String
    public let weight: Double
    public let reps: Int
    public let setOrderIndex: Int

    public init(
        setID: UUID,
        workoutID: UUID,
        sessionDate: Date,
        exerciseID: UUID,
        exerciseName: String,
        weight: Double,
        reps: Int,
        setOrderIndex: Int
    ) {
        self.setID = setID
        self.workoutID = workoutID
        self.sessionDate = sessionDate
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.setOrderIndex = setOrderIndex
    }

    public var volume: Double {
        weight * Double(reps)
    }

    public var estimatedOneRepMax: Double {
        weight * (1 + Double(reps) / 30)
    }
}

public struct DashboardStats: Codable, Hashable, Sendable {
    public let workoutCount: Int
    public let totalVolume: Double
    public let averageIntensity: Double
    public let streakDays: Int
    public let weeklyStreakWeeks: Int

    public init(
        workoutCount: Int,
        totalVolume: Double,
        averageIntensity: Double,
        streakDays: Int,
        weeklyStreakWeeks: Int
    ) {
        self.workoutCount = workoutCount
        self.totalVolume = totalVolume
        self.averageIntensity = averageIntensity
        self.streakDays = streakDays
        self.weeklyStreakWeeks = weeklyStreakWeeks
    }
}

public struct ExerciseProgressStats: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID { exerciseID }
    public let exerciseID: UUID
    public let sessionCount: Int
    public let setCount: Int
    public let totalVolume: Double
    public let maxWeight: Double
    public let bestEstimatedOneRepMax: Double
    public let latestWeight: Double?

    public init(
        exerciseID: UUID,
        sessionCount: Int,
        setCount: Int,
        totalVolume: Double,
        maxWeight: Double,
        bestEstimatedOneRepMax: Double,
        latestWeight: Double?
    ) {
        self.exerciseID = exerciseID
        self.sessionCount = sessionCount
        self.setCount = setCount
        self.totalVolume = totalVolume
        self.maxWeight = maxWeight
        self.bestEstimatedOneRepMax = bestEstimatedOneRepMax
        self.latestWeight = latestWeight
    }
}

public enum PersonalRecordKind: String, Codable, CaseIterable, Sendable {
    case maxWeight
    case estimatedOneRepMax
    case sessionVolume
}

public struct PersonalRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(exerciseID.uuidString):\(kind.rawValue)" }
    public let exerciseID: UUID
    public let kind: PersonalRecordKind
    public let value: Double
    public let achievedAt: Date
    public let workoutID: UUID
    public let setID: UUID?

    public init(
        exerciseID: UUID,
        kind: PersonalRecordKind,
        value: Double,
        achievedAt: Date,
        workoutID: UUID,
        setID: UUID? = nil
    ) {
        self.exerciseID = exerciseID
        self.kind = kind
        self.value = value
        self.achievedAt = achievedAt
        self.workoutID = workoutID
        self.setID = setID
    }
}

public struct SyncProfileStats: Codable, Hashable, Sendable {
    public let xp: Int
    public let level: Int
    public let workouts: Int

    public init(xp: Int, level: Int, workouts: Int) {
        self.xp = xp
        self.level = level
        self.workouts = workouts
    }
}

// MARK: - Muscle mapping models

public struct ExerciseMuscleMapping: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(exerciseNameKey)|\(muscleID)" }
    public let exerciseNameKey: String
    public var exerciseName: String
    public let muscleID: String
    public var weight: Double
    public var updatedAt: Date

    public init(
        exerciseNameKey: String,
        exerciseName: String,
        muscleID: String,
        weight: Double,
        updatedAt: Date = Date()
    ) {
        self.exerciseNameKey = exerciseNameKey
        self.exerciseName = exerciseName
        self.muscleID = muscleID
        self.weight = weight
        self.updatedAt = updatedAt
    }
}

public struct MuscleLoad: Codable, Identifiable, Hashable, Sendable {
    public var id: String { muscleID }
    public let muscleID: String
    public let load: Double
    public let lastTrainedAt: Date?

    public init(muscleID: String, load: Double, lastTrainedAt: Date?) {
        self.muscleID = muscleID
        self.load = load
        self.lastTrainedAt = lastTrainedAt
    }
}

// MARK: - Local snapshot

public struct WorkoutDataSnapshot: Codable, Hashable, Sendable {
    public var exercises: [Exercise]
    public var workouts: [WorkoutSession]
    public var muscleMappings: [ExerciseMuscleMapping]

    public init(
        exercises: [Exercise] = [],
        workouts: [WorkoutSession] = [],
        muscleMappings: [ExerciseMuscleMapping] = []
    ) {
        self.exercises = exercises
        self.workouts = workouts
        self.muscleMappings = muscleMappings
    }
}

// MARK: - Android-compatible backup schema v2

public struct BackupOwner: Codable, Hashable, Sendable {
    public var accountID: String?
    public var userID: String?
    public var email: String?
    public var remote: Bool

    public init(
        accountID: String? = nil,
        userID: String? = nil,
        email: String? = nil,
        remote: Bool = false
    ) {
        self.accountID = accountID
        self.userID = userID
        self.email = email
        self.remote = remote
    }

    private enum CodingKeys: String, CodingKey {
        case accountID = "accountId"
        case userID = "userId"
        case email
        case remote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID)?.nilIfJSONNull
        userID = try container.decodeIfPresent(String.self, forKey: .userID)?.nilIfJSONNull
        email = try container.decodeIfPresent(String.self, forKey: .email)?.nilIfJSONNull
        remote = try container.decodeIfPresent(Bool.self, forKey: .remote) ?? false
    }
}

public struct BackupExercise: Codable, Hashable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public struct BackupSet: Codable, Hashable, Sendable {
    public var weight: Double
    public var reps: Int

    public init(weight: Double, reps: Int) {
        self.weight = weight
        self.reps = reps
    }
}

public struct BackupWorkoutExercise: Codable, Hashable, Sendable {
    public var name: String
    public var sets: [BackupSet]

    public init(name: String, sets: [BackupSet]) {
        self.name = name
        self.sets = sets
    }
}

/// Legacy flat-set shape accepted by the Android importer and retained for parity.
public struct LegacyBackupSet: Codable, Hashable, Sendable {
    public var exerciseName: String?
    public var name: String?
    public var weight: Double
    public var reps: Int

    public init(
        exerciseName: String? = nil,
        name: String? = nil,
        weight: Double,
        reps: Int
    ) {
        self.exerciseName = exerciseName
        self.name = name
        self.weight = weight
        self.reps = reps
    }
}

public struct BackupSession: Codable, Hashable, Sendable {
    public var date: Int64?
    public var startedAt: Int64?
    public var note: String?
    public var exercises: [BackupWorkoutExercise]?
    public var sets: [LegacyBackupSet]?

    public init(
        date: Int64,
        note: String? = nil,
        exercises: [BackupWorkoutExercise]
    ) {
        self.date = date
        self.startedAt = nil
        self.note = note
        self.exercises = exercises
        self.sets = nil
    }
}

public struct BackupSummary: Codable, Hashable, Sendable {
    public var exerciseCount: Int
    public var sessionCount: Int
    public var setCount: Int
    public var totalVolume: Double

    public init(exerciseCount: Int, sessionCount: Int, setCount: Int, totalVolume: Double) {
        self.exerciseCount = exerciseCount
        self.sessionCount = sessionCount
        self.setCount = setCount
        self.totalVolume = totalVolume
    }
}

public struct GymBackup: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var exportedAt: Int64
    public var app: String
    public var diagnostics: Bool
    public var owner: BackupOwner?
    public var exercises: [BackupExercise]
    public var sessions: [BackupSession]
    public var summary: BackupSummary?

    public init(
        schemaVersion: Int = GymBackup.currentSchemaVersion,
        exportedAt: Int64,
        app: String = "GymApp",
        diagnostics: Bool,
        owner: BackupOwner?,
        exercises: [BackupExercise],
        sessions: [BackupSession],
        summary: BackupSummary?
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.app = app
        self.diagnostics = diagnostics
        self.owner = owner
        self.exercises = exercises
        self.sessions = sessions
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, app, diagnostics, owner, exercises, sessions, summary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        if let integer = try? container.decode(Int64.self, forKey: .exportedAt) {
            exportedAt = integer
        } else {
            exportedAt = Int64(try container.decode(Double.self, forKey: .exportedAt).rounded())
        }
        app = try container.decodeIfPresent(String.self, forKey: .app) ?? "GymApp"
        diagnostics = try container.decodeIfPresent(Bool.self, forKey: .diagnostics) ?? false
        owner = try container.decodeIfPresent(BackupOwner.self, forKey: .owner)
        exercises = try container.decodeIfPresent([BackupExercise].self, forKey: .exercises) ?? []
        sessions = try container.decodeIfPresent([BackupSession].self, forKey: .sessions) ?? []
        summary = try container.decodeIfPresent(BackupSummary.self, forKey: .summary)
    }
}

public struct BackupImportLimits: Codable, Hashable, Sendable {
    public static let standard = BackupImportLimits()

    public var maximumFileBytes: Int
    public var maximumExercises: Int
    public var maximumSessions: Int
    public var maximumExercisesPerSession: Int
    public var maximumSetsPerExercise: Int
    public var maximumTotalSets: Int
    public var maximumExerciseNameLength: Int
    public var maximumNoteLength: Int

    public init(
        maximumFileBytes: Int = 8 * 1_024 * 1_024,
        maximumExercises: Int = 2_000,
        maximumSessions: Int = 5_000,
        maximumExercisesPerSession: Int = 100,
        maximumSetsPerExercise: Int = 100,
        maximumTotalSets: Int = 100_000,
        maximumExerciseNameLength: Int = 160,
        maximumNoteLength: Int = 4_000
    ) {
        self.maximumFileBytes = maximumFileBytes
        self.maximumExercises = maximumExercises
        self.maximumSessions = maximumSessions
        self.maximumExercisesPerSession = maximumExercisesPerSession
        self.maximumSetsPerExercise = maximumSetsPerExercise
        self.maximumTotalSets = maximumTotalSets
        self.maximumExerciseNameLength = maximumExerciseNameLength
        self.maximumNoteLength = maximumNoteLength
    }
}

public struct BackupImportResult: Codable, Hashable, Sendable {
    public let importedSessions: Int
    public let skippedDuplicateSessions: Int
    public let addedExercises: Int
    public let ignoredInvalidSets: Int

    public init(
        importedSessions: Int,
        skippedDuplicateSessions: Int,
        addedExercises: Int,
        ignoredInvalidSets: Int
    ) {
        self.importedSessions = importedSessions
        self.skippedDuplicateSessions = skippedDuplicateSessions
        self.addedExercises = addedExercises
        self.ignoredInvalidSets = ignoredInvalidSets
    }
}

// MARK: - Shared date/string helpers

extension Date {
    var gymEpochMilliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded())
    }

    init(gymEpochMilliseconds: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(gymEpochMilliseconds) / 1_000)
    }
}

extension Calendar {
    func gymEpochDay(for date: Date) -> Int64 {
        let day = startOfDay(for: date)
        var components = DateComponents()
        components.calendar = self
        components.timeZone = timeZone
        components.year = 1970
        components.month = 1
        components.day = 1
        guard let epoch = self.date(from: components),
              let days = dateComponents([.day], from: epoch, to: day).day else {
            return 0
        }
        return Int64(days)
    }

    func gymDate(forEpochDay epochDay: Int64) -> Date {
        var components = DateComponents()
        components.calendar = self
        components.timeZone = timeZone
        components.year = 1970
        components.month = 1
        components.day = 1
        let epoch = date(from: components) ?? Date(timeIntervalSince1970: 0)
        return date(byAdding: .day, value: Int(epochDay), to: epoch) ?? epoch
    }

    func gymDaysBetween(_ earlier: Date, _ later: Date) -> Int {
        max(0, dateComponents([.day], from: startOfDay(for: earlier), to: startOfDay(for: later)).day ?? 0)
    }

    func gymMondayStart(of date: Date) -> Date {
        let day = startOfDay(for: date)
        let weekday = component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return self.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }
}

extension String {
    var gymTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfJSONNull: String? {
        let value = gymTrimmed
        return value.isEmpty || value == "null" ? nil : value
    }
}
