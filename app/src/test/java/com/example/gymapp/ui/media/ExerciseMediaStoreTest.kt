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
}
