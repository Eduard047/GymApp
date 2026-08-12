package com.example.gymapp.util

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.data.repository.WorkoutFeedback
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TrainingGuidanceManagerAccountIsolationTest {
    @Test
    fun switchAndDeletionKeepDismissalAndFeedbackBoundToOneAccount() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        clear(context)
        val manager = TrainingGuidanceManager(context)
        val accountA = AccountSession.Local("Alice")
        val accountB = AccountSession.Local("Bob")
        val startedAt = 1_786_473_600_000L

        try {
            manager.switchAccount(accountA)
            val bindingA = requireNotNull(manager.activeBinding)
            assertTrue(manager.dismissActivation())
            assertTrue(
                manager.saveFeedback(
                    sessionId = 11,
                    sessionStartedAtMillis = startedAt,
                    feedback = WorkoutFeedback.Normal,
                    ownedSessions = mapOf(11L to startedAt),
                    expectedAccountBinding = bindingA
                )
            )
            manager.switchAccount(accountB)
            assertFalse(manager.activationDismissed.value)
            assertTrue(manager.feedback.value.isEmpty())
            manager.switchAccount(null)
            assertFalse(manager.activationDismissed.value)
            assertTrue(manager.feedback.value.isEmpty())
            manager.switchAccount(accountA)
            assertTrue(manager.activationDismissed.value)
            assertEquals(WorkoutFeedback.Normal, manager.feedback.value[11]?.feedback)
            assertTrue(manager.clearAccount(accountA))
            assertFalse(manager.activationDismissed.value)
            assertTrue(manager.feedback.value.isEmpty())
        } finally {
            clear(context)
        }
    }

    @Test
    fun feedbackIsIdempotentAndRequiresExactOwnedSessionTimestamp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        clear(context)
        val manager = TrainingGuidanceManager(context)
        val account = AccountSession.Local("Owner")
        val startedAt = 1_786_473_600_000L
        val owned = mapOf(4L to startedAt, 5L to startedAt + 86_400_000L)

        try {
            manager.switchAccount(account)
            val binding = requireNotNull(manager.activeBinding)
            assertTrue(manager.saveFeedback(4, startedAt, WorkoutFeedback.Easy, owned, binding))
            val first = manager.feedback.value
            assertTrue(manager.saveFeedback(4, startedAt, WorkoutFeedback.Easy, owned, binding))
            assertEquals(first, manager.feedback.value)
            assertFalse(manager.saveFeedback(4, startedAt + 1, WorkoutFeedback.Hard, owned, binding))
            assertEquals(WorkoutFeedback.Easy, manager.feedback.value[4]?.feedback)
            assertTrue(manager.saveFeedback(4, startedAt, WorkoutFeedback.Hard, owned, binding))
            assertEquals(WorkoutFeedback.Hard, manager.feedback.value[4]?.feedback)
            assertTrue(manager.pruneFeedback(mapOf(5L to startedAt + 86_400_000L), binding))
            assertTrue(manager.feedback.value.isEmpty())
        } finally {
            clear(context)
        }
    }

    @Test
    fun feedbackRetainsNewest128SessionsAndPrunesTimestampReplacements() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        clear(context)
        val manager = TrainingGuidanceManager(context)
        val account = AccountSession.Local("Bounded")
        val base = 1_780_000_000_000L
        val owned = (1L..140L).associateWith { id -> base + id * 60_000L }

        try {
            manager.switchAccount(account)
            val binding = requireNotNull(manager.activeBinding)
            owned.forEach { (id, startedAt) ->
                assertTrue(
                    manager.saveFeedback(id, startedAt, WorkoutFeedback.Normal, owned, binding)
                )
            }
            assertEquals(128, manager.feedback.value.size)
            assertEquals((13L..140L).toSet(), manager.feedback.value.keys)

            val replacedTimestamp = owned.toMutableMap().apply {
                this[140L] = getValue(140L) + 1L
            }
            assertTrue(manager.pruneFeedback(replacedTimestamp, binding))
            assertFalse(manager.feedback.value.containsKey(140L))
        } finally {
            clear(context)
        }
    }

    @Test
    fun staleAccountBindingCannotWriteOrPruneTheNewAccountsFeedback() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        clear(context)
        val manager = TrainingGuidanceManager(context)
        val startedAt = 1_786_473_600_000L

        try {
            manager.switchAccount(AccountSession.Local("Old owner"))
            val oldBinding = requireNotNull(manager.activeBinding)
            manager.switchAccount(AccountSession.Local("New owner"))
            val newBinding = requireNotNull(manager.activeBinding)
            val owned = mapOf(9L to startedAt)

            assertFalse(
                manager.saveFeedback(
                    9L,
                    startedAt,
                    WorkoutFeedback.Hard,
                    owned,
                    oldBinding
                )
            )
            assertTrue(manager.feedback.value.isEmpty())
            assertTrue(
                manager.saveFeedback(
                    9L,
                    startedAt,
                    WorkoutFeedback.Normal,
                    owned,
                    newBinding
                )
            )
            assertFalse(manager.pruneFeedback(emptyMap(), oldBinding))
            assertEquals(WorkoutFeedback.Normal, manager.feedback.value[9L]?.feedback)
        } finally {
            clear(context)
        }
    }

    @Test
    fun malformedStoredSidecarFailsNeutralWithoutLeakingRawAccountIdentity() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        clear(context)
        val account = AccountSession.Local("Private owner")
        val first = TrainingGuidanceManager(context)
        first.switchAccount(account)
        val binding = requireNotNull(first.activeBinding)
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(
                "$binding:feedback",
                "{\"v\":1,\"f\":[[1,\"unknown\",1786473600000]]}"
            )
            .putString("$binding:activation_dismissed", "wrong-type")
            .commit()

        try {
            val reloaded = TrainingGuidanceManager(context)
            reloaded.switchAccount(account)
            assertTrue(reloaded.feedback.value.isEmpty())
            assertFalse(reloaded.activationDismissed.value)
            assertFalse(
                context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                    .all.keys.any { it.contains("Private owner") }
            )
        } finally {
            clear(context)
        }
    }

    @Test
    fun skippingActivationDoesNotApplyTheUnsubmittedSelectionToTrainingProfile() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        clear(context)
        context.deleteSharedPreferences("gym_training_profiles")
        val account = AccountSession.Local("Skip")
        val profileManager = TrainingProfileManager(context)
        val guidanceManager = TrainingGuidanceManager(context)

        try {
            profileManager.switchAccount(account)
            guidanceManager.switchAccount(account)
            val before = profileManager.profile.value

            assertTrue(guidanceManager.dismissActivation())

            assertEquals(TrainingProfile(), before)
            assertEquals(before, profileManager.profile.value)
            assertTrue(guidanceManager.activationDismissed.value)
        } finally {
            clear(context)
            context.deleteSharedPreferences("gym_training_profiles")
        }
    }

    private fun clear(context: Context) {
        context.deleteSharedPreferences(PREFERENCES)
    }

    private companion object {
        const val PREFERENCES = "gym_training_guidance_v1"
    }
}
