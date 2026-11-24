package com.example.gymapp.data.repository

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Two activity-only sessions (no exercises, duration > 0) at the same start are one workout on
 * both clients: the activity-only sidecar is keyed by its start. A backup may still carry both
 * (for example the same Health import with notes in two languages), so the validator keeps only
 * the first one instead of letting a later import create a second mirror at that start.
 */
class BackupActivityOnlyDuplicateTest {
    private val startedAt = 1_750_000_000_000L

    @Test
    fun validatorKeepsOnlyTheFirstActivityOnlySessionPerStart() {
        val backup = BackupImportValidator.validate(
            backup(
                activitySession(startedAt, "Health Connect · Strength training · Duration 30:00"),
                activitySession(startedAt, "Health Connect · Силове тренування · Тривалість 30:00"),
                activitySession(startedAt + 1L, "Later start")
            )
        )

        assertEquals(listOf(startedAt, startedAt + 1L), backup.sessions.map { it.date })
        assertEquals(
            "Health Connect · Strength training · Duration 30:00",
            backup.sessions.first().note
        )
    }

    @Test
    fun validatorKeepsStrengthSessionsThatShareTheActivityStart() {
        val backup = BackupImportValidator.validate(
            backup(
                activitySession(startedAt, "Watch"),
                """
                {"date":$startedAt,"exercises":[{"name":"Squat","sets":[{"weight":100,"reps":5}]}]}
                """.trimIndent()
            )
        )

        assertEquals(2, backup.sessions.size)
    }

    private fun activitySession(date: Long, note: String): String =
        JSONObject()
            .put("date", date)
            .put("note", note)
            .put("durationSeconds", 1_800)
            .put("exercises", org.json.JSONArray())
            .toString()

    private fun backup(vararg sessions: String): JSONObject = JSONObject(
        """
        {
          "schemaVersion": 2,
          "exercises": [],
          "sessions": [${sessions.joinToString(",")}]
        }
        """.trimIndent()
    )
}
