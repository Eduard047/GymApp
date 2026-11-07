package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import java.io.File
import java.time.ZoneId
import java.util.Locale
import kotlin.math.roundToLong
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/e1rm-trend-v1.json, the same cases the iOS suite runs. */
class ExerciseOneRepMaxTrendGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 6)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val expected = case.getJSONObject("expected")

            val history = historyOf(case.getJSONArray("sessions"))
            val points = history.toExerciseProgressPoints()

            val expectedPoints = expected.getJSONArray("points")
            assertEquals("$id point count", expectedPoints.length(), points.size)
            for (pointIndex in 0 until expectedPoints.length()) {
                val expectedPoint = expectedPoints.getJSONObject(pointIndex)
                val point = points[pointIndex]
                assertEquals("$id session order", expectedPoint.getLong("session"), point.sessionId)
                if (expectedPoint.isNull("e1rm")) {
                    assertEquals("$id session ${point.sessionId}", null, point.estimatedOneRepMax)
                } else {
                    assertEquals(
                        "$id session ${point.sessionId}",
                        expectedPoint.getDouble("e1rm"),
                        rounded(point.estimatedOneRepMax ?: Double.NaN),
                        0.0
                    )
                }
            }

            val chart = ExerciseProgressTextBuilder("en", ZoneId.of("UTC")).buildTrendChart(points)
            assertEquals("$id chart visible", expected.getBoolean("chartVisible"), chart.oneRepMaxPoints.isNotEmpty())
            if (expected.getBoolean("chartVisible")) {
                assertTrue("$id charted sessions", chart.oneRepMaxPoints.size >= 2)
                assertTrue(chart.oneRepMaxPoints.all { it.estimatedOneRepMax != null })
            }
            if (expected.isNull("bestE1rm")) {
                assertEquals("$id best", null, chart.bestOneRepMaxLabel)
            } else {
                assertEquals(
                    "$id best",
                    formatProgressWeightLabel(expected.getDouble("bestE1rm"), Locale.ENGLISH, "kg"),
                    chart.bestOneRepMaxLabel
                )
            }
        }
    }

    private fun historyOf(sessions: org.json.JSONArray): List<ExerciseHistoryEntry> {
        val entries = mutableListOf<ExerciseHistoryEntry>()
        var setId = 1L
        for (sessionIndex in 0 until sessions.length()) {
            val session = sessions.getJSONObject(sessionIndex)
            val sets = session.getJSONArray("sets")
            for (setIndex in 0 until sets.length()) {
                val set = sets.getJSONObject(setIndex)
                entries += ExerciseHistoryEntry(
                    setId = setId++,
                    sessionId = session.getLong("id"),
                    sessionDate = session.getLong("date") * 86_400_000L,
                    exerciseId = 1L,
                    exerciseName = "Bench Press",
                    weight = set.getDouble("weight"),
                    reps = set.getInt("reps"),
                    setOrderIndex = setIndex
                )
            }
        }
        return entries
    }

    private fun rounded(value: Double): Double = (value * 10).roundToLong() / 10.0

    private fun contract(): JSONObject {
        val direct = File("shared/e1rm-trend-v1.json")
        val file = if (direct.isFile) direct else File("../shared/e1rm-trend-v1.json")
        check(file.isFile) { "E1RM trend contract was not found." }
        return JSONObject(file.readText())
    }
}
