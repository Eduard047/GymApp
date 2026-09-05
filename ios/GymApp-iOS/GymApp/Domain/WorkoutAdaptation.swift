import Foundation

enum WorkoutAdaptation {
    static func build(_ source: ActiveWorkoutDraft, reason: String, minutes: Int = 20,
                      catalog: [Exercise], replacement: SmartWorkoutAlternative? = nil) -> ActiveWorkoutDraft? {
        guard source.commitIntent == nil else { return nil }
        var result = source
        if reason == "tooHard" {
            for i in result.exercises.indices {
                let exercise = catalog.first { $0.id == result.exercises[i].exerciseID }
                let profile = exercise?.machineLoadProfile
                let assistance = profile?.direction == .lowerIsHarder || (profile == nil && ["assisted_pull_up", "assisted_dip"].contains(exercise?.catalogKey ?? ""))
                for j in result.exercises[i].sets.indices where !result.exercises[i].sets[j].isCompleted {
                    let set = result.exercises[i].sets[j]
                    if set.weight == 0 { result.exercises[i].sets[j].reps = max(1, set.reps - 1) }
                    else { result.exercises[i].sets[j].weight = TrainingTools.stepWeight(set.weight, direction: assistance ? 1 : -1, allowed: profile?.allowedWeightsKg ?? []) }
                }
            }
        } else if reason == "timeCut", [10, 20, 30].contains(minutes) {
            var budget = minutes * 60
            var totalKept = 0
            result.exercises = source.exercises.compactMap { exercise in
                var block = exercise
                var kept = 0
                let rest = RecommendationEngine.restDurationSeconds(exerciseCatalogKey: exercise.exerciseCatalogKey, exerciseName: exercise.exerciseName ?? catalog.first { $0.id == exercise.exerciseID }?.name ?? "")
                block.sets = exercise.sets.filter { set in
                    if set.isCompleted { return true }
                    let cost = 60 + (kept > 0 ? rest : 0)
                    if budget < cost && totalKept > 0 { return false }
                    budget -= cost; kept += 1; totalKept += 1
                    return true
                }
                return block.sets.isEmpty ? nil : block
            }
        } else if reason == "equipmentUnavailable", let replacement,
                  let index = source.exercises.firstIndex(where: { $0.sets.contains(where: { !$0.isCompleted }) }),
                  !replacement.recommendation.sets.isEmpty {
            let block = source.exercises[index]
            let completed = block.sets.filter(\.isCompleted)
            let pending = block.sets.filter { !$0.isCompleted }
            let sets = pending.enumerated().map { i, set -> ActiveWorkoutSet in
                let recommended = replacement.recommendation.sets[min(i, replacement.recommendation.sets.count - 1)]
                return ActiveWorkoutSet(id: set.id, weight: recommended.weight ?? 0, reps: recommended.reps)
            }
            let updated = ActiveWorkoutExercise(id: completed.isEmpty ? block.id : UUID(), exerciseID: replacement.exercise.id,
                exerciseName: replacement.exercise.name, exerciseCatalogKey: replacement.exercise.catalogKey, sets: sets)
            var retained = block
            retained.sets = completed
            result.exercises.replaceSubrange(index ... index, with: completed.isEmpty ? [updated] : [retained, updated])
        } else { return nil }
        return result
    }

    static func preservesCompleted(_ source: ActiveWorkoutDraft, _ candidate: ActiveWorkoutDraft) -> Bool {
        let old = source.exercises.flatMap { block in block.sets.filter(\.isCompleted).map { (block.exerciseID, $0) } }
        let new = candidate.exercises.flatMap { block in block.sets.filter(\.isCompleted).map { (block.exerciseID, $0) } }
        return old.count == new.count && old.allSatisfy { id, set in new.contains { $0.0 == id && $0.1 == set } }
    }
}
