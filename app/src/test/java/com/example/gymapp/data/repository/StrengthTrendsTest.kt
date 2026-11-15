package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import java.io.File
import java.time.Instant
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/strength-trends-v1.json, the same cases the iOS suite runs. */
class StrengthTrendsTest {
    private val now = Instant.parse("2026-11-16T12:00:00Z").toEpochMilli()
    private val day = 24L * 60L * 60L * 1000L

    @Test
    fun sharedCasesMatchTheContract() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 6)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val sets = case.getJSONArray("sets")
            val history = (0 until sets.length()).map { i ->
                val set = sets.getJSONObject(i)
                val exercise = set.getLong("exercise")
                ExerciseHistoryEntry(
                    setId = i.toLong() + 1,
                    sessionId = exercise * 1000 + set.getLong("daysAgo"),
                    sessionDate = now - set.getLong("daysAgo") * day,
                    exerciseId = exercise,
                    exerciseName = "Exercise $exercise",
                    weight = set.getDouble("weight"),
                    reps = set.getInt("reps"),
                    setOrderIndex = i
                )
            }
            val expected = case.getJSONArray("expected")
            val actual = buildStrengthTrends(history, now)
            assertEquals("$id row count", expected.length(), actual.size)
            for (row in 0 until expected.length()) {
                val want = expected.getJSONObject(row)
                val got = actual[row]
                assertEquals("$id exercise", want.getLong("exercise"), got.exerciseId)
                assertEquals("$id weight", want.getDouble("bestWeight"), got.bestWeight, 1e-9)
                assertEquals("$id reps", want.getInt("bestReps"), got.bestReps)
                if (want.isNull("monthDelta")) {
                    assertNull("$id delta", got.deltaKg)
                } else {
                    assertEquals("$id delta", want.getDouble("monthDelta"), got.deltaKg!!, 1e-9)
                }
            }
        }
    }

    private fun contract(): JSONObject {
        val direct = File("shared/strength-trends-v1.json")
        val file = if (direct.isFile) direct else File("../shared/strength-trends-v1.json")
        check(file.isFile) { "Strength trends contract was not found." }
        return JSONObject(file.readText())
    }
}
