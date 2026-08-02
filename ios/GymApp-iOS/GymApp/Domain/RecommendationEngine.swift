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

    public init(
        focus: SmartWorkoutFocus,
        exercises: [SmartWorkoutExercise],
        variant: SmartWorkoutVariant = .a
    ) {
        self.focus = focus
        self.exercises = exercises
        self.variant = variant
    }

    private enum CodingKeys: String, CodingKey {
        case focus
        case exercises
        case variant
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        focus = try container.decode(SmartWorkoutFocus.self, forKey: .focus)
        exercises = try container.decode([SmartWorkoutExercise].self, forKey: .exercises)
        variant = try container.decodeIfPresent(SmartWorkoutVariant.self, forKey: .variant) ?? .a
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(focus, forKey: .focus)
        try container.encode(exercises, forKey: .exercises)
        try container.encode(variant, forKey: .variant)
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

    public static func buildForExercise(
        exerciseID: UUID,
        history: [ExerciseHistoryEntry],
        exerciseCatalogKey: String? = nil,
        exerciseName: String? = nil,
        trainingProfile: TrainingProfile = TrainingProfile(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WorkoutRecommendation {
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

        guard !matchingHistory.isEmpty else {
            let targetSetCount = setBudget(
                profile: trainingProfile,
                analysis: programmingAnalysis
            )
            return WorkoutRecommendation(
                exerciseID: exerciseID,
                sets: (0 ..< targetSetCount).map { index in
                    RecommendedWorkoutSet(
                        id: recommendedSetID(
                            exerciseID: exerciseID,
                            workoutID: nil,
                            kind: .newExercise,
                            index: index,
                            weight: nil,
                            reps: defaultRepsTarget
                        ),
                        weight: nil,
                        reps: defaultRepsTarget
                    )
                },
                kind: .newExercise,
                confidence: 0.35,
                estimatedVolume: 0,
                daysSinceLastSession: nil,
                reasons: [.noHistory]
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
            analysis: programmingAnalysis
        )
        let loadMode = programmingAnalysis?.loadMode ?? .standard
        let bestEstimatedMax = sessionSnapshots.map { $0.estimatedMax }.max() ?? 0
        let canAssessStandardLoadTrend = loadMode != .assistance && latest.maxWeight > 0
        let plateauDetected = canAssessStandardLoadTrend &&
            isTruePlateau(Array(sessionSnapshots.prefix(4)))
        let latestNearBest = bestEstimatedMax <= 0 || latest.estimatedMax >= bestEstimatedMax * 0.97
        let previousVolumePerSet = previous?.averageVolumePerSet ?? latest.averageVolumePerSet
        let volumeRatio = previousVolumePerSet <= 0
            ? 1
            : latest.averageVolumePerSet / previousVolumePerSet
        let repeatedRegression: Bool
        if sessionSnapshots.count < 3 || loadMode == .assistance {
            repeatedRegression = false
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
            volumeRatio < 0.88
        let earnedProgression = completedAtRepCeiling(
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
            loadMode: loadMode
        ) && !(loadMode == .bodyweight && latest.maxWeight <= 0)
        let isFatLossDeficit = trainingProfile.goal == .aestheticFatLoss &&
            trainingProfile.calorieMode == .deficit

        let kind: WorkoutRecommendationKind
        if daysSinceLastSession >= comebackBreakDays {
            kind = .comeback
        } else if repeatedRegression {
            kind = .deload
        } else if earnedProgression {
            kind = .progressiveOverload
        } else if plateauDetected {
            kind = .plateauBreak
        } else {
            kind = .holdAndBuild
        }

        let baselineSets = resizedBaselineSets(latest.sets, targetCount: targetSetCount)
        let plateauUsesLowerRange = latest.averageReps >= Double(repRange.lowerBound + repRange.upperBound) / 2
        let sets = baselineSets.enumerated().map { index, baseline -> RecommendedWorkoutSet in
            let target: (weight: Double?, reps: Int)
            switch kind {
            case .newExercise:
                target = (nil, defaultRepsTarget)
            case .progressiveOverload:
                let increasedWeight = baseline.weight > 0
                    ? roundToNearestHalf(
                        loadMode == .assistance
                            ? max(0, baseline.weight - chooseWeightStep(
                                weight: baseline.weight,
                                profile: trainingProfile
                            ))
                            : baseline.weight + chooseWeightStep(
                                weight: baseline.weight,
                                profile: trainingProfile
                            )
                    )
                    : baseline.weight
                target = (
                    increasedWeight,
                    baseline.weight <= 0 ? repRange.upperBound : repRange.lowerBound
                )
            case .holdAndBuild:
                target = (
                    baseline.weight,
                    min(repRange.upperBound, max(repRange.lowerBound, baseline.reps + 1))
                )
            case .deload:
                target = (
                    baseline.weight > 0
                        ? roundToNearestHalf(
                            loadMode == .assistance
                                ? baseline.weight + chooseWeightStep(
                                    weight: baseline.weight,
                                    profile: trainingProfile
                                )
                                : baseline.weight * (isFatLossDeficit ? 0.9 : 0.92)
                        )
                        : baseline.weight,
                    min(repRange.upperBound, max(repRange.lowerBound, baseline.reps))
                )
            case .comeback:
                target = (
                    baseline.weight > 0
                        ? roundToNearestHalf(
                            loadMode == .assistance
                                ? baseline.weight + chooseWeightStep(
                                    weight: baseline.weight,
                                    profile: trainingProfile
                                )
                                : baseline.weight * comebackMultiplier(daysSinceLastSession)
                        )
                        : baseline.weight,
                    min(repRange.upperBound, max(repRange.lowerBound, baseline.reps))
                )
            case .plateauBreak:
                target = (
                    baseline.weight,
                    plateauUsesLowerRange ? repRange.lowerBound : repRange.upperBound
                )
            }
            return RecommendedWorkoutSet(
                id: recommendedSetID(
                    exerciseID: exerciseID,
                    workoutID: latest.workoutID,
                    kind: kind,
                    index: index,
                    weight: target.weight,
                    reps: target.reps
                ),
                weight: target.weight,
                reps: target.reps
            )
        }

        var reasons: [WorkoutRecommendationReason] = []
        func addReason(_ reason: WorkoutRecommendationReason, when condition: Bool) {
            if condition && !reasons.contains(reason) { reasons.append(reason) }
        }
        addReason(.lastSessionStrong, when: latestStable)
        addReason(.lastSessionUnstable, when: latestStrained || repeatedRegression)
        addReason(.recentBreak, when: daysSinceLastSession >= comebackBreakDays)
        addReason(.volumeTrendingUp, when: volumeRatio >= 1.08)
        addReason(.volumeDropped, when: volumeRatio < 0.9 || repeatedRegression)
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
            estimatedVolume: sets.reduce(0) { $0 + ($1.weight ?? 0) * Double($1.reps) },
            daysSinceLastSession: daysSinceLastSession,
            reasons: Array(reasons.prefix(3))
        )
    }

    public static func buildWorkoutPlan(
        exercises: [Exercise],
        history: [ExerciseHistoryEntry],
        trainingProfile: TrainingProfile = TrainingProfile(),
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
            return SmartWorkoutPlan(focus: .fullBody, exercises: [])
        }
        let usableHistory = history
            .prefix(maximumHistorySetCount)
            .filter { isUsableHistoryEntry($0, now: now) }
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
        let targetExerciseCount = targetExerciseCount(
            focus: focus,
            profile: trainingProfile
        )
        let recentIDs = recentSessionIDs(usableHistory, limit: 3)
        let targetMuscles = targetMuscles(for: focus)
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
                score: focusScore + muscleMatch + due + continuity +
                    variantScore + programmingScore - recentPenalty - sameWeekPenalty
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
            history: usableHistory,
            now: now,
            calendar: calendar
        )
        return SmartWorkoutPlan(
            focus: focus,
            exercises: selected.map {
                SmartWorkoutExercise(
                    exercise: $0.exercise,
                    recommendation: buildForExercise(
                        exerciseID: $0.exercise.id,
                        history: $0.history,
                        exerciseCatalogKey: $0.exercise.catalogKey,
                        exerciseName: $0.exercise.name,
                        trainingProfile: trainingProfile,
                        now: now,
                        calendar: calendar
                    )
                )
            },
            variant: variant
        )
    }

    private static func chooseWeightStep(weight: Double, profile: TrainingProfile) -> Double {
        let step: Double
        switch weight {
        case ..<20: step = 1
        case ..<60: step = 2.5
        case ..<120: step = 5
        default: step = 7.5
        }
        return profile.goal == .aestheticFatLoss || profile.calorieMode == .deficit
            ? step * 0.5
            : step
    }

    private static func goalRepRange(
        _ profile: TrainingProfile,
        analysis: ExerciseAnalysis?
    ) -> ClosedRange<Int> {
        let compound = isCompound(analysis)
        switch profile.goal {
        case .strength: return compound ? 3 ... 6 : 6 ... 10
        case .muscleGain, .aestheticFatLoss: return compound ? 6 ... 10 : 8 ... 10
        case .balanced: return compound ? 5 ... 8 : 8 ... 10
        }
    }

    private static func defaultTargetReps(
        _ profile: TrainingProfile,
        analysis: ExerciseAnalysis?,
        repRange: ClosedRange<Int>
    ) -> Int {
        let compound = isCompound(analysis)
        let target: Int
        switch profile.goal {
        case .strength: target = compound ? 5 : 8
        case .muscleGain, .aestheticFatLoss, .balanced: target = compound ? 8 : 10
        }
        return min(repRange.upperBound, max(repRange.lowerBound, target))
    }

    private static func isCompound(_ analysis: ExerciseAnalysis?) -> Bool {
        guard let analysis else { return false }
        return analysis.role == .primary || analysis.role == .secondary
    }

    private static func setBudget(
        profile: TrainingProfile,
        analysis: ExerciseAnalysis?
    ) -> Int {
        let highFrequency = profile.workoutsPerWeek >= 5
        let recoveryLimited = profile.calorieMode == .deficit
        return analysis?.role == .primary && !highFrequency && !recoveryLimited ? 4 : 3
    }

    private static func targetExerciseCount(
        focus: SmartWorkoutFocus,
        profile: TrainingProfile
    ) -> Int {
        let days = min(6, max(2, profile.workoutsPerWeek))
        var target = days == 2 ? 6 : days == 3 ? 5 : days == 4 ? 4 : 3
        if profile.goal == .strength { target -= 1 }
        if profile.calorieMode == .deficit { target -= 1 }
        return min(6, max(focus == .fullBody ? 3 : 2, target))
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
        loadMode: ExerciseLoadMode
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
        let weightDidNotDecline = loadMode == .assistance
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

    private static func isTruePlateau(_ sessions: [ExerciseSessionSnapshot]) -> Bool {
        guard sessions.count >= 4,
              sessions.allSatisfy({ $0.estimatedMax > 0 && $0.averageVolumePerSet > 0 }) else {
            return false
        }
        let latest = sessions[0]
        let oldest = sessions[sessions.count - 1]
        let estimatedMaxValues = sessions.map(\.estimatedMax)
        let volumeValues = sessions.map(\.averageVolumePerSet)
        guard let maximumEstimatedMax = estimatedMaxValues.max(),
              let minimumEstimatedMax = estimatedMaxValues.min(),
              let maximumVolume = volumeValues.max(),
              let minimumVolume = volumeValues.min() else { return false }
        let estimatedMaxSpread = (maximumEstimatedMax - minimumEstimatedMax) / maximumEstimatedMax
        let volumeSpread = (maximumVolume - minimumVolume) / maximumVolume
        return estimatedMaxSpread <= 0.02 &&
            volumeSpread <= 0.03 &&
            latest.estimatedMax <= oldest.estimatedMax * 1.015 &&
            latest.averageReps <= oldest.averageReps + 0.25 &&
            latest.averageVolumePerSet <= oldest.averageVolumePerSet * 1.02
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
                    loadMode: programming.loadMode
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
            loadMode: .standard
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
        history: [ExerciseHistoryEntry],
        now: Date,
        calendar: Calendar
    ) -> [ExerciseCandidate] {
        var selected: [ExerciseCandidate] = []
        var covered = Set<String>()
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
                patterns: preferredPatterns(for: focus, variant: variant)
            )
            selectRequiredPattern(
                remaining: &remaining,
                selected: &selected,
                covered: &covered,
                patterns: variant == .a ? [.hinge, .kneeFlexion] : [.squat, .legPress]
            )
        }

        if focus == .upper {
            let preferred = preferredPatterns(for: focus, variant: variant)
            let pressPatterns = preferred.intersection([.horizontalPress, .verticalPress])
            let pullPatterns = preferred.intersection([.horizontalPull, .verticalPull])
            selectRequiredPattern(
                remaining: &remaining,
                selected: &selected,
                covered: &covered,
                patterns: pressPatterns.isEmpty ? [.horizontalPress, .verticalPress] : pressPatterns
            )
            selectRequiredPattern(
                remaining: &remaining,
                selected: &selected,
                covered: &covered,
                patterns: pullPatterns.isEmpty ? [.horizontalPull, .verticalPull] : pullPatterns
            )
        } else if focus == .push || focus == .pull {
            selectRequiredPattern(
                remaining: &remaining,
                selected: &selected,
                covered: &covered,
                patterns: preferredPatterns(for: focus, variant: variant)
            )
        }

        if focus == .fullBody {
            for required in [SmartWorkoutFocus.push, .pull, .legs] {
                guard let best = remaining
                    .filter({ $0.analysis.category == required && isCompound($0.analysis) })
                    .max(by: {
                        let leftScore = $0.score + programmingPriority($0.analysis)
                        let rightScore = $1.score + programmingPriority($1.analysis)
                        if leftScore != rightScore { return leftScore < rightScore }
                        return $0.exercise.name.localizedCaseInsensitiveCompare($1.exercise.name) == .orderedDescending
                    }) else { continue }
                selected.append(best)
                covered.formUnion(best.analysis.muscles)
                remaining.removeAll { $0.exercise.id == best.exercise.id }
            }
        }

        while selected.count < targetExerciseCount, !remaining.isEmpty {
            let scored = remaining.map { candidate in
                (
                    candidate,
                    balancedScore(
                        candidate,
                        selected: selected,
                        covered: covered,
                        targets: targetMuscles,
                        lastTrained: lastTrained,
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
            remaining.removeAll { $0.exercise.id == best.exercise.id }
        }

        return Array(selected.prefix(targetExerciseCount))
    }

    private static func programmingPriority(_ analysis: ExerciseAnalysis) -> Double {
        switch analysis.role {
        case .primary: return 28
        case .secondary: return 14
        case .isolation, .core, .warmup: return 0
        }
    }

    private static func selectRequiredPattern(
        remaining: inout [ExerciseCandidate],
        selected: inout [ExerciseCandidate],
        covered: inout Set<String>,
        patterns: Set<MovementPattern>
    ) {
        guard let best = remaining
            .filter({ !$0.analysis.patterns.isDisjoint(with: patterns) })
            .max(by: {
                let leftScore = $0.score +
                    Double($0.analysis.patterns.intersection(patterns).count) * 35 +
                    programmingPriority($0.analysis)
                let rightScore = $1.score +
                    Double($1.analysis.patterns.intersection(patterns).count) * 35 +
                    programmingPriority($1.analysis)
                if leftScore != rightScore { return leftScore < rightScore }
                return $0.exercise.name.localizedCaseInsensitiveCompare($1.exercise.name) == .orderedDescending
            }) else { return }
        selected.append(best)
        covered.formUnion(best.analysis.muscles)
        remaining.removeAll { $0.exercise.id == best.exercise.id }
    }

    private static func balancedScore(
        _ candidate: ExerciseCandidate,
        selected: [ExerciseCandidate],
        covered: Set<String>,
        targets: Set<String>,
        lastTrained: [String: Date],
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
        return candidate.score + Double(newTargets) * 24 + Double(overlap) * 4 - fatigue -
            repeatedPenalty - duplicateCompoundPatternPenalty - sameCategoryPenalty
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

    private static func roundToNearestHalf(_ value: Double) -> Double {
        let bounded = min(maximumSupportedWeight, max(0, value))
        return (bounded * 2).rounded(.toNearestOrEven) / 2
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
        let score: Double
    }

    private struct ExerciseAnalysis {
        let category: SmartWorkoutFocus
        let muscles: Set<String>
        let patterns: Set<MovementPattern>
        let role: ExerciseRole
        let loadMode: ExerciseLoadMode
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
