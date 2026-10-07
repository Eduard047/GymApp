package com.example.gymapp.ui.screens

import com.example.gymapp.data.entity.ExerciseEntity
import org.junit.Assert.assertTrue
import org.junit.Test

class UprightRowSlangSearchTest {
    private val names = listOf(
        "Upright Row",
        "upright row",
        "Тяга штанги до підборіддя",
        "Тяга штанги к подбородку",
        "Тяга штанги к подбородку".uppercase(),
        "Протяжка",
        "Протяжка со штангой",
        "Тяга штанги к подбородку",
        "  Upright   Row ",
        "Тяга штанги до підборіддя"
    )
    private val queries = listOf("протяжка", "Протяжка", "протяжку", "протяжки", "ПРОТЯЖКА", "протяжкою")

    @Test
    fun slangQueryFindsEveryRecognizableUprightRowName() {
        val failures = mutableListOf<String>()
        names.forEach { name ->
            queries.forEach { query ->
                val found = filterAndSortExercises(
                    exercises = listOf(ExerciseEntity(id = 1, name = name)),
                    exerciseWorkoutCounts = emptyMap(),
                    muscleIdsByExerciseName = emptyMap(),
                    query = query,
                    bodyFilter = ExerciseBodyFilter.All,
                    muscleFilter = null,
                    sortMode = ExerciseSortMode.Name,
                    favoritesOnly = false,
                    languageTag = "ru"
                ).isNotEmpty()
                if (!found) failures += "'$name' <- '$query'"
            }
        }
        assertTrue("Not found: $failures", failures.isEmpty())
    }

    @Test
    fun searchRecognitionDoesNotChangeIdentityResolution() {
        val ru = com.example.gymapp.data.catalog.BuiltInExerciseCatalog
        org.junit.Assert.assertEquals("upright_row", ru.definitionForSearchName("Тяга штанги к подбородку")?.key)
        org.junit.Assert.assertNull(ru.definitionForName("Тяга штанги к подбородку"))
        org.junit.Assert.assertNull(ru.definitionForSearchName("Моё упражнение"))
    }
}
