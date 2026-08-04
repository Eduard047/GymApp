package com.example.gymapp.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class CloudSyncBaselineStoreTest {
    @Test
    fun `v3 baseline round trips while legacy unversioned digest is ignored`() {
        val digest = "a".repeat(64)

        assertEquals(digest, decodeCloudSyncBaseline(encodeCloudSyncBaseline(digest)))
        assertNull(decodeCloudSyncBaseline(digest))
        assertNull(decodeCloudSyncBaseline("v2:$digest"))
        assertNull(decodeCloudSyncBaseline("v3:${"a".repeat(63)}"))
    }

    @Test
    fun `baseline encoder accepts only lowercase sha256`() {
        listOf("", "A".repeat(64), "g".repeat(64), "a".repeat(65)).forEach { invalid ->
            assertThrows(IllegalArgumentException::class.java) {
                encodeCloudSyncBaseline(invalid)
            }
        }
    }
}
