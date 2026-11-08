package com.example.gymapp.ui.viewmodel

import java.io.File
import java.time.ZoneId
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/biggest-workout-v1.json, the same cases the iOS suite runs. */
class BiggestWorkoutGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 19)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val earlier = case.getJSONArray("earlier").let { rows ->
                List(rows.length()) { i ->
                    rows.getJSONObject(i).let {
                        BiggestWorkoutSession(it.getLong("id"), it.getLong("date"), it.getDouble("volume"))
                    }
                }
            }
            val current = case.getJSONObject("current")
            val actual = biggestWorkoutBadge(
                earlier = earlier,
                currentDate = current.getLong("date"),
                currentVolume = current.getDouble("volume"),
                zone = ZoneId.of(case.getString("timeZone"))
            )
            val expected = if (case.isNull("expected")) null else case.getString("expected")
            if (actual?.wire != expected) {
                mismatches += "${case.getString("id")}: expected $expected but was ${actual?.wire}"
            }
        }
        assertEquals("Biggest workout mismatches", emptyList<String>(), mismatches)
    }

    private fun contract(): JSONObject {
        val direct = File("shared/biggest-workout-v1.json")
        val file = if (direct.isFile) direct else File("../shared/biggest-workout-v1.json")
        check(file.isFile) { "Biggest workout contract was not found." }
        return JSONObject(file.readText())
    }
}
