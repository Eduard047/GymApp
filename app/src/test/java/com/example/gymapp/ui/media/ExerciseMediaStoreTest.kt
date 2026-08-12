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
}
