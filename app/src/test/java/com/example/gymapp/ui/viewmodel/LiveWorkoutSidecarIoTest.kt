package com.example.gymapp.ui.viewmodel

import java.util.concurrent.Executors
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.CoroutineStart
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveWorkoutSidecarIoTest {
    @Test
    fun runExecutesOnInjectedDispatcherNotCaller() {
        val executor = Executors.newSingleThreadExecutor { Thread(it, "sidecar-io-test") }
        try {
            val io = LiveWorkoutSidecarIo(executor.asCoroutineDispatcher())
            val callerThread = Thread.currentThread().name
            val workerThread = runBlocking { io.run { Thread.currentThread().name } }
            assertTrue(workerThread, workerThread.startsWith("sidecar-io-test"))
            assertNotEquals(callerThread, workerThread)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun runDeliversResultEvenWhenCallerIsCancelledMidFlight() {
        val executor = Executors.newSingleThreadExecutor { Thread(it, "sidecar-io-test") }
        try {
            val io = LiveWorkoutSidecarIo(executor.asCoroutineDispatcher())
            var completed = false
            runBlocking {
                val job = launch(start = CoroutineStart.UNDISPATCHED) {
                    io.run {
                        Thread.sleep(100)
                        completed = true
                    }
                }
                job.cancel()
                job.join()
            }
            assertTrue("write must finish even if the caller was cancelled", completed)
        } finally {
            executor.shutdownNow()
        }
    }
}
