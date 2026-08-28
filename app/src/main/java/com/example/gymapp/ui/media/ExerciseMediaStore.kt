package com.example.gymapp.ui.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.collection.LruCache
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
    private const val BundledBitmapCacheBytes = 8 * 1_024 * 1_024
    private val allowedTypes = setOf("image/jpeg", "image/png", "image/webp")
    // Bundled exercise frames are public, immutable application assets. Keeping only these
    // bitmaps in a small process cache avoids retaining account-owned custom media after logout.
    private val bundledBitmapCache = object : LruCache<String, Bitmap>(BundledBitmapCacheBytes) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    fun bundledFramePaths(exerciseName: String): List<String> {
        val key = bundledCatalogKey(exerciseName) ?: return emptyList()
        return listOf("exercise-media/${key}_0.jpg", "exercise-media/${key}_1.jpg")
    }

    internal fun bundledCatalogKey(exerciseName: String): String? {
        BuiltInExerciseCatalog.inferKey(exerciseName)?.let { return it }
        val normalized = exerciseName.trim().lowercase()
        if (normalized.isEmpty() || normalized.length > 256) return null
        return BuiltInExerciseCatalog.definitions.firstOrNull { definition ->
            BuiltInExerciseCatalog.displayName(definition.nameEn, "ru")
                .trim()
                .lowercase() == normalized
        }?.key
    }

    fun customFile(context: Context, ownerKey: String, exerciseId: Long): File =
        File(File(context.filesDir, "exercise-media/${ownerFingerprint(ownerKey)}"), "$exerciseId.jpg")

    internal fun hasPotentialMedia(
        context: Context,
        ownerKey: String,
        exerciseId: Long,
        exerciseName: String
    ): Boolean = customFile(context, ownerKey, exerciseId).isFile || bundledCatalogKey(exerciseName) != null

    fun loadCustom(
        context: Context,
        ownerKey: String,
        exerciseId: Long,
        requestedWidth: Int,
        requestedHeight: Int
    ): Bitmap? =
        customFile(context, ownerKey, exerciseId)
            .takeIf(File::isFile)
            ?.let { file ->
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.absolutePath, bounds)
                val options = sampledOptions(bounds, requestedWidth, requestedHeight)
                BitmapFactory.decodeFile(file.absolutePath, options)
            }

    fun loadBundledFrame(
        context: Context,
        path: String,
        requestedWidth: Int,
        requestedHeight: Int
    ): Bitmap? {
        val cacheKey = bundledFrameCacheKey(path, requestedWidth, requestedHeight)
        bundledBitmapCache.get(cacheKey)?.let { cached ->
            if (!cached.isRecycled) return cached
            bundledBitmapCache.remove(cacheKey)
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.assets.open(path).use { BitmapFactory.decodeStream(it, null, bounds) }
        val options = sampledOptions(bounds, requestedWidth, requestedHeight)
        val decoded = context.assets.open(path).use {
            BitmapFactory.decodeStream(it, null, options)
        } ?: return null
        bundledBitmapCache.put(cacheKey, decoded)
        return decoded
    }

    internal fun bundledFrameCacheKey(
        path: String,
        requestedWidth: Int,
        requestedHeight: Int
    ): String = "$path:${requestedWidth.coerceAtLeast(1)}x${requestedHeight.coerceAtLeast(1)}"

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
        val decodeOptions = sampledOptions(bounds, MaxSavedDimension, MaxSavedDimension)
        val decoded = requireNotNull(
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, decodeOptions)
        ) {
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

    fun deleteCustom(context: Context, ownerKey: String, exerciseId: Long): Boolean =
        deleteCustomFile(customFile(context, ownerKey, exerciseId))

    internal fun deleteCustomFile(file: File): Boolean {
        if (!file.exists()) return true
        if (!file.isFile) return false
        return file.delete() && !file.exists()
    }

    fun clearOwner(context: Context, ownerKey: String): Boolean =
        clearOwnerDirectory(
            File(context.filesDir, "exercise-media/${ownerFingerprint(ownerKey)}")
        )

    internal fun clearOwnerDirectory(directory: File): Boolean {
        if (!directory.exists()) return true
        if (!directory.isDirectory || !directory.name.matches(Regex("^[a-f0-9]{64}$"))) {
            return false
        }
        val canonicalDirectory = runCatching { directory.canonicalFile }.getOrNull()
            ?: return false
        val children = directory.listFiles() ?: return false
        var cleared = true
        children.forEach { child ->
            val hasExpectedParent = runCatching {
                child.parentFile?.canonicalFile == canonicalDirectory
            }.getOrDefault(false)
            if (!hasExpectedParent || child.isDirectory || !child.delete()) cleared = false
        }
        if (directory.listFiles()?.isNotEmpty() != false) return false
        return directory.delete() && cleared
    }

    internal fun calculateInSampleSize(
        sourceWidth: Int,
        sourceHeight: Int,
        requestedWidth: Int,
        requestedHeight: Int
    ): Int {
        if (
            sourceWidth <= 0 ||
                sourceHeight <= 0 ||
                requestedWidth <= 0 ||
                requestedHeight <= 0
        ) {
            return 1
        }

        var sampleSize = 1
        while (
            sourceWidth / (sampleSize * 2) >= requestedWidth &&
                sourceHeight / (sampleSize * 2) >= requestedHeight
        ) {
            sampleSize *= 2
        }
        return sampleSize
    }

    private fun sampledOptions(
        bounds: BitmapFactory.Options,
        requestedWidth: Int,
        requestedHeight: Int
    ) = BitmapFactory.Options().apply {
        inSampleSize = calculateInSampleSize(
            sourceWidth = bounds.outWidth,
            sourceHeight = bounds.outHeight,
            requestedWidth = requestedWidth,
            requestedHeight = requestedHeight
        )
    }

    private fun ownerFingerprint(ownerKey: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("gymapp-exercise-media-v1:$ownerKey".toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }
}
