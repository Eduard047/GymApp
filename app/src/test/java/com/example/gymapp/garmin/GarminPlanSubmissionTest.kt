package com.example.gymapp.garmin

import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class GarminPlanSubmissionTest {
    private val account = "a".repeat(64)
    private val authTransition = "b".repeat(64)
    private val device = "123456789"
    private val generation = "c".repeat(64)
    private val zeroPlan = listOf(
        NamedWorkoutSetDraft("Bench Press", 0.0, 8),
        NamedWorkoutSetDraft("Bench Press", 20.0, 5)
    )

    @Test
    fun unchangedExactDraftReusesRequestIdRevisionAndZeroWeight() {
        val key = key()
        val first = prepareGarminPlanSubmission(
            key = key,
            encodedExisting = null,
            lastGlobalRevision = null,
            nowMillis = 1_800_000_000_000L,
            newRequestId = { "request-fixed-0001" }
        )
        assertNotNull(first)
        first!!
        assertFalse(first.reused)
        assertEquals(1_800_000_000_000L, first.envelope.revision)
        assertEquals("request-fixed-0001", first.envelope.requestId)

        val retried = prepareGarminPlanSubmission(
            key = key.copy(orderedPlan = zeroPlan.map { it.copy() }),
            encodedExisting = first.encodedEnvelope,
            lastGlobalRevision = first.envelope.revision,
            nowMillis = first.envelope.revision + 50_000L,
            newRequestId = { error("An unchanged retry must not allocate an ID") }
        )

        assertNotNull(retried)
        retried!!
        assertTrue(retried.reused)
        assertEquals(first.envelope, retried.envelope)
        assertEquals(first.encodedEnvelope, retried.encodedEnvelope)
        val firstPayload = materializeGarminPlanSubmissionPayload(key, first.envelope)
        val retriedPayload = materializeGarminPlanSubmissionPayload(key, retried.envelope)
        assertEquals(firstPayload, retriedPayload)
        assertEquals(listOf(0.0, 20.0), firstPayload?.get("planWeights"))
        assertEquals(listOf(8, 5), firstPayload?.get("planReps"))
        assertEquals(first.envelope.requestId, firstPayload?.get("requestId"))
        assertEquals(first.envelope.revision, firstPayload?.get("syncRevision"))
        assertFalse(firstPayload.orEmpty().containsKey("exercises"))
        assertEquals(
            garminPlanSubmissionFingerprint(key),
            garminPlanSubmissionFingerprint(key.copy(orderedPlan = zeroPlan))
        )
    }

    @Test
    fun orderedPlanMutationAndContextChangesRotateSubmission() {
        val original = prepareGarminPlanSubmission(
            key = key(),
            encodedExisting = null,
            lastGlobalRevision = null,
            nowMillis = 1_800_000_000_000L,
            newRequestId = { "request-original-1" }
        )!!

        val variants = listOf(
            key().copy(orderedPlan = zeroPlan.reversed()),
            key().copy(orderedPlan = zeroPlan.mapIndexed { index, set ->
                if (index == 1) set.copy(weight = 21.0) else set
            }),
            key().copy(accountBinding = "d".repeat(64)),
            key().copy(authTransitionKey = "e".repeat(64)),
            key().copy(deviceBinding = "987654321"),
            key().copy(pairingGeneration = "f".repeat(64)),
            key().copy(includePairingGeneration = false),
            key().copy(languageTag = "ru")
        )

        variants.forEachIndexed { index, changed ->
            val rotated = prepareGarminPlanSubmission(
                key = changed,
                encodedExisting = original.encodedEnvelope,
                lastGlobalRevision = original.envelope.revision,
                nowMillis = original.envelope.revision,
                newRequestId = { "request-rotated-$index" }
            )!!
            assertFalse("variant $index", rotated.reused)
            assertEquals(original.envelope.revision + 1L, rotated.envelope.revision)
            assertNotEquals(original.envelope.requestId, rotated.envelope.requestId)
            assertNotEquals(original.envelope.fingerprint, rotated.envelope.fingerprint)
        }
    }

    @Test
    fun staleGlobalRevisionAndMalformedEnvelopeFailNeutralByRotating() {
        val original = prepareGarminPlanSubmission(
            key = key(),
            encodedExisting = null,
            lastGlobalRevision = null,
            nowMillis = 1_800_000_000_000L,
            newRequestId = { "request-original-1" }
        )!!
        val globallyAdvanced = prepareGarminPlanSubmission(
            key = key(),
            encodedExisting = original.encodedEnvelope,
            lastGlobalRevision = original.envelope.revision + 7L,
            nowMillis = original.envelope.revision,
            newRequestId = { "request-after-fence" }
        )!!
        assertFalse(globallyAdvanced.reused)
        assertEquals(original.envelope.revision + 8L, globallyAdvanced.envelope.revision)

        val malformed = prepareGarminPlanSubmission(
            key = key(),
            encodedExisting = "{not-json",
            lastGlobalRevision = original.envelope.revision,
            nowMillis = original.envelope.revision,
            newRequestId = { "request-after-malformed" }
        )!!
        assertFalse(malformed.reused)
        assertEquals(original.envelope.revision + 1L, malformed.envelope.revision)
        assertNull(decodeGarminPlanSubmissionEnvelope("x".repeat(513)))
    }

    @Test
    fun invalidAccountDeviceNumbersAndPlanAreRejectedWithoutEnvelope() {
        assertNull(garminPlanSubmissionFingerprint(key().copy(accountBinding = "wrong")))
        assertNull(garminPlanSubmissionFingerprint(key().copy(deviceBinding = "watch")))
        assertNull(
            prepareGarminPlanSubmission(
                key = key().copy(orderedPlan = listOf(zeroPlan.first().copy(weight = -1.0))),
                encodedExisting = null,
                lastGlobalRevision = null,
                nowMillis = 1_800_000_000_000L,
                newRequestId = { "request-invalid-plan" }
            )
        )
        assertNull(
            prepareGarminPlanSubmission(
                key = key(),
                encodedExisting = null,
                lastGlobalRevision = null,
                nowMillis = 1_800_000_000_000L,
                newRequestId = { "short" }
            )
        )
        val valid = prepareGarminPlanSubmission(
            key = key(),
            encodedExisting = null,
            lastGlobalRevision = null,
            nowMillis = 1_800_000_000_000L,
            newRequestId = { "request-valid-0001" }
        )!!
        assertNull(
            materializeGarminPlanSubmissionPayload(
                key().copy(accountBinding = "d".repeat(64)),
                valid.envelope
            )
        )
    }

    @Test
    fun concurrentIdenticalSubmissionsCoalesceToOneTransportOperation() = runBlocking {
        val fingerprint = garminPlanRequestFingerprint(
            accountBinding = account,
            authTransitionKey = authTransition,
            trustedDeviceBinding = device,
            languageTag = "en",
            orderedPlan = zeroPlan
        )!!
        val coordinator = GarminPlanSubmissionCoalescer(this)
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val sends = AtomicInteger(0)
        val operation: suspend () -> Boolean = {
            sends.incrementAndGet()
            entered.complete(Unit)
            release.await()
            true
        }

        val first = async { coordinator.submit(fingerprint, operation) }
        entered.await()
        val second = async { coordinator.submit(fingerprint, operation) }
        yield()
        assertEquals(1, sends.get())
        release.complete(Unit)

        assertTrue(first.await())
        assertTrue(second.await())
        assertEquals(1, sends.get())
    }

    @Test
    fun differentDraftFingerprintsDoNotCoalesce() = runBlocking {
        val firstFingerprint = garminPlanRequestFingerprint(
            account,
            authTransition,
            device,
            "en",
            zeroPlan
        )!!
        val secondFingerprint = garminPlanRequestFingerprint(
            account,
            authTransition,
            device,
            "en",
            zeroPlan.reversed()
        )!!
        val coordinator = GarminPlanSubmissionCoalescer(this)
        val sends = AtomicInteger(0)

        val first = async {
            coordinator.submit(firstFingerprint) { sends.incrementAndGet(); true }
        }
        val second = async {
            coordinator.submit(secondFingerprint) { sends.incrementAndGet(); true }
        }

        assertTrue(first.await())
        assertTrue(second.await())
        assertEquals(2, sends.get())
    }

    @Test
    fun cancellingFirstWaiterDoesNotExposeRunningSubmissionForDuplicateSend() = runBlocking {
        val managerScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val coordinator = GarminPlanSubmissionCoalescer(managerScope)
            val fingerprint = requestFingerprint()
            val entered = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            val sends = AtomicInteger(0)
            val operation: suspend () -> Boolean = {
                sends.incrementAndGet()
                entered.complete(Unit)
                release.await()
                true
            }
            val firstWaiter = async { coordinator.submit(fingerprint, operation) }
            entered.await()
            firstWaiter.cancelAndJoin()

            val replacementWaiter = async { coordinator.submit(fingerprint, operation) }
            yield()
            assertEquals(1, sends.get())
            release.complete(Unit)
            assertTrue(replacementWaiter.await())
            assertEquals(1, sends.get())
        } finally {
            managerScope.cancel()
        }
    }

    @Test
    fun cancellingJoinerDoesNotCancelSharedSubmissionOrStartAnother() = runBlocking {
        val managerScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val coordinator = GarminPlanSubmissionCoalescer(managerScope)
            val fingerprint = requestFingerprint()
            val entered = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            val sends = AtomicInteger(0)
            val operation: suspend () -> Boolean = {
                sends.incrementAndGet()
                entered.complete(Unit)
                release.await()
                true
            }
            val firstWaiter = async { coordinator.submit(fingerprint, operation) }
            entered.await()
            val cancelledJoiner = async { coordinator.submit(fingerprint, operation) }
            yield()
            cancelledJoiner.cancelAndJoin()
            val finalJoiner = async { coordinator.submit(fingerprint, operation) }
            yield()

            assertEquals(1, sends.get())
            release.complete(Unit)
            assertTrue(firstWaiter.await())
            assertTrue(finalJoiner.await())
            assertEquals(1, sends.get())
        } finally {
            managerScope.cancel()
        }
    }

    private fun key() = GarminPlanSubmissionKey(
        accountBinding = account,
        authTransitionKey = authTransition,
        deviceBinding = device,
        pairingGeneration = generation,
        includePairingGeneration = true,
        languageTag = "en",
        orderedPlan = zeroPlan
    )

    private fun requestFingerprint(): String = garminPlanRequestFingerprint(
        accountBinding = account,
        authTransitionKey = authTransition,
        trustedDeviceBinding = device,
        languageTag = "en",
        orderedPlan = zeroPlan
    )!!
}
