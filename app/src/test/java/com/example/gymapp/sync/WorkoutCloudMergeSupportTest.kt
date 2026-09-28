package com.example.gymapp.sync

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WorkoutCloudMergeSupportTest {
    private val userId = "00000000-0000-4000-8000-0000000001a1"

    @Test
    fun remoteRevisionTimeKeepsMillisecondsFromPostgresTimestamps() {
        assertEquals(1_754_384_401_123L, remoteStateRevisionMillis("2025-08-05T09:00:01.123456+00:00"))
        assertEquals(1_754_384_401_000L, remoteStateRevisionMillis("2025-08-05T09:00:01Z"))
        assertNull(remoteStateRevisionMillis("not a time"))
    }

    @Test
    fun exerciseIdentityMatchesCatalogKeysAndNormalizedCustomNames() {
        assertEquals(
            workoutMergeExerciseIdentity(WorkoutMergeExercise("Bench Press", "bench_press")),
            workoutMergeExerciseIdentity(WorkoutMergeExercise("Bench Press", null))
        )
        assertEquals(
            workoutMergeExerciseIdentity(WorkoutMergeExercise("Cable  Kickback", null)),
            workoutMergeExerciseIdentity(WorkoutMergeExercise("cable kickback", null))
        )
        assertNotEquals(
            workoutMergeExerciseIdentity(WorkoutMergeExercise("Cable Kickback", null)),
            workoutMergeExerciseIdentity(WorkoutMergeExercise("Band Fly", null))
        )
    }

    @Test
    fun cloudStateCoreUsesPortableKeysAndTrimmedNotes() {
        val core = workoutMergeCoreFromCloudState(canonicalState())

        assertEquals(listOf(WorkoutMergeExercise("Bench Press", "bench_press")), core.exercises)
        assertEquals(
            listOf(
                WorkoutMergeSession(
                    date = 1_750_000_000_000L,
                    note = "Workout",
                    blocks = listOf(
                        WorkoutMergeBlock(
                            name = "Bench Press",
                            catalogKey = "bench_press",
                            sets = listOf(WorkoutMergeSet(weight = 80.0, reps = 8))
                        )
                    )
                )
            ),
            core.sessions
        )
        assertEquals(core, WorkoutCloudSyncState.decodeCore(WorkoutCloudSyncState.encodeCore(core)))
    }

    private fun canonicalState(): JSONObject = JSONObject(
        """
        {
          "schemaVersion": 2,
          "exportedAt": 1750000000000,
          "app": "GymApp",
          "diagnostics": false,
          "owner": {
            "accountId": "$userId",
            "userId": "$userId",
            "remote": true
          },
          "exercises": [{"name": "Bench Press"}],
          "sessions": [{
            "date": 1750000000000,
            "note": "  Workout  ",
            "exercises": [{
              "name": "Bench Press",
              "sets": [{"weight": 80.0, "reps": 8}]
            }]
          }],
          "summary": {
            "exerciseCount": 1,
            "sessionCount": 1,
            "setCount": 1,
            "totalVolume": 640.0
          }
        }
        """.trimIndent()
    )
}
