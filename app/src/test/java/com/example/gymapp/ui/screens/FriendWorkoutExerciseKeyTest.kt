package com.example.gymapp.ui.screens

import com.example.gymapp.auth.SocialFriendWorkoutExercise
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class FriendWorkoutExerciseKeyTest {
    private fun exercise(name: String, catalogKey: String?) =
        SocialFriendWorkoutExercise(catalogKey = catalogKey, name = name, sets = emptyList())

    @Test
    fun duplicateExercisesGetDistinctKeys() {
        val bench = exercise("Bench", "bench_press")
        val custom = exercise("My lift", null)
        val keys = listOf(bench, bench, custom, custom)
            .mapIndexed { index, item -> friendWorkoutExerciseKey(index, item) }
        assertEquals(keys.size, keys.toSet().size)
    }

    @Test
    fun sameIndexDifferentExerciseDiffers() {
        assertNotEquals(
            friendWorkoutExerciseKey(0, exercise("A", null)),
            friendWorkoutExerciseKey(0, exercise("B", null))
        )
    }
}
