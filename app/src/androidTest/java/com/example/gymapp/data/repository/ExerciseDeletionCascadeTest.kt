package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Deleting an exercise mirrors the iPhone: its blocks leave every workout, workouts left empty
 * are deleted, and the exercise's manual muscle mapping is pruned.
 */
@RunWith(AndroidJUnit4::class)
class ExerciseDeletionCascadeTest {
    @Test
    fun cascadeDropsEmptiedWorkoutsKeepsOthersAndPrunesMapping() = runBlocking {
        withDatabase("exercise-delete-cascade") { database, repository ->
            val target = repository.addExercise("Cascade target")
            val other = repository.addExercise("Cascade other")
            val emptiedSession = repository.createWorkoutSession(
                date = 1_750_000_000_000L,
                note = null,
                workoutExercises = listOf(
                    WorkoutExerciseDraft(target, listOf(WorkoutSetDraft(50.0, 8)))
                )
            )
            val sharedSession = repository.createWorkoutSession(
                date = 1_750_000_100_000L,
                note = null,
                workoutExercises = listOf(
                    WorkoutExerciseDraft(target, listOf(WorkoutSetDraft(50.0, 8))),
                    WorkoutExerciseDraft(other, listOf(WorkoutSetDraft(30.0, 12)))
                )
            )
            val untouchedSession = repository.createWorkoutSession(
                date = 1_750_000_200_000L,
                note = null,
                workoutExercises = listOf(
                    WorkoutExerciseDraft(other, listOf(WorkoutSetDraft(30.0, 12)))
                )
            )
            repository.saveExerciseMuscleMapping("Cascade target", listOf("chest"))
            repository.saveExerciseMuscleMapping("Cascade other", listOf("back"))

            val snapshot = checkNotNull(repository.getExerciseDeletionSnapshot(target))
            assertEquals(2, snapshot.workoutCount)
            assertEquals(listOf(emptiedSession), snapshot.emptiedWorkoutSessionIds)
            assertEquals(1, snapshot.emptiedWorkoutCount)

            assertTrue(repository.deleteExerciseIfUnchanged(snapshot))

            assertNull(database.exerciseDao().getById(target))
            assertNull(database.workoutDao().getSessionDetailsSnapshot(emptiedSession))
            val shared = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sharedSession))
            assertEquals(listOf(other), shared.workoutExercises.map { it.exercise.id })
            assertNotNull(database.workoutDao().getSessionDetailsSnapshot(untouchedSession))
            assertTrue(database.muscleMappingDao().getForExercise("cascade target").isEmpty())
            assertEquals(1, database.muscleMappingDao().getForExercise("cascade other").size)
        }
    }

    @Test
    fun unusedExerciseDeletionKeepsAnActivityOnlyWorkout() = runBlocking {
        withDatabase("exercise-delete-activity-only") { database, repository ->
            val exercise = repository.addExercise("Unused exercise")
            val activity = activityItem(startedAt = 1_750_000_000_000L)
            repository.applyGarminCreateWorkout(
                ownerBinding = "a".repeat(64),
                deviceBinding = "123456789",
                pairingGeneration = "b".repeat(64),
                requestId = "exercise-delete-activity-request",
                payloadDigest = "c".repeat(64),
                date = activity.workoutStartedAt,
                note = activity.note,
                sets = emptyList(),
                durationSeconds = activity.durationSeconds,
                isFreeWorkout = true,
                activityOnlyWorkout = activity
            )

            val snapshot = checkNotNull(repository.getExerciseDeletionSnapshot(exercise))
            assertEquals(0, snapshot.workoutCount)
            assertEquals(0, snapshot.emptiedWorkoutCount)
            assertTrue(repository.deleteExerciseIfUnchanged(snapshot))

            assertEquals(
                listOf(activity.workoutStartedAt),
                database.workoutDao().getSessions().first().map { it.session.date }
            )
            assertEquals(1, database.activityOnlyWorkoutDao().getAll().size)
        }
    }

    @Test
    fun droppedWorkoutRestoresAWatchActivityRecordedAtTheSameStart() = runBlocking {
        withDatabase("exercise-delete-restores-activity") { database, repository ->
            val startedAt = 1_750_000_000_000L
            val exercise = repository.addExercise("Shadowing exercise")
            repository.createWorkoutSession(
                date = startedAt,
                note = "Core",
                workoutExercises = listOf(
                    WorkoutExerciseDraft(exercise, listOf(WorkoutSetDraft(80.0, 8)))
                )
            )
            repository.reconcileActivityOnlyWorkoutSidecar(listOf(activityItem(startedAt)))

            val snapshot = checkNotNull(repository.getExerciseDeletionSnapshot(exercise))
            assertEquals(1, snapshot.emptiedWorkoutCount)
            assertTrue(repository.deleteExerciseIfUnchanged(snapshot))

            val sessions = database.workoutDao().getSessionDetailsAtExactDate(startedAt)
            assertEquals(1, sessions.size)
            assertTrue(sessions.single().workoutExercises.isEmpty())
            assertEquals(1, database.activityOnlyWorkoutDao().getAll().size)
        }
    }

    @Test
    fun confirmationGoesStaleWhenAnotherBlockJoinsAnEmptiedWorkout() = runBlocking {
        withDatabase("exercise-delete-stale-emptied") { database, repository ->
            val target = repository.addExercise("Stale target")
            val other = repository.addExercise("Stale other")
            val sessionId = repository.createWorkoutSession(
                date = 1_750_000_000_000L,
                note = null,
                workoutExercises = listOf(
                    WorkoutExerciseDraft(target, listOf(WorkoutSetDraft(50.0, 8)))
                )
            )
            val stale = checkNotNull(repository.getExerciseDeletionSnapshot(target))
            assertEquals(listOf(sessionId), stale.emptiedWorkoutSessionIds)

            repository.addExerciseToSession(sessionId, other, 30.0, 12)

            assertFalse(repository.deleteExerciseIfUnchanged(stale))
            assertNotNull(database.exerciseDao().getById(target))

            val fresh = checkNotNull(repository.getExerciseDeletionSnapshot(target))
            assertEquals(0, fresh.emptiedWorkoutCount)
            assertTrue(repository.deleteExerciseIfUnchanged(fresh))
            val kept = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
            assertEquals(listOf(other), kept.workoutExercises.map { it.exercise.id })
        }
    }

    private fun activityItem(startedAt: Long) = ActivityOnlyWorkoutItem(
        workoutStartedAt = startedAt,
        durationSeconds = 1_234,
        gymCalories = 10.0,
        garminCalories = null,
        averageHeartRate = null,
        maximumHeartRate = null,
        endingHeartRateZone = null,
        note = "Garmin · Free workout"
    )

    private suspend fun withDatabase(
        prefix: String,
        block: suspend (GymDatabase, GymRepository) -> Unit
    ) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "$prefix-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        try {
            block(database, GymRepository(database))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }
}
