package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.entity.ExerciseEntity
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SharedWorkoutImportSecurityTest {
    @Test
    fun unsafeUnicodeNamesAreRejectedWithoutMutatingTheCatalog() = runBlocking {
        withDatabase("shared-workout-unsafe-unicode") { database, repository ->
            val unsafeScalars = listOf(
                "\u0080",
                "\u009f",
                "\u200b",
                "\u2060",
                "\ufeff",
                "\u2028",
                "\u2029"
            )

            unsafeScalars.forEach { scalar ->
                val plan = SharedWorkoutPlan(
                    exercises = listOf(
                        SharedWorkoutExercise(
                            catalogKey = null,
                            name = "Visible${scalar}Name",
                            sets = listOf(SharedWorkoutSet(weight = 10.0, reps = 8))
                        )
                    )
                )

                val failure = runCatching {
                    repository.resolveSharedWorkoutExerciseIds(plan)
                }.exceptionOrNull()

                assertTrue(failure is IllegalArgumentException)
                assertEquals(0, database.exerciseDao().getExerciseCount())
            }
        }
    }

    @Test
    fun mismatchedCatalogKeyCannotReplaceAnExistingBuiltInExercise() = runBlocking {
        withDatabase("shared-workout-mismatched-key") { database, repository ->
            val benchPressId = database.exerciseDao().insert(
                ExerciseEntity(name = "Bench Press")
            )
            val attackerControlledName = "Unreviewed Front Raise"
            val plan = SharedWorkoutPlan(
                exercises = listOf(
                    SharedWorkoutExercise(
                        catalogKey = "bench_press",
                        name = attackerControlledName,
                        sets = listOf(SharedWorkoutSet(weight = 12.5, reps = 10))
                    )
                )
            )

            val resolvedId = repository.resolveSharedWorkoutExerciseIds(plan).single()

            assertNotEquals(benchPressId, resolvedId)
            assertEquals(
                attackerControlledName,
                database.exerciseDao().getById(resolvedId)?.name
            )
            assertEquals("Bench Press", database.exerciseDao().getById(benchPressId)?.name)
            assertEquals(2, database.exerciseDao().getExerciseCount())
        }
    }

    @Test
    fun failureAfterCreatingAnExerciseRollsBackTheWholeImport() = runBlocking {
        withDatabase("shared-workout-rollback") { database, repository ->
            database.exerciseDao().insert(ExerciseEntity(name = "Ambiguous Target"))
            database.exerciseDao().insert(ExerciseEntity(name = " ambiguous   target "))
            val namesBefore = database.exerciseDao().getExercisesSnapshot().map { it.name }.toSet()
            val rollbackSentinel = "Fresh shared rollback sentinel"
            val plan = SharedWorkoutPlan(
                exercises = listOf(
                    SharedWorkoutExercise(
                        catalogKey = null,
                        name = rollbackSentinel,
                        sets = listOf(SharedWorkoutSet(weight = 20.0, reps = 8))
                    ),
                    SharedWorkoutExercise(
                        catalogKey = null,
                        name = "AMBIGUOUS TARGET",
                        sets = listOf(SharedWorkoutSet(weight = 0.0, reps = 12))
                    )
                )
            )

            val failure = runCatching {
                repository.resolveSharedWorkoutExerciseIds(plan)
            }.exceptionOrNull()

            assertTrue(failure is IllegalArgumentException)
            val exercisesAfter = database.exerciseDao().getExercisesSnapshot()
            assertEquals(namesBefore, exercisesAfter.map { it.name }.toSet())
            assertTrue(exercisesAfter.none { it.name == rollbackSentinel })
        }
    }

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
