package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.auth.AccountSession
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LiveWorkoutSidecarStoreTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var store: LiveWorkoutSidecarStore

    @Before
    fun setUp() {
        store = LiveWorkoutSidecarStore(context)
        store.clearAll()
    }

    @After
    fun tearDown() {
        store.clearAll()
    }

    @Test
    fun accountGenerationMismatchCannotReadOrEraseAnotherGeneration() {
        val first = session("42345678-1234-4123-8123-123456789abc")
        val nextGeneration = first.copy(
            sessionGeneration = "62345678-1234-4123-8123-123456789abc"
        )
        val binding = binding(first)
        assertTrue(store.save(first, binding))
        assertEquals(binding, store.load(first))

        assertNull(store.load(nextGeneration))
        assertEquals(binding, store.load(first))
    }

    @Test
    fun anotherAccountCannotClearCurrentBindingThroughScopedClear() {
        val first = session("42345678-1234-4123-8123-123456789abc")
        val other = session("72345678-1234-4123-8123-123456789abc")
        val binding = binding(first)
        assertTrue(store.save(first, binding))
        val preferences = context.getSharedPreferences(
            LIVE_SIDECAR_PREFERENCES,
            android.content.Context.MODE_PRIVATE
        )
        val before = preferences.all.toMap()

        assertFalse(store.clear(other))
        assertEquals(before, preferences.all)
        assertEquals(binding, store.load(first))
        assertEquals(binding, LiveWorkoutSidecarStore(context).load(first))
        assertNull(LiveWorkoutSidecarStore(context).load(other))
    }

    private fun session(userId: String) = AccountSession.Cloud(
        userId = userId,
        email = "synthetic@example.invalid",
        displayName = "Synthetic",
        accessToken = "synthetic-token",
        refreshToken = null,
        sessionGeneration = "52345678-1234-4123-8123-123456789abc"
    )

    private fun binding(session: AccountSession.Cloud) = LiveWorkoutBinding(
        userId = session.userId,
        sessionGeneration = session.sessionGeneration,
        roomId = "lr_0123456789abcdef0123456789abcdef",
        role = "owner",
        peerProfileId = "p_0123456789abcdef0123456789abcdef",
        peerDisplayName = "Partner",
        roomRevision = 3,
        membershipRevision = 1,
        progressRevision = 1,
        workoutStartedAt = 1_786_330_800_000L,
        serverToLocalSetIds = mapOf(
            "s_01_01" to "32345678-1234-4123-8123-123456789abc"
        )
    )
}
