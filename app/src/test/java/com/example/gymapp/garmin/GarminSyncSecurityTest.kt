package com.example.gymapp.garmin

import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GarminSyncSecurityTest {
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
    }

    @Test
    fun workoutParserAcceptsBoundedSetStatisticsAndRejectsInconsistentMetrics() {
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
        assertNull(
            parseGarminWorkoutCommand(
                validCommand() + ("setMetrics" to listOf(metrics.toMutableList().also { it[3] = 100 })),
                nowMillis
            )
        )
        assertNull(
            parseGarminWorkoutCommand(
                validCommand() + ("setMetrics" to listOf(metrics.dropLast(1))),
                nowMillis
            )
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
