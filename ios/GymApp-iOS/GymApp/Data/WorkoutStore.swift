import Combine
import Foundation

public enum WorkoutStoreError: Error, LocalizedError, Equatable, Sendable {
    case invalidAccountStorageKey
    case corruptStore(String)
    case storageAccountMismatch
    case invalidExerciseName
    case duplicateExerciseName
    case exerciseNotFound
    case exerciseInUse
    case workoutNotFound
    case workoutExerciseNotFound
    case setNotFound
    case invalidWorkout(String)
    case invalidWeight
    case invalidReps
    case unsupportedBackupSchema(Int)
    case malformedBackup(String)
    case backupOwnerMismatch
    case importLimitExceeded(String)
    case persistenceFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAccountStorageKey:
            return "The account storage key is empty or too long."
        case let .corruptStore(message):
            return "The local workout store is invalid: \(message)"
        case .storageAccountMismatch:
            return "The local workout file belongs to another account."
        case .invalidExerciseName:
            return "Enter a valid exercise name."
        case .duplicateExerciseName:
            return "An exercise with this name already exists."
        case .exerciseNotFound:
            return "The exercise no longer exists."
        case .exerciseInUse:
            return "The exercise is used by saved workouts."
        case .workoutNotFound:
            return "The workout no longer exists."
        case .workoutExerciseNotFound:
            return "The exercise entry no longer exists in this workout."
        case .setNotFound:
            return "The set no longer exists."
        case let .invalidWorkout(message):
            return "The workout is invalid: \(message)"
        case .invalidWeight:
            return "Weight must be a finite non-negative number."
        case .invalidReps:
            return "Repetitions must be between 1 and 10,000."
        case let .unsupportedBackupSchema(version):
            return "Backup schema version \(version) is not supported."
        case let .malformedBackup(message):
            return "The backup is invalid: \(message)"
        case .backupOwnerMismatch:
            return "This backup belongs to another account."
        case let .importLimitExceeded(limit):
            return "The backup exceeds the allowed \(limit) limit."
        case let .persistenceFailure(message):
            return "Workout data could not be saved: \(message)"
        }
    }
}

struct WorkoutStoreOpenResult {
    let store: WorkoutStore
    let quarantinedFileURL: URL?
}

struct PreparedCloudBackup {
    let data: Data
    /// Only the native v2 envelope is safe to write back losslessly. Legacy PWA
    /// payloads contain profile/language/mapping fields that the native model cannot retain.
    let roundTripSafe: Bool
}

/// Account-scoped, dependency-free workout repository.
///
/// Every mutation is validated, encoded as one snapshot and written with
/// `Data.WritingOptions.atomic` before the published state is changed. Creating the
/// store never seeds demo content; `seedDemoData` is the only demo entry point.
@MainActor
public final class WorkoutStore: ObservableObject {
    @Published public private(set) var exercises: [Exercise]
    @Published public private(set) var workouts: [WorkoutSession]
    @Published public private(set) var muscleMappings: [ExerciseMuscleMapping]

    public private(set) var accountStorageKey: String
    public private(set) var storageURL: URL

    public var snapshot: WorkoutDataSnapshot {
        WorkoutDataSnapshot(
            exercises: exercises,
            workouts: workouts,
            muscleMappings: muscleMappings
        )
    }

    public var workoutSummaries: [WorkoutSessionSummary] {
        workouts
            .filter { $0.setCount > 0 }
            .map(Self.summary)
            .sorted { $0.date > $1.date }
    }

    public var latestWorkoutTemplate: WorkoutSession? {
        workouts
            .filter { $0.setCount > 0 }
            .max { $0.date < $1.date }
    }

    private let directoryURL: URL
    private let fileManager: FileManager

    private static let persistedSchemaVersion = 1
    private static let maximumAccountStorageKeyLength = 128
    private static let maximumExerciseNameLength = 160
    private static let maximumNoteLength = 4_000
    private static let maximumWeight = 1_000_000.0
    private static let maximumReps = 10_000
    // Foundation's documented practical Date domain. This preserves legitimate
    // historical/future data while excluding values that cannot round-trip safely.
    private static let minimumSupportedTimestampMilliseconds: Int64 = -62_135_769_600_000
    private static let maximumSupportedTimestampMilliseconds: Int64 = 64_092_211_200_000
    private static let maximumOwnerFieldBytes = 512
    private static let maximumCatalogKeyBytes = 256
    private static let maximumAppNameBytes = 128

    private struct PersistedEnvelope: Codable {
        var schemaVersion: Int
        var accountStorageKey: String
        var savedAt: Date
        var snapshot: WorkoutDataSnapshot
    }

    public init(
        accountStorageKey: String,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let key = try Self.validatedStorageKey(accountStorageKey)
        let directory = try directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.excludePrivateItemFromBackup(directory)
        let fileURL = Self.fileURL(for: key, in: directory)
        if fileManager.fileExists(atPath: fileURL.path) {
            try Self.excludePrivateItemFromBackup(fileURL)
        }
        let loaded = try Self.load(
            accountStorageKey: key,
            from: fileURL,
            fileManager: fileManager
        )

        self.accountStorageKey = key
        self.directoryURL = directory
        self.storageURL = fileURL
        self.fileManager = fileManager
        self.exercises = loaded.exercises
        self.workouts = loaded.workouts
        self.muscleMappings = loaded.muscleMappings
    }

    /// Opens the account store while preserving an unreadable or mismatched envelope.
    /// The damaged file is moved aside before a fresh persistent store is created, so
    /// launch never needs to discard the only copy of the user's local data.
    static func openRecoveringCorruptStore(
        accountStorageKey: String,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> WorkoutStoreOpenResult {
        do {
            return WorkoutStoreOpenResult(
                store: try WorkoutStore(
                    accountStorageKey: accountStorageKey,
                    directoryURL: directoryURL,
                    fileManager: fileManager
                ),
                quarantinedFileURL: nil
            )
        } catch let error as WorkoutStoreError {
            switch error {
            case .corruptStore, .storageAccountMismatch:
                break
            default:
                throw error
            }
        }

        let key = try validatedStorageKey(accountStorageKey)
        let resolvedDirectory: URL
        if let directoryURL {
            resolvedDirectory = directoryURL
        } else {
            resolvedDirectory = try defaultDirectory(fileManager: fileManager)
        }
        try fileManager.createDirectory(
            at: resolvedDirectory,
            withIntermediateDirectories: true
        )
        try excludePrivateItemFromBackup(resolvedDirectory)

        let sourceURL = fileURL(for: key, in: resolvedDirectory)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw WorkoutStoreError.corruptStore("The damaged local file is unavailable.")
        }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let quarantineURL = resolvedDirectory.appendingPathComponent(
            "\(stem).recovery-\(UUID().uuidString.lowercased()).json",
            isDirectory: false
        )
        do {
            try fileManager.moveItem(at: sourceURL, to: quarantineURL)
            try excludePrivateItemFromBackup(quarantineURL)
        } catch {
            if fileManager.fileExists(atPath: quarantineURL.path),
               !fileManager.fileExists(atPath: sourceURL.path) {
                try? fileManager.moveItem(at: quarantineURL, to: sourceURL)
            }
            throw WorkoutStoreError.persistenceFailure(
                "The damaged local file could not be preserved: \(error.localizedDescription)"
            )
        }

        do {
            let store = try WorkoutStore(
                accountStorageKey: key,
                directoryURL: resolvedDirectory,
                fileManager: fileManager
            )
            return WorkoutStoreOpenResult(
                store: store,
                quarantinedFileURL: quarantineURL
            )
        } catch {
            // Best effort rollback keeps the original account file in its expected place
            // when creating the replacement store fails for an unrelated filesystem reason.
            if !fileManager.fileExists(atPath: sourceURL.path) {
                try? fileManager.moveItem(at: quarantineURL, to: sourceURL)
            }
            throw error
        }
    }

    public func switchAccount(to accountStorageKey: String) throws {
        let key = try Self.validatedStorageKey(accountStorageKey)
        guard key != self.accountStorageKey else { return }

        let fileURL = Self.fileURL(for: key, in: directoryURL)
        if fileManager.fileExists(atPath: fileURL.path) {
            try Self.excludePrivateItemFromBackup(fileURL)
        }
        let loaded = try Self.load(
            accountStorageKey: key,
            from: fileURL,
            fileManager: fileManager
        )
        self.accountStorageKey = key
        self.storageURL = fileURL
        publish(Self.normalized(loaded))
    }

    public func clearAllData() throws {
        try commit(WorkoutDataSnapshot())
    }

    /// Removes the account-scoped file itself, used after an account/profile is deleted.
    /// Unlike `clearAllData`, this leaves no envelope containing the former storage key.
    public func destroyAccountData() throws {
        let empty = WorkoutDataSnapshot()
        // Stop exposing the deleted account's payload immediately. Persisting the empty
        // envelope before unlinking also makes a failed remove safe and retryable.
        publish(empty)
        do {
            try persist(empty)
            try Self.destroyAccountFiles(
                accountStorageKey: accountStorageKey,
                directoryURL: directoryURL,
                fileManager: fileManager
            )
        } catch let error as WorkoutStoreError {
            throw error
        } catch {
            throw WorkoutStoreError.persistenceFailure(error.localizedDescription)
        }
    }

    /// Removes the primary envelope and recovery copies for exactly one account.
    /// This does not decode the envelope, so deletion can still finish after corruption.
    public static func destroyAccountFiles(
        accountStorageKey: String,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let key = try validatedStorageKey(accountStorageKey)
        let directory = try directoryURL ?? defaultDirectory(fileManager: fileManager)
        guard fileManager.fileExists(atPath: directory.path) else { return }

        let primaryURL = fileURL(for: key, in: directory)
        let primaryStem = primaryURL.deletingPathExtension().lastPathComponent
        let recoveryPrefix = "\(primaryStem).recovery-"
        var candidates = [primaryURL]
        do {
            let children = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            candidates.append(contentsOf: children.filter { child in
                let name = child.lastPathComponent
                guard name.hasPrefix(recoveryPrefix), name.hasSuffix(".json") else {
                    return false
                }
                let start = name.index(name.startIndex, offsetBy: recoveryPrefix.count)
                let end = name.index(name.endIndex, offsetBy: -".json".count)
                return UUID(uuidString: String(name[start ..< end])) != nil
            })
        } catch {
            throw WorkoutStoreError.persistenceFailure(error.localizedDescription)
        }

        var firstError: Error?
        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            do {
                try fileManager.removeItem(at: candidate)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError {
            throw WorkoutStoreError.persistenceFailure(firstError.localizedDescription)
        }
    }

    public func saveNow() throws {
        try persist(Self.normalized(snapshot))
    }

    // MARK: Exercise CRUD

    @discardableResult
    public func addExercise(name: String) throws -> Exercise {
        let cleaned = try Self.validatedExerciseName(name)
        var created: Exercise?
        try mutate { state in
            guard !state.exercises.contains(where: {
                Self.exerciseIdentityConflicts($0, candidateName: cleaned)
            }) else {
                throw WorkoutStoreError.duplicateExerciseName
            }
            let exercise = Exercise(name: cleaned)
            state.exercises.append(exercise)
            created = exercise
        }
        return created!
    }

    public func renameExercise(id: UUID, to newName: String) throws {
        let cleaned = try Self.validatedExerciseName(newName)
        try mutate { state in
            guard let index = state.exercises.firstIndex(where: { $0.id == id }) else {
                throw WorkoutStoreError.exerciseNotFound
            }
            guard !state.exercises.contains(where: {
                $0.id != id && Self.exerciseIdentityConflicts($0, candidateName: cleaned)
            }) else {
                throw WorkoutStoreError.duplicateExerciseName
            }

            let oldName = state.exercises[index].name
            let oldKey = MuscleMappingEngine.normalizeExerciseName(oldName)
            let newKey = MuscleMappingEngine.normalizeExerciseName(cleaned)
            state.exercises[index].name = cleaned
            state.exercises[index].catalogKey = BuiltInExerciseCatalog.canonicalKey(forName: cleaned)

            var merged: [String: ExerciseMuscleMapping] = [:]
            for mapping in state.muscleMappings {
                var value = mapping
                if mapping.exerciseNameKey == oldKey {
                    value = ExerciseMuscleMapping(
                        exerciseNameKey: newKey,
                        exerciseName: cleaned,
                        muscleID: mapping.muscleID,
                        weight: mapping.weight,
                        updatedAt: Date()
                    )
                }
                merged[value.id] = value
            }
            state.muscleMappings = Array(merged.values)
        }
    }

    public func deleteExercise(id: UUID, cascadeFromWorkouts: Bool = true) throws {
        try mutate { state in
            guard state.exercises.contains(where: { $0.id == id }) else {
                throw WorkoutStoreError.exerciseNotFound
            }
            let isUsed = state.workouts.contains { workout in
                workout.exercises.contains { $0.exerciseID == id }
            }
            if isUsed && !cascadeFromWorkouts {
                throw WorkoutStoreError.exerciseInUse
            }

            let nameKey = state.exercises
                .first(where: { $0.id == id })
                .map { MuscleMappingEngine.normalizeExerciseName($0.name) }
            state.exercises.removeAll { $0.id == id }
            state.muscleMappings.removeAll { $0.exerciseNameKey == nameKey }
            if cascadeFromWorkouts {
                state.workouts = state.workouts.compactMap { workout in
                    var updated = workout
                    updated.exercises.removeAll { $0.exerciseID == id }
                    return updated.exercises.isEmpty ? nil : updated
                }
            }
        }
    }

    public func exercise(id: UUID) -> Exercise? {
        exercises.first { $0.id == id }
    }

    public func exercise(named name: String) -> Exercise? {
        exercises.first { Self.namesEqual($0.name, name) }
    }

    // MARK: Workout CRUD and templates

    @discardableResult
    public func createWorkout(
        date: Date,
        note: String? = nil,
        exercises drafts: [WorkoutExerciseDraft]
    ) throws -> WorkoutSession {
        var created: WorkoutSession?
        try mutate { state in
            let workout = try Self.makeWorkout(
                date: date,
                note: note,
                drafts: drafts,
                knownExerciseIDs: Set(state.exercises.map(\.id))
            )
            state.workouts.append(workout)
            created = workout
        }
        return created!
    }

    @discardableResult
    public func createWorkout(
        date: Date,
        note: String? = nil,
        namedSets: [NamedWorkoutSetDraft]
    ) throws -> WorkoutSession? {
        guard !namedSets.isEmpty else { return nil }
        var created: WorkoutSession?
        try mutate { state in
            var exerciseIDByKey = Dictionary(
                uniqueKeysWithValues: state.exercises.map { (Self.nameKey($0.name), $0.id) }
            )
            var orderedIDs: [UUID] = []
            var grouped: [UUID: [WorkoutSetDraft]] = [:]

            for set in namedSets {
                let cleanedName = set.exerciseName.gymTrimmed
                guard !cleanedName.isEmpty else { continue }
                let name = try Self.validatedExerciseName(cleanedName)
                try Self.validate(weight: set.weight, reps: set.reps)
                let key = Self.nameKey(name)
                let exerciseID: UUID
                if let existing = exerciseIDByKey[key] {
                    exerciseID = existing
                } else {
                    let exercise = Exercise(name: name)
                    state.exercises.append(exercise)
                    exerciseIDByKey[key] = exercise.id
                    exerciseID = exercise.id
                }
                if grouped[exerciseID] == nil { orderedIDs.append(exerciseID) }
                grouped[exerciseID, default: []].append(
                    WorkoutSetDraft(weight: set.weight, reps: set.reps)
                )
            }

            let drafts = orderedIDs.compactMap { exerciseID -> WorkoutExerciseDraft? in
                guard let sets = grouped[exerciseID], !sets.isEmpty else { return nil }
                return WorkoutExerciseDraft(exerciseID: exerciseID, sets: sets)
            }
            guard !drafts.isEmpty else { return }
            let workout = try Self.makeWorkout(
                date: date,
                note: note,
                drafts: drafts,
                knownExerciseIDs: Set(state.exercises.map(\.id))
            )
            state.workouts.append(workout)
            created = workout
        }
        return created
    }

    public func updateWorkout(id: UUID, date: Date, note: String?) throws {
        try mutate { state in
            guard let index = state.workouts.firstIndex(where: { $0.id == id }) else {
                throw WorkoutStoreError.workoutNotFound
            }
            state.workouts[index].date = date
            state.workouts[index].note = try Self.validatedNote(note)
        }
    }

    public func deleteWorkout(id: UUID) throws {
        try mutate { state in
            guard state.workouts.contains(where: { $0.id == id }) else {
                throw WorkoutStoreError.workoutNotFound
            }
            state.workouts.removeAll { $0.id == id }
        }
    }

    public func workout(id: UUID) -> WorkoutSession? {
        workouts.first { $0.id == id }
    }

    public func makeWorkoutDraft(
        copying workoutID: UUID,
        date: Date = Date(),
        noteOverride: String? = nil
    ) throws -> WorkoutDraft {
        guard let source = workout(id: workoutID) else {
            throw WorkoutStoreError.workoutNotFound
        }
        return WorkoutDraft(
            date: date,
            note: noteOverride ?? source.note,
            exercises: source.exercises.map { block in
                WorkoutExerciseDraft(
                    exerciseID: block.exerciseID,
                    sets: block.sets.map { WorkoutSetDraft(weight: $0.weight, reps: $0.reps) }
                )
            }
        )
    }

    @discardableResult
    public func copyWorkout(
        id workoutID: UUID,
        to date: Date,
        noteOverride: String? = nil
    ) throws -> WorkoutSession {
        let draft = try makeWorkoutDraft(
            copying: workoutID,
            date: date,
            noteOverride: noteOverride
        )
        return try createWorkout(date: draft.date, note: draft.note, exercises: draft.exercises)
    }

    @discardableResult
    public func repeatLatestWorkout(
        on date: Date = Date(),
        noteOverride: String? = nil
    ) throws -> WorkoutSession? {
        guard let latest = latestWorkoutTemplate else { return nil }
        return try copyWorkout(id: latest.id, to: date, noteOverride: noteOverride)
    }

    // MARK: Workout exercise and set CRUD

    @discardableResult
    public func addExercise(
        toWorkout workoutID: UUID,
        exerciseID: UUID,
        initialSet: WorkoutSetDraft
    ) throws -> WorkoutExercise {
        var created: WorkoutExercise?
        try mutate { state in
            guard state.exercises.contains(where: { $0.id == exerciseID }) else {
                throw WorkoutStoreError.exerciseNotFound
            }
            guard let workoutIndex = state.workouts.firstIndex(where: { $0.id == workoutID }) else {
                throw WorkoutStoreError.workoutNotFound
            }
            try Self.validate(weight: initialSet.weight, reps: initialSet.reps)
            let block = WorkoutExercise(
                exerciseID: exerciseID,
                sets: [WorkoutSet(weight: initialSet.weight, reps: initialSet.reps)]
            )
            state.workouts[workoutIndex].exercises.append(block)
            created = block
        }
        return created!
    }

    public func removeExercise(
        fromWorkout workoutID: UUID,
        workoutExerciseID: UUID
    ) throws {
        try mutate { state in
            guard let workoutIndex = state.workouts.firstIndex(where: { $0.id == workoutID }) else {
                throw WorkoutStoreError.workoutNotFound
            }
            guard state.workouts[workoutIndex].exercises.contains(where: { $0.id == workoutExerciseID }) else {
                throw WorkoutStoreError.workoutExerciseNotFound
            }
            state.workouts[workoutIndex].exercises.removeAll { $0.id == workoutExerciseID }
            if state.workouts[workoutIndex].exercises.isEmpty {
                state.workouts.remove(at: workoutIndex)
            }
        }
    }

    @discardableResult
    public func addSet(
        workoutID: UUID,
        workoutExerciseID: UUID,
        weight: Double,
        reps: Int
    ) throws -> WorkoutSet {
        var created: WorkoutSet?
        try mutate { state in
            try Self.validate(weight: weight, reps: reps)
            let location = try Self.blockLocation(
                workoutID: workoutID,
                workoutExerciseID: workoutExerciseID,
                in: state
            )
            let set = WorkoutSet(weight: weight, reps: reps)
            state.workouts[location.workout].exercises[location.block].sets.append(set)
            created = set
        }
        return created!
    }

    public func updateSet(
        workoutID: UUID,
        workoutExerciseID: UUID,
        setID: UUID,
        weight: Double,
        reps: Int
    ) throws {
        try mutate { state in
            try Self.validate(weight: weight, reps: reps)
            let location = try Self.blockLocation(
                workoutID: workoutID,
                workoutExerciseID: workoutExerciseID,
                in: state
            )
            guard let setIndex = state.workouts[location.workout]
                .exercises[location.block].sets.firstIndex(where: { $0.id == setID }) else {
                throw WorkoutStoreError.setNotFound
            }
            state.workouts[location.workout].exercises[location.block].sets[setIndex].weight = weight
            state.workouts[location.workout].exercises[location.block].sets[setIndex].reps = reps
        }
    }

    /// Mirrors Android cleanup: deleting the final set removes its exercise block;
    /// deleting the final block removes the workout session.
    public func deleteSet(
        workoutID: UUID,
        workoutExerciseID: UUID,
        setID: UUID
    ) throws {
        try mutate { state in
            let location = try Self.blockLocation(
                workoutID: workoutID,
                workoutExerciseID: workoutExerciseID,
                in: state
            )
            guard state.workouts[location.workout].exercises[location.block]
                .sets.contains(where: { $0.id == setID }) else {
                throw WorkoutStoreError.setNotFound
            }
            state.workouts[location.workout].exercises[location.block]
                .sets.removeAll { $0.id == setID }

            if state.workouts[location.workout].exercises[location.block].sets.isEmpty {
                state.workouts[location.workout].exercises.remove(at: location.block)
            }
            if state.workouts[location.workout].exercises.isEmpty {
                state.workouts.remove(at: location.workout)
            }
        }
    }

    // MARK: Muscle mappings

    public func saveExerciseMuscleMapping(
        exerciseName: String,
        muscleIDs: [String]
    ) throws {
        let cleaned = try Self.validatedExerciseName(exerciseName)
        let key = MuscleMappingEngine.normalizeExerciseName(cleaned)
        let validMuscles = Set(MuscleMappingEngine.muscleDefinitions.map(\.id))
        let ids = muscleIDs
            .map(\.gymTrimmed)
            .filter { !$0.isEmpty && validMuscles.contains($0) }
            .reduce(into: [String]()) { result, id in
                if !result.contains(id) { result.append(id) }
            }

        try mutate { state in
            state.muscleMappings.removeAll { $0.exerciseNameKey == key }
            state.muscleMappings.append(contentsOf: ids.map {
                ExerciseMuscleMapping(
                    exerciseNameKey: key,
                    exerciseName: cleaned,
                    muscleID: $0,
                    weight: 1,
                    updatedAt: Date()
                )
            })
        }
    }

    /// Explicitly fills only exercises that do not already have a manual mapping.
    @discardableResult
    public func seedDefaultMuscleMappings() throws -> Int {
        var inserted = 0
        try mutate { state in
            var existingKeys = Set(state.muscleMappings.map(\.exerciseNameKey))
            for exercise in state.exercises {
                let key = MuscleMappingEngine.normalizeExerciseName(exercise.name)
                guard !existingKeys.contains(key) else { continue }
                let contributions = MuscleMappingEngine.defaultContributions(for: exercise.name)
                let mappings = contributions.map {
                    ExerciseMuscleMapping(
                        exerciseNameKey: key,
                        exerciseName: exercise.name,
                        muscleID: $0.muscleID,
                        weight: $0.weight,
                        updatedAt: Date()
                    )
                }
                state.muscleMappings.append(contentsOf: mappings)
                inserted += mappings.count
                existingKeys.insert(key)
            }
        }
        return inserted
    }

    // MARK: History, stats and records

    public func allExerciseHistory() -> [ExerciseHistoryEntry] {
        historyEntries(exerciseID: nil, from: nil, through: nil)
    }

    public func exerciseHistory(
        exerciseID: UUID,
        from startDate: Date? = nil,
        through endDate: Date? = nil
    ) -> [ExerciseHistoryEntry] {
        historyEntries(exerciseID: exerciseID, from: startDate, through: endDate)
    }

    public func lastWeight(exerciseID: UUID, before date: Date? = nil) -> Double? {
        workouts
            .filter { date == nil || $0.date < date! }
            .sorted { $0.date > $1.date }
            .lazy
            .flatMap { workout in
                workout.exercises
                    .filter { $0.exerciseID == exerciseID }
                    .flatMap { $0.sets.reversed() }
            }
            .first?
            .weight
    }

    public func maxWeight(exerciseID: UUID, excludingWorkout workoutID: UUID? = nil) -> Double? {
        workouts
            .filter { workoutID == nil || $0.id != workoutID }
            .flatMap(\.exercises)
            .filter { $0.exerciseID == exerciseID }
            .flatMap(\.sets)
            .map(\.weight)
            .max()
    }

    public func progressStats(exerciseID: UUID) -> ExerciseProgressStats {
        let history = exerciseHistory(exerciseID: exerciseID)
        return ExerciseProgressStats(
            exerciseID: exerciseID,
            sessionCount: Set(history.map(\.workoutID)).count,
            setCount: history.count,
            totalVolume: history.reduce(0) { $0 + $1.volume },
            maxWeight: history.map(\.weight).max() ?? 0,
            bestEstimatedOneRepMax: history.map(\.estimatedOneRepMax).max() ?? 0,
            latestWeight: lastWeight(exerciseID: exerciseID)
        )
    }

    public func personalRecords(exerciseID: UUID) -> [PersonalRecord] {
        let history = exerciseHistory(exerciseID: exerciseID)
        guard !history.isEmpty else { return [] }

        var records: [PersonalRecord] = []
        if let maxWeightEntry = history.max(by: {
            $0.weight == $1.weight ? $0.sessionDate > $1.sessionDate : $0.weight < $1.weight
        }) {
            records.append(
                PersonalRecord(
                    exerciseID: exerciseID,
                    kind: .maxWeight,
                    value: maxWeightEntry.weight,
                    achievedAt: maxWeightEntry.sessionDate,
                    workoutID: maxWeightEntry.workoutID,
                    setID: maxWeightEntry.setID
                )
            )
        }
        if let estimatedMaxEntry = history.max(by: {
            $0.estimatedOneRepMax == $1.estimatedOneRepMax
                ? $0.sessionDate > $1.sessionDate
                : $0.estimatedOneRepMax < $1.estimatedOneRepMax
        }) {
            records.append(
                PersonalRecord(
                    exerciseID: exerciseID,
                    kind: .estimatedOneRepMax,
                    value: estimatedMaxEntry.estimatedOneRepMax,
                    achievedAt: estimatedMaxEntry.sessionDate,
                    workoutID: estimatedMaxEntry.workoutID,
                    setID: estimatedMaxEntry.setID
                )
            )
        }

        let grouped = Dictionary(grouping: history, by: \.workoutID)
        if let bestSession = grouped.values.max(by: {
            $0.reduce(0) { $0 + $1.volume } < $1.reduce(0) { $0 + $1.volume }
        }), let first = bestSession.first {
            records.append(
                PersonalRecord(
                    exerciseID: exerciseID,
                    kind: .sessionVolume,
                    value: bestSession.reduce(0) { $0 + $1.volume },
                    achievedAt: first.sessionDate,
                    workoutID: first.workoutID
                )
            )
        }
        return records
    }

    public func dashboardStats(
        from startDate: Date? = nil,
        through endDate: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DashboardStats {
        let selected = workoutSummaries.filter { summary in
            (startDate == nil || summary.date >= startDate!) &&
                (endDate == nil || summary.date <= endDate!)
        }
        let totalVolume = selected.reduce(0) { $0 + $1.totalVolume }
        let totalSets = selected.reduce(0) { $0 + $1.setCount }
        return DashboardStats(
            workoutCount: selected.count,
            totalVolume: totalVolume,
            averageIntensity: totalSets == 0 ? 0 : totalVolume / Double(totalSets),
            streakDays: Self.currentStreakDays(
                sessions: workoutSummaries,
                now: now,
                calendar: calendar
            ),
            weeklyStreakWeeks: Self.weeklyStreakWeeks(
                sessions: workoutSummaries,
                now: now,
                calendar: calendar
            )
        )
    }

    /// Canonical cross-platform profile scoring.
    public func syncProfileStats() -> SyncProfileStats {
        let summaries = workoutSummaries
        let xp = summaries.reduce(0) { $0 + GamificationEngine.xpForSession($1) }
        let level = GamificationEngine.level(for: xp)
        return SyncProfileStats(xp: xp, level: level, workouts: summaries.count)
    }

    public func gamificationSnapshot(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> GamificationSnapshot {
        GamificationEngine.buildSnapshot(
            sessions: workoutSummaries,
            now: now,
            calendar: calendar
        )
    }

    // MARK: Backup v2

    public func makeBackup(
        includeDiagnostics: Bool = false,
        owner: BackupOwner? = nil,
        exportedAt: Date = Date()
    ) throws -> GymBackup {
        let exportedAtMilliseconds = try Self.validatedTimestamp(
            exportedAt,
            field: "export timestamp"
        )
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let backupExercises = exercises
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { BackupExercise(name: $0.name, catalogKey: $0.catalogKey) }
        let backupSessions = try workouts
            .filter { $0.setCount > 0 }
            .sorted { $0.date < $1.date }
            .map { workout in
                BackupSession(
                    date: try Self.validatedTimestamp(workout.date, field: "session timestamp"),
                    note: workout.note,
                    exercises: workout.exercises.compactMap { block in
                        guard let exercise = exerciseByID[block.exerciseID], !block.sets.isEmpty else {
                            return nil
                        }
                        return BackupWorkoutExercise(
                            name: exercise.name,
                            catalogKey: exercise.catalogKey,
                            sets: block.sets.map { BackupSet(weight: $0.weight, reps: $0.reps) }
                        )
                    }
                )
            }

        return GymBackup(
            exportedAt: exportedAtMilliseconds,
            diagnostics: includeDiagnostics,
            owner: owner ?? BackupOwner(accountID: accountStorageKey),
            exercises: backupExercises,
            sessions: backupSessions,
            summary: BackupSummary(
                exerciseCount: backupExercises.count,
                sessionCount: backupSessions.count,
                setCount: workouts.reduce(0) { $0 + $1.setCount },
                totalVolume: workouts.reduce(0) { $0 + $1.totalVolume }
            )
        )
    }

    public func exportBackupData(
        includeDiagnostics: Bool = false,
        owner: BackupOwner? = nil,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        if prettyPrinted { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        do {
            return try encoder.encode(
                try makeBackup(includeDiagnostics: includeDiagnostics, owner: owner)
            )
        } catch let error as WorkoutStoreError {
            throw error
        } catch {
            throw WorkoutStoreError.persistenceFailure(error.localizedDescription)
        }
    }

    public func exportBackupJSON(
        includeDiagnostics: Bool = false,
        owner: BackupOwner? = nil,
        prettyPrinted: Bool = true
    ) throws -> String {
        let data = try exportBackupData(
            includeDiagnostics: includeDiagnostics,
            owner: owner,
            prettyPrinted: prettyPrinted
        )
        guard let json = String(data: data, encoding: .utf8) else {
            throw WorkoutStoreError.persistenceFailure("UTF-8 encoding failed.")
        }
        return json
    }

    /// Adapts authenticated legacy PWA cloud rows to the native backup reader without
    /// weakening owner checks. The caller must keep cloud writes paused when the result
    /// is not round-trip safe, because native export does not preserve PWA-only fields.
    static func prepareCloudBackup(
        _ data: Data,
        activeOwner: BackupOwner,
        limits: BackupImportLimits = .standard
    ) throws -> PreparedCloudBackup {
        guard activeOwner.remote,
              let expectedUserID = activeOwner.userID?.nilIfJSONNull,
              let expectedAccountID = activeOwner.accountID?.nilIfJSONNull else {
            throw WorkoutStoreError.backupOwnerMismatch
        }
        guard data.count <= limits.maximumFileBytes else {
            throw WorkoutStoreError.importLimitExceeded("file size")
        }
        try validateJSONEnvelope(data, limits: limits)

        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw WorkoutStoreError.malformedBackup(error.localizedDescription)
        }
        guard var root = parsed as? [String: Any] else {
            throw WorkoutStoreError.malformedBackup("The cloud state must be a JSON object.")
        }

        let canonicalOwner: [String: Any] = {
            var owner: [String: Any] = [
                "accountId": expectedAccountID,
                "userId": expectedUserID,
                "remote": true
            ]
            if let email = activeOwner.email?.nilIfJSONNull { owner["email"] = email }
            return owner
        }()

        if root["schemaVersion"] == nil {
            let requiredPWAKeys: Set<String> = [
                "language", "exercises", "sessions", "mappings", "profile"
            ]
            let allowedPWAKeys = requiredPWAKeys.union(["progressExerciseId"])
            guard requiredPWAKeys.isSubset(of: Set(root.keys)),
                  Set(root.keys).isSubset(of: allowedPWAKeys),
                  let language = root["language"] as? String,
                  language == "en" || language == "uk",
                  root["exercises"] is [Any],
                  root["sessions"] is [Any],
                  root["mappings"] is [String: Any],
                  root["profile"] is [String: Any] else {
                throw WorkoutStoreError.malformedBackup(
                    "The legacy PWA cloud state has an unsupported shape."
                )
            }
            root["schemaVersion"] = GymBackup.currentSchemaVersion
            root["exportedAt"] = Date().gymEpochMilliseconds
            root["app"] = "GymApp"
            root["diagnostics"] = false
            root["owner"] = canonicalOwner
            return PreparedCloudBackup(
                data: try encodedCloudBackup(root, limits: limits),
                roundTripSafe: false
            )
        }

        let nativeKeys: Set<String> = [
            "schemaVersion", "exportedAt", "app", "diagnostics", "owner",
            "exercises", "sessions", "summary"
        ]
        var roundTripSafe = Set(root.keys).isSubset(of: nativeKeys)
        var needsEncoding = false

        if root["owner"] == nil || root["owner"] is NSNull {
            // The authenticated user_states row supplies the missing legacy identity.
            root["owner"] = canonicalOwner
            needsEncoding = true
        } else if let owner = root["owner"] as? [String: Any] {
            guard let ownerUserID = owner["userId"] as? String,
                  ownerUserID == expectedUserID else {
                throw WorkoutStoreError.backupOwnerMismatch
            }
            if let remoteMarker = owner["remote"] as? String {
                guard remoteMarker == "supabase" else {
                    throw WorkoutStoreError.backupOwnerMismatch
                }
                // PWA uses `remote-<uuid>` while native clients use `cloud_<uuid>`.
                // Exact user identity is authoritative; rewrite only the representation.
                root["owner"] = canonicalOwner
                needsEncoding = true
                roundTripSafe = false
            } else {
                guard owner["remote"] as? Bool == true else {
                    throw WorkoutStoreError.backupOwnerMismatch
                }
            }
        } else {
            throw WorkoutStoreError.backupOwnerMismatch
        }

        return PreparedCloudBackup(
            data: needsEncoding ? try encodedCloudBackup(root, limits: limits) : data,
            roundTripSafe: roundTripSafe
        )
    }

    private static func encodedCloudBackup(
        _ object: [String: Any],
        limits: BackupImportLimits
    ) throws -> Data {
        let encoded: Data
        do {
            encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            throw WorkoutStoreError.malformedBackup(error.localizedDescription)
        }
        guard encoded.count <= limits.maximumFileBytes else {
            throw WorkoutStoreError.importLimitExceeded("file size")
        }
        return encoded
    }

    @discardableResult
    public func importBackup(
        json: String,
        activeOwner: BackupOwner? = nil,
        limits: BackupImportLimits = .standard
    ) throws -> BackupImportResult {
        guard Self.utf8Length(of: json, isAtMost: limits.maximumFileBytes) else {
            throw WorkoutStoreError.importLimitExceeded("file size")
        }
        guard let data = json.data(using: .utf8) else {
            throw WorkoutStoreError.malformedBackup("The document is not UTF-8 JSON.")
        }
        return try importBackup(data: data, activeOwner: activeOwner, limits: limits)
    }

    @discardableResult
    public func importBackup(
        data: Data,
        activeOwner: BackupOwner? = nil,
        limits: BackupImportLimits = .standard
    ) throws -> BackupImportResult {
        try applyBackup(
            data: data,
            activeOwner: activeOwner,
            limits: limits,
            replacingExisting: false
        )
    }

    /// Restores an authoritative snapshot, replacing all locally persisted workout data.
    /// Use this for a cloud snapshot after its account ownership has been validated.
    @discardableResult
    public func restoreBackup(
        data: Data,
        activeOwner: BackupOwner? = nil,
        limits: BackupImportLimits = .standard
    ) throws -> BackupImportResult {
        try applyBackup(
            data: data,
            activeOwner: activeOwner,
            limits: limits,
            replacingExisting: true
        )
    }

    /// String convenience for authoritative restores.
    @discardableResult
    public func restoreBackup(
        json: String,
        activeOwner: BackupOwner? = nil,
        limits: BackupImportLimits = .standard
    ) throws -> BackupImportResult {
        guard Self.utf8Length(of: json, isAtMost: limits.maximumFileBytes) else {
            throw WorkoutStoreError.importLimitExceeded("file size")
        }
        guard let data = json.data(using: .utf8) else {
            throw WorkoutStoreError.malformedBackup("The document is not UTF-8 JSON.")
        }
        return try restoreBackup(data: data, activeOwner: activeOwner, limits: limits)
    }

    private func applyBackup(
        data: Data,
        activeOwner: BackupOwner?,
        limits: BackupImportLimits,
        replacingExisting: Bool
    ) throws -> BackupImportResult {
        guard data.count <= limits.maximumFileBytes else {
            throw WorkoutStoreError.importLimitExceeded("file size")
        }
        try Self.validateJSONEnvelope(data, limits: limits)

        let backup: GymBackup
        do {
            backup = try JSONDecoder().decode(GymBackup.self, from: data)
        } catch {
            throw WorkoutStoreError.malformedBackup(error.localizedDescription)
        }
        guard backup.schemaVersion == GymBackup.currentSchemaVersion else {
            throw WorkoutStoreError.unsupportedBackupSchema(backup.schemaVersion)
        }
        guard backup.exercises.count <= limits.maximumExercises else {
            throw WorkoutStoreError.importLimitExceeded("exercise count")
        }
        guard backup.sessions.count <= limits.maximumSessions else {
            throw WorkoutStoreError.importLimitExceeded("session count")
        }
        try Self.validateBackupMetadata(backup, limits: limits)
        let resolvedOwner = activeOwner ?? BackupOwner(accountID: accountStorageKey)
        let destinationIsFresh = snapshot.exercises.isEmpty &&
            snapshot.workouts.isEmpty && snapshot.muscleMappings.isEmpty
        try Self.validateBackupOwner(
            backup.owner,
            activeOwner: resolvedOwner,
            allowDifferentLocalAccountID: !replacingExisting && destinationIsFresh
        )

        var next = replacingExisting ? WorkoutDataSnapshot() : snapshot
        var exerciseIDByKey = Dictionary(
            uniqueKeysWithValues: next.exercises.map { (Self.nameKey($0.name), $0.id) }
        )
        var exerciseIDByCatalogKey: [String: UUID] = [:]
        var exerciseIndexByID: [UUID: Int] = [:]
        for (index, exercise) in next.exercises.enumerated() {
            exerciseIndexByID[exercise.id] = index
            if let catalogKey = BuiltInExerciseCatalog.resolvedKey(
                catalogKey: exercise.catalogKey,
                name: exercise.name
            ) {
                exerciseIDByCatalogKey[catalogKey] = exerciseIDByCatalogKey[catalogKey] ?? exercise.id
            }
        }
        var addedExercises = 0
        var importedSessions = 0
        var skippedDuplicates = 0
        var ignoredInvalidSets = 0
        var encounteredSets = 0

        func resolveExercise(_ rawName: String, catalogKey: String? = nil) throws -> UUID? {
            guard Self.utf8Length(of: rawName, isAtMost: limits.maximumExerciseNameBytes) else {
                throw WorkoutStoreError.importLimitExceeded("exercise name length")
            }
            let name = rawName.gymTrimmed
            guard !name.isEmpty else { return nil }
            guard name.count <= limits.maximumExerciseNameLength else {
                throw WorkoutStoreError.importLimitExceeded("exercise name length")
            }
            if let catalogKey,
               catalogKey.utf8.count > Self.maximumCatalogKeyBytes {
                throw WorkoutStoreError.importLimitExceeded("catalog key length")
            }
            let key = Self.nameKey(name)
            let resolvedCatalogKey = BuiltInExerciseCatalog.resolvedKey(
                catalogKey: catalogKey,
                name: name
            )
            if let id = exerciseIDByKey[key] {
                if let index = exerciseIndexByID[id],
                   next.exercises[index].catalogKey == nil {
                    next.exercises[index].catalogKey = resolvedCatalogKey
                }
                return id
            }
            if let resolvedCatalogKey,
               let id = exerciseIDByCatalogKey[resolvedCatalogKey] {
                return id
            }
            guard next.exercises.count < limits.maximumExercises else {
                throw WorkoutStoreError.importLimitExceeded("exercise count")
            }
            let exercise = Exercise(name: name, catalogKey: resolvedCatalogKey)
            next.exercises.append(exercise)
            exerciseIndexByID[exercise.id] = next.exercises.count - 1
            exerciseIDByKey[key] = exercise.id
            if let resolvedCatalogKey {
                exerciseIDByCatalogKey[resolvedCatalogKey] = exercise.id
            }
            addedExercises += 1
            return exercise.id
        }

        for item in backup.exercises {
            _ = try resolveExercise(item.name, catalogKey: item.catalogKey)
        }

        var existingSignatures = Set(next.workouts.map(Self.importSignature))
        for session in backup.sessions {
            let rawNote = session.note?.gymTrimmed
            if let rawNote,
               (rawNote.utf8.count > limits.maximumNoteBytes ||
                rawNote.count > limits.maximumNoteLength) {
                throw WorkoutStoreError.importLimitExceeded("note length")
            }
            let note = rawNote?.isEmpty == false ? rawNote : nil
            var orderedExerciseIDs: [UUID] = []
            var setsByExerciseID: [UUID: [WorkoutSetDraft]] = [:]

            func appendSets(_ sets: [WorkoutSetDraft], exerciseID: UUID) throws {
                guard !sets.isEmpty else { return }
                if setsByExerciseID[exerciseID] == nil {
                    orderedExerciseIDs.append(exerciseID)
                }
                setsByExerciseID[exerciseID, default: []].append(contentsOf: sets)
                guard setsByExerciseID[exerciseID, default: []].count <= limits.maximumSetsPerExercise else {
                    throw WorkoutStoreError.importLimitExceeded("sets per exercise")
                }
            }

            if let blocks = session.exercises {
                guard blocks.count <= limits.maximumExercisesPerSession else {
                    throw WorkoutStoreError.importLimitExceeded("exercises per session")
                }
                for block in blocks {
                    guard block.sets.count <= limits.maximumSetsPerExercise else {
                        throw WorkoutStoreError.importLimitExceeded("sets per exercise")
                    }
                    guard let exerciseID = try resolveExercise(
                        block.name,
                        catalogKey: block.catalogKey
                    ) else { continue }
                    var sets: [WorkoutSetDraft] = []
                    for set in block.sets {
                        encounteredSets += 1
                        guard encounteredSets <= limits.maximumTotalSets else {
                            throw WorkoutStoreError.importLimitExceeded("total set count")
                        }
                        guard set.weight.isFinite, set.reps > 0,
                              set.reps <= Self.maximumReps else {
                            ignoredInvalidSets += 1
                            continue
                        }
                        let weight = max(0, set.weight)
                        guard weight <= Self.maximumWeight else {
                            ignoredInvalidSets += 1
                            continue
                        }
                        sets.append(WorkoutSetDraft(weight: weight, reps: set.reps))
                    }
                    if !sets.isEmpty {
                        try appendSets(sets, exerciseID: exerciseID)
                    }
                }
            } else if let flatSets = session.sets {
                guard flatSets.count <= limits.maximumTotalSets else {
                    throw WorkoutStoreError.importLimitExceeded("total set count")
                }
                for set in flatSets {
                    encounteredSets += 1
                    guard encounteredSets <= limits.maximumTotalSets else {
                        throw WorkoutStoreError.importLimitExceeded("total set count")
                    }
                    let name = (set.exerciseName?.gymTrimmed.isEmpty == false
                        ? set.exerciseName!
                        : set.name ?? "").gymTrimmed
                    guard !name.isEmpty, set.weight.isFinite, set.reps > 0,
                          set.reps <= Self.maximumReps else {
                        ignoredInvalidSets += 1
                        continue
                    }
                    let weight = max(0, set.weight)
                    guard weight <= Self.maximumWeight else {
                        ignoredInvalidSets += 1
                        continue
                    }
                    guard let exerciseID = try resolveExercise(name) else { continue }
                    try appendSets(
                        [WorkoutSetDraft(weight: weight, reps: set.reps)],
                        exerciseID: exerciseID
                    )
                }
            }

            guard orderedExerciseIDs.count <= limits.maximumExercisesPerSession else {
                throw WorkoutStoreError.importLimitExceeded("exercises per session")
            }
            let drafts = orderedExerciseIDs.compactMap { exerciseID -> WorkoutExerciseDraft? in
                guard let sets = setsByExerciseID[exerciseID], !sets.isEmpty else { return nil }
                return WorkoutExerciseDraft(exerciseID: exerciseID, sets: sets)
            }
            guard !drafts.isEmpty else { continue }
            let timestamp = try Self.validatedTimestamp(
                session.date ?? session.startedAt ?? Date().gymEpochMilliseconds,
                field: "session timestamp"
            )
            let signature = Self.importSignature(
                dateMilliseconds: timestamp,
                note: note,
                drafts: drafts
            )
            if existingSignatures.insert(signature).inserted {
                guard next.workouts.count < limits.maximumSessions else {
                    throw WorkoutStoreError.importLimitExceeded("session count")
                }
                let workout = try Self.makeWorkout(
                    date: Date(gymEpochMilliseconds: timestamp),
                    note: note,
                    drafts: drafts,
                    knownExerciseIDs: Set(next.exercises.map(\.id))
                )
                next.workouts.append(workout)
                importedSessions += 1
            } else {
                skippedDuplicates += 1
            }
        }

        try commit(next)
        return BackupImportResult(
            importedSessions: importedSessions,
            skippedDuplicateSessions: skippedDuplicates,
            addedExercises: addedExercises,
            ignoredInvalidSets: ignoredInvalidSets
        )
    }

    // MARK: Explicit demo data

    /// Adds deterministic sample data only when explicitly called and only to an
    /// empty account store. Normal initialization always stays empty.
    @discardableResult
    public func seedDemoData(referenceDate: Date = Date(), calendar: Calendar = .current) throws -> Bool {
        guard exercises.isEmpty, workouts.isEmpty else { return false }
        var next = WorkoutDataSnapshot()
        let bench = Exercise(name: "Bench Press")
        let row = Exercise(name: "Barbell Row")
        let squat = Exercise(name: "Barbell Squat")
        next.exercises = [bench, row, squat]

        let previousDate = calendar.date(byAdding: .day, value: -3, to: referenceDate) ?? referenceDate
        next.workouts = [
            WorkoutSession(
                date: previousDate,
                note: "Demo workout",
                exercises: [
                    WorkoutExercise(
                        exerciseID: bench.id,
                        sets: [
                            WorkoutSet(weight: 50, reps: 10),
                            WorkoutSet(weight: 52.5, reps: 8),
                            WorkoutSet(weight: 52.5, reps: 8)
                        ]
                    ),
                    WorkoutExercise(
                        exerciseID: row.id,
                        sets: [
                            WorkoutSet(weight: 45, reps: 10),
                            WorkoutSet(weight: 45, reps: 10),
                            WorkoutSet(weight: 45, reps: 9)
                        ]
                    )
                ]
            ),
            WorkoutSession(
                date: referenceDate,
                note: nil,
                exercises: [
                    WorkoutExercise(
                        exerciseID: squat.id,
                        sets: [
                            WorkoutSet(weight: 70, reps: 8),
                            WorkoutSet(weight: 70, reps: 8),
                            WorkoutSet(weight: 72.5, reps: 6)
                        ]
                    )
                ]
            )
        ]
        try commit(next)
        return true
    }

    // MARK: Persistence and validation

    private func mutate(_ mutation: (inout WorkoutDataSnapshot) throws -> Void) throws {
        var next = snapshot
        try mutation(&next)
        try commit(next)
    }

    private func commit(_ state: WorkoutDataSnapshot) throws {
        try Self.validate(state)
        let normalized = Self.normalized(state)
        try persist(normalized)
        publish(normalized)
    }

    private func publish(_ state: WorkoutDataSnapshot) {
        exercises = state.exercises
        workouts = state.workouts
        muscleMappings = state.muscleMappings
    }

    private func persist(_ state: WorkoutDataSnapshot) throws {
        let envelope = PersistedEnvelope(
            schemaVersion: Self.persistedSchemaVersion,
            accountStorageKey: accountStorageKey,
            savedAt: Date(),
            snapshot: state
        )
        do {
            let data = try Self.localEncoder().encode(envelope)
            try data.write(
                to: storageURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            try Self.excludePrivateItemFromBackup(storageURL)
        } catch let error as WorkoutStoreError {
            throw error
        } catch {
            throw WorkoutStoreError.persistenceFailure(error.localizedDescription)
        }
    }

    private static func load(
        accountStorageKey: String,
        from url: URL,
        fileManager: FileManager
    ) throws -> WorkoutDataSnapshot {
        guard fileManager.fileExists(atPath: url.path) else {
            return WorkoutDataSnapshot()
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let envelope = try localDecoder().decode(PersistedEnvelope.self, from: data)
            guard envelope.schemaVersion == persistedSchemaVersion else {
                throw WorkoutStoreError.corruptStore(
                    "Unsupported local schema \(envelope.schemaVersion)."
                )
            }
            guard envelope.accountStorageKey == accountStorageKey else {
                throw WorkoutStoreError.storageAccountMismatch
            }
            try validate(envelope.snapshot)
            return normalized(envelope.snapshot)
        } catch let error as WorkoutStoreError {
            throw error
        } catch {
            throw WorkoutStoreError.corruptStore(error.localizedDescription)
        }
    }

    private static func localEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func localDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func defaultDirectory(fileManager: FileManager) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw WorkoutStoreError.persistenceFailure("Application Support is unavailable.")
        }
        return applicationSupport
            .appendingPathComponent("GymApp", isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
    }

    private static func excludePrivateItemFromBackup(_ url: URL) throws {
        do {
            try (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        } catch {
            throw WorkoutStoreError.persistenceFailure(
                "Private workout storage could not be excluded from backup: \(error.localizedDescription)"
            )
        }
    }

    private static func validatedStorageKey(_ key: String) throws -> String {
        let cleaned = key.gymTrimmed
        guard !cleaned.isEmpty, cleaned.count <= maximumAccountStorageKeyLength else {
            throw WorkoutStoreError.invalidAccountStorageKey
        }
        return cleaned
    }

    private static func fileURL(for key: String, in directory: URL) -> URL {
        directory.appendingPathComponent("account-\(stableHash(key)).json", isDirectory: false)
    }

    /// Stable non-cryptographic filename hash. The original account identifier is
    /// retained inside the envelope and checked on load, so a collision cannot mix data.
    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func normalized(_ state: WorkoutDataSnapshot) -> WorkoutDataSnapshot {
        WorkoutDataSnapshot(
            exercises: state.exercises.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            },
            workouts: state.workouts.sorted { $0.date > $1.date },
            muscleMappings: state.muscleMappings.sorted {
                if $0.exerciseNameKey == $1.exerciseNameKey {
                    return $0.muscleID < $1.muscleID
                }
                return $0.exerciseNameKey < $1.exerciseNameKey
            }
        )
    }

    private static func validate(_ state: WorkoutDataSnapshot) throws {
        guard Set(state.exercises.map(\.id)).count == state.exercises.count else {
            throw WorkoutStoreError.corruptStore("Duplicate exercise identifier.")
        }
        for exercise in state.exercises {
            _ = try validatedExerciseName(exercise.name)
            if let catalogKey = exercise.catalogKey,
               !utf8Length(of: catalogKey, isAtMost: maximumCatalogKeyBytes) {
                throw WorkoutStoreError.corruptStore("An exercise catalog key is too long.")
            }
        }
        guard Set(state.exercises.map { nameKey($0.name) }).count == state.exercises.count else {
            throw WorkoutStoreError.corruptStore("Duplicate exercise name.")
        }
        guard Set(state.workouts.map(\.id)).count == state.workouts.count else {
            throw WorkoutStoreError.corruptStore("Duplicate workout identifier.")
        }
        let knownExerciseIDs = Set(state.exercises.map(\.id))
        var blockIDs = Set<UUID>()
        var setIDs = Set<UUID>()
        for workout in state.workouts {
            guard !workout.exercises.isEmpty else {
                throw WorkoutStoreError.corruptStore("A workout has no exercises.")
            }
            guard isSupportedTimestamp(workout.date) else {
                throw WorkoutStoreError.corruptStore("A workout timestamp is outside the supported range.")
            }
            _ = try validatedNote(workout.note)
            for block in workout.exercises {
                guard blockIDs.insert(block.id).inserted else {
                    throw WorkoutStoreError.corruptStore("Duplicate workout exercise identifier.")
                }
                guard knownExerciseIDs.contains(block.exerciseID) else {
                    throw WorkoutStoreError.corruptStore("A workout references a missing exercise.")
                }
                guard !block.sets.isEmpty else {
                    throw WorkoutStoreError.corruptStore("A workout exercise has no sets.")
                }
                for set in block.sets {
                    guard setIDs.insert(set.id).inserted else {
                        throw WorkoutStoreError.corruptStore("Duplicate set identifier.")
                    }
                    try validate(weight: set.weight, reps: set.reps)
                }
            }
        }
        guard Set(state.muscleMappings.map(\.id)).count == state.muscleMappings.count else {
            throw WorkoutStoreError.corruptStore("Duplicate muscle mapping.")
        }
        let validMuscles = Set(MuscleMappingEngine.muscleDefinitions.map(\.id))
        for mapping in state.muscleMappings {
            guard utf8Length(
                    of: mapping.exerciseNameKey,
                    isAtMost: BackupImportLimits.standard.maximumExerciseNameBytes
                  ),
                  utf8Length(
                    of: mapping.exerciseName,
                    isAtMost: BackupImportLimits.standard.maximumExerciseNameBytes
                  ),
                  utf8Length(of: mapping.muscleID, isAtMost: maximumCatalogKeyBytes),
                  !mapping.exerciseNameKey.isEmpty,
                  validMuscles.contains(mapping.muscleID),
                  mapping.weight.isFinite,
                  (0 ... 1).contains(mapping.weight) else {
                throw WorkoutStoreError.corruptStore("Invalid muscle mapping.")
            }
        }
    }

    /// Rejects pathological JSON before Foundation materializes nested containers or
    /// attacker-controlled multi-megabyte strings.
    private static func validateJSONEnvelope(
        _ data: Data,
        limits: BackupImportLimits
    ) throws {
        guard limits.maximumJSONNestingDepth > 0,
              limits.maximumJSONStringBytes > 0 else {
            throw WorkoutStoreError.importLimitExceeded("JSON parser configuration")
        }

        var depth = 0
        var inString = false
        var escaped = false
        var currentStringBytes = 0
        for byte in data {
            if inString {
                if escaped {
                    escaped = false
                    currentStringBytes += 1
                } else if byte == 0x5C { // backslash
                    escaped = true
                    currentStringBytes += 1
                } else if byte == 0x22 { // quote
                    inString = false
                } else {
                    currentStringBytes += 1
                }
                guard currentStringBytes <= limits.maximumJSONStringBytes else {
                    throw WorkoutStoreError.importLimitExceeded("JSON string size")
                }
                continue
            }

            switch byte {
            case 0x22: // quote
                inString = true
                escaped = false
                currentStringBytes = 0
            case 0x7B, 0x5B: // { [
                depth += 1
                guard depth <= limits.maximumJSONNestingDepth else {
                    throw WorkoutStoreError.importLimitExceeded("JSON nesting depth")
                }
            case 0x7D, 0x5D: // } ]
                depth -= 1
                guard depth >= 0 else {
                    throw WorkoutStoreError.malformedBackup("Unbalanced JSON container.")
                }
            default:
                break
            }
        }
        guard !inString, depth == 0 else {
            throw WorkoutStoreError.malformedBackup("Incomplete JSON document.")
        }
    }

    private static func validateBackupMetadata(
        _ backup: GymBackup,
        limits: BackupImportLimits
    ) throws {
        _ = try validatedTimestamp(backup.exportedAt, field: "export timestamp")
        guard backup.app.utf8.count <= maximumAppNameBytes else {
            throw WorkoutStoreError.importLimitExceeded("app name length")
        }
        if let owner = backup.owner {
            for value in [owner.accountID, owner.userID, owner.email].compactMap({ $0 }) {
                guard value.utf8.count <= maximumOwnerFieldBytes else {
                    throw WorkoutStoreError.importLimitExceeded("owner field length")
                }
            }
        }
        if let summary = backup.summary {
            guard summary.exerciseCount >= 0,
                  summary.sessionCount >= 0,
                  summary.setCount >= 0,
                  summary.exerciseCount <= limits.maximumExercises,
                  summary.sessionCount <= limits.maximumSessions,
                  summary.setCount <= limits.maximumTotalSets,
                  summary.totalVolume.isFinite,
                  summary.totalVolume >= 0 else {
                throw WorkoutStoreError.malformedBackup("The backup summary is invalid.")
            }
        }

        for exercise in backup.exercises {
            try validateImportedExerciseText(
                name: exercise.name,
                catalogKey: exercise.catalogKey,
                limits: limits
            )
        }
        for session in backup.sessions {
            if let timestamp = session.date ?? session.startedAt {
                _ = try validatedTimestamp(timestamp, field: "session timestamp")
            }
            if let note = session.note {
                guard note.utf8.count <= limits.maximumNoteBytes,
                      note.count <= limits.maximumNoteLength else {
                    throw WorkoutStoreError.importLimitExceeded("note length")
                }
            }
            if let blocks = session.exercises {
                guard blocks.count <= limits.maximumExercisesPerSession else {
                    throw WorkoutStoreError.importLimitExceeded("exercises per session")
                }
                for block in blocks {
                    try validateImportedExerciseText(
                        name: block.name,
                        catalogKey: block.catalogKey,
                        limits: limits
                    )
                    guard block.sets.count <= limits.maximumSetsPerExercise else {
                        throw WorkoutStoreError.importLimitExceeded("sets per exercise")
                    }
                }
            }
            if let flatSets = session.sets {
                guard flatSets.count <= limits.maximumTotalSets else {
                    throw WorkoutStoreError.importLimitExceeded("total set count")
                }
                for set in flatSets {
                    if let name = set.exerciseName ?? set.name {
                        try validateImportedExerciseText(
                            name: name,
                            catalogKey: nil,
                            limits: limits
                        )
                    }
                }
            }
        }
    }

    private static func validateImportedExerciseText(
        name: String,
        catalogKey: String?,
        limits: BackupImportLimits
    ) throws {
        guard utf8Length(of: name, isAtMost: limits.maximumExerciseNameBytes),
              name.count <= limits.maximumExerciseNameLength else {
            throw WorkoutStoreError.importLimitExceeded("exercise name length")
        }
        if let catalogKey,
           catalogKey.utf8.count > maximumCatalogKeyBytes {
            throw WorkoutStoreError.importLimitExceeded("catalog key length")
        }
    }

    private static func validatedTimestamp(_ value: Int64, field: String) throws -> Int64 {
        guard (minimumSupportedTimestampMilliseconds ... maximumSupportedTimestampMilliseconds)
            .contains(value) else {
            throw WorkoutStoreError.malformedBackup("The \(field) is outside the supported range.")
        }
        return value
    }

    private static func validatedTimestamp(_ value: Date, field: String) throws -> Int64 {
        let milliseconds = (value.timeIntervalSince1970 * 1_000).rounded()
        guard milliseconds.isFinite,
              milliseconds >= Double(minimumSupportedTimestampMilliseconds),
              milliseconds <= Double(maximumSupportedTimestampMilliseconds) else {
            throw WorkoutStoreError.invalidWorkout("The \(field) is outside the supported range.")
        }
        return Int64(milliseconds)
    }

    private static func isSupportedTimestamp(_ value: Date) -> Bool {
        (try? validatedTimestamp(value, field: "session timestamp")) != nil
    }

    private static func validatedExerciseName(_ name: String) throws -> String {
        guard utf8Length(
            of: name,
            isAtMost: BackupImportLimits.standard.maximumExerciseNameBytes
        ) else {
            throw WorkoutStoreError.invalidExerciseName
        }
        let cleaned = name.gymTrimmed
        guard !cleaned.isEmpty,
              cleaned.count <= maximumExerciseNameLength,
              !cleaned.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw WorkoutStoreError.invalidExerciseName
        }
        return cleaned
    }

    private static func validatedNote(_ note: String?) throws -> String? {
        guard let note else { return nil }
        guard utf8Length(
            of: note,
            isAtMost: BackupImportLimits.standard.maximumNoteBytes
        ) else {
            throw WorkoutStoreError.invalidWorkout("The note is too long.")
        }
        let cleaned = note.gymTrimmed
        guard cleaned.count <= maximumNoteLength else {
            throw WorkoutStoreError.invalidWorkout("The note is too long.")
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func validate(weight: Double, reps: Int) throws {
        guard weight.isFinite, weight >= 0, weight <= maximumWeight else {
            throw WorkoutStoreError.invalidWeight
        }
        guard (1 ... maximumReps).contains(reps) else {
            throw WorkoutStoreError.invalidReps
        }
    }

    private static func makeWorkout(
        date: Date,
        note: String?,
        drafts: [WorkoutExerciseDraft],
        knownExerciseIDs: Set<UUID>
    ) throws -> WorkoutSession {
        _ = try validatedTimestamp(date, field: "session timestamp")
        guard !drafts.isEmpty else {
            throw WorkoutStoreError.invalidWorkout("At least one exercise is required.")
        }
        let blocks = try drafts.map { draft -> WorkoutExercise in
            guard knownExerciseIDs.contains(draft.exerciseID) else {
                throw WorkoutStoreError.exerciseNotFound
            }
            guard !draft.sets.isEmpty else {
                throw WorkoutStoreError.invalidWorkout("Each exercise needs at least one set.")
            }
            let sets = try draft.sets.map { item -> WorkoutSet in
                try validate(weight: item.weight, reps: item.reps)
                return WorkoutSet(weight: item.weight, reps: item.reps)
            }
            return WorkoutExercise(exerciseID: draft.exerciseID, sets: sets)
        }
        return WorkoutSession(
            date: date,
            note: try validatedNote(note),
            exercises: blocks
        )
    }

    private static func blockLocation(
        workoutID: UUID,
        workoutExerciseID: UUID,
        in state: WorkoutDataSnapshot
    ) throws -> (workout: Int, block: Int) {
        guard let workoutIndex = state.workouts.firstIndex(where: { $0.id == workoutID }) else {
            throw WorkoutStoreError.workoutNotFound
        }
        guard let blockIndex = state.workouts[workoutIndex]
            .exercises.firstIndex(where: { $0.id == workoutExerciseID }) else {
            throw WorkoutStoreError.workoutExerciseNotFound
        }
        return (workoutIndex, blockIndex)
    }

    private static func namesEqual(_ lhs: String, _ rhs: String) -> Bool {
        nameKey(lhs) == nameKey(rhs)
    }

    private static func exerciseIdentityConflicts(
        _ existing: Exercise,
        candidateName: String
    ) -> Bool {
        if namesEqual(existing.name, candidateName) { return true }
        guard let candidateKey = BuiltInExerciseCatalog.canonicalKey(forName: candidateName) else {
            return false
        }
        return BuiltInExerciseCatalog.resolvedKey(
            catalogKey: existing.catalogKey,
            name: existing.name
        ) == candidateKey
    }

    private static func nameKey(_ value: String) -> String {
        value.gymTrimmed.lowercased()
    }

    private static func summary(_ workout: WorkoutSession) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            workoutID: workout.id,
            date: workout.date,
            note: workout.note,
            exerciseCount: workout.exercises.filter { !$0.sets.isEmpty }.count,
            setCount: workout.setCount,
            totalVolume: workout.totalVolume
        )
    }

    private func historyEntries(
        exerciseID: UUID?,
        from startDate: Date?,
        through endDate: Date?
    ) -> [ExerciseHistoryEntry] {
        let exercisesByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        var result: [ExerciseHistoryEntry] = []
        for workout in workouts {
            guard (startDate == nil || workout.date >= startDate!),
                  (endDate == nil || workout.date <= endDate!) else { continue }
            for block in workout.exercises {
                guard exerciseID == nil || block.exerciseID == exerciseID,
                      let exercise = exercisesByID[block.exerciseID] else { continue }
                for (index, set) in block.sets.enumerated() {
                    result.append(
                        ExerciseHistoryEntry(
                            setID: set.id,
                            workoutID: workout.id,
                            sessionDate: workout.date,
                            exerciseID: block.exerciseID,
                            exerciseName: exercise.name,
                            exerciseCatalogKey: exercise.catalogKey,
                            weight: set.weight,
                            reps: set.reps,
                            setOrderIndex: index
                        )
                    )
                }
            }
        }
        return result.sorted {
            if $0.sessionDate != $1.sessionDate { return $0.sessionDate > $1.sessionDate }
            if exerciseID == nil,
               $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) != .orderedSame {
                return $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending
            }
            return $0.setOrderIndex < $1.setOrderIndex
        }
    }

    private static func currentStreakDays(
        sessions: [WorkoutSessionSummary],
        now: Date,
        calendar: Calendar
    ) -> Int {
        guard !sessions.isEmpty else { return 0 }
        let workoutDays = Set(sessions.map { calendar.gymEpochDay(for: $0.date) })
        var cursor = calendar.gymEpochDay(for: now)
        if !workoutDays.contains(cursor) { cursor -= 1 }
        var streak = 0
        while workoutDays.contains(cursor) {
            streak += 1
            cursor -= 1
        }
        return streak
    }

    private static func weeklyStreakWeeks(
        sessions: [WorkoutSessionSummary],
        now: Date,
        calendar: Calendar
    ) -> Int {
        guard !sessions.isEmpty else { return 0 }
        let counts = Dictionary(grouping: sessions) {
            calendar.gymEpochDay(for: calendar.gymMondayStart(of: $0.date))
        }.mapValues(\.count)
        var cursor = calendar.gymEpochDay(for: calendar.gymMondayStart(of: now))
        if counts[cursor, default: 0] < 3 { cursor -= 7 }
        var streak = 0
        while counts[cursor, default: 0] >= 3 {
            streak += 1
            cursor -= 7
        }
        return streak
    }

    private static func validateBackupOwner(
        _ backupOwner: BackupOwner?,
        activeOwner: BackupOwner,
        allowDifferentLocalAccountID: Bool = false
    ) throws {
        if activeOwner.remote {
            guard let backupOwner,
                  backupOwner.remote,
                  let backupUserID = backupOwner.userID?.nilIfJSONNull,
                  let activeUserID = activeOwner.userID?.nilIfJSONNull,
                  backupUserID == activeUserID else {
                throw WorkoutStoreError.backupOwnerMismatch
            }
            return
        }

        guard let backupOwner else { return }
        let backupUserID = backupOwner.userID?.nilIfJSONNull
        let backupAccountID = backupOwner.accountID?.nilIfJSONNull
        let activeAccountID = activeOwner.accountID?.nilIfJSONNull

        guard !backupOwner.remote, backupUserID == nil else {
            throw WorkoutStoreError.backupOwnerMismatch
        }
        if !allowDifferentLocalAccountID {
            guard backupAccountID == nil || backupAccountID == activeAccountID else {
                throw WorkoutStoreError.backupOwnerMismatch
            }
        }
    }

    private static func importSignature(_ workout: WorkoutSession) -> String {
        importSignature(
            dateMilliseconds: workout.date.gymEpochMilliseconds,
            note: workout.note,
            drafts: workout.exercises.map { block in
                WorkoutExerciseDraft(
                    exerciseID: block.exerciseID,
                    sets: block.sets.map { WorkoutSetDraft(weight: $0.weight, reps: $0.reps) }
                )
            }
        )
    }

    private static func importSignature(
        dateMilliseconds: Int64,
        note: String?,
        drafts: [WorkoutExerciseDraft]
    ) -> String {
        var components = ["\(dateMilliseconds)|\(note?.gymTrimmed ?? "")"]
        components.reserveCapacity(1 + drafts.count + drafts.reduce(0) { $0 + $1.sets.count })
        for block in drafts {
            components.append("|\(block.exerciseID.uuidString)")
            for set in block.sets {
                components.append(":\(set.weight)x\(set.reps)")
            }
        }
        return components.joined()
    }

    private static func utf8Length(of value: String, isAtMost maximum: Int) -> Bool {
        guard maximum >= 0 else { return false }
        if maximum == Int.max { return true }
        return value.utf8.prefix(maximum + 1).count <= maximum
    }
}
