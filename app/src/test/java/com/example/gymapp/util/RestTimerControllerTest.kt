package com.example.gymapp.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RestTimerControllerTest {
    @Test
    fun timerResetsOnlyWhenTheBoundAccountActuallyChanges() {
        val tracker = RestTimerAccountSwitchTracker()
        val accountA = "a".repeat(64)
        val accountB = "b".repeat(64)

        assertFalse(tracker.bind(accountA))
        assertFalse(tracker.bind(accountA))
        assertTrue(tracker.bind(accountB))
        assertFalse(tracker.bind(accountB))
        assertTrue(tracker.bind(null))
        assertFalse(tracker.bind(null))
        assertTrue(tracker.bind(accountA))
    }

    @Test
    fun committedRestStaysSuccessfulWhenTheServiceFailsToStart() {
        val controller = controllerWithFailingService()
        assertTrue(controller.ensureActiveWorkoutTimer(ACCOUNT, SESSION_STARTED_AT))

        assertTrue(controller.startActiveWorkoutRest(ACCOUNT, SESSION_STARTED_AT, seconds = 60))
        assertEquals(
            NOW + 60_000L,
            controller.activeWorkoutTimerSnapshot.value?.restEndsAt
        )
        assertEquals(
            75,
            controller.adjustActiveWorkoutRest(ACCOUNT, SESSION_STARTED_AT, deltaSeconds = 15)
        )
    }

    @Test
    fun restWithoutLedgerSessionStillFailsBeforeTouchingTheService() {
        var serviceCalls = 0
        val controller = controllerWithFailingService { serviceCalls += 1 }

        assertFalse(controller.startActiveWorkoutRest(ACCOUNT, SESSION_STARTED_AT, seconds = 60))
        assertEquals(0, serviceCalls)
    }

    private fun controllerWithFailingService(onCall: () -> Unit = {}): RestTimerController {
        val activeLedger = ActiveWorkoutTimerLedger(
            object : ActiveWorkoutTimerPersistence {
                private var stored: ActiveWorkoutTimerSnapshot? = null
                override fun load() = stored
                override fun save(snapshot: ActiveWorkoutTimerSnapshot?): Boolean {
                    stored = snapshot
                    return true
                }
            },
            nowMillis = { NOW }
        )
        val exerciseLedger = ExerciseRestTimerLedger(
            object : ExerciseRestTimerPersistence {
                override fun load() = ExerciseRestTimerSnapshot(null, emptyMap())
                override fun save(snapshot: ExerciseRestTimerSnapshot) = true
            },
            nowMillis = { NOW }
        )
        activeLedger.switchAccount(ACCOUNT)
        return RestTimerController(
            exerciseLedger,
            activeLedger,
            startService = { onCall(); error("service start refused") },
            stopService = { onCall(); error("service stop refused") }
        )
    }

    private companion object {
        const val ACCOUNT = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
        const val NOW = 1_700_000_000_000L
        const val SESSION_STARTED_AT = NOW - 10_000L
    }
}
