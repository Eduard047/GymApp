package com.example.gymapp.ui.screens

import com.example.gymapp.data.entity.ExerciseEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExerciseSearchLocalizationTest {
    @Test
    fun russianBuiltInDisplayNameMatchesEnglishAndUkrainianStoredIdentity() {
        assertTrue(exerciseNameMatchesLocalizedQuery("Bench Press", "жим штанги лежа"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Жим штанги лежачи", "жим штанги лежа"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Hammer Curl", "молоточные сгибания"))
    }

    @Test
    fun existingLanguagesAliasesAndCustomNamesRemainSearchable() {
        assertTrue(exerciseNameMatchesLocalizedQuery("Bench Press", "bench"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Bench Press", "жим штанги лежачи"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Тяга верхнього блока до грудей", "фронтальна тяга"))
        assertTrue(exerciseNameMatchesLocalizedQuery("Моё упражнение", "моё"))
        assertFalse(exerciseNameMatchesLocalizedQuery("Моё упражнение", "жим штанги"))
    }

    @Test
    fun sharedPickerFiltersFavoritesBodyAndSpecificMuscle() {
        val bench = ExerciseEntity(id = 1, name = "Bench Press", isFavorite = true)
        val squat = ExerciseEntity(id = 2, name = "Squat")
        val crunch = ExerciseEntity(id = 3, name = "Crunch", isFavorite = true)
        val mappings = mapOf(
            bench.name to setOf("chest", "triceps"),
            squat.name to setOf("quads", "glutes"),
            crunch.name to setOf("abs")
        )

        assertEquals(
            listOf(bench),
            filterAndSortExercises(
                exercises = listOf(bench, squat, crunch),
                exerciseWorkoutCounts = emptyMap(),
                muscleIdsByExerciseName = mappings,
                query = "",
                bodyFilter = ExerciseBodyFilter.Upper,
                muscleFilter = "chest",
                sortMode = ExerciseSortMode.Name,
                favoritesOnly = true,
                languageTag = "en"
            )
        )
    }

    @Test
    fun sharedPickerSortsByWorkoutFrequencyWithStableNameTieBreak() {
        val bench = ExerciseEntity(id = 1, name = "Bench Press")
        val squat = ExerciseEntity(id = 2, name = "Squat")
        val crunch = ExerciseEntity(id = 3, name = "Crunch")
        val exercises = listOf(squat, crunch, bench)

        val mostFrequent = filterAndSortExercises(
            exercises = exercises,
            exerciseWorkoutCounts = mapOf(bench.id to 4, squat.id to 1, crunch.id to 1),
            muscleIdsByExerciseName = emptyMap(),
            query = "",
            bodyFilter = ExerciseBodyFilter.All,
            muscleFilter = null,
            sortMode = ExerciseSortMode.MostFrequent,
            favoritesOnly = false,
            languageTag = "en"
        )
        val leastFrequent = filterAndSortExercises(
            exercises = exercises,
            exerciseWorkoutCounts = mapOf(bench.id to 4, squat.id to 1, crunch.id to 1),
            muscleIdsByExerciseName = emptyMap(),
            query = "",
            bodyFilter = ExerciseBodyFilter.All,
            muscleFilter = null,
            sortMode = ExerciseSortMode.LeastFrequent,
            favoritesOnly = false,
            languageTag = "en"
        )

        assertEquals(listOf(bench, crunch, squat), mostFrequent)
        assertEquals(listOf(crunch, squat, bench), leastFrequent)
    }
}
