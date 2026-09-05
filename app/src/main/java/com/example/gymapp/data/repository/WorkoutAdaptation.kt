package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.*
import java.util.UUID

object WorkoutAdaptation {
    fun build(source: ActiveWorkoutDetails, reason: String, minutes: Int = 20,
              profiles: Map<Long, ExerciseLoadProfile> = emptyMap(),
              exerciseId: (ActiveWorkoutExerciseEntity) -> Long?, replacement: SmartWorkoutAlternative? = null): ActiveWorkoutDetails? {
        val blocks = source.exercises.toMutableList()
        when (reason) {
            "tooHard" -> blocks.indices.forEach { i ->
                val block = blocks[i]; val profile = exerciseId(block.activeWorkoutExercise)?.let(profiles::get)
                val assistance = profile?.direction == ExerciseLoadDirection.LowerIsHarder ||
                    (profile == null && block.activeWorkoutExercise.catalogKey in setOf("assisted_pull_up", "assisted_dip"))
                blocks[i] = block.copy(sets = block.sets.map { set -> if (set.completedAt != null) set else if (set.weight == 0.0)
                    set.copy(reps = (set.reps - 1).coerceAtLeast(1)) else set.copy(weight = TrainingTools.stepWeight(set.weight, if (assistance) 1 else -1, profile?.allowedWeightsKg.orEmpty())) })
            }
            "timeCut" -> {
                if (minutes !in listOf(10, 20, 30)) return null
                var budget = minutes * 60; var totalKept = 0
                val filtered = blocks.mapNotNull { block ->
                    var kept = 0
                    val sets = block.sets.filter { set ->
                        if (set.completedAt != null) true else {
                            val cost = 60 + if (kept > 0) WorkoutRecommendationEngine.recommendedRestSeconds(block.activeWorkoutExercise.exerciseName) else 0
                            if (budget < cost && totalKept > 0) false else { budget -= cost; kept++; totalKept++; true }
                        }
                    }
                    block.takeIf { sets.isNotEmpty() }?.copy(sets = sets)
                }
                blocks.clear(); blocks += filtered
            }
            "equipmentUnavailable" -> {
                val alternate = replacement ?: return null
                val index = blocks.indexOfFirst { it.sets.any { set -> set.completedAt == null } }
                if (index < 0 || alternate.recommendation.sets.isEmpty()) return null
                val old = blocks[index]; val completed = old.sets.filter { it.completedAt != null }; val pending = old.sets.filter { it.completedAt == null }
                val blockId = if (completed.isEmpty()) old.activeWorkoutExercise.id else UUID.randomUUID().toString()
                val exercise = ActiveWorkoutExerciseEntity(blockId, old.activeWorkoutExercise.activeWorkoutId,
                    alternate.exercise.name, com.example.gymapp.data.catalog.BuiltInExerciseCatalog.inferKey(alternate.exercise.name),
                    if (completed.isEmpty()) old.activeWorkoutExercise.orderIndex else old.activeWorkoutExercise.orderIndex + 1)
                val sets = pending.mapIndexed { i, set ->
                    val rec = alternate.recommendation.sets[minOf(i, alternate.recommendation.sets.lastIndex)]
                    set.copy(activeWorkoutExerciseId = blockId, weight = rec.weight ?: 0.0, reps = rec.reps, orderIndex = i)
                }
                val replacementBlock = ActiveWorkoutExerciseWithDetails(exercise, sets)
                blocks.removeAt(index)
                if (completed.isNotEmpty()) blocks.add(index, old.copy(sets = completed))
                blocks.add(index + if (completed.isEmpty()) 0 else 1, replacementBlock)
            }
            else -> return null
        }
        return source.copy(exercises = blocks.mapIndexed { i, block ->
            val owner = block.activeWorkoutExercise.copy(orderIndex = i)
            block.copy(activeWorkoutExercise = owner, sets = block.sets.mapIndexed { j, set -> set.copy(activeWorkoutExerciseId = owner.id, orderIndex = j) })
        })
    }
}
