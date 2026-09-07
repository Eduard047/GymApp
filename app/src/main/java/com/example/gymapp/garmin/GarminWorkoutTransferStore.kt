package com.example.gymapp.garmin

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/** Use only a private file beneath Context.noBackupFilesDir. */
internal class GarminWorkoutTransferStore(private val file: File) {
    @Synchronized
    fun accept(frame: Map<Any?, Any?>, binding: GarminBinding, nowMillis: Long): GarminTransferStep? =
        runCatching {
            val previous = if (file.exists()) readBounded() else null
            val step = GarminWorkoutTransfer.accept(previous, frame, binding, nowMillis) ?: return null
            val parent = checkNotNull(file.parentFile)
            check(parent.isDirectory || parent.mkdirs())
            val temporary = File(parent, file.name + ".new")
            try {
                FileOutputStream(temporary).use { output ->
                    output.write(step.state.toByteArray(Charsets.UTF_8))
                    output.fd.sync()
                }
                // Both files are in the same private directory. A failed rename
                // leaves the previously acknowledged state untouched.
                check(temporary.renameTo(file))
                check(readBounded() == step.state)
                step
            } finally {
                temporary.delete()
            }
        }.getOrNull()

    @Synchronized
    fun clear(): Boolean = !file.exists() || file.delete()

    @Synchronized
    fun clearAccount(accountBinding: String): Boolean = runCatching {
        if (!file.exists()) return true
        val owner = GarminWorkoutTransfer.stagedAccount(readBounded()) ?: return false
        owner != accountBinding || file.delete()
    }.getOrDefault(false)

    private fun readBounded(): String = file.inputStream().use { input ->
        val bytes = ByteArrayOutputStream()
        val buffer = ByteArray(4096)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            check(bytes.size() + count <= 65536)
            bytes.write(buffer, 0, count)
        }
        Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes.toByteArray())).toString()
    }
}
