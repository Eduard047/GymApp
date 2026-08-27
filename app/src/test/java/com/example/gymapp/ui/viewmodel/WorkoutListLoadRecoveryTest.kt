package com.example.gymapp.ui.viewmodel

import com.example.gymapp.auth.AccountSession
import com.example.gymapp.data.entity.ExerciseEntity
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutListLoadRecoveryTest {
    @Test
    fun firstRecommendationSubscriptionFailureRecoversAfterLoadGenerationRetry() = runBlocking {
        val loadGeneration = MutableStateFlow(0L)
        val outcomes = mutableListOf<WorkoutRecommendationContextLoad>()
        var exerciseSubscriptions = 0

        val collection = launch(start = CoroutineStart.UNDISPATCHED) {
            generationScopedRecommendationContext(
                loadGeneration = loadGeneration,
                exercisesSource = {
                    flow {
                        exerciseSubscriptions += 1
                        if (exerciseSubscriptions == 1) {
                            error("synthetic first subscription failure")
                        }
                        emit(listOf(ExerciseEntity(id = 7L, name = "Recovery press")))
                    }
                },
                historySource = { flowOf(emptyList()) },
                loadProfilesSource = { flowOf(emptyMap()) },
                muscleMappingsSource = { flowOf(emptyList()) }
            ).take(2).toList(outcomes)
        }

        withTimeout(2_000) {
            while (outcomes.isEmpty()) yield()
            loadGeneration.value = 1L
            collection.join()
        }

        assertEquals(2, exerciseSubscriptions)
        assertTrue(outcomes[0] is WorkoutRecommendationContextLoad.Failed)
        val recovered = outcomes[1] as WorkoutRecommendationContextLoad.Loaded
        assertEquals(listOf("Recovery press"), recovered.context.exercises.map { it.name })
    }

    @Test
    fun cloudAccountPresentationSurvivesNonDataStatesWithoutBecomingLocal() {
        val cloud = AccountSession.Cloud(
            userId = "user-1",
            email = "athlete@example.test",
            displayName = "Athlete",
            accessToken = "test-token",
            refreshToken = null
        )

        val presentation = exerciseAccountUiModel(cloud, canLogout = true)

        assertEquals("Athlete", presentation.label)
        assertEquals("athlete@example.test", presentation.supporting)
        assertTrue(presentation.isCloudAccount)
        assertTrue(presentation.canLogout)

        val unavailable = exerciseAccountUiModel(session = null, canLogout = true)
        assertFalse(unavailable.isCloudAccount)
        assertFalse(unavailable.canLogout)
    }
}
