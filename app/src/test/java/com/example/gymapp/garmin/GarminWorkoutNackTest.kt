package com.example.gymapp.garmin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GarminWorkoutNackTest {
    private val binding = GarminBinding(
        account = "a".repeat(64),
        device = "123456789",
        pairingGeneration = "b".repeat(64)
    )

    @Test
    fun nackEchoesBoundedPrintableRequestIdWithFixedReason() {
        val requestId = "workout-request-0001"
        val payload = garminNackPayload(
            mapOf("requestId" to requestId),
            GarminNackReason.GENERATION_MISMATCH
        )!!

        assertEquals(
            mapOf(
                "type" to "nack",
                "requestId" to requestId,
                "reason" to "generation_mismatch"
            ),
            payload
        )
    }

    @Test
    fun nackOmitsRequestIdThatIsMissingOversizedOrNotPrintable() {
        val badIds: List<Any?> = listOf(
            null,
            42,
            "",
            "x".repeat(MAX_GARMIN_REQUEST_ID_LENGTH + 1),
            "id-with-\nnewline",
            "id-with-é-non-ascii",
            "id-with-\u0000-nul"
        )
        for (bad in badIds) {
            val payload = garminNackPayload(
                mapOf("requestId" to bad),
                GarminNackReason.INVALID
            )!!
            assertFalse("requestId must be omitted for $bad", payload.containsKey("requestId"))
            assertEquals(setOf("type", "reason"), payload.keys)
        }
        assertEquals(
            "x".repeat(MAX_GARMIN_REQUEST_ID_LENGTH),
            garminNackPayload(
                mapOf("requestId" to "x".repeat(MAX_GARMIN_REQUEST_ID_LENGTH)),
                GarminNackReason.REJECTED
            )!!["requestId"]
        )
    }

    @Test
    fun nackRejectsReasonsOutsideTheFixedSet() {
        assertNull(garminNackPayload(emptyMap(), "free text from the watch"))
        assertNull(garminNackPayload(emptyMap(), ""))
        for (reason in GarminNackReason.all) {
            assertTrue(reason.matches(Regex("[a-z_]{1,32}")))
            assertEquals(reason, garminNackPayload(emptyMap(), reason)!!["reason"])
        }
        assertEquals(
            setOf(
                "generation_missing",
                "generation_mismatch",
                "binding_mismatch",
                "invalid",
                "rejected",
                "rate_limited",
                "reset_required"
            ),
            GarminNackReason.all
        )
    }

    @Test
    fun boundNackCarriesOnlyBindingFieldsAndNoWorkoutData() {
        val command = mapOf<Any?, Any?>(
            "type" to "create_workout",
            "requestId" to "workout-request-0001",
            "sets" to listOf("secret"),
            "note" to "private"
        )
        val bound = boundGarminPayload(
            garminNackPayload(command, GarminNackReason.RATE_LIMITED)!!,
            binding
        )

        assertEquals(
            setOf(
                "type", "requestId", "reason",
                "bindingVersion", "accountBinding", "deviceBinding", "pairingGeneration"
            ),
            bound.keys
        )
        assertEquals("nack", bound["type"])
        assertEquals("rate_limited", bound["reason"])
        assertEquals(binding.pairingGeneration, bound["pairingGeneration"])
        assertTrue(isWithinSmallNackBudget(bound))
    }

    @Test
    fun legacyFallbackGenerationNackOmitsGeneration() {
        val legacy = binding.copy(pairingGeneration = LEGACY_GARMIN_FALLBACK_GENERATION)
        val bound = boundGarminPayload(
            payload = garminNackPayload(emptyMap(), GarminNackReason.GENERATION_MISSING)!!,
            binding = legacy,
            includePairingGeneration = legacy.pairingGeneration != LEGACY_GARMIN_FALLBACK_GENERATION
        )
        assertFalse(bound.containsKey("pairingGeneration"))
    }

    private fun isWithinSmallNackBudget(payload: Map<String, Any>): Boolean =
        payload.entries.sumOf { (k, v) -> k.length + v.toString().length } < 512
}
