package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BackupActivityOnlyMergeImportTest {
    private val startedAt = 1_750_000_000_000L

    private fun item() = ActivityOnlyWorkoutItem(
        workoutStartedAt = startedAt,
        durationSeconds = 1_800,
        gymCalories = 250.0,
        note = "Health Connect · Strength training · Duration 30:00"
    )

    @Test
    fun mergeImportSkipsActivityOnlySessionAtAnExistingStartWithAnotherNote() = runBlocking {
        withDatabase { database, repository ->
            repository.importHealthActivity(item(), "health_connect:a")

            val imported = repository.importBackupJson(
                backup(
                    activitySession("Health Connect · Силове тренування · Тривалість 30:00"),
                    activitySession("My edited note")
                )
            )

            assertEquals(0, imported)
            val sessions = database.workoutDao().getSessions().first()
            assertEquals(1, sessions.size)
            assertEquals(item().note, sessions.single().session.note)
            // Threw "Activity-only workout mirrors have duplicate timestamps." before the fix.
            repository.observeActivityOnlyWorkoutFingerprint().first()
        }
    }

    @Test
    fun mergeImportSkipsActivityOnlySessionAtAnExistingStrengthStart() = runBlocking {
        withDatabase { database, repository ->
            val strength = JSONObject()
                .put("date", startedAt)
                .put(
                    "exercises",
                    JSONArray().put(
                        JSONObject()
                            .put("name", "Squat")
                            .put("sets", JSONArray().put(JSONObject().put("weight", 100).put("reps", 5)))
                    )
                )
            assertEquals(1, repository.importBackupJson(backup(strength)))

            assertEquals(0, repository.importBackupJson(backup(activitySession("Watch"))))
            assertEquals(1, database.workoutDao().getSessions().first().size)
        }
    }

    private fun activitySession(note: String): JSONObject = JSONObject()
        .put("date", startedAt)
        .put("note", note)
        .put("durationSeconds", 1_800)
        .put("exercises", JSONArray())

    private fun backup(vararg sessions: JSONObject): String = JSONObject()
        .put("schemaVersion", 2)
        .put("exercises", JSONArray())
        .put("sessions", JSONArray(sessions.toList()))
        .toString()

    private suspend fun withDatabase(block: suspend (GymDatabase, GymRepository) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "backup-activity-merge-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        try {
            block(database, GymRepository(database))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }
}
