package com.example.gymapp.wearsync

import com.example.gymapp.auth.AccountSession
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneWearProtocolTest {
    private val now = 1_750_000_000_000L
    private val ownerId = "a".repeat(64)
    private val operationId = "123e4567-e89b-42d3-a456-426614174000"

    @Test
    fun validCreateWorkoutUsesStrictBoundEnvelope() {
        val raw =
            """
            {
              "type":"create_workout",
              "protocolVersion":1,
              "operationId":"$operationId",
              "sentAt":$now,
              "ownerId":"$ownerId",
              "accountGeneration":7,
              "startedAt":$now,
              "note":"watch",
              "sets":[{"exerciseName":"Bench Press","weight":80.0,"reps":8}]
            }
            """.trimIndent()

        val result = PhoneWearProtocol.parse(
            PhoneWearPaths.CREATE_WORKOUT,
            raw.toByteArray(),
            now
        )

        assertTrue(result is PhoneWearParseResult.Valid)
        val valid = result as PhoneWearParseResult.Valid
        val command = valid.command as PhoneWearCommand.CreateWorkout
        assertEquals(ownerId, command.envelope.ownerId)
        assertEquals(7L, command.envelope.accountGeneration)
        assertEquals("Bench Press", command.sets.single().exerciseName)
        assertTrue(valid.canonicalPayloadDigest.matches(Regex("^[0-9a-f]{64}$")))
    }

    @Test
    fun mutationDigestIgnoresFreshSentAtButBindsEveryLogicalField() {
        fun create(sentAt: Long, reps: Int): PhoneWearParseResult.Valid {
            val raw =
                """
                {"sets":[{"reps":$reps,"weight":80.0,"exerciseName":"Bench Press"}],
                 "startedAt":$now,"accountGeneration":7,"ownerId":"$ownerId",
                 "sentAt":$sentAt,"operationId":"$operationId","protocolVersion":1,
                 "type":"create_workout"}
                """.trimIndent()
            return PhoneWearProtocol.parse(
                PhoneWearPaths.CREATE_WORKOUT,
                raw.toByteArray(),
                now
            ) as PhoneWearParseResult.Valid
        }

        val original = create(now - 1_000L, reps = 8)
        val lostAckRetry = create(now + 1_000L, reps = 8)
        val changedCommand = create(now + 2_000L, reps = 9)

        assertEquals(original.canonicalPayloadDigest, lostAckRetry.canonicalPayloadDigest)
        assertFalse(original.canonicalPayloadDigest == changedCommand.canonicalPayloadDigest)
    }

    @Test
    fun mutationDigestNormalizesSignedZero() {
        fun update(weight: String): String {
            val raw =
                """{"type":"update_set","protocolVersion":1,"operationId":"$operationId","sentAt":$now,"ownerId":"$ownerId","accountGeneration":7,"setId":4,"weight":$weight,"reps":8}"""
            return (
                PhoneWearProtocol.parse(PhoneWearPaths.UPDATE_SET, raw.toByteArray(), now) as
                    PhoneWearParseResult.Valid
            ).canonicalPayloadDigest
        }

        assertEquals(update("0.0"), update("-0.0"))
    }

    @Test
    fun rejectsUnexpectedDuplicateAndPathConfusedFields() {
        val extra = requestJson().dropLast(1) + ",\"admin\":true}"
        assertInvalid(PhoneWearPaths.REQUEST_FULL_SYNC, extra)

        val duplicate = requestJson().replace(
            "\"protocolVersion\":1",
            "\"protocolVersion\":1,\"protocolVersion\":1"
        )
        assertInvalid(PhoneWearPaths.REQUEST_FULL_SYNC, duplicate)

        assertInvalid(PhoneWearPaths.DELETE_SET, requestJson())
    }

    @Test
    fun rejectsMalformedUtf8DeepJsonAndStaleTimestamp() {
        val malformedUtf8 = byteArrayOf('{'.code.toByte(), '"'.code.toByte(), 0xC3.toByte(), '"'.code.toByte(), '}'.code.toByte())
        assertTrue(
            PhoneWearProtocol.parse(PhoneWearPaths.REQUEST_FULL_SYNC, malformedUtf8, now) is
                PhoneWearParseResult.Invalid
        )

        val deepValue = "[".repeat(33) + "0" + "]".repeat(33)
        assertInvalid(
            PhoneWearPaths.REQUEST_FULL_SYNC,
            requestJson().dropLast(1) + ",\"nested\":$deepValue}"
        )

        assertInvalid(
            PhoneWearPaths.REQUEST_FULL_SYNC,
            requestJson(sentAt = now - 8L * 24 * 60 * 60 * 1_000)
        )
    }

    @Test
    fun fullRequestMayBeUnboundButBindingMustBeComplete() {
        assertTrue(
            PhoneWearProtocol.parse(
                PhoneWearPaths.REQUEST_FULL_SYNC,
                requestJson().toByteArray(),
                now
            ) is PhoneWearParseResult.Valid
        )
        val bound = requestJson().dropLast(1) +
            ",\"ownerId\":\"$ownerId\",\"accountGeneration\":9}"
        assertTrue(
            PhoneWearProtocol.parse(
                PhoneWearPaths.REQUEST_FULL_SYNC,
                bound.toByteArray(),
                now
            ) is PhoneWearParseResult.Valid
        )
        assertInvalid(
            PhoneWearPaths.REQUEST_FULL_SYNC,
            requestJson().dropLast(1) + ",\"ownerId\":\"$ownerId\"}"
        )
    }

    @Test
    fun boundedFullSyncNeverTruncatesInvalidSessionFields() {
        val binding = PhoneWearAccountBinding(ownerId, 3L, signedOut = false)
        val valid = PhoneWearOutboundSession(
            id = 1L,
            startedAt = now,
            note = null,
            sets = listOf(
                PhoneWearOutboundSet(11L, 1L, "Bench Press", 80.0, 8, 0)
            )
        )
        val invalidName = PhoneWearOutboundSession(
            id = 2L,
            startedAt = now,
            note = null,
            sets = listOf(
                PhoneWearOutboundSet(22L, 2L, "x".repeat(121), 20.0, 10, 0)
            )
        )

        val payload = PhoneWearProtocol.buildBoundedFullSync(
            binding = binding,
            revision = 1L,
            sessions = listOf(valid, invalidName),
            exerciseCatalog = List(1_500) { "Exercise $it" },
            now = now,
            messageId = operationId
        )
        val root = JSONObject(payload.toString(Charsets.UTF_8))

        assertTrue(payload.size <= PhoneWearPaths.MAX_MESSAGE_BYTES)
        assertEquals(1, root.getJSONArray("sessions").length())
        assertEquals(1L, root.getJSONArray("sessions").getJSONObject(0).getLong("id"))
        assertTrue(root.getJSONArray("exerciseCatalog").length() <= PhoneWearPaths.MAX_EXERCISE_CATALOG)
        assertEquals(
            setOf(
                "protocolVersion", "ownerId", "accountGeneration", "revision",
                "messageId", "sentAt", "sessions", "exerciseCatalog"
            ),
            root.keys().asSequence().toSet()
        )
    }

    @Test
    fun ackContainsOnlyCurrentBindingAndExactStatus() {
        val payload = PhoneWearProtocol.buildMutationAck(
            binding = PhoneWearAccountBinding(ownerId, 12L, signedOut = false),
            operationId = operationId,
            accepted = false,
            now = now
        )
        val root = JSONObject(payload.toString(Charsets.UTF_8))

        assertEquals(ownerId, root.getString("ownerId"))
        assertEquals(12L, root.getLong("accountGeneration"))
        assertEquals("rejected", root.getString("status"))
        assertFalse(root.has("messageId"))
        assertEquals(
            setOf("protocolVersion", "ownerId", "accountGeneration", "operationId", "status", "sentAt"),
            root.keys().asSequence().toSet()
        )
    }

    @Test
    fun accountHistoryIsNotExposedToWatchPinnedForAnotherOwner() {
        val session = AccountSession.Local("Second account")
        val secondBinding = PhoneWearAccountBinding("b".repeat(64), 3L, signedOut = false)
        val firstAccountWatch = PhoneWearTrustedSource("watch-a", "a".repeat(64))

        assertFalse(
            mayExposePhoneWearAccountData(
                session = session,
                binding = secondBinding,
                trustedSource = firstAccountWatch,
                targetNodeId = "watch-a"
            )
        )
        assertTrue(
            mayExposePhoneWearAccountData(
                session = session,
                binding = secondBinding,
                trustedSource = firstAccountWatch.copy(ownerId = secondBinding.ownerId),
                targetNodeId = "watch-a"
            )
        )
    }

    private fun requestJson(sentAt: Long = now): String {
        return """{"type":"request_full_sync","protocolVersion":1,"operationId":"$operationId","sentAt":$sentAt}"""
    }

    private fun assertInvalid(path: String, raw: String) {
        assertTrue(
            PhoneWearProtocol.parse(path, raw.toByteArray(), now) is PhoneWearParseResult.Invalid
        )
    }
}
