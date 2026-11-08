package com.example.gymapp.ui.viewmodel

import java.io.File
import java.time.ZoneId
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/untrained-muscles-v1.json, the same cases the iOS suite runs. */
class UntrainedMusclesGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val contract = contract()
        val majors = contract.getJSONArray("majorMuscles").let { rows -> List(rows.length()) { rows.getString(it) } }
        assertEquals(majors, UNTRAINED_HINT_MUSCLE_IDS)
        val cases = contract.getJSONArray("cases")
        assertTrue(cases.length() >= 19)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val workouts = case.getJSONArray("workouts").let { rows -> List(rows.length()) { rows.getLong(it) } }
            val sets = case.getJSONArray("sets").let { rows ->
                List(rows.length()) { i ->
                    val row = rows.getJSONObject(i)
                    val muscles = row.getJSONObject("muscles")
                    UntrainedMuscleSet(
                        date = row.getLong("date"),
                        reps = row.getInt("reps"),
                        muscles = muscles.keys().asSequence().associateWith { muscles.getDouble(it) }
                    )
                }
            }
            val actual = untrainedMuscleIds(
                workoutDates = workouts,
                sets = sets,
                now = case.getLong("now"),
                zone = ZoneId.of(case.getString("timeZone"))
            )
            val expected = case.getJSONArray("expected").let { rows -> List(rows.length()) { rows.getString(it) } }
            if (actual != expected) {
                mismatches += "${case.getString("id")}: expected $expected but was $actual"
            }
        }
        assertEquals("Untrained muscles mismatches", emptyList<String>(), mismatches)
    }

    private fun contract(): JSONObject {
        val direct = File("shared/untrained-muscles-v1.json")
        val file = if (direct.isFile) direct else File("../shared/untrained-muscles-v1.json")
        check(file.isFile) { "Untrained muscles contract was not found." }
        return JSONObject(file.readText())
    }
}
