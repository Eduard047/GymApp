package com.example.gymapp.auth

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.repository.SharedWorkoutExercise
import com.example.gymapp.data.repository.SharedWorkoutPlan
import com.example.gymapp.data.repository.SharedWorkoutSet
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SocialWorkoutInviteRequestStoreTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var store: SocialWorkoutInviteRequestStore

    @Before
    fun setUp() {
        context.deleteSharedPreferences(SOCIAL_WORKOUT_REQUEST_PREFERENCES)
        store = SocialWorkoutInviteRequestStore(context)
    }

    @After
    fun tearDown() {
        context.deleteSharedPreferences(SOCIAL_WORKOUT_REQUEST_PREFERENCES)
    }

    @Test
    fun restartRetryReusesRequestIdAndAccountDeletionIsOwnerScoped() {
        val first = session("42345678-1234-4123-8123-123456789abc")
        val other = session("72345678-1234-4123-8123-123456789abc")
        val fingerprint = socialWorkoutInviteRequestFingerprint(
            "p_${"a".repeat(32)}",
            plan()
        )
        val firstId = requireNotNull(store.retainOrCreate(first, fingerprint))
        val afterRestartId = requireNotNull(
            SocialWorkoutInviteRequestStore(context).retainOrCreate(first, fingerprint)
        )
        val otherId = requireNotNull(store.retainOrCreate(other, fingerprint))

        assertEquals(firstId, afterRestartId)
        assertNotEquals(firstId, otherId)
        assertTrue(store.clearCloudAccountLocalState(first.userId.uppercase()))
        assertNull(
            context.getSharedPreferences(
                SOCIAL_WORKOUT_REQUEST_PREFERENCES,
                android.content.Context.MODE_PRIVATE
            ).all.keys.singleOrNull { it.contains(first.userId) }
        )
        assertEquals(otherId, store.retainOrCreate(other, fingerprint))
    }

    private fun session(userId: String) = AccountSession.Cloud(
        userId = userId,
        email = "synthetic@example.invalid",
        displayName = "Synthetic",
        accessToken = "synthetic-token",
        refreshToken = null,
        sessionGeneration = "52345678-1234-4123-8123-123456789abc"
    )

    private fun plan() = SharedWorkoutPlan(
        listOf(
            SharedWorkoutExercise(
                catalogKey = "bench_press",
                name = "Bench Press",
                sets = listOf(SharedWorkoutSet(100.0, 5))
            )
        )
    )
}
