package com.example.gymapp.ui.viewmodel

import com.example.gymapp.ui.screens.formatWeekVolumeDelta
import java.io.File
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/week-volume-delta-v1.json, the same cases the iOS suite runs. */
class WeekVolumeDeltaGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 12)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val zone = ZoneId.of(case.getString("zone"))
            val sessions = case.getJSONArray("sessions")
            val samples = (0 until sessions.length()).map {
                val row = sessions.getJSONObject(it)
                WeekVolumeSample(millis(row.getString("at"), zone), row.getDouble("volume"))
            }
            val actual = weekVolumeDeltaPercent(
                samples = samples,
                nowMillis = millis(case.getString("now"), zone),
                zoneId = zone,
                weekOffset = case.getInt("weekOffset")
            )
            val expected = if (case.isNull("expectedPercent")) null else case.getInt("expectedPercent")
            assertEquals(id, expected, actual)
        }
    }

    @Test
    fun resultDoesNotDependOnTheDeviceTimeZone() {
        val original = java.util.TimeZone.getDefault()
        try {
            for (zone in listOf("UTC", "Pacific/Kiritimati", "America/Los_Angeles")) {
                java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone(zone))
                sharedGoldenCasesMatchIos()
            }
        } finally {
            java.util.TimeZone.setDefault(original)
        }
    }

    @Test
    fun displayUsesTrueMinusSignAndNoSignForZero() {
        assertEquals("+12%", formatWeekVolumeDelta(12, Locale.ENGLISH))
        assertEquals("−8%", formatWeekVolumeDelta(-8, Locale.ENGLISH))
        assertEquals("0%", formatWeekVolumeDelta(0, Locale.ENGLISH))
        assertEquals("+999%", formatWeekVolumeDelta(999, Locale.ENGLISH))
    }

    private fun millis(local: String, zone: ZoneId): Long =
        LocalDateTime.parse(local).atZone(zone).toInstant().toEpochMilli()

    private fun contract(): JSONObject {
        val direct = File("shared/week-volume-delta-v1.json")
        val file = if (direct.isFile) direct else File("../shared/week-volume-delta-v1.json")
        check(file.isFile) { "Week volume delta contract was not found." }
        return JSONObject(file.readText())
    }
}
