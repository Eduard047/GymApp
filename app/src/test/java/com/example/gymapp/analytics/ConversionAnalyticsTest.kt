package com.example.gymapp.analytics

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class MemoryStorage(
    var consent: Boolean? = null,
    var firstWorkoutLogged: Boolean = false
) : ConversionAnalyticsStorage {
    override fun readConsent(): Boolean? = consent
    override fun writeConsent(granted: Boolean) {
        consent = granted
    }
    override fun readFirstWorkoutLogged(): Boolean = firstWorkoutLogged
    override fun writeFirstWorkoutLogged() {
        firstWorkoutLogged = true
    }
}

private class RecordingSink : AnalyticsSink {
    override val available: Boolean = true
    val calls = mutableListOf<String>()
    val events = mutableListOf<Pair<String, Map<String, String>>>()
    var lastConsent: AnalyticsConsentState? = null
    var collectionEnabled: Boolean? = null

    override fun setCollectionEnabled(enabled: Boolean) {
        collectionEnabled = enabled
        calls += "collection=$enabled"
    }

    override fun setConsent(state: AnalyticsConsentState) {
        lastConsent = state
        calls += "consent"
    }

    override fun resetAnalyticsData() {
        calls += "reset"
    }

    override fun logEvent(name: String, params: Map<String, String>) {
        events += name to params
    }
}

class ConversionAnalyticsTest {
    @Test
    fun `allow enables collection and grants measurement signals but never personalization`() {
        val sink = RecordingSink()
        val analytics = ConversionAnalytics(MemoryStorage(), sink)
        assertNull(analytics.consent.value)

        analytics.setConsent(true)

        assertEquals(true, analytics.consent.value)
        assertEquals(true, sink.collectionEnabled)
        assertEquals(AnalyticsConsentState(true, true, true, false), sink.lastConsent)
        assertFalse("reset must not run on allow", "reset" in sink.calls)
    }

    @Test
    fun `deny and revoke disable collection deny every signal and reset analytics data`() {
        val sink = RecordingSink()
        val analytics = ConversionAnalytics(MemoryStorage(), sink)
        analytics.setConsent(true)
        sink.calls.clear()

        analytics.setConsent(false)

        assertEquals(false, analytics.consent.value)
        assertEquals(false, sink.collectionEnabled)
        assertEquals(AnalyticsConsentState(false, false, false, false), sink.lastConsent)
        assertEquals(listOf("collection=false", "consent", "reset"), sink.calls)
    }

    @Test
    fun `choice is persisted and a stored allow is re-applied at startup while deny and unasked are not`() {
        val storage = MemoryStorage()
        ConversionAnalytics(storage, RecordingSink()).setConsent(true)
        val allowedSink = RecordingSink()
        val restarted = ConversionAnalytics(storage, allowedSink)
        assertEquals(true, restarted.consent.value)
        restarted.applyStoredChoice()
        assertEquals(true, allowedSink.collectionEnabled)

        listOf(MemoryStorage(consent = false), MemoryStorage(consent = null)).forEach {
            val sink = RecordingSink()
            ConversionAnalytics(it, sink).applyStoredChoice()
            assertTrue("nothing is sent to the SDK at startup", sink.calls.isEmpty())
        }
    }

    @Test
    fun `sign up logs only the email method and only with consent`() {
        val sink = RecordingSink()
        val analytics = ConversionAnalytics(MemoryStorage(), sink)
        analytics.logSignUp()
        assertTrue(sink.events.isEmpty())

        analytics.setConsent(true)
        analytics.logSignUp()
        assertEquals(listOf("sign_up" to mapOf("method" to "email")), sink.events)

        analytics.setConsent(false)
        analytics.logSignUp()
        assertEquals(1, sink.events.size)
    }

    @Test
    fun `first workout fires once for a brand new history`() {
        val storage = MemoryStorage(consent = true)
        val sink = RecordingSink()
        val analytics = ConversionAnalytics(storage, sink)

        analytics.onWorkoutFinished(1)
        analytics.onWorkoutFinished(1)
        analytics.onWorkoutFinished(2)

        assertEquals(listOf("first_workout" to emptyMap<String, String>()), sink.events)
        assertTrue(storage.firstWorkoutLogged)
        // Survives a restart: a new instance on the same storage never fires it again.
        val again = RecordingSink()
        ConversionAnalytics(storage, again).onWorkoutFinished(1)
        assertTrue(again.events.isEmpty())
    }

    @Test
    fun `first workout does not fire for users who already had workouts`() {
        val storage = MemoryStorage(consent = true)
        val sink = RecordingSink()
        val analytics = ConversionAnalytics(storage, sink)

        analytics.onWorkoutFinished(2)
        analytics.onWorkoutFinished(40)

        assertTrue(sink.events.isEmpty())
        assertFalse(storage.firstWorkoutLogged)
    }

    @Test
    fun `first workout needs consent and does not consume the flag without it`() {
        val storage = MemoryStorage(consent = false)
        val sink = RecordingSink()
        val analytics = ConversionAnalytics(storage, sink)

        analytics.onWorkoutFinished(1)

        assertTrue(sink.events.isEmpty())
        assertFalse(storage.firstWorkoutLogged)

        val unasked = MemoryStorage()
        ConversionAnalytics(unasked, sink).onWorkoutFinished(1)
        assertTrue(sink.events.isEmpty())
        assertFalse(unasked.firstWorkoutLogged)
    }

    @Test
    fun `without Firebase every call is a silent no-op and the choice still persists`() {
        val storage = MemoryStorage()
        val analytics = ConversionAnalytics(storage, NoOpAnalyticsSink)
        assertFalse("no prompt or settings row without a Firebase client", analytics.available)

        analytics.applyStoredChoice()
        analytics.setConsent(true)
        analytics.logSignUp()
        analytics.onWorkoutFinished(1)
        analytics.setConsent(false)

        assertEquals(false, storage.consent)
    }

    @Test
    fun `manifest keeps measurement off and consent denied by default`() {
        val manifest = Files.readString(appFile("src/main/AndroidManifest.xml"))
        listOf(
            "firebase_analytics_collection_enabled",
            "google_analytics_automatic_screen_reporting_enabled",
            "google_analytics_default_allow_analytics_storage",
            "google_analytics_default_allow_ad_storage",
            "google_analytics_default_allow_ad_user_data",
            "google_analytics_default_allow_ad_personalization_signals"
        ).forEach { name ->
            assertTrue(
                "$name must default to false",
                Regex(
                    "android:name=\"$name\"\\s+android:value=\"false\""
                ).containsMatchIn(manifest)
            )
        }
    }

    @Test
    fun `analytics state is excluded from every Android backup mode`() {
        val legacy = Files.readString(appFile("src/main/res/xml/backup_rules.xml"))
        val extraction = Files.readString(appFile("src/main/res/xml/data_extraction_rules.xml"))
        listOf(
            "gym_analytics_consent_v1.xml",
            "com.google.android.gms.measurement.prefs.xml"
        ).forEach { path ->
            assertEquals(1, Regex("path=\"${Regex.escape(path)}\"").findAll(legacy).count())
            assertEquals(2, Regex("path=\"${Regex.escape(path)}\"").findAll(extraction).count())
        }
    }

    @Test
    fun `only the analytics wrapper imports Firebase Analytics`() {
        val sources = appFile("src/main/java/com/example/gymapp/analytics/ConversionAnalytics.kt")
            .parent.parent
        val offenders = Files.walk(sources).use { files ->
            files.filter { it.toString().endsWith(".kt") }
                .filter { Files.readString(it).contains("com.google.firebase.analytics") }
                .map { it.fileName.toString() }
                .toList()
        }
        assertEquals(listOf("ConversionAnalytics.kt"), offenders)
    }

    private fun appFile(relativePath: String): Path {
        val workingDirectory = Paths.get("").toAbsolutePath().normalize()
        return generateSequence(workingDirectory) { it.parent }
            .flatMap { directory ->
                sequenceOf(directory.resolve(relativePath), directory.resolve("app").resolve(relativePath))
            }
            .distinct()
            .firstOrNull(Files::isRegularFile)
            ?: error("Could not locate app/$relativePath")
    }
}
