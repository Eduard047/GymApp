package com.example.gymapp.navigation

import com.example.gymapp.auth.AccountSession
import com.example.gymapp.sync.CloudSyncPhase
import com.example.gymapp.ui.viewmodel.runLogoutAfterBoundedCloudFlush
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LogoutCloudFlushTest {
    private val session = AccountSession.Cloud(
        userId = "00000000-0000-4000-8000-000000000001",
        email = "user@example.test",
        displayName = "User",
        accessToken = "token",
        refreshToken = "refresh",
        sessionGeneration = "generation-1"
    )

    private fun decide(
        activeSession: AccountSession? = session,
        armed: String? = session.sessionGeneration,
        phase: CloudSyncPhase? = CloudSyncPhase.Pending,
        authLoading: Boolean = false
    ) = shouldFlushCloudAutosaveBeforeLogout(
        session = session,
        activeSession = activeSession,
        autosaveArmedGeneration = armed,
        syncPhase = phase,
        authLoading = authLoading
    )

    @Test
    fun flushesOnlyWhenSignedInWithArmedPendingAutosave() {
        assertTrue(decide())
    }

    @Test
    fun noPendingChangeMeansNoUpload() {
        assertFalse(decide(phase = CloudSyncPhase.Synced))
        assertFalse(decide(phase = CloudSyncPhase.Checking))
        assertFalse(decide(phase = null))
    }

    @Test
    fun conflictOrFailedSaveNeverUploadsOnLogout() {
        // A failed save or conflict clears the armed pull generation and sets the phase.
        assertFalse(decide(phase = CloudSyncPhase.Conflict))
        assertFalse(decide(phase = CloudSyncPhase.Error))
        assertFalse(decide(armed = null))
        assertFalse(decide(armed = "older-generation"))
    }

    @Test
    fun invalidOrChangedSessionNeverUploads() {
        assertFalse(decide(activeSession = null))
        assertFalse(decide(activeSession = session.copy(sessionGeneration = "generation-2")))
        assertFalse(
            decide(activeSession = session.copy(userId = "00000000-0000-4000-8000-000000000002"))
        )
        assertFalse(decide(authLoading = true))
    }

    @Test
    fun pendingChangeIsUploadedBeforeLogout() = runBlocking {
        val order = mutableListOf<String>()
        runLogoutAfterBoundedCloudFlush(
            flush = { if (decide()) order += "upload" },
            timeoutMillis = 5_000,
            logout = { order += "logout" }
        )
        assertEquals(listOf("upload", "logout"), order)
    }

    @Test
    fun noPendingChangeSkipsUploadButLogsOut() = runBlocking {
        val uploads = AtomicInteger()
        val logouts = AtomicInteger()
        runLogoutAfterBoundedCloudFlush(
            flush = { if (decide(phase = CloudSyncPhase.Synced)) uploads.incrementAndGet() },
            timeoutMillis = 5_000,
            logout = { logouts.incrementAndGet() }
        )
        assertEquals(0, uploads.get())
        assertEquals(1, logouts.get())
    }

    @Test
    fun timeoutStillLogsOut() = runBlocking {
        val logouts = AtomicInteger()
        val started = System.nanoTime()
        runLogoutAfterBoundedCloudFlush(
            flush = { delay(60_000) },
            timeoutMillis = 50,
            logout = { logouts.incrementAndGet() }
        )
        assertEquals(1, logouts.get())
        assertTrue((System.nanoTime() - started) / 1_000_000 < 10_000)
    }

    @Test
    fun failedFlushStillLogsOut() = runBlocking {
        val logouts = AtomicInteger()
        runLogoutAfterBoundedCloudFlush(
            flush = { error("network down") },
            timeoutMillis = 5_000,
            logout = { logouts.incrementAndGet() }
        )
        assertEquals(1, logouts.get())
    }

    @Test
    fun noFlushLogsOutImmediately() = runBlocking {
        val logouts = AtomicInteger()
        runLogoutAfterBoundedCloudFlush(
            flush = null,
            timeoutMillis = 5_000,
            logout = { logouts.incrementAndGet() }
        )
        assertEquals(1, logouts.get())
    }

    @Test
    fun cancelledScopeStillLogsOut() = runBlocking {
        val logouts = AtomicInteger()
        val flushStarted = CompletableDeferred<Unit>()
        val job = launch(Dispatchers.Default, start = CoroutineStart.ATOMIC) {
            runLogoutAfterBoundedCloudFlush(
                flush = {
                    flushStarted.complete(Unit)
                    awaitCancellation()
                },
                timeoutMillis = 60_000,
                logout = {
                    delay(1) // logout is suspending (dispatcher hop) and must survive cancel
                    logouts.incrementAndGet()
                }
            )
        }
        flushStarted.await()
        job.cancel(CancellationException("view model cleared"))
        job.join()
        assertEquals(1, logouts.get())
    }
}
