import Foundation

public enum WorkoutFeedback: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case easy
    case normal
    case hard

    public var id: Self { self }
}

public struct WorkoutFeedbackContext: Hashable, Sendable {
    public let workoutID: UUID
    public let sessionDate: Date
    public let feedback: WorkoutFeedback

    public init(workoutID: UUID, sessionDate: Date, feedback: WorkoutFeedback) {
        self.workoutID = workoutID
        self.sessionDate = sessionDate
        self.feedback = feedback
    }
}

public enum WeeklyTrainingDecision: String, Codable, CaseIterable, Hashable, Sendable {
    case train
    case recovery
    case rest
}

public struct WeeklyTrainingGuidance: Hashable, Sendable {
    public let decision: WeeklyTrainingDecision
    public let completedTrainingDays: Int
    public let targetTrainingDays: Int

    public init(
        decision: WeeklyTrainingDecision,
        completedTrainingDays: Int,
        targetTrainingDays: Int
    ) {
        self.decision = decision
        self.completedTrainingDays = completedTrainingDays
        self.targetTrainingDays = min(6, max(2, targetTrainingDays))
    }
}

enum TrainingActivationChoices {
    static let goals: [TrainingGoal] = [
        .aestheticFatLoss,
        .muscleGain,
        .strength,
        .balanced
    ]
    static let days = Array(2 ... 6)
    static let efforts: [SmartWorkoutEffort] = [.recovery, .standard, .hard]
}

public struct WorkoutLaunchSeed: Hashable, Sendable {
    static let maximumAge: TimeInterval = 5 * 60
    static let maximumFutureSkew: TimeInterval = 60
    private static let maximumHistorySetCount = 100_000
    private static let maximumSupportedWeight = 1_000_000.0
    private static let maximumSupportedReps = 10_000
    private static let maximumSupportedSetCount = 100
    private static let maximumMuscleMappingCount = 100_000
    private static let minimumSupportedTimestamp = Date(
        timeIntervalSince1970: -62_135_769_600
    )

    public let id: UUID
    public let accountStorageKey: String
    public let profile: TrainingProfile
    public let requestedEffort: SmartWorkoutEffort
    public let plan: SmartWorkoutPlan
    public let createdAt: Date
    private let catalogBinding: Data
    private let historyBinding: Data
    private let muscleMappingBinding: Data

    public init(
        id: UUID = UUID(),
        accountStorageKey: String,
        profile: TrainingProfile,
        requestedEffort: SmartWorkoutEffort,
        plan: SmartWorkoutPlan,
        catalog: [Exercise]? = nil,
        history: [ExerciseHistoryEntry] = [],
        muscleMappings: [ExerciseMuscleMapping] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountStorageKey = accountStorageKey
        self.profile = profile
        self.requestedEffort = requestedEffort
        self.plan = plan
        self.createdAt = createdAt
        catalogBinding = Self.catalogBinding(
            catalog ?? plan.exercises.map(\.exercise)
        ) ?? Data()
        historyBinding = Self.historyBinding(
            history,
            asOf: createdAt
        ) ?? Data()
        muscleMappingBinding = Self.muscleMappingBinding(muscleMappings) ?? Data()
    }

    public func belongs(to accountStorageKey: String) -> Bool {
        self.accountStorageKey == accountStorageKey
    }

    func isValid(
        accountStorageKey: String,
        currentProfile: TrainingProfile,
        catalog: [Exercise],
        history: [ExerciseHistoryEntry] = [],
        muscleMappings: [ExerciseMuscleMapping] = [],
        now: Date = Date()
    ) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        guard belongs(to: accountStorageKey),
              profile == currentProfile,
              createdAt.timeIntervalSince1970.isFinite,
              now.timeIntervalSince1970.isFinite,
              age >= -Self.maximumFutureSkew,
              age <= Self.maximumAge,
              catalogBinding == Self.catalogBinding(catalog),
              historyBinding == Self.historyBinding(history, asOf: now),
              muscleMappings.count <= Self.maximumMuscleMappingCount,
              muscleMappingBinding == Self.muscleMappingBinding(muscleMappings),
              requestedEffort == plan.requestedEffort,
              plan.appliedEffort != .auto,
              (1 ... 8).contains(plan.exercises.count) else {
            return false
        }

        var exerciseIDs = Set<UUID>()
        var totalSets = 0
        for planned in plan.exercises {
            let recommendation = planned.recommendation
            guard exerciseIDs.insert(planned.exercise.id).inserted,
                  catalog.lazy.filter({ $0.id == planned.exercise.id }).count == 1,
                  catalog.first(where: { $0.id == planned.exercise.id }) == planned.exercise,
                  recommendation.exerciseID == planned.exercise.id,
                  (3 ... 4).contains(recommendation.sets.count),
                  recommendation.confidence.isFinite,
                  (0 ... 1).contains(recommendation.confidence),
                  recommendation.estimatedVolume.isFinite,
                  recommendation.estimatedVolume >= 0 else {
                return false
            }
            totalSets += recommendation.sets.count
            guard totalSets <= 24 else { return false }
            for set in recommendation.sets {
                guard (1 ... 10_000).contains(set.reps),
                      set.weight.map({ $0.isFinite && (0 ... 1_000_000).contains($0) }) ?? true else {
                    return false
                }
            }
        }
        return true
    }

    private static func catalogBinding(_ catalog: [Exercise]) -> Data? {
        let sorted = catalog.sorted {
            $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(sorted)
    }

    private static func historyBinding(
        _ history: [ExerciseHistoryEntry],
        asOf now: Date
    ) -> Data? {
        guard now.timeIntervalSince1970.isFinite else { return nil }
        let relevant = history
            .prefix(maximumHistorySetCount)
            .filter { isUsableHistoryEntry($0, now: now) }
            .sorted { left, right in
                if left.workoutID != right.workoutID {
                    return left.workoutID.uuidString < right.workoutID.uuidString
                }
                if left.sessionDate != right.sessionDate {
                    return left.sessionDate < right.sessionDate
                }
                if left.exerciseID != right.exerciseID {
                    return left.exerciseID.uuidString < right.exerciseID.uuidString
                }
                if left.setOrderIndex != right.setOrderIndex {
                    return left.setOrderIndex < right.setOrderIndex
                }
                return left.setID.uuidString < right.setID.uuidString
            }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(relevant)
    }

    private static func muscleMappingBinding(
        _ mappings: [ExerciseMuscleMapping]
    ) -> Data? {
        guard mappings.count <= maximumMuscleMappingCount else { return nil }
        let sorted = mappings.sorted { left, right in
            if left.exerciseNameKey != right.exerciseNameKey {
                return left.exerciseNameKey < right.exerciseNameKey
            }
            if left.muscleID != right.muscleID {
                return left.muscleID < right.muscleID
            }
            return left.updatedAt < right.updatedAt
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(sorted)
    }

    private static func isUsableHistoryEntry(
        _ entry: ExerciseHistoryEntry,
        now: Date
    ) -> Bool {
        let name = entry.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return entry.weight.isFinite && (0 ... maximumSupportedWeight).contains(entry.weight) &&
            (1 ... maximumSupportedReps).contains(entry.reps) &&
            (0 ..< maximumSupportedSetCount).contains(entry.setOrderIndex) &&
            !name.isEmpty && entry.exerciseName.utf8.count <= 640 &&
            entry.exerciseName.unicodeScalars.count <= 160 &&
            !entry.exerciseName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
            entry.sessionDate.timeIntervalSinceReferenceDate.isFinite &&
            entry.sessionDate >= minimumSupportedTimestamp &&
            entry.sessionDate <= now
    }

}

/// A launch seed may be presented repeatedly by SwiftUI for one sheet identity, but a
/// second presentation must not replay it. Claims are short-lived and root-local data
/// never leaves the process or the account-scoped store.
@MainActor
enum WorkoutLaunchSeedUseGate {
    private struct Claim {
        let consumerID: UUID
        let createdAt: Date
    }

    private static let maximumLiveClaims = 128
    private static var claims: [UUID: Claim] = [:]

    static func claim(
        _ seed: WorkoutLaunchSeed,
        consumerID: UUID,
        now: Date = Date()
    ) -> Bool {
        prune(now: now)
        guard claims[seed.id] == nil,
              claims.count < maximumLiveClaims else { return false }
        claims[seed.id] = Claim(consumerID: consumerID, createdAt: now)
        return true
    }

    static func accepts(
        _ seed: WorkoutLaunchSeed,
        consumerID: UUID?,
        now: Date = Date()
    ) -> Bool {
        prune(now: now)
        guard let consumerID, let claim = claims[seed.id] else { return false }
        return claim.consumerID == consumerID
    }

    private static func prune(now: Date) {
        claims = claims.filter { _, claim in
            let age = now.timeIntervalSince(claim.createdAt)
            return age >= -WorkoutLaunchSeed.maximumFutureSkew &&
                age <= WorkoutLaunchSeed.maximumAge
        }
    }
}

/// Materializes and starts the exact, already-reviewed Smart Coach plan without
/// routing through the editable workout sheet. The whole boundary is MainActor
/// isolated so two taps cannot both pass the active-draft and one-shot checks.
@MainActor
enum DirectWorkoutPlanStarter {
    @discardableResult
    static func start(
        seed: WorkoutLaunchSeed,
        currentProfile: TrainingProfile,
        workoutStore: WorkoutStore,
        activeWorkoutStore: ActiveWorkoutStore,
        now: Date = Date(),
        consumerID: UUID = UUID()
    ) -> ActiveWorkoutDraft? {
        guard activeWorkoutStore.draft == nil,
              activeWorkoutStore.accountStorageKey == workoutStore.accountStorageKey,
              seed.isValid(
                accountStorageKey: workoutStore.accountStorageKey,
                currentProfile: currentProfile,
                catalog: workoutStore.exercises,
                history: workoutStore.allExerciseHistory(),
                muscleMappings: workoutStore.muscleMappings,
                now: now
              ) else {
            return nil
        }

        let exercises = seed.plan.exercises.map { planned in
            ActiveWorkoutExercise(
                id: planned.exercise.id,
                exerciseID: planned.exercise.id,
                sets: planned.recommendation.sets.map { set in
                    ActiveWorkoutSet(
                        id: set.id,
                        weight: set.weight ?? 0,
                        reps: set.reps
                    )
                }
            )
        }
        guard !exercises.isEmpty,
              WorkoutLaunchSeedUseGate.claim(
                seed,
                consumerID: consumerID,
                now: now
              ) else {
            return nil
        }

        do {
            return try activeWorkoutStore.start(
                workoutDate: now,
                note: nil,
                exercises: exercises,
                workoutStore: workoutStore,
                now: now
            )
        } catch {
            return nil
        }
    }
}

enum FirstWorkoutActivation {
    static func commit(
        seed: WorkoutLaunchSeed,
        accountStorageKey: String,
        catalog: [Exercise],
        muscleMappings: [ExerciseMuscleMapping] = [],
        profileStore: TrainingProfileStore,
        now: Date = Date(),
        launch: (WorkoutLaunchSeed) -> Bool
    ) -> Bool {
        guard seed.isValid(
            accountStorageKey: accountStorageKey,
            currentProfile: seed.profile,
            catalog: catalog,
            muscleMappings: muscleMappings,
            now: now
        ) else { return false }
        return profileStore.withCommittedActivation(
            seed.profile,
            accountStorageKey: accountStorageKey
        ) {
            launch(seed)
        }
    }
}

public extension TrainingProfile {
    static func activationProfile(
        goal: TrainingGoal,
        workoutsPerWeek: Int
    ) -> TrainingProfile {
        let boundedDays = min(6, max(2, workoutsPerWeek))
        let split: TrainingSplit = switch boundedDays {
        case ...3: .fullBody
        case 4: .upperLower
        default: .pushPullLegs
        }
        let calories: CalorieMode = switch goal {
        case .aestheticFatLoss: .deficit
        case .muscleGain: .surplus
        case .strength, .balanced: .maintenance
        }
        return TrainingProfile(
            split: split,
            workoutsPerWeek: boundedDays,
            goal: goal,
            calorieMode: calories
        )
    }
}

public extension SmartWorkoutFocus {
    var displayName: String {
        switch self {
        case .upper:
            gymText("Upper body", "Верх тіла", "Верх тела", languageCode: gymCurrentLanguageCode())
        case .lower:
            gymText("Lower body", "Низ тіла", "Низ тела", languageCode: gymCurrentLanguageCode())
        case .push:
            gymText("Push", "Жимові", "Жимовые", languageCode: gymCurrentLanguageCode())
        case .pull:
            gymText("Pull", "Тягові", "Тяговые", languageCode: gymCurrentLanguageCode())
        case .legs:
            gymText("Legs", "Ноги", "Ноги", languageCode: gymCurrentLanguageCode())
        case .fullBody:
            gymText("Full body", "Усе тіло", "Всё тело", languageCode: gymCurrentLanguageCode())
        }
    }
}

public extension SmartWorkoutEffort {
    var gymDisplayName: String {
        switch self {
        case .auto:
            gymText("Auto", "Авто", "Авто", languageCode: gymCurrentLanguageCode())
        case .recovery:
            gymText(
                "Recovery",
                "Відновлювальне",
                "Восстановительная",
                languageCode: gymCurrentLanguageCode()
            )
        case .standard:
            gymText(
                "Standard",
                "Звичайне",
                "Обычная",
                languageCode: gymCurrentLanguageCode()
            )
        case .hard:
            gymText(
                "Hard",
                "Важке",
                "Тяжёлая",
                languageCode: gymCurrentLanguageCode()
            )
        }
    }
}
