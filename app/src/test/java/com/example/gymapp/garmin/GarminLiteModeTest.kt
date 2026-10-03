package com.example.gymapp.garmin

import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GarminLiteModeTest {
    private val device = "123456789"
    private val binding = GarminBinding(
        account = "a".repeat(64),
        device = device,
        pairingGeneration = "1".repeat(64)
    )
    private val syncId = "sync-request-1234567890"

    private class FakeStore(
        val values: MutableMap<String, Boolean> = mutableMapOf(),
        val failing: Boolean = false
    ) : GarminLiteFlagStore {
        var writes = 0
        override fun read(deviceBinding: String): Boolean? {
            if (failing) error("read failed")
            return values[deviceBinding]
        }

        override fun write(deviceBinding: String, lite: Boolean) {
            if (failing) error("write failed")
            writes++
            values[deviceBinding] = lite
        }
    }

    private fun requestSync(version: Any?): Map<Any?, Any?> = buildMap {
        put("type", "request_sync")
        put("requestId", "request-1234567890")
        if (version != null) put("watchVersion", version)
    }

    private fun ack(applied: Boolean, lite: Any? = null): Map<Any?, Any?> = buildMap {
        put("type", "sync_ack")
        put("syncId", syncId)
        put("requestId", syncId)
        put("syncRevision", 1_800_000_000_123L)
        put("applied", applied)
        if (lite != null) put("lite", lite)
    }

    @Test
    fun liteIsDetectedFromTheWatchVersionSuffixOnly() {
        assertTrue(garminWatchVersionIsLite("2026.08.20.1521-lite"))
        assertFalse(garminWatchVersionIsLite("2026.08.20.1521"))
        assertFalse(garminWatchVersionIsLite("-lite"))
        assertFalse(garminWatchVersionIsLite("2026.08.20-lite.1"))
        assertFalse(garminWatchVersionIsLite("2026.08.20.1521-LITE"))
        assertFalse(garminWatchVersionIsLite(null))
    }

    @Test
    fun watchVersionIsBoundedAndPrintableAscii() {
        assertEquals(
            "2026.08.20.1521-lite",
            garminWatchVersionOrNull(requestSync("2026.08.20.1521-lite"))
        )
        assertNull(garminWatchVersionOrNull(requestSync(null)))
        assertNull(garminWatchVersionOrNull(requestSync("")))
        assertNull(garminWatchVersionOrNull(requestSync(12345)))
        assertNull(garminWatchVersionOrNull(requestSync("1".repeat(MAX_GARMIN_WATCH_VERSION_CHARS + 1))))
        assertEquals(
            "1".repeat(MAX_GARMIN_WATCH_VERSION_CHARS),
            garminWatchVersionOrNull(requestSync("1".repeat(MAX_GARMIN_WATCH_VERSION_CHARS)))
        )
        assertNull(garminWatchVersionOrNull(requestSync("1.0 -lite")))
        assertNull(garminWatchVersionOrNull(requestSync("1.0-lite\n")))
        assertNull(garminWatchVersionOrNull(requestSync("1.0-lité")))
        assertNull(garminRequestSyncLiteVerdict(requestSync("x".repeat(500) + "-lite")))
        assertEquals(true, garminRequestSyncLiteVerdict(requestSync("1.0-lite")))
        assertEquals(false, garminRequestSyncLiteVerdict(requestSync("1.0")))
    }

    @Test
    fun ackLiteMarkerMustBeTheExactIntegerOne() {
        assertTrue(garminSyncAckIsLite(ack(applied = true, lite = 1)))
        assertTrue(garminSyncAckIsLite(ack(applied = true, lite = 1L)))
        assertFalse(garminSyncAckIsLite(ack(applied = true)))
        assertFalse(garminSyncAckIsLite(ack(applied = true, lite = 0)))
        assertFalse(garminSyncAckIsLite(ack(applied = true, lite = 2)))
        assertFalse(garminSyncAckIsLite(ack(applied = true, lite = "1")))
        assertFalse(garminSyncAckIsLite(ack(applied = true, lite = true)))
        assertFalse(garminSyncAckIsLite(ack(applied = true, lite = 1.0)))
        assertFalse(garminSyncAckIsLite(ack(applied = true, lite = 1) + ("type" to "sync")))
    }

    @Test
    fun liteAcknowledgementIsAcceptedOnceAndRefusalStopsRetries() {
        val revision = 1_800_000_000_123L
        val applied = ack(applied = true, lite = 1)
        assertTrue(garminSyncAckMatches(applied, syncId, revision))
        assertFalse(garminLiteSyncAckRefused(applied, syncId, revision))

        val refused = ack(applied = false, lite = 1)
        assertFalse(garminSyncAckMatches(refused, syncId, revision))
        assertTrue(garminLiteSyncAckRefused(refused, syncId, revision))

        // A refusal is only trusted from a lite watch and only for the exact sync.
        assertFalse(garminLiteSyncAckRefused(ack(applied = false), syncId, revision))
        assertFalse(garminLiteSyncAckRefused(refused, syncId, revision + 1))
        assertFalse(garminLiteSyncAckRefused(refused, "other-sync-1234567890", revision))
        assertFalse(garminLiteSyncAckRefused(refused + ("requestId" to "other-id-12345678901"), syncId, revision))
        assertFalse(garminLiteSyncAckRefused(refused + ("syncRevision" to 5), syncId, revision))
        assertFalse(garminLiteSyncAckRefused(refused + ("applied" to "false"), syncId, revision))
    }

    @Test
    fun planTooLargeRefusalNeedsExactCorrelationAndReason() {
        val revision = 1_800_000_000_123L
        val refused = ack(applied = false) + ("reason" to "plan_too_large")
        assertTrue(garminPlanTooLargeAckRefused(refused, syncId, revision))
        // Also accepted from a watch that adds the lite marker.
        assertTrue(garminPlanTooLargeAckRefused(refused + ("lite" to 1), syncId, revision))
        assertFalse(garminSyncAckMatches(refused, syncId, revision))

        assertFalse(garminPlanTooLargeAckRefused(ack(applied = false), syncId, revision))
        assertFalse(
            garminPlanTooLargeAckRefused(
                ack(applied = false) + ("reason" to "other"),
                syncId,
                revision
            )
        )
        assertFalse(garminPlanTooLargeAckRefused(refused + ("reason" to "PLAN_TOO_LARGE"), syncId, revision))
        assertFalse(garminPlanTooLargeAckRefused(refused + ("reason" to null), syncId, revision))
        assertFalse(garminPlanTooLargeAckRefused(refused + ("applied" to true), syncId, revision))
        assertFalse(garminPlanTooLargeAckRefused(refused + ("applied" to "false"), syncId, revision))
        assertFalse(garminPlanTooLargeAckRefused(refused + ("applied" to null), syncId, revision))
        assertFalse(garminPlanTooLargeAckRefused(refused, syncId, revision + 1))
        assertFalse(garminPlanTooLargeAckRefused(refused, "other-sync-1234567890", revision))
        assertFalse(garminPlanTooLargeAckRefused(refused + ("syncId" to "other-sync-1234567890"), syncId, revision))
        assertFalse(garminPlanTooLargeAckRefused(refused + ("requestId" to "other-id-12345678901"), syncId, revision))
        assertFalse(garminPlanTooLargeAckRefused(refused + ("syncRevision" to 5), syncId, revision))
        assertFalse(garminPlanTooLargeAckRefused(refused + ("type" to "sync"), syncId, revision))
        assertFalse(garminPlanTooLargeAckRefused(refused, "bad id", revision))
        assertFalse(garminPlanTooLargeAckRefused(refused, syncId, 0L))
        val oversized = refused + (1..MAX_GARMIN_COMMAND_ENTRIES).associate { "x$it" to 1 }
        assertFalse(garminPlanTooLargeAckRefused(oversized, syncId, revision))
    }

    @Test
    fun bindingOnlyPayloadHasEmptyPlanArraysAndNoCatalog() {
        val base = garminBindingOnlySyncPayload(language = "uk", syncId = syncId)
        assertEquals("sync", base["type"])
        assertEquals(emptyList<Any>(), base["planNames"])
        assertEquals(emptyList<Any>(), base["planWeights"])
        assertEquals(emptyList<Any>(), base["planReps"])
        assertFalse(base.containsKey("exercises"))
        assertEquals("uk", base["language"])
        assertEquals(false, base["resetWorkout"])
        assertFalse(base.containsKey("repairPairing"))
        assertEquals(syncId, base["syncId"])
        assertEquals(syncId, base["requestId"])

        val bound = checkNotNull(
            boundGarminSyncPayload(base, binding, 1_800_000_000_123L, includePairingGeneration = true)
        )
        assertEquals(binding.account, bound["accountBinding"])
        assertEquals(binding.device, bound["deviceBinding"])
        assertEquals(binding.pairingGeneration, bound["pairingGeneration"])
        assertEquals(GARMIN_BINDING_VERSION, bound["bindingVersion"])
        assertEquals(1_800_000_000_123L, bound["syncRevision"])
        assertTrue(bound["syncRevision"] is Long)
        assertEquals(emptyList<Any>(), bound["planNames"])
        assertFalse(bound.containsKey("exercises"))

        val legacy = checkNotNull(
            boundGarminSyncPayload(base, binding, 1_800_000_000_123L, includePairingGeneration = false)
        )
        assertFalse(legacy.containsKey("pairingGeneration"))

        val repair = garminBindingOnlySyncPayload("en", syncId, repairPairing = true)
        assertEquals(true, repair["repairPairing"])
    }

    @Test
    fun bindingOnlyPayloadIsMuchSmallerThanAFullPlanPayloadAndNonLiteIsUnchanged() {
        val key = GarminPlanSubmissionKey(
            accountBinding = binding.account,
            authTransitionKey = "b".repeat(64),
            deviceBinding = binding.device,
            pairingGeneration = binding.pairingGeneration,
            includePairingGeneration = true,
            languageTag = "en",
            orderedPlan = (1..20).map {
                NamedWorkoutSetDraft(exerciseName = "Exercise number $it", weight = 40.0 + it, reps = 8)
            },
            exerciseCatalog = (1..40).map { "Catalog exercise $it" }
        )
        val envelope = checkNotNull(
            prepareGarminPlanSubmission(
                key = key,
                encodedExisting = null,
                lastGlobalRevision = null,
                nowMillis = 1_800_000_000_000L,
                newRequestId = { syncId }
            )
        ).envelope
        val full = checkNotNull(materializeGarminPlanSubmissionPayload(key, envelope))

        // Non-lite sync keeps the plan columns and the free-order catalog.
        assertEquals(20, (full["planNames"] as List<*>).size)
        assertEquals(20, (full["planWeights"] as List<*>).size)
        assertEquals(20, (full["planReps"] as List<*>).size)
        assertTrue((full["exercises"] as List<*>).isNotEmpty())

        val lite = checkNotNull(
            boundGarminSyncPayload(
                garminBindingOnlySyncPayload("en", syncId),
                binding,
                envelope.revision
            )
        )
        val fullBytes = checkNotNull(estimatedGarminConnectIqWireBytes(full))
        val liteBytes = checkNotNull(estimatedGarminConnectIqWireBytes(lite))
        assertTrue("lite=$liteBytes full=$fullBytes", liteBytes < 600)
        assertTrue(liteBytes * 4 < fullBytes)
        assertNotNull(lite["syncRevision"])
    }

    @Test
    fun trackerRemembersLiteFromRequestSyncAndClearsItForANonLiteBuild() {
        val store = FakeStore()
        val tracker = GarminLiteWatchTracker(store)
        assertFalse(tracker.isLite(device))

        assertTrue(tracker.recordRequestSync(device, requestSync("2026.08.20.1521-lite")))
        assertTrue(tracker.isLite(device))
        assertEquals(true, store.values[device])

        // Same verdict again changes nothing and writes nothing.
        val writes = store.writes
        assertFalse(tracker.recordRequestSync(device, requestSync("2026.08.20.1521-lite")))
        assertEquals(writes, store.writes)

        // A request without a usable version leaves the verdict alone.
        assertFalse(tracker.recordRequestSync(device, requestSync(null)))
        assertFalse(tracker.recordRequestSync(device, requestSync("x".repeat(100))))
        assertTrue(tracker.isLite(device))

        assertTrue(tracker.recordRequestSync(device, requestSync("2026.08.20.1521")))
        assertFalse(tracker.isLite(device))
        assertEquals(false, store.values[device])
    }

    @Test
    fun trackerReadsAPersistedVerdictAfterRestart() {
        val store = FakeStore(mutableMapOf(device to true))
        assertTrue(GarminLiteWatchTracker(store).isLite(device))
        assertFalse(GarminLiteWatchTracker(store).isLite("987654321"))
    }

    @Test
    fun trackerNeverSwitchesAWatchToNonLiteFromAnAckAndOnlySetsLiteFromOne() {
        val store = FakeStore()
        val tracker = GarminLiteWatchTracker(store)

        assertFalse(tracker.recordSyncAck(device, ack(applied = true)))
        assertFalse(tracker.isLite(device))

        assertTrue(tracker.recordSyncAck(device, ack(applied = true, lite = 1)))
        assertTrue(tracker.isLite(device))
        assertFalse(tracker.recordSyncAck(device, ack(applied = true)))
        assertTrue(tracker.isLite(device))
        assertEquals(true, store.values[device])
    }

    @Test
    fun trackerIgnoresInvalidDeviceBindingsAndSurvivesStorageFailure() {
        val tracker = GarminLiteWatchTracker(FakeStore())
        assertFalse(tracker.recordRequestSync("not-a-device", requestSync("1.0-lite")))
        assertFalse(tracker.isLite("not-a-device"))

        val failing = GarminLiteWatchTracker(FakeStore(failing = true))
        assertFalse(failing.isLite(device))
        failing.recordRequestSync(device, requestSync("1.0-lite"))
        // The in-memory verdict still protects the watch for this process.
        assertTrue(failing.isLite(device))
    }

    @Test
    fun uiStateReportsOnlyTheTrustedWatchAsLite() {
        val lite = GarminDeviceSummary("Instinct 2", connected = true, trustedForActiveAccount = true, liteMode = true)
        val other = GarminDeviceSummary("Forerunner", connected = true, trustedForActiveAccount = false)
        assertTrue(GarminDeviceUiState(true, listOf(other, lite)).trustedWatchIsLite)
        assertFalse(
            GarminDeviceUiState(true, listOf(lite.copy(trustedForActiveAccount = false), other))
                .trustedWatchIsLite
        )
        assertFalse(GarminDeviceUiState(true, listOf(other.copy(trustedForActiveAccount = true))).trustedWatchIsLite)
        assertFalse(GarminDeviceUiState().trustedWatchIsLite)
    }

    @Test
    fun freeWorkoutFromALiteWatchParsesAsActivityOnly() {
        val nowMillis = 1_800_000_000_000L
        val free = mapOf<Any?, Any?>(
            "type" to "create_workout",
            "requestId" to "lite-free-workout-123456",
            "workoutMode" to "free",
            "startedAtSeconds" to 1_700_000_000L,
            "durationSeconds" to 1_800L,
            "gymCalories" to 120.5,
            "avgHeartRate" to 118,
            "maxHeartRate" to 151,
            "sets" to emptyList<Any>()
        )
        val parsed = checkNotNull(parseGarminWorkoutCommand(free, nowMillis))
        assertEquals(GarminWorkoutMode.Free, parsed.mode)
        assertTrue(parsed.sets.isEmpty())
        assertEquals(1_800L, parsed.durationSeconds)
        assertEquals(118, parsed.averageHeartRate)
        assertEquals(151, parsed.maximumHeartRate)
    }
}
