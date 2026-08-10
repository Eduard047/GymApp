package com.example.gymapp.push

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.work.BackoffPolicy
import androidx.work.NetworkType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PushWorkRequestTest {
    @Test
    fun reconciliationWorkIsNetworkBoundBackedOffAndContainsNoPrivateData() {
        val request = pushReconciliationWorkRequest()

        assertFalse(PUSH_WORK_CONFIGURATION.containsPrivateInputData)
        assertEquals(NetworkType.CONNECTED, PUSH_WORK_CONFIGURATION.requiredNetworkType)
        assertEquals(BackoffPolicy.EXPONENTIAL, PUSH_WORK_CONFIGURATION.backoffPolicy)
        assertTrue(PUSH_RECONCILIATION_WORK_TAG in request.tags)
    }
}
