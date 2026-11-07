package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import java.io.File
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SmartCoachProgressionGoldenTest {
    @Test
    fun sharedProgressionVectorsMatchAndroidPerExerciseEngine() {
        val root = JSONObject(sharedFixture().readText())
        assertEquals(1, root.getInt("contractVersion"))
        val nowMillis = root.getLong("nowEpochMillis")
        val vectors = root.getJSONArray("vectors")
        assertTrue(vectors.length() >= 8)

        repeat(vectors.length()) { index ->
            val vector = vectors.getJSONObject(index)
            val name = vector.getString("name")
            val expected = vector.getJSONObject("expected")
            val recommendation = recommend(vector, nowMillis)

            assertEquals(name, expected.getString("kind"), recommendation.kind.name.replaceFirstChar(Char::lowercase))
            assertEquals(name, expected.getJSONArray("targetRir").getInt(0), recommendation.targetRir.first)
            assertEquals(name, expected.getJSONArray("targetRir").getInt(1), recommendation.targetRir.last)
            val sets = expected.getJSONArray("sets")
            assertEquals(name, sets.length(), recommendation.sets.size)
            repeat(sets.length()) { setIndex ->
                val set = sets.getJSONObject(setIndex)
                val actual = recommendation.sets[setIndex]
                if (set.isNull("weight")) {
                    assertEquals("$name set $setIndex weight", null, actual.weight)
                } else {
                    assertEquals("$name set $setIndex weight", set.getDouble("weight"), actual.weight ?: Double.NaN, 0.0001)
                }
                assertEquals("$name set $setIndex reps", set.getInt("reps"), actual.reps)
            }
        }
    }

    private fun recommend(vector: JSONObject, nowMillis: Long): WorkoutRecommendation {
        val profile = vector.getJSONObject("trainingProfile")
        val exerciseName = vector.getString("exerciseName")
        val dayMillis = 86_400_000L
        val history = vector.getJSONArray("history").let { entries ->
            List(entries.length()) { i ->
                val entry = entries.getJSONObject(i)
                val daysAgo = entry.getInt("daysAgo")
                ExerciseHistoryEntry(
                    setId = i + 1L,
                    sessionId = 1_000L + daysAgo,
                    sessionDate = nowMillis - daysAgo * dayMillis,
                    exerciseId = 1L,
                    exerciseName = exerciseName,
                    weight = entry.getDouble("weight"),
                    reps = entry.getInt("reps"),
                    setOrderIndex = entry.getInt("setOrder")
                )
            }
        }
        val loadProfile = vector.optJSONObject("loadProfile")?.let {
            ExerciseLoadProfile(
                direction = ExerciseLoadDirection.entries.first { d -> d.wireValue == it.getString("direction") },
                allowedWeightsKg = it.getJSONArray("allowedWeightsKg").doubles()
            )
        }
        return WorkoutRecommendationEngine.buildForExercise(
            exerciseId = 1L,
            history = history,
            trainingProfile = TrainingProfile(
                split = TrainingSplit.entries.first { it.name.equals(profile.getString("split"), ignoreCase = true) },
                workoutsPerWeek = profile.getInt("workoutsPerWeek"),
                goal = TrainingGoal.entries.first { it.name.equals(profile.getString("goal"), ignoreCase = true) },
                calorieMode = CalorieMode.entries.first { it.name.equals(profile.getString("calorieMode"), ignoreCase = true) }
            ),
            nowMillis = nowMillis + vector.getInt("nowOffsetDays") * dayMillis,
            zoneId = ZoneId.of("UTC"),
            exerciseName = exerciseName,
            loadProfile = loadProfile,
            effort = SmartWorkoutEffort.entries.first { it.name.equals(vector.getString("effort"), ignoreCase = true) }
        )
    }

    private fun JSONArray.doubles(): List<Double> = List(length()) { getDouble(it) }

    private fun sharedFixture(): File {
        val direct = File("shared/smart-coach-progression-v1.json")
        if (direct.isFile) return direct
        return File("../shared/smart-coach-progression-v1.json").also {
            check(it.isFile) { "Shared Smart Coach progression fixture was not found." }
        }
    }
}
