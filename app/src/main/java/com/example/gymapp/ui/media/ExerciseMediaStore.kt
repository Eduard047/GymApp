package com.example.gymapp.ui.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import kotlin.math.min

object ExerciseMediaStore {
    private const val MaxInputBytes = 8 * 1024 * 1024
    private const val MaxOutputBytes = 1_600_000
    private const val MaxDimension = 8_192
    private const val MaxPixels = 40_000_000L
    private const val MaxSavedDimension = 1_024
    private val allowedTypes = setOf("image/jpeg", "image/png", "image/webp")

    fun bundledFramePaths(exerciseName: String): List<String> {
        val key = BuiltInExerciseCatalog.inferKey(exerciseName) ?: return emptyList()
        return listOf("exercise-media/${key}_0.jpg", "exercise-media/${key}_1.jpg")
    }

    fun customFile(context: Context, ownerKey: String, exerciseId: Long): File =
        File(File(context.filesDir, "exercise-media/${ownerFingerprint(ownerKey)}"), "$exerciseId.jpg")

    fun loadCustom(context: Context, ownerKey: String, exerciseId: Long): Bitmap? =
        customFile(context, ownerKey, exerciseId)
            .takeIf(File::isFile)
            ?.let { BitmapFactory.decodeFile(it.absolutePath) }

    fun saveCustom(context: Context, ownerKey: String, exerciseId: Long, uri: Uri) {
        val mime = context.contentResolver.getType(uri)?.lowercase()
        require(mime in allowedTypes) { "unsupported_type" }
        val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(16 * 1024)
            var total = 0
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                total += read
                require(total <= MaxInputBytes) { "image_too_large" }
                output.write(buffer, 0, read)
            }
            output.toByteArray()
        } ?: error("image_unavailable")

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth in 32..MaxDimension && bounds.outHeight in 32..MaxDimension) {
            "invalid_dimensions"
        }
        require(bounds.outWidth.toLong() * bounds.outHeight.toLong() <= MaxPixels) {
            "invalid_dimensions"
        }
        val decoded = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size)) {
            "invalid_image"
        }
        val scale = min(1f, MaxSavedDimension.toFloat() / maxOf(decoded.width, decoded.height))
        val scaled = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                decoded,
                (decoded.width * scale).toInt().coerceAtLeast(1),
                (decoded.height * scale).toInt().coerceAtLeast(1),
                true
            ).also { decoded.recycle() }
        } else {
            decoded
        }
        val encoded = ByteArrayOutputStream().use {
            check(scaled.compress(Bitmap.CompressFormat.JPEG, 82, it)) { "encode_failed" }
            it.toByteArray()
        }
        scaled.recycle()
        require(encoded.size <= MaxOutputBytes) { "image_too_large" }

        val target = customFile(context, ownerKey, exerciseId)
        target.parentFile?.mkdirs()
        val temporary = File(target.parentFile, "${target.name}.tmp")
        temporary.writeBytes(encoded)
        check(temporary.renameTo(target)) { "save_failed" }
    }

    fun deleteCustom(context: Context, ownerKey: String, exerciseId: Long) {
        customFile(context, ownerKey, exerciseId).delete()
    }

    private fun ownerFingerprint(ownerKey: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("gymapp-exercise-media-v1:$ownerKey".toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }
}
