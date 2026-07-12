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

public struct SmartWorkoutPlan: Codable, Identifiable, Hashable, Sendable {
    public var id: String {
        focus.rawValue + ":" + exercises.map { $0.id.uuidString }.joined(separator: ",")
    }
    public let focus: SmartWorkoutFocus
    public let exercises: [SmartWorkoutExercise]
}

/// Pure Swift port of Android's per-exercise and smart-plan recommendation engine.
public enum RecommendationEngine {
    private static let defaultSetCount = 3
    private static let defaultReps = 10
    private static let maxHistorySets = 120
    private static let comebackBreakDays = 10

    private static let upperFocuses: Set<SmartWorkoutFocus> = [.upper, .push, .pull]
    private static let lowerFocuses: Set<SmartWorkoutFocus> = [.lower, .legs]
    private static let pushMuscles: Set<String> = ["chest", "shoulders", "triceps"]
    private static let pullMuscles: Set<String> = ["lats", "upperBack", "biceps", "forearms"]
    private static let lowerMuscles: Set<String> = ["quads", "hamstrings", "glutes", "calves", "adductors", "lowerBack"]
    private static let coreMuscles: Set<String> = ["abs", "obliques"]

    public static func buildForExercise(
        exerciseID: UUID,
        history: [ExerciseHistoryEntry],
        trainingProfile: TrainingProfile = TrainingProfile(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WorkoutRecommendation {
        let history = history
            .filter { $0.exerciseID == exerciseID }
            .sorted {
                $0.sessionDate == $1.sessionDate
                    ? $0.setOrderIndex < $1.setOrderIndex
                    : $0.sessionDate > $1.sessionDate
            }
            .prefix(maxHistorySets)

        guard !history.isEmpty else {
            return WorkoutRecommendation(
                exerciseID: exerciseID,
                sets: (0 ..< defaultSetCount).map { _ in
                    RecommendedWorkoutSet(weight: nil, reps: defaultReps)
                },
                kind: .newExercise,
                confidence: 0.35,
                estimatedVolume: 0,
                daysSinceLastSession: nil,
                reasons: [.noHistory]
            )
        }

        let sessions = Dictionary(grouping: history, by: \.workoutID)
            .values
            .map { ExerciseSessionSnapshot(sets: $0.sorted { $0.setOrderIndex < $1.setOrderIndex }) }
            .sorted { $0.date > $1.date }
        let latest = sessions[0]
        let previous = sessions.count > 1 ? sessions[1] : nil
        let daysSinceLastSession = calendar.gymDaysBetween(latest.date, now)
        let recentSessions = Array(sessions.prefix(5))
        let bestEstimatedMax = sessions.map(\.estimatedMax).max() ?? 0
        let recentMaxWeights = recentSessions.map(\.maxWeight)
        let plateauDetected = recentMaxWeights.count >= 4 &&
            (recentMaxWeights.max() ?? 0) - (recentMaxWeights.min() ?? 0) <= 1.25
        let latestNearBest = bestEstimatedMax <= 0 || latest.estimatedMax >= bestEstimatedMax * 0.97
        let previousVolume = previous?.volume ?? latest.volume
        let volumeRatio = previousVolume <= 0 ? 1 : latest.volume / previousVolume
        let latestStable = latest.minReps >= 8 && latest.sets.count >= 3
        let latestStrained = latest.minReps <= 5 || volumeRatio < 0.88
        let isFatLossDeficit = trainingProfile.goal == .aestheticFatLoss &&
            trainingProfile.calorieMode == .deficit

        let kind: WorkoutRecommendationKind
        if daysSinceLastSession >= comebackBreakDays {
            kind = .comeback
        } else if latestStrained || (isFatLossDeficit && volumeRatio < 0.96) {
            kind = .deload
        } else if plateauDetected {
            kind = .plateauBreak
        } else if latestStable && volumeRatio >= 0.95 && !isFatLossDeficit {
            kind = .progressiveOverload
        } else {
            kind = .holdAndBuild
        }

        let targetSetCount: Int
        if trainingProfile.goal == .strength {
            targetSetCount = min(5, max(3, latest.sets.count))
        } else if isFatLossDeficit {
            targetSetCount = min(4, max(3, latest.sets.count))
        } else {
            targetSetCount = min(5, max(2, latest.sets.count))
        }

        let rawTargetWeight: Double?
        switch kind {
        case .newExercise:
            rawTargetWeight = nil
        case .progressiveOverload:
            rawTargetWeight = latest.maxWeight + chooseWeightStep(
                weight: latest.maxWeight,
                profile: trainingProfile
            )
        case .holdAndBuild, .plateauBreak:
            rawTargetWeight = latest.maxWeight
        case .deload:
            rawTargetWeight = latest.maxWeight * (isFatLossDeficit ? 0.9 : 0.92)
        case .comeback:
            rawTargetWeight = latest.maxWeight * comebackMultiplier(daysSinceLastSession)
        }
        let targetWeight = rawTargetWeight.map(roundToNearestHalf)

        let averageReps = Int(latest.averageReps.rounded())
        let targetReps: Int
        switch kind {
        case .newExercise:
            targetReps = defaultReps
        case .progressiveOverload:
            targetReps = min(goalMaxReps(trainingProfile), max(6, averageReps))
        case .holdAndBuild:
            targetReps = min(goalMaxReps(trainingProfile), max(8, averageReps + 1))
        case .deload:
            targetReps = min(12, max(8, averageReps + 1))
        case .comeback:
            targetReps = min(12, max(8, averageReps))
        case .plateauBreak:
            targetReps = latest.averageReps >= 9 && !isFatLossDeficit ? 6 : 11
        }

        let sets = (0 ..< targetSetCount).map { index -> RecommendedWorkoutSet in
            let reps: Int
            if kind == .plateauBreak && targetReps <= 6 {
                reps = max(4, targetReps - index / 2)
            } else if index >= 3 {
                reps = max(5, targetReps - 1)
            } else {
                reps = targetReps
            }
            return RecommendedWorkoutSet(weight: targetWeight, reps: reps)
        }

        var reasons: [WorkoutRecommendationReason] = []
        func addReason(_ reason: WorkoutRecommendationReason, when condition: Bool) {
            if condition && !reasons.contains(reason) { reasons.append(reason) }
        }
        addReason(.lastSessionStrong, when: latestStable)
        addReason(.lastSessionUnstable, when: latestStrained)
        addReason(.recentBreak, when: daysSinceLastSession >= comebackBreakDays)
        addReason(.volumeTrendingUp, when: volumeRatio >= 1.08)
        addReason(.volumeDropped, when: volumeRatio < 0.9)
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
                sessionCount: sessions.count,
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
        guard !exercises.isEmpty else {
            return SmartWorkoutPlan(focus: .fullBody, exercises: [])
        }
        let focus = chooseWorkoutFocus(
            history: history,
            profile: trainingProfile,
            now: now,
            calendar: calendar
        )
        let targetExerciseCount = focus == .fullBody ? 6 : 5
        let historyByExercise = Dictionary(grouping: history, by: \.exerciseID)
        let recentIDs = recentSessionIDs(history, limit: 3)
        let targetMuscles = targetMuscles(for: focus)

        let candidates = exercises.map { exercise -> ExerciseCandidate in
            let exerciseHistory = historyByExercise[exercise.id, default: []]
            let analysis = analyzeExercise(exercise.name)
            let daysSince = exerciseHistory.map(\.sessionDate).max()
                .map { calendar.gymDaysBetween($0, now) } ?? 90
            let sessionCount = Set(exerciseHistory.map(\.workoutID)).count
            let recentPenalty = Double(Set(
                exerciseHistory.filter { recentIDs.contains($0.workoutID) }.map(\.workoutID)
            ).count) * 16
            let sameWeekPenalty = exerciseHistory.contains {
                calendar.gymDaysBetween($0.sessionDate, now) <= 6
            } ? 55.0 : 0.0
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
            let novelty = sessionCount == 0 ? 12.0 : 0.0
            let due = Double(min(28, daysSince)) * 1.25
            let confidence = Double(min(4, sessionCount)) * 2
            return ExerciseCandidate(
                exercise: exercise,
                analysis: analysis,
                score: focusScore + muscleMatch + novelty + due + confidence -
                    recentPenalty - sameWeekPenalty
            )
        }

        let selected = selectBalancedExercises(
            candidates: candidates,
            focus: focus,
            targetMuscles: targetMuscles,
            targetExerciseCount: targetExerciseCount,
            history: history,
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
                        history: history,
                        trainingProfile: trainingProfile,
                        now: now,
                        calendar: calendar
                    )
                )
            }
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

    private static func goalMaxReps(_ profile: TrainingProfile) -> Int {
        switch profile.goal {
        case .strength: return 8
        case .aestheticFatLoss: return 14
        case .muscleGain, .balanced: return 12
        }
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
        guard !history.isEmpty else {
            switch profile.split {
            case .upperLower: return .upper
            case .fullBody, .custom: return .fullBody
            case .pushPullLegs: return .push
            }
        }
        let sessions = sessionGroups(history)
        guard let latestEntries = sessions.first?.entries else { return .upper }
        let latestFocus = dominantFocus(latestEntries)

        switch profile.split {
        case .upperLower:
            let thisWeek = sessions.filter { calendar.gymDaysBetween($0.date, now) <= 6 }
            let latestWeekFocus = thisWeek.first.map { dominantFocus($0.entries) } ?? latestFocus
            if latestWeekFocus.isLowerDay { return .upper }
            if latestWeekFocus.isUpperDay { return .lower }
            let upperCount = thisWeek.filter { dominantFocus($0.entries).isUpperDay }.count
            let lowerCount = thisWeek.filter { dominantFocus($0.entries).isLowerDay }.count
            return lowerCount < upperCount ? .lower : .upper
        case .pushPullLegs:
            switch latestFocus {
            case .push: return .pull
            case .pull: return .legs
            case .legs, .lower: return .push
            case .upper, .fullBody: return chooseMostNeglectedFocus(history)
            }
        case .fullBody:
            return .fullBody
        case .custom:
            return chooseMostNeglectedFocus(history)
        }
    }

    private static func analyzeExercise(_ name: String) -> ExerciseAnalysis {
        let value = MuscleMappingEngine.normalizeExerciseName(name)
        var muscles = Set<String>()
        var patterns = Set<MovementPattern>()
        func has(_ tokens: String...) -> Bool { tokens.contains { value.contains($0) } }
        func add(_ ids: String...) { muscles.formUnion(ids) }
        func pattern(_ values: MovementPattern...) { patterns.formUnion(values) }

        if has("жим ног", "leg press") { add("quads", "glutes", "hamstrings"); pattern(.legPress) }
        if has("прис", "присед", "squat", "випад", "выпад", "lunge") { add("quads", "glutes", "hamstrings"); pattern(.squat) }
        if has("румун", "румын", "станов", "становая", "deadlift") { add("hamstrings", "glutes", "lowerBack", "upperBack"); pattern(.hinge) }
        if has("згинання ніг", "згибання ніг", "сгибание ног", "leg curl") { add("hamstrings"); pattern(.kneeFlexion) }
        if has("розгинання ніг", "разгибание ног", "leg extension") { add("quads"); pattern(.kneeExtension) }
        if has("сідниц", "ягодиц", "glute", "hip thrust", "місток", "мостик") { add("glutes", "hamstrings"); pattern(.hinge) }
        if has("икр", "ікр", "calf", "носок", "носки") { add("calves"); pattern(.calf) }
        if has("зведення ніг", "сведение ног", "adductor") { add("adductors") }

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
        if has("тяга", "row") && !has("румун", "румын", "станов", "становая", "deadlift", "підборід", "подбород") { add("lats", "upperBack", "biceps"); pattern(.horizontalPull) }
        if has("спин", "спина", "back") { add("lats", "upperBack") }
        if has("біцепс", "бицепс", "bicep", "curl", "згинання рук", "сгибание рук") { add("biceps", "forearms") }
        if has("передпліч", "предплеч", "forearm") { add("forearms") }

        if has("прес", "abs", "crunch", "скруч", "планка", "plank", "leg raise") { add("abs"); pattern(.core) }
        if has("нахил", "наклон", "сторони", "стороны", "oblique", "rotation", "twist") { add("obliques") }
        if has("гіперекстензі", "гиперэкстенз", "hyperextension") { add("lowerBack", "glutes", "hamstrings"); pattern(.hinge) }

        let category: SmartWorkoutFocus
        if !muscles.isDisjoint(with: lowerMuscles) {
            category = .legs
        } else if !muscles.isDisjoint(with: pullMuscles) && muscles.isDisjoint(with: pushMuscles) {
            category = .pull
        } else if !muscles.isDisjoint(with: pushMuscles) {
            category = .push
        } else {
            category = .fullBody
        }
        if patterns.isEmpty { patterns.insert(.accessory) }
        return ExerciseAnalysis(category: category, muscles: muscles, patterns: patterns)
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
                patterns: [.squat, .legPress]
            )
            if shouldPrioritizeHeavyLower(history) {
                selectRequiredPattern(
                    remaining: &remaining,
                    selected: &selected,
                    covered: &covered,
                    patterns: [.hinge]
                )
            }
        }
        if focus == .fullBody {
            for required in [SmartWorkoutFocus.push, .pull, .legs] {
                guard let best = remaining
                    .filter({ $0.analysis.category == required })
                    .max(by: { $0.score < $1.score }) else { continue }
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
                        covered: covered,
                        targets: targetMuscles,
                        lastTrained: lastTrained,
                        now: now,
                        calendar: calendar
                    )
                )
            }
            guard let best = scored.max(by: {
                $0.1 == $1.1
                    ? $0.0.exercise.name.lowercased() > $1.0.exercise.name.lowercased()
                    : $0.1 < $1.1
            })?.0 else { break }
            selected.append(best)
            covered.formUnion(best.analysis.muscles)
            remaining.removeAll { $0.exercise.id == best.exercise.id }
        }

        if selected.count < targetExerciseCount {
            let selectedIDs = Set(selected.map { $0.exercise.id })
            selected.append(contentsOf: candidates
                .filter { isEligible($0.analysis, for: focus) && !selectedIDs.contains($0.exercise.id) }
                .sorted {
                    $0.score == $1.score
                        ? $0.exercise.name.lowercased() < $1.exercise.name.lowercased()
                        : $0.score > $1.score
                }
                .prefix(targetExerciseCount - selected.count))
        }
        return Array(selected.prefix(targetExerciseCount))
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
                $0.score + Double($0.analysis.patterns.intersection(patterns).count) * 35 <
                    $1.score + Double($1.analysis.patterns.intersection(patterns).count) * 35
            }) else { return }
        selected.append(best)
        covered.formUnion(best.analysis.muscles)
        remaining.removeAll { $0.exercise.id == best.exercise.id }
    }

    private static func shouldPrioritizeHeavyLower(_ history: [ExerciseHistoryEntry]) -> Bool {
        guard let latest = sessionGroups(history)
            .first(where: { dominantFocus($0.entries).isLowerDay }) else { return true }
        let patterns = Set(latest.entries.flatMap { analyzeExercise($0.exerciseName).patterns })
        return !patterns.contains(.squat) && !patterns.contains(.legPress) && !patterns.contains(.hinge)
    }

    private static func balancedScore(
        _ candidate: ExerciseCandidate,
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
        return candidate.score + Double(newTargets) * 24 + Double(overlap) * 4 - fatigue - repeatedPenalty
    }

    private static func dominantFocus(_ entries: [ExerciseHistoryEntry]) -> SmartWorkoutFocus {
        let counts = Dictionary(grouping: entries) { analyzeExercise($0.exerciseName).category }
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
        Set(Dictionary(grouping: history, by: \.workoutID)
            .map { (id: $0.key, date: $0.value.map(\.sessionDate).max() ?? .distantPast) }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map(\.id))
    }

    private static func lastTrainedByMuscle(
        _ history: [ExerciseHistoryEntry]
    ) -> [String: Date] {
        var result: [String: Date] = [:]
        for entry in history {
            for muscle in analyzeExercise(entry.exerciseName).muscles {
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
            let focus = analyzeExercise(entry.exerciseName).category
            if entry.sessionDate > lastByFocus[focus, default: .distantPast] {
                lastByFocus[focus] = entry.sessionDate
            }
        }
        return [SmartWorkoutFocus.push, .pull, .legs, .fullBody].min {
            lastByFocus[$0, default: .distantPast] < lastByFocus[$1, default: .distantPast]
        } ?? .fullBody
    }

    private static func roundToNearestHalf(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    private static func sessionGroups(_ history: [ExerciseHistoryEntry]) -> [SessionGroup] {
        Dictionary(grouping: history, by: \.workoutID)
            .map {
                SessionGroup(
                    id: $0.key,
                    date: $0.value.map(\.sessionDate).max() ?? .distantPast,
                    entries: $0.value
                )
            }
            .sorted { $0.date > $1.date }
    }

    private struct ExerciseSessionSnapshot {
        let sets: [ExerciseHistoryEntry]
        var date: Date { sets[0].sessionDate }
        var maxWeight: Double { sets.map(\.weight).max() ?? 0 }
        var minReps: Int { sets.map(\.reps).min() ?? 0 }
        var averageReps: Double { Double(sets.reduce(0) { $0 + $1.reps }) / Double(sets.count) }
        var volume: Double { sets.reduce(0) { $0 + $1.volume } }
        var estimatedMax: Double { sets.map(\.estimatedOneRepMax).max() ?? 0 }
    }

    private struct ExerciseCandidate {
        let exercise: Exercise
        let analysis: ExerciseAnalysis
        let score: Double
    }

    private struct ExerciseAnalysis {
        let category: SmartWorkoutFocus
        let muscles: Set<String>
        let patterns: Set<MovementPattern>
    }

    private enum MovementPattern: Hashable {
        case squat, legPress, hinge, kneeFlexion, kneeExtension, calf
        case horizontalPress, verticalPress, horizontalPull, verticalPull
        case core, accessory
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
