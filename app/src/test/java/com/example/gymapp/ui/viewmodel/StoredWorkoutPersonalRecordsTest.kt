package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutExerciseWithDetails
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionEntity
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StoredWorkoutPersonalRecordsTest {
    private val sessionId = 10L
    private val sessionDate = 1_000L

    private fun details(vararg sets: Pair<Double, Int>): WorkoutSessionDetails {
        val workoutExercise = WorkoutExerciseEntity(
            id = 100L,
            sessionId = sessionId,
            exerciseId = 1L,
            orderIndex = 0
        )
        return WorkoutSessionDetails(
            session = WorkoutSessionEntity(id = sessionId, date = sessionDate, note = null),
            workoutExercises = listOf(
                WorkoutExerciseWithDetails(
                    workoutExercise = workoutExercise,
                    exercise = ExerciseEntity(id = 1L, name = "Bench Press"),
                    sets = sets.mapIndexed { index, (weight, reps) ->
                        SetEntryEntity(
                            id = 1_000L + index,
                            workoutExerciseId = 100L,
                            weight = weight,
                            reps = reps,
                            orderIndex = index
                        )
                    }
                )
            )
        )
    }

    private fun prior(setId: Long, session: Long, date: Long, weight: Double, reps: Int) =
        ExerciseHistoryEntry(
            setId = setId,
            sessionId = session,
            sessionDate = date,
            exerciseId = 1L,
            exerciseName = "Bench Press",
            weight = weight,
            reps = reps,
            setOrderIndex = 0
        )

    @Test
    fun firstSessionOfAnExerciseHasNoRecords() {
        val detail = details(60.0 to 8, 80.0 to 5)

        assertEquals(emptySet<Long>(), storedWorkoutPersonalRecordSetIds(detail, emptyList()))
        assertFalse(storedWorkoutPersonalRecordFlags(detail, emptyList()).getValue(100L))
    }

    @Test
    fun laterWorkoutsAndTheWorkoutItselfAreNotBaseline() {
        val history = listOf(
            prior(1, session = 11, date = 2_000L, weight = 200.0, reps = 5), // later workout
            prior(2, session = sessionId, date = sessionDate, weight = 90.0, reps = 5) // itself
        )

        assertTrue(storedWorkoutPersonalRecordSetIds(details(90.0 to 5), history).isEmpty())
    }

    @Test
    fun weightRecordMustBeStrictlyHeavierAndRunningBestIsUsed() {
        val history = listOf(prior(1, session = 5, date = 500L, weight = 60.0, reps = 5))
        // 60 x5 ties the best weight and its estimate; 70 x5 beats it; 70 x5 again only matches.
        val detail = details(60.0 to 5, 70.0 to 5, 70.0 to 5)

        assertEquals(setOf(1_001L), storedWorkoutPersonalRecordSetIds(detail, history))
        assertTrue(storedWorkoutPersonalRecordFlags(detail, history).getValue(100L))
    }

    @Test
    fun estimatedOneRepMaxRecordWithoutHeavierWeightCounts() {
        val history = listOf(prior(1, session = 5, date = 500L, weight = 60.0, reps = 5))

        assertEquals(
            setOf(1_000L),
            storedWorkoutPersonalRecordSetIds(details(60.0 to 10), history)
        )
    }

    @Test
    fun zeroKilogramSetsNeverCountAsRecords() {
        val history = listOf(prior(1, session = 5, date = 500L, weight = 0.0, reps = 5))

        assertTrue(storedWorkoutPersonalRecordSetIds(details(0.0 to 30), history).isEmpty())
    }

    /** Runs the "storedCases" of shared/personal-records-v1.json, the same cases the iOS suite runs. */
    @Test
    fun sharedStoredWorkoutCasesMatchIos() {
        val cases = contract().getJSONArray("storedCases")
        assertTrue(cases.length() >= 6)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val exerciseIds = mutableMapOf<String, Long>()
            fun idOf(key: String): Long = exerciseIds.getOrPut(key) { exerciseIds.size + 1L }

            val history = case.getJSONArray("history").objects().mapIndexed { i, item ->
                val (session, date) = when (val whenKey = item.getString("when")) {
                    "earlier" -> 5L to 500L
                    "same-date-lower-id" -> (sessionId - 1) to sessionDate
                    "same-date-higher-id" -> (sessionId + 1) to sessionDate
                    "later" -> 5L to 2_000L
                    "self" -> sessionId to sessionDate
                    else -> error("$id: unknown when $whenKey")
                }
                ExerciseHistoryEntry(
                    setId = i + 1L,
                    sessionId = session,
                    sessionDate = date,
                    exerciseId = idOf(item.getString("exercise")),
                    exerciseName = item.getString("exercise"),
                    weight = item.getDouble("weight"),
                    reps = item.getInt("reps"),
                    setOrderIndex = 0
                )
            }

            var nextSetId = 1_000L
            val blocks = case.getJSONArray("workout").objects().mapIndexed { blockIndex, block ->
                val workoutExerciseId = 100L + blockIndex
                WorkoutExerciseWithDetails(
                    workoutExercise = WorkoutExerciseEntity(
                        id = workoutExerciseId,
                        sessionId = sessionId,
                        exerciseId = idOf(block.getString("exercise")),
                        orderIndex = blockIndex
                    ),
                    exercise = ExerciseEntity(id = idOf(block.getString("exercise")), name = block.getString("exercise")),
                    sets = block.getJSONArray("sets").objects().mapIndexed { setIndex, set ->
                        SetEntryEntity(
                            id = nextSetId++,
                            workoutExerciseId = workoutExerciseId,
                            weight = set.getDouble("weight"),
                            reps = set.getInt("reps"),
                            orderIndex = setIndex
                        )
                    }
                )
            }
            val detail = WorkoutSessionDetails(
                session = WorkoutSessionEntity(id = sessionId, date = sessionDate, note = null),
                workoutExercises = blocks
            )
            val records = storedWorkoutPersonalRecordSetIds(detail, history)

            val expected = case.getJSONObject("expected").getJSONArray("records").objects()
            assertEquals("$id block count", expected.size, blocks.size)
            expected.forEachIndexed { blockIndex, want ->
                val flags = want.getJSONArray("sets")
                assertEquals(
                    "$id block $blockIndex records",
                    List(flags.length()) { flags.getBoolean(it) },
                    blocks[blockIndex].sets.map { it.id in records }
                )
            }
        }
    }

    private fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }

    private fun contract(): JSONObject {
        val direct = File("shared/personal-records-v1.json")
        val file = if (direct.isFile) direct else File("../shared/personal-records-v1.json")
        check(file.isFile) { "Personal records contract was not found." }
        return JSONObject(file.readText())
    }
}
