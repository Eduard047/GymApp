package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/plan-seed-last-session-v1.json, the same cases the iOS suite runs. */
class PlanSeedLastSessionGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 12)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val history = case.getJSONArray("history").let { rows ->
                List(rows.length()) { i -> rows.getJSONObject(i).toEntry(i.toLong()) }
            }
            val actual = lastSessionSetSeed(history, case.getLong("exerciseId"))
            val expected = case.optJSONArray("expected")?.let { rows ->
                List(rows.length()) { i ->
                    rows.getJSONObject(i).let { SetSeed(it.getDouble("weight"), it.getInt("reps")) }
                }
            }
            if (actual != expected) mismatches += "${case.getString("id")}: expected $expected but was $actual"
        }
        assertEquals("Plan seed mismatches", emptyList<String>(), mismatches)
    }

    @Test
    fun seedReplacesOnlyAnUntouchedDefaultCard() {
        val seed = listOf(SetSeed(60.0, 10), SetSeed(0.0, 8), SetSeed(52.5, 6))
        val fresh = appendExerciseDraft(emptyList(), draftId = 1L, exerciseId = 5L)
        val seeded = withSeedSetsIfPristine(fresh, 1L, seed).single().sets
        assertEquals(listOf("60" to "10", "0" to "8", "52.5" to "6"), seeded.map { it.weight to it.reps })

        val typed = fresh.map { it.copy(sets = listOf(SetInputState(weight = "70", reps = "10"))) }
        assertEquals(typed, withSeedSetsIfPristine(typed, 1L, seed))
        val editedReps = fresh.map { it.copy(sets = listOf(SetInputState(weight = "", reps = "6"))) }
        assertEquals(editedReps, withSeedSetsIfPristine(editedReps, 1L, seed))
        assertEquals(fresh, withSeedSetsIfPristine(fresh, 2L, seed))
    }

    private fun JSONObject.toEntry(setId: Long) = ExerciseHistoryEntry(
        setId = setId,
        sessionId = getLong("sessionId"),
        sessionDate = getLong("date"),
        exerciseId = getLong("exerciseId"),
        exerciseName = "Exercise",
        weight = getDouble("weight"),
        reps = getInt("reps"),
        setOrderIndex = getInt("setOrderIndex"),
        blockOrderIndex = getInt("blockOrderIndex")
    )

    private fun contract(): JSONObject {
        val direct = File("shared/plan-seed-last-session-v1.json")
        val file = if (direct.isFile) direct else File("../shared/plan-seed-last-session-v1.json")
        check(file.isFile) { "Plan seed contract was not found." }
        return JSONObject(file.readText())
    }
}
