import Foundation

public enum TrainingSplit: String, Codable, CaseIterable, Sendable {
    case upperLower
    case fullBody
    case pushPullLegs
    case custom
}

public enum TrainingGoal: String, Codable, CaseIterable, Sendable {
    case aestheticFatLoss
    case muscleGain
    case strength
    case balanced
}

public enum CalorieMode: String, Codable, CaseIterable, Sendable {
    case deficit
    case maintenance
    case surplus
}

public enum SmartWorkoutEffort: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case auto
    case recovery
    case standard
    case hard

    public var id: Self { self }

    /// A plan created before effort-aware coaching existed decodes as Auto.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try? container.decode(String.self)
        self = rawValue.flatMap(Self.init(rawValue:)) ?? .auto
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum SmartWorkoutEffortAdjustment: String, Codable, Hashable, Sendable {
    case autoRecovery
    case autoFeedbackRecovery
    case feedbackEasyExtraSet
    case hardInsufficientHistory
    case hardLongBreak
    case hardTargetNotRecovered
}

public struct TrainingProfile: Codable, Hashable, Sendable {
    public var split: TrainingSplit
    public var workoutsPerWeek: Int
    public var goal: TrainingGoal
    public var calorieMode: CalorieMode

    public init(
        split: TrainingSplit = .upperLower,
        workoutsPerWeek: Int = 4,
        goal: TrainingGoal = .aestheticFatLoss,
        calorieMode: CalorieMode = .deficit
    ) {
        self.split = split
        self.workoutsPerWeek = min(6, max(2, workoutsPerWeek))
        self.goal = goal
        self.calorieMode = calorieMode
    }
}

public struct RecommendedWorkoutSet: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let weight: Double?
    public let reps: Int

    public init(id: UUID = UUID(), weight: Double?, reps: Int) {
        self.id = id
        self.weight = weight
        self.reps = reps
    }
}

public enum WorkoutRecommendationKind: String, Codable, CaseIterable, Sendable {
    case newExercise
    case progressiveOverload
    case holdAndBuild
    case deload
    case comeback
    case plateauBreak
}

public enum WorkoutRecommendationReason: String, Codable, CaseIterable, Sendable {
    case noHistory
    case lastSessionStrong
    case lastSessionUnstable
    case recentBreak
    case volumeTrendingUp
    case volumeDropped
    case plateauDetected
    case nearPersonalBest
    case conservativeIncrease
    case loadBoundaryReached
    case harderBodyweightVariation
    case recoverySession
    case hardSession
    case aestheticGoal
    case calorieDeficit
    case fourDayUpperLower
}

public struct WorkoutRecommendation: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID { exerciseID }
    public let exerciseID: UUID
    public let sets: [RecommendedWorkoutSet]
    public let kind: WorkoutRecommendationKind
    public let confidence: Float
    public let estimatedVolume: Double
    public let daysSinceLastSession: Int?
    public let reasons: [WorkoutRecommendationReason]

    public var targetRIR: ClosedRange<Int> {
        if kind == .deload || kind == .comeback || reasons.contains(.recoverySession) {
            return 3 ... 4
        }
        if reasons.contains(.hardSession), sets.count == 4 {
            return 1 ... 2
        }
        return 2 ... 3
    }
}

public enum SmartWorkoutFocus: String, Codable, CaseIterable, Sendable {
    case upper
    case lower
    case push
    case pull
    case legs
    case fullBody
}

public struct SmartWorkoutExercise: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID { exercise.id }
    public let exercise: Exercise
    public let recommendation: WorkoutRecommendation
}

public struct SmartWorkoutAlternative: Identifiable, Hashable, Sendable {
    public var id: UUID { exercise.id }
    public let exercise: Exercise
    public let recommendation: WorkoutRecommendation

    public init(exercise: Exercise, recommendation: WorkoutRecommendation) {
        self.exercise = exercise
        self.recommendation = recommendation
    }
}

public enum SmartWorkoutVariant: String, Codable, CaseIterable, Sendable {
    case a = "A"
    case b = "B"
    case c = "C"

    fileprivate var index: Int {
        switch self {
        case .a: return 0
        case .b: return 1
        case .c: return 2
        }
    }
}

public struct SmartWorkoutPlan: Codable, Identifiable, Hashable, Sendable {
    public var id: String {
        focus.rawValue + ":" + variant.rawValue + ":" +
            exercises.map { $0.id.uuidString }.joined(separator: ",")
    }
    public let focus: SmartWorkoutFocus
    public let exercises: [SmartWorkoutExercise]
    public let variant: SmartWorkoutVariant
    public let requestedEffort: SmartWorkoutEffort
    public let appliedEffort: SmartWorkoutEffort
    public let effortAdjustment: SmartWorkoutEffortAdjustment?

    public init(
        focus: SmartWorkoutFocus,
        exercises: [SmartWorkoutExercise],
        variant: SmartWorkoutVariant = .a,
        requestedEffort: SmartWorkoutEffort = .auto,
        appliedEffort: SmartWorkoutEffort = .standard,
        effortAdjustment: SmartWorkoutEffortAdjustment? = nil
    ) {
        self.focus = focus
        self.exercises = exercises
        self.variant = variant
        self.requestedEffort = requestedEffort
        self.appliedEffort = appliedEffort == .auto ? .standard : appliedEffort
        self.effortAdjustment = effortAdjustment
    }

    private enum CodingKeys: String, CodingKey {
        case focus
        case exercises
        case variant
        case requestedEffort
        case appliedEffort
        case effortAdjustment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        focus = try container.decode(SmartWorkoutFocus.self, forKey: .focus)
        exercises = try container.decode([SmartWorkoutExercise].self, forKey: .exercises)
        variant = try container.decodeIfPresent(SmartWorkoutVariant.self, forKey: .variant) ?? .a
        requestedEffort = try container.decodeIfPresent(
            SmartWorkoutEffort.self,
            forKey: .requestedEffort
        ) ?? .auto
        let decodedApplied = try container.decodeIfPresent(
            SmartWorkoutEffort.self,
            forKey: .appliedEffort
        ) ?? .standard
        appliedEffort = decodedApplied == .auto ? .standard : decodedApplied
        effortAdjustment = try container.decodeIfPresent(
            SmartWorkoutEffortAdjustment.self,
            forKey: .effortAdjustment
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(focus, forKey: .focus)
        try container.encode(exercises, forKey: .exercises)
        try container.encode(variant, forKey: .variant)
        try container.encode(requestedEffort, forKey: .requestedEffort)
        try container.encode(appliedEffort, forKey: .appliedEffort)
        try container.encodeIfPresent(effortAdjustment, forKey: .effortAdjustment)
    }
}

/// Pure Swift port of Android's per-exercise and smart-plan recommendation engine.
public enum RecommendationEngine {
    enum ExerciseRole: String, Sendable {
        case primary
        case secondary
        case isolation
        case core
        case warmup
    }

    enum ExerciseLoadMode: String, Sendable {
        case standard
        case bodyweight
        case assistance
        case none
    }

    enum EquipmentKind: String, Codable, CaseIterable, Sendable {
        case barbell
        case dumbbell
        case cable
        case machine
        case bodyweight
        case assisted
        case other
    }

    enum MovementPattern: Hashable, Sendable {
        case squat, legPress, hinge, kneeFlexion, kneeExtension, calf
        case horizontalPress, verticalPress, horizontalPull, verticalPull
        case core, accessory
    }

    struct ExerciseProgrammingMetadata: Equatable, Sendable {
        let category: SmartWorkoutFocus
        let role: ExerciseRole
        let loadMode: ExerciseLoadMode
        let patterns: Set<MovementPattern>
        let equipment: EquipmentKind

        init(
            category: SmartWorkoutFocus,
            role: ExerciseRole,
            loadMode: ExerciseLoadMode,
            patterns: Set<MovementPattern>,
            equipment: EquipmentKind = .other
        ) {
            self.category = category
            self.role = role
            self.loadMode = loadMode
            self.patterns = patterns
            self.equipment = equipment
        }
    }

    private static let defaultSetCount = 3
    private static let defaultReps = 10
    private static let maxHistorySessions = 24
    private static let comebackBreakDays = 10
    private static let maximumSupportedWeight = 1_000_000.0
    private static let maximumSupportedReps = 10_000
    private static let maximumSupportedSetCount = 100
    private static let maximumHistorySetCount = 100_000
    private static let maximumExerciseCount = 2_000
    private static let maximumSmartPlanSetCount = 24
    private static let minimumSupportedTimestamp = Date(
        timeIntervalSince1970: -62_135_769_600
    )

    private static let upperFocuses: Set<SmartWorkoutFocus> = [.upper, .push, .pull]
    private static let lowerFocuses: Set<SmartWorkoutFocus> = [.lower, .legs]
    private static let pushMuscles: Set<String> = ["chest", "shoulders", "triceps"]
    private static let pullMuscles: Set<String> = ["lats", "upperBack", "biceps", "forearms"]
    private static let lowerMuscles: Set<String> = ["quads", "hamstrings", "glutes", "calves", "adductors", "lowerBack"]
    private static let coreMuscles: Set<String> = ["abs", "obliques"]
    private static let lowerMovementPatterns: Set<MovementPattern> = [
        .squat, .legPress, .hinge, .kneeFlexion, .kneeExtension, .calf
    ]
    private static let compoundMovementPatterns: Set<MovementPattern> = [
        .squat, .legPress, .hinge, .horizontalPress, .verticalPress, .horizontalPull, .verticalPull
    ]

    // Reviewed programming data is bound to canonical catalog keys. User-created
    // names still use the conservative heuristic fallback in analyzeExercise.
    static let builtInProgramming: [String: ExerciseProgrammingMetadata] = [
        "bench_press": .init(category: .push, role: .primary, loadMode: .standard, patterns: [.horizontalPress]),
        "dumbbell_bench_press": .init(category: .push, role: .secondary, loadMode: .standard, patterns: [.horizontalPress]),
        "incline_dumbbell_press": .init(category: .push, role: .secondary, loadMode: .standard, patterns: [.horizontalPress]),
        "incline_bench_press": .init(category: .push, role: .secondary, loadMode: .standard, patterns: [.horizontalPress]),
        "chest_fly_machine": .init(category: .push, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "push_up": .init(category: .push, role: .secondary, loadMode: .bodyweight, patterns: [.horizontalPress]),
        "dips": .init(category: .push, role: .secondary, loadMode: .bodyweight, patterns: [.horizontalPress]),
        "assisted_dip": .init(category: .push, role: .secondary, loadMode: .assistance, patterns: [.horizontalPress]),
        "pull_up": .init(category: .pull, role: .secondary, loadMode: .bodyweight, patterns: [.verticalPull]),
        "assisted_pull_up": .init(category: .pull, role: .secondary, loadMode: .assistance, patterns: [.verticalPull]),
        "band_assisted_pull_up": .init(category: .pull, role: .secondary, loadMode: .bodyweight, patterns: [.verticalPull]),
        "lat_pulldown": .init(category: .pull, role: .secondary, loadMode: .standard, patterns: [.verticalPull]),
        "straight_arm_pulldown": .init(category: .pull, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "barbell_row": .init(category: .pull, role: .primary, loadMode: .standard, patterns: [.horizontalPull]),
        "seated_cable_row": .init(category: .pull, role: .secondary, loadMode: .standard, patterns: [.horizontalPull]),
        "plate_loaded_row": .init(category: .pull, role: .secondary, loadMode: .standard, patterns: [.horizontalPull]),
        "face_pull": .init(category: .pull, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "squat": .init(category: .legs, role: .primary, loadMode: .standard, patterns: [.squat]),
        "leg_press": .init(category: .legs, role: .secondary, loadMode: .standard, patterns: [.legPress]),
        "bulgarian_split_squat": .init(category: .legs, role: .secondary, loadMode: .standard, patterns: [.squat]),
        "lunge": .init(category: .legs, role: .secondary, loadMode: .standard, patterns: [.squat]),
        "romanian_deadlift": .init(category: .legs, role: .primary, loadMode: .standard, patterns: [.hinge]),
        "deadlift": .init(category: .legs, role: .primary, loadMode: .standard, patterns: [.hinge]),
        "hip_thrust": .init(category: .legs, role: .secondary, loadMode: .standard, patterns: [.hinge]),
        "leg_extension": .init(category: .legs, role: .isolation, loadMode: .standard, patterns: [.kneeExtension]),
        "lying_leg_curl": .init(category: .legs, role: .isolation, loadMode: .standard, patterns: [.kneeFlexion]),
        "seated_leg_curl": .init(category: .legs, role: .isolation, loadMode: .standard, patterns: [.kneeFlexion]),
        "hip_adduction": .init(category: .legs, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "hip_abduction": .init(category: .legs, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "calf_raise": .init(category: .legs, role: .isolation, loadMode: .standard, patterns: [.calf]),
        "shoulder_press": .init(category: .push, role: .primary, loadMode: .standard, patterns: [.verticalPress]),
        "lateral_raise": .init(category: .push, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "machine_lateral_raise": .init(category: .push, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "rear_delt_fly": .init(category: .pull, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "upright_row": .init(category: .pull, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "biceps_curl": .init(category: .pull, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "barbell_curl": .init(category: .pull, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "seated_dumbbell_curl": .init(category: .pull, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "hammer_curl": .init(category: .pull, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "cable_curl": .init(category: .pull, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "preacher_curl": .init(category: .pull, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "triceps_pushdown": .init(category: .push, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "v_bar_pushdown": .init(category: .push, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "overhead_dumbbell_triceps_extension": .init(category: .push, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "french_press": .init(category: .push, role: .isolation, loadMode: .standard, patterns: [.accessory]),
        "hyperextension": .init(category: .legs, role: .isolation, loadMode: .standard, patterns: [.hinge]),
        "side_hyperextension": .init(category: .fullBody, role: .core, loadMode: .standard, patterns: [.core]),
        "plank": .init(category: .fullBody, role: .core, loadMode: .bodyweight, patterns: [.core]),
        "weighted_crunch": .init(category: .fullBody, role: .core, loadMode: .standard, patterns: [.core]),
        "hanging_leg_raise": .init(category: .fullBody, role: .core, loadMode: .bodyweight, patterns: [.core]),
        "plate_twist": .init(category: .fullBody, role: .core, loadMode: .standard, patterns: [.core]),
        "weighted_side_bend": .init(category: .fullBody, role: .core, loadMode: .standard, patterns: [.core]),
        "warm_up": .init(category: .fullBody, role: .warmup, loadMode: .none, patterns: [.accessory])
    ]

    /// Equipment is trusted only when it is attached to a canonical built-in key.
    /// Custom names never get equipment privileges from keyword matching.
    static let builtInEquipment: [String: EquipmentKind] = [
        "bench_press": .barbell,
        "dumbbell_bench_press": .dumbbell,
        "incline_dumbbell_press": .dumbbell,
        "incline_bench_press": .barbell,
        "chest_fly_machine": .machine,
        "push_up": .bodyweight,
        "dips": .bodyweight,
        "assisted_dip": .assisted,
        "pull_up": .bodyweight,
        "assisted_pull_up": .assisted,
        "band_assisted_pull_up": .assisted,
        "lat_pulldown": .cable,
        "straight_arm_pulldown": .cable,
        "barbell_row": .barbell,
        "seated_cable_row": .cable,
        "plate_loaded_row": .machine,
        "face_pull": .cable,
        "squat": .barbell,
        "leg_press": .machine,
        "bulgarian_split_squat": .dumbbell,
        "lunge": .dumbbell,
        "romanian_deadlift": .barbell,
        "deadlift": .barbell,
        "hip_thrust": .barbell,
        "leg_extension": .machine,
        "lying_leg_curl": .machine,
        "seated_leg_curl": .machine,
        "hip_adduction": .machine,
        "hip_abduction": .machine,
        "calf_raise": .machine,
        "shoulder_press": .dumbbell,
        "lateral_raise": .dumbbell,
        "machine_lateral_raise": .machine,
        "rear_delt_fly": .machine,
        "upright_row": .barbell,
        "biceps_curl": .dumbbell,
        "barbell_curl": .barbell,
        "seated_dumbbell_curl": .dumbbell,
        "hammer_curl": .dumbbell,
        "cable_curl": .cable,
        "preacher_curl": .machine,
        "triceps_pushdown": .cable,
        "v_bar_pushdown": .cable,
        "overhead_dumbbell_triceps_extension": .dumbbell,
        "french_press": .barbell,
        "hyperextension": .machine,
        "side_hyperextension": .machine,
        "plank": .bodyweight,
        "weighted_crunch": .cable,
        "hanging_leg_raise": .bodyweight,
        "plate_twist": .other,
        "weighted_side_bend": .dumbbell,
        "warm_up": .bodyweight
    ]

    public static func buildForExercise(
        exerciseID: UUID,
        history: [ExerciseHistoryEntry],
        exerciseCatalogKey: String? = nil,
        exerciseName: String? = nil,
        machineLoadProfile: MachineLoadProfile? = nil,
        trainingProfile: TrainingProfile = TrainingProfile(),
        effort: SmartWorkoutEffort = .standard,
        allowsHardSetBoost: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WorkoutRecommendation {
        let appliedEffort: SmartWorkoutEffort = effort == .auto ? .standard : effort
        let programmingAnalysis: ExerciseAnalysis? = if let exerciseName,
                                                        !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            analyzeExercise(exerciseName, catalogKey: exerciseCatalogKey)
        } else if let matchingEntry = history.first(where: {
            $0.exerciseID == exerciseID && !$0.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            analyzeExercise(
                matchingEntry.exerciseName,
                catalogKey: matchingEntry.exerciseCatalogKey
            )
        } else {
            nil
        }
        let targetIdentityKey = exerciseName.map {
            exerciseIdentityKey(name: $0, catalogKey: exerciseCatalogKey)
        } ?? exerciseCatalogKey.flatMap {
            BuiltInExerciseCatalog.definition(forKey: $0).map { "catalog:\($0.key)" }
        }
        let matchingHistory = history
            .prefix(maximumHistorySetCount)
            .filter {
                isUsableHistoryEntry($0, now: now) &&
                    ($0.exerciseID == exerciseID || (
                        targetIdentityKey != nil &&
                            entryIdentityKey($0) == targetIdentityKey
                    ))
            }
            .sorted {
                $0.sessionDate == $1.sessionDate
                    ? $0.setOrderIndex < $1.setOrderIndex
                    : $0.sessionDate > $1.sessionDate
            }
        let repRange = goalRepRange(trainingProfile, analysis: programmingAnalysis)
        let defaultRepsTarget = defaultTargetReps(
            trainingProfile,
            analysis: programmingAnalysis,
            repRange: repRange
        )
        let matchingSessionCount = Set(matchingHistory.map(\.workoutID)).count
        let hardSetEligible = allowsHardSetBoost && matchingSessionCount >= 2

        guard !matchingHistory.isEmpty else {
            let targetSetCount = setBudget(
                profile: trainingProfile,
                analysis: programmingAnalysis,
                effort: appliedEffort,
                allowsHardSetBoost: false
            )
            let defaultWeight: Double? = if let loadMode = programmingAnalysis?.loadMode,
                                            loadMode == .bodyweight || loadMode == .none {
                0
            } else {
                nil
            }
            let newExerciseReps = appliedEffort == .recovery &&
                programmingAnalysis?.loadMode == .bodyweight
                ? max(repRange.lowerBound, defaultRepsTarget - 1)
                : defaultRepsTarget
            return WorkoutRecommendation(
                exerciseID: exerciseID,
                sets: (0 ..< targetSetCount).map { index in
                    RecommendedWorkoutSet(
                        id: recommendedSetID(
                            exerciseID: exerciseID,
                            workoutID: nil,
                            kind: .newExercise,
                            index: index,
                            weight: defaultWeight,
                            reps: newExerciseReps
                        ),
                        weight: defaultWeight,
                        reps: newExerciseReps
                    )
                },
                kind: .newExercise,
                confidence: 0.35,
                estimatedVolume: 0,
                daysSinceLastSession: nil,
                reasons: appliedEffort == .recovery
                    ? [.noHistory, .recoverySession]
                    : [.noHistory]
            )
        }

        let groupedHistory: [UUID: [ExerciseHistoryEntry]] = Dictionary(
            grouping: matchingHistory,
            by: { $0.workoutID }
        )
        let unsortedSnapshots: [ExerciseSessionSnapshot] = groupedHistory.values.map { entries in
            let sortedSets = entries.sorted {
                $0.setOrderIndex == $1.setOrderIndex
                    ? $0.setID.uuidString < $1.setID.uuidString
                    : $0.setOrderIndex < $1.setOrderIndex
            }
            return ExerciseSessionSnapshot(
                sets: Array(sortedSets.prefix(maximumSupportedSetCount))
            )
        }
        let sortedSnapshots = unsortedSnapshots.sorted { left, right in
            left.date == right.date
                ? left.workoutID.uuidString < right.workoutID.uuidString
                : left.date > right.date
        }
        let sessionSnapshots = Array(sortedSnapshots.prefix(maxHistorySessions))
        let latest = sessionSnapshots[0]
        let previous = sessionSnapshots.count > 1 ? sessionSnapshots[1] : nil
        let daysSinceLastSession = calendar.gymDaysBetween(latest.date, now)
        let targetSetCount = setBudget(
            profile: trainingProfile,
            analysis: programmingAnalysis,
            effort: appliedEffort,
            allowsHardSetBoost: hardSetEligible
        )
        let loadMode = programmingAnalysis?.loadMode ?? .standard
        let loadDirection = effectiveLoadDirection(
            machineLoadProfile: machineLoadProfile,
            loadMode: loadMode
        )
        let usesExternalLoadMetrics = loadDirection == .higherIsHarder && loadMode != .assistance
        let canAssessStandardLoadTrend = usesExternalLoadMetrics && latest.maxWeight > 0
        let bestEstimatedMax = canAssessStandardLoadTrend
            ? sessionSnapshots.map { $0.estimatedMax }.max() ?? 0
            : 0
        let plateauDetected = canAssessStandardLoadTrend &&
            isTruePlateau(Array(sessionSnapshots.prefix(4)))
        let latestNearBest = canAssessStandardLoadTrend &&
            latest.estimatedMax >= bestEstimatedMax * 0.97
        let previousVolumePerSet = previous?.averageVolumePerSet ?? latest.averageVolumePerSet
        let volumeRatio = !canAssessStandardLoadTrend || previousVolumePerSet <= 0
            ? 1
            : latest.averageVolumePerSet / previousVolumePerSet
        let repeatedRegression: Bool
        if sessionSnapshots.count < 3 {
            repeatedRegression = false
        } else if loadDirection == .lowerIsHarder {
            repeatedRegression = isAssistanceRegression(
                newer: sessionSnapshots[0],
                older: sessionSnapshots[1]
            ) && isAssistanceRegression(
                newer: sessionSnapshots[1],
                older: sessionSnapshots[2]
            )
        } else if loadMode == .bodyweight,
                  sessionSnapshots.prefix(3).allSatisfy({ $0.maxWeight <= 0 }) {
            repeatedRegression = isBodyweightRepRegression(
                newer: sessionSnapshots[0],
                older: sessionSnapshots[1]
            ) && isBodyweightRepRegression(
                newer: sessionSnapshots[1],
                older: sessionSnapshots[2]
            )
        } else {
            repeatedRegression = canAssessStandardLoadTrend &&
                isComparableRegression(newer: sessionSnapshots[0], older: sessionSnapshots[1]) &&
                isComparableRegression(newer: sessionSnapshots[1], older: sessionSnapshots[2])
        }
        let latestStable = latest.sets.count >= 2 &&
            latest.sets.allSatisfy { $0.reps >= repRange.lowerBound }
        let latestStrained = latest.sets.contains { $0.reps < repRange.lowerBound } ||
            (canAssessStandardLoadTrend && volumeRatio < 0.90)
        let completedRepCeiling = completedAtRepCeiling(
            latest,
            targetSetCount: targetSetCount,
            repCeiling: repRange.upperBound
        ) && completedAtRepCeiling(
            previous,
            targetSetCount: targetSetCount,
            repCeiling: repRange.upperBound
        ) && performanceDidNotDecline(
            latest: latest,
            previous: previous,
            targetSetCount: targetSetCount,
            loadDirection: loadDirection
        )
        let needsHarderBodyweightVariation = completedRepCeiling &&
            loadMode == .bodyweight && latest.maxWeight <= 0
        let earnedProgression = completedRepCeiling && !needsHarderBodyweightVariation
        let hasHarderWeight = harderWeightAvailable(
                machineLoadProfile: machineLoadProfile,
                loadDirection: loadDirection,
                baselineSets: Array(latest.sets.prefix(targetSetCount))
            )
        let earnedAtLoadBoundary = earnedProgression && !hasHarderWeight
        let isFatLossDeficit = trainingProfile.goal == .aestheticFatLoss &&
            trainingProfile.calorieMode == .deficit

        let baseKind: WorkoutRecommendationKind
        if daysSinceLastSession >= comebackBreakDays {
            baseKind = .comeback
        } else if repeatedRegression {
            baseKind = .deload
        } else if earnedProgression && hasHarderWeight {
            baseKind = .progressiveOverload
        } else if plateauDetected {
            baseKind = .plateauBreak
        } else {
            baseKind = .holdAndBuild
        }
        let kind: WorkoutRecommendationKind = if appliedEffort == .recovery,
                                                   baseKind != .deload,
                                                   baseKind != .comeback {
            .holdAndBuild
        } else {
            baseKind
        }
        let safetyOverridesIntensity = kind == .deload || kind == .comeback
        let hardIntensityEligible = appliedEffort == .hard && hardSetEligible &&
            isCompound(programmingAnalysis) && !safetyOverridesIntensity
        let effectiveTargetSetCount = safetyOverridesIntensity ? 3 : targetSetCount

        let baselineSets = resizedBaselineSets(latest.sets, targetCount: effectiveTargetSetCount)
        let plateauUsesLowerRange = latest.averageReps >= Double(repRange.lowerBound + repRange.upperBound) / 2
        let sets = baselineSets.enumerated().map { index, baseline -> RecommendedWorkoutSet in
            let target: (weight: Double?, reps: Int)
            switch kind {
            case .newExercise:
                target = (nil, defaultRepsTarget)
            case .progressiveOverload:
                let increasedWeight = adjustedWeight(
                    baseline.weight,
                    adjustment: .harder,
                    machineLoadProfile: machineLoadProfile,
                    loadDirection: loadDirection
                )
                target = (
                    increasedWeight,
                    baseline.weight <= 0 ? repRange.upperBound : repRange.lowerBound
                )
            case .holdAndBuild:
                target = (
                    adjustedWeight(
                        baseline.weight,
                        adjustment: .hold,
                        machineLoadProfile: machineLoadProfile,
                        loadDirection: loadDirection
                    ),
                    min(repRange.upperBound, max(repRange.lowerBound, baseline.reps + 1))
                )
            case .deload:
                target = (
                    easedWeight(
                        baseline.weight,
                        multiplier: isFatLossDeficit ? 0.9 : 0.92,
                        machineLoadProfile: machineLoadProfile,
                        loadDirection: loadDirection
                    ),
                    min(repRange.upperBound, max(repRange.lowerBound, baseline.reps))
                )
            case .comeback:
                target = (
                    easedWeight(
                        baseline.weight,
                        multiplier: comebackMultiplier(daysSinceLastSession),
                        machineLoadProfile: machineLoadProfile,
                        loadDirection: loadDirection
                    ),
                    min(repRange.upperBound, max(repRange.lowerBound, baseline.reps))
                )
            case .plateauBreak:
                target = (
                    adjustedWeight(
                        baseline.weight,
                        adjustment: .hold,
                        machineLoadProfile: machineLoadProfile,
                        loadDirection: loadDirection
                    ),
                    plateauUsesLowerRange ? repRange.lowerBound : repRange.upperBound
                )
            }
            let effortAdjustedTarget: (weight: Double?, reps: Int)
            if appliedEffort == .recovery, !safetyOverridesIntensity {
                let recoveryReps = loadMode == .bodyweight || loadMode == .none
                    ? max(repRange.lowerBound, min(repRange.upperBound, baseline.reps - 1))
                    : max(repRange.lowerBound, min(repRange.upperBound, baseline.reps))
                effortAdjustedTarget = (
                    easedWeight(
                        baseline.weight,
                        multiplier: 0.9,
                        machineLoadProfile: machineLoadProfile,
                        loadDirection: loadDirection
                    ),
                    recoveryReps
                )
            } else {
                effortAdjustedTarget = target
            }
            return RecommendedWorkoutSet(
                id: recommendedSetID(
                    exerciseID: exerciseID,
                    workoutID: latest.workoutID,
                    kind: kind,
                    index: index,
                    weight: effortAdjustedTarget.weight,
                    reps: effortAdjustedTarget.reps
                ),
                weight: effortAdjustedTarget.weight,
                reps: effortAdjustedTarget.reps
            )
        }

        var reasons: [WorkoutRecommendationReason] = []
        func addReason(_ reason: WorkoutRecommendationReason, when condition: Bool) {
            if condition && !reasons.contains(reason) { reasons.append(reason) }
        }
        addReason(.recoverySession, when: appliedEffort == .recovery)
        addReason(.hardSession, when: hardIntensityEligible)
        addReason(.loadBoundaryReached, when: earnedAtLoadBoundary)
        addReason(.harderBodyweightVariation, when: needsHarderBodyweightVariation)
        addReason(.lastSessionStrong, when: latestStable)
        addReason(.lastSessionUnstable, when: latestStrained || repeatedRegression)
        addReason(.recentBreak, when: daysSinceLastSession >= comebackBreakDays)
        addReason(.volumeTrendingUp, when: canAssessStandardLoadTrend && volumeRatio >= 1.08)
        addReason(.volumeDropped, when: canAssessStandardLoadTrend && (volumeRatio < 0.9 || repeatedRegression))
        addReason(.plateauDetected, when: plateauDetected)
        addReason(.nearPersonalBest, when: latestNearBest)
        addReason(.aestheticGoal, when: trainingProfile.goal == .aestheticFatLoss)
        addReason(.calorieDeficit, when: trainingProfile.calorieMode == .deficit)
        addReason(.fourDayUpperLower, when: trainingProfile.workoutsPerWeek == 4 && trainingProfile.split == .upperLower)
        addReason(.conservativeIncrease, when: kind == .progressiveOverload)
        if reasons.isEmpty { reasons = [.conservativeIncrease] }

        return WorkoutRecommendation(
            exerciseID: exerciseID,
            sets: sets,
            kind: kind,
            confidence: confidence(
                sessionCount: sessionSnapshots.count,
                lastSetCount: latest.sets.count,
                daysSinceLastSession: daysSinceLastSession,
                profile: trainingProfile
            ),
            estimatedVolume: usesExternalLoadMetrics
                ? sets.reduce(0) { $0 + ($1.weight ?? 0) * Double($1.reps) }
                : 0,
            daysSinceLastSession: daysSinceLastSession,
            reasons: Array(reasons.prefix(3))
        )
    }

    public static func buildWorkoutPlan(
        exercises: [Exercise],
        history: [ExerciseHistoryEntry],
        muscleMappings: [ExerciseMuscleMapping] = [],
        trainingProfile: TrainingProfile = TrainingProfile(),
        effort requestedEffort: SmartWorkoutEffort = .auto,
        latestFeedback: WorkoutFeedbackContext? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SmartWorkoutPlan {
        var seenExerciseIDs = Set<UUID>()
        let usableExercises = exercises
            .prefix(maximumExerciseCount)
            .filter {
                isUsableExercise($0) &&
                    BuiltInExerciseCatalog.resolvedKey(
                        catalogKey: $0.catalogKey,
                        name: $0.name
                    ) != "warm_up" &&
                    seenExerciseIDs.insert($0.id).inserted
            }
        guard !usableExercises.isEmpty else {
            return SmartWorkoutPlan(
                focus: .fullBody,
                exercises: [],
                requestedEffort: requestedEffort,
                appliedEffort: .standard
            )
        }
        let usableHistory = history
            .prefix(maximumHistorySetCount)
            .filter {
                isUsableHistoryEntry($0, now: now) && $0.sessionDate <= now
            }
        let focus = chooseWorkoutFocus(
            history: usableHistory,
            profile: trainingProfile,
            now: now,
            calendar: calendar
        )
        let variant = nextVariant(
            focus: focus,
            history: usableHistory
        )
        let recentIDs = recentSessionIDs(usableHistory, limit: 3)
        let targetMuscles = targetMuscles(for: focus)
        let effortResolution = resolveEffort(
            requested: requestedEffort,
            targetMuscles: targetMuscles,
            history: usableHistory,
            latestFeedback: latestFeedback,
            now: now,
            calendar: calendar
        )
        let appliedEffort = effortResolution.effort
        let targetSessionSetBudget = targetSessionSetBudget(
            profile: trainingProfile,
            effort: appliedEffort
        )
        let targetExerciseCount = targetExerciseCount(
            profile: trainingProfile,
            effort: appliedEffort,
            sessionSetBudget: targetSessionSetBudget
        )
        let manualContributionMap = MuscleMappingEngine.manualContributionMap(from: muscleMappings)
        let weeklyVolume = weeklyVolumeState(
            history: usableHistory,
            manualContributions: manualContributionMap,
            profile: trainingProfile,
            now: now
        )
        let historyByIdentity: [String: [ExerciseHistoryEntry]] = Dictionary(
            grouping: usableHistory,
            by: { entryIdentityKey($0) }
        )
        let candidates = usableExercises.map { exercise -> ExerciseCandidate in
            let identityKey = exerciseIdentityKey(exercise)
            let exerciseHistory = historyByIdentity[identityKey, default: []]
            let analysis = analyzeExercise(
                exercise.name,
                catalogKey: exercise.catalogKey
            )
            let daysSince = exerciseHistory.map(\.sessionDate).max()
                .map { calendar.gymDaysBetween($0, now) } ?? 7
            let sessionCount = Set(exerciseHistory.map(\.workoutID)).count
            let recentPenalty = Double(Set(
                exerciseHistory.filter { recentIDs.contains($0.workoutID) }.map(\.workoutID)
            ).count) * 8
            let sameWeekPenalty = exerciseHistory.contains {
                calendar.gymDaysBetween($0.sessionDate, now) <= 6
            } ? 10.0 : 0.0
            let focusScore: Double
            if focus == .fullBody {
                focusScore = 44
            } else if isEligible(analysis, for: focus) {
                focusScore = 86
            } else if analysis.category == .fullBody {
                focusScore = 32
            } else {
                focusScore = -60
            }
            let muscleMatch = Double(analysis.muscles.intersection(targetMuscles).count) * 9
            let due = Double(min(14, daysSince))
            let continuity = Double(min(4, sessionCount)) * 5
            let variantScore = variantPreferenceScore(
                analysis: analysis,
                focus: focus,
                variant: variant,
                identityKey: identityKey
            )
            let programmingScore = programmingPreferenceScore(
                analysis: analysis,
                profile: trainingProfile,
                sessionCount: sessionCount
            )
            return ExerciseCandidate(
                exercise: exercise,
                analysis: analysis,
                identityKey: identityKey,
                history: exerciseHistory,
                muscleContributions: MuscleMappingEngine.contributions(
                    for: exercise.name,
                    manualMappings: manualContributionMap
                ),
                plannedSetCount: setBudget(
                    profile: trainingProfile,
                    analysis: analysis,
                    effort: appliedEffort,
                    allowsHardSetBoost: false
                ),
                score: focusScore + muscleMatch + due + continuity +
                    variantScore + programmingScore + (exercise.isFavorite ? 5 : 0) -
                    recentPenalty - sameWeekPenalty
            )
        }
        let canonicalCandidates = Dictionary(grouping: candidates, by: \.identityKey)
            .values
            .compactMap { equivalents in
                equivalents.sorted { left, right in
                    if left.score != right.score { return left.score > right.score }
                    let comparison = left.exercise.name.localizedCaseInsensitiveCompare(right.exercise.name)
                    if comparison != .orderedSame { return comparison == .orderedAscending }
                    return left.exercise.id.uuidString < right.exercise.id.uuidString
                }.first
            }

        let selected = selectBalancedExercises(
            candidates: canonicalCandidates,
            focus: focus,
            variant: variant,
            targetMuscles: targetMuscles,
            targetExerciseCount: targetExerciseCount,
            targetSessionSetBudget: targetSessionSetBudget,
            history: usableHistory,
            weeklyVolume: weeklyVolume,
            now: now,
            calendar: calendar
        )
        var hardCompoundBoosts = 0
        var plannedExercises = selected.map { candidate -> SmartWorkoutExercise in
            let mayBoostHardCompound = appliedEffort == .hard &&
                isCompound(candidate.analysis) &&
                Set(candidate.history.map(\.workoutID)).count >= 2 &&
                hardCompoundBoosts < 2
            if mayBoostHardCompound { hardCompoundBoosts += 1 }
            return SmartWorkoutExercise(
                exercise: candidate.exercise,
                recommendation: buildForExercise(
                    exerciseID: candidate.exercise.id,
                    history: candidate.history,
                    exerciseCatalogKey: candidate.exercise.catalogKey,
                    exerciseName: candidate.exercise.name,
                    machineLoadProfile: candidate.exercise.machineLoadProfile,
                    trainingProfile: trainingProfile,
                    effort: appliedEffort,
                    allowsHardSetBoost: mayBoostHardCompound,
                    now: now,
                    calendar: calendar
                )
            )
        }
        let mayApplyEasyFeedback = requestedEffort == .auto &&
            appliedEffort == .standard &&
            effortResolution.adjustment == nil &&
            !plannedExercises.contains {
                $0.recommendation.kind == .deload || $0.recommendation.kind == .comeback
            } &&
            recentLatestFeedback(
                latestFeedback,
                history: usableHistory,
                now: now,
                calendar: calendar
            ) == .easy
        let setCountBeforeEasyFeedback = plannedExercises.reduce(0) {
            $0 + $1.recommendation.sets.count
        }
        if mayApplyEasyFeedback {
            plannedExercises = addingOneSafeSetIfPossible(to: plannedExercises)
        }
        let easyFeedbackApplied = plannedExercises.reduce(0) {
            $0 + $1.recommendation.sets.count
        } == setCountBeforeEasyFeedback + 1
        plannedExercises = enforcingSmartPlanCaps(on: plannedExercises)
        return SmartWorkoutPlan(
            focus: focus,
            exercises: plannedExercises,
            variant: variant,
            requestedEffort: requestedEffort,
            appliedEffort: appliedEffort,
            effortAdjustment: easyFeedbackApplied
                ? .feedbackEasyExtraSet
                : effortResolution.adjustment
        )
    }

    public static func findAlternatives(
        currentExercise: Exercise,
        selectedExerciseIDs: Set<UUID>,
        exercises: [Exercise],
        history: [ExerciseHistoryEntry],
        muscleMappings: [ExerciseMuscleMapping] = [],
        trainingProfile: TrainingProfile = TrainingProfile(),
        effort: SmartWorkoutEffort = .standard,
        allowsHardSetBoost: Bool = true,
        limit: Int = 5,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SmartWorkoutAlternative] {
        let boundedLimit = min(6, max(0, limit))
        guard boundedLimit > 0,
              isUsableExercise(currentExercise),
              canonicalCatalogKey(
                  catalogKey: currentExercise.catalogKey,
                  name: currentExercise.name
              ) != "warm_up" else { return [] }

        let safeExercises = Array(exercises.prefix(maximumExerciseCount)).filter(isUsableExercise)
        let currentIdentity = exerciseIdentityKey(currentExercise)
        let currentAnalysis = analyzeExercise(
            currentExercise.name,
            catalogKey: currentExercise.catalogKey
        )
        let selectedIdentities = Set(safeExercises.compactMap { exercise in
            selectedExerciseIDs.contains(exercise.id) ? exerciseIdentityKey(exercise) : nil
        })
        let manualContributionMap = MuscleMappingEngine.manualContributionMap(from: muscleMappings)
        let currentContributions = MuscleMappingEngine.contributions(
            for: currentExercise.name,
            manualMappings: manualContributionMap
        )
        let usableHistory = history
            .prefix(maximumHistorySetCount)
            .filter {
                isUsableHistoryEntry($0, now: now) && $0.sessionDate <= now
            }
        let historyByIdentity = Dictionary(grouping: usableHistory, by: entryIdentityKey)
        let currentIsTrunk = currentAnalysis.role == .core ||
            currentIdentity == "catalog:hyperextension" ||
            currentIdentity == "catalog:side_hyperextension"

        var seenIdentities = Set<String>()
        let scored = safeExercises.compactMap { candidate -> (Exercise, Double, ExerciseAnalysis, String)? in
            let identity = exerciseIdentityKey(candidate)
            guard candidate.id != currentExercise.id,
                  identity != currentIdentity,
                  !selectedExerciseIDs.contains(candidate.id),
                  !selectedIdentities.contains(identity),
                  seenIdentities.insert(identity).inserted,
                  canonicalCatalogKey(catalogKey: candidate.catalogKey, name: candidate.name) != "warm_up"
            else { return nil }

            let analysis = analyzeExercise(candidate.name, catalogKey: candidate.catalogKey)
            let candidateIsTrunk = analysis.role == .core ||
                identity == "catalog:hyperextension" || identity == "catalog:side_hyperextension"
            guard currentIsTrunk == candidateIsTrunk else { return nil }
            guard isCompound(currentAnalysis) == isCompound(analysis) else { return nil }

            let meaningfulCurrentPatterns = currentAnalysis.patterns.subtracting([.accessory])
            if !meaningfulCurrentPatterns.isEmpty,
               analysis.patterns.isDisjoint(with: meaningfulCurrentPatterns) {
                return nil
            }
            if currentAnalysis.loadMode == .assistance, analysis.loadMode != .assistance {
                return nil
            }

            let candidateContributions = MuscleMappingEngine.contributions(
                for: candidate.name,
                manualMappings: manualContributionMap
            )
            let muscleSimilarity = weightedMuscleSimilarity(
                currentContributions,
                candidateContributions
            )
            guard muscleSimilarity >= 0.25 ||
                    !currentAnalysis.muscles.isDisjoint(with: analysis.muscles)
            else { return nil }

            let movementScore = Double(
                currentAnalysis.patterns.intersection(analysis.patterns).count
            ) * 100
            let roleScore = currentAnalysis.role == analysis.role ? 32.0 : 20.0
            let categoryScore = currentAnalysis.category == analysis.category ? 28.0 : 0.0
            let loadModeScore = currentAnalysis.loadMode == analysis.loadMode ? 22.0 : 0.0
            let equipmentScore: Double
            if currentAnalysis.equipment == analysis.equipment {
                equipmentScore = 18
            } else if Set([currentAnalysis.equipment, analysis.equipment]) ==
                        Set([EquipmentKind.barbell, .dumbbell]) {
                equipmentScore = 12
            } else {
                equipmentScore = 0
            }
            let familiarity = Double(min(
                4,
                Set(historyByIdentity[identity, default: []].map(\.workoutID)).count
            )) * 3
            let favoriteBonus = candidate.isFavorite ? 5.0 : 0.0
            return (
                candidate,
                movementScore + muscleSimilarity * 80 + roleScore + categoryScore +
                    loadModeScore + equipmentScore + familiarity + favoriteBonus,
                analysis,
                identity
            )
        }.sorted { left, right in
            if left.1 != right.1 { return left.1 > right.1 }
            let comparison = left.0.name.localizedCaseInsensitiveCompare(right.0.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return left.0.id.uuidString < right.0.id.uuidString
        }

        let appliedEffort = effort == .auto ? .standard : effort
        return scored.prefix(boundedLimit).map { candidate, _, _, identity in
            SmartWorkoutAlternative(
                exercise: candidate,
                recommendation: buildForExercise(
                    exerciseID: candidate.id,
                    history: historyByIdentity[identity, default: []],
                    exerciseCatalogKey: candidate.catalogKey,
                    exerciseName: candidate.name,
                    machineLoadProfile: candidate.machineLoadProfile,
                    trainingProfile: trainingProfile,
                    effort: appliedEffort,
                    allowsHardSetBoost: allowsHardSetBoost,
                    now: now,
                    calendar: calendar
                )
            )
        }
    }

    private static func weightedMuscleSimilarity(
        _ left: [MuscleContribution],
        _ right: [MuscleContribution]
    ) -> Double {
        let leftMap = Dictionary(uniqueKeysWithValues: left.map { ($0.muscleID, min(1, max(0, $0.weight))) })
        let rightMap = Dictionary(uniqueKeysWithValues: right.map { ($0.muscleID, min(1, max(0, $0.weight))) })
        let keys = Set(leftMap.keys).union(rightMap.keys)
        let intersection = keys.reduce(0.0) { $0 + min(leftMap[$1, default: 0], rightMap[$1, default: 0]) }
        let union = keys.reduce(0.0) { $0 + max(leftMap[$1, default: 0], rightMap[$1, default: 0]) }
        return union > 0 ? intersection / union : 0
    }

    private enum LoadAdjustment {
        case harder
        case easier(multiplier: Double)
        case hold
    }

    private static func effectiveLoadDirection(
        machineLoadProfile: MachineLoadProfile?,
        loadMode: ExerciseLoadMode
    ) -> MachineLoadDirection {
        machineLoadProfile?.direction ?? (loadMode == .assistance ? .lowerIsHarder : .higherIsHarder)
    }

    private static func adjustedWeight(
        _ baseline: Double,
        adjustment: LoadAdjustment,
        machineLoadProfile: MachineLoadProfile?,
        loadDirection: MachineLoadDirection
    ) -> Double {
        if let machineLoadProfile {
            let values = machineLoadProfile.allowedWeightsKg
            switch adjustment {
            case .hold:
                return values.min {
                    let leftDistance = abs($0 - baseline)
                    let rightDistance = abs($1 - baseline)
                    return leftDistance == rightDistance ? $0 < $1 : leftDistance < rightDistance
                } ?? baseline
            case .harder:
                if loadDirection == .higherIsHarder {
                    return values.first(where: { $0 > baseline }) ?? values.last ?? baseline
                }
                return values.last(where: { $0 < baseline }) ?? values.first ?? baseline
            case .easier:
                if loadDirection == .higherIsHarder {
                    return values.last(where: { $0 < baseline }) ?? values.first ?? baseline
                }
                return values.first(where: { $0 > baseline }) ?? values.last ?? baseline
            }
        }

        guard baseline > 0 else { return baseline }
        switch adjustment {
        case .hold:
            return nearestFallbackGridWeight(baseline)
        case .harder:
            return loadDirection == .lowerIsHarder
                ? previousFallbackGridWeight(baseline)
                : nextFallbackGridWeight(baseline)
        case let .easier(multiplier):
            if loadDirection == .lowerIsHarder {
                return nextFallbackGridWeight(baseline)
            }
            let desired = nearestFallbackGridWeight(baseline * multiplier)
            return desired < baseline ? desired : previousFallbackGridWeight(baseline)
        }
    }

    private static func easedWeight(
        _ baseline: Double,
        multiplier: Double,
        machineLoadProfile: MachineLoadProfile?,
        loadDirection: MachineLoadDirection
    ) -> Double {
        guard baseline > 0, multiplier.isFinite else { return max(0, baseline) }
        let boundedMultiplier = min(0.99, max(0.5, multiplier))
        let desired = loadDirection == .higherIsHarder
            ? baseline * boundedMultiplier
            : baseline / boundedMultiplier

        if let machineLoadProfile {
            let values = machineLoadProfile.allowedWeightsKg
            if loadDirection == .higherIsHarder {
                return values.last(where: { $0 <= desired && $0 < baseline })
                    ?? values.first(where: { $0 < baseline })
                    ?? values.first
                    ?? baseline
            }
            return values.first(where: { $0 >= desired && $0 > baseline })
                ?? values.last(where: { $0 > baseline })
                ?? values.last
                ?? baseline
        }

        if loadDirection == .higherIsHarder {
            let snapped = max(0, floor(desired / fallbackWeightGrid) * fallbackWeightGrid)
            return snapped < baseline ? snapped : previousFallbackGridWeight(baseline)
        }
        let snapped = min(
            maximumSupportedWeight,
            ceil(desired / fallbackWeightGrid) * fallbackWeightGrid
        )
        return snapped > baseline ? snapped : nextFallbackGridWeight(baseline)
    }

    private static let fallbackWeightGrid = 2.5

    private static func nearestFallbackGridWeight(_ weight: Double) -> Double {
        max(0, (weight / fallbackWeightGrid).rounded() * fallbackWeightGrid)
    }

    private static func nextFallbackGridWeight(_ weight: Double) -> Double {
        let nextIndex = floor(weight / fallbackWeightGrid) + 1
        return min(maximumSupportedWeight, nextIndex * fallbackWeightGrid)
    }

    private static func previousFallbackGridWeight(_ weight: Double) -> Double {
        let previousIndex = ceil(weight / fallbackWeightGrid) - 1
        return max(0, previousIndex * fallbackWeightGrid)
    }

    private static func harderWeightAvailable(
        machineLoadProfile: MachineLoadProfile?,
        loadDirection: MachineLoadDirection,
        baselineSets: [ExerciseHistoryEntry]
    ) -> Bool {
        guard let machineLoadProfile else { return true }
        return baselineSets.contains { baseline in
            if loadDirection == .higherIsHarder {
                return machineLoadProfile.allowedWeightsKg.contains { $0 > baseline.weight }
            }
            return machineLoadProfile.allowedWeightsKg.contains { $0 < baseline.weight }
        }
    }

    private static func goalRepRange(
        _ profile: TrainingProfile,
        analysis: ExerciseAnalysis?
    ) -> ClosedRange<Int> {
        let role = analysis?.role ?? .isolation
        switch profile.goal {
        case .strength:
            return switch role {
            case .primary: 4 ... 6
            case .secondary: 5 ... 8
            case .isolation, .core, .warmup: 8 ... 10
            }
        case .muscleGain:
            return switch role {
            case .primary: 6 ... 8
            case .secondary: 7 ... 10
            case .isolation, .core, .warmup: 8 ... 10
            }
        case .aestheticFatLoss:
            return switch role {
            case .primary: 6 ... 8
            case .secondary: 7 ... 10
            case .isolation, .core, .warmup: 8 ... 10
            }
        case .balanced:
            return switch role {
            case .primary: 5 ... 8
            case .secondary: 6 ... 10
            case .isolation, .core, .warmup: 8 ... 10
            }
        }
    }

    private static func defaultTargetReps(
        _ profile: TrainingProfile,
        analysis: ExerciseAnalysis?,
        repRange: ClosedRange<Int>
    ) -> Int {
        let role = analysis?.role ?? .isolation
        let target: Int
        switch profile.goal {
        case .strength:
            target = switch role {
            case .primary: 5
            case .secondary: 6
            case .isolation, .core, .warmup: 8
            }
        case .muscleGain, .aestheticFatLoss:
            target = switch role {
            case .primary: 8
            case .secondary: 9
            case .isolation, .core, .warmup: 10
            }
        case .balanced:
            target = switch role {
            case .primary: 7
            case .secondary: 8
            case .isolation, .core, .warmup: 10
            }
        }
        return min(repRange.upperBound, max(repRange.lowerBound, target))
    }

    private static func isCompound(_ analysis: ExerciseAnalysis?) -> Bool {
        guard let analysis else { return false }
        return analysis.role == .primary || analysis.role == .secondary
    }

    static func restDurationSeconds(
        exerciseCatalogKey: String?,
        exerciseName: String
    ) -> Int {
        switch analyzeExercise(exerciseName, catalogKey: exerciseCatalogKey).role {
        case .primary: 180
        case .secondary: 120
        case .isolation, .core, .warmup: 75
        }
    }

    private static func setBudget(
        profile: TrainingProfile,
        analysis: ExerciseAnalysis?,
        effort: SmartWorkoutEffort = .standard,
        allowsHardSetBoost: Bool = true
    ) -> Int {
        if effort == .recovery { return 3 }
        if effort == .hard {
            return isCompound(analysis) && allowsHardSetBoost ? 4 : 3
        }
        let highFrequency = profile.workoutsPerWeek >= 5
        let recoveryLimited = profile.calorieMode == .deficit
        return analysis?.role == .primary && !highFrequency && !recoveryLimited ? 4 : 3
    }

    private static func targetExerciseCount(
        profile: TrainingProfile,
        effort: SmartWorkoutEffort = .standard,
        sessionSetBudget: Int? = nil
    ) -> Int {
        let budget = sessionSetBudget ?? targetSessionSetBudget(
            profile: profile,
            effort: effort
        )
        // Every selected exercise receives at least three working sets. Do not
        // round a partial three-set slot up into another exercise; that can make
        // a higher-frequency plan contain more exercises when primary movements
        // switch from four sets to three. This also matches the PWA budget rule.
        return min(8, max(4, budget / 3))
    }

    /// A bounded per-session budget keeps low-frequency sessions useful without producing
    /// 30-set marathons. Calories shift optional volume only; every selected movement still
    /// receives at least three working sets through `setBudget`.
    static func targetSessionSetBudget(
        profile: TrainingProfile,
        effort: SmartWorkoutEffort = .standard
    ) -> Int {
        let frequencyBase: Int = switch min(6, max(2, profile.workoutsPerWeek)) {
        case 2: 24
        case 3: 21
        case 4: 18
        case 5: 16
        default: 15
        }
        let goalAdjustment: Int = switch profile.goal {
        case .muscleGain: 2
        case .strength, .balanced: 0
        case .aestheticFatLoss: -1
        }
        let calorieAdjustment: Int = switch profile.calorieMode {
        case .deficit: -3
        case .maintenance: 0
        case .surplus: 3
        }
        let effortAdjustment: Int = switch effort {
        case .recovery: -5
        case .hard: 2
        case .auto, .standard: 0
        }
        return min(24, max(12, frequencyBase + goalAdjustment + calorieAdjustment + effortAdjustment))
    }

    private static func programmingPreferenceScore(
        analysis: ExerciseAnalysis,
        profile: TrainingProfile,
        sessionCount: Int
    ) -> Double {
        let compound = isCompound(analysis)
        var score: Double
        switch profile.goal {
        case .strength: score = compound ? 24 : -8
        case .muscleGain: score = compound ? 14 : 6
        case .aestheticFatLoss: score = compound ? 8 : 2
        case .balanced: score = compound ? 10 : 4
        }
        if profile.calorieMode == .deficit {
            score += sessionCount > 0 ? 10 : -6
        } else if profile.calorieMode == .surplus, compound {
            score += 4
        }
        return score
    }

    private static func completedAtRepCeiling(
        _ session: ExerciseSessionSnapshot?,
        targetSetCount: Int,
        repCeiling: Int
    ) -> Bool {
        guard let session, session.sets.count >= targetSetCount else { return false }
        return session.sets.prefix(targetSetCount).allSatisfy { $0.reps >= repCeiling }
    }

    private static func performanceDidNotDecline(
        latest: ExerciseSessionSnapshot,
        previous: ExerciseSessionSnapshot?,
        targetSetCount: Int,
        loadDirection: MachineLoadDirection
    ) -> Bool {
        guard let previous,
              latest.sets.count >= targetSetCount,
              previous.sets.count >= targetSetCount else { return false }
        let latestSets = latest.sets.prefix(targetSetCount)
        let previousSets = previous.sets.prefix(targetSetCount)
        let latestAverageWeight = latestSets.map(\.weight).reduce(0, +) / Double(targetSetCount)
        let previousAverageWeight = previousSets.map(\.weight).reduce(0, +) / Double(targetSetCount)
        let latestAverageReps = Double(latestSets.map(\.reps).reduce(0, +)) / Double(targetSetCount)
        let previousAverageReps = Double(previousSets.map(\.reps).reduce(0, +)) / Double(targetSetCount)
        let weightDidNotDecline = loadDirection == .lowerIsHarder
            ? latestAverageWeight <= previousAverageWeight
            : latestAverageWeight >= previousAverageWeight
        return weightDidNotDecline && latestAverageReps >= previousAverageReps
    }

    private static func resizedBaselineSets(
        _ sets: [ExerciseHistoryEntry],
        targetCount: Int
    ) -> [ExerciseHistoryEntry] {
        guard let finalSet = sets.last else { return [] }
        if targetCount <= sets.count {
            return Array(sets.prefix(targetCount))
        }
        return sets + Array(repeating: finalSet, count: targetCount - sets.count)
    }

    private static func isComparableRegression(
        newer: ExerciseSessionSnapshot,
        older: ExerciseSessionSnapshot
    ) -> Bool {
        if older.maxWeight <= 0, newer.maxWeight <= 0 {
            return newer.averageReps < older.averageReps * 0.9
        }
        guard older.estimatedMax > 0, older.averageVolumePerSet > 0 else { return false }
        return newer.estimatedMax < older.estimatedMax * 0.97 &&
            newer.averageVolumePerSet < older.averageVolumePerSet * 0.92
    }

    private static func isBodyweightRepRegression(
        newer: ExerciseSessionSnapshot,
        older: ExerciseSessionSnapshot
    ) -> Bool {
        newer.averageReps < older.averageReps * 0.9
    }

    private static func isAssistanceRegression(
        newer: ExerciseSessionSnapshot,
        older: ExerciseSessionSnapshot
    ) -> Bool {
        guard older.maxWeight > 0 else { return false }
        return newer.averageWeight > older.averageWeight * 1.03 &&
            newer.averageReps <= older.averageReps * 1.02
    }

    private static func isTruePlateau(_ sessions: [ExerciseSessionSnapshot]) -> Bool {
        guard sessions.count >= 4 else { return false }
        let latest = sessions[0]
        let oldest = sessions[sessions.count - 1]
        let estimatedMaxImproved = oldest.estimatedMax <= 0
            ? latest.estimatedMax > 0
            : latest.estimatedMax > oldest.estimatedMax * 1.015
        let averageRepsImproved = latest.averageReps > oldest.averageReps + 0.25
        let volumePerSetImproved = oldest.averageVolumePerSet <= 0
            ? latest.averageVolumePerSet > 0
            : latest.averageVolumePerSet > oldest.averageVolumePerSet * 1.02
        let maxWeights = sessions.map(\.maxWeight)
        let stableLoad = (maxWeights.max() ?? 0) - (maxWeights.min() ?? 0) <=
            max(1.25, oldest.maxWeight * 0.02)
        return stableLoad && !estimatedMaxImproved && !averageRepsImproved && !volumePerSetImproved
    }

    private static func canonicalCatalogKey(
        catalogKey: String?,
        name: String?
    ) -> String? {
        BuiltInExerciseCatalog.resolvedKey(
            catalogKey: catalogKey,
            name: name ?? ""
        )
    }

    private static func isUsableExercise(_ exercise: Exercise) -> Bool {
        let trimmedName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && exercise.name.utf8.count <= 640 &&
            exercise.name.unicodeScalars.count <= 160 &&
            !exercise.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func isUsableHistoryEntry(
        _ entry: ExerciseHistoryEntry,
        now: Date
    ) -> Bool {
        let trimmedName = entry.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return entry.weight.isFinite && entry.weight >= 0 && entry.weight <= maximumSupportedWeight &&
            entry.reps > 0 && entry.reps <= maximumSupportedReps &&
            entry.setOrderIndex >= 0 && entry.setOrderIndex < maximumSupportedSetCount &&
            !trimmedName.isEmpty && entry.exerciseName.utf8.count <= 640 &&
            entry.exerciseName.unicodeScalars.count <= 160 &&
            !entry.exerciseName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
            entry.sessionDate.timeIntervalSinceReferenceDate.isFinite &&
            entry.sessionDate >= minimumSupportedTimestamp &&
            entry.sessionDate <= now.addingTimeInterval(24 * 60 * 60)
    }

    private static func exerciseIdentityKey(_ exercise: Exercise) -> String {
        exerciseIdentityKey(name: exercise.name, catalogKey: exercise.catalogKey)
    }

    private static func exerciseIdentityKey(name: String, catalogKey: String?) -> String {
        if let catalogKey = canonicalCatalogKey(
            catalogKey: catalogKey,
            name: name
        ) {
            return "catalog:\(catalogKey)"
        }
        return "custom:\(MuscleMappingEngine.normalizeExerciseName(name))"
    }

    private static func entryIdentityKey(_ entry: ExerciseHistoryEntry) -> String {
        if let catalogKey = canonicalCatalogKey(
            catalogKey: entry.exerciseCatalogKey,
            name: entry.exerciseName
        ) {
            return "catalog:\(catalogKey)"
        }
        return "custom:\(MuscleMappingEngine.normalizeExerciseName(entry.exerciseName))"
    }

    private static func variantPreferenceScore(
        analysis: ExerciseAnalysis,
        focus: SmartWorkoutFocus,
        variant: SmartWorkoutVariant,
        identityKey: String
    ) -> Double {
        let slotCount = focus == .fullBody ? 3 : 2
        let variantIndex = min(variant.index, slotCount - 1)
        let bucketScore = rotationBucket(identityKey, modulo: slotCount) == variantIndex
            ? 10.0
            : 0.0
        let preferredPatterns = preferredPatterns(for: focus, variant: variant)
        let patternScore = Double(analysis.patterns.intersection(preferredPatterns).count) * 18
        return bucketScore + patternScore
    }

    private static func preferredPatterns(
        for focus: SmartWorkoutFocus,
        variant: SmartWorkoutVariant
    ) -> Set<MovementPattern> {
        switch focus {
        case .upper:
            return variant == .a
                ? [.horizontalPress, .horizontalPull]
                : [.verticalPress, .verticalPull]
        case .push:
            return variant == .a ? [.horizontalPress] : [.verticalPress]
        case .pull:
            return variant == .a ? [.horizontalPull] : [.verticalPull]
        case .lower, .legs:
            return variant == .a
                ? [.squat, .legPress]
                : [.hinge, .kneeFlexion]
        case .fullBody:
            switch variant {
            case .a: return [.horizontalPress, .horizontalPull, .squat]
            case .b: return [.verticalPress, .verticalPull, .hinge]
            case .c: return [.legPress, .kneeExtension, .calf, .core]
            }
        }
    }

    private static func rotationBucket(_ value: String, modulo: Int) -> Int {
        guard modulo > 1 else { return 0 }
        var hash: Int32 = 0
        for codeUnit in value.utf16 {
            hash = hash &* 31 &+ Int32(codeUnit)
        }
        let remainder = Int(hash % Int32(modulo))
        return remainder >= 0 ? remainder : remainder + modulo
    }

    private static func recommendedSetID(
        exerciseID: UUID,
        workoutID: UUID?,
        kind: WorkoutRecommendationKind,
        index: Int,
        weight: Double?,
        reps: Int
    ) -> UUID {
        let seed = [
            exerciseID.uuidString.lowercased(),
            workoutID?.uuidString.lowercased() ?? "new",
            kind.rawValue,
            String(index),
            weight.map { String($0.bitPattern) } ?? "nil",
            String(reps)
        ].joined(separator: "|")
        let first = stableHash(seed, seed: 0xcbf29ce484222325)
        let second = stableHash(seed, seed: 0x84222325cbf29ce4)
        var characters = Array(String(format: "%016llx%016llx", first, second))
        characters[12] = "4"
        characters[16] = ["8", "9", "a", "b"][Int(second & 3)]
        let raw = String(characters)
        let firstGroup = String(raw.prefix(8))
        let secondGroup = String(raw.dropFirst(8).prefix(4))
        let thirdGroup = String(raw.dropFirst(12).prefix(4))
        let fourthGroup = String(raw.dropFirst(16).prefix(4))
        let fifthGroup = String(raw.dropFirst(20).prefix(12))
        let uuidString = firstGroup + "-" + secondGroup + "-" + thirdGroup + "-" +
            fourthGroup + "-" + fifthGroup
        return UUID(uuidString: uuidString) ?? exerciseID
    }

    private static func stableHash(_ value: String, seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    private static func comebackMultiplier(_ days: Int) -> Double {
        if days >= 45 { return 0.82 }
        if days >= 30 { return 0.86 }
        return 0.9
    }

    private static func confidence(
        sessionCount: Int,
        lastSetCount: Int,
        daysSinceLastSession: Int,
        profile: TrainingProfile
    ) -> Float {
        let historyScore = Float(min(sessionCount, 6)) * 0.09
        let setScore = Float(min(lastSetCount, 4)) * 0.05
        let profileScore: Float = profile.workoutsPerWeek > 0 ? 0.06 : 0
        let penalty: Float = daysSinceLastSession >= 30 ? 0.18 :
            (daysSinceLastSession >= 14 ? 0.08 : 0)
        return min(0.94, max(0.25, 0.35 + historyScore + setScore + profileScore - penalty))
    }

    private static func resolveEffort(
        requested: SmartWorkoutEffort,
        targetMuscles: Set<String>,
        history: [ExerciseHistoryEntry],
        latestFeedback: WorkoutFeedbackContext?,
        now: Date,
        calendar: Calendar
    ) -> (effort: SmartWorkoutEffort, adjustment: SmartWorkoutEffortAdjustment?) {
        let sessions = sessionGroups(history)
        let latestSessionDays = sessions.first.map { calendar.gymDaysBetween($0.date, now) }
        let lastTrained = lastTrainedByMuscle(history)
        let recentlyTrainedTargets = targetMuscles.filter { muscle in
            guard let date = lastTrained[muscle] else { return false }
            return calendar.gymDaysBetween(date, now) <= 1
        }.count
        let recentRatio = targetMuscles.isEmpty
            ? 0
            : Double(recentlyTrainedTargets) / Double(targetMuscles.count)

        switch requested {
        case .auto:
            if recentLatestFeedback(
                latestFeedback,
                history: history,
                now: now,
                calendar: calendar
            ) == .hard {
                return (.recovery, .autoFeedbackRecovery)
            }
            return recentRatio >= 0.5
                ? (.recovery, .autoRecovery)
                : (.standard, nil)
        case .recovery:
            return (.recovery, nil)
        case .standard:
            return (.standard, nil)
        case .hard:
            guard sessions.count >= 2 else { return (.standard, .hardInsufficientHistory) }
            guard latestSessionDays.map({ $0 < comebackBreakDays }) ?? false else {
                return (.standard, .hardLongBreak)
            }
            guard recentRatio < 0.5 else { return (.standard, .hardTargetNotRecovered) }
            return (.hard, nil)
        }
    }

    public static func weeklyTrainingGuidance(
        history: [ExerciseHistoryEntry],
        trainingProfile: TrainingProfile = TrainingProfile(),
        latestFeedback: WorkoutFeedbackContext? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyTrainingGuidance {
        let usableHistory = history
            .prefix(maximumHistorySetCount)
            .filter {
                isUsableHistoryEntry($0, now: now) && $0.sessionDate <= now
            }
        let targetDays = min(6, max(2, trainingProfile.workoutsPerWeek))
        let weekStart = calendar.gymMondayStart(of: now)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        let completedDays = Set(usableHistory.lazy
            .filter { $0.sessionDate >= weekStart && $0.sessionDate < weekEnd }
            .map { calendar.gymEpochDay(for: $0.sessionDate) })
            .count

        if completedDays >= targetDays {
            return WeeklyTrainingGuidance(
                decision: .rest,
                completedTrainingDays: completedDays,
                targetTrainingDays: targetDays
            )
        }

        let feedbackRequiresRecovery = recentLatestFeedback(
            latestFeedback,
            history: usableHistory,
            now: now,
            calendar: calendar
        ) == .hard
        let focus = chooseWorkoutFocus(
            history: usableHistory,
            profile: trainingProfile,
            now: now,
            calendar: calendar
        )
        let focusMuscles = targetMuscles(for: focus)
        let lastTrained = lastTrainedByMuscle(usableHistory)
        let recentlyTrainedCount = focusMuscles.filter { muscle in
            guard let date = lastTrained[muscle] else { return false }
            return calendar.gymDaysBetween(date, now) <= 1
        }.count
        let recentRatio = focusMuscles.isEmpty
            ? 0
            : Double(recentlyTrainedCount) / Double(focusMuscles.count)
        return WeeklyTrainingGuidance(
            decision: feedbackRequiresRecovery || recentRatio >= 0.5 ? .recovery : .train,
            completedTrainingDays: completedDays,
            targetTrainingDays: targetDays
        )
    }

    private static func recentLatestFeedback(
        _ context: WorkoutFeedbackContext?,
        history: [ExerciseHistoryEntry],
        now: Date,
        calendar: Calendar
    ) -> WorkoutFeedback? {
        guard let context,
              let latestSession = sessionGroups(history).first,
              latestSession.id == context.workoutID,
              latestSession.date == context.sessionDate,
              latestSession.date <= now else {
            return nil
        }
        let ageDays = calendar.gymDaysBetween(latestSession.date, now)
        guard (0 ... 7).contains(ageDays) else { return nil }
        return context.feedback
    }

    private static func addingOneSafeSetIfPossible(
        to exercises: [SmartWorkoutExercise]
    ) -> [SmartWorkoutExercise] {
        guard exercises.reduce(0, { $0 + $1.recommendation.sets.count }) <
                maximumSmartPlanSetCount,
              let index = exercises.firstIndex(where: {
                  let recommendation = $0.recommendation
                  return recommendation.sets.count < 4 &&
                      !recommendation.sets.isEmpty &&
                      recommendation.kind != .deload &&
                      recommendation.kind != .comeback &&
                      !recommendation.reasons.contains(.recoverySession)
              }) else {
            return exercises
        }
        var result = exercises
        let item = result[index]
        let recommendation = item.recommendation
        guard let finalSet = recommendation.sets.last else { return exercises }
        let extraSet = RecommendedWorkoutSet(
            id: recommendedSetID(
                exerciseID: item.exercise.id,
                workoutID: nil,
                kind: recommendation.kind,
                index: recommendation.sets.count,
                weight: finalSet.weight,
                reps: finalSet.reps
            ),
            weight: finalSet.weight,
            reps: finalSet.reps
        )
        let boosted = WorkoutRecommendation(
            exerciseID: recommendation.exerciseID,
            sets: recommendation.sets + [extraSet],
            kind: recommendation.kind,
            confidence: recommendation.confidence,
            estimatedVolume: recommendation.estimatedVolume +
                ((extraSet.weight ?? 0) * Double(extraSet.reps)),
            daysSinceLastSession: recommendation.daysSinceLastSession,
            reasons: recommendation.reasons
        )
        result[index] = SmartWorkoutExercise(
            exercise: item.exercise,
            recommendation: boosted
        )
        return result
    }

    private static func enforcingSmartPlanCaps(
        on exercises: [SmartWorkoutExercise]
    ) -> [SmartWorkoutExercise] {
        let exerciseCap = 8
        let preservedTrunk = exercises.last.map { item -> Bool in
            let analysis = analyzeExercise(
                item.exercise.name,
                catalogKey: item.exercise.catalogKey
            )
            return analysis.role == .core || isHyperextensionHistoryName(
                item.exercise.name,
                catalogKey: item.exercise.catalogKey
            )
        } == true
        let source: [SmartWorkoutExercise]
        if preservedTrunk, exercises.count > exerciseCap, let trunk = exercises.last {
            source = Array(exercises.prefix(exerciseCap - 1)) + [trunk]
        } else {
            source = Array(exercises.prefix(exerciseCap))
        }
        var remainingSets = maximumSmartPlanSetCount
        var bounded: [SmartWorkoutExercise] = []
        bounded.reserveCapacity(source.count)
        for (index, item) in source.enumerated() {
            let remainingExerciseMinimum = (source.count - index - 1) * 3
            let availableForCurrent = remainingSets - remainingExerciseMinimum
            guard availableForCurrent >= 3 else { break }
            let retainedSets = Array(item.recommendation.sets.prefix(
                min(4, availableForCurrent)
            ))
            guard retainedSets.count >= 3 else { continue }
            let recommendation = item.recommendation
            let retainedVolume = retainedSets.reduce(0) {
                $0 + (($1.weight ?? 0) * Double($1.reps))
            }
            bounded.append(SmartWorkoutExercise(
                exercise: item.exercise,
                recommendation: WorkoutRecommendation(
                    exerciseID: recommendation.exerciseID,
                    sets: retainedSets,
                    kind: recommendation.kind,
                    confidence: recommendation.confidence,
                    estimatedVolume: retainedVolume,
                    daysSinceLastSession: recommendation.daysSinceLastSession,
                    reasons: recommendation.reasons
                )
            ))
            remainingSets -= retainedSets.count
        }
        return bounded
    }

    private static func isHyperextensionHistoryName(
        _ name: String,
        catalogKey: String?
    ) -> Bool {
        let key = canonicalCatalogKey(catalogKey: catalogKey, name: name)
        return key == "hyperextension" || key == "side_hyperextension"
    }

    private static func chooseWorkoutFocus(
        history: [ExerciseHistoryEntry],
        profile: TrainingProfile,
        now: Date,
        calendar: Calendar
    ) -> SmartWorkoutFocus {
        if profile.workoutsPerWeek <= 2 { return .fullBody }
        guard !history.isEmpty else {
            switch profile.split {
            case .upperLower: return .upper
            case .fullBody, .custom: return .fullBody
            case .pushPullLegs: return .push
            }
        }
        let sessions = sessionGroups(history)
        guard !sessions.isEmpty else { return .upper }

        switch profile.split {
        case .upperLower:
            if let latestRecognized = sessions
                .map({ dominantFocus($0.entries) })
                .first(where: { $0.isUpperDay || $0.isLowerDay }) {
                return latestRecognized.isLowerDay ? .upper : .lower
            }
            let thisWeek = sessions.filter { calendar.gymDaysBetween($0.date, now) <= 6 }
            let upperCount = thisWeek.filter { dominantFocus($0.entries).isUpperDay }.count
            let lowerCount = thisWeek.filter { dominantFocus($0.entries).isLowerDay }.count
            return lowerCount < upperCount ? .lower : .upper
        case .pushPullLegs:
            let latestFocus = sessions
                .map { dominantFocus($0.entries) }
                .first { $0 == .push || $0 == .pull || $0.isLowerDay }
            switch latestFocus {
            case .push: return .pull
            case .pull: return .legs
            case .legs, .lower: return .push
            case .upper, .fullBody, .none: return chooseMostNeglectedFocus(history)
            }
        case .fullBody:
            return .fullBody
        case .custom:
            return chooseMostNeglectedFocus(history)
        }
    }

    private static func nextVariant(
        focus: SmartWorkoutFocus,
        history: [ExerciseHistoryEntry]
    ) -> SmartWorkoutVariant {
        let sessions = sessionGroups(history)
        let modulo: Int
        let completedCount: Int
        if focus == .fullBody {
            modulo = 3
            completedCount = sessions.count
        } else {
            modulo = 2
            completedCount = sessions.filter {
                let completedFocus = dominantFocus($0.entries)
                switch focus {
                case .upper: return completedFocus.isUpperDay
                case .lower, .legs: return completedFocus.isLowerDay
                case .push: return completedFocus == .push
                case .pull: return completedFocus == .pull
                case .fullBody: return completedFocus == .fullBody
                }
            }.count
        }
        switch completedCount % modulo {
        case 1: return .b
        case 2: return .c
        default: return .a
        }
    }

    private static func analyzeExercise(
        _ name: String,
        catalogKey: String? = nil
    ) -> ExerciseAnalysis {
        let resolvedCatalogKey = canonicalCatalogKey(catalogKey: catalogKey, name: name)
        let definition = BuiltInExerciseCatalog.definition(forKey: resolvedCatalogKey)
        let value = MuscleMappingEngine.normalizeExerciseName(definition?.englishName ?? name)
        var muscles = Set<String>()
        var patterns = Set<MovementPattern>()
        func has(_ tokens: String...) -> Bool { tokens.contains { value.contains($0) } }
        func add(_ ids: String...) { muscles.formUnion(ids) }
        func pattern(_ values: MovementPattern...) { patterns.formUnion(values) }

        if let definition {
            muscles.formUnion(definition.muscleIDs)
            if let programming = builtInProgramming[definition.key] {
                return ExerciseAnalysis(
                    category: programming.category,
                    muscles: muscles,
                    patterns: programming.patterns,
                    role: programming.role,
                    loadMode: programming.loadMode,
                    equipment: builtInEquipment[definition.key] ?? programming.equipment
                )
            }
        }

        if has("жим ног", "leg press") { add("quads", "glutes", "hamstrings"); pattern(.legPress) }
        if has("прис", "присед", "squat", "випад", "выпад", "lunge") { add("quads", "glutes", "hamstrings"); pattern(.squat) }
        if has("румун", "румын", "станов", "становая", "deadlift") { add("hamstrings", "glutes", "lowerBack", "upperBack"); pattern(.hinge) }
        if has("згинання ніг", "згибання ніг", "сгибание ног", "leg curl") { add("hamstrings"); pattern(.kneeFlexion) }
        if has("розгинання ніг", "разгибание ног", "leg extension") { add("quads"); pattern(.kneeExtension) }
        if has("сідниц", "ягодиц", "glute", "hip thrust", "місток", "мостик") { add("glutes", "hamstrings"); pattern(.hinge) }
        if has("икр", "ікр", "calf", "носок", "носки") { add("calves"); pattern(.calf) }
        if has("зведення ніг", "сведение ног", "adductor") { add("adductors") }
        if has("розведення ніг", "разведение ног", "hip abduction", "abductor") { add("glutes") }

        if has("жим", "press", "bench", "віджим", "отжим", "push up", "dips", "брусь") && !has("ног", "leg press") {
            add("chest", "triceps", "shoulders")
            has("сидя", "сидячи", "над голов", "overhead", "shoulder")
                ? pattern(.verticalPress)
                : pattern(.horizontalPress)
        }
        if has("груд", "груди", "chest", "метелик", "pec deck", "зведення рук", "сведение рук", "fly", "flies") { add("chest", "shoulders") }
        if has("плеч", "дельт", "махи", "розведення", "разведение", "lateral raise", "rear delt", "shoulder", "overhead", "над голов") { add("shoulders"); pattern(.verticalPress) }
        if has("трицепс", "tricep", "француз", "розгинання рук", "разгибание рук", "pushdown", "гантеля над голов", "гантель над голов") { add("triceps") }

        if has("підтяг", "подтяг", "pull up", "pullup", "pulldown", "верхній блок", "верхний блок", "журавель") { add("lats", "upperBack", "biceps"); pattern(.verticalPull) }
        if has("face pull", "тяга каната до обличчя", "тяга каната к лицу") {
            add("shoulders", "upperBack")
            pattern(.horizontalPull)
        }
        if has("тяга", "row") && !has("румун", "румын", "станов", "становая", "deadlift", "підборід", "подбород") { add("lats", "upperBack", "biceps"); pattern(.horizontalPull) }
        if has("спин", "спина", "back") { add("lats", "upperBack") }
        if has("біцепс", "бицепс", "bicep", "curl", "згинання рук", "сгибание рук") { add("biceps", "forearms") }
        if has("передпліч", "предплеч", "forearm") { add("forearms") }

        if has("прес", "abs", "crunch", "скруч", "планка", "plank", "leg raise") { add("abs"); pattern(.core) }
        if has("нахил", "наклон", "сторони", "стороны", "oblique", "rotation", "twist") { add("obliques") }
        if has("гіперекстензі", "гиперэкстенз", "hyperextension") { add("lowerBack", "glutes", "hamstrings"); pattern(.hinge) }

        let classificationMuscles = Set(definition?.muscleIDs ?? Array(muscles))
        let lowerCount = classificationMuscles.intersection(lowerMuscles).count
        let pushCount = classificationMuscles.intersection(pushMuscles).count
        let pullCount = classificationMuscles.intersection(pullMuscles).count
        let hasPullPattern = patterns.contains(.horizontalPull) || patterns.contains(.verticalPull)
        let hasPressPattern = patterns.contains(.horizontalPress) || patterns.contains(.verticalPress)
        let category: SmartWorkoutFocus
        if resolvedCatalogKey == "warm_up" {
            category = .fullBody
        } else if !patterns.isDisjoint(with: lowerMovementPatterns) ||
                    lowerCount > max(pushCount, pullCount) {
            category = .legs
        } else if hasPullPattern && !hasPressPattern {
            category = .pull
        } else if hasPressPattern {
            category = .push
        } else if pullCount > pushCount {
            category = .pull
        } else if pushCount > pullCount {
            category = .push
        } else {
            category = .fullBody
        }
        if patterns.isEmpty { patterns.insert(.accessory) }
        let role: ExerciseRole = patterns.isDisjoint(with: compoundMovementPatterns)
            ? .isolation
            : .secondary
        return ExerciseAnalysis(
            category: category,
            muscles: muscles,
            patterns: patterns,
            role: role,
            loadMode: .standard,
            equipment: .other
        )
    }

    private static func isEligible(_ analysis: ExerciseAnalysis, for focus: SmartWorkoutFocus) -> Bool {
        switch focus {
        case .upper: return upperFocuses.contains(analysis.category)
        case .lower, .legs:
            return lowerFocuses.contains(analysis.category) ||
                !analysis.muscles.isDisjoint(with: coreMuscles)
        case .push: return analysis.category == .push
        case .pull: return analysis.category == .pull
        case .fullBody: return true
        }
    }

    private static func selectBalancedExercises(
        candidates: [ExerciseCandidate],
        focus: SmartWorkoutFocus,
        variant: SmartWorkoutVariant,
        targetMuscles: Set<String>,
        targetExerciseCount: Int,
        targetSessionSetBudget: Int,
        history: [ExerciseHistoryEntry],
        weeklyVolume: WeeklyVolumeState,
        now: Date,
        calendar: Calendar
    ) -> [ExerciseCandidate] {
        var selected: [ExerciseCandidate] = []
        var covered = Set<String>()
        var projectedWeeklyVolume = weeklyVolume
        let lastTrained = lastTrainedByMuscle(history)
        let eligible = candidates.filter { isEligible($0.analysis, for: focus) }
        var remaining = eligible.isEmpty && focus != .lower && focus != .legs
            ? candidates
            : eligible

        if focus == .lower || focus == .legs {
            selectRequiredPattern(
                remaining: &remaining,
                selected: &selected,
                covered: &covered,
                patterns: [.squat, .legPress],
                weeklyVolume: &projectedWeeklyVolume
            )
            selectRequiredPattern(
                remaining: &remaining,
                selected: &selected,
                covered: &covered,
                patterns: [.hinge, .kneeFlexion],
                weeklyVolume: &projectedWeeklyVolume
            )
        }

        if focus == .upper {
            for pattern in [
                MovementPattern.horizontalPress,
                .verticalPress,
                .horizontalPull,
                .verticalPull
            ] {
                selectRequiredPattern(
                    remaining: &remaining,
                    selected: &selected,
                    covered: &covered,
                    patterns: [pattern],
                    weeklyVolume: &projectedWeeklyVolume
                )
            }
        } else if focus == .push {
            for pattern in [MovementPattern.horizontalPress, .verticalPress] {
                selectRequiredPattern(
                    remaining: &remaining,
                    selected: &selected,
                    covered: &covered,
                    patterns: [pattern],
                    weeklyVolume: &projectedWeeklyVolume
                )
            }
        } else if focus == .pull {
            for pattern in [MovementPattern.horizontalPull, .verticalPull] {
                selectRequiredPattern(
                    remaining: &remaining,
                    selected: &selected,
                    covered: &covered,
                    patterns: [pattern],
                    weeklyVolume: &projectedWeeklyVolume
                )
            }
        }

        if focus == .fullBody {
            let variantPatterns = preferredPatterns(for: focus, variant: variant)
            for required in [SmartWorkoutFocus.push, .pull, .legs] {
                let categoryCandidates = remaining.filter {
                    $0.analysis.category == required && isCompound($0.analysis)
                }
                let variantCandidates = categoryCandidates.filter {
                    !$0.analysis.patterns.isDisjoint(with: variantPatterns)
                }
                let selectionPool = variantCandidates.isEmpty
                    ? categoryCandidates
                    : variantCandidates
                guard let best = selectionPool
                    .max(by: {
                        let leftScore = $0.score + programmingPriority($0.analysis) +
                            weeklyVolumeScore($0, state: projectedWeeklyVolume)
                        let rightScore = $1.score + programmingPriority($1.analysis) +
                            weeklyVolumeScore($1, state: projectedWeeklyVolume)
                        if leftScore != rightScore { return leftScore < rightScore }
                        return $0.exercise.name.localizedCaseInsensitiveCompare($1.exercise.name) == .orderedDescending
                    }) else { continue }
                selected.append(best)
                covered.formUnion(best.analysis.muscles)
                projectWeeklyVolume(best, into: &projectedWeeklyVolume)
                remaining.removeAll { $0.exercise.id == best.exercise.id }
            }
        }

        let coreLastPerformed = history
            .filter { isTrunkHistoryEntry($0) && !isHyperextensionHistoryEntry($0) }
            .map(\.sessionDate)
            .max() ?? .distantPast
        let hyperLastPerformed = history
            .filter(isHyperextensionHistoryEntry)
            .map(\.sessionDate)
            .max() ?? .distantPast
        let prefersHyperextension: Bool
        if hyperLastPerformed != coreLastPerformed {
            prefersHyperextension = hyperLastPerformed < coreLastPerformed
        } else {
            prefersHyperextension = variant == .b
        }

        // Reserve one direct trunk slot, but append it only after the working
        // movements so the generated order is compounds, accessories, trunk.
        let allTrunkCandidates = candidates.filter(isTrunkAccessory)
        remaining.removeAll(where: isTrunkAccessory)
        let workingExerciseTarget = allTrunkCandidates.isEmpty
            ? max(targetExerciseCount, selected.count)
            : max(selected.count, targetExerciseCount - 1)

        while selected.count < workingExerciseTarget, !remaining.isEmpty {
            let usedSetBudget = selected.reduce(0) { $0 + $1.plannedSetCount }
            let withinBudget = remaining.filter {
                usedSetBudget + $0.plannedSetCount <= targetSessionSetBudget
            }
            let belowWeeklyTargets = withinBudget.filter {
                !isWeeklyVolumeSaturated($0, state: projectedWeeklyVolume)
            }
            // Required movement patterns above are retained even when the week is saturated.
            // Optional filler stops once every safe candidate is already at its weekly target.
            let fillerCandidates = belowWeeklyTargets.isEmpty ? [] : belowWeeklyTargets
            let scored = fillerCandidates.map { candidate in
                (
                    candidate,
                    balancedScore(
                        candidate,
                        selected: selected,
                        covered: covered,
                        targets: targetMuscles,
                        lastTrained: lastTrained,
                        weeklyVolume: projectedWeeklyVolume,
                        now: now,
                        calendar: calendar
                    )
                )
            }
            guard let best = scored.max(by: {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                return $0.0.exercise.name.localizedCaseInsensitiveCompare($1.0.exercise.name) == .orderedDescending
            })?.0 else { break }
            selected.append(best)
            covered.formUnion(best.analysis.muscles)
            projectWeeklyVolume(best, into: &projectedWeeklyVolume)
            remaining.removeAll { $0.exercise.id == best.exercise.id }
        }

        let recentHyperextensionSessionCount = Set(history.filter {
            isHyperextensionHistoryEntry($0) &&
                calendar.gymDaysBetween($0.sessionDate, now) <= 6
        }.map(\.workoutID)).count
        let hasCompoundHinge = selected.contains {
            isCompound($0.analysis) && $0.analysis.patterns.contains(.hinge)
        }
        let safeTrunkCandidates = allTrunkCandidates.filter {
            !isHyperextension($0) ||
                (!hasCompoundHinge && recentHyperextensionSessionCount < 2)
        }
        if let trunk = safeTrunkCandidates.min(by: {
               let leftPreferred = isHyperextension($0) == prefersHyperextension
               let rightPreferred = isHyperextension($1) == prefersHyperextension
               if leftPreferred != rightPreferred { return leftPreferred }
               let leftWeeklyScore = weeklyVolumeScore($0, state: projectedWeeklyVolume)
               let rightWeeklyScore = weeklyVolumeScore($1, state: projectedWeeklyVolume)
               if leftWeeklyScore != rightWeeklyScore { return leftWeeklyScore > rightWeeklyScore }
               let leftDate = $0.history.map(\.sessionDate).max() ?? .distantPast
               let rightDate = $1.history.map(\.sessionDate).max() ?? .distantPast
               if leftDate != rightDate { return leftDate < rightDate }
               if $0.score != $1.score { return $0.score > $1.score }
               return $0.exercise.name.localizedCaseInsensitiveCompare($1.exercise.name) == .orderedDescending
           }) {
            selected.append(trunk)
        }

        let ordered = selected.enumerated().sorted { left, right in
            let leftTrunk = isTrunkAccessory(left.element)
            let rightTrunk = isTrunkAccessory(right.element)
            if leftTrunk != rightTrunk { return !leftTrunk }
            let leftPriority = programmingOrder(left.element.analysis)
            let rightPriority = programmingOrder(right.element.analysis)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            return left.offset < right.offset
        }.map(\.element)
        let finalCount = allTrunkCandidates.isEmpty
            ? targetExerciseCount
            : max(targetExerciseCount, selected.count)
        return Array(ordered.prefix(finalCount))
    }

    private static func isTrunkAccessory(_ candidate: ExerciseCandidate) -> Bool {
        candidate.analysis.role == .core || isHyperextension(candidate)
    }

    private static func isHyperextension(_ candidate: ExerciseCandidate) -> Bool {
        candidate.identityKey == "catalog:hyperextension" ||
            candidate.identityKey == "catalog:side_hyperextension"
    }

    private static func isTrunkHistoryEntry(_ entry: ExerciseHistoryEntry) -> Bool {
        if isHyperextensionHistoryEntry(entry) { return true }
        return analyzeExercise(entry.exerciseName, catalogKey: entry.exerciseCatalogKey).role == .core
    }

    private static func isHyperextensionHistoryEntry(_ entry: ExerciseHistoryEntry) -> Bool {
        let key = canonicalCatalogKey(
            catalogKey: entry.exerciseCatalogKey,
            name: entry.exerciseName
        )
        return key == "hyperextension" || key == "side_hyperextension"
    }

    private static func programmingPriority(_ analysis: ExerciseAnalysis) -> Double {
        switch analysis.role {
        case .primary: return 28
        case .secondary: return 14
        case .isolation, .core, .warmup: return 0
        }
    }

    private static func programmingOrder(_ analysis: ExerciseAnalysis) -> Int {
        switch analysis.role {
        case .primary: return 0
        case .secondary: return 1
        case .isolation: return 2
        case .core: return 3
        case .warmup: return 4
        }
    }

    private static func selectRequiredPattern(
        remaining: inout [ExerciseCandidate],
        selected: inout [ExerciseCandidate],
        covered: inout Set<String>,
        patterns: Set<MovementPattern>,
        weeklyVolume: inout WeeklyVolumeState
    ) {
        guard let best = remaining
            .filter({ !isTrunkAccessory($0) && !$0.analysis.patterns.isDisjoint(with: patterns) })
            .max(by: {
                let leftScore = $0.score +
                    Double($0.analysis.patterns.intersection(patterns).count) * 35 +
                    programmingPriority($0.analysis) + weeklyVolumeScore($0, state: weeklyVolume)
                let rightScore = $1.score +
                    Double($1.analysis.patterns.intersection(patterns).count) * 35 +
                    programmingPriority($1.analysis) + weeklyVolumeScore($1, state: weeklyVolume)
                if leftScore != rightScore { return leftScore < rightScore }
                return $0.exercise.name.localizedCaseInsensitiveCompare($1.exercise.name) == .orderedDescending
            }) else { return }
        selected.append(best)
        covered.formUnion(best.analysis.muscles)
        projectWeeklyVolume(best, into: &weeklyVolume)
        remaining.removeAll { $0.exercise.id == best.exercise.id }
    }

    private static func balancedScore(
        _ candidate: ExerciseCandidate,
        selected: [ExerciseCandidate],
        covered: Set<String>,
        targets: Set<String>,
        lastTrained: [String: Date],
        weeklyVolume: WeeklyVolumeState,
        now: Date,
        calendar: Calendar
    ) -> Double {
        let newTargets = candidate.analysis.muscles.filter {
            targets.contains($0) && !covered.contains($0)
        }.count
        let overlap = candidate.analysis.muscles.intersection(targets).count
        let fatigue = candidate.analysis.muscles.reduce(0.0) { result, muscle in
            guard let date = lastTrained[muscle] else { return result }
            switch calendar.gymDaysBetween(date, now) {
            case 0: return result + 28
            case 1: return result + 18
            case 2: return result + 8
            default: return result
            }
        }
        let repeatedPenalty = !covered.isEmpty && candidate.analysis.muscles.allSatisfy(covered.contains)
            ? 10.0
            : 0.0
        let duplicateCompoundPatternPenalty: Double
        if isCompound(candidate.analysis) {
            duplicateCompoundPatternPenalty = selected.reduce(0) { result, item in
                let repeatedPatterns = candidate.analysis.patterns
                    .intersection(compoundMovementPatterns)
                    .intersection(item.analysis.patterns)
                    .count
                return result + Double(repeatedPatterns) * 30
            }
        } else {
            duplicateCompoundPatternPenalty = 0
        }
        let sameCategoryPenalty = Double(selected.filter {
            $0.analysis.category == candidate.analysis.category
        }.count) * 12
        return candidate.score + Double(newTargets) * 24 + Double(overlap) * 4 +
            weeklyVolumeScore(candidate, state: weeklyVolume) - fatigue -
            repeatedPenalty - duplicateCompoundPatternPenalty - sameCategoryPenalty
    }

    static func weeklyEffectiveSets(
        history: [ExerciseHistoryEntry],
        muscleMappings: [ExerciseMuscleMapping] = [],
        now: Date
    ) -> [String: Double] {
        let usableHistory = history
            .prefix(maximumHistorySetCount)
            .filter { isUsableHistoryEntry($0, now: now) }
        let manualContributions = MuscleMappingEngine.manualContributionMap(from: muscleMappings)
        let knownMuscleIDs = Set(MuscleMappingEngine.muscleDefinitions.map(\.id))
        let windowStart = now.addingTimeInterval(-7 * 24 * 60 * 60)
        var completed: [String: Double] = [:]
        for entry in usableHistory where entry.sessionDate >= windowStart && entry.sessionDate <= now {
            for contribution in MuscleMappingEngine.contributions(
                for: entry.exerciseName,
                manualMappings: manualContributions
            ) where knownMuscleIDs.contains(contribution.muscleID) && contribution.weight.isFinite {
                let weight = min(1, max(0, contribution.weight))
                guard weight > 0 else { continue }
                completed[contribution.muscleID, default: 0] += weight
            }
        }
        return completed
    }

    static func weeklyTargetSets(profile: TrainingProfile) -> Double {
        weeklySetTarget(profile: profile)
    }

    static func weeklyCoverageScore(
        contributions: [MuscleContribution],
        plannedSetCount: Int,
        projectedSets: [String: Double],
        targetSets: Double
    ) -> Double {
        let knownMuscleIDs = Set(MuscleMappingEngine.muscleDefinitions.map(\.id))
        var gain = 0.0
        var contributionWeight = 0.0
        for contribution in contributions
        where knownMuscleIDs.contains(contribution.muscleID) && contribution.weight.isFinite {
            let weight = min(1, max(0, contribution.weight))
            guard weight > 0 else { continue }
            contributionWeight += weight
            let deficit = max(0, targetSets - projectedSets[contribution.muscleID, default: 0])
            gain += min(deficit, Double(max(0, plannedSetCount)) * weight)
        }
        return gain > 0 ? gain * 18 : -12 * contributionWeight
    }

    private static func weeklyVolumeState(
        history: [ExerciseHistoryEntry],
        manualContributions: [String: [MuscleContribution]],
        profile: TrainingProfile,
        now: Date
    ) -> WeeklyVolumeState {
        let knownMuscleIDs = Set(MuscleMappingEngine.muscleDefinitions.map(\.id))
        var completed: [String: Double] = [:]
        let windowStart = now.addingTimeInterval(-7 * 24 * 60 * 60)
        for entry in history where entry.sessionDate >= windowStart && entry.sessionDate <= now {
            for contribution in MuscleMappingEngine.contributions(
                for: entry.exerciseName,
                manualMappings: manualContributions
            ) where knownMuscleIDs.contains(contribution.muscleID) && contribution.weight.isFinite {
                let weight = min(1, max(0, contribution.weight))
                guard weight > 0 else { continue }
                completed[contribution.muscleID, default: 0] += weight
            }
        }
        return WeeklyVolumeState(
            projectedSets: completed,
            targetSets: weeklyMuscleTargets(profile: profile),
            knownMuscleIDs: knownMuscleIDs
        )
    }

    private static func weeklySetTarget(profile: TrainingProfile) -> Double {
        let base: Int
        switch profile.goal {
        case .muscleGain: base = 10
        case .strength, .balanced, .aestheticFatLoss: base = 8
        }
        let calorieAdjustment: Int
        switch profile.calorieMode {
        case .deficit: calorieAdjustment = -1
        case .maintenance: calorieAdjustment = 0
        case .surplus: calorieAdjustment = 1
        }
        return Double(min(12, max(4, base + calorieAdjustment)))
    }

    static func weeklyMuscleTargets(profile: TrainingProfile) -> [String: Double] {
        let base = weeklySetTarget(profile: profile)
        let major: Set<String> = [
            "chest", "shoulders", "lats", "upperBack", "quads", "hamstrings", "glutes"
        ]
        let secondary: Set<String> = ["biceps", "triceps", "calves", "abs"]
        return Dictionary(uniqueKeysWithValues: MuscleMappingEngine.muscleDefinitions.map { muscle in
            let multiplier: Double
            if major.contains(muscle.id) {
                multiplier = 1
            } else if secondary.contains(muscle.id) {
                multiplier = 0.75
            } else {
                multiplier = 0.5
            }
            return (muscle.id, min(12, max(4, base * multiplier)))
        })
    }

    private static func weeklyVolumeScore(
        _ candidate: ExerciseCandidate,
        state: WeeklyVolumeState
    ) -> Double {
        var gain = 0.0
        var contributionWeight = 0.0
        for contribution in candidate.muscleContributions
        where state.knownMuscleIDs.contains(contribution.muscleID) && contribution.weight.isFinite {
            let weight = min(1, max(0, contribution.weight))
            guard weight > 0 else { continue }
            contributionWeight += weight
            let target = state.targetSets[contribution.muscleID, default: 4]
            let deficit = max(0, target - state.projectedSets[contribution.muscleID, default: 0])
            gain += min(deficit, Double(candidate.plannedSetCount) * weight)
        }
        return gain > 0 ? gain * 18 : -12 * contributionWeight
    }

    private static func isWeeklyVolumeSaturated(
        _ candidate: ExerciseCandidate,
        state: WeeklyVolumeState
    ) -> Bool {
        let meaningful = candidate.muscleContributions.filter {
            state.knownMuscleIDs.contains($0.muscleID) &&
                $0.weight.isFinite && $0.weight > 0
        }
        guard !meaningful.isEmpty else { return false }
        return meaningful.allSatisfy { contribution in
            state.projectedSets[contribution.muscleID, default: 0] >=
                state.targetSets[contribution.muscleID, default: 4]
        }
    }

    private static func projectWeeklyVolume(
        _ candidate: ExerciseCandidate,
        into state: inout WeeklyVolumeState
    ) {
        for contribution in candidate.muscleContributions
        where state.knownMuscleIDs.contains(contribution.muscleID) && contribution.weight.isFinite {
            let weight = min(1, max(0, contribution.weight))
            guard weight > 0 else { continue }
            state.projectedSets[contribution.muscleID, default: 0] +=
                Double(candidate.plannedSetCount) * weight
        }
    }

    private static func dominantFocus(_ entries: [ExerciseHistoryEntry]) -> SmartWorkoutFocus {
        let counts = Dictionary(grouping: entries) {
            analyzeExercise($0.exerciseName, catalogKey: $0.exerciseCatalogKey).category
        }
            .mapValues(\.count)
        let lowerCount = counts[.legs, default: 0] + counts[.lower, default: 0]
        let upperCount = counts[.push, default: 0] + counts[.pull, default: 0] + counts[.upper, default: 0]
        if lowerCount > upperCount { return .lower }
        if upperCount > lowerCount {
            return counts[.push, default: 0] >= counts[.pull, default: 0] ? .push : .pull
        }
        return .fullBody
    }

    private static func recentSessionIDs(
        _ history: [ExerciseHistoryEntry],
        limit: Int
    ) -> Set<UUID> {
        Set(sessionGroups(history).prefix(limit).map { $0.id })
    }

    private static func lastTrainedByMuscle(
        _ history: [ExerciseHistoryEntry]
    ) -> [String: Date] {
        var result: [String: Date] = [:]
        for entry in history {
            for muscle in analyzeExercise(
                entry.exerciseName,
                catalogKey: entry.exerciseCatalogKey
            ).muscles {
                if entry.sessionDate > result[muscle, default: .distantPast] {
                    result[muscle] = entry.sessionDate
                }
            }
        }
        return result
    }

    private static func targetMuscles(for focus: SmartWorkoutFocus) -> Set<String> {
        switch focus {
        case .upper: return pushMuscles.union(pullMuscles)
        case .lower, .legs: return lowerMuscles.union(coreMuscles)
        case .push: return pushMuscles
        case .pull: return pullMuscles
        case .fullBody: return pushMuscles.union(pullMuscles).union(lowerMuscles).union(coreMuscles)
        }
    }

    private static func chooseMostNeglectedFocus(
        _ history: [ExerciseHistoryEntry]
    ) -> SmartWorkoutFocus {
        var lastByFocus: [SmartWorkoutFocus: Date] = [:]
        for entry in history {
            let focus = analyzeExercise(
                entry.exerciseName,
                catalogKey: entry.exerciseCatalogKey
            ).category
            if entry.sessionDate > lastByFocus[focus, default: .distantPast] {
                lastByFocus[focus] = entry.sessionDate
            }
        }
        return [SmartWorkoutFocus.push, .pull, .legs, .fullBody].min {
            lastByFocus[$0, default: .distantPast] < lastByFocus[$1, default: .distantPast]
        } ?? .fullBody
    }

    private static func sessionGroups(_ history: [ExerciseHistoryEntry]) -> [SessionGroup] {
        Dictionary(grouping: history, by: \.workoutID)
            .map {
                let boundedEntries = $0.value.sorted {
                    $0.setOrderIndex == $1.setOrderIndex
                        ? $0.setID.uuidString < $1.setID.uuidString
                        : $0.setOrderIndex < $1.setOrderIndex
                }.prefix(maximumSupportedSetCount)
                return SessionGroup(
                    id: $0.key,
                    date: boundedEntries.map(\.sessionDate).max() ?? .distantPast,
                    entries: Array(boundedEntries)
                )
            }
            .sorted {
                $0.date == $1.date
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.date > $1.date
            }
    }

    private struct ExerciseSessionSnapshot {
        let sets: [ExerciseHistoryEntry]
        var workoutID: UUID { sets[0].workoutID }
        var date: Date { sets[0].sessionDate }
        var maxWeight: Double { sets.map(\.weight).max() ?? 0 }
        var minReps: Int { sets.map(\.reps).min() ?? 0 }
        var averageReps: Double { Double(sets.reduce(0) { $0 + $1.reps }) / Double(sets.count) }
        var averageWeight: Double { sets.reduce(0) { $0 + $1.weight } / Double(sets.count) }
        var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
        var volume: Double { sets.reduce(0) { $0 + $1.volume } }
        var averageVolumePerSet: Double { volume / Double(sets.count) }
        var estimatedMax: Double { sets.map(\.estimatedOneRepMax).max() ?? 0 }
    }

    private struct ExerciseCandidate {
        let exercise: Exercise
        let analysis: ExerciseAnalysis
        let identityKey: String
        let history: [ExerciseHistoryEntry]
        let muscleContributions: [MuscleContribution]
        let plannedSetCount: Int
        let score: Double
    }

    private struct WeeklyVolumeState {
        var projectedSets: [String: Double]
        let targetSets: [String: Double]
        let knownMuscleIDs: Set<String>
    }

    private struct ExerciseAnalysis {
        let category: SmartWorkoutFocus
        let muscles: Set<String>
        let patterns: Set<MovementPattern>
        let role: ExerciseRole
        let loadMode: ExerciseLoadMode
        let equipment: EquipmentKind
    }

    private struct SessionGroup {
        let id: UUID
        let date: Date
        let entries: [ExerciseHistoryEntry]
    }
}

private extension SmartWorkoutFocus {
    var isUpperDay: Bool { self == .upper || self == .push || self == .pull }
    var isLowerDay: Bool { self == .lower || self == .legs }
}
