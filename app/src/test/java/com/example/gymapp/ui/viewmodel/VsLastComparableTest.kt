package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The "is the comparison shown" rule of the post-workout summary; the cases are shared with iOS. */
class VsLastComparableTest {
    @Test
    fun sharedCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 8)
        val mismatches = (0 until cases.length()).map { cases.getJSONObject(it) }.mapNotNull { case ->
            val actual = isVsLastComparable(case.getInt("currentSetCount"), case.getInt("previousSetCount"))
            if (actual == case.getBoolean("shown")) null else "${case.getString("id")}: was $actual"
        }
        assertEquals(emptyList<String>(), mismatches)
    }

    @Test
    fun previousWorkoutIsTheLatestEarlierOneSharingAnExercise() {
        val history = listOf(
            entry(session = 1, date = 100, exercise = 1),
            entry(session = 2, date = 200, exercise = 1),
            entry(session = 2, date = 200, exercise = 1, set = 1),
            entry(session = 2, date = 200, exercise = 2),
            // Later but without a shared exercise: ignored.
            entry(session = 3, date = 300, exercise = 9),
            // The finished workout itself and anything after it: ignored.
            entry(session = 4, date = 400, exercise = 1),
            entry(session = 5, date = 500, exercise = 1)
        )
        assertEquals(
            3,
            previousWorkoutSetCount(setOf(1L), history, currentSessionId = 4, currentSessionDate = 400)
        )
        assertEquals(
            0,
            previousWorkoutSetCount(setOf(7L), history, currentSessionId = 4, currentSessionDate = 400)
        )
    }

    @Test
    fun exerciseSummariesKeepWorkoutOrderCountLoggedSetsAndPickTheBestSet() {
        val entries = listOf(
            entry(session = 4, date = 400, exercise = 2, block = 1, weight = 40.0, reps = 10),
            entry(session = 4, date = 400, exercise = 1, block = 0, weight = 60.0, reps = 8, set = 0),
            entry(session = 4, date = 400, exercise = 1, block = 0, weight = 62.5, reps = 6, set = 1),
            entry(session = 4, date = 400, exercise = 1, block = 0, weight = 80.0, reps = 0, set = 2)
        )
        val summaries = buildExerciseSummaries(entries)
        assertEquals(listOf(1L, 2L), summaries.map { it.exerciseId })
        assertEquals(2, summaries[0].setCount)
        assertEquals(VsLastSet(62.5, 6), summaries[0].best)
        assertEquals(1, summaries[1].setCount)
    }

    private fun entry(
        session: Long,
        date: Long,
        exercise: Long,
        set: Int = 0,
        block: Int = 0,
        weight: Double = 50.0,
        reps: Int = 8
    ) = ExerciseHistoryEntry(
        setId = session * 1000 + exercise * 10 + set,
        sessionId = session,
        sessionDate = date,
        exerciseId = exercise,
        exerciseName = "Exercise $exercise",
        weight = weight,
        reps = reps,
        setOrderIndex = set,
        blockOrderIndex = block
    )

    private fun contract(): JSONObject {
        val direct = File("shared/vs-last-comparable-v1.json")
        val file = if (direct.isFile) direct else File("../shared/vs-last-comparable-v1.json")
        check(file.isFile) { "Vs last comparable contract was not found." }
        return JSONObject(file.readText())
    }
}
