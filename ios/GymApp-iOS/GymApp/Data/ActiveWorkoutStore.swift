import Combine
import Foundation

enum ActiveWorkoutStoreError: Error, LocalizedError, Equatable, Sendable {
    case storageUnavailable
    case alreadyActive
    case noActiveWorkout
    case staleDraft
    case accountMismatch
    case exerciseUnavailable
    case setUnavailable
    case setAlreadyCompleted
    case setIsNotLatest
    case noCompletedSets
    case workoutFinishing
    case invalidDraft
    case invalidWeight
    case invalidReps
    case limitExceeded

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "Active workout progress could not be saved."
        case .alreadyActive:
            "Finish or discard the active workout before starting another one."
        case .noActiveWorkout:
            "There is no active workout to continue."
        case .staleDraft:
            "The active workout changed. Review it and try again."
        case .accountMismatch:
            "This active workout belongs to another account."
        case .exerciseUnavailable:
            "An exercise in this workout is no longer available."
        case .setUnavailable:
            "This set is no longer available."
        case .setAlreadyCompleted:
            "This set has already been recorded."
        case .setIsNotLatest:
            "Only the latest recorded set can be undone."
        case .noCompletedSets:
            "Record at least one set before finishing the workout."
        case .workoutFinishing:
            "This workout is already finishing. Retry completion instead of changing it."
        case .invalidDraft:
            "The active workout contains invalid data."
        case .invalidWeight:
            "Weight must be a finite non-negative number."
        case .invalidReps:
            "Repetitions must be between 1 and 10,000."
        case .limitExceeded:
            "The active workout is too large."
        }
    }
}

struct ActiveWorkoutSetInput: Equatable, Sendable {
    let weight: Double
    let reps: Int
}

/// One crash-safe, account-scoped active workout. It lives beside, but never inside,
/// the shared `WorkoutStore` envelope so older clients and cloud backups ignore it.
@MainActor
final class ActiveWorkoutStore: ObservableObject {
    @Published private(set) var draft: ActiveWorkoutDraft?
    @Published private(set) var recoveryMessage: String?

    let accountStorageKey: String
    let storageURL: URL

    private let fileManager: FileManager
    private let envelopeWriter: (Data, URL) throws -> Void
    private var writesBlocked = false

    private static let schemaVersion = 1
    private static let maximumFileBytes = 8 * 1_024 * 1_024
    private static let maximumAccountStorageKeyCharacters = 128
    private static let maximumAccountStorageKeyBytes = 512
    private static let maximumExercises = 100
    private static let maximumSetsPerExercise = 100
    private static let maximumTotalSets = 10_000
    private static let maximumNoteCharacters = 4_000
    private static let maximumNoteBytes = 16_000
    private static let maximumExerciseNameCharacters = 160
    private static let maximumExerciseNameBytes = 640
    private static let maximumCatalogKeyBytes = 256
    private static let maximumJSONNestingDepth = 16
    private static let maximumJSONContainers = 25_000
    private static let maximumWeight = 1_000_000.0
    private static let maximumReps = 10_000
    private static let maximumRestSeconds = 30 * 60
    private static let minimumSupportedTimestampMilliseconds: Int64 = -62_135_769_600_000
    private static let maximumSupportedTimestampMilliseconds: Int64 = 64_092_211_200_000

    private struct Envelope: Codable {
        let schemaVersion: Int
        let accountStorageKey: String
        let savedAt: Date
        let draft: ActiveWorkoutDraft?
    }

    init(
        accountStorageKey: String,
        workoutStorageURL: URL,
        fileManager: FileManager = .default,
        envelopeWriter: ((Data, URL) throws -> Void)? = nil
    ) {
        self.accountStorageKey = accountStorageKey
        self.storageURL = Self.storageURL(forWorkoutStorageURL: workoutStorageURL)
        self.fileManager = fileManager
        self.envelopeWriter = envelopeWriter ?? Self.writeEnvelopeAtomically
        self.draft = nil

        do {
            try Self.validateAccountStorageKey(accountStorageKey)
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.excludeFromBackup(storageURL.deletingLastPathComponent())
            draft = try Self.load(
                accountStorageKey: accountStorageKey,
                storageURL: storageURL,
                fileManager: fileManager
            )
        } catch {
            recoverUnreadableFile()
        }
    }

    static func storageURL(forWorkoutStorageURL workoutStorageURL: URL) -> URL {
        workoutStorageURL
            .deletingPathExtension()
            .appendingPathExtension("active-workout.json")
    }

    @discardableResult
    func start(
        workoutDate: Date,
        note: String?,
        exercises: [ActiveWorkoutExercise],
        workoutStore: WorkoutStore,
        now: Date = Date()
    ) throws -> ActiveWorkoutDraft {
        guard !writesBlocked else { throw ActiveWorkoutStoreError.storageUnavailable }
        guard draft == nil else { throw ActiveWorkoutStoreError.alreadyActive }
        guard workoutStore.accountStorageKey == accountStorageKey else {
            throw ActiveWorkoutStoreError.accountMismatch
        }
        let knownExercises = workoutStore.exercises
        guard Set(knownExercises.map(\.id)).count == knownExercises.count else {
            throw ActiveWorkoutStoreError.invalidDraft
        }
        let knownByID = Dictionary(uniqueKeysWithValues: knownExercises.map { ($0.id, $0) })
        let boundExercises = try exercises.map { exercise -> ActiveWorkoutExercise in
            guard let storedExercise = knownByID[exercise.exerciseID] else {
                throw ActiveWorkoutStoreError.exerciseUnavailable
            }
            return ActiveWorkoutExercise(
                id: exercise.id,
                exerciseID: storedExercise.id,
                exerciseName: storedExercise.name,
                exerciseCatalogKey: storedExercise.catalogKey,
                sets: exercise.sets
            )
        }
        guard Self.isSupportedTimestamp(now),
              Self.isSupportedTimestamp(workoutDate),
              workoutDate <= now.addingTimeInterval(5 * 60) else {
            throw ActiveWorkoutStoreError.invalidDraft
        }

        let candidate = ActiveWorkoutDraft(
            startedAt: now,
            workoutDate: workoutDate,
            note: Self.normalizedNote(note),
            exercises: boundExercises,
            revision: 0,
            lastModifiedAt: now,
            timing: ActiveWorkoutTimingState(activeSince: now)
        )
        try commit(candidate)
        recoveryMessage = nil
        return candidate
    }

    /// Restores an active live workout from the authenticated server snapshot. The
    /// caller supplies server-canonical completion values and timestamps; this method
    /// binds only the local exercise UUIDs and commits the whole recovered draft once.
    @discardableResult
    func startRecoveredLiveWorkout(
        startedAt: Date,
        exercises: [ActiveWorkoutExercise],
        undoableSetID: UUID?,
        workoutStore: WorkoutStore,
        now: Date = Date(),
        persistBindingBeforeCommit: (ActiveWorkoutDraft) throws -> Void = { _ in }
    ) throws -> ActiveWorkoutDraft {
        guard !writesBlocked else { throw ActiveWorkoutStoreError.storageUnavailable }
        guard draft == nil else { throw ActiveWorkoutStoreError.alreadyActive }
        guard workoutStore.accountStorageKey == accountStorageKey else {
            throw ActiveWorkoutStoreError.accountMismatch
        }
        let knownExercises = workoutStore.exercises
        guard Set(knownExercises.map(\.id)).count == knownExercises.count else {
            throw ActiveWorkoutStoreError.invalidDraft
        }
        let knownByID = Dictionary(uniqueKeysWithValues: knownExercises.map { ($0.id, $0) })
        let boundExercises = try exercises.map { exercise -> ActiveWorkoutExercise in
            guard let storedExercise = knownByID[exercise.exerciseID] else {
                throw ActiveWorkoutStoreError.exerciseUnavailable
            }
            return ActiveWorkoutExercise(
                id: exercise.id,
                exerciseID: storedExercise.id,
                exerciseName: storedExercise.name,
                exerciseCatalogKey: storedExercise.catalogKey,
                sets: exercise.sets
            )
        }
        let completedDates = boundExercises.flatMap { exercise in
            exercise.sets.compactMap(\.completedAt)
        }
        guard Self.isSupportedTimestamp(startedAt), Self.isSupportedTimestamp(now),
              completedDates.allSatisfy({
                  Self.isSupportedTimestamp($0) && $0 >= startedAt
              }) else {
            throw ActiveWorkoutStoreError.invalidDraft
        }
        let lastModifiedAt = completedDates.reduce(max(now, startedAt), max)
        let candidate = ActiveWorkoutDraft(
            startedAt: startedAt,
            workoutDate: startedAt,
            note: nil,
            exercises: boundExercises,
            undoableSetID: undoableSetID,
            revision: 0,
            lastModifiedAt: lastModifiedAt,
            timing: ActiveWorkoutTimingState(activeSince: startedAt)
        )
        try Self.validate(candidate)
        try persistBindingBeforeCommit(candidate)
        try commit(candidate)
        recoveryMessage = nil
        return candidate
    }

    @discardableResult
    func updateSet(
        draftID: UUID,
        setID: UUID,
        weight: Double,
        reps: Int,
        expectedRevision: UInt64,
        now: Date = Date()
    ) throws -> ActiveWorkoutDraft {
        try mutate(
            draftID: draftID,
            expectedRevision: expectedRevision,
            now: now
        ) { candidate in
            let location = try Self.setLocation(setID: setID, in: candidate)
            guard candidate.exercises[location.exercise].sets[location.set].completedAt == nil else {
                throw ActiveWorkoutStoreError.setAlreadyCompleted
            }
            try Self.validate(weight: weight, reps: reps)
            candidate.exercises[location.exercise].sets[location.set].weight = weight == 0 ? 0.0 : weight
            candidate.exercises[location.exercise].sets[location.set].reps = reps
        }
    }

    @discardableResult
    func recordSet(
        draftID: UUID,
        setID: UUID,
        expectedRevision: UInt64,
        restSeconds: Int? = nil,
        now: Date = Date()
    ) throws -> ActiveWorkoutDraft {
        try mutate(
            draftID: draftID,
            expectedRevision: expectedRevision,
            now: now
        ) { candidate in
            let location = try Self.setLocation(setID: setID, in: candidate)
            let set = candidate.exercises[location.exercise].sets[location.set]
            guard set.completedAt == nil else {
                throw ActiveWorkoutStoreError.setAlreadyCompleted
            }
            try Self.validate(weight: set.weight, reps: set.reps)
            candidate.exercises[location.exercise].sets[location.set].completedAt = now
            candidate.undoableSetID = setID
            if let restSeconds {
                try Self.pauseTiming(
                    in: &candidate,
                    at: now,
                    restSeconds: restSeconds
                )
            }
        }
    }

    /// Validates the complete unfinished input set before changing any row, then writes
    /// one new draft revision. A missing, extra, malformed, or stale input leaves the
    /// current draft byte-for-byte unchanged.
    @discardableResult
    func recordAllSets(
        draftID: UUID,
        expectedRevision: UInt64,
        inputs: [UUID: ActiveWorkoutSetInput],
        now: Date = Date()
    ) throws -> ActiveWorkoutDraft {
        try mutate(
            draftID: draftID,
            expectedRevision: expectedRevision,
            now: now
        ) { candidate in
            let unfinishedLocations = candidate.exercises.indices.flatMap { exerciseIndex in
                candidate.exercises[exerciseIndex].sets.indices.compactMap { setIndex in
                    candidate.exercises[exerciseIndex].sets[setIndex].isCompleted
                        ? nil
                        : (exercise: exerciseIndex, set: setIndex)
                }
            }
            guard !unfinishedLocations.isEmpty else {
                throw ActiveWorkoutStoreError.setAlreadyCompleted
            }
            let unfinishedIDs = Set(unfinishedLocations.map {
                candidate.exercises[$0.exercise].sets[$0.set].id
            })
            guard unfinishedIDs.count == unfinishedLocations.count,
                  Set(inputs.keys) == unfinishedIDs else {
                throw ActiveWorkoutStoreError.invalidDraft
            }

            // Do not mutate the candidate until every row has passed validation.
            for location in unfinishedLocations {
                let setID = candidate.exercises[location.exercise].sets[location.set].id
                guard let input = inputs[setID] else {
                    throw ActiveWorkoutStoreError.invalidDraft
                }
                try Self.validate(weight: input.weight, reps: input.reps)
            }

            for location in unfinishedLocations {
                let setID = candidate.exercises[location.exercise].sets[location.set].id
                guard let input = inputs[setID] else {
                    throw ActiveWorkoutStoreError.invalidDraft
                }
                candidate.exercises[location.exercise].sets[location.set].weight =
                    input.weight == 0 ? 0.0 : input.weight
                candidate.exercises[location.exercise].sets[location.set].reps = input.reps
                candidate.exercises[location.exercise].sets[location.set].completedAt = now
            }
            candidate.undoableSetID = nil
            var timing = Self.normalizedTiming(in: candidate, at: now)
            if timing.restingUntil != nil {
                timing.restingUntil = nil
                timing.activeSince = now
            }
            candidate.timing = timing
        }
    }

    @discardableResult
    func beginRest(
        draftID: UUID,
        expectedRevision: UInt64,
        seconds: Int,
        now: Date = Date()
    ) throws -> ActiveWorkoutDraft {
        try mutate(
            draftID: draftID,
            expectedRevision: expectedRevision,
            now: now
        ) { candidate in
            try Self.pauseTiming(in: &candidate, at: now, restSeconds: seconds)
        }
    }

    @discardableResult
    func adjustRest(
        draftID: UUID,
        expectedRevision: UInt64,
        remainingSeconds: Int,
        now: Date = Date()
    ) throws -> ActiveWorkoutDraft {
        try mutate(
            draftID: draftID,
            expectedRevision: expectedRevision,
            now: now
        ) { candidate in
            guard (1 ... Self.maximumRestSeconds).contains(remainingSeconds) else {
                throw ActiveWorkoutStoreError.invalidDraft
            }
            var timing = Self.normalizedTiming(in: candidate, at: now)
            guard timing.restingUntil != nil else {
                throw ActiveWorkoutStoreError.invalidDraft
            }
            timing.restingUntil = now.addingTimeInterval(TimeInterval(remainingSeconds))
            candidate.timing = timing
        }
    }

    @discardableResult
    func endRest(
        draftID: UUID,
        expectedRevision: UInt64,
        now: Date = Date()
    ) throws -> ActiveWorkoutDraft {
        try mutate(
            draftID: draftID,
            expectedRevision: expectedRevision,
            now: now
        ) { candidate in
            var timing = Self.normalizedTiming(in: candidate, at: now)
            if timing.restingUntil != nil {
                timing.restingUntil = nil
                timing.activeSince = now
            }
            candidate.timing = timing
        }
    }

    /// Only the most recently persisted completion can move back to editable state. This
    /// keeps earlier history immutable and makes a retry deterministic after a stale view.
    @discardableResult
    func undoLatestRecordedSet(
        draftID: UUID,
        setID: UUID,
        expectedRevision: UInt64,
        now: Date = Date()
    ) throws -> ActiveWorkoutDraft {
        try mutate(
            draftID: draftID,
            expectedRevision: expectedRevision,
            now: now
        ) { candidate in
            guard candidate.undoableSetID == setID else {
                throw ActiveWorkoutStoreError.setIsNotLatest
            }
            let location = try Self.setLocation(setID: setID, in: candidate)
            guard candidate.exercises[location.exercise].sets[location.set].completedAt != nil else {
                throw ActiveWorkoutStoreError.invalidDraft
            }
            candidate.exercises[location.exercise].sets[location.set].completedAt = nil
            candidate.undoableSetID = nil
            var timing = Self.normalizedTiming(in: candidate, at: now)
            if timing.restingUntil != nil {
                timing.restingUntil = nil
                timing.activeSince = now
            }
            candidate.timing = timing
        }
    }

    @discardableResult
    func appendSet(
        draftID: UUID,
        exerciseBlockID: UUID,
        weight: Double,
        reps: Int,
        expectedRevision: UInt64,
        now: Date = Date()
    ) throws -> ActiveWorkoutDraft {
        try mutate(
            draftID: draftID,
            expectedRevision: expectedRevision,
            now: now
        ) { candidate in
            guard let exerciseIndex = candidate.exercises.firstIndex(where: {
                $0.id == exerciseBlockID
            }) else {
                throw ActiveWorkoutStoreError.exerciseUnavailable
            }
            guard candidate.exercises[exerciseIndex].sets.count < Self.maximumSetsPerExercise,
                  candidate.plannedSetCount < Self.maximumTotalSets else {
                throw ActiveWorkoutStoreError.limitExceeded
            }
            try Self.validate(weight: weight, reps: reps)
            candidate.exercises[exerciseIndex].sets.append(
                ActiveWorkoutSet(weight: weight, reps: reps)
            )
        }
    }

    /// Cloud restore intentionally recreates local exercise UUIDs because UUIDs are not
    /// part of the shared contract. Rebind only by the local stable catalog/name identity,
    /// and persist that mapping before the draft is presented again.
    func rebindExercises(to workoutStore: WorkoutStore, now: Date = Date()) throws {
        guard workoutStore.accountStorageKey == accountStorageKey else {
            throw ActiveWorkoutStoreError.accountMismatch
        }
        guard let current = draft, current.commitIntent == nil else { return }
        let replacements = Dictionary(uniqueKeysWithValues: current.exercises.compactMap {
            exercise -> (UUID, UUID)? in
            guard let resolvedID = Self.resolvedExerciseID(
                for: exercise,
                in: workoutStore.exercises
            ), resolvedID != exercise.exerciseID else { return nil }
            return (exercise.id, resolvedID)
        })
        guard !replacements.isEmpty else { return }

        _ = try mutate(
            draftID: current.id,
            expectedRevision: current.revision,
            now: max(now, current.lastModifiedAt)
        ) { candidate in
            for index in candidate.exercises.indices {
                if let replacement = replacements[candidate.exercises[index].id] {
                    candidate.exercises[index].exerciseID = replacement
                }
            }
        }
    }

    /// Persists an immutable completion intent before touching history. Every later retry
    /// either commits that exact intent or confirms its existing history row, then clears
    /// the companion file. No editable state exists between those transitions.
    @discardableResult
    func finish(
        draftID: UUID,
        expectedRevision: UInt64,
        into workoutStore: WorkoutStore,
        now: Date = Date()
    ) throws -> WorkoutSession {
        guard !writesBlocked else { throw ActiveWorkoutStoreError.storageUnavailable }
        guard workoutStore.accountStorageKey == accountStorageKey else {
            throw ActiveWorkoutStoreError.accountMismatch
        }
        let current = try currentDraft(
            draftID: draftID,
            expectedRevision: expectedRevision
        )
        let intent: ActiveWorkoutCommitIntent
        if let lockedIntent = current.commitIntent {
            intent = lockedIntent
        } else {
            let preparedAt = max(now, current.lastModifiedAt)
            let preparedIntent = try Self.makeCommitIntent(
                from: current,
                exercises: workoutStore.exercises,
                preparedAt: preparedAt
            )
            _ = try mutate(
                draftID: current.id,
                expectedRevision: current.revision,
                now: preparedAt,
                allowCommitTransition: true
            ) { candidate in
                guard candidate.commitIntent == nil else {
                    throw ActiveWorkoutStoreError.workoutFinishing
                }
                candidate.commitIntent = preparedIntent
            }
            intent = preparedIntent
        }

        let storedWorkout = try workoutStore.commitActiveWorkout(
            intent,
            expectedAccountStorageKey: accountStorageKey
        )
        try persist(nil)
        draft = nil
        recoveryMessage = nil
        return storedWorkout
    }

    func discard(draftID: UUID, expectedRevision: UInt64) throws {
        guard !writesBlocked else { throw ActiveWorkoutStoreError.storageUnavailable }
        let current = try currentDraft(draftID: draftID, expectedRevision: expectedRevision)
        guard current.commitIntent == nil else {
            throw ActiveWorkoutStoreError.workoutFinishing
        }
        try persist(nil)
        draft = nil
        recoveryMessage = nil
    }

    private func mutate(
        draftID: UUID,
        expectedRevision: UInt64,
        now: Date,
        allowCommitTransition: Bool = false,
        mutation: (inout ActiveWorkoutDraft) throws -> Void
    ) throws -> ActiveWorkoutDraft {
        guard !writesBlocked else { throw ActiveWorkoutStoreError.storageUnavailable }
        var candidate = try currentDraft(
            draftID: draftID,
            expectedRevision: expectedRevision
        )
        guard allowCommitTransition || candidate.commitIntent == nil else {
            throw ActiveWorkoutStoreError.workoutFinishing
        }
        try mutation(&candidate)
        if candidate.timing != nil {
            candidate.timing = Self.normalizedTiming(in: candidate, at: now)
        }
        guard candidate.revision < UInt64.max, Self.isSupportedTimestamp(now) else {
            throw ActiveWorkoutStoreError.invalidDraft
        }
        candidate.revision += 1
        candidate.lastModifiedAt = now
        try commit(candidate)
        return candidate
    }

    private func currentDraft(
        draftID: UUID,
        expectedRevision: UInt64
    ) throws -> ActiveWorkoutDraft {
        guard let draft else { throw ActiveWorkoutStoreError.noActiveWorkout }
        guard draft.id == draftID, draft.revision == expectedRevision else {
            throw ActiveWorkoutStoreError.staleDraft
        }
        return draft
    }

    private func commit(_ candidate: ActiveWorkoutDraft) throws {
        try Self.validate(candidate)
        try persist(candidate)
        draft = candidate
    }

    private func persist(_ candidate: ActiveWorkoutDraft?) throws {
        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            accountStorageKey: accountStorageKey,
            savedAt: Date(),
            draft: candidate
        )
        do {
            let data = try Self.encoder().encode(envelope)
            guard data.count <= Self.maximumFileBytes else {
                throw ActiveWorkoutStoreError.limitExceeded
            }
            try envelopeWriter(data, storageURL)
            try Self.excludeFromBackup(storageURL)
        } catch let error as ActiveWorkoutStoreError {
            throw error
        } catch {
            throw ActiveWorkoutStoreError.storageUnavailable
        }
    }

    private static func load(
        accountStorageKey: String,
        storageURL: URL,
        fileManager: FileManager
    ) throws -> ActiveWorkoutDraft? {
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: storageURL.path)
        guard let byteCount = attributes[.size] as? NSNumber,
              byteCount.intValue <= maximumFileBytes else {
            throw ActiveWorkoutStoreError.limitExceeded
        }
        let data = try Data(contentsOf: storageURL, options: .mappedIfSafe)
        guard !data.isEmpty, data.count <= maximumFileBytes else {
            throw ActiveWorkoutStoreError.invalidDraft
        }
        try validateJSONShape(data)
        let envelope = try decoder().decode(Envelope.self, from: data)
        guard envelope.schemaVersion == schemaVersion else {
            throw ActiveWorkoutStoreError.invalidDraft
        }
        guard envelope.accountStorageKey == accountStorageKey else {
            throw ActiveWorkoutStoreError.accountMismatch
        }
        try validateAccountStorageKey(envelope.accountStorageKey)
        guard isSupportedTimestamp(envelope.savedAt) else {
            throw ActiveWorkoutStoreError.invalidDraft
        }
        if let draft = envelope.draft { try validate(draft) }
        try excludeFromBackup(storageURL)
        return envelope.draft
    }

    private func recoverUnreadableFile() {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            writesBlocked = true
            recoveryMessage = "Active workout storage is unavailable."
            return
        }
        let quarantineURL = storageURL
            .deletingPathExtension()
            .appendingPathExtension("recovery-\(UUID().uuidString.lowercased()).json")
        do {
            try fileManager.moveItem(at: storageURL, to: quarantineURL)
            try Self.excludeFromBackup(quarantineURL)
            recoveryMessage = "Damaged active workout progress was preserved for recovery."
        } catch {
            writesBlocked = true
            recoveryMessage = "Active workout progress could not be opened safely."
        }
    }

    private static func validate(_ candidate: ActiveWorkoutDraft) throws {
        guard isSupportedTimestamp(candidate.startedAt),
              isSupportedTimestamp(candidate.workoutDate),
              isSupportedTimestamp(candidate.lastModifiedAt),
              candidate.lastModifiedAt >= candidate.startedAt,
              candidate.exercises.count >= 1,
              candidate.exercises.count <= maximumExercises else {
            throw ActiveWorkoutStoreError.invalidDraft
        }
        if let note = candidate.note {
            guard note.count <= maximumNoteCharacters,
                  note.utf8.prefix(maximumNoteBytes + 1).count <= maximumNoteBytes else {
                throw ActiveWorkoutStoreError.limitExceeded
            }
        }
        guard Set(candidate.exercises.map(\.id)).count == candidate.exercises.count else {
            throw ActiveWorkoutStoreError.invalidDraft
        }

        var totalSets = 0
        var setIDs = Set<UUID>()
        var completedSetIDs = Set<UUID>()
        for exercise in candidate.exercises {
            if let name = exercise.exerciseName {
                guard !name.gymTrimmed.isEmpty,
                      name.count <= maximumExerciseNameCharacters,
                      name.utf8.prefix(maximumExerciseNameBytes + 1).count <= maximumExerciseNameBytes,
                      !name.unicodeScalars.contains(where: {
                          CharacterSet.controlCharacters.contains($0)
                      }) else {
                    throw ActiveWorkoutStoreError.invalidDraft
                }
            }
            if let catalogKey = exercise.exerciseCatalogKey {
                guard !catalogKey.gymTrimmed.isEmpty,
                      catalogKey.utf8.prefix(maximumCatalogKeyBytes + 1).count <= maximumCatalogKeyBytes else {
                    throw ActiveWorkoutStoreError.invalidDraft
                }
            }
            guard !exercise.sets.isEmpty,
                  exercise.sets.count <= maximumSetsPerExercise else {
                throw ActiveWorkoutStoreError.limitExceeded
            }
            totalSets += exercise.sets.count
            guard totalSets <= maximumTotalSets else {
                throw ActiveWorkoutStoreError.limitExceeded
            }
            for set in exercise.sets {
                guard setIDs.insert(set.id).inserted else {
                    throw ActiveWorkoutStoreError.invalidDraft
                }
                try validate(weight: set.weight, reps: set.reps)
                if let completedAt = set.completedAt {
                    guard isSupportedTimestamp(completedAt),
                          completedAt >= candidate.startedAt,
                          completedAt <= candidate.lastModifiedAt else {
                        throw ActiveWorkoutStoreError.invalidDraft
                    }
                    completedSetIDs.insert(set.id)
                }
            }
        }
        if let undoableSetID = candidate.undoableSetID {
            guard completedSetIDs.contains(undoableSetID) else {
                throw ActiveWorkoutStoreError.invalidDraft
            }
        }
        if let timing = candidate.timing {
            let maximumAccumulated = max(
                0,
                candidate.lastModifiedAt.timeIntervalSince(candidate.startedAt)
            ) + 1
            guard timing.accumulatedActiveSeconds.isFinite,
                  timing.accumulatedActiveSeconds >= 0,
                  timing.accumulatedActiveSeconds <= maximumAccumulated,
                  (timing.activeSince == nil) != (timing.restingUntil == nil) else {
                throw ActiveWorkoutStoreError.invalidDraft
            }
            if let activeSince = timing.activeSince {
                guard isSupportedTimestamp(activeSince),
                      activeSince >= candidate.startedAt,
                      activeSince <= candidate.lastModifiedAt else {
                    throw ActiveWorkoutStoreError.invalidDraft
                }
            }
            if let restingUntil = timing.restingUntil {
                guard isSupportedTimestamp(restingUntil),
                      restingUntil > candidate.lastModifiedAt,
                      restingUntil.timeIntervalSince(candidate.lastModifiedAt) <=
                        TimeInterval(maximumRestSeconds) else {
                    throw ActiveWorkoutStoreError.invalidDraft
                }
            }
        }
        if let intent = candidate.commitIntent {
            try validate(intent, matches: candidate)
        }
    }

    private static func validate(
        _ intent: ActiveWorkoutCommitIntent,
        matches draft: ActiveWorkoutDraft
    ) throws {
        guard intent.workoutID == draft.id,
              intent.workoutDate == draft.workoutDate,
              intent.note == draft.note,
              isSupportedTimestamp(intent.preparedAt),
              intent.preparedAt == draft.lastModifiedAt,
              !intent.exercises.isEmpty,
              intent.exercises.count <= maximumExercises,
              Set(intent.exercises.map(\.id)).count == intent.exercises.count else {
            throw ActiveWorkoutStoreError.invalidDraft
        }
        let completedBlockIDs = Set(draft.exercises.compactMap { exercise in
            exercise.sets.contains(where: \.isCompleted) ? exercise.id : nil
        })
        guard Set(intent.exercises.map(\.id)) == completedBlockIDs else {
            throw ActiveWorkoutStoreError.invalidDraft
        }

        let activeByBlockID = Dictionary(
            uniqueKeysWithValues: draft.exercises.map { ($0.id, $0) }
        )
        for committedExercise in intent.exercises {
            guard let activeExercise = activeByBlockID[committedExercise.id] else {
                throw ActiveWorkoutStoreError.invalidDraft
            }
            let committedName = committedExercise.exerciseName.gymTrimmed
            guard committedName == committedExercise.exerciseName,
                  !committedName.isEmpty,
                  committedName.count <= maximumExerciseNameCharacters,
                  committedName.utf8.prefix(maximumExerciseNameBytes + 1).count <= maximumExerciseNameBytes,
                  !committedName.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0)
                  }) else {
                throw ActiveWorkoutStoreError.invalidDraft
            }
            if let catalogKey = committedExercise.exerciseCatalogKey {
                guard catalogKey == catalogKey.gymTrimmed,
                      catalogKey.utf8.prefix(maximumCatalogKeyBytes + 1).count <= maximumCatalogKeyBytes,
                      let definition = BuiltInExerciseCatalog.definition(forKey: catalogKey),
                      BuiltInExerciseCatalog.canonicalKey(forName: committedName) == definition.key else {
                    throw ActiveWorkoutStoreError.invalidDraft
                }
            }
            guard let activeName = activeExercise.exerciseName else {
                throw ActiveWorkoutStoreError.invalidDraft
            }
            let activeKey = BuiltInExerciseCatalog.resolvedKey(
                catalogKey: activeExercise.exerciseCatalogKey,
                name: activeName
            )
            let committedKey = BuiltInExerciseCatalog.resolvedKey(
                catalogKey: committedExercise.exerciseCatalogKey,
                name: committedName
            )
            if activeKey != nil || committedKey != nil {
                guard activeKey == committedKey else {
                    throw ActiveWorkoutStoreError.invalidDraft
                }
            } else {
                guard MuscleMappingEngine.normalizeExerciseName(activeName) ==
                    MuscleMappingEngine.normalizeExerciseName(committedName) else {
                    throw ActiveWorkoutStoreError.invalidDraft
                }
            }

            let completedSets = activeExercise.sets.compactMap { set -> WorkoutSet? in
                guard set.isCompleted else { return nil }
                return WorkoutSet(id: set.id, weight: set.weight, reps: set.reps)
            }
            guard !completedSets.isEmpty,
                  completedSets == committedExercise.sets,
                  committedExercise.sets.count <= maximumSetsPerExercise else {
                throw ActiveWorkoutStoreError.invalidDraft
            }
            for set in committedExercise.sets {
                try validate(weight: set.weight, reps: set.reps)
            }
        }
    }

    private static func validate(weight: Double, reps: Int) throws {
        guard weight.isFinite, (0 ... maximumWeight).contains(weight) else {
            throw ActiveWorkoutStoreError.invalidWeight
        }
        guard (1 ... maximumReps).contains(reps) else {
            throw ActiveWorkoutStoreError.invalidReps
        }
    }

    private static func setLocation(
        setID: UUID,
        in draft: ActiveWorkoutDraft
    ) throws -> (exercise: Int, set: Int) {
        for exerciseIndex in draft.exercises.indices {
            if let setIndex = draft.exercises[exerciseIndex].sets.firstIndex(where: {
                $0.id == setID
            }) {
                return (exerciseIndex, setIndex)
            }
        }
        throw ActiveWorkoutStoreError.setUnavailable
    }

    private static func normalizedTiming(
        in draft: ActiveWorkoutDraft,
        at now: Date
    ) -> ActiveWorkoutTimingState {
        var timing = draft.timing ?? ActiveWorkoutTimingState(activeSince: draft.startedAt)
        if let restingUntil = timing.restingUntil, now >= restingUntil {
            timing.restingUntil = nil
            timing.activeSince = restingUntil
        }
        return timing
    }

    private static func pauseTiming(
        in draft: inout ActiveWorkoutDraft,
        at now: Date,
        restSeconds: Int
    ) throws {
        guard (1 ... maximumRestSeconds).contains(restSeconds) else {
            throw ActiveWorkoutStoreError.invalidDraft
        }
        var timing = normalizedTiming(in: draft, at: now)
        if let activeSince = timing.activeSince {
            let interval = max(0, now.timeIntervalSince(activeSince))
            guard interval.isFinite else { throw ActiveWorkoutStoreError.invalidDraft }
            timing.accumulatedActiveSeconds += interval
        }
        timing.activeSince = nil
        timing.restingUntil = now.addingTimeInterval(TimeInterval(restSeconds))
        draft.timing = timing
    }

    private static func makeCommitIntent(
        from draft: ActiveWorkoutDraft,
        exercises storedExercises: [Exercise],
        preparedAt: Date
    ) throws -> ActiveWorkoutCommitIntent {
        guard isSupportedTimestamp(preparedAt), preparedAt >= draft.lastModifiedAt else {
            throw ActiveWorkoutStoreError.invalidDraft
        }

        let completedExercises = try draft.exercises.compactMap {
            activeExercise -> ActiveWorkoutCommitExercise? in
            let completedSets = activeExercise.sets.compactMap { set -> WorkoutSet? in
                guard set.isCompleted else { return nil }
                return WorkoutSet(id: set.id, weight: set.weight, reps: set.reps)
            }
            guard !completedSets.isEmpty else { return nil }

            let resolvedExercise = resolvedExercise(
                for: activeExercise,
                in: storedExercises
            )
            guard let rawExerciseName = activeExercise.exerciseName else {
                throw ActiveWorkoutStoreError.exerciseUnavailable
            }
            let exerciseName = rawExerciseName.gymTrimmed
            guard !exerciseName.isEmpty else {
                throw ActiveWorkoutStoreError.exerciseUnavailable
            }
            let preferredExerciseID: UUID
            if let resolvedExercise {
                preferredExerciseID = resolvedExercise.id
            } else if storedExercises.contains(where: { $0.id == activeExercise.exerciseID }) {
                // A different exercise reused the local UUID. Freeze a fresh target before
                // history is touched; the WorkoutStore later validates it again atomically.
                preferredExerciseID = UUID()
            } else {
                preferredExerciseID = activeExercise.exerciseID
            }
            return ActiveWorkoutCommitExercise(
                id: activeExercise.id,
                preferredExerciseID: preferredExerciseID,
                exerciseName: exerciseName,
                exerciseCatalogKey: activeExercise.exerciseCatalogKey,
                sets: completedSets
            )
        }
        guard !completedExercises.isEmpty else {
            throw ActiveWorkoutStoreError.noCompletedSets
        }
        return ActiveWorkoutCommitIntent(
            workoutID: draft.id,
            workoutDate: draft.workoutDate,
            note: draft.note,
            preparedAt: preparedAt,
            exercises: completedExercises
        )
    }

    private static func resolvedExerciseID(
        for activeExercise: ActiveWorkoutExercise,
        in exercises: [Exercise]
    ) -> UUID? {
        resolvedExercise(for: activeExercise, in: exercises)?.id
    }

    private static func resolvedExercise(
        for activeExercise: ActiveWorkoutExercise,
        in exercises: [Exercise]
    ) -> Exercise? {
        let expectedCatalogKey = BuiltInExerciseCatalog.resolvedKey(
            catalogKey: activeExercise.exerciseCatalogKey,
            name: activeExercise.exerciseName ?? ""
        )
        let expectedNameKey = activeExercise.exerciseName.map(
            MuscleMappingEngine.normalizeExerciseName
        )

        func identityMatches(_ exercise: Exercise) -> Bool {
            if let expectedCatalogKey {
                return BuiltInExerciseCatalog.resolvedKey(
                    catalogKey: exercise.catalogKey,
                    name: exercise.name
                ) == expectedCatalogKey
            }
            if let expectedNameKey, !expectedNameKey.isEmpty {
                return MuscleMappingEngine.normalizeExerciseName(exercise.name) == expectedNameKey
            }
            return true
        }

        if let exact = exercises.first(where: { $0.id == activeExercise.exerciseID }),
           identityMatches(exact) {
            return exact
        }
        let matchingExercises = exercises.filter(identityMatches)
        return matchingExercises.count == 1 ? matchingExercises[0] : nil
    }

    private static func normalizedNote(_ note: String?) -> String? {
        guard let cleaned = note?.gymTrimmed, !cleaned.isEmpty else { return nil }
        return cleaned
    }

    private static func validateAccountStorageKey(_ key: String) throws {
        let cleaned = key.gymTrimmed
        guard cleaned == key,
              !cleaned.isEmpty,
              cleaned.count <= maximumAccountStorageKeyCharacters,
              cleaned.utf8.prefix(maximumAccountStorageKeyBytes + 1).count <= maximumAccountStorageKeyBytes else {
            throw ActiveWorkoutStoreError.accountMismatch
        }
    }

    private static func validateJSONShape(_ data: Data) throws {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ActiveWorkoutStoreError.invalidDraft
        }
        guard root is [String: Any] else {
            throw ActiveWorkoutStoreError.invalidDraft
        }

        var pending: [(value: Any, depth: Int)] = [(root, 1)]
        var containerCount = 0
        while let item = pending.popLast() {
            guard item.depth <= maximumJSONNestingDepth else {
                throw ActiveWorkoutStoreError.limitExceeded
            }
            if let object = item.value as? [String: Any] {
                containerCount += 1
                guard containerCount <= maximumJSONContainers else {
                    throw ActiveWorkoutStoreError.limitExceeded
                }
                pending.append(contentsOf: object.values.map { ($0, item.depth + 1) })
            } else if let array = item.value as? [Any] {
                containerCount += 1
                guard containerCount <= maximumJSONContainers else {
                    throw ActiveWorkoutStoreError.limitExceeded
                }
                pending.append(contentsOf: array.map { ($0, item.depth + 1) })
            }
        }
    }

    private static func isSupportedTimestamp(_ date: Date) -> Bool {
        let milliseconds = date.timeIntervalSince1970 * 1_000
        return milliseconds.isFinite &&
            milliseconds.rounded(.towardZero) >= Double(minimumSupportedTimestampMilliseconds) &&
            milliseconds.rounded(.towardZero) <= Double(maximumSupportedTimestampMilliseconds)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func excludeFromBackup(_ url: URL) throws {
        try (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    }

    private static func writeEnvelopeAtomically(_ data: Data, to url: URL) throws {
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}
