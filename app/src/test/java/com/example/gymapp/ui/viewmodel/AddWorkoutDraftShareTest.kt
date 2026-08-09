package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.IncomingSharedWorkoutUrl
import com.example.gymapp.data.repository.SharedWorkoutLink
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AddWorkoutDraftShareTest {
    @Test
    fun validDraftBuildsTheExistingPortableShareContractInEditorOrder() {
        val url = buildSharedWorkoutDraftUrl(
            drafts = listOf(
                ExerciseInputState(
                    draftId = 1L,
                    exerciseId = 2L,
                    sets = listOf(
                        SetInputState(weight = "80", reps = "8"),
                        SetInputState(weight = "82,5", reps = "6")
                    )
                ),
                ExerciseInputState(draftId = 2L),
                ExerciseInputState(
                    draftId = 3L,
                    exerciseId = 3L,
                    sets = listOf(SetInputState(weight = "", reps = "12"))
                )
            ),
            exercises = listOf(
                ExerciseEntity(id = 3L, name = "Custom Core Move"),
                ExerciseEntity(id = 2L, name = "Bench Press")
            )
        )

        assertTrue(url.startsWith("${SharedWorkoutLink.BASE_URL}#workout="))
        val parsed = SharedWorkoutLink.parseIncomingUrl(
            rawUrl = url,
            customScheme = "com.setforge.gymapp"
        )
        assertTrue(parsed is IncomingSharedWorkoutUrl.Valid)
        val plan = (parsed as IncomingSharedWorkoutUrl.Valid).plan
        assertEquals(listOf("Bench Press", "Custom Core Move"), plan.exercises.map { it.name })
        assertEquals("bench_press", plan.exercises[0].catalogKey)
        assertEquals(listOf(80.0, 82.5), plan.exercises[0].sets.map { it.weight })
        assertEquals(listOf(8, 6), plan.exercises[0].sets.map { it.reps })
        assertEquals(0.0, plan.exercises[1].sets.single().weight, 0.0)
    }

    @Test
    fun invalidOrUnresolvableSelectedDraftFailsClosed() {
        val exercises = listOf(ExerciseEntity(id = 2L, name = "Bench Press"))

        assertThrows(IllegalArgumentException::class.java) {
            buildSharedWorkoutDraftUrl(
                drafts = listOf(
                    ExerciseInputState(
                        draftId = 1L,
                        exerciseId = 2L,
                        sets = listOf(SetInputState(weight = "80", reps = ""))
                    )
                ),
                exercises = exercises
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            buildSharedWorkoutDraftUrl(
                drafts = listOf(
                    ExerciseInputState(
                        draftId = 1L,
                        exerciseId = 99L,
                        sets = listOf(SetInputState(weight = "80", reps = "8"))
                    )
                ),
                exercises = exercises
            )
        }
    }

    @Test
    fun draftShareEnforcesTheSmallerCrossPlatformSetLimitBeforeEncoding() {
        assertThrows(IllegalArgumentException::class.java) {
            buildSharedWorkoutDraftUrl(
                drafts = listOf(
                    ExerciseInputState(
                        draftId = 1L,
                        exerciseId = 2L,
                        sets = List(SharedWorkoutLink.MAX_SETS_PER_EXERCISE + 1) {
                            SetInputState(weight = "1", reps = "1")
                        }
                    )
                ),
                exercises = listOf(ExerciseEntity(id = 2L, name = "Bench Press"))
            )
        }
    }
}
