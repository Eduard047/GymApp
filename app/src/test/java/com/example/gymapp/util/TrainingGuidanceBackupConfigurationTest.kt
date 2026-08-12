package com.example.gymapp.util

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import org.junit.Assert.assertEquals
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
            "gym_local_profile_deletion_journal_v1.xml.bak"
        )

        paths.forEach { path ->
            assertEquals(1, legacy.excludeCount(path))
            assertEquals(2, extraction.excludeCount(path))
        }
    }

    @Test
    fun `Finder duplicate exercise images are excluded from Android packaging only`() {
        val buildScript = Files.readString(appFile("build.gradle.kts"))
        val assets = appPath("src/main/assets/exercise-media")
        val sourceNames = Files.list(assets).use { files ->
            files.filter(Files::isRegularFile)
                .map { it.fileName.toString() }
                .filter { it.endsWith(".jpg") }
                .toList()
        }

        assertEquals(122, sourceNames.size)
        assertEquals(16, sourceNames.count { it.endsWith(" 2.jpg") })
        assertEquals(106, sourceNames.count { !it.endsWith(" 2.jpg") })
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
