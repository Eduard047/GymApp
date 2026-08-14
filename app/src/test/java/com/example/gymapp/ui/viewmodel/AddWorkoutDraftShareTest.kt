package com.example.gymapp.ui.viewmodel

import com.example.gymapp.auth.SocialIncomingWorkoutInvite
import com.example.gymapp.auth.SocialWorkoutInviteSummary
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.IncomingSharedWorkoutUrl
import com.example.gymapp.data.repository.SharedWorkoutExercise
import com.example.gymapp.data.repository.SharedWorkoutLink
import com.example.gymapp.data.repository.SharedWorkoutPlan
import com.example.gymapp.data.repository.SharedWorkoutSet
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.navigation.shouldConsumeAcceptedSocialWorkout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AddWorkoutDraftShareTest {
    @Test
    fun lateGarminResultCannotAcknowledgeAnEditedOrClearedDraft() {
        assertTrue(watchPlanSyncResultIsCurrent(capturedGeneration = 7L, currentGeneration = 7L))
        assertFalse(watchPlanSyncResultIsCurrent(capturedGeneration = 7L, currentGeneration = 8L))
        assertFalse(watchPlanSyncResultIsCurrent(capturedGeneration = 8L, currentGeneration = 7L))
    }

    @Test
    fun directInviteDraftUsesExactlyTheExistingPortableWorkoutPlan() {
        val drafts = listOf(
            ExerciseInputState(
                draftId = 1L,
                exerciseId = 2L,
                sets = listOf(SetInputState(weight = "80", reps = "8"))
            )
        )
        val exercises = listOf(ExerciseEntity(id = 2L, name = "Bench Press"))

        val directPlan = buildSharedWorkoutDraftPlan(drafts, exercises)
        val linkPlan = SharedWorkoutLink.parseIncomingUrl(
            rawUrl = buildSharedWorkoutDraftUrl(drafts, exercises),
            customScheme = "com.setforge.gymapp"
        ) as IncomingSharedWorkoutUrl.Valid

        assertEquals(linkPlan.plan, directPlan)
        assertEquals(setOf("bench_press"), directPlan.exercises.mapNotNull { it.catalogKey }.toSet())
    }

    @Test
    fun acceptedInboxRowCanRecoverItsEditableCopyAfterProcessRestartWithoutRespondingAgain() {
        val plan = SharedWorkoutPlan(
            exercises = listOf(
                SharedWorkoutExercise(
                    catalogKey = "bench_press",
                    name = "Bench Press",
                    sets = listOf(SharedWorkoutSet(weight = 80.0, reps = 8))
                )
            )
        )
        val acceptedInvite = SocialIncomingWorkoutInvite(
            inviteId = "wi_${"a".repeat(32)}",
            profileId = "p_${"b".repeat(32)}",
            displayName = "Training Friend",
            status = "accepted",
            inviteRevision = 2,
            createdAt = "2026-08-09T10:00:00Z",
            expiresAt = "2026-08-16T10:00:00Z",
            respondedAt = "2026-08-09T10:01:00Z",
            summary = SocialWorkoutInviteSummary(1, 1, listOf("Bench Press")),
            workout = null
        )

        val recovered = acceptedSocialWorkoutForReuse(acceptedInvite, loadedPlan = plan)

        assertEquals(acceptedInvite.inviteId, recovered?.inviteId)
        assertEquals(plan, recovered?.plan)
        assertNull(
            acceptedSocialWorkoutForReuse(
                acceptedInvite.copy(status = "pending"),
                loadedPlan = plan
            )
        )
        assertNull(acceptedSocialWorkoutForReuse(acceptedInvite, loadedPlan = null))
        assertNull(
            acceptedSocialWorkoutForReuse(
                acceptedInvite.copy(
                    summary = SocialWorkoutInviteSummary(1, 2, listOf("Bench Press"))
                ),
                loadedPlan = plan
            )
        )
    }

    @Test
    fun localImportRejectsBuiltInAliasCollisionBeforeTheAcceptedPayloadIsConsumed() {
        val plan = SharedWorkoutPlan(
            exercises = listOf(
                SharedWorkoutExercise(
                    catalogKey = "bench_press",
                    name = "Bench Press",
                    sets = listOf(SharedWorkoutSet(weight = 80.0, reps = 8))
                ),
                SharedWorkoutExercise(
                    catalogKey = "bench_press_uk",
                    name = "Жим штанги лежачи",
                    sets = listOf(SharedWorkoutSet(weight = 75.0, reps = 10))
                )
            )
        )

        assertThrows(IllegalArgumentException::class.java) {
            normalizeSharedWorkoutPlanForDraftImport(plan)
        }
        assertFalse(shouldConsumeAcceptedSocialWorkout(appliedToDraft = false))
    }

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
                    sets = listOf(SetInputState(weight = "0", reps = "12"))
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
                        sets = listOf(SetInputState(weight = "", reps = "8"))
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
    fun smartCoachNullableLoadIsShownAndSharedAsExplicitZero() {
        assertEquals("0", smartWorkoutWeightInput(null))
        assertEquals("0", smartWorkoutWeightInput(0.0))
        assertThrows(IllegalArgumentException::class.java) {
            smartWorkoutWeightInput(Double.NaN)
        }
        assertThrows(IllegalArgumentException::class.java) {
            smartWorkoutWeightInput(-0.01)
        }
        assertThrows(IllegalArgumentException::class.java) {
            smartWorkoutWeightInput(WorkoutDataLimits.MAX_WEIGHT + 0.01)
        }

        val plan = buildSharedWorkoutDraftPlan(
            drafts = listOf(
                ExerciseInputState(
                    draftId = 1L,
                    exerciseId = 2L,
                    sets = listOf(SetInputState(weight = smartWorkoutWeightInput(null), reps = "12"))
                )
            ),
            exercises = listOf(ExerciseEntity(id = 2L, name = "Pull Up"))
        )
        assertEquals(0.0, plan.exercises.single().sets.single().weight, 0.0)
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
