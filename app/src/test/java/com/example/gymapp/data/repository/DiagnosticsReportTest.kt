package com.example.gymapp.data.repository

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosticsReportTest {
    private val context = DiagnosticsContext(
        version = "1.2.3",
        build = "456",
        operatingSystemVersion = "Android 15 (API 35)",
        localeIdentifier = "uk-UA",
        cloudSyncEnabled = true,
        hasSuccessfulSync = true,
        hasError = false
    )

    private fun keys(value: JSONObject) = value.keys().asSequence().toSet()

    @Test
    fun usesTheSameAllowlistedKeysAsTheIphoneReport() {
        val report = DiagnosticsReportBuilder.build(
            exportedAtMillis = 1_750_000_000_000L,
            context = context,
            exerciseCount = 3,
            workoutCount = 2,
            setCount = 9,
            manualMuscleMappingCount = 4
        )

        assertEquals(
            setOf("schemaVersion", "reportType", "exportedAt", "application", "workoutData", "cloudSync"),
            keys(report)
        )
        assertEquals(1, report.getInt("schemaVersion"))
        assertEquals("diagnostics", report.getString("reportType"))
        val application = report.getJSONObject("application")
        assertEquals(
            setOf("version", "build", "operatingSystemVersion", "localeIdentifier"),
            keys(application)
        )
        assertEquals("1.2.3", application.getString("version"))
        assertEquals("456", application.getString("build"))
        assertEquals("Android 15 (API 35)", application.getString("operatingSystemVersion"))
        assertEquals("uk-UA", application.getString("localeIdentifier"))
        val workoutData = report.getJSONObject("workoutData")
        assertEquals(
            setOf("exerciseCount", "workoutCount", "setCount", "manualMuscleMappingCount"),
            keys(workoutData)
        )
        assertEquals(3, workoutData.getInt("exerciseCount"))
        assertEquals(2, workoutData.getInt("workoutCount"))
        assertEquals(9, workoutData.getInt("setCount"))
        assertEquals(4, workoutData.getInt("manualMuscleMappingCount"))
        val cloudSync = report.getJSONObject("cloudSync")
        assertEquals(setOf("enabled", "hasSuccessfulSync", "hasError"), keys(cloudSync))
        assertTrue(cloudSync.getBoolean("enabled"))
        assertTrue(cloudSync.getBoolean("hasSuccessfulSync"))
        assertFalse(cloudSync.getBoolean("hasError"))
    }

    @Test
    fun containsOnlyTypedValuesAndNoIdentifiersOrWorkoutContent() {
        val text = DiagnosticsReportBuilder.build(
            exportedAtMillis = 1L,
            context = context,
            exerciseCount = 1,
            workoutCount = 1,
            setCount = 1,
            manualMuscleMappingCount = 0
        ).toString(2)

        for (forbidden in listOf(
            "PRIVATE EXERCISE CANARY",
            "PRIVATE NOTE CANARY",
            "diagnostics-account-canary",
            "diagnostics-user-canary",
            "diagnostics-email-canary@example.com",
            "@",
            "email",
            "userId",
            "accountId",
            "owner",
            "exerciseName",
            "note"
        )) {
            assertFalse("leaked $forbidden", text.contains(forbidden))
        }
    }
}
