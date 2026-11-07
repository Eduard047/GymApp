package com.example.gymapp.ui.media

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.io.path.createTempDirectory

class ExerciseMediaStoreTest {
    @Test
    fun calculateInSampleSizeUsesLargestSafePowerOfTwo() {
        assertEquals(4, ExerciseMediaStore.calculateInSampleSize(4_096, 3_072, 800, 600))
        assertEquals(2, ExerciseMediaStore.calculateInSampleSize(1_024, 768, 320, 240))
    }

    @Test
    fun calculateInSampleSizeKeepsSmallOrInvalidImagesAtFullResolution() {
        assertEquals(1, ExerciseMediaStore.calculateInSampleSize(480, 320, 800, 600))
        assertEquals(1, ExerciseMediaStore.calculateInSampleSize(0, 320, 800, 600))
        assertEquals(1, ExerciseMediaStore.calculateInSampleSize(480, 320, 0, 600))
    }

    @Test
    fun orientationTransformMapsAllEightExifOrientations() {
        val expected = mapOf(
            1 to (0 to false),
            2 to (0 to true),
            3 to (180 to false),
            4 to (180 to true),
            5 to (90 to true),
            6 to (90 to false),
            7 to (270 to true),
            8 to (270 to false)
        )
        expected.forEach { (orientation, rotationAndMirror) ->
            val transform = ExerciseMediaStore.orientationTransform(orientation)
            assertEquals("rotation for $orientation", rotationAndMirror.first, transform.rotationDegrees)
            assertEquals("mirror for $orientation", rotationAndMirror.second, transform.mirrorHorizontally)
        }
    }

    @Test
    fun orientationTransformTreatsUnknownValuesAsUpright() {
        listOf(0, 9, -1, 255).forEach {
            assertTrue(ExerciseMediaStore.orientationTransform(it).isIdentity)
        }
    }

    @Test
    fun orientedSizeSwapsWidthAndHeightOnlyForQuarterTurns() {
        (listOf(5, 6, 7, 8)).forEach {
            assertEquals(3_000 to 4_000, ExerciseMediaStore.orientedSize(4_000, 3_000, it))
        }
        listOf(1, 2, 3, 4, 0).forEach {
            assertEquals(4_000 to 3_000, ExerciseMediaStore.orientedSize(4_000, 3_000, it))
        }
    }

    @Test
    fun bundledMediaUsesStableCatalogIdentityAcrossSupportedLanguages() {
        assertEquals("bench_press", ExerciseMediaStore.bundledCatalogKey("Bench Press"))
        assertEquals("bench_press", ExerciseMediaStore.bundledCatalogKey("Жим штанги лежачи"))
        assertEquals(
            "bench_press",
            ExerciseMediaStore.bundledCatalogKey(
                BuiltInExerciseCatalog.displayName("Bench Press", "ru")
            )
        )
        assertEquals(null, ExerciseMediaStore.bundledCatalogKey("Custom press"))
    }

    @Test
    fun bundledFrameCacheKeyIsStableAndSeparatesDecodeSizes() {
        assertEquals(
            "exercise-media/bench_press_0.jpg:256x192",
            ExerciseMediaStore.bundledFrameCacheKey(
                "exercise-media/bench_press_0.jpg",
                256,
                192
            )
        )
        assertFalse(
            ExerciseMediaStore.bundledFrameCacheKey(
                "exercise-media/bench_press_0.jpg",
                256,
                192
            ) == ExerciseMediaStore.bundledFrameCacheKey(
                "exercise-media/bench_press_0.jpg",
                1_024,
                768
            )
        )
    }

    @Test
    fun accountCleanupDeletesOnlyTheCapturedOwnersMediaDirectory() {
        val root = createTempDirectory("gymapp-media-cleanup-").toFile()
        try {
            val captured = root.resolve("a".repeat(64)).apply { mkdirs() }
            val other = root.resolve("b".repeat(64)).apply { mkdirs() }
            captured.resolve("1.jpg").writeText("captured")
            captured.resolve("2.jpg.tmp").writeText("temporary")
            other.resolve("1.jpg").writeText("other")

            assertTrue(ExerciseMediaStore.clearOwnerDirectory(captured))
            assertFalse(captured.exists())
            assertTrue(other.resolve("1.jpg").isFile)
            assertTrue(ExerciseMediaStore.clearOwnerDirectory(captured))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun customRestoreReportsDurableDeletionAndFailsClosedForNonFile() {
        val root = createTempDirectory("gymapp-media-delete-").toFile()
        try {
            val image = root.resolve("1.jpg").apply { writeText("custom") }
            assertTrue(ExerciseMediaStore.deleteCustomFile(image))
            assertFalse(image.exists())
            assertTrue(ExerciseMediaStore.deleteCustomFile(image))

            val undeletableTarget = root.resolve("2.jpg").apply {
                mkdirs()
                resolve("owned").writeText("keep")
            }
            assertFalse(ExerciseMediaStore.deleteCustomFile(undeletableTarget))
            assertTrue(undeletableTarget.resolve("owned").isFile)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun customPhotoRemovalIsOfferedWheneverACustomPhotoExists() {
        assertEquals(null, customPhotoRemoval(hasCustomPhoto = false, hasBundledFrames = true))
        assertEquals(null, customPhotoRemoval(hasCustomPhoto = false, hasBundledFrames = false))
        assertEquals(
            CustomPhotoRemoval.RestoreBuiltIn,
            customPhotoRemoval(hasCustomPhoto = true, hasBundledFrames = true)
        )
        // A user-created exercise has no bundled frames; its photo must still be removable.
        assertEquals(
            CustomPhotoRemoval.Remove,
            customPhotoRemoval(hasCustomPhoto = true, hasBundledFrames = false)
        )
    }

    @Test
    fun deleteCustomFileRemovesPhotoAndTreatsMissingFileAsDeleted() {
        val directory = createTempDirectory("exercise-media-delete").toFile()
        try {
            val photo = java.io.File(directory, "42.jpg").apply { writeBytes(byteArrayOf(1, 2, 3)) }
            assertTrue(ExerciseMediaStore.deleteCustomFile(photo))
            assertFalse(photo.exists())
            assertTrue(ExerciseMediaStore.deleteCustomFile(photo))
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun planPhotoRemapMovesPhotoToTheNewIdOfTheSameIdentity() {
        val plan = planPhotoRemap(
            photoHolders = listOf("name:my lift" to 7L),
            newIdsByIdentity = mapOf("name:my lift" to 31L, "name:other" to 32L)
        )
        assertEquals(listOf(PhotoMove(7L, 31L)), plan.moves)
        assertTrue(plan.deletions.isEmpty())
    }

    @Test
    fun planPhotoRemapHandlesSwappedIds() {
        val plan = planPhotoRemap(
            photoHolders = listOf("name:a" to 1L, "name:b" to 2L),
            newIdsByIdentity = mapOf("name:a" to 2L, "name:b" to 1L)
        )
        assertEquals(listOf(PhotoMove(1L, 2L), PhotoMove(2L, 1L)), plan.moves)
        assertTrue(plan.deletions.isEmpty())
    }

    @Test
    fun planPhotoRemapDeletesPhotosOfExercisesRemovedRemotely() {
        val plan = planPhotoRemap(
            photoHolders = listOf("name:gone" to 4L, "name:kept" to 5L),
            newIdsByIdentity = mapOf("name:kept" to 5L)
        )
        assertTrue(plan.moves.isEmpty())
        assertEquals(listOf(4L), plan.deletions)
    }

    @Test
    fun planPhotoRemapIgnoresExercisesWithoutPhotoAndUnchangedIds() {
        val plan = planPhotoRemap(
            photoHolders = listOf("name:same" to 9L),
            newIdsByIdentity = mapOf("name:same" to 9L, "name:no photo" to 10L)
        )
        assertTrue(plan.isEmpty)
        assertTrue(planPhotoRemap(emptyList(), mapOf("name:x" to 1L)).isEmpty)
    }

    @Test
    fun planPhotoRemapKeepsOnlyOnePhotoPerIdentity() {
        val plan = planPhotoRemap(
            photoHolders = listOf("catalog:bench_press" to 8L, "catalog:bench_press" to 3L),
            newIdsByIdentity = mapOf("catalog:bench_press" to 20L)
        )
        assertEquals(listOf(PhotoMove(3L, 20L)), plan.moves)
        assertEquals(listOf(8L), plan.deletions)
    }

    @Test
    fun exerciseMediaIdentityKeyUsesCatalogKeyThenNormalizedName() {
        assertEquals(
            exerciseMediaIdentityKey("Bench Press"),
            exerciseMediaIdentityKey("  bench   press ")
        )
        assertEquals("name:my  weird lift".replace("  ", " "), exerciseMediaIdentityKey("My  Weird Lift"))
    }

    @Test
    fun applyPhotoRemapSwapsPhotosWithoutClobberingAndDeletesRemovedOnes() {
        val directory = createTempDirectory("exercise-media-remap").toFile()
        try {
            fun photo(id: Long, content: Byte) =
                java.io.File(directory, "$id.jpg").apply { writeBytes(byteArrayOf(content)) }
            photo(1L, 11)
            photo(2L, 22)
            photo(3L, 33)
            photo(4L, 44)
            val plan = planPhotoRemap(
                photoHolders = listOf("name:a" to 1L, "name:b" to 2L, "name:c" to 3L, "name:d" to 4L),
                // a and b swap, c is removed remotely, d moves onto the freed id 3.
                newIdsByIdentity = mapOf("name:a" to 2L, "name:b" to 1L, "name:d" to 3L)
            )
            applyPhotoRemap(directory, plan)
            assertEquals(11.toByte(), java.io.File(directory, "2.jpg").readBytes().single())
            assertEquals(22.toByte(), java.io.File(directory, "1.jpg").readBytes().single())
            assertEquals(44.toByte(), java.io.File(directory, "3.jpg").readBytes().single())
            assertFalse(java.io.File(directory, "4.jpg").exists())
            assertEquals(
                listOf("1.jpg", "2.jpg", "3.jpg"),
                directory.listFiles().orEmpty().map { it.name }.sorted()
            )
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun mediaRevisionAdvancesWhenPhotosAreRemapped() {
        val before = ExerciseMediaStore.mediaRevision.value
        ExerciseMediaStore.notifyMediaRemapped()
        assertEquals(before + 1, ExerciseMediaStore.mediaRevision.value)
    }
}
