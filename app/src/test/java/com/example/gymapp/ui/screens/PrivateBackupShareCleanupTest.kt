package com.example.gymapp.ui.screens

import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PrivateBackupShareCleanupTest {
    @Test
    fun deletionCleanupRemovesOnlyTheCapturedOwnersPrivateShareArtifacts() {
        val root = createTempDirectory("gymapp-private-shares-").toFile()
        try {
            val deletedOwnerKey = "gym_cloud_deleted-user"
            val replacementOwnerKey = "gym_cloud_replacement-user"
            val deletedOwnerDirectory = privateBackupShareOwnerDirectory(root, deletedOwnerKey)
                .apply { assertTrue(mkdirs()) }
            val replacementOwnerDirectory = privateBackupShareOwnerDirectory(
                root,
                replacementOwnerKey
            ).apply { assertTrue(mkdirs()) }
            val backup = deletedOwnerDirectory.resolve("gymapp-backup-test.json").apply {
                writeText("private")
            }
            val report = deletedOwnerDirectory.resolve("gymapp-report-test.pdf").apply {
                writeText("private")
            }
            val replacementBackup = replacementOwnerDirectory
                .resolve("gymapp-backup-replacement.json")
                .apply { writeText("other account") }
            val legacyUnboundBackup = root.resolve("gymapp-backup-legacy.json").apply {
                writeText("unknown owner")
            }
            val unrelated = root.resolve("keep.txt").apply { writeText("keep") }

            assertTrue(clearPrivateBackupShareArtifacts(root, deletedOwnerKey))
            assertFalse(backup.exists())
            assertFalse(report.exists())
            assertFalse(deletedOwnerDirectory.exists())
            assertTrue(replacementBackup.isFile)
            assertTrue(legacyUnboundBackup.isFile)
            assertTrue(unrelated.isFile)
            assertTrue(clearPrivateBackupShareArtifacts(root, deletedOwnerKey))
            assertTrue(replacementBackup.isFile)
            assertTrue(privateBackupShareOwnerDirectory(root, deletedOwnerKey).name.matches(
                Regex("^[a-f0-9]{64}$")
            ))
        } finally {
            root.deleteRecursively()
        }
    }
}
