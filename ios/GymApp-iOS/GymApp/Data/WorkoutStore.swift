import Combine
import CoreFoundation
import Foundation

public enum WorkoutStoreError: Error, LocalizedError, Equatable, Sendable {
    case invalidAccountStorageKey
    case corruptStore(String)
    case storageAccountMismatch
    case invalidExerciseName
    case duplicateExerciseName
    case exerciseNotFound
    case exerciseInUse
    case builtInExerciseReadOnly
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
        case .builtInExerciseReadOnly:
            return "Built-in exercises cannot be renamed."
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
    /// True when every core field is represented by the typed workout model and every
    /// namespaced extension can be preserved verbatim on the next compare-and-swap write.
    let roundTripSafe: Bool
    /// Canonical JSON object containing optional client-specific state. iOS never interprets
    /// unknown namespaces, but carries them through account-scoped cloud writes unchanged.
    let extensionsData: Data?
    /// Legacy PWA/native rows are normalized in memory first. The caller should queue a CAS
    /// write so all clients subsequently observe the shared canonical envelope.
    let requiresCanonicalUpload: Bool
}

/// Aggregate-only projection for support diagnostics. Keep row values and owner data out.
struct WorkoutDiagnosticsSnapshot: Equatable, Sendable {
    let exerciseCount: Int
    let workoutCount: Int
    let setCount: Int
    let manualMuscleMappingCount: Int
}

enum WeeklyStreakCalculator {
    private static let minimumWorkoutsPerWeek = 3

    static func current(
        sessions: [WorkoutSessionSummary],
        now: Date,
        calendar: Calendar
    ) -> Int {
        let counts = weeklyCounts(sessions: sessions, calendar: calendar)
        guard !counts.isEmpty else { return 0 }

        var cursor = calendar.gymEpochDay(for: calendar.gymMondayStart(of: now))
        if counts[cursor, default: 0] < minimumWorkoutsPerWeek { cursor -= 7 }

        var streak = 0
        while counts[cursor, default: 0] >= minimumWorkoutsPerWeek {
            streak += 1
            cursor -= 7
        }
        return streak
    }

    static func bestDuringPeriod(
        sessions: [WorkoutSessionSummary],
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar
    ) -> Int {
        guard endDate >= startDate else { return 0 }
        let periodWeeks = Set(
            sessions
                .filter { $0.date >= startDate && $0.date <= endDate }
                .map { calendar.gymEpochDay(for: calendar.gymMondayStart(of: $0.date)) }
        )
        guard !periodWeeks.isEmpty else { return 0 }

        let successfulWeeks = weeklyCounts(sessions: sessions, calendar: calendar)
            .filter { $0.value >= minimumWorkoutsPerWeek }
            .keys
            .sorted()

        var previousWeek: Int64?
        var running = 0
        var best = 0
        for week in successfulWeeks {
            running = previousWeek.map { $0 + 7 == week } == true ? running + 1 : 1
            if periodWeeks.contains(week) {
                best = max(best, running)
            }
            previousWeek = week
        }
        return best
    }

    private static func weeklyCounts(
        sessions: [WorkoutSessionSummary],
        calendar: Calendar
    ) -> [Int64: Int] {
        Dictionary(grouping: sessions) {
            calendar.gymEpochDay(for: calendar.gymMondayStart(of: $0.date))
        }.mapValues(\.count)
    }
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
    public private(set) var catalogSeedVersion: Int
    /// Account-scoped, validated client extension namespaces from the shared cloud row.
    /// Stored separately from workout/domain state so unknown clients can round-trip data
    /// without iOS interpreting or exposing it.
    private(set) var cloudExtensionsData: Data?

    public private(set) var accountStorageKey: String
    public private(set) var storageURL: URL

    public var snapshot: WorkoutDataSnapshot {
        WorkoutDataSnapshot(
            exercises: exercises,
            workouts: workouts,
            muscleMappings: muscleMappings,
            catalogSeedVersion: catalogSeedVersion
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

    private static let persistedSchemaVersion = 2
    private static let oldestSupportedPersistedSchemaVersion = 1
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
        var favoriteExerciseIDs: [UUID]?
        var cloudExtensionsData: Data?
    }

    private struct LoadedStore {
        let snapshot: WorkoutDataSnapshot
        let cloudExtensionsData: Data?
    }

    private struct AuthoritativeBackupSetRow: Equatable {
        let exerciseIdentity: String
        let weight: Double
        let reps: Int
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
        self.exercises = loaded.snapshot.exercises
        self.workouts = loaded.snapshot.workouts
        self.muscleMappings = loaded.snapshot.muscleMappings
        self.catalogSeedVersion = loaded.snapshot.catalogSeedVersion
        self.cloudExtensionsData = loaded.cloudExtensionsData
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
        self.cloudExtensionsData = loaded.cloudExtensionsData
        publish(Self.normalized(loaded.snapshot))
    }

    public func clearAllData() throws {
        try commit(WorkoutDataSnapshot())
    }

    /// Replaces only the opaque shared-cloud extension sidecar. Validation and the local
    /// account envelope write complete before the new value becomes observable, so a crash
    /// cannot pair another account's extension data with this store.
    func setCloudExtensionsData(_ data: Data?) throws {
        if let data {
            _ = try Self.validatedCloudExtensions(data, limits: .standard)
        }
        let previous = cloudExtensionsData
        cloudExtensionsData = data
        do {
            try persist(snapshot)
        } catch {
            cloudExtensionsData = previous
            throw error
        }
    }

    /// Removes the account-scoped file itself, used after an account/profile is deleted.
    /// Unlike `clearAllData`, this leaves no envelope containing the former storage key.
    public func destroyAccountData() throws {
        let empty = WorkoutDataSnapshot()
        // Stop exposing the deleted account's payload immediately. Persisting the empty
        // envelope before unlinking also makes a failed remove safe and retryable.
        publish(empty)
        cloudExtensionsData = nil
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

    /// Removes the primary envelope, its active-workout companion, and recovery copies
    /// for exactly one account.
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
        let activeWorkoutURL = ActiveWorkoutStore.storageURL(
            forWorkoutStorageURL: primaryURL
        )
        let activeWorkoutStem = activeWorkoutURL.deletingPathExtension().lastPathComponent
        let activeWorkoutRecoveryPrefix = "\(activeWorkoutStem).recovery-"
        var candidates = [primaryURL, activeWorkoutURL]
        do {
            let children = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            candidates.append(contentsOf: children.filter { child in
                let name = child.lastPathComponent
                let matchedPrefix: String
                if name.hasPrefix(recoveryPrefix) {
                    matchedPrefix = recoveryPrefix
                } else if name.hasPrefix(activeWorkoutRecoveryPrefix) {
                    matchedPrefix = activeWorkoutRecoveryPrefix
                } else {
                    return false
                }
                guard name.hasSuffix(".json") else { return false }
                let start = name.index(name.startIndex, offsetBy: matchedPrefix.count)
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
    public func addExercise(
        name: String,
        machineLoadProfile: MachineLoadProfile? = nil
    ) throws -> Exercise {
        let cleaned = try Self.validatedExerciseName(name)
        var created: Exercise?
        try mutate { state in
            guard !state.exercises.contains(where: {
                Self.exerciseIdentityConflicts($0, candidateName: cleaned)
            }) else {
                throw WorkoutStoreError.duplicateExerciseName
            }
            let exercise = Exercise(name: cleaned, machineLoadProfile: machineLoadProfile)
            state.exercises.append(exercise)
            created = exercise
        }
        return created!
    }

    /// Adds every missing public catalog item while preserving custom exercises and history.
    @discardableResult
    public func seedBuiltInExercises() throws -> Int {
        var inserted = 0
        try mutate { state in
            guard state.catalogSeedVersion < BuiltInExerciseCatalog.seedVersion else { return }
            let currentSeedVersion = max(0, state.catalogSeedVersion)
            let pendingDefinitions = BuiltInExerciseCatalog.definitions.filter {
                $0.introducedInSeedVersion > currentSeedVersion
            }
            var existingKeys = Set(state.exercises.compactMap { exercise in
                BuiltInExerciseCatalog.resolvedKey(
                    catalogKey: exercise.catalogKey,
                    name: exercise.name
                )
            })
            for definition in pendingDefinitions where !existingKeys.contains(definition.key) {
                // A full legacy account must still open. Keep the marker unset so deleting an
                // exercise later gives the migration another chance to add the remaining items.
                guard state.exercises.count < BackupImportLimits.standard.maximumExercises else { break }
                state.exercises.append(
                    Exercise(
                        name: definition.englishName,
                        catalogKey: definition.key
                    )
                )
                existingKeys.insert(definition.key)
                inserted += 1
            }
            if pendingDefinitions.allSatisfy({ existingKeys.contains($0.key) }) {
                state.catalogSeedVersion = BuiltInExerciseCatalog.seedVersion
            }
        }
        return inserted
    }

    public func renameExercise(id: UUID, to newName: String) throws {
        let cleaned = try Self.validatedExerciseName(newName)
        try mutate { state in
            guard let index = state.exercises.firstIndex(where: { $0.id == id }) else {
                throw WorkoutStoreError.exerciseNotFound
            }
            guard BuiltInExerciseCatalog.resolvedKey(
                catalogKey: state.exercises[index].catalogKey,
                name: state.exercises[index].name
            ) == nil else {
                throw WorkoutStoreError.builtInExerciseReadOnly
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

    /// Updates only the machine's selectable loads. Exercise identity, workout
    /// history, favorites, and manual muscle mappings stay attached to the same row.
    public func updateExerciseMachineLoadProfile(
        id: UUID,
        machineLoadProfile: MachineLoadProfile?
    ) throws {
        try mutate { state in
            guard let index = state.exercises.firstIndex(where: { $0.id == id }) else {
                throw WorkoutStoreError.exerciseNotFound
            }
            state.exercises[index].machineLoadProfile = machineLoadProfile
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

    /// Toggles a device-local preference in the same atomic account-store commit as
    /// the rest of the exercise state. Shared backups intentionally omit this flag.
    @discardableResult
    public func toggleExerciseFavorite(id: UUID) throws -> Bool {
        var updatedValue = false
        try mutate { state in
            guard let index = state.exercises.firstIndex(where: { $0.id == id }) else {
                throw WorkoutStoreError.exerciseNotFound
            }
            state.exercises[index].isFavorite.toggle()
            updatedValue = state.exercises[index].isFavorite
        }
        return updatedValue
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

    /// Resolves a validated shared plan into an editable local draft in one commit.
    /// Missing catalog/custom exercises are created only when the caller invokes this
    /// method after explicit user confirmation; no workout session is saved here.
    func materializeSharedWorkoutDraft(
        _ plan: SharedWorkoutPlan
    ) throws -> [WorkoutExerciseDraft] {
        let validated = try SharedWorkoutLinkValidator.validate(plan)
        var result: [WorkoutExerciseDraft] = []
        try mutate { state in
            var resolvedDrafts: [WorkoutExerciseDraft] = []
            resolvedDrafts.reserveCapacity(validated.exercises.count)

            for sharedExercise in validated.exercises {
                let exerciseID: UUID
                let trustedCatalogKey = BuiltInExerciseCatalog.canonicalKey(
                    forName: sharedExercise.name
                )
                if let catalogKey = trustedCatalogKey {
                    let matches = state.exercises.filter {
                        BuiltInExerciseCatalog.resolvedKey(
                            catalogKey: $0.catalogKey,
                            name: $0.name
                        ) == catalogKey
                    }
                    guard matches.count <= 1 else {
                        throw WorkoutStoreError.invalidWorkout(
                            "The shared exercise identity is ambiguous."
                        )
                    }
                    if let existing = matches.first {
                        exerciseID = existing.id
                    } else {
                        guard state.exercises.count < BackupImportLimits.standard.maximumExercises else {
                            throw WorkoutStoreError.importLimitExceeded("exercise count")
                        }
                        guard let definition = BuiltInExerciseCatalog.definition(forKey: catalogKey) else {
                            throw SharedWorkoutLinkError.invalidCatalogKey
                        }
                        let exercise = Exercise(
                            name: definition.englishName,
                            catalogKey: definition.key
                        )
                        guard !state.exercises.contains(where: {
                            Self.exerciseIdentityConflicts($0, candidateName: exercise.name)
                        }) else {
                            throw WorkoutStoreError.duplicateExerciseName
                        }
                        state.exercises.append(exercise)
                        exerciseID = exercise.id
                    }
                } else if let existingID = try Self.resolvedStoredExerciseID(
                    for: sharedExercise.name,
                    in: state.exercises
                ) {
                    exerciseID = existingID
                } else {
                    guard state.exercises.count < BackupImportLimits.standard.maximumExercises else {
                        throw WorkoutStoreError.importLimitExceeded("exercise count")
                    }
                    let cleaned = try Self.validatedExerciseName(sharedExercise.name)
                    guard !state.exercises.contains(where: {
                        Self.exerciseIdentityConflicts($0, candidateName: cleaned)
                    }) else {
                        throw WorkoutStoreError.duplicateExerciseName
                    }
                    let exercise = Exercise(name: cleaned)
                    state.exercises.append(exercise)
                    exerciseID = exercise.id
                }

                resolvedDrafts.append(
                    WorkoutExerciseDraft(
                        exerciseID: exerciseID,
                        sets: sharedExercise.sets.map {
                            WorkoutSetDraft(weight: $0.weight, reps: $0.repetitions)
                        }
                    )
                )
            }
            result = resolvedDrafts
        }
        return result
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
            var orderedIDs: [UUID] = []
            var grouped: [UUID: [WorkoutSetDraft]] = [:]

            for set in namedSets {
                let cleanedName = set.exerciseName.gymTrimmed
                guard !cleanedName.isEmpty else { continue }
                let name = try Self.validatedExerciseName(cleanedName)
                try Self.validate(weight: set.weight, reps: set.reps)
                let exerciseID: UUID
                if let existing = try Self.resolvedStoredExerciseID(
                    for: name,
                    in: state.exercises
                ) {
                    exerciseID = existing
                } else {
                    let exercise = Exercise(name: name)
                    state.exercises.append(exercise)
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

    /// Atomically restores any exercise identities needed by a frozen local completion
    /// intent and inserts its workout. A retry accepts only history that matches the
    /// immutable block/set payload and the same exercise identities.
    @discardableResult
    func commitActiveWorkout(
        _ intent: ActiveWorkoutCommitIntent,
        expectedAccountStorageKey: String
    ) throws -> WorkoutSession {
        guard expectedAccountStorageKey == accountStorageKey else {
            throw WorkoutStoreError.storageAccountMismatch
        }
        try Self.validateActiveWorkoutCommit(intent)

        var storedWorkout: WorkoutSession?
        try mutate { state in
            if let existing = state.workouts.first(where: { $0.id == intent.workoutID }) {
                guard Self.workout(existing, matches: intent, exercises: state.exercises) else {
                    throw WorkoutStoreError.invalidWorkout(
                        "Existing history does not match the committed active workout."
                    )
                }
                storedWorkout = existing
                return
            }

            let limits = BackupImportLimits.standard
            guard state.workouts.count < limits.maximumSessions else {
                throw WorkoutStoreError.importLimitExceeded("session count")
            }
            let existingSetCount = state.workouts.reduce(0) { count, workout in
                count + workout.setCount
            }
            let committedSetCount = intent.exercises.reduce(0) { $0 + $1.sets.count }
            guard existingSetCount <= limits.maximumTotalSets - committedSetCount else {
                throw WorkoutStoreError.importLimitExceeded("set count")
            }

            var resolvedExerciseIDs: [UUID: UUID] = [:]
            for committedExercise in intent.exercises {
                resolvedExerciseIDs[committedExercise.id] = try Self.resolveOrRestoreExercise(
                    for: committedExercise,
                    in: &state
                )
            }
            var completedBlocks: [WorkoutExercise] = []
            completedBlocks.reserveCapacity(intent.exercises.count)
            for committedExercise in intent.exercises {
                guard let resolvedExerciseID = resolvedExerciseIDs[committedExercise.id] else {
                    throw WorkoutStoreError.persistenceFailure(
                        "The active workout exercise resolution was incomplete."
                    )
                }
                completedBlocks.append(
                    WorkoutExercise(
                        id: committedExercise.id,
                        exerciseID: resolvedExerciseID,
                        sets: committedExercise.sets
                    )
                )
            }
            let workout = WorkoutSession(
                id: intent.workoutID,
                date: intent.workoutDate,
                note: intent.note,
                exercises: completedBlocks
            )
            state.workouts.append(workout)
            storedWorkout = workout
        }
        guard let storedWorkout else {
            throw WorkoutStoreError.persistenceFailure(
                "The committed active workout was not stored."
            )
        }
        return storedWorkout
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
            guard !state.workouts[workoutIndex].exercises.contains(where: {
                $0.exerciseID == exerciseID
            }) else {
                throw WorkoutStoreError.invalidWorkout(
                    "The exercise is already in this workout."
                )
            }
            let block = WorkoutExercise(
                exerciseID: exerciseID,
                sets: [WorkoutSet(weight: initialSet.weight, reps: initialSet.reps)]
            )
            // Match new-workout creation: a manually added exercise is immediately
            // visible at the top without deleting or rewriting any existing block.
            state.workouts[workoutIndex].exercises.insert(block, at: 0)
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
            weeklyStreakWeeks: {
                if let startDate, let endDate,
                   !calendar.isDate(startDate, equalTo: now, toGranularity: .month) {
                    return WeeklyStreakCalculator.bestDuringPeriod(
                        sessions: workoutSummaries,
                        from: startDate,
                        through: endDate,
                        calendar: calendar
                    )
                }
                return WeeklyStreakCalculator.current(
                    sessions: workoutSummaries,
                    now: now,
                    calendar: calendar
                )
            }()
        )
    }

    /// Canonical cross-platform profile scoring.
    public func syncProfileStats() -> SyncProfileStats {
        let summaries = workoutSummaries
        let xp = summaries.reduce(0) { $0 + GamificationEngine.xpForSession($1) }
        let level = GamificationEngine.level(for: xp)
        return SyncProfileStats(xp: xp, level: level, workouts: summaries.count)
    }

    func diagnosticsSnapshot() -> WorkoutDiagnosticsSnapshot {
        WorkoutDiagnosticsSnapshot(
            exerciseCount: exercises.count,
            workoutCount: workouts.lazy.filter { $0.setCount > 0 }.count,
            setCount: workouts.reduce(0) { $0 + $1.setCount },
            manualMuscleMappingCount: muscleMappings.count
        )
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

    /// Full private backup for user-controlled migration and restore. Diagnostics use
    /// `WorkoutDiagnosticsSnapshot` and never pass through this schema.

    public func makeBackup(
        owner: BackupOwner? = nil,
        exportedAt: Date = Date()
    ) throws -> GymBackup {
        let exportedAtMilliseconds = try Self.validatedTimestamp(
            exportedAt,
            field: "export timestamp"
        )
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let backupExercises = exercises
            .map {
                BackupExercise(
                    name: $0.name,
                    catalogKey: $0.catalogKey,
                    machineLoadProfile: $0.machineLoadProfile
                )
            }
            .sorted(by: BackupExercisePortableWireOrder.precedes)
        let backupSessions = try workouts
            .enumerated()
            .filter { $0.element.setCount > 0 }
            .sorted { lhs, rhs in
                if lhs.element.date != rhs.element.date {
                    return lhs.element.date < rhs.element.date
                }
                return lhs.offset < rhs.offset
            }
            .map { indexedWorkout in
                let workout = indexedWorkout.element
                return BackupSession(
                    date: try Self.validatedTimestamp(workout.date, field: "session timestamp"),
                    note: workout.note,
                    exercises: workout.exercises.compactMap { block in
                        guard let exercise = exerciseByID[block.exerciseID], !block.sets.isEmpty else {
                            return nil
                        }
                        return BackupWorkoutExercise(
                            name: exercise.name,
                            catalogKey: exercise.catalogKey,
                            // The catalog already carries the current machine profile. Keeping a
                            // second copy in every historical block made otherwise equivalent
                            // Android and iOS cloud envelopes diverge.
                            machineLoadProfile: nil,
                            sets: block.sets.map { BackupSet(weight: $0.weight, reps: $0.reps) }
                        )
                    }
                )
            }
        let backupSets = backupSessions.flatMap { session in
            (session.exercises ?? []).flatMap(\.sets)
        }

        return GymBackup(
            exportedAt: exportedAtMilliseconds,
            diagnostics: false,
            owner: owner ?? BackupOwner(accountID: accountStorageKey),
            catalogSeedVersion: catalogSeedVersion,
            exercises: backupExercises,
            sessions: backupSessions,
            summary: BackupSummary(
                exerciseCount: backupExercises.count,
                sessionCount: backupSessions.count,
                setCount: backupSets.count,
                totalVolume: backupSets.reduce(0) {
                    $0 + ($1.weight * Double($1.reps))
                }
            )
        )
    }

    public func exportBackupData(
        owner: BackupOwner? = nil,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        if prettyPrinted { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        do {
            return try encoder.encode(try makeBackup(owner: owner))
        } catch let error as WorkoutStoreError {
            throw error
        } catch {
            throw WorkoutStoreError.persistenceFailure(error.localizedDescription)
        }
    }

    public func exportBackupJSON(
        owner: BackupOwner? = nil,
        prettyPrinted: Bool = true
    ) throws -> String {
        let data = try exportBackupData(
            owner: owner,
            prettyPrinted: prettyPrinted
        )
        guard let json = String(data: data, encoding: .utf8) else {
            throw WorkoutStoreError.persistenceFailure("UTF-8 encoding failed.")
        }
        return json
    }

    /// Encodes only the schema-v2 workout core understood by the released 2.2.9 clients.
    /// Client-specific extensions, catalog migration markers, and machine-load profiles stay
    /// account-local so a newer client cannot make the shared row unreadable to an older one.
    func exportCloudBackupData(
        owner: BackupOwner,
        extensionsData: Data? = nil
    ) throws -> Data {
        let backupData = try exportBackupData(owner: owner, prettyPrinted: false)
        let decoded = try JSONDecoder().decode(GymBackup.self, from: backupData)
        // A legacy local store can safely retain two previously distinct spellings that now
        // share one portable identity. Never publish that ambiguity or silently merge it.
        var backup = try Self.canonicalCloudWorkoutIdentityInput(decoded)
        backup.exercises = backup.exercises.map { exercise in
            var portable = exercise
            portable.machineLoadProfile = nil
            return portable
        }
        backup.sessions = backup.sessions.map { session in
            var portable = session
            portable.exercises = session.exercises?.map { block in
                var portableBlock = block
                portableBlock.machineLoadProfile = nil
                return portableBlock
            }
            return portable
        }

        let encoded: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoded = try encoder.encode(backup)
        } catch {
            throw WorkoutStoreError.persistenceFailure(error.localizedDescription)
        }
        guard var root = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw WorkoutStoreError.persistenceFailure("Cloud backup encoding failed.")
        }
        root.removeValue(forKey: "catalogSeedVersion")
        root.removeValue(forKey: "extensions")
        // Keep the source-compatible argument while deliberately retaining the data locally.
        _ = extensionsData
        return try Self.encodedCloudBackup(root, limits: .standard)
    }

    /// Validates and canonicalizes an authenticated shared cloud row. Legacy PWA rows are
    /// converted to the native workout core while their language/mapping/profile state moves
    /// into `extensions.pwa`. Unknown extension namespaces are retained as bounded opaque JSON.
    static func prepareCloudBackup(
        _ data: Data,
        activeOwner: BackupOwner,
        localCatalogSeedVersion: Int = 0,
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
        guard (0 ... BuiltInExerciseCatalog.seedVersion).contains(localCatalogSeedVersion) else {
            throw WorkoutStoreError.corruptStore("Unsupported exercise catalog seed version.")
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

        if isLegacyPWACloudEnvelope(root) {
            return try prepareLegacyPWACloudBackup(
                root,
                canonicalOwner: canonicalOwner,
                expectedUserID: expectedUserID,
                expectedAccountID: expectedAccountID,
                limits: limits
            )
        }

        let extensionsData = try encodedExtensionsData(from: root, limits: limits)
        var needsEncoding = false
        var requiresCanonicalUpload = false

        if root["catalogSeedVersion"] == nil {
            // The shared cloud catalog is authoritative and intentionally omits this local
            // migration marker. Treat an absent marker as fully seeded so a fresh install
            // cannot resurrect built-ins deleted on another platform.
            root["catalogSeedVersion"] = BuiltInExerciseCatalog.seedVersion
            needsEncoding = true
        }

        if root["owner"] == nil || root["owner"] is NSNull {
            // Only the exact five-key earliest PWA row may inherit the authenticated
            // user_states owner. A native-shaped document without an owner is ambiguous.
            throw WorkoutStoreError.backupOwnerMismatch
        } else if let owner = root["owner"] as? [String: Any] {
            guard let ownerUserID = owner["userId"] as? String,
                  ownerUserID == expectedUserID,
                  let ownerAccountID = owner["accountId"] as? String,
                  isRecognizedCloudAccountID(ownerAccountID, userID: expectedUserID),
                  isRecognizedCloudAccountID(expectedAccountID, userID: expectedUserID) else {
                throw WorkoutStoreError.backupOwnerMismatch
            }
            if let remoteMarker = owner["remote"] as? String {
                guard remoteMarker == "supabase" else {
                    throw WorkoutStoreError.backupOwnerMismatch
                }
                // Legacy PWA rows may use `remote-<uuid>`. Exact user identity is
                // authoritative; rewrite the alias to the portable Supabase UUID.
                root["owner"] = canonicalOwner
                needsEncoding = true
                requiresCanonicalUpload = true
            } else {
                guard jsonBoolean(owner["remote"]) == true else {
                    throw WorkoutStoreError.backupOwnerMismatch
                }
            }
        } else {
            throw WorkoutStoreError.backupOwnerMismatch
        }

        let preparedData = needsEncoding ? try encodedCloudBackup(root, limits: limits) : data
        // Decoder tolerance remains broader than cloud write tolerance. Unknown core fields
        // keep the row readable but paused; known namespaced extensions are lossless.
        let roundTripSafe = isCanonicalNativeCloudEnvelope(
            root,
            expectedUserID: expectedUserID,
            expectedAccountID: expectedAccountID,
            limits: limits
        )
        return PreparedCloudBackup(
            data: preparedData,
            roundTripSafe: roundTripSafe,
            extensionsData: roundTripSafe ? extensionsData : nil,
            requiresCanonicalUpload: roundTripSafe && requiresCanonicalUpload
        )
    }

    private static func isLegacyPWACloudEnvelope(_ root: [String: Any]) -> Bool {
        let legacySignals: Set<String> = [
            "language", "mappings", "profile", "progressExerciseId",
            "source", "exerciseCatalog"
        ]
        return !legacySignals.isDisjoint(with: Set(root.keys))
    }

    private static func prepareLegacyPWACloudBackup(
        _ legacyRoot: [String: Any],
        canonicalOwner: [String: Any],
        expectedUserID: String,
        expectedAccountID: String,
        limits: BackupImportLimits
    ) throws -> PreparedCloudBackup {
        let earliestOwnerlessKeys: Set<String> = [
            "language", "exercises", "sessions", "mappings", "profile"
        ]
        let allowedKeys: Set<String> = [
            "schemaVersion", "exportedAt", "app", "source", "diagnostics", "owner",
            "catalogSeedVersion", "language", "exercises", "exerciseCatalog", "sessions",
            "mappings", "profile", "progressExerciseId"
        ]
        guard Set(legacyRoot.keys).isSubset(of: allowedKeys),
              (legacyRoot["owner"] != nil || Set(legacyRoot.keys) == earliestOwnerlessKeys),
              legacyRoot["extensions"] == nil,
              legacyRoot["summary"] == nil,
              legacyRoot["exercises"] is [Any],
              legacyRoot["sessions"] is [Any],
              let mappings = legacyRoot["mappings"] as? [String: Any],
              let profile = legacyRoot["profile"] as? [String: Any] else {
            throw WorkoutStoreError.malformedBackup(
                "The legacy PWA cloud state has an unsupported shape."
            )
        }
        let language: String
        if let rawLanguage = legacyRoot["language"] {
            guard let rawLanguage = rawLanguage as? String else {
                throw WorkoutStoreError.malformedBackup(
                    "The legacy PWA language is invalid."
                )
            }
            language = rawLanguage
        } else {
            // The later owner-bound browser export omitted language; its documented
            // import fallback was English. Ownerless rows remain exact and must carry it.
            guard legacyRoot["owner"] != nil else {
                throw WorkoutStoreError.malformedBackup(
                    "The legacy PWA language is missing."
                )
            }
            language = "en"
        }
        if let schema = legacyRoot["schemaVersion"],
           jsonExactInteger(schema) != Int64(GymBackup.currentSchemaVersion) {
            throw WorkoutStoreError.malformedBackup("The legacy PWA schema is unsupported.")
        }
        let exportedAt: Int64
        if let rawExportedAt = legacyRoot["exportedAt"] {
            guard let value = jsonExactInteger(rawExportedAt),
                  (try? validatedTimestamp(value, field: "export timestamp")) != nil else {
                throw WorkoutStoreError.malformedBackup(
                    "The legacy PWA export timestamp is invalid."
                )
            }
            exportedAt = value
        } else {
            exportedAt = Date().gymEpochMilliseconds
        }
        if let app = legacyRoot["app"], app as? String != "GymApp" {
            throw WorkoutStoreError.malformedBackup("The legacy PWA app marker is invalid.")
        }
        if let source = legacyRoot["source"] {
            guard let source = source as? String,
                  !source.isEmpty,
                  source.utf8.count <= maximumAppNameBytes else {
                throw WorkoutStoreError.malformedBackup("The legacy PWA source is invalid.")
            }
        }
        if let diagnostics = legacyRoot["diagnostics"], jsonBoolean(diagnostics) != false {
            throw WorkoutStoreError.malformedBackup(
                "A diagnostics document cannot replace cloud workout state."
            )
        }
        if let owner = legacyRoot["owner"] {
            guard let owner = owner as? [String: Any],
                  Set(owner.keys).isSubset(of: ["accountId", "userId", "email", "remote"]),
                  Set(owner.keys).isSuperset(of: ["accountId", "userId", "remote"]),
                  let userID = owner["userId"] as? String,
                  userID == expectedUserID,
                  let accountID = owner["accountId"] as? String,
                  isRecognizedCloudAccountID(accountID, userID: expectedUserID),
                  isRecognizedCloudAccountID(expectedAccountID, userID: expectedUserID) else {
                throw WorkoutStoreError.backupOwnerMismatch
            }
            if let marker = owner["remote"] as? String {
                guard marker == "supabase" else {
                    throw WorkoutStoreError.backupOwnerMismatch
                }
            } else if jsonBoolean(owner["remote"]) != true {
                throw WorkoutStoreError.backupOwnerMismatch
            }
            if let rawEmail = owner["email"], !(rawEmail is NSNull) {
                guard let email = rawEmail as? String,
                      email.utf8.count <= maximumOwnerFieldBytes else {
                    throw WorkoutStoreError.backupOwnerMismatch
                }
            }
        }
        if let progressExerciseID = legacyRoot["progressExerciseId"],
           !(1 ... 9_007_199_254_740_991).contains(jsonExactInteger(progressExerciseID) ?? -1) {
            throw WorkoutStoreError.malformedBackup(
                "The legacy PWA progress exercise identifier is invalid."
            )
        }
        if let rawCatalog = legacyRoot["exerciseCatalog"] {
            guard let catalog = rawCatalog as? [Any],
                  catalog.count <= limits.maximumExercises else {
                throw WorkoutStoreError.malformedBackup(
                    "The legacy PWA compatibility catalog is invalid."
                )
            }
            for item in catalog {
                let name: String?
                if let item = item as? String {
                    name = item
                } else if let item = item as? [String: Any] {
                    name = item["name"] as? String
                } else {
                    name = nil
                }
                guard let name,
                      name == name.gymTrimmed,
                      !name.isEmpty,
                      name.count <= limits.maximumExerciseNameLength,
                      name.utf8.count <= limits.maximumExerciseNameBytes else {
                    throw WorkoutStoreError.malformedBackup(
                        "The legacy PWA compatibility catalog is invalid."
                    )
                }
            }
        }

        let pwaExtensions: [String: Any] = [
            "version": 1,
            "language": language,
            "mappings": mappings,
            "profile": profile
        ]
        let extensions = try validateCloudExtensionsObject(
            ["pwa": pwaExtensions],
            limits: limits
        )
        let extensionsData = try encodedCloudBackup(extensions, limits: limits)

        var decodingRoot = legacyRoot
        for key in [
            "language", "mappings", "profile", "progressExerciseId", "source",
            "exerciseCatalog"
        ] {
            decodingRoot.removeValue(forKey: key)
        }
        decodingRoot["schemaVersion"] = GymBackup.currentSchemaVersion
        decodingRoot["exportedAt"] = exportedAt
        decodingRoot["app"] = "GymApp"
        decodingRoot["diagnostics"] = false
        decodingRoot["owner"] = canonicalOwner
        if decodingRoot["catalogSeedVersion"] == nil {
            decodingRoot["catalogSeedVersion"] = BuiltInExerciseCatalog.seedVersion
        }

        let decodingData = try encodedCloudBackup(decodingRoot, limits: limits)
        let decoded: GymBackup
        do {
            decoded = try JSONDecoder().decode(GymBackup.self, from: decodingData)
        } catch {
            throw WorkoutStoreError.malformedBackup(error.localizedDescription)
        }
        guard decoded.exercises.count <= limits.maximumExercises,
              decoded.sessions.count <= limits.maximumSessions else {
            throw WorkoutStoreError.importLimitExceeded("legacy PWA collection count")
        }
        try validateBackupMetadata(decoded, limits: limits)
        var canonical = try canonicalCloudWorkoutIdentityInput(decoded)
        try validateLosslessAuthoritativeRestore(
            original: decoded,
            canonical: canonical,
            limits: limits
        )
        canonical.schemaVersion = GymBackup.currentSchemaVersion
        canonical.exportedAt = exportedAt
        canonical.app = "GymApp"
        canonical.diagnostics = false
        canonical.owner = BackupOwner(
            accountID: canonicalOwner["accountId"] as? String,
            userID: canonicalOwner["userId"] as? String,
            email: canonicalOwner["email"] as? String,
            remote: true
        )
        canonical.catalogSeedVersion = decoded.catalogSeedVersion
        canonical.summary = canonicalBackupSummary(canonical)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedCanonical: Data
        do {
            encodedCanonical = try encoder.encode(canonical)
        } catch {
            throw WorkoutStoreError.malformedBackup(error.localizedDescription)
        }
        guard var canonicalRoot = try JSONSerialization.jsonObject(
            with: encodedCanonical
        ) as? [String: Any] else {
            throw WorkoutStoreError.malformedBackup(
                "The legacy PWA state could not be canonicalized."
            )
        }
        canonicalRoot["extensions"] = extensions
        guard isCanonicalNativeCloudEnvelope(
            canonicalRoot,
            expectedUserID: expectedUserID,
            expectedAccountID: expectedAccountID,
            limits: limits
        ) else {
            throw WorkoutStoreError.malformedBackup(
                "The legacy PWA state cannot be represented losslessly."
            )
        }
        return PreparedCloudBackup(
            data: try encodedCloudBackup(canonicalRoot, limits: limits),
            roundTripSafe: true,
            extensionsData: extensionsData,
            requiresCanonicalUpload: true
        )
    }

    private static func canonicalBackupSummary(_ backup: GymBackup) -> BackupSummary {
        let blocks = backup.sessions.flatMap { $0.exercises ?? [] }
        let sets = blocks.flatMap(\.sets)
        return BackupSummary(
            exerciseCount: backup.exercises.count,
            sessionCount: backup.sessions.count,
            setCount: sets.count,
            totalVolume: sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        )
    }

    private static func encodedExtensionsData(
        from root: [String: Any],
        limits: BackupImportLimits
    ) throws -> Data? {
        guard let rawExtensions = root["extensions"] else { return nil }
        guard let extensions = rawExtensions as? [String: Any] else {
            throw WorkoutStoreError.malformedBackup("Cloud extensions must be an object.")
        }
        return try encodedCloudBackup(
            validateCloudExtensionsObject(extensions, limits: limits),
            limits: limits
        )
    }

    private static func validatedCloudExtensions(
        _ data: Data,
        limits: BackupImportLimits
    ) throws -> [String: Any] {
        guard data.count <= limits.maximumFileBytes else {
            throw WorkoutStoreError.importLimitExceeded("extension size")
        }
        try validateJSONEnvelope(data, limits: limits)
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw WorkoutStoreError.malformedBackup(error.localizedDescription)
        }
        guard let extensions = parsed as? [String: Any] else {
            throw WorkoutStoreError.malformedBackup("Cloud extensions must be an object.")
        }
        return try validateCloudExtensionsObject(extensions, limits: limits)
    }

    @discardableResult
    private static func validateCloudExtensionsObject(
        _ extensions: [String: Any],
        limits: BackupImportLimits
    ) throws -> [String: Any] {
        guard extensions.count <= 32 else {
            throw WorkoutStoreError.importLimitExceeded("extension namespace count")
        }
        let namespacePattern = try NSRegularExpression(pattern: "^[a-z][a-z0-9._-]{0,63}$")
        for (namespace, value) in extensions {
            let range = NSRange(namespace.startIndex..., in: namespace)
            guard namespacePattern.firstMatch(in: namespace, range: range) != nil,
                  value is [String: Any] else {
                throw WorkoutStoreError.malformedBackup(
                    "Cloud extension namespace must contain a valid object."
                )
            }
        }

        var pending: [Any] = [extensions]
        var nodeCount = 0
        while let value = pending.popLast() {
            nodeCount += 1
            guard nodeCount <= 1_000_000 else {
                throw WorkoutStoreError.importLimitExceeded("extension complexity")
            }
            if let object = value as? [String: Any] {
                for (key, child) in object {
                    guard !["__proto__", "prototype", "constructor"].contains(key) else {
                        throw WorkoutStoreError.malformedBackup(
                            "Cloud extensions contain a forbidden key."
                        )
                    }
                    pending.append(child)
                }
            } else if let array = value as? [Any] {
                pending.append(contentsOf: array)
            } else if value is String || value is NSNull || jsonBoolean(value) != nil ||
                        jsonFiniteNumber(value) != nil {
                continue
            } else {
                throw WorkoutStoreError.malformedBackup(
                    "Cloud extensions contain a non-JSON value."
                )
            }
        }

        if let rawPWA = extensions["pwa"] {
            guard let pwa = rawPWA as? [String: Any],
                  Set(pwa.keys) == Set(["version", "language", "mappings", "profile"]),
                  jsonExactInteger(pwa["version"]) == 1,
                  let language = pwa["language"] as? String,
                  ["en", "uk", "ru"].contains(language),
                  let mappings = pwa["mappings"] as? [String: Any],
                  mappings.count <= 2_000,
                  let profile = pwa["profile"] as? [String: Any] else {
                throw WorkoutStoreError.malformedBackup("The PWA cloud extension is invalid.")
            }
            for (name, rawMuscles) in mappings {
                guard name == name.gymTrimmed,
                      !name.isEmpty,
                      name.count <= limits.maximumExerciseNameLength,
                      name.utf8.count <= limits.maximumExerciseNameBytes,
                      let muscles = rawMuscles as? [Any],
                      muscles.count <= 32 else {
                    throw WorkoutStoreError.malformedBackup(
                        "The PWA muscle mapping is invalid."
                    )
                }
                var seen = Set<String>()
                for rawMuscle in muscles {
                    guard let muscle = rawMuscle as? String,
                          muscle == muscle.gymTrimmed,
                          !muscle.isEmpty,
                          muscle.utf16.count <= 64,
                          muscle.utf8.count <= 256,
                          seen.insert(muscle).inserted else {
                        throw WorkoutStoreError.malformedBackup(
                            "The PWA muscle mapping is invalid."
                        )
                    }
                }
            }
            guard Set(profile.keys) == Set(["split", "days", "goal", "calories"]),
                  let split = profile["split"] as? String,
                  ["Upper / Lower", "Full Body", "Push Pull Legs", "Custom"].contains(split),
                  let days = jsonExactInteger(profile["days"]),
                  (2 ... 6).contains(days),
                  let goal = profile["goal"] as? String,
                  ["Aesthetic Cut", "Muscle Gain", "Strength", "Balanced"].contains(goal),
                  let calories = profile["calories"] as? String,
                  ["Deficit", "Maintenance", "Surplus"].contains(calories) else {
                throw WorkoutStoreError.malformedBackup("The PWA training profile is invalid.")
            }
        }
        let encoded = try encodedCloudBackup(extensions, limits: limits)
        try validateJSONEnvelope(encoded, limits: limits)
        return extensions
    }

    private static func isCanonicalNativeCloudEnvelope(
        _ root: [String: Any],
        expectedUserID: String,
        expectedAccountID: String,
        limits: BackupImportLimits
    ) -> Bool {
        let requiredRootKeys: Set<String> = [
            "schemaVersion", "exportedAt", "app", "diagnostics", "owner",
            "exercises", "sessions", "summary"
        ]
        let rootKeys = Set(root.keys)
        let optionalRootKeys: Set<String> = ["catalogSeedVersion", "extensions"]
        guard requiredRootKeys.isSubset(of: rootKeys),
              rootKeys.isSubset(of: requiredRootKeys.union(optionalRootKeys)),
              jsonExactInteger(root["schemaVersion"]) == Int64(GymBackup.currentSchemaVersion),
              let exportedAt = jsonExactInteger(root["exportedAt"]),
              (try? validatedTimestamp(exportedAt, field: "export timestamp")) != nil,
              root["app"] as? String == "GymApp",
              jsonBoolean(root["diagnostics"]) == false else {
            return false
        }
        if rootKeys.contains("catalogSeedVersion") {
            guard let seedVersion = jsonExactInteger(root["catalogSeedVersion"]),
                  (0 ... Int64(BuiltInExerciseCatalog.seedVersion)).contains(seedVersion) else {
                return false
            }
        }
        if let rawExtensions = root["extensions"] {
            guard let extensions = rawExtensions as? [String: Any],
                  (try? validateCloudExtensionsObject(extensions, limits: limits)) != nil else {
                return false
            }
        }

        guard let owner = root["owner"] as? [String: Any],
              Set(owner.keys).isSubset(of: ["accountId", "userId", "email", "remote"]),
              Set(owner.keys).isSuperset(of: ["accountId", "userId", "remote"]),
              let ownerAccountID = owner["accountId"] as? String,
              isRecognizedCloudAccountID(ownerAccountID, userID: expectedUserID),
              isRecognizedCloudAccountID(expectedAccountID, userID: expectedUserID),
              owner["userId"] as? String == expectedUserID,
              jsonBoolean(owner["remote"]) == true else {
            return false
        }
        if let email = owner["email"],
           !(email is NSNull),
           !(email is String) {
            return false
        }
        for value in [owner["accountId"], owner["userId"], owner["email"]] {
            if let string = value as? String,
               string.utf8.count > maximumOwnerFieldBytes {
                return false
            }
        }

        guard let rawExercises = root["exercises"] as? [Any],
              rawExercises.count <= limits.maximumExercises else {
            return false
        }
        var catalogWires: [String: (name: String, catalogKey: String?)] = [:]
        var previousCatalogExercise: BackupExercise?
        for rawExercise in rawExercises {
            guard let exercise = rawExercise as? [String: Any],
                  let wire = canonicalNativeExerciseWire(
                      exercise,
                      allowLoadProfile: true,
                      limits: limits
                  ), catalogWires[wire.identity] == nil,
                  let exerciseData = try? JSONSerialization.data(withJSONObject: exercise),
                  let backupExercise = try? JSONDecoder().decode(
                      BackupExercise.self,
                      from: exerciseData
                  ),
                  previousCatalogExercise.map({
                      !BackupExercisePortableWireOrder.precedes(backupExercise, $0)
                  }) ?? true else {
                return false
            }
            catalogWires[wire.identity] = (wire.name, wire.catalogKey)
            previousCatalogExercise = backupExercise
        }

        guard let rawSessions = root["sessions"] as? [Any],
              rawSessions.count <= limits.maximumSessions else {
            return false
        }
        var totalSetCount = 0
        var totalVolume = 0.0
        var previousSessionTimestamp: Int64?
        for rawSession in rawSessions {
            guard let session = rawSession as? [String: Any],
                  Set(session.keys).isSubset(of: ["date", "note", "exercises"]),
                  Set(session.keys).isSuperset(of: ["date", "exercises"]),
                  let timestamp = jsonExactInteger(session["date"]),
                  (try? validatedTimestamp(timestamp, field: "session timestamp")) != nil,
                  previousSessionTimestamp.map({ $0 <= timestamp }) ?? true,
                  let rawBlocks = session["exercises"] as? [Any],
                  !rawBlocks.isEmpty,
                  rawBlocks.count <= limits.maximumExercisesPerSession else {
                return false
            }
            previousSessionTimestamp = timestamp
            if let note = session["note"], !(note is NSNull) {
                guard let note = note as? String,
                      note == note.gymTrimmed,
                      !note.isEmpty,
                      note.count <= limits.maximumNoteLength,
                      note.utf8.count <= limits.maximumNoteBytes else {
                    return false
                }
            }

            for rawBlock in rawBlocks {
                guard let block = rawBlock as? [String: Any],
                      !block.keys.contains("loadProfile"),
                      let wire = canonicalNativeExerciseWire(
                          block,
                          allowLoadProfile: false,
                          limits: limits
                      ),
                      let catalogWire = catalogWires[wire.identity],
                      wireStringsEqual(catalogWire.name, wire.name),
                      optionalWireStringsEqual(catalogWire.catalogKey, wire.catalogKey),
                      let rawSets = block["sets"] as? [Any],
                      !rawSets.isEmpty,
                      rawSets.count <= limits.maximumSetsPerExercise else {
                    return false
                }
                for rawSet in rawSets {
                    guard let set = rawSet as? [String: Any],
                          Set(set.keys) == Set(["weight", "reps"]),
                          let weight = jsonFiniteNumber(set["weight"]),
                          (0 ... maximumWeight).contains(weight),
                          let reps = jsonExactInteger(set["reps"]),
                          (1 ... Int64(maximumReps)).contains(reps) else {
                        return false
                    }
                    totalSetCount += 1
                    totalVolume += weight * Double(reps)
                    guard totalSetCount <= limits.maximumTotalSets else { return false }
                    guard totalVolume.isFinite else { return false }
                }
            }
        }

        guard let summary = root["summary"] as? [String: Any],
              Set(summary.keys) == Set([
                  "exerciseCount", "sessionCount", "setCount", "totalVolume"
              ]),
              jsonExactInteger(summary["exerciseCount"]) == Int64(rawExercises.count),
              jsonExactInteger(summary["sessionCount"]) == Int64(rawSessions.count),
              jsonExactInteger(summary["setCount"]) == Int64(totalSetCount),
              let summaryVolume = jsonFiniteNumber(summary["totalVolume"]),
              summaryVolume == (totalVolume == 0 ? 0.0 : totalVolume) else {
            return false
        }
        return true
    }

    private static func isRecognizedCloudAccountID(_ accountID: String, userID: String) -> Bool {
        accountID == userID ||
            accountID == "remote-\(userID)" ||
            accountID == "cloud_\(userID)"
    }

    private static func canonicalNativeExerciseWire(
        _ exercise: [String: Any],
        allowLoadProfile: Bool,
        limits: BackupImportLimits
    ) -> (identity: String, name: String, catalogKey: String?)? {
        let allowedKeys: Set<String> = allowLoadProfile
            ? ["name", "catalogKey", "loadProfile"]
            : ["name", "catalogKey", "sets"]
        guard Set(exercise.keys).isSubset(of: allowedKeys),
              exercise.keys.contains("name"),
              let name = exercise["name"] as? String,
              name.count <= limits.maximumExerciseNameLength,
              name.utf8.count <= limits.maximumExerciseNameBytes else {
            return nil
        }
        let rawCatalogKey: String?
        if exercise.keys.contains("catalogKey") {
            guard let value = exercise["catalogKey"] as? String,
                  value.utf8.count <= maximumCatalogKeyBytes else {
                return nil
            }
            rawCatalogKey = value
        } else {
            rawCatalogKey = nil
        }
        guard let canonical = try? canonicalBackupExerciseWire(
            name: name,
            catalogKey: rawCatalogKey
        ), canonical.name == name, canonical.catalogKey == rawCatalogKey else {
            return nil
        }
        if allowLoadProfile,
           exercise.keys.contains("loadProfile"),
           !isCanonicalMachineLoadProfile(exercise["loadProfile"]) {
            return nil
        }
        return (
            backupExerciseIdentity(name: canonical.name, catalogKey: canonical.catalogKey),
            canonical.name,
            canonical.catalogKey
        )
    }

    private static func isCanonicalMachineLoadProfile(_ value: Any?) -> Bool {
        guard let profile = value as? [String: Any],
              Set(profile.keys) == Set(["direction", "allowedWeightsKg"]),
              let direction = profile["direction"] as? String,
              MachineLoadDirection(rawValue: direction) != nil,
              let rawWeights = profile["allowedWeightsKg"] as? [Any],
              !rawWeights.isEmpty,
              rawWeights.count <= MachineLoadProfile.maximumAllowedWeightCount else {
            return false
        }
        var previous: Double?
        for rawWeight in rawWeights {
            guard let weight = jsonFiniteNumber(rawWeight),
                  (0 ... MachineLoadProfile.maximumAllowedWeightKg).contains(weight),
                  previous.map({ $0 < weight }) ?? true else {
                return false
            }
            previous = weight == 0 ? 0.0 : weight
        }
        return true
    }

    private static func jsonBoolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    private static func jsonFiniteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func jsonExactInteger(_ value: Any?) -> Int64? {
        guard let number = jsonFiniteNumber(value),
              number.rounded() == number,
              number >= Double(Int64.min),
              number < Double(Int64.max) else {
            return nil
        }
        let integer = Int64(number)
        return Double(integer) == number ? integer : nil
    }

    private static func wireStringsEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    private static func optionalWireStringsEqual(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return wireStringsEqual(left, right)
        default:
            return false
        }
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

        var backup: GymBackup
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
        let decodedBackup = backup
        backup = try Self.canonicalCloudWorkoutIdentityInput(backup)
        if replacingExisting {
            try Self.validateLosslessAuthoritativeRestore(
                original: decodedBackup,
                canonical: backup,
                limits: limits
            )
        }

        // Favorite status is local to this account and deliberately absent from the
        // Android/PWA-compatible backup. Preserve it by stable exercise identity when
        // a cloud restore replaces UUIDs, so an older client cannot erase the choice.
        let localExercisesByCatalogKey = Dictionary(grouping: snapshot.exercises.compactMap {
            exercise -> (key: String, exercise: Exercise)? in
            guard let key = BuiltInExerciseCatalog.resolvedKey(
                catalogKey: exercise.catalogKey,
                name: exercise.name
            ) else { return nil }
            return (key, exercise)
        }, by: \.key)
        let localExercisesByPortableNameKey = Dictionary(
            grouping: snapshot.exercises,
            by: { Self.nameKey($0.name) }
        )
        func isLocallyFavorite(name: String, catalogKey: String?) -> Bool {
            let legacyKey = Self.legacyPersistedNameKey(name)
            if let exactLegacyMatch = snapshot.exercises.first(where: {
                Self.legacyPersistedNameKey($0.name) == legacyKey
            }) {
                return exactLegacyMatch.isFavorite
            }
            if let resolved = BuiltInExerciseCatalog.resolvedKey(
                catalogKey: catalogKey,
                name: name
            ) {
                let catalogMatches = localExercisesByCatalogKey[resolved] ?? []
                return catalogMatches.count == 1 && catalogMatches[0].exercise.isFavorite
            }
            let portableMatches = localExercisesByPortableNameKey[Self.nameKey(name)] ?? []
            return portableMatches.count == 1 && portableMatches[0].isFavorite
        }

        func localMachineLoadProfile(
            name: String,
            catalogKey: String?
        ) -> MachineLoadProfile? {
            let legacyKey = Self.legacyPersistedNameKey(name)
            let exactLegacyMatches = snapshot.exercises.filter {
                Self.legacyPersistedNameKey($0.name) == legacyKey
            }
            if exactLegacyMatches.count == 1 {
                return exactLegacyMatches[0].machineLoadProfile
            }
            if let resolved = BuiltInExerciseCatalog.resolvedKey(
                catalogKey: catalogKey,
                name: name
            ) {
                let catalogMatches = localExercisesByCatalogKey[resolved] ?? []
                if catalogMatches.count == 1 {
                    return catalogMatches[0].exercise.machineLoadProfile
                }
            }
            let portableMatches = localExercisesByPortableNameKey[Self.nameKey(name)] ?? []
            return portableMatches.count == 1
                ? portableMatches[0].machineLoadProfile
                : nil
        }

        var next = replacingExisting ? WorkoutDataSnapshot() : snapshot
        next.catalogSeedVersion = replacingExisting
            ? backup.catalogSeedVersion
            : max(next.catalogSeedVersion, backup.catalogSeedVersion)
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

        func resolveExercise(
            _ rawName: String,
            catalogKey: String? = nil,
            machineLoadProfile: MachineLoadProfile? = nil
        ) throws -> UUID? {
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
            let resolvedCatalogKey = BuiltInExerciseCatalog.resolvedKey(
                catalogKey: catalogKey,
                name: name
            )
            if let id = try Self.resolvedStoredExerciseID(for: name, in: next.exercises) {
                if let index = exerciseIndexByID[id] {
                    if next.exercises[index].catalogKey == nil {
                        next.exercises[index].catalogKey = resolvedCatalogKey
                    }
                    if let machineLoadProfile {
                        next.exercises[index].machineLoadProfile = machineLoadProfile
                    }
                }
                return id
            }
            if let resolvedCatalogKey,
               let id = exerciseIDByCatalogKey[resolvedCatalogKey] {
                if let machineLoadProfile,
                   let index = exerciseIndexByID[id] {
                    next.exercises[index].machineLoadProfile = machineLoadProfile
                }
                return id
            }
            guard next.exercises.count < limits.maximumExercises else {
                throw WorkoutStoreError.importLimitExceeded("exercise count")
            }
            let exercise = Exercise(
                name: name,
                catalogKey: resolvedCatalogKey,
                machineLoadProfile: machineLoadProfile ?? localMachineLoadProfile(
                    name: name,
                    catalogKey: resolvedCatalogKey
                ),
                isFavorite: isLocallyFavorite(name: name, catalogKey: resolvedCatalogKey)
            )
            next.exercises.append(exercise)
            exerciseIndexByID[exercise.id] = next.exercises.count - 1
            if let resolvedCatalogKey {
                exerciseIDByCatalogKey[resolvedCatalogKey] = exercise.id
            }
            addedExercises += 1
            return exercise.id
        }

        for item in backup.exercises {
            _ = try resolveExercise(
                item.name,
                catalogKey: item.catalogKey,
                machineLoadProfile: item.machineLoadProfile
            )
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
            let drafts: [WorkoutExerciseDraft]
            if let blocks = session.exercises {
                guard blocks.count <= limits.maximumExercisesPerSession else {
                    throw WorkoutStoreError.importLimitExceeded("exercises per session")
                }
                var nativeDrafts: [WorkoutExerciseDraft] = []
                var nativeSetCountByExerciseID: [UUID: Int] = [:]
                for block in blocks {
                    guard block.sets.count <= limits.maximumSetsPerExercise else {
                        throw WorkoutStoreError.importLimitExceeded("sets per exercise")
                    }
                    guard let exerciseID = try resolveExercise(
                        block.name,
                        catalogKey: block.catalogKey,
                        machineLoadProfile: nil
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
                        let weight = set.weight <= 0 ? 0.0 : set.weight
                        guard weight <= Self.maximumWeight else {
                            ignoredInvalidSets += 1
                            continue
                        }
                        sets.append(WorkoutSetDraft(weight: weight, reps: set.reps))
                    }
                    if !sets.isEmpty {
                        let combinedCount = nativeSetCountByExerciseID[exerciseID, default: 0] + sets.count
                        guard combinedCount <= limits.maximumSetsPerExercise else {
                            throw WorkoutStoreError.importLimitExceeded("sets per exercise")
                        }
                        nativeSetCountByExerciseID[exerciseID] = combinedCount
                        nativeDrafts.append(WorkoutExerciseDraft(exerciseID: exerciseID, sets: sets))
                    }
                }
                drafts = nativeDrafts
            } else if let flatSets = session.sets {
                guard flatSets.count <= limits.maximumTotalSets else {
                    throw WorkoutStoreError.importLimitExceeded("total set count")
                }
                var orderedExerciseIDs: [UUID] = []
                var setsByExerciseID: [UUID: [WorkoutSetDraft]] = [:]
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
                    let weight = set.weight <= 0 ? 0.0 : set.weight
                    guard weight <= Self.maximumWeight else {
                        ignoredInvalidSets += 1
                        continue
                    }
                    guard let exerciseID = try resolveExercise(
                        name,
                        catalogKey: set.catalogKey
                    ) else { continue }
                    if setsByExerciseID[exerciseID] == nil {
                        orderedExerciseIDs.append(exerciseID)
                    }
                    setsByExerciseID[exerciseID, default: []].append(
                        WorkoutSetDraft(weight: weight, reps: set.reps)
                    )
                    guard setsByExerciseID[exerciseID, default: []].count <= limits.maximumSetsPerExercise else {
                        throw WorkoutStoreError.importLimitExceeded("sets per exercise")
                    }
                }
                guard orderedExerciseIDs.count <= limits.maximumExercisesPerSession else {
                    throw WorkoutStoreError.importLimitExceeded("exercises per session")
                }
                drafts = orderedExerciseIDs.compactMap { exerciseID -> WorkoutExerciseDraft? in
                    guard let sets = setsByExerciseID[exerciseID], !sets.isEmpty else { return nil }
                    return WorkoutExerciseDraft(exerciseID: exerciseID, sets: sets)
                }
            } else {
                drafts = []
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
            if replacingExisting || existingSignatures.insert(signature).inserted {
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
        catalogSeedVersion = state.catalogSeedVersion
    }

    private func persist(_ state: WorkoutDataSnapshot) throws {
        let envelope = PersistedEnvelope(
            schemaVersion: Self.persistedSchemaVersion,
            accountStorageKey: accountStorageKey,
            savedAt: Date(),
            snapshot: state,
            favoriteExerciseIDs: state.exercises
                .filter(\.isFavorite)
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString },
            cloudExtensionsData: cloudExtensionsData
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
    ) throws -> LoadedStore {
        guard fileManager.fileExists(atPath: url.path) else {
            return LoadedStore(snapshot: WorkoutDataSnapshot(), cloudExtensionsData: nil)
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let envelope = try localDecoder().decode(PersistedEnvelope.self, from: data)
            guard (oldestSupportedPersistedSchemaVersion ... persistedSchemaVersion)
                .contains(envelope.schemaVersion) else {
                throw WorkoutStoreError.corruptStore(
                    "Unsupported local schema \(envelope.schemaVersion)."
                )
            }
            guard envelope.accountStorageKey == accountStorageKey else {
                throw WorkoutStoreError.storageAccountMismatch
            }
            var migratedSnapshot = envelope.snapshot
            let persistedFavoriteIDs = envelope.favoriteExerciseIDs ?? []
            guard persistedFavoriteIDs.count <= BackupImportLimits.standard.maximumExercises else {
                throw WorkoutStoreError.corruptStore("Too many favorite exercise identifiers.")
            }
            let favoriteIDs = Set(persistedFavoriteIDs).union(
                migratedSnapshot.exercises.lazy.filter(\.isFavorite).map(\.id)
            )
            migratedSnapshot.exercises = migratedSnapshot.exercises.map { exercise in
                var migrated = exercise
                migrated.isFavorite = favoriteIDs.contains(exercise.id)
                return migrated
            }
            try validate(migratedSnapshot)
            if let extensionsData = envelope.cloudExtensionsData {
                _ = try validatedCloudExtensions(extensionsData, limits: .standard)
            }
            return LoadedStore(
                snapshot: normalized(migratedSnapshot),
                cloudExtensionsData: envelope.cloudExtensionsData
            )
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
        let workouts = state.workouts
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.date != rhs.element.date {
                    return lhs.element.date > rhs.element.date
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        return WorkoutDataSnapshot(
            exercises: state.exercises.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            },
            workouts: workouts,
            muscleMappings: state.muscleMappings.sorted {
                if $0.exerciseNameKey == $1.exerciseNameKey {
                    return $0.muscleID < $1.muscleID
                }
                return $0.exerciseNameKey < $1.exerciseNameKey
            },
            catalogSeedVersion: state.catalogSeedVersion
        )
    }

    private static func validate(_ state: WorkoutDataSnapshot) throws {
        guard (0 ... BuiltInExerciseCatalog.seedVersion).contains(state.catalogSeedVersion) else {
            throw WorkoutStoreError.corruptStore("Unsupported exercise catalog seed version.")
        }
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
        // Validate persisted names with the exact key used before portable cloud identity was
        // introduced. New CRUD/import paths still use the stricter portable key below.
        guard Set(state.exercises.map { legacyPersistedNameKey($0.name) }).count == state.exercises.count else {
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
        guard (0 ... BuiltInExerciseCatalog.seedVersion).contains(backup.catalogSeedVersion) else {
            throw WorkoutStoreError.malformedBackup(
                "The exercise catalog seed version is unsupported."
            )
        }
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
                            catalogKey: set.catalogKey,
                            limits: limits
                        )
                    }
                }
            }
        }
    }

    /// Returns the canonical cross-client workout projection used both by cloud conflict
    /// comparison and authoritative restore. Validation deliberately happens after raw wire
    /// exercise names/keys are canonicalized, but before redundant nested profiles are removed.
    static func canonicalCloudWorkoutIdentityInput(_ backup: GymBackup) throws -> GymBackup {
        var canonical = backup
        canonical.exercises = try backup.exercises
            .map { try canonicalBackupExercise($0) }
            .sorted(by: BackupExercisePortableWireOrder.precedes)
        try validateUniqueBackupExerciseIdentities(canonical.exercises)
        let catalogByIdentity = Dictionary(uniqueKeysWithValues: canonical.exercises.map {
            (
                backupExerciseIdentity(name: $0.name, catalogKey: $0.catalogKey),
                $0
            )
        })
        canonical.sessions = try backup.sessions.enumerated().map { index, session in
            var canonicalSession = session
            canonicalSession.date = session.date ?? session.startedAt
            canonicalSession.startedAt = nil
            let note = session.note?.gymTrimmed
            canonicalSession.note = note?.isEmpty == false ? note : nil
            if let blocks = session.exercises {
                canonicalSession.exercises = try blocks.map {
                    try canonicalBackupWorkoutExercise($0)
                }
            } else if let flatSets = session.sets {
                var identityOrder: [String] = []
                var setsByIdentity: [String: [BackupSet]] = [:]
                for flatSet in flatSets {
                    let rawName = (flatSet.exerciseName?.gymTrimmed.isEmpty == false
                        ? flatSet.exerciseName
                        : flatSet.name) ?? ""
                    let flatWire = try canonicalBackupExerciseWire(
                        name: rawName,
                        catalogKey: flatSet.catalogKey
                    )
                    let identity = backupExerciseIdentity(
                        name: flatWire.name,
                        catalogKey: flatWire.catalogKey
                    )
                    guard catalogByIdentity[identity] != nil else {
                        throw WorkoutStoreError.malformedBackup(
                            "A legacy workout exercise is missing from the canonical catalog."
                        )
                    }
                    if setsByIdentity[identity] == nil { identityOrder.append(identity) }
                    setsByIdentity[identity, default: []].append(
                        BackupSet(
                            weight: flatSet.weight == 0 ? 0.0 : flatSet.weight,
                            reps: flatSet.reps
                        )
                    )
                }
                canonicalSession.exercises = identityOrder.compactMap { identity in
                    guard let exercise = catalogByIdentity[identity],
                          let sets = setsByIdentity[identity],
                          !sets.isEmpty else { return nil }
                    return BackupWorkoutExercise(
                        name: exercise.name,
                        catalogKey: exercise.catalogKey,
                        sets: sets
                    )
                }
            }
            // Native blocks are authoritative when both compatibility shapes are present;
            // legacy flat-only rows have now been converted without dropping any set.
            canonicalSession.sets = nil
            return (index: index, session: canonicalSession)
        }.sorted { lhs, rhs in
            let leftTimestamp = lhs.session.date ?? Int64.min
            let rightTimestamp = rhs.session.date ?? Int64.min
            if leftTimestamp != rightTimestamp { return leftTimestamp < rightTimestamp }
            return lhs.index < rhs.index
        }.map(\.session)

        try validateNestedExerciseLoadProfiles(canonical)

        canonical.sessions = canonical.sessions.map { session in
            var canonicalSession = session
            canonicalSession.exercises = session.exercises?.map { block in
                var canonicalBlock = block
                // A matching nested profile is compatibility-only duplication. The catalog is
                // authoritative, so absence and a matching redundant copy have one identity.
                canonicalBlock.machineLoadProfile = nil
                return canonicalBlock
            }
            return canonicalSession
        }
        return canonical
    }

    private static func validateLosslessAuthoritativeRestore(
        original: GymBackup,
        canonical: GymBackup,
        limits: BackupImportLimits
    ) throws {
        guard original.sessions.count == canonical.sessions.count else {
            throw WorkoutStoreError.malformedBackup("The workout session list is inconsistent.")
        }

        var catalogWires: [String: (name: String, catalogKey: String?)] = [:]
        for exercise in canonical.exercises {
            let identity = backupExerciseIdentity(
                name: exercise.name,
                catalogKey: exercise.catalogKey
            )
            guard catalogWires[identity] == nil else {
                throw WorkoutStoreError.malformedBackup(
                    "The exercise catalog contains a duplicate canonical identity."
                )
            }
            catalogWires[identity] = (exercise.name, exercise.catalogKey)
        }

        for (originalSession, session) in zip(original.sessions, canonical.sessions) {
            guard let timestamp = session.date,
                  (try? validatedTimestamp(timestamp, field: "session timestamp")) != nil else {
                throw WorkoutStoreError.malformedBackup("A workout timestamp is required.")
            }
            if let date = originalSession.date,
               let startedAt = originalSession.startedAt,
               date != startedAt {
                throw WorkoutStoreError.malformedBackup(
                    "A workout contains conflicting timestamps."
                )
            }
            if let originalBlocks = originalSession.exercises,
               let originalFlatSets = originalSession.sets {
                let nativeRows = try authoritativeRows(
                    blocks: originalBlocks,
                    limits: limits
                )
                let flatRows = try authoritativeRows(
                    flatSets: originalFlatSets,
                    limits: limits
                )
                guard nativeRows == flatRows else {
                    throw WorkoutStoreError.malformedBackup(
                        "A workout contains conflicting native and legacy sets."
                    )
                }
            }

            if let blocks = session.exercises {
                guard !blocks.isEmpty else {
                    throw WorkoutStoreError.malformedBackup("A workout has no exercises.")
                }
                for block in blocks {
                    guard !block.sets.isEmpty else {
                        throw WorkoutStoreError.malformedBackup(
                            "A workout exercise has no valid sets."
                        )
                    }
                    let identity = backupExerciseIdentity(
                        name: block.name,
                        catalogKey: block.catalogKey
                    )
                    guard let catalogWire = catalogWires[identity],
                          wireStringsEqual(catalogWire.name, block.name),
                          optionalWireStringsEqual(catalogWire.catalogKey, block.catalogKey) else {
                        throw WorkoutStoreError.malformedBackup(
                            "A workout exercise is missing from the canonical catalog."
                        )
                    }
                    for set in block.sets {
                        guard set.weight.isFinite,
                              (0 ... maximumWeight).contains(set.weight),
                              (1 ... maximumReps).contains(set.reps) else {
                            throw WorkoutStoreError.malformedBackup(
                                "A workout set is outside the supported range."
                            )
                        }
                    }
                }
            } else if let flatSets = session.sets {
                guard !flatSets.isEmpty else {
                    throw WorkoutStoreError.malformedBackup("A workout has no valid sets.")
                }
                _ = try authoritativeRows(flatSets: flatSets, limits: limits)
            } else {
                throw WorkoutStoreError.malformedBackup("A workout has no exercises.")
            }
        }
    }

    private static func authoritativeRows(
        blocks: [BackupWorkoutExercise],
        limits: BackupImportLimits
    ) throws -> [AuthoritativeBackupSetRow] {
        var rows: [AuthoritativeBackupSetRow] = []
        for block in blocks {
            guard !block.sets.isEmpty,
                  block.sets.count <= limits.maximumSetsPerExercise else {
                throw WorkoutStoreError.malformedBackup(
                    "A workout exercise has no valid bounded sets."
                )
            }
            let wire = try canonicalBackupExerciseWire(
                name: block.name,
                catalogKey: block.catalogKey
            )
            let identity = backupExerciseIdentity(
                name: wire.name,
                catalogKey: wire.catalogKey
            )
            for set in block.sets {
                guard set.weight.isFinite,
                      (0 ... maximumWeight).contains(set.weight),
                      (1 ... maximumReps).contains(set.reps) else {
                    throw WorkoutStoreError.malformedBackup(
                        "A workout set is outside the supported range."
                    )
                }
                rows.append(AuthoritativeBackupSetRow(
                    exerciseIdentity: identity,
                    weight: set.weight == 0 ? 0.0 : set.weight,
                    reps: set.reps
                ))
            }
        }
        return rows
    }

    private static func authoritativeRows(
        flatSets: [LegacyBackupSet],
        limits: BackupImportLimits
    ) throws -> [AuthoritativeBackupSetRow] {
        guard flatSets.count <= limits.maximumTotalSets else {
            throw WorkoutStoreError.importLimitExceeded("total set count")
        }
        return try flatSets.map { set in
            let rawName = (set.exerciseName?.gymTrimmed.isEmpty == false
                ? set.exerciseName
                : set.name) ?? ""
            let wire = try canonicalBackupExerciseWire(
                name: rawName,
                catalogKey: set.catalogKey
            )
            guard set.weight.isFinite,
                  (0 ... maximumWeight).contains(set.weight),
                  (1 ... maximumReps).contains(set.reps) else {
                throw WorkoutStoreError.malformedBackup(
                    "A legacy workout set is outside the supported range."
                )
            }
            return AuthoritativeBackupSetRow(
                exerciseIdentity: backupExerciseIdentity(
                    name: wire.name,
                    catalogKey: wire.catalogKey
                ),
                weight: set.weight == 0 ? 0.0 : set.weight,
                reps: set.reps
            )
        }
    }

    private static func canonicalBackupExercise(_ exercise: BackupExercise) throws -> BackupExercise {
        var canonical = exercise
        let wire = try canonicalBackupExerciseWire(
            name: exercise.name,
            catalogKey: exercise.catalogKey
        )
        canonical.name = wire.name
        canonical.catalogKey = wire.catalogKey
        return canonical
    }

    private static func canonicalBackupWorkoutExercise(
        _ exercise: BackupWorkoutExercise
    ) throws -> BackupWorkoutExercise {
        var canonical = exercise
        let wire = try canonicalBackupExerciseWire(
            name: exercise.name,
            catalogKey: exercise.catalogKey
        )
        canonical.name = wire.name
        canonical.catalogKey = wire.catalogKey
        canonical.sets = exercise.sets.map { set in
            var canonicalSet = set
            canonicalSet.weight = set.weight == 0 ? 0.0 : set.weight
            return canonicalSet
        }
        return canonical
    }

    private static func canonicalBackupExerciseWire(
        name rawName: String,
        catalogKey rawCatalogKey: String?
    ) throws -> (name: String, catalogKey: String?) {
        let name = rawName.gymTrimmed
        guard !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw WorkoutStoreError.malformedBackup("An exercise name contains unsupported characters.")
        }
        let trimmedKey = rawCatalogKey?.gymTrimmed
        let key = trimmedKey?.isEmpty == false ? trimmedKey : nil
        let resolvedKey = BuiltInExerciseCatalog.resolvedKey(catalogKey: key, name: name)
        if !name.isEmpty {
            return (name, resolvedKey)
        }
        guard let resolvedKey,
              let definition = BuiltInExerciseCatalog.definition(forKey: resolvedKey) else {
            throw WorkoutStoreError.malformedBackup("An exercise name is required.")
        }
        // Recover the legacy key-only shape exactly as Android does instead of silently
        // dropping its workout blocks during restore.
        return (definition.englishName, resolvedKey)
    }

    private static func validateUniqueBackupExerciseIdentities(
        _ exercises: [BackupExercise]
    ) throws {
        var identities = Set<String>()
        for exercise in exercises {
            let identity = backupExerciseIdentity(
                name: exercise.name,
                catalogKey: exercise.catalogKey
            )
            guard identities.insert(identity).inserted else {
                throw WorkoutStoreError.malformedBackup(
                    "The exercise catalog contains a duplicate canonical identity."
                )
            }
        }
    }

    private static func validateNestedExerciseLoadProfiles(_ backup: GymBackup) throws {
        let catalogProfiles = Dictionary(uniqueKeysWithValues: backup.exercises.map { exercise in
            (
                backupExerciseIdentity(name: exercise.name, catalogKey: exercise.catalogKey),
                exercise.machineLoadProfile
            )
        })
        for session in backup.sessions {
            for block in session.exercises ?? [] {
                guard let nestedProfile = block.machineLoadProfile else { continue }
                let identity = backupExerciseIdentity(name: block.name, catalogKey: block.catalogKey)
                guard catalogProfiles.keys.contains(identity),
                      catalogProfiles[identity] == nestedProfile else {
                    throw WorkoutStoreError.malformedBackup(
                        "A workout exercise load profile does not match the exercise catalog."
                    )
                }
            }
        }
    }

    private static func backupExerciseIdentity(name: String, catalogKey: String?) -> String {
        if let resolvedCatalogKey = BuiltInExerciseCatalog.resolvedKey(
            catalogKey: catalogKey,
            name: name
        ) {
            return "catalog:\(resolvedCatalogKey)"
        }
        return "name:\(MuscleMappingEngine.normalizeExerciseName(name))"
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

    private static func validateActiveWorkoutCommit(
        _ intent: ActiveWorkoutCommitIntent
    ) throws {
        let limits = BackupImportLimits.standard
        _ = try validatedTimestamp(intent.workoutDate, field: "session timestamp")
        _ = try validatedTimestamp(intent.preparedAt, field: "completion timestamp")
        guard try validatedNote(intent.note) == intent.note,
              !intent.exercises.isEmpty,
              intent.exercises.count <= limits.maximumExercisesPerSession,
              Set(intent.exercises.map(\.id)).count == intent.exercises.count else {
            throw WorkoutStoreError.invalidWorkout("Invalid active workout completion intent.")
        }

        var setIDs = Set<UUID>()
        var totalSets = 0
        for committedExercise in intent.exercises {
            let cleanedName = try validatedExerciseName(committedExercise.exerciseName)
            guard cleanedName == committedExercise.exerciseName,
                  !committedExercise.sets.isEmpty,
                  committedExercise.sets.count <= limits.maximumSetsPerExercise else {
                throw WorkoutStoreError.invalidWorkout("Invalid active workout exercise snapshot.")
            }
            if let catalogKey = committedExercise.exerciseCatalogKey {
                guard catalogKey == catalogKey.gymTrimmed,
                      utf8Length(of: catalogKey, isAtMost: maximumCatalogKeyBytes),
                      let definition = BuiltInExerciseCatalog.definition(forKey: catalogKey),
                      BuiltInExerciseCatalog.canonicalKey(forName: cleanedName) == definition.key else {
                    throw WorkoutStoreError.invalidWorkout("Invalid active workout catalog identity.")
                }
            }
            totalSets += committedExercise.sets.count
            guard totalSets <= limits.maximumTotalSets else {
                throw WorkoutStoreError.importLimitExceeded("set count")
            }
            for set in committedExercise.sets {
                guard setIDs.insert(set.id).inserted else {
                    throw WorkoutStoreError.invalidWorkout("Duplicate active workout set identifier.")
                }
                try validate(weight: set.weight, reps: set.reps)
            }
        }
    }

    private static func resolveOrRestoreExercise(
        for committedExercise: ActiveWorkoutCommitExercise,
        in state: inout WorkoutDataSnapshot
    ) throws -> UUID {
        if let preferred = state.exercises.first(where: {
            $0.id == committedExercise.preferredExerciseID
        }), activeExercise(preferred, matches: committedExercise) {
            return preferred.id
        }

        let matchingExercises = state.exercises.filter {
            activeExercise($0, matches: committedExercise)
        }
        guard matchingExercises.count <= 1 else {
            throw WorkoutStoreError.invalidWorkout(
                "The active workout exercise identity is ambiguous."
            )
        }
        if let matchingExercise = matchingExercises.first {
            return matchingExercise.id
        }
        guard !state.exercises.contains(where: {
            $0.id == committedExercise.preferredExerciseID
        }) else {
            throw WorkoutStoreError.invalidWorkout(
                "The active workout exercise identifier is already in use."
            )
        }
        guard state.exercises.count < BackupImportLimits.standard.maximumExercises else {
            throw WorkoutStoreError.importLimitExceeded("exercise count")
        }
        guard !state.exercises.contains(where: {
            exerciseIdentityConflicts($0, candidateName: committedExercise.exerciseName)
        }) else {
            throw WorkoutStoreError.duplicateExerciseName
        }

        let restored = Exercise(
            id: committedExercise.preferredExerciseID,
            name: committedExercise.exerciseName,
            catalogKey: committedExercise.exerciseCatalogKey
        )
        guard activeExercise(restored, matches: committedExercise) else {
            throw WorkoutStoreError.invalidWorkout(
                "The active workout exercise snapshot could not be restored."
            )
        }
        state.exercises.append(restored)
        return restored.id
    }

    private static func activeExercise(
        _ exercise: Exercise,
        matches committedExercise: ActiveWorkoutCommitExercise
    ) -> Bool {
        if let expectedKey = BuiltInExerciseCatalog.canonicalKey(
            forName: committedExercise.exerciseName
        ) {
            return BuiltInExerciseCatalog.resolvedKey(
                catalogKey: exercise.catalogKey,
                name: exercise.name
            ) == expectedKey
        }
        return namesEqual(exercise.name, committedExercise.exerciseName)
    }

    private static func workout(
        _ workout: WorkoutSession,
        matches intent: ActiveWorkoutCommitIntent,
        exercises: [Exercise]
    ) -> Bool {
        guard workout.id == intent.workoutID,
              workout.date == intent.workoutDate,
              workout.note == intent.note,
              workout.exercises.count == intent.exercises.count else {
            return false
        }
        let committedByBlockID = Dictionary(
            uniqueKeysWithValues: intent.exercises.map { ($0.id, $0) }
        )
        for block in workout.exercises {
            guard let committedExercise = committedByBlockID[block.id],
                  block.sets == committedExercise.sets,
                  let storedExercise = exercises.first(where: {
                      $0.id == block.exerciseID
                  }),
                  activeExercise(storedExercise, matches: committedExercise) else {
                return false
            }
        }
        return true
    }

    private static func nameKey(_ value: String) -> String {
        MuscleMappingEngine.normalizeExerciseName(value)
    }

    private static func legacyPersistedNameKey(_ value: String) -> String {
        value.gymTrimmed.lowercased()
    }

    private static func resolvedStoredExerciseID(
        for name: String,
        in exercises: [Exercise]
    ) throws -> UUID? {
        let legacyKey = legacyPersistedNameKey(name)
        if let exactLegacyMatch = exercises.first(where: {
            legacyPersistedNameKey($0.name) == legacyKey
        }) {
            return exactLegacyMatch.id
        }

        let portableKey = nameKey(name)
        let portableMatches = exercises.filter { nameKey($0.name) == portableKey }
        guard portableMatches.count <= 1 else {
            // A pre-portable store may legitimately contain multiple names that collapse to
            // one cross-client identity. Guessing would attach history to the wrong exercise.
            throw WorkoutStoreError.duplicateExerciseName
        }
        return portableMatches.first?.id
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
