package com.example.gymapp.sync

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CloudSyncStatusStoreTest {
    @Test
    fun lastSuccessIsAccountScopedAndRejectsImplausibleFutureTimestamps() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = CloudSyncStatusStore(context)
        val firstUser = "00000000-0000-4000-8000-000000000101"
        val secondUser = "00000000-0000-4000-8000-000000000202"
        store.clear(firstUser)
        store.clear(secondUser)
        try {
            assertTrue(store.writeLastSuccess(firstUser, timestamp = NOW))
            assertEquals(NOW, store.readLastSuccess(firstUser, nowMillis = NOW + 1_000L))
            assertNull(store.readLastSuccess(secondUser, nowMillis = NOW + 1_000L))

            assertTrue(store.writeLastSuccess(secondUser, timestamp = NOW + TWO_DAYS_MILLIS))
            assertNull(store.readLastSuccess(secondUser, nowMillis = NOW))
        } finally {
            store.clear(firstUser)
            store.clear(secondUser)
        }
    }

    private companion object {
        const val NOW = 1_750_000_000_000L
        const val TWO_DAYS_MILLIS = 2L * 24L * 60L * 60L * 1_000L
    }
}
