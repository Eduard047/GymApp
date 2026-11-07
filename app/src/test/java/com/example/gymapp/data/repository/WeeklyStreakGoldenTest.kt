package com.example.gymapp.data.repository

import java.io.File
import java.time.OffsetDateTime
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/weekly-streak-v1.json, the same cases the iOS suite runs. */
class WeeklyStreakGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val contract = contract()
        val zoneId = ZoneId.of(contract.getString("timezone"))
        val cases = contract.getJSONArray("cases")
        assertTrue(cases.length() >= 10)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val target = case.getInt("targetPerWeek")
            val now = millis(case.getString("now"))
            val sessions = case.getJSONArray("sessions").strings().map(::millis)
            val period = case.getJSONObject("period")
            val expected = case.getJSONObject("expected")

            assertEquals(
                "$id current",
                expected.getInt("current"),
                WeeklyStreakCalculator.current(sessions, target, now, zoneId)
            )
            assertEquals(
                "$id bestDuringPeriod",
                expected.getInt("bestDuringPeriod"),
                WeeklyStreakCalculator.bestDuringPeriod(
                    sessionTimestamps = sessions,
                    targetWorkoutsPerWeek = target,
                    periodStartMillis = millis(period.getString("start")),
                    periodEndMillis = millis(period.getString("end")),
                    zoneId = zoneId
                )
            )
            // Android has no separate "longest" function: it is the best streak over a period
            // that covers every session up to now.
            val pastSessions = sessions.filter { it <= now }
            val longest = if (pastSessions.isEmpty()) {
                0
            } else {
                WeeklyStreakCalculator.bestDuringPeriod(
                    sessionTimestamps = pastSessions,
                    targetWorkoutsPerWeek = target,
                    periodStartMillis = pastSessions.min(),
                    periodEndMillis = now,
                    zoneId = zoneId
                )
            }
            assertEquals("$id longest", expected.getInt("longest"), longest)
        }
    }

    private fun millis(iso: String): Long = OffsetDateTime.parse(iso).toInstant().toEpochMilli()

    private fun JSONArray.strings(): List<String> = List(length()) { getString(it) }

    private fun contract(): JSONObject {
        val direct = File("shared/weekly-streak-v1.json")
        val file = if (direct.isFile) direct else File("../shared/weekly-streak-v1.json")
        check(file.isFile) { "Weekly streak contract was not found." }
        return JSONObject(file.readText(Charsets.UTF_8))
    }
}
