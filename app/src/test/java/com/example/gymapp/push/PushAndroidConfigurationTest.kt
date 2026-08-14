package com.example.gymapp.push

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

class PushAndroidConfigurationTest {
    @Test
    fun `messaging service is private auto init is off and device identity is not backed up`() {
        val manifest = parseXml(appFile("src/main/AndroidManifest.xml"))
        val services = manifest.getElementsByTagName("service")
        val pushService = (0 until services.length)
            .map { services.item(it) as Element }
            .firstOrNull {
                it.androidAttribute("name") == ".push.GymFirebaseMessagingService"
            }
        assertNotNull(pushService)
        assertEquals("false", pushService?.androidAttribute("exported"))
        assertEquals("false", pushService?.androidAttribute("directBootAware"))
        assertTrue(
            pushService?.getElementsByTagName("action")?.let { actions ->
                (0 until actions.length).any {
                    (actions.item(it) as Element).androidAttribute("name") ==
                        "com.google.firebase.MESSAGING_EVENT"
                }
            } == true
        )

        val metadata = manifest.getElementsByTagName("meta-data")
        val autoInit = (0 until metadata.length)
            .map { metadata.item(it) as Element }
            .firstOrNull {
                it.androidAttribute("name") == "firebase_messaging_auto_init_enabled"
            }
        assertEquals("false", autoInit?.androidAttribute("value"))
        val notificationDelegation = (0 until metadata.length)
            .map { metadata.item(it) as Element }
            .firstOrNull {
                it.androidAttribute("name") ==
                    "firebase_messaging_notification_delegation_enabled"
            }
        assertEquals("false", notificationDelegation?.androidAttribute("value"))
        assertFalse(
            (0 until metadata.length)
                .map { metadata.item(it) as Element }
                .any {
                    it.androidAttribute("name") ==
                        "firebase_messaging_installation_id_enabled"
                }
        )

        val legacyBackup = Files.readString(appFile("src/main/res/xml/backup_rules.xml"))
        val extractionRules = Files.readString(
            appFile("src/main/res/xml/data_extraction_rules.xml")
        )
        listOf(legacyBackup, extractionRules).forEach { rules ->
            assertTrue(rules.contains("domain=\"file\" path=\".\""))
            assertTrue(rules.contains("path=\"gym_push_installation.xml\""))
            assertTrue(rules.contains("path=\"com.google.android.gms.appid.xml\""))
            assertTrue(rules.contains("path=\"com.google.firebase.messaging.xml\""))
        }
    }

    @Test
    fun `Firebase is optional only for debug while production release is reviewed and fail closed`() {
        val gradle = Files.readString(appFile("build.gradle.kts"))
        val playRelease = Files.readString(appFile("scripts/build-play-release-aab.ps1"))
        val phoneRelease = Files.readString(appFile("scripts/build-phone-release-apk.ps1"))
        val releaseGate = Files.readString(
            appFile("scripts/android-release-firebase-gate.ps1")
        )

        assertTrue(gradle.contains("findProperty(\"gymappFirebaseConfigFile\")"))
        assertTrue(gradle.contains("gymappRequireReviewedFirebaseConfig"))
        assertTrue(gradle.contains("gymappFirebaseConfigSha256"))
        assertTrue(gradle.contains("com.google.firebase:firebase-messaging"))
        assertTrue(gradle.contains("FIREBASE_CONFIGURED"))
        listOf(playRelease, phoneRelease).forEach { script ->
            assertTrue(script.contains("Resolve-ReviewedReleaseFirebaseConfig"))
            assertTrue(script.contains("-PgymappRequireReviewedFirebaseConfig=true"))
            assertTrue(script.contains("-PgymappFirebaseConfigSha256="))
            assertTrue(script.contains("Assert-ReleaseFirebaseBuildConfig"))
            assertTrue(script.contains("Assert-ReleaseFirebaseArtifact"))
        }
        assertTrue(releaseGate.contains("must remain outside the repository"))
        assertTrue(releaseGate.contains("owner-only mode 0600"))
        assertTrue(releaseGate.contains("FIREBASE_CONFIGURED = true"))
        assertNull(appFileOrNull("google-services.json"))
    }

    @Test
    fun `durable reconciliation work never persists a provider token as input`() {
        val worker = Files.readString(
            appFile("src/main/java/com/example/gymapp/push/PushReconciliationWorker.kt")
        )

        assertTrue(worker.contains("containsPrivateInputData = false"))
        assertFalse(worker.contains("setInputData("))
    }

    private fun parseXml(path: Path) = DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
        setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        setFeature("http://xml.org/sax/features/external-general-entities", false)
        setFeature("http://xml.org/sax/features/external-parameter-entities", false)
        setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
        isXIncludeAware = false
        isExpandEntityReferences = false
    }.newDocumentBuilder().parse(path.toFile())

    private fun Element.androidAttribute(name: String): String =
        getAttributeNS("http://schemas.android.com/apk/res/android", name)

    private fun appFile(relativePath: String): Path = appFileOrNull(relativePath)
        ?: error("Could not locate app/$relativePath")

    private fun appFileOrNull(relativePath: String): Path? {
        val workingDirectory = Paths.get("").toAbsolutePath().normalize()
        return generateSequence(workingDirectory) { it.parent }
            .flatMap { directory ->
                sequenceOf(
                    directory.resolve(relativePath),
                    directory.resolve("app").resolve(relativePath)
                )
            }
            .distinct()
            .firstOrNull(Files::isRegularFile)
    }
}
