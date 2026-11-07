package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Test

class SharedWorkoutShareTextTest {
    @Test
    fun putsMessageThenLinkOnSeparateLines() {
        assertEquals(
            "Open this editable workout plan in GymApp.\nhttps://example.test/#workout=abc",
            sharedWorkoutShareText(
                "Open this editable workout plan in GymApp.",
                "https://example.test/#workout=abc"
            )
        )
    }
}
