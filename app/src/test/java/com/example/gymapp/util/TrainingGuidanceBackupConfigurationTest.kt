package com.example.gymapp.util

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TrainingGuidanceBackupConfigurationTest {
    @Test
    fun `account local guidance sidecar is excluded from every Android backup mode`() {
        val legacy = Files.readString(appFile("src/main/res/xml/backup_rules.xml"))
        val extraction = Files.readString(
            appFile("src/main/res/xml/data_extraction_rules.xml")
        )
        val paths = listOf(
            "gym_training_guidance_v1.xml",
            "gym_training_guidance_v1.xml.bak",
            "gym_local_profile_registry_v1.xml",
            "gym_local_profile_registry_v1.xml.bak",
            "gym_local_profile_deletion_journal_v1.xml",
            "gym_local_profile_deletion_journal_v1.xml.bak",
            "gym_social_workout_invite_requests.xml",
            "gym_social_workout_invite_requests.xml.bak"
        )

        paths.forEach { path ->
            assertEquals(1, legacy.excludeCount(path))
            assertEquals(2, extraction.excludeCount(path))
        }
    }

    @Test
    fun `optional Finder duplicate exercise images are byte-identical and excluded from packaging`() {
        val buildScript = Files.readString(appFile("build.gradle.kts"))
        val assets = appPath("src/main/assets/exercise-media")
        val sourcePaths = Files.list(assets).use { files ->
            files.filter(Files::isRegularFile)
                .filter { it.fileName.toString().endsWith(".jpg") }
                .toList()
        }
        val finderDuplicates = sourcePaths.filter { it.fileName.toString().endsWith(" 2.jpg") }
        val canonicalPaths = sourcePaths - finderDuplicates.toSet()

        assertEquals(106, canonicalPaths.size)
        finderDuplicates.forEach { duplicate ->
            val canonicalName = duplicate.fileName.toString().removeSuffix(" 2.jpg") + ".jpg"
            val canonical = assets.resolve(canonicalName)
            assertTrue("Missing canonical media for $canonicalName", Files.isRegularFile(canonical))
            assertTrue(
                "Finder duplicate differs from $canonicalName",
                Files.readAllBytes(canonical).contentEquals(Files.readAllBytes(duplicate))
            )
        }
        assertEquals(
            1,
            Regex("ignoreAssetsPattern\\s*=\\s*\"[^\"]*\\* 2\\.jpg[^\"]*\"")
                .findAll(buildScript)
                .count()
        )
    }

    private fun String.excludeCount(path: String): Int =
        Regex("<exclude\\s+domain=\\\"sharedpref\\\"\\s+path=\\\"${Regex.escape(path)}\\\"\\s*/>")
            .findAll(this)
            .count()

    private fun appFile(relativePath: String): Path {
        return appPath(relativePath).takeIf(Files::isRegularFile)
            ?: error("Could not locate app/$relativePath")
    }

    private fun appPath(relativePath: String): Path {
        val workingDirectory = Paths.get("").toAbsolutePath().normalize()
        return generateSequence(workingDirectory) { it.parent }
            .flatMap { directory ->
                sequenceOf(
                    directory.resolve(relativePath),
                    directory.resolve("app").resolve(relativePath)
                )
            }
            .distinct()
            .firstOrNull(Files::exists)
            ?: error("Could not locate app/$relativePath")
    }
}
