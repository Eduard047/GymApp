package com.example.gymapp.ui.screens

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
}
