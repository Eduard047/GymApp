package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BackupCatalogKeyImportTest {
    @Test
    fun exerciseCrudRejectsBuiltInAliasesAsDuplicates() {
        runBlocking {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val databaseName = "catalog-key-duplicates-${UUID.randomUUID()}"
            val database = GymDatabase.getInstance(context, databaseName)

            try {
                val repository = GymRepository(database)
                repository.addExercise("Присідання зі штангою")
                assertThrows(IllegalArgumentException::class.java) {
                    runBlocking { repository.addExercise("Squat") }
                }

                val customID = repository.addExercise("My custom movement")
                val custom = database.exerciseDao().getExercisesSnapshot().single { it.id == customID }
                assertThrows(IllegalArgumentException::class.java) {
                    runBlocking { repository.renameExercise(custom, "Barbell Squat") }
                }
            } finally {
                database.close()
                context.deleteDatabase(databaseName)
            }
        }
    }

    @Test
    fun recognizedRawNamesAreNotRedirectedByHostileOrMalformedCatalogKeys() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "catalog-key-import-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            val benchID = repository.addExercise("Bench Press")
            val squatID = repository.addExercise("Присідання зі штангою")
            val rawBackup =
                """
                {
                  "schemaVersion": 2,
                  "exportedAt": 1750000000000,
                  "app": "GymApp",
                  "diagnostics": false,
                  "exercises": [],
                  "sessions": [
                    {
                      "date": 1750000000000,
                      "exercises": [
                        {
                          "name": "Squat",
                          "catalogKey": "bench_press",
                          "sets": [{"weight": 80.0, "reps": 8}]
                        },
                        {
                          "name": "Barbell Squat",
                          "catalogKey": "not-a-real-catalog-key",
                          "sets": [{"weight": 82.5, "reps": 6}]
                        }
                      ]
                    }
                  ]
                }
                """.trimIndent()

            assertEquals(1, repository.importBackupJson(rawBackup))

            val importedWorkout = repository.getLatestWorkoutTemplate()
            assertNotNull(importedWorkout)
            val importedExercises = importedWorkout!!.workoutExercises
            assertEquals(1, importedExercises.size)
            assertEquals(squatID, importedExercises.single().exercise.id)
            assertEquals(2, importedExercises.single().sets.size)
            assertFalse(importedExercises.any { it.exercise.id == benchID })
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }
}
