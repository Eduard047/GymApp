package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/pr-history-v1.json, the same cases the iOS suite runs. */
class PersonalRecordHistoryGoldenTest {
    @Test
    fun sharedGoldenCasesMatchIos() {
        val root = contract()
        val cases = root.getJSONArray("cases")
        assertTrue(cases.length() >= 10)
        val limit = root.getInt("limit")
        assertEquals(MAX_PERSONAL_RECORD_HISTORY, limit)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val actual = personalRecordHistory(history(case.getJSONArray("sessions")), limit)
                .map { "${it.sessionId}/${it.setOrderIndex}/${it.weight}/${it.reps}/${kindName(it.kind)}" }
            val expected = case.getJSONArray("expected").objects().map {
                "${it.getInt("session")}/${it.getInt("set")}/${it.getDouble("weight")}/${it.getInt("reps")}/${it.getString("kind")}"
            }
            assertEquals(id, expected, actual)
        }
    }

    @Test
    fun eventsCarryTheSessionDate() {
        val events = personalRecordHistory(
            history(
                JSONArray(
                    """[{"id":1,"date":1000,"sets":[{"weight":100,"reps":5}]},
                        {"id":2,"date":5000,"sets":[{"weight":105,"reps":5}]}]"""
                )
            )
        )
        assertEquals(listOf(5000L), events.map { it.sessionDate })
    }

    @Test
    fun listIsCappedAtTheLimitKeepingTheNewest() {
        // 60 sessions, each heavier than the last: 59 records.
        val entries = (1..60).map { session ->
            ExerciseHistoryEntry(
                setId = session * 10L,
                sessionId = session.toLong(),
                sessionDate = session * 1_000L,
                exerciseId = 1L,
                exerciseName = "Bench",
                weight = 50.0 + session,
                reps = 5,
                setOrderIndex = 0
            )
        }
        val events = personalRecordHistory(entries)
        assertEquals(MAX_PERSONAL_RECORD_HISTORY, events.size)
        assertEquals(60L, events.first().sessionId)
        assertEquals(11L, events.last().sessionId)
        assertEquals(emptyList<PersonalRecordEvent>(), personalRecordHistory(emptyList()))
    }

    private fun kindName(kind: PersonalRecordKind): String = when (kind) {
        PersonalRecordKind.WEIGHT -> "weight"
        PersonalRecordKind.ESTIMATED_ONE_REP_MAX -> "e1rm"
    }

    private fun history(sessions: JSONArray): List<ExerciseHistoryEntry> =
        sessions.objects().flatMap { session ->
            val sessionId = session.getLong("id")
            session.getJSONArray("sets").objects().mapIndexed { index, set ->
                ExerciseHistoryEntry(
                    setId = sessionId * 1_000 + index,
                    sessionId = sessionId,
                    sessionDate = session.getLong("date"),
                    exerciseId = 1L,
                    exerciseName = "Exercise",
                    weight = set.getDouble("weight"),
                    reps = set.getInt("reps"),
                    setOrderIndex = index
                )
            }
        }

    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }

    private fun contract(): JSONObject {
        val direct = File("shared/pr-history-v1.json")
        val file = if (direct.isFile) direct else File("../shared/pr-history-v1.json")
        check(file.isFile) { "PR history contract was not found." }
        return JSONObject(file.readText())
    }
}
