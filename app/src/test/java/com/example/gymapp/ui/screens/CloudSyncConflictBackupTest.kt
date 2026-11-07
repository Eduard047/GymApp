package com.example.gymapp.ui.screens

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudSyncConflictBackupTest {
    @Test
    fun writesJsonAndClosesStream() {
        var closed = false
        val sink = object : ByteArrayOutputStream() {
            override fun close() {
                closed = true
                super.close()
            }
        }
        assertTrue(writeCloudSyncConflictBackup("{\"a\":\"й\"}") { sink })
        assertEquals("{\"a\":\"й\"}", sink.toString(Charsets.UTF_8.name()))
        assertTrue(closed)
    }

    @Test
    fun missingStreamOrIoFailureReturnsFalse() {
        assertFalse(writeCloudSyncConflictBackup("{}") { null })
        assertFalse(writeCloudSyncConflictBackup("{}") { throw IOException("denied") })
        assertFalse(
            writeCloudSyncConflictBackup("{}") {
                object : OutputStream() {
                    override fun write(b: Int) = throw IOException("disk full")
                }
            }
        )
    }

    @Test
    fun suggestedFileNameIsJson() {
        assertTrue(CLOUD_SYNC_CONFLICT_BACKUP_FILE_NAME.endsWith(".json"))
    }
}
