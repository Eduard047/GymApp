import Foundation

public enum SmartCoachReadinessV2: String, Codable, CaseIterable, Hashable, Sendable {
    case low, normal, high
}

public enum SmartCoachEquipmentV2: String, Codable, CaseIterable, Hashable, Sendable {
    case barbell, dumbbell, cable, machine, bodyweight, assisted, band, other
}

public enum SmartCoachExerciseFeedbackOutcomeV2: String, Codable, CaseIterable, Hashable, Sendable {
    case onTarget, tooEasy, tooHard, equipmentUnavailable, timeCut
}

public enum SmartCoachV2Reason: String, Codable, CaseIterable, Hashable, Sendable {
    case readinessRecovery
    case timeCapped
    case equipmentUnavailable
    case avoidedMuscle
    case exerciseFeedbackTooHard
    case exerciseFeedbackRepeatedEasy
}

public enum SmartCoachExerciseRoleV2: String, Codable, CaseIterable, Hashable, Sendable {
    case primary, secondary, isolation, core, warmup
}

public struct SmartCoachExerciseFeedbackSignalV2: Codable, Hashable, Sendable {
    public let actualRIR: Int?
    public let outcome: SmartCoachExerciseFeedbackOutcomeV2
    public let ageDays: Int

    public init(
        actualRIR: Int? = nil,
        outcome: SmartCoachExerciseFeedbackOutcomeV2 = .onTarget,
        ageDays: Int
    ) {
        self.actualRIR = actualRIR
        self.outcome = outcome
        self.ageDays = ageDays
    }
}

public struct SmartCoachContextV2: Codable, Hashable, Sendable {
    public static let minimumAvailableMinutes = 30
    public static let maximumAvailableMinutes = 120
    public static let maximumEquipmentItems = 8
    public static let maximumAvoidedMuscles = 8
    public static let knownMuscleIDs: Set<String> = [
        "chest", "shoulders", "biceps", "triceps", "forearms", "abs", "obliques",
        "lats", "upperBack", "lowerBack", "glutes", "quads", "hamstrings",
        "adductors", "calves"
    ]

    public let readiness: SmartCoachReadinessV2?
    public let availableMinutes: Int?
    /// Nil is unrestricted. A present set must contain 1...8 canonical values.
    public let availableEquipment: Set<SmartCoachEquipmentV2>?
    public let musclesToAvoid: Set<String>

    public init(
        readiness: SmartCoachReadinessV2? = nil,
        availableMinutes: Int? = nil,
        availableEquipment: Set<SmartCoachEquipmentV2>? = nil,
        musclesToAvoid: Set<String> = []
    ) {
        self.readiness = readiness
        self.availableMinutes = availableMinutes
        self.availableEquipment = availableEquipment
        self.musclesToAvoid = musclesToAvoid
    }

    public var isValid: Bool {
        (availableMinutes.map {
            (Self.minimumAvailableMinutes ... Self.maximumAvailableMinutes).contains($0)
        } ?? true) &&
            (availableEquipment.map { (1 ... Self.maximumEquipmentItems).contains($0.count) } ?? true) &&
            musclesToAvoid.count <= Self.maximumAvoidedMuscles &&
            musclesToAvoid.isSubset(of: Self.knownMuscleIDs)
    }
}

public struct SmartCoachV2Scenario: Sendable {
    public let requestedEffort: SmartWorkoutEffort
    public let baseSetBudget: Int
    public let role: SmartCoachExerciseRoleV2
    public let equipment: SmartCoachEquipmentV2
    public let primaryMuscles: Set<String>
    public let context: SmartCoachContextV2
    /// Newest first. Invalid or stale values are ignored, never coerced.
    public let feedback: [SmartCoachExerciseFeedbackSignalV2]

    public init(
        requestedEffort: SmartWorkoutEffort,
        baseSetBudget: Int,
        role: SmartCoachExerciseRoleV2,
        equipment: SmartCoachEquipmentV2,
        primaryMuscles: Set<String> = [],
        context: SmartCoachContextV2 = SmartCoachContextV2(),
        feedback: [SmartCoachExerciseFeedbackSignalV2] = []
    ) {
        self.requestedEffort = requestedEffort
        self.baseSetBudget = baseSetBudget
        self.role = role
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.context = context
        self.feedback = feedback
    }
}

public struct SmartCoachV2Adaptation: Equatable, Sendable {
    public let eligible: Bool
    public let appliedEffort: SmartWorkoutEffort
    public let setBudget: Int
    public let targetRIR: ClosedRange<Int>
    public let restSeconds: Int
    public let loadAdjustmentSteps: Int
    public let confidenceDelta: Float
    public let freshForSeconds: Int
    public let reasons: [SmartCoachV2Reason]
}

public let smartCoachV2ContractVersion = 2
public let smartCoachV2FreshForSeconds = 6 * 60 * 60
public let smartCoachV2MaximumFeedbackAgeDays = 14
public let smartCoachV2MaximumFeedbackPerExercise = 8

/// Pure policy layer shared by the real engine and the cross-client golden vectors.
public func resolveSmartCoachV2(_ scenario: SmartCoachV2Scenario) -> SmartCoachV2Adaptation {
    precondition((12 ... 24).contains(scenario.baseSetBudget))
    precondition(scenario.primaryMuscles.isSubset(of: SmartCoachContextV2.knownMuscleIDs))
    precondition(scenario.context.isValid)

    var reasons: [SmartCoachV2Reason] = []
    let appliedEffort: SmartWorkoutEffort
    if scenario.context.readiness == .low {
        appliedEffort = .recovery
        reasons.append(.readinessRecovery)
    } else if scenario.requestedEffort == .auto {
        appliedEffort = .standard
    } else {
        appliedEffort = scenario.requestedEffort
    }
    let timeCap = scenario.context.availableMinutes.map { min(24, max(12, $0 / 3)) }
    let setBudget = min(scenario.baseSetBudget, timeCap ?? scenario.baseSetBudget)
    if setBudget < scenario.baseSetBudget { reasons.append(.timeCapped) }

    var eligible = true
    if let available = scenario.context.availableEquipment,
       !available.contains(scenario.equipment) {
        eligible = false
        reasons.append(.equipmentUnavailable)
    }
    if !scenario.primaryMuscles.isDisjoint(with: scenario.context.musclesToAvoid) {
        eligible = false
        reasons.append(.avoidedMuscle)
    }

    let usableFeedback = scenario.feedback
        .prefix(smartCoachV2MaximumFeedbackPerExercise)
        .filter { signal in
            (0 ... smartCoachV2MaximumFeedbackAgeDays).contains(signal.ageDays) &&
                (signal.actualRIR.map { (0 ... 5).contains($0) } ?? true) &&
                ![.equipmentUnavailable, .timeCut].contains(signal.outcome)
        }
    let latest = usableFeedback.first
    let latestIsHard = latest?.outcome == .tooHard || latest?.actualRIR.map { $0 <= 1 } == true
    let firstTwo = Array(usableFeedback.prefix(2))
    let firstTwoAreEasy = firstTwo.count == 2 && firstTwo.allSatisfy { signal in
        signal.outcome == .tooEasy || signal.actualRIR.map { $0 >= 4 } == true
    }
    let loadAdjustmentSteps: Int
    if latestIsHard {
        loadAdjustmentSteps = -1
        reasons.append(.exerciseFeedbackTooHard)
    } else if firstTwoAreEasy {
        loadAdjustmentSteps = 1
        reasons.append(.exerciseFeedbackRepeatedEasy)
    } else {
        loadAdjustmentSteps = 0
    }

    let targetRIR: ClosedRange<Int>
    if latestIsHard || appliedEffort == .recovery {
        targetRIR = 3 ... 4
    } else if appliedEffort == .hard && [.primary, .secondary].contains(scenario.role) {
        targetRIR = 1 ... 2
    } else {
        targetRIR = 2 ... 3
    }
    let restSeconds = switch scenario.role {
    case .primary: 180
    case .secondary: 120
    case .isolation: 75
    case .core, .warmup: 60
    }
    return SmartCoachV2Adaptation(
        eligible: eligible,
        appliedEffort: appliedEffort,
        setBudget: setBudget,
        targetRIR: targetRIR,
        restSeconds: restSeconds,
        loadAdjustmentSteps: loadAdjustmentSteps,
        confidenceDelta: loadAdjustmentSteps == 0 ? 0 : 0.05,
        freshForSeconds: smartCoachV2FreshForSeconds,
        reasons: Array(reasons.prefix(4))
    )
}
