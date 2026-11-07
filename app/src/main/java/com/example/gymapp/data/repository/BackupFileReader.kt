package com.example.gymapp.data.repository

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

class BackupFileTooLargeException : Exception("Backup file exceeds the size limit.")

/**
 * Reads a user-chosen backup file into text without trusting its length. The stream is consumed
 * through a bounded buffer and aborted as soon as it passes [maximumBytes], so an oversized or
 * endless source can never be loaded fully into memory. Blocking: call it off the main thread.
 */
object BackupFileReader {
    private const val BUFFER_BYTES = 16 * 1_024

    /**
     * @throws BackupFileTooLargeException when the stream holds more than [maximumBytes] bytes.
     * @throws java.nio.charset.CharacterCodingException when the bytes are not valid UTF-8.
     */
    fun readUtf8(
        input: InputStream,
        maximumBytes: Int = WorkoutDataLimits.MAX_BACKUP_BYTES
    ): String {
        require(maximumBytes > 0)
        val buffer = ByteArray(BUFFER_BYTES)
        val collected = ByteArrayOutputStream(minOf(maximumBytes, BUFFER_BYTES))
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            total += read
            if (total > maximumBytes) throw BackupFileTooLargeException()
            collected.write(buffer, 0, read)
        }
        val decoded = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(collected.toByteArray()))
            .toString()
        return decoded.removePrefix("\uFEFF")
    }
}
