package com.example.gymapp.ui.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import androidx.collection.LruCache
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.catalog.normalizeExerciseIdentityName
import com.example.gymapp.data.entity.ExerciseEntity
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import kotlin.math.min
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

/** What the media sheet offers for a custom photo; null means there is no custom photo. */
internal enum class CustomPhotoRemoval { RestoreBuiltIn, Remove }

internal fun customPhotoRemoval(hasCustomPhoto: Boolean, hasBundledFrames: Boolean): CustomPhotoRemoval? =
    when {
        !hasCustomPhoto -> null
        hasBundledFrames -> CustomPhotoRemoval.RestoreBuiltIn
        else -> CustomPhotoRemoval.Remove
    }

/**
 * Stable identity of an exercise across a cloud replace, which re-inserts every exercise with a
 * new auto-generated id. Same rule as the repository's exercise matching: the built-in catalog
 * key when the name resolves, otherwise the portable normalized name.
 */
internal fun exerciseMediaIdentityKey(name: String): String =
    BuiltInExerciseCatalog.inferKey(name)?.let { "catalog:$it" }
        ?: "name:${normalizeExerciseIdentityName(name)}"

internal data class PhotoMove(val fromId: Long, val toId: Long)

internal data class PhotoRemapPlan(val moves: List<PhotoMove>, val deletions: List<Long>) {
    val isEmpty: Boolean get() = moves.isEmpty() && deletions.isEmpty()
}

/**
 * Pure mapping from "exercises that had a custom photo before the replace" (identity to old id)
 * and "exercises after the replace" (identity to new id) to the file moves and deletions.
 * Photos whose identity no longer exists are deleted. When several old exercises share one
 * identity, only the lowest old id keeps its photo.
 */
internal fun planPhotoRemap(
    photoHolders: List<Pair<String, Long>>,
    newIdsByIdentity: Map<String, Long>
): PhotoRemapPlan {
    val sorted = photoHolders.sortedBy { it.second }
    val claimedTargets = HashSet<Long>()
    val moves = ArrayList<PhotoMove>()
    val deletions = ArrayList<Long>()
    // Photos that already sit on the right id stay put and claim their target first.
    sorted.forEach { (identity, oldId) ->
        if (newIdsByIdentity[identity] == oldId) claimedTargets += oldId
    }
    sorted.forEach { (identity, oldId) ->
        val newId = newIdsByIdentity[identity]
        when {
            newId == null -> deletions += oldId
            newId == oldId -> Unit
            claimedTargets.add(newId) -> moves += PhotoMove(oldId, newId)
            else -> deletions += oldId
        }
    }
    return PhotoRemapPlan(moves = moves, deletions = deletions)
}

private const val PhotoRemapSuffix = ".remap"

/**
 * Applies [plan] inside one owner [directory]. Deletions first, then every moved photo is renamed
 * to a temporary name before any is renamed to its final name, so swaps and chains of id changes
 * can never overwrite a photo that has not moved yet.
 */
internal fun applyPhotoRemap(directory: File, plan: PhotoRemapPlan) {
    plan.deletions.forEach { id -> ExerciseMediaStore.deleteCustomFile(File(directory, "$id.jpg")) }
    val staged = plan.moves.mapNotNull { move ->
        val source = File(directory, "${move.fromId}.jpg")
        val temporary = File(directory, "${move.fromId}.jpg$PhotoRemapSuffix")
        if (source.isFile && source.renameTo(temporary)) move to temporary else null
    }
    staged.forEach { (move, temporary) ->
        val target = File(directory, "${move.toId}.jpg")
        if (!temporary.renameTo(target)) temporary.delete()
    }
}

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

    private val mutableMediaRevision = MutableStateFlow(0)

    /**
     * Bumped after custom photos were moved to new exercise ids (cloud replace). Photo loaders
     * include it in their keys so they reload instead of showing a pre-remap miss forever.
     */
    val mediaRevision: StateFlow<Int> = mutableMediaRevision.asStateFlow()

    internal fun notifyMediaRemapped() {
        mutableMediaRevision.value += 1
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
        val sampled = requireNotNull(
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, decodeOptions)
        ) {
            "invalid_image"
        }
        // BitmapFactory ignores EXIF orientation and the JPEG re-encode below drops the tag,
        // so portrait camera photos would be saved sideways. Bake the rotation into the pixels.
        val decoded = applyExifOrientation(sampled, readExifOrientation(bytes))
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

    /**
     * Runs a cloud replace that deletes and re-inserts every exercise with new ids, and keeps each
     * custom photo attached to the same exercise (by identity). If [replace] throws, no photo is
     * touched. A media failure never fails the replace.
     */
    suspend fun <T> preservePhotosAcrossReplace(
        context: Context,
        ownerKey: String,
        loadExercises: suspend () -> List<ExerciseEntity>,
        replace: suspend () -> T
    ): T {
        val holders = try {
            loadExercises().mapNotNull { exercise ->
                exerciseMediaIdentityKey(exercise.name)
                    .takeIf { customFile(context, ownerKey, exercise.id).isFile }
                    ?.let { it to exercise.id }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            emptyList()
        }
        val result = replace()
        if (holders.isNotEmpty()) {
            // The replace is committed: finish the remap even when the caller is cancelled
            // (sign-out, account switch), or photos would stay attached to dead ids.
            withContext(NonCancellable) {
                try {
                    val newIds = LinkedHashMap<String, Long>()
                    loadExercises().sortedBy { it.id }.forEach { exercise ->
                        newIds.putIfAbsent(exerciseMediaIdentityKey(exercise.name), exercise.id)
                    }
                    val plan = planPhotoRemap(holders, newIds)
                    if (!plan.isEmpty) {
                        withContext(Dispatchers.IO) {
                            applyPhotoRemap(
                                directory = customFile(context, ownerKey, 0L).parentFile
                                    ?: return@withContext,
                                plan = plan
                            )
                        }
                        notifyMediaRemapped()
                    }
                } catch (_: Throwable) {
                    // Photos are a best-effort extra; the already-applied replace must still succeed.
                }
            }
        }
        return result
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

    /** Rotation (clockwise degrees) followed by an optional horizontal mirror. */
    internal data class OrientationTransform(
        val rotationDegrees: Int,
        val mirrorHorizontally: Boolean
    ) {
        val isIdentity: Boolean get() = rotationDegrees == 0 && !mirrorHorizontally
        val swapsAxes: Boolean get() = rotationDegrees == 90 || rotationDegrees == 270
    }

    /** Maps an EXIF orientation value (1..8) to the transform that makes the pixels upright. */
    internal fun orientationTransform(exifOrientation: Int): OrientationTransform =
        when (exifOrientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> OrientationTransform(0, true)
            ExifInterface.ORIENTATION_ROTATE_180 -> OrientationTransform(180, false)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> OrientationTransform(180, true)
            ExifInterface.ORIENTATION_TRANSPOSE -> OrientationTransform(90, true)
            ExifInterface.ORIENTATION_ROTATE_90 -> OrientationTransform(90, false)
            ExifInterface.ORIENTATION_TRANSVERSE -> OrientationTransform(270, true)
            ExifInterface.ORIENTATION_ROTATE_270 -> OrientationTransform(270, false)
            else -> OrientationTransform(0, false)
        }

    internal fun orientedSize(width: Int, height: Int, exifOrientation: Int): Pair<Int, Int> =
        if (orientationTransform(exifOrientation).swapsAxes) height to width else width to height

    private fun readExifOrientation(bytes: ByteArray): Int =
        runCatching {
            ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

    private fun applyExifOrientation(source: Bitmap, exifOrientation: Int): Bitmap {
        val transform = orientationTransform(exifOrientation)
        if (transform.isIdentity) return source
        val matrix = Matrix().apply {
            setRotate(transform.rotationDegrees.toFloat())
            if (transform.mirrorHorizontally) postScale(-1f, 1f)
        }
        val oriented = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
        if (oriented !== source) source.recycle()
        return oriented
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
