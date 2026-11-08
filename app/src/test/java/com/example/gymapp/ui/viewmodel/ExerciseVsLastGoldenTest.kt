package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import java.io.File
import kotlin.math.abs
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/exercise-vs-last-v1.json, the same cases the iOS suite runs. */
class ExerciseVsLastGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 15)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val current = case.getJSONObject("currentSession")
            val currentId = current.getLong("id")
            val currentDate = current.getLong("date")
            val history = case.getJSONArray("history").let { rows ->
                List(rows.length()) { i -> rows.getJSONObject(i).toEntry(i.toLong()) }
            }
            val actual = buildExerciseVsLast(
                currentEntries = history.filter { it.sessionId == currentId },
                allHistory = history,
                currentSessionId = currentId,
                currentSessionDate = currentDate
            )
            val expected = case.getJSONArray("expected")
            val id = case.getString("id")
            if (actual.size != expected.length()) {
                mismatches += "$id: expected ${expected.length()} rows but was ${actual.size}: $actual"
                continue
            }
            for (i in actual.indices) {
                val want = expected.getJSONObject(i)
                val got = actual[i]
                val problems = mutableListOf<String>()
                if (got.exerciseId != want.getLong("exerciseId")) problems += "exerciseId ${got.exerciseId}"
                if (got.status.wire != want.getString("status")) problems += "status ${got.status.wire}"
                val wantBasis = if (want.isNull("basis")) null else want.getString("basis")
                if (got.basis?.wire != wantBasis) problems += "basis ${got.basis?.wire}"
                val wantDelta = if (want.isNull("delta")) null else want.getDouble("delta")
                if ((got.delta == null) != (wantDelta == null) ||
                    (got.delta != null && abs(got.delta - wantDelta!!) > 1e-9)
                ) {
                    problems += "delta ${got.delta}"
                }
                val wantBest = want.getJSONObject("best")
                if (got.best != VsLastSet(wantBest.getDouble("weight"), wantBest.getInt("reps"))) {
                    problems += "best ${got.best}"
                }
                val wantPrev = if (want.isNull("previousBest")) null else want.getJSONObject("previousBest")
                    .let { VsLastSet(it.getDouble("weight"), it.getInt("reps")) }
                if (got.previousBest != wantPrev) problems += "previousBest ${got.previousBest}"
                if (problems.isNotEmpty()) mismatches += "$id[$i]: ${problems.joinToString()} (want $want)"
            }
        }
        assertEquals("Exercise vs last mismatches", emptyList<String>(), mismatches)
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
        val direct = File("shared/exercise-vs-last-v1.json")
        val file = if (direct.isFile) direct else File("../shared/exercise-vs-last-v1.json")
        check(file.isFile) { "Exercise vs last contract was not found." }
        return JSONObject(file.readText())
    }
}
