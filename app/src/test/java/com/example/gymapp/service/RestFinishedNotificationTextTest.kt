package com.example.gymapp.service

import com.example.gymapp.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RestFinishedNotificationTextTest {
    @Test
    fun missingOrBlankExerciseKeepsTheGenericBody() {
        assertNull(restFinishedExerciseLabel(null) { it })
        assertNull(restFinishedExerciseLabel("   ") { it })
        assertNull(restFinishedExerciseLabel("Squat") { " " })
        assertEquals(R.string.timer_notification_finished_text, restFinishedBodyResource(null))
    }

    @Test
    fun knownExerciseUsesTheLocalizedNameInTheExerciseBody() {
        val label = restFinishedExerciseLabel(" Bench Press ") { raw ->
            assertEquals("Bench Press", raw)
            "Жим лежачи"
        }
        assertEquals("Жим лежачи", label)
        assertEquals(R.string.timer_notification_finished_body_exercise, restFinishedBodyResource(label))
    }

    @Test
    fun overlongNameIsCapped() {
        assertEquals(80, restFinishedExerciseLabel("x".repeat(500)) { it }?.length)
    }
}
