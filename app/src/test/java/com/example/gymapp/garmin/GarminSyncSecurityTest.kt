package com.example.gymapp.garmin

import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.util.AppLanguage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GarminSyncSecurityTest {
    @Test
    fun pendingAccountResetCanOnlyStartFromExplicitUserAction() {
        assertTrue(
            shouldAttemptPendingGarminReset(GarminPendingResetTrigger.ExplicitUserAction)
        )
        assertFalse(
            shouldAttemptPendingGarminReset(GarminPendingResetTrigger.AuthenticationChange)
        )
        assertFalse(shouldAttemptPendingGarminReset(GarminPendingResetTrigger.SdkReady))
        assertFalse(
            shouldAttemptPendingGarminReset(GarminPendingResetTrigger.DeviceStatusChange)
        )
    }

    @Test
    fun deviceEventRegistrationIsIdempotentAndCanRecoverAfterSdkShutdown() {
        val tracker = GarminDeviceRegistrationTracker()

        assertTrue(tracker.claim(123456789L))
        assertFalse(tracker.claim(123456789L))
        assertTrue(tracker.claim(987654321L))

        tracker.release(123456789L)
        assertTrue(tracker.claim(123456789L))

        tracker.clear()
        assertTrue(tracker.claim(123456789L))
        assertTrue(tracker.claim(987654321L))
    }

    @Test
    fun cloudAccountBindingMatchesCanonicalServerHash() {
        val expected = "986c0dc956dc822b5d8f698661b9eb1ef880786ff9043c16744d2a420e99e9bb"

        assertEquals(
            expected,
            canonicalCloudGarminAccountBinding(" 123E4567-E89B-12D3-A456-426614174000 ")
        )
        assertTrue(isValidGarminAccountBinding(expected))
        assertNull(canonicalCloudGarminAccountBinding("not-a-supabase-uuid"))
        assertNull(canonicalCloudGarminAccountBinding("x".repeat(10_000)))
        assertFalse(isValidGarminAccountBinding(expected.uppercase()))
        assertFalse(isValidGarminAccountBinding("a".repeat(63)))
    }

    @Test
    fun localAccountBindingIsRandomDomainSeparatedAndProtocolCompatible() {
        val first = newLocalGarminAccountBinding("fixed-random-id")
        val second = newLocalGarminAccountBinding("another-random-id")

        assertEquals(
            "96d29274f065bdcf076d7d30f29c3b6c678a2f8e83e66282b02b751eff147278",
            first
        )
        assertTrue(isValidGarminAccountBinding(first))
        assertNotEquals(first, second)
    }

    @Test
    fun stalePairingPreferenceCleanupKeepsOnlyTheCurrentScopedKeys() {
        val prefixes = listOf(
            "pairing_generation_v1_",
            "pairing_generation_pending_v1_",
            "pairing_generation_capable_v1_"
        )
        val retained = setOf(
            "pairing_generation_v1_current",
            "pairing_generation_pending_v1_current",
            "pairing_generation_capable_v1_current"
        )
        val unrelated = "pairing_generation_v10_not-this-prefix"
        val stale = setOf(
            "pairing_generation_v1_old",
            "pairing_generation_pending_v1_old",
            "pairing_generation_capable_v1_old"
        )

        assertEquals(
            stale,
            garminScopedPreferenceKeysToRemove(
                existingKeys = retained + stale + unrelated,
                retainedKeys = retained,
                scopedPrefixes = prefixes
            )
        )
    }

    @Test
    fun boundCommandsRequireBothCurrentAccountAndTransportDevice() {
        val expected = GarminBinding(
            account = "a".repeat(64),
            device = "123456789",
            pairingGeneration = "1".repeat(64)
        )
        val bound = mapOf<Any?, Any?>(
            "bindingVersion" to GARMIN_BINDING_VERSION,
            "accountBinding" to expected.account,
            "deviceBinding" to expected.device,
            "pairingGeneration" to expected.pairingGeneration
        )

        assertEquals(
            GarminBindingDecision.Bound,
            garminBindingDecision(bound, expected)
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(bound - "deviceBinding", expected)
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(bound - "pairingGeneration", expected)
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(
                bound + ("accountBinding" to "b".repeat(64)),
                expected
            )
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(
                bound + ("deviceBinding" to "987654321"),
                expected
            )
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(
                bound + ("pairingGeneration" to "2".repeat(64)),
                expected
            )
        )
    }

    @Test
    fun protocolDowngradesMissingVersionsAndWrongTypesAreRejected() {
        val expected = GarminBinding(
            account = "a".repeat(64),
            device = "123456789",
            pairingGeneration = "1".repeat(64)
        )
        val base = mapOf<Any?, Any?>(
            "accountBinding" to expected.account,
            "deviceBinding" to expected.device,
            "pairingGeneration" to expected.pairingGeneration
        )

        assertEquals(GarminBindingDecision.Rejected, garminBindingDecision(base, expected))
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(base + ("bindingVersion" to 1), expected)
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(base + ("bindingVersion" to 2.5), expected)
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(base + ("bindingVersion" to "2"), expected)
        )
        assertEquals(
            GarminBindingDecision.Bound,
            garminBindingDecision(base + ("bindingVersion" to 2L), expected)
        )

        val outbound = boundGarminPayload(
            payload = mapOf("type" to "sync"),
            binding = expected
        )
        assertEquals(GARMIN_BINDING_VERSION, outbound["bindingVersion"])
        assertEquals(expected.account, outbound["accountBinding"])
        assertEquals(expected.device, outbound["deviceBinding"])
        assertEquals(expected.pairingGeneration, outbound["pairingGeneration"])
    }

    @Test
    fun syncRevisionIsExactMonotonicAndFailsClosedAtSafeIntegerLimit() {
        val now = 1_800_000_000_000L

        assertEquals(now, nextGarminSyncRevision(lastRevision = null, nowMillis = now))
        assertEquals(
            now + 1L,
            nextGarminSyncRevision(lastRevision = now, nowMillis = now)
        )
        assertEquals(
            now + 101L,
            nextGarminSyncRevision(lastRevision = now + 100L, nowMillis = now - 10_000L)
        )
        assertNull(
            nextGarminSyncRevision(
                lastRevision = MAX_GARMIN_SYNC_REVISION,
                nowMillis = now
            )
        )
        assertNull(nextGarminSyncRevision(lastRevision = -1L, nowMillis = now))
        assertNull(
            nextGarminSyncRevision(
                lastRevision = null,
                nowMillis = MAX_GARMIN_SYNC_REVISION + 1L
            )
        )
    }

    @Test
    fun accountSwitchSharesOneDeviceFenceAndRejectsDelayedPriorAccountRevision() {
        val device = "123456789"
        val accountAKey = globalGarminSyncRevisionStorageKey(device)
        val accountBKey = globalGarminSyncRevisionStorageKey(device)
        val accountARevision = checkNotNull(
            nextGarminSyncRevision(lastRevision = null, nowMillis = 1_800_000_000_000L)
        )
        val accountBRevision = checkNotNull(
            nextGarminSyncRevision(
                lastRevision = accountARevision,
                nowMillis = 1_800_000_000_000L
            )
        )

        assertEquals(accountAKey, accountBKey)
        assertTrue(accountBRevision > accountARevision)
        assertTrue(accountARevision < accountBRevision)
        assertNotEquals(accountAKey, globalGarminSyncRevisionStorageKey("987654321"))
        assertNull(globalGarminSyncRevisionStorageKey("not-a-device"))
    }

    @Test
    fun retriesKeepOneLongRevisionDistinctFromSyncId() {
        val binding = GarminBinding(
            account = "a".repeat(64),
            device = "123456789",
            pairingGeneration = "1".repeat(64)
        )
        val syncId = "sync-request-1234567890"
        val base = mapOf<String, Any>(
            "type" to "sync",
            "syncId" to syncId,
            "requestId" to syncId
        )
        val revision = 1_800_000_000_123L

        val firstAttempt = boundGarminSyncPayload(base, binding, revision)
        val retryAttempt = boundGarminSyncPayload(base, binding, revision)

        assertNotNull(firstAttempt)
        assertEquals(firstAttempt, retryAttempt)
        checkNotNull(retryAttempt)
        assertTrue(retryAttempt["syncRevision"] is Long)
        assertEquals(revision, retryAttempt["syncRevision"])
        assertEquals(syncId, retryAttempt["syncId"])
        assertEquals(syncId, retryAttempt["requestId"])
        assertNotEquals(syncId, retryAttempt["syncRevision"].toString())
        assertNull(boundGarminSyncPayload(base, binding, 0L))
    }

    @Test
    fun syncAckMustEchoExactRequestAndLongRevision() {
        val syncId = "sync-request-1234567890"
        val revision = 1_800_000_000_123L
        val valid = mapOf<Any?, Any?>(
            "type" to "sync_ack",
            "syncId" to syncId,
            "requestId" to syncId,
            "syncRevision" to revision,
            "applied" to true
        )

        assertTrue(garminSyncAckMatches(valid, syncId, revision))
        assertFalse(garminSyncAckMatches(valid + ("syncRevision" to revision - 1L), syncId, revision))
        assertFalse(garminSyncAckMatches(valid + ("syncRevision" to revision.toDouble()), syncId, revision))
        assertFalse(garminSyncAckMatches(valid + ("requestId" to "other-request-123456"), syncId, revision))
        assertFalse(garminSyncAckMatches(valid + ("applied" to false), syncId, revision))
    }

    @Test
    fun callbackAdmissionCapsHugeBatchesAndQueueFloods() {
        val work = mapOf<Any?, Any?>(
            "type" to "request_sync",
            "requestId" to "request-1234567890"
        )
        val messages = List(10_000) { work }

        val envelopes = boundedGarminInboundEnvelopes(messages)

        assertEquals(MAX_GARMIN_EVENT_BATCH, envelopes.size)
        assertTrue(envelopes.all { it.kind == GarminInboundCommandKind.Work })

        val channel = newBoundedGarminInboundChannel<Int>(MAX_GARMIN_PENDING_WORK_COMMANDS)
        val accepted = (0 until 10_000).count { channel.trySend(it).isSuccess }
        assertEquals(MAX_GARMIN_PENDING_WORK_COMMANDS, accepted)
        channel.cancel()

        val malformedAckFlood = List(10_000) {
            mapOf<Any?, Any?>(
                "type" to "sync_ack",
                "syncId" to "sync-request-1234567890",
                "requestId" to "sync-request-1234567890",
                "syncRevision" to 1_800_000_000_123.0,
                "applied" to true
            )
        }
        assertTrue(boundedGarminInboundEnvelopes(malformedAckFlood).isEmpty())
    }

    @Test
    fun watchOriginatedSyncNeverBootstrapsAnUnboundDevice() {
        val expected = GarminBinding(
            account = "a".repeat(64),
            device = "123456789",
            pairingGeneration = "1".repeat(64)
        )

        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(emptyMap(), expected)
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(
                mapOf("deviceBinding" to expected.device),
                expected
            )
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(
                mapOf("deviceBinding" to "other-device"),
                expected
            )
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(mapOf("accountBinding" to expected.account), expected)
        )
    }

    @Test
    fun readOnlySyncCanUpgradeMissingGenerationButWorkoutBindingCannot() {
        val expected = GarminBinding(
            account = "a".repeat(64),
            device = "123456789",
            pairingGeneration = "1".repeat(64)
        )
        val legacySyncRequest = mapOf<Any?, Any?>(
            "bindingVersion" to GARMIN_BINDING_VERSION,
            "accountBinding" to expected.account,
            "deviceBinding" to expected.device
        )

        assertEquals(
            GarminBindingDecision.Bound,
            garminSyncRequestBindingDecision(legacySyncRequest, expected)
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(legacySyncRequest, expected)
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminSyncRequestBindingDecision(
                legacySyncRequest + ("pairingGeneration" to "2".repeat(64)),
                expected
            )
        )
        assertEquals(
            GarminSyncRequestBindingMismatch.PairingGeneration,
            garminSyncRequestBindingMismatch(
                legacySyncRequest + ("pairingGeneration" to "2".repeat(64)),
                expected
            )
        )
        assertEquals(
            GarminSyncRequestBindingMismatch.Account,
            garminSyncRequestBindingMismatch(
                legacySyncRequest + ("accountBinding" to "b".repeat(64)),
                expected
            )
        )
        assertEquals(
            GarminSyncRequestBindingMismatch.Device,
            garminSyncRequestBindingMismatch(
                legacySyncRequest + ("deviceBinding" to "other-device"),
                expected
            )
        )
        assertTrue(
            garminSyncRequestCanRepairPairing(
                legacySyncRequest + ("pairingGeneration" to "2".repeat(64)),
                expected
            )
        )
        assertFalse(
            garminSyncRequestCanRepairPairing(
                legacySyncRequest +
                    ("accountBinding" to "b".repeat(64)) +
                    ("pairingGeneration" to "2".repeat(64)),
                expected
            )
        )
        assertFalse(
            garminSyncRequestCanRepairPairing(
                legacySyncRequest + ("pairingGeneration" to "malformed"),
                expected
            )
        )
    }

    @Test
    fun releasedWatchFallbackIsExplicitAndGenerationlessOnly() {
        val fallback = GarminBinding(
            account = "a".repeat(64),
            device = "123456789",
            pairingGeneration = LEGACY_GARMIN_FALLBACK_GENERATION
        )
        val releasedWatchCommand = mapOf<Any?, Any?>(
            "bindingVersion" to GARMIN_BINDING_VERSION,
            "accountBinding" to fallback.account,
            "deviceBinding" to fallback.device
        )

        assertEquals(
            GarminBindingDecision.Bound,
            garminBindingDecision(releasedWatchCommand, fallback)
        )
        assertEquals(
            GarminBindingDecision.Rejected,
            garminBindingDecision(
                releasedWatchCommand + ("pairingGeneration" to "1".repeat(64)),
                fallback
            )
        )
        val payload = boundGarminPayload(
            payload = mapOf("type" to "ack"),
            binding = fallback,
            includePairingGeneration = false
        )
        assertFalse(payload.containsKey("pairingGeneration"))
    }

    @Test
    fun validWorkoutCommandKeepsLegitimateValues() {
        val nowMillis = 1_800_000_000_000L
        val parsed = parseGarminWorkoutCommand(validCommand(), nowMillis)

        assertNotNull(parsed)
        checkNotNull(parsed)
        assertEquals("request-1234567890", parsed.requestId)
        assertEquals(1_700_000_000_000L, parsed.startedAtMillis)
        assertEquals(listOf(NamedWorkoutSetDraft("Bench Press", 82.5, 8)), parsed.sets)
        assertEquals(3_600L, parsed.durationSeconds)
        assertEquals(450.5, parsed.gymCalories)
        assertEquals(430, parsed.garminCalories)
        assertEquals(132, parsed.averageHeartRate)
        assertEquals(168, parsed.maximumHeartRate)
        assertEquals(3, parsed.endingHeartRateZone)
        assertEquals(listOf(null), parsed.setStatistics)

        val resumedSegment = parseGarminWorkoutCommand(
            validCommand() - setOf(
                "durationSeconds",
                "gymCalories",
                "garminCalories",
                "avgHeartRate",
                "maxHeartRate",
                "heartRateZone"
            ),
            nowMillis
        )
        assertNotNull(resumedSegment)
        assertNull(resumedSegment?.durationSeconds)
        assertNull(resumedSegment?.gymCalories)
        assertNull(resumedSegment?.garminCalories)
        assertNull(resumedSegment?.averageHeartRate)
        assertNull(resumedSegment?.maximumHeartRate)
        assertNull(resumedSegment?.endingHeartRateZone)
    }

    @Test
    fun releasedWatchExplicitNullMetricsRemainCompatibleButMalformedValuesFailClosed() {
        val nowMillis = 1_800_000_000_000L
        val explicitNullMetrics = validCommand().toMutableMap().apply {
            listOf(
                "durationSeconds",
                "gymCalories",
                "garminCalories",
                "avgHeartRate",
                "maxHeartRate",
                "lastHeartRate",
                "heartRateZone"
            ).forEach { key -> put(key, null) }
        }

        val parsed = parseGarminWorkoutCommand(explicitNullMetrics, nowMillis)

        assertNotNull(parsed)
        assertNull(parsed?.durationSeconds)
        assertNull(parsed?.gymCalories)
        assertNull(parsed?.garminCalories)
        assertNull(parsed?.averageHeartRate)
        assertNull(parsed?.maximumHeartRate)
        assertNull(parsed?.endingHeartRateZone)

        listOf(
            "garminCalories" to "430",
            "garminCalories" to -1,
            "lastHeartRate" to "120",
            "lastHeartRate" to 301,
            "avgHeartRate" to 120.5,
            "durationSeconds" to Double.POSITIVE_INFINITY
        ).forEach { (key, value) ->
            assertNull(
                key,
                parseGarminWorkoutCommand(
                    explicitNullMetrics + (key to value),
                    nowMillis
                )
            )
        }
        assertNull(
            parseGarminWorkoutCommand(validCommand() + ("requestId" to null), nowMillis)
        )
        assertNull(parseGarminWorkoutCommand(validCommand() + ("sets" to null), nowMillis))
    }

    @Test
    fun workoutParserAcceptsBoundedSetStatisticsAndCanonicalizesLegacyPeakHeartRate() {
        val nowMillis = 1_800_000_000_000L
        val metrics = listOf<Any?>(
            32,
            64,
            112,
            148,
            130,
            24,
            90
        )
        val parsed = parseGarminWorkoutCommand(
            validCommand() + ("setMetrics" to listOf(metrics)),
            nowMillis
        )

        assertNotNull(parsed)
        assertEquals(
            GarminSetStatistics(
                activeSeconds = 32L,
                restBeforeSeconds = 64L,
                startHeartRate = 112,
                peakHeartRate = 148,
                endHeartRate = 130,
                recoveryHeartRateDrop = 24,
                detectionConfidence = 90
            ),
            parsed?.setStatistics?.single()
        )
        assertNull(
            parseGarminWorkoutCommand(
                validCommand() + ("setMetrics" to listOf(metrics.toMutableList().also { it[6] = 101 })),
                nowMillis
            )
        )
        assertEquals(
            GarminWorkoutParseIssue.SetMetricsShape,
            parseGarminWorkoutCommandResult(
                validCommand() + ("setMetrics" to listOf(metrics.dropLast(1))),
                nowMillis
            ).issue
        )
        assertEquals(
            GarminWorkoutParseIssue.SetMetricsDetectionConfidence,
            parseGarminWorkoutCommandResult(
                validCommand() +
                    ("setMetrics" to listOf(metrics.toMutableList().also { it[6] = 101 })),
                nowMillis
            ).issue
        )
        assertEquals(
            130,
            parseGarminWorkoutCommand(
                validCommand() +
                    ("setMetrics" to listOf(metrics.toMutableList().also { it[3] = 100 })),
                nowMillis
            )?.setStatistics?.single()?.peakHeartRate
        )
        assertEquals(
            GarminSetStatistics(
                activeSeconds = 32L,
                restBeforeSeconds = 64L,
                startHeartRate = null,
                peakHeartRate = null,
                endHeartRate = null,
                recoveryHeartRateDrop = null,
                detectionConfidence = 90
            ),
            parseGarminWorkoutCommand(
                validCommand() +
                    ("setMetrics" to listOf(listOf(32, 64, null, null, null, null, 90))),
                nowMillis
            )?.setStatistics?.single()
        )
        assertNull(
            parseGarminWorkoutCommand(
                validCommand() + ("setMetrics" to listOf(metrics.dropLast(1))),
                nowMillis
            )
        )
    }

    @Test
    fun workoutParserKeepsPartialMultiSetValuesAndBoundedIntervals() {
        val nowMillis = 1_800_000_000_000L
        val sets = listOf(
            validSet() + mapOf("weight" to 82.5, "reps" to 8),
            validSet() + mapOf("weight" to 80.0, "reps" to 7),
            validSet() + mapOf("weight" to 77.5, "reps" to 6)
        )
        val intervals = listOf(
            listOf(0, 42, 5.5, 6, 0, 0, 12, 20, 10, 0),
            listOf(90, 128, 4.25, null, 0, 3, 15, 15, 5, 0),
            listOf(180, 180, 82.5 * 8.0 / 700.0, 0, 0, 0, 0, 0, 0, 0)
        )
        val parsed = parseGarminWorkoutCommand(
            validCommand() + mapOf(
                "sets" to sets,
                "setIntervals" to intervals,
                "plannedSetCount" to 5,
                "plannedTargetSetCount" to 5,
                "completedPlannedSetCount" to 2
            ),
            nowMillis
        )

        assertNotNull(parsed)
        checkNotNull(parsed)
        assertEquals(
            listOf(
                NamedWorkoutSetDraft("Bench Press", 82.5, 8),
                NamedWorkoutSetDraft("Bench Press", 80.0, 7),
                NamedWorkoutSetDraft("Bench Press", 77.5, 6)
            ),
            parsed.sets
        )
        assertEquals(5, parsed.plannedSetCount)
        assertEquals(5, parsed.plannedTargetSetCount)
        assertEquals(2, parsed.completedPlannedSetCount)
        assertEquals(
            GarminSetInterval(
                startOffsetSeconds = 0,
                endOffsetSeconds = 42,
                gymCalories = 5.5,
                garminCalories = 6,
                heartRateZoneSeconds = listOf(0, 0, 12, 20, 10, 0)
            ),
            parsed.setIntervals.first()
        )
        val note = garminWorkoutNote(parsed, AppLanguage.EN)
        assertTrue(note.contains("Completed 2/5 sets"))
        assertTrue(note.contains("S1 I0-42s K5.5/6 Z0/0/12/20/10/0s"))
        assertTrue(note.contains("S2 I90-128s K4.25/- Z0/3/15/15/5/0s"))
        assertTrue(note.contains("S3 I180-180s K0.94/0 Z0/0/0/0/0/0s"))
        assertTrue(WorkoutDataLimits.isValidNote(note))
    }

    @Test
    fun exactPlannedTargetKeepsLegacyPlannedCountCompatibleWithExtraSets() {
        val nowMillis = 1_800_000_000_000L
        val wireCommand = validCommand() + mapOf(
            "sets" to List(4) { validSet() },
            "plannedSetCount" to 4,
            "plannedTargetSetCount" to 3,
            "completedPlannedSetCount" to 2
        )
        val parsed = checkNotNull(parseGarminWorkoutCommand(wireCommand, nowMillis))

        assertEquals(4, parsed.sets.size)
        assertEquals(4, parsed.plannedSetCount)
        assertEquals(3, parsed.plannedTargetSetCount)
        assertEquals(2, parsed.completedPlannedSetCount)
        assertTrue(garminWorkoutNote(parsed, AppLanguage.EN).contains("Completed 2/3 sets"))

        val legacyView = wireCommand - setOf(
            "plannedTargetSetCount",
            "completedPlannedSetCount"
        )
        val legacyParsed = checkNotNull(parseGarminWorkoutCommand(legacyView, nowMillis))
        assertEquals(4, legacyParsed.plannedSetCount)
        assertEquals(
            canonicalGarminWorkoutPayloadDigest(legacyParsed),
            canonicalGarminWorkoutPayloadDigest(parsed)
        )
    }

    @Test
    fun workoutParserRejectsMalformedSetIntervalsAndImpossibleCompletedCounts() {
        val nowMillis = 1_800_000_000_000L
        val validInterval = listOf<Any?>(0, 42, 5.5, 6, 0, 0, 12, 20, 10, 0)

        assertEquals(
            GarminWorkoutParseIssue.SetIntervals,
            parseGarminWorkoutCommandResult(
                validCommand() + ("setIntervals" to emptyList<Any>()),
                nowMillis
            ).issue
        )
        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsShape,
            parseGarminWorkoutCommandResult(
                validCommand() + ("setIntervals" to listOf(validInterval.dropLast(1))),
                nowMillis
            ).issue
        )
        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsOffsets,
            parseGarminWorkoutCommandResult(
                validCommand() + (
                    "setIntervals" to listOf(validInterval.toMutableList().also {
                        it[0] = 43
                        it[1] = 42
                    })
                    ),
                nowMillis
            ).issue
        )
        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsGymCalories,
            parseGarminWorkoutCommandResult(
                validCommand() + (
                    "setIntervals" to listOf(validInterval.toMutableList().also { it[2] = Double.NaN })
                    ),
                nowMillis
            ).issue
        )
        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsGarminCalories,
            parseGarminWorkoutCommandResult(
                validCommand() + (
                    "setIntervals" to listOf(validInterval.toMutableList().also { it[3] = 1.5 })
                    ),
                nowMillis
            ).issue
        )
        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsHeartRateZones,
            parseGarminWorkoutCommandResult(
                validCommand() + (
                    "setIntervals" to listOf(validInterval.toMutableList().also { it[4] = 1 })
                    ),
                nowMillis
            ).issue
        )
        val extraSetCommand = validCommand() + mapOf(
            "sets" to listOf(validSet(), validSet(), validSet()),
            "plannedSetCount" to 3,
            "plannedTargetSetCount" to 2,
            "completedPlannedSetCount" to 0
        )
        val extraSetParsed = parseGarminWorkoutCommand(extraSetCommand, nowMillis)
        assertNotNull(extraSetParsed)
        assertEquals(0, extraSetParsed?.completedPlannedSetCount)
        assertTrue(
            garminWorkoutNote(checkNotNull(extraSetParsed), AppLanguage.EN)
                .contains("Completed 0/2 sets")
        )

        listOf(
            validCommand() + ("completedPlannedSetCount" to 0),
            validCommand() + mapOf(
                "plannedSetCount" to 1,
                "plannedTargetSetCount" to 1
            ),
            validCommand() + mapOf(
                "plannedSetCount" to 1,
                "plannedTargetSetCount" to 1,
                "completedPlannedSetCount" to 2
            ),
            validCommand() + mapOf(
                "plannedSetCount" to 3,
                "plannedTargetSetCount" to 3,
                "completedPlannedSetCount" to 2
            ),
            validCommand() + mapOf(
                "plannedSetCount" to 3,
                "plannedTargetSetCount" to 3,
                "completedPlannedSetCount" to -1
            ),
            validCommand() + mapOf(
                "plannedSetCount" to 3,
                "plannedTargetSetCount" to 3,
                "completedPlannedSetCount" to 1.5
            )
        ).forEach { command ->
            assertEquals(
                GarminWorkoutParseIssue.CompletedPlannedSetCount,
                parseGarminWorkoutCommandResult(command, nowMillis).issue
            )
        }
    }

    @Test
    fun workoutParserEnforcesStructuredIntervalTimelineAndAggregateTotals() {
        val nowMillis = 1_800_000_000_000L
        val sets = listOf(validSet(), validSet())
        val first = listOf<Any?>(0, 42, 5.0, 5, 0, 0, 12, 20, 10, 0)
        val second = listOf<Any?>(42, 50, 5.0, 5, 0, 0, 0, 8, 0, 0)
        val baseline = validCommand() + mapOf(
            "sets" to sets,
            "setIntervals" to listOf(first, second),
            "durationSeconds" to 50,
            "gymCalories" to 9.91,
            "garminCalories" to 10
        )

        assertNotNull(parseGarminWorkoutCommand(baseline, nowMillis))
        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsOffsets,
            parseGarminWorkoutCommandResult(baseline - "durationSeconds", nowMillis).issue
        )

        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsOffsets,
            parseGarminWorkoutCommandResult(
                baseline + (
                    "setIntervals" to listOf(
                        first,
                        second.toMutableList().also {
                            it[0] = 41
                        }
                    )
                    ),
                nowMillis
            ).issue
        )
        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsOffsets,
            parseGarminWorkoutCommandResult(
                baseline + (
                    "setIntervals" to listOf(
                        first,
                        second.toMutableList().also { it[1] = 51 }
                    )
                    ),
                nowMillis
            ).issue
        )
        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsGymCalories,
            parseGarminWorkoutCommandResult(
                baseline + ("gymCalories" to 9.89),
                nowMillis
            ).issue
        )
        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsGymCalories,
            parseGarminWorkoutCommandResult(baseline - "gymCalories", nowMillis).issue
        )
        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsGarminCalories,
            parseGarminWorkoutCommandResult(
                baseline + ("garminCalories" to 9),
                nowMillis
            ).issue
        )
        assertEquals(
            GarminWorkoutParseIssue.SetIntervalsGarminCalories,
            parseGarminWorkoutCommandResult(baseline - "garminCalories", nowMillis).issue
        )

        val missingPerIntervalGarminCalories = baseline + (
            "setIntervals" to listOf(
                first,
                second.toMutableList().also { it[3] = null }
            )
            ) + ("garminCalories" to 9)
        assertNotNull(parseGarminWorkoutCommand(missingPerIntervalGarminCalories, nowMillis))
    }

    @Test
    fun maximumSetDiagnosticsReserveSpaceForTheOmittedRowMarker() {
        val nowMillis = 1_800_000_000_000L
        val set = validSet() + mapOf("weight" to 1_000_000.0, "reps" to 10_000)
        val intervals = List(MAX_GARMIN_WORKOUT_SETS) { index ->
            listOf(
                index * 7_200,
                (index + 1) * 7_200,
                1_666.66,
                1_666,
                1_200,
                1_200,
                1_200,
                1_200,
                1_200,
                1_200
            )
        }
        val metrics = listOf(7_200, 86_400, 240, 240, 240, 240, 100)
        val parsed = parseGarminWorkoutCommand(
            validCommand() + mapOf(
                "sets" to List(MAX_GARMIN_WORKOUT_SETS) { set },
                "setMetrics" to List(MAX_GARMIN_WORKOUT_SETS) { metrics },
                "setIntervals" to intervals,
                "durationSeconds" to MAX_GARMIN_DURATION_SECONDS,
                "gymCalories" to MAX_GARMIN_CALORIES,
                "garminCalories" to MAX_GARMIN_CALORIES.toInt(),
                "plannedSetCount" to MAX_GARMIN_WORKOUT_SETS
            ),
            nowMillis
        )

        assertNotNull(parsed)
        val note = garminWorkoutNote(checkNotNull(parsed), AppLanguage.EN)
        assertTrue(WorkoutDataLimits.isValidNote(note))
        assertTrue(note.codePointCount(0, note.length) <= WorkoutDataLimits.MAX_NOTE_LENGTH)
        assertTrue(note.contains("S1 "))
        val omitted = checkNotNull(
            Regex("(?:^| · )S\\+([0-9]{1,2})$").find(note)
        ).groupValues[1].toInt()
        val included = Regex("(?:^| · )S[1-9][0-9]?\\s").findAll(note).count()
        assertEquals(MAX_GARMIN_WORKOUT_SETS, included + omitted)
        assertEquals(MAX_GARMIN_WORKOUT_SETS, parsed.sets.size)
    }

    @Test
    fun newDiagnosticFieldsDoNotBreakAckLostRetriesAcceptedByOlderAndroid() {
        val nowMillis = 1_800_000_000_000L
        val legacyParsed = checkNotNull(parseGarminWorkoutCommand(validCommand(), nowMillis))
        val upgradedParsed = checkNotNull(
            parseGarminWorkoutCommand(
                validCommand() + mapOf(
                    "setIntervals" to listOf(
                        listOf(0, 42, 5.5, 6, 0, 0, 12, 20, 10, 0)
                    ),
                    "plannedSetCount" to 3,
                    "plannedTargetSetCount" to 3,
                    "completedPlannedSetCount" to 1
                ),
                nowMillis
            )
        )

        assertEquals(
            canonicalGarminWorkoutPayloadDigest(legacyParsed),
            canonicalGarminWorkoutPayloadDigest(upgradedParsed)
        )
    }

    @Test
    fun workoutParserRejectsMissingIdsUnboundedCollectionsAndUnsafeNumbers() {
        val nowMillis = 1_800_000_000_000L
        val baseline = validCommand().toMutableMap()

        assertNull(parseGarminWorkoutCommand(baseline - "requestId", nowMillis))
        assertNull(
            parseGarminWorkoutCommand(
                baseline + ("requestId" to "short"),
                nowMillis
            )
        )
        assertNull(
            parseGarminWorkoutCommand(
                baseline + ("sets" to List(MAX_GARMIN_WORKOUT_SETS + 1) { validSet() }),
                nowMillis
            )
        )
        assertNull(
            parseGarminWorkoutCommand(
                baseline + ("sets" to listOf(validSet() + ("weight" to Double.NaN))),
                nowMillis
            )
        )
        assertNull(
            parseGarminWorkoutCommand(
                baseline + ("avgHeartRate" to 180) + ("maxHeartRate" to 120),
                nowMillis
            )
        )
        assertNull(
            parseGarminWorkoutCommand(
                baseline + ("sets" to listOf(validSet() + ("reps" to 8.5))),
                nowMillis
            )
        )
        assertNull(
            parseGarminWorkoutCommand(
                baseline + ("gymCalories" to Double.POSITIVE_INFINITY),
                nowMillis
            )
        )
        assertNull(
            parseGarminWorkoutCommand(
                baseline + ("startedAtSeconds" to nowMillis / 1_000L + MAX_GARMIN_FUTURE_SKEW_SECONDS + 1),
                nowMillis
            )
        )
        assertNull(
            parseGarminWorkoutCommand(
                baseline + (
                    "sets" to listOf(
                        validSet() + ("exerciseName" to "x".repeat(161))
                    )
                ),
                nowMillis
            )
        )
    }

    @Test
    fun outboundPlanRejectsValuesTheWatchCannotSafelyPersist() {
        val valid = NamedWorkoutSetDraft("Squat", 100.0, 5)

        assertEquals(listOf(valid), validatedGarminPlanOrNull(listOf(valid)))
        assertNull(
            validatedGarminPlanOrNull(
                List(MAX_GARMIN_WORKOUT_SETS + 1) { valid }
            )
        )
        assertNull(validatedGarminPlanOrNull(listOf(valid.copy(weight = Double.NaN))))
        assertNull(validatedGarminPlanOrNull(listOf(valid.copy(reps = 0))))
        assertNull(
            validatedGarminPlanOrNull(
                listOf(valid.copy(exerciseName = "\u0301".repeat(10_000)))
            )
        )
        val maximumByteNames = List(20) { index ->
            "😀".repeat(157) + index.toString().padStart(3, '0')
        }
        assertNull(
            validatedGarminPlanOrNull(
                maximumByteNames.map { name -> valid.copy(exerciseName = name) }
            )
        )
    }

    @Test
    fun exerciseCatalogBoundsLegacyUnicodeBeforeWatchPayloadConstruction() {
        val oversizedRaw = "\u0301".repeat(10_000)

        assertNull(
            validatedGarminExerciseCatalog(
                exercises = listOf(oversizedRaw, " Squat "),
                maximumCount = 60
            )
        )
        assertEquals(
            listOf("Squat"),
            validatedGarminExerciseCatalog(
                exercises = listOf(" Squat ", "Squat"),
                maximumCount = 60
            )
        )
        assertNull(
            validatedGarminExerciseCatalog(
                exercises = List(61) { index -> "Exercise $index" },
                maximumCount = 60
            )
        )
        assertNull(
            validatedGarminExerciseCatalog(
                exercises = listOf("Squat", "   "),
                maximumCount = 60
            )
        )
        val maximumByteNames = List(20) { index ->
            "😀".repeat(157) + index.toString().padStart(3, '0')
        }
        assertNull(
            validatedGarminExerciseCatalog(
                exercises = maximumByteNames,
                maximumCount = 60
            )
        )
    }

    @Test
    fun firstSecurePairingRequiresExactlyOneConnectedTransportDevice() {
        assertNull(selectGarminDeviceTarget(emptyList(), listOf("11"), trustedBinding = null))
        assertNull(selectGarminDeviceTarget(listOf("11", "22"), emptyList(), trustedBinding = null))
        assertEquals(
            GarminDeviceTarget("11", GarminDeviceTargetSource.Connected),
            selectGarminDeviceTarget(listOf("11"), listOf("22"), trustedBinding = null)
        )
        assertEquals(
            GarminDeviceTarget("11", GarminDeviceTargetSource.Connected),
            selectGarminDeviceTarget(listOf("11", "11"), emptyList(), trustedBinding = null)
        )
        assertNull(
            selectGarminDeviceTarget(listOf("not-a-device"), emptyList(), trustedBinding = null)
        )
    }

    @Test
    fun trustedDeviceSelectionFiltersEveryOtherConnectedOrKnownWatch() {
        assertEquals(
            GarminDeviceTarget("22", GarminDeviceTargetSource.Connected),
            selectGarminDeviceTarget(
                connectedBindings = listOf("11", "22", "33"),
                knownBindings = listOf("44"),
                trustedBinding = "22"
            )
        )
        assertEquals(
            GarminDeviceTarget("22", GarminDeviceTargetSource.KnownPinned),
            selectGarminDeviceTarget(
                connectedBindings = listOf("11", "33"),
                knownBindings = listOf("22", "44"),
                trustedBinding = "22"
            )
        )
        assertNull(
            selectGarminDeviceTarget(
                connectedBindings = listOf("11"),
                knownBindings = listOf("33"),
                trustedBinding = "22"
            )
        )
    }

    @Test
    fun globalWatchPinMigratesOneLegacyDeviceAndRejectsConflicts() {
        assertEquals(
            GarminTrustedDeviceResolution(GarminTrustedDeviceState.Unpaired),
            resolveGlobalGarminDeviceBinding(null, emptyList())
        )
        assertEquals(
            GarminTrustedDeviceResolution(GarminTrustedDeviceState.Pinned, "22"),
            resolveGlobalGarminDeviceBinding(null, listOf("22", "22"))
        )
        assertEquals(
            GarminTrustedDeviceResolution(GarminTrustedDeviceState.Pinned, "22"),
            resolveGlobalGarminDeviceBinding("22", listOf("22"))
        )
        assertEquals(
            GarminTrustedDeviceState.Conflict,
            resolveGlobalGarminDeviceBinding("22", listOf("33")).state
        )
        assertEquals(
            GarminTrustedDeviceState.Conflict,
            resolveGlobalGarminDeviceBinding(null, listOf("not-a-device")).state
        )
    }

    @Test
    fun authTransitionEpochSeparatesAccountsLoginsAndSignedOutState() {
        val accountA = "a".repeat(64)
        val accountB = "b".repeat(64)
        val aGenerationOne = checkNotNull(
            garminAuthTransitionTarget(accountA, "session-generation-1")
        )
        val aTokenRefresh = checkNotNull(
            garminAuthTransitionTarget(accountA, "session-generation-1")
        )
        val aGenerationTwo = checkNotNull(
            garminAuthTransitionTarget(accountA, "session-generation-2")
        )
        val bGeneration = checkNotNull(
            garminAuthTransitionTarget(accountB, "session-generation-1")
        )
        val signedOut = checkNotNull(garminAuthTransitionTarget(null, null))

        assertEquals(aGenerationOne, aTokenRefresh)
        assertNotEquals(aGenerationOne.key, aGenerationTwo.key)
        assertNotEquals(aGenerationOne.key, bGeneration.key)
        assertNotEquals(aGenerationOne.accountBinding, signedOut.accountBinding)
        assertTrue(isValidGarminAccountBinding(signedOut.key))
        assertTrue(isValidGarminAccountBinding(signedOut.accountBinding))
        assertNull(garminAuthTransitionTarget(null, "unexpected-generation"))
    }

    @Test
    fun accountTransitionRequiresResetOnlyAfterPhysicalPairing() {
        val target = checkNotNull(
            garminAuthTransitionTarget("a".repeat(64), "generation")
        )

        assertFalse(
            garminAuthTransitionNeedsReset(
                target.key,
                lastReadyKey = null,
                trustedDeviceState = GarminTrustedDeviceState.Unpaired
            )
        )
        assertTrue(
            garminAuthTransitionNeedsReset(
                target.key,
                lastReadyKey = null,
                trustedDeviceState = GarminTrustedDeviceState.Pinned
            )
        )
        assertFalse(
            garminAuthTransitionNeedsReset(
                target.key,
                lastReadyKey = target.key,
                trustedDeviceState = GarminTrustedDeviceState.Pinned
            )
        )
        assertTrue(
            garminAuthTransitionNeedsReset(
                target.key,
                lastReadyKey = target.key,
                trustedDeviceState = GarminTrustedDeviceState.Conflict
            )
        )
    }

    @Test
    fun canonicalWorkoutDigestIsStableAndDetectsChangedReplayPayload() {
        val nowMillis = 1_800_000_000_000L
        val command = checkNotNull(parseGarminWorkoutCommand(validCommand(), nowMillis))
        val sameCommand = checkNotNull(parseGarminWorkoutCommand(validCommand(), nowMillis))
        val changedCommand = command.copy(
            sets = command.sets.map { it.copy(reps = it.reps + 1) }
        )
        val changedEndingZone = command.copy(endingHeartRateZone = 4)

        val digest = canonicalGarminWorkoutPayloadDigest(command)

        assertEquals(digest, canonicalGarminWorkoutPayloadDigest(sameCommand))
        assertNotEquals(digest, canonicalGarminWorkoutPayloadDigest(changedCommand))
        assertNotEquals(digest, canonicalGarminWorkoutPayloadDigest(changedEndingZone))
        assertTrue(digest.matches(Regex("^[0-9a-f]{64}$")))
    }

    @Test
    fun cacheAndReplayScopesDoNotExposeOrMixBindings() {
        val first = garminStorageKey("cached_plan", "a".repeat(64), "device-one")
        val second = garminStorageKey("cached_plan", "b".repeat(64), "device-one")
        val third = garminStorageKey("cached_plan", "a".repeat(64), "device-two")

        assertNotEquals(first, second)
        assertNotEquals(first, third)
        assertFalse(first.contains("device-one"))
        assertFalse(first.contains("a".repeat(64)))
    }

    private fun validCommand(): Map<Any?, Any?> = mapOf(
        "type" to "create_workout",
        "requestId" to "request-1234567890",
        "startedAtSeconds" to 1_700_000_000L,
        "durationSeconds" to 3_600L,
        "gymCalories" to 450.5,
        "garminCalories" to 430,
        "avgHeartRate" to 132,
        "maxHeartRate" to 168,
        "heartRateZone" to 3,
        "sets" to listOf(validSet())
    )

    private fun validSet(): Map<Any?, Any?> = mapOf(
        "exerciseName" to "Bench Press",
        "weight" to 82.5,
        "reps" to 8
    )
}
