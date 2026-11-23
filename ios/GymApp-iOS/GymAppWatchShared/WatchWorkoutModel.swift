import Foundation

/// Snapshot of a running Apple Watch workout. Foundation-only so the iPhone
/// test target can exercise it. The watch writes it to disk after every change,
/// so a killed app restores sets, start time, pauses and the selected exercise.
struct WatchActiveWorkout: Codable, Equatable, Sendable {
    var requestId: String
    var accountBinding: String
    var mode: WatchWorkoutMode
    var planRevision: Int64?
    /// Plan captured at Start. A plan pushed during the workout never changes it.
    var plan: [WatchPlanExercise]
    var startedAtMillis: Int64
    /// nil until an exercise is chosen (free workout before the first pick).
    var exerciseName: String?
    var draftWeight: Double
    var draftReps: Int
    var sets: [WatchWorkoutSet]
    var restEndsAtMillis: Int64?
    var undoUntilMillis: Int64?
    var pausedAtMillis: Int64?
    var pausedTotalMillis: Int64
    var heartRateEnabled: Bool
}

struct WatchSetPosition: Equatable, Sendable {
    /// 1-based set number shown to the user.
    let index: Int
    /// Planned set count; nil for an exercise outside the plan.
    let count: Int?
}

struct WatchPlanProgress: Equatable, Sendable {
    let name: String
    let done: Int
    let total: Int
}

/// Values shown on Summary and kept with an outbox item.
struct WatchWorkoutSummary: Codable, Equatable, Sendable {
    let durationSeconds: Int64
    let setCount: Int
    let volumeKilograms: Double
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let activeKilocalories: Double?
    let endedAtMillis: Int64
}

/// Pure reducer for the watch workout. Every function is deterministic in its inputs.
enum WatchWorkoutModel {
    static let undoWindowMillis: Int64 = 5_000
    static let restAddSeconds = 15
    static let fallbackWeight = 0.0
    static let fallbackReps = 10

    // MARK: Start

    /// Plan mode needs a non-empty plan; free mode starts with no exercise selected.
    static func start(
        mode: WatchWorkoutMode,
        context: WatchBoundContext,
        requestId: String,
        nowMillis: Int64,
        heartRateEnabled: Bool
    ) -> WatchActiveWorkout? {
        guard WatchSync.isValidRequestID(requestId), WatchSync.isValidHash(context.accountBinding) else { return nil }
        let plan = mode == .plan ? context.plan : []
        if mode == .plan, plan.isEmpty { return nil }
        var workout = WatchActiveWorkout(
            requestId: requestId,
            accountBinding: context.accountBinding,
            mode: mode,
            planRevision: mode == .plan ? context.planRevision : nil,
            plan: plan,
            startedAtMillis: nowMillis,
            exerciseName: plan.first?.name,
            draftWeight: fallbackWeight,
            draftReps: fallbackReps,
            sets: [],
            restEndsAtMillis: nil,
            undoUntilMillis: nil,
            pausedAtMillis: nil,
            pausedTotalMillis: 0,
            heartRateEnabled: heartRateEnabled
        )
        if let name = workout.exerciseName {
            (workout.draftWeight, workout.draftReps) = prefill(workout, exercise: name)
        }
        return workout
    }

    // MARK: Queries

    static func doneCount(_ workout: WatchActiveWorkout, exercise: String) -> Int {
        workout.sets.reduce(0) { $0 + ($1.exerciseName == exercise ? 1 : 0) }
    }

    static func planExercise(_ workout: WatchActiveWorkout, named name: String) -> WatchPlanExercise? {
        workout.plan.first { $0.name == name }
    }

    static func plannedNextSet(_ workout: WatchActiveWorkout, exercise: String) -> WatchPlanSet? {
        guard let planned = planExercise(workout, named: exercise) else { return nil }
        let done = doneCount(workout, exercise: exercise)
        return done < planned.sets.count ? planned.sets[done] : nil
    }

    /// Plan target for the next set, else the last logged values for this exercise, else 0 × 10.
    static func prefill(_ workout: WatchActiveWorkout, exercise: String) -> (weight: Double, reps: Int) {
        if let planned = plannedNextSet(workout, exercise: exercise) { return (planned.weight, planned.reps) }
        if let last = workout.sets.last(where: { $0.exerciseName == exercise }) { return (last.weight, last.reps) }
        return (fallbackWeight, fallbackReps)
    }

    /// "Set k of n" for plan exercises (stays "n of n" once the plan is done), "Set k" otherwise.
    static func setPosition(_ workout: WatchActiveWorkout) -> WatchSetPosition? {
        guard let name = workout.exerciseName else { return nil }
        let done = doneCount(workout, exercise: name)
        if let planned = planExercise(workout, named: name) {
            let count = planned.sets.count
            return WatchSetPosition(index: min(done + 1, count), count: count)
        }
        return WatchSetPosition(index: done + 1, count: nil)
    }

    static func planProgress(_ workout: WatchActiveWorkout) -> [WatchPlanProgress] {
        workout.plan.map { WatchPlanProgress(name: $0.name, done: doneCount(workout, exercise: $0.name), total: $0.sets.count) }
    }

    /// The first plan exercise with sets remaining (the picker opens there).
    static func firstUnfinishedPlanExercise(_ workout: WatchActiveWorkout) -> String? {
        planProgress(workout).first { $0.done < $0.total }?.name
    }

    static func restSeconds(_ workout: WatchActiveWorkout, exercise: String) -> Int {
        planExercise(workout, named: exercise)?.restSeconds ?? WatchSync.defaultRestSeconds
    }

    static func isPaused(_ workout: WatchActiveWorkout) -> Bool { workout.pausedAtMillis != nil }

    /// Remaining rest in whole seconds (rounded up); nil when not resting. Frozen while paused.
    static func restRemainingSeconds(_ workout: WatchActiveWorkout, nowMillis: Int64) -> Int? {
        guard let end = workout.restEndsAtMillis else { return nil }
        let reference = workout.pausedAtMillis ?? nowMillis
        let remaining = end - reference
        guard remaining > 0 else { return nil }
        return Int((remaining + 999) / 1_000)
    }

    static func canUndo(_ workout: WatchActiveWorkout, nowMillis: Int64) -> Bool {
        guard let until = workout.undoUntilMillis, !workout.sets.isEmpty, workout.pausedAtMillis == nil else { return false }
        return nowMillis < until
    }

    /// Elapsed time excluding pauses.
    static func activeMillis(_ workout: WatchActiveWorkout, nowMillis: Int64) -> Int64 {
        let reference = workout.pausedAtMillis ?? nowMillis
        return max(0, reference - workout.startedAtMillis - workout.pausedTotalMillis)
    }

    static func volume(_ sets: [WatchWorkoutSet]) -> Double {
        let total = sets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        return (total * 100).rounded() / 100
    }

    // MARK: Changes

    static func selectExercise(_ workout: inout WatchActiveWorkout, name: String) {
        guard WatchSync.isValidExerciseName(name) else { return }
        workout.exerciseName = name
        (workout.draftWeight, workout.draftReps) = prefill(workout, exercise: name)
    }

    /// Logs a set for the selected exercise, starts rest and opens the undo window.
    @discardableResult
    static func logSet(_ workout: inout WatchActiveWorkout, weight: Double, reps: Int, nowMillis: Int64) -> Bool {
        guard workout.pausedAtMillis == nil,
              let name = workout.exerciseName,
              workout.sets.count < WatchSync.maximumWorkoutSets else { return false }
        let normalized = WatchCrownSteps.normalizedWeight(weight)
        guard WatchSync.isValidWeight(normalized), WatchSync.repsRange.contains(reps) else { return false }
        workout.sets.append(WatchWorkoutSet(exerciseName: name, weight: normalized, reps: reps, completedAtMillis: nowMillis))
        (workout.draftWeight, workout.draftReps) = prefill(workout, exercise: name)
        let rest = restSeconds(workout, exercise: name)
        workout.restEndsAtMillis = rest > 0 ? nowMillis + Int64(rest) * 1_000 : nil
        workout.undoUntilMillis = nowMillis + undoWindowMillis
        return true
    }

    /// Removes the last set inside the undo window and returns to Working with its values.
    @discardableResult
    static func undo(_ workout: inout WatchActiveWorkout, nowMillis: Int64) -> Bool {
        guard canUndo(workout, nowMillis: nowMillis) else { return false }
        let removed = workout.sets.removeLast()
        workout.exerciseName = removed.exerciseName
        workout.draftWeight = removed.weight
        workout.draftReps = removed.reps
        workout.restEndsAtMillis = nil
        workout.undoUntilMillis = nil
        return true
    }

    static func endUndoWindow(_ workout: inout WatchActiveWorkout) {
        workout.undoUntilMillis = nil
    }

    static func addRest(_ workout: inout WatchActiveWorkout, nowMillis: Int64) {
        guard restRemainingSeconds(workout, nowMillis: nowMillis) != nil, let end = workout.restEndsAtMillis else { return }
        workout.restEndsAtMillis = end + Int64(restAddSeconds) * 1_000
        workout.undoUntilMillis = nil
    }

    static func skipRest(_ workout: inout WatchActiveWorkout) {
        workout.restEndsAtMillis = nil
        workout.undoUntilMillis = nil
    }

    static func pause(_ workout: inout WatchActiveWorkout, nowMillis: Int64) {
        guard workout.pausedAtMillis == nil else { return }
        workout.pausedAtMillis = nowMillis
        workout.undoUntilMillis = nil
    }

    /// Resuming shifts the rest end by the paused time, so timers stay frozen during a pause.
    static func resume(_ workout: inout WatchActiveWorkout, nowMillis: Int64) {
        guard let pausedAt = workout.pausedAtMillis else { return }
        let paused = max(0, nowMillis - pausedAt)
        workout.pausedTotalMillis += paused
        if let end = workout.restEndsAtMillis { workout.restEndsAtMillis = end + paused }
        workout.pausedAtMillis = nil
    }

    // MARK: Finish

    /// The finished workout message, or nil when no set was logged (such a workout can only be discarded).
    static func finish(
        _ workout: WatchActiveWorkout,
        endedAtMillis: Int64,
        healthKit: WatchHealthKitStatus,
        averageHeartRate: Double?,
        maximumHeartRate: Double?,
        activeKilocalories: Double?
    ) -> WatchWorkoutMessage? {
        guard !workout.sets.isEmpty else { return nil }
        let lastSet = workout.sets.map(\.completedAtMillis).max() ?? workout.startedAtMillis
        let ended = max(endedAtMillis, workout.startedAtMillis + 1_000, lastSet - WatchSync.setTimeToleranceMillis + 1)
        let wallSeconds = (ended - workout.startedAtMillis + 999) / 1_000
        let activeSeconds = activeMillis(workout, nowMillis: ended) / 1_000
        let duration = min(max(1, min(activeSeconds, wallSeconds)), WatchSync.durationSecondsRange.upperBound)

        var average: Int?
        var maximum: Int?
        if let avg = averageHeartRate, let max = maximumHeartRate, avg.isFinite, max.isFinite {
            let roundedAverage = Int(avg.rounded())
            let roundedMaximum = Int(max.rounded())
            if WatchSync.heartRateRange.contains(roundedAverage),
               WatchSync.heartRateRange.contains(roundedMaximum),
               roundedAverage <= roundedMaximum {
                average = roundedAverage
                maximum = roundedMaximum
            }
        }
        var kilocalories: Double?
        if let value = activeKilocalories, value.isFinite, value > 0 {
            let rounded = (value * 10).rounded() / 10
            if WatchSync.activeKilocaloriesRange.contains(rounded) { kilocalories = rounded }
        }

        return WatchWorkoutMessage(
            requestId: workout.requestId,
            accountBinding: workout.accountBinding,
            mode: workout.mode,
            planRevision: workout.mode == .plan ? workout.planRevision : nil,
            startedAtMillis: workout.startedAtMillis,
            endedAtMillis: ended,
            durationSeconds: duration,
            sets: workout.sets,
            healthKit: healthKit,
            averageHeartRate: average,
            maximumHeartRate: maximum,
            activeKilocalories: kilocalories
        )
    }

    static func summary(_ message: WatchWorkoutMessage) -> WatchWorkoutSummary {
        WatchWorkoutSummary(
            durationSeconds: message.durationSeconds,
            setCount: message.sets.count,
            volumeKilograms: volume(message.sets),
            averageHeartRate: message.averageHeartRate,
            maximumHeartRate: message.maximumHeartRate,
            activeKilocalories: message.activeKilocalories,
            endedAtMillis: message.endedAtMillis
        )
    }
}

/// Heart-rate zones as % of maximum heart rate: <60, 60–70, 70–80, 80–90, ≥90.
enum WatchHeartRateZone {
    /// Owner decision for v1: zones use a maximum heart rate of 190.
    static let defaultMaximumHeartRate = 190

    static func zone(bpm: Int, maximumHeartRate: Int = defaultMaximumHeartRate) -> Int? {
        guard bpm > 0, maximumHeartRate > 0 else { return nil }
        let percent = Double(bpm) * 100 / Double(maximumHeartRate)
        switch percent {
        case ..<60: return 1
        case ..<70: return 2
        case ..<80: return 3
        case ..<90: return 4
        default: return 5
        }
    }
}
