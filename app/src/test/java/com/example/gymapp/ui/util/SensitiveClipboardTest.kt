package com.example.gymapp.ui.util

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SensitiveClipboardTest {
    private val value = "{\"schemaVersion\":2,\"workouts\":[{\"id\":1}]}"
    private val marker = "GymApp private backup:test-marker"
    private val digest = SensitiveClipboard.digest(value)

    @Test
    fun `unchanged app-owned backup remains eligible for timed clearing`() {
        assertTrue(
            SensitiveClipboard.matchesBackupClip(
                expectedMarker = marker,
                expectedLength = value.length,
                expectedDigest = digest,
                currentMarker = marker,
                currentItemCount = 1,
                currentValue = value
            )
        )
    }

    @Test
    fun `clipboard copied by the user after the backup is never cleared`() {
        assertFalse(
            SensitiveClipboard.matchesBackupClip(
                expectedMarker = marker,
                expectedLength = value.length,
                expectedDigest = digest,
                currentMarker = "another-app",
                currentItemCount = 1,
                currentValue = value
            )
        )
        assertFalse(
            SensitiveClipboard.matchesBackupClip(
                expectedMarker = marker,
                expectedLength = value.length,
                expectedDigest = digest,
                currentMarker = marker,
                currentItemCount = 1,
                currentValue = value.replace("1", "2")
            )
        )
    }

    @Test
    fun `multi-item clipboard is never cleared`() {
        assertFalse(
            SensitiveClipboard.matchesBackupClip(
                expectedMarker = marker,
                expectedLength = value.length,
                expectedDigest = digest,
                currentMarker = marker,
                currentItemCount = 2,
                currentValue = value
            )
        )
    }

    @Test
    fun `clipboard backup is conservatively byte bounded`() {
        assertTrue(SensitiveClipboard.canCopyBackup("private backup"))
        assertTrue(
            SensitiveClipboard.canCopyBackup(
                "a".repeat(SensitiveClipboard.MAX_CLIPBOARD_BACKUP_BYTES)
            )
        )
        assertFalse(
            SensitiveClipboard.canCopyBackup(
                "a".repeat(SensitiveClipboard.MAX_CLIPBOARD_BACKUP_BYTES + 1)
            )
        )
        assertFalse(
            SensitiveClipboard.canCopyBackup(
                "€".repeat(SensitiveClipboard.MAX_CLIPBOARD_BACKUP_BYTES / 3 + 1)
            )
        )
    }
}
