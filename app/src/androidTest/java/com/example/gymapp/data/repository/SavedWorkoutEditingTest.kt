package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SavedWorkoutEditingTest {
    private fun withRepository(block: suspend (GymRepository, GymDatabase) -> Unit) = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "saved-workout-editing-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        try {
            block(GymRepository(database), database)
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    private suspend fun GymRepository.threeExerciseWorkout(date: Long): Long {
        val ids = listOf("Saved edit A", "Saved edit B", "Saved edit C").map { addExercise(it) }
        return createWorkoutSession(
            date = date,
            note = "original",
            workoutExercises = ids.map { id ->
                WorkoutExerciseDraft(
                    exerciseId = id,
                    sets = listOf(WorkoutSetDraft(50.0, 8), WorkoutSetDraft(55.0, 6))
                )
            }
        )
    }

    @Test
    fun removingAnExerciseDeletesItsSetsAndRenumbersTheRest() = withRepository { repository, database ->
        val sessionId = repository.threeExerciseWorkout(1_788_685_200_000)
        val before = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
            .workoutExercises.sortedBy { it.workoutExercise.orderIndex }
        val removed = before[0]

        assertTrue(repository.removeExerciseFromSession(sessionId, removed.workoutExercise.id))

        val after = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
            .workoutExercises.sortedBy { it.workoutExercise.orderIndex }
        assertEquals(
            before.drop(1).map { it.workoutExercise.id },
            after.map { it.workoutExercise.id }
        )
        assertEquals(listOf(0, 1), after.map { it.workoutExercise.orderIndex })
        removed.sets.forEach { assertNull(database.setDao().getById(it.id)) }
        after.forEach { assertEquals(2, it.sets.size) }
    }

    @Test
    fun removingTheMiddleExerciseKeepsOrderContiguous() = withRepository { repository, database ->
        val sessionId = repository.threeExerciseWorkout(1_788_685_200_000)
        val before = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
            .workoutExercises.sortedBy { it.workoutExercise.orderIndex }

        assertTrue(repository.removeExerciseFromSession(sessionId, before[1].workoutExercise.id))

        val after = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
            .workoutExercises.sortedBy { it.workoutExercise.orderIndex }
        assertEquals(
            listOf(before[0].workoutExercise.id, before[2].workoutExercise.id),
            after.map { it.workoutExercise.id }
        )
        assertEquals(listOf(0, 1), after.map { it.workoutExercise.orderIndex })
    }

    @Test
    fun theLastExerciseAndForeignBlocksAreNeverRemoved() = withRepository { repository, database ->
        val exerciseId = repository.addExercise("Saved edit single")
        val sessionId = repository.createWorkoutSession(
            date = 1_788_685_200_000,
            note = null,
            workoutExercises = listOf(
                WorkoutExerciseDraft(exerciseId, listOf(WorkoutSetDraft(40.0, 10)))
            )
        )
        val only = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
            .workoutExercises.single()

        assertFalse(repository.removeExerciseFromSession(sessionId, only.workoutExercise.id))
        assertFalse(repository.removeExerciseFromSession(sessionId + 999, only.workoutExercise.id))
        assertFalse(repository.removeExerciseFromSession(sessionId, only.workoutExercise.id + 999))

        val still = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
        assertEquals(1, still.workoutExercises.single().sets.size)
    }

    @Test
    fun updatingDetailsChangesDateAndNoteOnly() = withRepository { repository, database ->
        val sessionId = repository.threeExerciseWorkout(1_788_685_200_000)
        val exercisesBefore = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
            .workoutExercises.map { it.workoutExercise to it.sets }

        repository.updateWorkoutSessionDetails(sessionId, 1_788_000_000_000, "  Deload week \n")

        val after = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
        assertEquals(1_788_000_000_000, after.session.date)
        assertEquals("Deload week", after.session.note)
        assertEquals(exercisesBefore, after.workoutExercises.map { it.workoutExercise to it.sets })

        repository.updateWorkoutSessionDetails(sessionId, after.session.date, "   ")
        assertNull(checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId)).session.note)
    }

    @Test
    fun invalidDetailsAreRejectedWithoutChangingTheWorkout() = withRepository { repository, database ->
        val sessionId = repository.threeExerciseWorkout(1_788_685_200_000)

        runCatching {
            repository.updateWorkoutSessionDetails(
                sessionId,
                WorkoutDataLimits.MAX_TIMESTAMP_MILLIS + 1,
                "x"
            )
        }.also { assertTrue(it.isFailure) }
        runCatching {
            repository.updateWorkoutSessionDetails(
                sessionId,
                1_788_685_200_000,
                "n".repeat(WorkoutDataLimits.MAX_NOTE_LENGTH + 1)
            )
        }.also { assertTrue(it.isFailure) }

        val session = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId)).session
        assertEquals(1_788_685_200_000, session.date)
        assertEquals("original", session.note)
    }
}
