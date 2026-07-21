package com.example.gymapp

import com.example.gymapp.data.repository.muscleContributionsForExercise
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MuscleMappingTest {
    @Test
    fun hipAbductionMapsToGlutesWithoutShoulders() {
        listOf("Hip Abduction", "Розведення ніг", "Разведение ног в тренажере").forEach { exerciseName ->
            val muscleIds = muscleContributionsForExercise(exerciseName).map { it.muscleId }.toSet()

            assertTrue("$exerciseName should map to glutes", muscleIds.contains("glutes"))
            assertFalse("$exerciseName should not map to shoulders", muscleIds.contains("shoulders"))
        }
    }

    @Test
    fun legCurlMapsToHamstringsWithoutArmBiceps() {
        val muscleIds = muscleContributionsForExercise("Leg Curl").map { it.muscleId }.toSet()

        assertTrue(muscleIds.contains("hamstrings"))
        assertTrue(muscleIds.contains("calves"))
        assertFalse(muscleIds.contains("biceps"))
        assertFalse(muscleIds.contains("forearms"))
    }

    @Test
    fun localLegCurlNameMapsToHamstrings() {
        val muscleIds = muscleContributionsForExercise(
            "\u0437\u0433\u0438\u0431\u0430\u043d\u043d\u044f \u043d\u0456\u0433"
        ).map { it.muscleId }.toSet()

        assertTrue(muscleIds.contains("hamstrings"))
        assertTrue(muscleIds.contains("calves"))
        assertFalse(muscleIds.contains("biceps"))
    }

    @Test
    fun russianLegCurlVariantsMapToHamstrings() {
        listOf(
            "\u0441\u0433\u0438\u0431\u0430\u043d\u0438\u0435 \u043d\u043e\u0433",
            "\u0441\u0433\u0438\u0431\u0430\u043d\u0438\u044f \u043d\u043e\u0433",
            "\u0441\u0433\u0438\u0431\u0430\u043d\u0438\u0435 \u043d\u043e\u0433 \u0432 \u0442\u0440\u0435\u043d\u0430\u0436\u0451\u0440\u0435",
            "\u0441\u0433\u0438\u0431\u0430\u043d\u0438\u0435 \u043d\u043e\u0433 \u043b\u0435\u0436\u0430",
            "\u0441\u0433\u0438\u0431\u0430\u043d\u0438\u0435 \u043d\u043e\u0433 \u0441\u0438\u0434\u044f"
        ).forEach { exerciseName ->
            val muscleIds = muscleContributionsForExercise(exerciseName).map { it.muscleId }.toSet()

            assertTrue("$exerciseName should map to hamstrings", muscleIds.contains("hamstrings"))
            assertFalse("$exerciseName should not map to arm biceps", muscleIds.contains("biceps"))
        }
    }
}
