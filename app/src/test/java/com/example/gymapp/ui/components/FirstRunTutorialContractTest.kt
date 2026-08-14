package com.example.gymapp.ui.components

import com.example.gymapp.navigation.AppDestination
import com.example.gymapp.navigation.canRequestTutorialReplay
import com.example.gymapp.navigation.tutorialDestinationAfterDismissal
import com.example.gymapp.navigation.tutorialDestinationForStep
import com.example.gymapp.util.FirstRunTutorialCompletion
import org.junit.Assert.assertEquals
import org.junit.Test

class FirstRunTutorialContractTest {
    @Test
    fun versionOneKeepsExactCrossClientStepOrderAndTargets() {
        assertEquals(1, FIRST_RUN_TUTORIAL_VERSION)
        assertEquals(
            listOf("todayFocus", "todayPrimaryAction", "exercises", "progress", "profile"),
            FIRST_RUN_TUTORIAL_STEPS.map { it.id }
        )
        assertEquals(
            listOf(
                TutorialTarget.TodayFocus,
                TutorialTarget.TodayPrimaryAction,
                TutorialTarget.NavigationExercises,
                TutorialTarget.NavigationProgress,
                TutorialTarget.NavigationProfile
            ),
            FIRST_RUN_TUTORIAL_STEPS.map { it.target }
        )
    }

    @Test
    fun eachStepOpensTheScreenContainingItsTargetAndBackRestoresThatTarget() {
        assertEquals(
            listOf(
                AppDestination.Workouts,
                AppDestination.Workouts,
                AppDestination.Exercises,
                AppDestination.Progress,
                AppDestination.Profile
            ),
            FIRST_RUN_TUTORIAL_STEPS.indices.map(::tutorialDestinationForStep)
        )
        assertEquals(AppDestination.Workouts, tutorialDestinationForStep(-1))
        assertEquals(AppDestination.Workouts, tutorialDestinationForStep(99))
    }

    @Test
    fun skipAndDoneDismissWithoutChangingTheCurrentRoute() {
        assertEquals(
            null,
            tutorialDestinationAfterDismissal(FirstRunTutorialCompletion.Skipped)
        )
        assertEquals(
            null,
            tutorialDestinationAfterDismissal(FirstRunTutorialCompletion.Completed)
        )
    }

    @Test
    fun manualReplayNeverQueuesBehindAConflictingFlow() {
        assertEquals(
            true,
            canRequestTutorialReplay(
                authenticationInProgress = false,
                hasPendingExternalTarget = false,
                hasActiveWorkout = false,
                hasLiveReservationOrRoom = false,
                hasBlockingDialog = false,
                accountTransitionInProgress = false
            )
        )
        assertEquals(
            false,
            canRequestTutorialReplay(
                authenticationInProgress = false,
                hasPendingExternalTarget = false,
                hasActiveWorkout = true,
                hasLiveReservationOrRoom = false,
                hasBlockingDialog = false,
                accountTransitionInProgress = false
            )
        )
    }
}
