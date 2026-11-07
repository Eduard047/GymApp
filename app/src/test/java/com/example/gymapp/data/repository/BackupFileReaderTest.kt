package com.example.gymapp.data.repository

import java.io.ByteArrayInputStream
import java.io.InputStream
import java.nio.charset.CharacterCodingException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class BackupFileReaderTest {
    @Test
    fun readsUtf8TextAndStripsByteOrderMark() {
        val text = "{\"name\":\"Жим лёжа €\"}"
        val bytes = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) +
            text.toByteArray(Charsets.UTF_8)

        assertEquals(text, BackupFileReader.readUtf8(ByteArrayInputStream(bytes)))
    }

    @Test
    fun acceptsExactlyTheMaximumAndRejectsOneByteMore() {
        val limit = 40_000
        val atLimit = ByteArray(limit) { 'a'.code.toByte() }
        assertEquals(limit, BackupFileReader.readUtf8(ByteArrayInputStream(atLimit), limit).length)

        try {
            BackupFileReader.readUtf8(ByteArrayInputStream(atLimit + byteArrayOf(1)), limit)
            fail("Expected BackupFileTooLargeException")
        } catch (_: BackupFileTooLargeException) {
        }
    }

    @Test
    fun stopsReadingAnEndlessStreamShortlyAfterTheCap() {
        var produced = 0L
        val endless = object : InputStream() {
            override fun read(): Int {
                produced++
                return 'x'.code
            }

            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                java.util.Arrays.fill(buffer, offset, offset + length, 'x'.code.toByte())
                produced += length
                return length
            }
        }
        val limit = 100_000

        try {
            BackupFileReader.readUtf8(endless, limit)
            fail("Expected BackupFileTooLargeException")
        } catch (_: BackupFileTooLargeException) {
        }

        assertTrue("read ahead too far: $produced", produced <= limit + 16 * 1_024)
    }

    @Test
    fun usesTheSharedBackupLimitByDefault() {
        val tooBig = ByteArray(WorkoutDataLimits.MAX_BACKUP_BYTES + 1) { 'a'.code.toByte() }
        try {
            BackupFileReader.readUtf8(ByteArrayInputStream(tooBig))
            fail("Expected BackupFileTooLargeException")
        } catch (_: BackupFileTooLargeException) {
        }
    }

    @Test
    fun rejectsInvalidUtf8() {
        try {
            BackupFileReader.readUtf8(ByteArrayInputStream(byteArrayOf(0x7B, 0xC3.toByte(), 0x28, 0x7D)))
            fail("Expected CharacterCodingException")
        } catch (_: CharacterCodingException) {
        }
    }
}
