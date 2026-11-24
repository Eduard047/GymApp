package com.example.gymapp.wearsync

import com.example.gymapp.auth.AccountSession
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.util.AppLanguage
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
        // An unknown key is ignored (it grants nothing), not a reason to drop the message.
        val extra = requestJson().dropLast(1) + ",\"admin\":true}"
        val parsedExtra = PhoneWearProtocol.parse(PhoneWearPaths.REQUEST_FULL_SYNC, extra.toByteArray(), now)
        assertTrue(parsedExtra is PhoneWearParseResult.Valid)
        assertEquals(
            (PhoneWearProtocol.parse(PhoneWearPaths.REQUEST_FULL_SYNC, requestJson().toByteArray(), now)
                as PhoneWearParseResult.Valid).command,
            (parsedExtra as PhoneWearParseResult.Valid).command
        )

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
        val binding = PhoneWearAccountBinding(ownerId, 3L, signedOut = false, authorityEpoch = TEST_EPOCH)
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
                "protocolVersion", "ownerId", "accountGeneration", "authorityEpoch", "revision",
                "messageId", "sentAt", "sessions", "exerciseCatalog"
            ),
            root.keys().asSequence().toSet()
        )
    }

    @Test
    fun ackContainsOnlyCurrentBindingAndExactStatus() {
        val payload = PhoneWearProtocol.buildMutationAck(
            binding = PhoneWearAccountBinding(ownerId, 12L, signedOut = false, authorityEpoch = TEST_EPOCH),
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
            setOf("protocolVersion", "ownerId", "accountGeneration", "authorityEpoch", "operationId", "status", "sentAt"),
            root.keys().asSequence().toSet()
        )
    }

    @Test
    fun accountHistoryFollowsThePinnedNodeAndTheActiveAccount() {
        val session = AccountSession.Local("Second account")
        val secondBinding = PhoneWearAccountBinding("b".repeat(64), 3L, signedOut = false, authorityEpoch = TEST_EPOCH)
        val watch = PhoneWearTrustedSource("watch-a", "a".repeat(64))

        assertTrue(mayExposePhoneWearAccountData(session, secondBinding, watch, "watch-a"))
        assertFalse(mayExposePhoneWearAccountData(session, secondBinding, watch, "watch-b"))
        assertFalse(mayExposePhoneWearAccountData(null, secondBinding, watch, "watch-a"))
        assertFalse(mayExposePhoneWearAccountData(session, secondBinding, null, "watch-a"))
    }

    @Test
    fun createWorkoutDurationIsOptionalAndBounded() {
        fun json(extra: String) =
            """{"type":"create_workout","protocolVersion":1,"operationId":"$operationId","sentAt":$now,"ownerId":"$ownerId","accountGeneration":7,"startedAt":$now$extra,"sets":[{"exerciseName":"Squat","weight":100.0,"reps":5}]}"""
        fun parse(raw: String) = PhoneWearProtocol.parse(PhoneWearPaths.CREATE_WORKOUT, raw.toByteArray(), now)

        val without = parse(json("")) as PhoneWearParseResult.Valid
        assertEquals(null, (without.command as PhoneWearCommand.CreateWorkout).durationSeconds)
        val with = parse(json(",\"durationSeconds\":1800")) as PhoneWearParseResult.Valid
        assertEquals(1_800L, (with.command as PhoneWearCommand.CreateWorkout).durationSeconds)
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json(",\"durationSeconds\":86401"))
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json(",\"durationSeconds\":-1"))
    }

    @Test
    fun createWorkoutHeartRateIsOptionalBoundedAndOrdered() {
        fun json(extra: String) =
            """{"type":"create_workout","protocolVersion":1,"operationId":"$operationId","sentAt":$now,"ownerId":"$ownerId","accountGeneration":7,"startedAt":$now$extra,"sets":[{"exerciseName":"Squat","weight":100.0,"reps":5}]}"""
        fun parse(raw: String) = PhoneWearProtocol.parse(PhoneWearPaths.CREATE_WORKOUT, raw.toByteArray(), now)

        val old = parse(json("")) as PhoneWearParseResult.Valid
        val oldCommand = old.command as PhoneWearCommand.CreateWorkout
        assertEquals(null, oldCommand.averageHeartRate)
        assertEquals(null, oldCommand.maxHeartRate)

        val withHr = parse(json(",\"avgHeartRate\":128,\"maxHeartRate\":171")) as PhoneWearParseResult.Valid
        val command = withHr.command as PhoneWearCommand.CreateWorkout
        assertEquals(128, command.averageHeartRate)
        assertEquals(171, command.maxHeartRate)
        // Present values bind the digest; absent ones leave an old build's digest untouched.
        assertFalse(old.canonicalPayloadDigest == withHr.canonicalPayloadDigest)
        assertEquals(old.canonicalPayloadDigest, (parse(json("")) as PhoneWearParseResult.Valid).canonicalPayloadDigest)

        assertEquals(25, ((parse(json(",\"avgHeartRate\":25,\"maxHeartRate\":240")) as PhoneWearParseResult.Valid)
            .command as PhoneWearCommand.CreateWorkout).averageHeartRate)
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json(",\"avgHeartRate\":24,\"maxHeartRate\":150"))
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json(",\"avgHeartRate\":120,\"maxHeartRate\":241"))
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json(",\"avgHeartRate\":150,\"maxHeartRate\":149"))
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json(",\"avgHeartRate\":130.5,\"maxHeartRate\":160"))
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json(",\"avgHeartRate\":\"130\",\"maxHeartRate\":160"))
    }

    @Test
    fun wearWorkoutNoteCarriesHeartRateLikeGarminAndStaysBounded() {
        assertEquals(null, wearWorkoutNote(null, null, null, AppLanguage.EN))
        assertEquals("kept", wearWorkoutNote("kept", null, null, AppLanguage.EN))
        assertEquals(
            "Wear OS · Avg HR 128 · Max HR 171",
            wearWorkoutNote(null, 128, 171, AppLanguage.EN)
        )
        assertEquals(
            "Wear OS · Средний пульс 128 · Макс. пульс 171",
            wearWorkoutNote(null, 128, 171, AppLanguage.RU)
        )
        assertEquals(
            "Wear OS · Середній пульс 128 · Макс. пульс 171",
            wearWorkoutNote(null, 128, 171, AppLanguage.UK)
        )
        assertEquals(
            "Push day · Wear OS · Avg HR 90 · Max HR 120",
            wearWorkoutNote("Push day", 90, 120, AppLanguage.EN)
        )
        // A watch note that leaves no room for the summary is never truncated or dropped.
        val huge = "я".repeat(510)
        assertEquals(huge, wearWorkoutNote(huge, 128, 171, AppLanguage.EN))
        val note = wearWorkoutNote(null, 128, 171, AppLanguage.RU)!!
        assertTrue(note.codePointCount(0, note.length) <= 512 && note.toByteArray().size <= 2048)
    }

    @Test
    fun unknownOptionalKeysAreIgnoredButBoundedAndNeverChangeTheDigest() {
        fun json(extra: String, setExtra: String = "") =
            """{"type":"create_workout","protocolVersion":1,"operationId":"$operationId","sentAt":$now,"ownerId":"$ownerId","accountGeneration":7,"startedAt":$now$extra,"sets":[{"exerciseName":"Squat","weight":100.0,"reps":5$setExtra}]}"""
        fun parse(raw: String) = PhoneWearProtocol.parse(PhoneWearPaths.CREATE_WORKOUT, raw.toByteArray(), now)

        val plain = parse(json("")) as PhoneWearParseResult.Valid
        val withUnknown = parse(
            json(",\"activeCalories\":321,\"future\":{\"a\":[1,2]}", setExtra = ",\"rpe\":8")
        ) as PhoneWearParseResult.Valid
        // The workout is applied exactly as without the unknown keys, under the same digest, so a
        // retry from an older or newer watch build is still recognised as the same operation.
        assertEquals(plain.command, withUnknown.command)
        assertEquals(plain.canonicalPayloadDigest, withUnknown.canonicalPayloadDigest)

        // The payload is still untrusted: required keys, known value types and bounds hold.
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json("").replace("\"startedAt\":$now,", ""))
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json(",\"durationSeconds\":\"60\""))
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json("", setExtra = ",\"reps\":6"))
        val tooManyKeys = (1..40).joinToString("") { ",\"k$it\":1" }
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json(tooManyKeys))
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json("", setExtra = tooManyKeys))
        assertInvalid(PhoneWearPaths.CREATE_WORKOUT, json(",\"${"k".repeat(65)}\":1"))
        // An unknown key cannot smuggle another owner in: the claim is still the envelope's.
        val claimed = parse(json(",\"owner\":\"${"b".repeat(64)}\"")) as PhoneWearParseResult.Valid
        assertEquals(ownerId, claimed.command.envelope.ownerId)
    }

    @Test
    fun linkIntentIsAnExplicitBooleanOfTheFullSyncRequest() {
        fun parse(raw: String) = PhoneWearProtocol.parse(PhoneWearPaths.REQUEST_FULL_SYNC, raw.toByteArray(), now)
        val plain = (parse(requestJson()) as PhoneWearParseResult.Valid).command as PhoneWearCommand.RequestFull
        assertFalse(plain.linkIntent)
        val link = (parse(requestJson().dropLast(1) + ",\"link\":true}") as PhoneWearParseResult.Valid)
            .command as PhoneWearCommand.RequestFull
        assertTrue(link.linkIntent)
        assertInvalid(PhoneWearPaths.REQUEST_FULL_SYNC, requestJson().dropLast(1) + ",\"link\":\"yes\"}")
        assertInvalid(PhoneWearPaths.REQUEST_FULL_SYNC, requestJson().dropLast(1) + ",\"link\":1}")
    }

    @Test
    fun bindingStateCarriesEpochAndGenerationButNeverAnOwner() {
        val signedOut = PhoneWearAccountBinding("c".repeat(64), 9L, signedOut = true, authorityEpoch = TEST_EPOCH)
        val keys = setOf("protocolVersion", "state", "authorityEpoch", "accountGeneration", "messageId", "sentAt")
        val unbound = org.json.JSONObject(
            String(PhoneWearProtocol.buildBindingState(signedOut, unlinked = false, now = now, messageId = operationId))
        )
        assertEquals(keys, unbound.keys().asSequence().toSet())
        assertEquals("unbound", unbound.getString("state"))
        assertEquals(TEST_EPOCH, unbound.getString("authorityEpoch"))
        assertEquals(9L, unbound.getLong("accountGeneration"))
        val unlinked = org.json.JSONObject(
            String(PhoneWearProtocol.buildBindingState(signedOut, unlinked = true, now = now, messageId = operationId))
        )
        assertEquals(keys, unlinked.keys().asSequence().toSet())
        assertEquals("unlinked", unlinked.getString("state"))
        // The deletion reason is added only when asked, and only to an unlink.
        val deleted = org.json.JSONObject(
            String(
                PhoneWearProtocol.buildBindingState(
                    signedOut, unlinked = true, now = now, messageId = operationId, accountDeleted = true
                )
            )
        )
        assertEquals(keys + "reason", deleted.keys().asSequence().toSet())
        assertEquals("unlinked", deleted.getString("state"))
        assertEquals("account_deleted", deleted.getString("reason"))
        assertThrows { PhoneWearProtocol.buildBindingState(signedOut, unlinked = false, accountDeleted = true) }
        // The deleted owner rides only on the deletion reason, and only as a valid owner id.
        val deletedOwner = "c".repeat(64)
        val named = org.json.JSONObject(
            String(
                PhoneWearProtocol.buildBindingState(
                    signedOut, unlinked = true, now = now, messageId = operationId,
                    accountDeleted = true, deletedOwnerId = deletedOwner
                )
            )
        )
        assertEquals(keys + "reason" + "deletedOwnerId", named.keys().asSequence().toSet())
        assertEquals("account_deleted", named.getString("reason"))
        assertEquals(deletedOwner, named.getString("deletedOwnerId"))
        assertThrows { PhoneWearProtocol.buildBindingState(signedOut, unlinked = true, deletedOwnerId = deletedOwner) }
        assertThrows {
            PhoneWearProtocol.buildBindingState(signedOut, unlinked = false, accountDeleted = true, deletedOwnerId = deletedOwner)
        }
        assertThrows {
            PhoneWearProtocol.buildBindingState(signedOut, unlinked = true, accountDeleted = true, deletedOwnerId = "C".repeat(64))
        }
        assertThrows {
            PhoneWearProtocol.buildBindingState(signedOut, unlinked = true, accountDeleted = true, deletedOwnerId = "c".repeat(63))
        }
        assertThrows {
            PhoneWearProtocol.buildBindingState(signedOut.copy(authorityEpoch = "not-an-epoch"), unlinked = false)
        }
    }

    @Test
    fun everyPhoneEnvelopeCarriesTheAuthorityEpoch() {
        val binding = PhoneWearAccountBinding(ownerId, 4L, signedOut = false, authorityEpoch = TEST_EPOCH)
        val ack = org.json.JSONObject(String(PhoneWearProtocol.buildMutationAck(binding, operationId, accepted = true, now = now)))
        val fullSync = org.json.JSONObject(
            String(PhoneWearProtocol.buildBoundedFullSync(binding, 1L, emptyList(), emptyList(), now = now, messageId = operationId))
        )
        assertEquals(TEST_EPOCH, ack.getString("authorityEpoch"))
        assertEquals(TEST_EPOCH, fullSync.getString("authorityEpoch"))
        assertThrows {
            PhoneWearProtocol.buildBoundedFullSync(binding.copy(authorityEpoch = ""), 1L, emptyList(), emptyList())
        }
    }

    private fun requestJson(sentAt: Long = now): String {
        return """{"type":"request_full_sync","protocolVersion":1,"operationId":"$operationId","sentAt":$sentAt}"""
    }

    private fun assertInvalid(path: String, raw: String) {
        assertTrue(
            PhoneWearProtocol.parse(path, raw.toByteArray(), now) is PhoneWearParseResult.Invalid
        )
    }

    @Test
    fun workoutPlanKeepsUnicodeNamesAndUsesBoundedWatchEnvelope() {
        val binding = PhoneWearAccountBinding(ownerId = ownerId, accountGeneration = 4L, signedOut = false, authorityEpoch = TEST_EPOCH)
        val payload = PhoneWearProtocol.buildWorkoutPlan(
            binding = binding,
            revision = 9L,
            sets = listOf(
                NamedWorkoutSetDraft("Жим лёжа", 80.0, 8),
                NamedWorkoutSetDraft("Присяд зі штангою", 100.0, 5)
            ),
            exerciseCatalog = listOf("Жим лёжа", "жим лёжа", "Тяга"),
            profile = PhoneWearPlanProfile("UpperLower", 4, "Strength", "Deficit"),
            planSource = "smart_coach",
            now = now,
            messageId = operationId
        )

        assertTrue(payload.size <= PhoneWearPaths.MAX_MESSAGE_BYTES)
        val root = JSONObject(payload.toString(Charsets.UTF_8))
        assertEquals(1, root.getInt("protocolVersion"))
        assertEquals(ownerId, root.getString("ownerId"))
        assertEquals(4L, root.getLong("accountGeneration"))
        assertEquals(9L, root.getLong("revision"))
        assertEquals(now, root.getLong("sentAt"))
        assertTrue(root.getLong("expiresAt") in (now + 1)..(now + 30L * 24 * 60 * 60 * 1_000))
        assertEquals("Жим лёжа", root.getJSONArray("sets").getJSONObject(0).getString("exerciseName"))
        assertEquals("Присяд зі штангою", root.getJSONArray("sets").getJSONObject(1).getString("exerciseName"))
        assertEquals(2, root.getJSONArray("exerciseCatalog").length())
        assertEquals(4, root.getJSONObject("trainingProfile").getInt("workoutsPerWeek"))
    }

    @Test
    fun workoutPlanRejectsSignedOutEmptyOversizedAndInvalidPlans() {
        val binding = PhoneWearAccountBinding(ownerId = ownerId, accountGeneration = 4L, signedOut = false, authorityEpoch = TEST_EPOCH)
        fun build(
            sets: List<NamedWorkoutSetDraft>,
            account: PhoneWearAccountBinding = binding
        ) = PhoneWearProtocol.buildWorkoutPlan(
            binding = account,
            revision = 1L,
            sets = sets,
            exerciseCatalog = emptyList(),
            profile = null,
            planSource = "smart_coach",
            now = now,
            messageId = operationId
        )
        val good = NamedWorkoutSetDraft("Bench Press", 80.0, 8)
        assertThrows { build(emptyList()) }
        assertThrows { build(List(PhoneWearPaths.MAX_PLAN_SETS + 1) { good }) }
        assertThrows { build(listOf(good.copy(reps = 0))) }
        assertThrows { build(listOf(good.copy(exerciseName = " "))) }
        assertThrows { build(listOf(good), binding.copy(signedOut = true)) }
        assertEquals(1, JSONObject(build(listOf(good)).toString(Charsets.UTF_8)).getJSONArray("sets").length())
    }

    @Test
    fun watchUnlinkParsesABoundOrUnboundEnvelope() {
        fun unlink(extra: String = ""): String =
            """{"type":"unlink","protocolVersion":1,"operationId":"$operationId","sentAt":$now$extra}"""

        val bound = PhoneWearProtocol.parse(
            PhoneWearPaths.UNLINK,
            unlink(""","ownerId":"$ownerId","accountGeneration":7""").toByteArray(),
            now
        ) as PhoneWearParseResult.Valid
        val command = bound.command as PhoneWearCommand.Unlink
        assertEquals(ownerId, command.envelope.ownerId)
        assertEquals(7L, command.envelope.accountGeneration)
        assertEquals(operationId, command.envelope.operationId)

        val unbound = PhoneWearProtocol.parse(PhoneWearPaths.UNLINK, unlink().toByteArray(), now)
            as PhoneWearParseResult.Valid
        assertEquals(null, unbound.command.envelope.ownerId)
        assertEquals(null, unbound.command.envelope.accountGeneration)
        assertTrue(PhoneWearPaths.UNLINK in PhoneWearPaths.inboundPaths)
        assertTrue(PhoneWearPaths.UNLINK.startsWith("/gym/sync/"))
    }

    @Test
    fun watchUnlinkRejectsMalformedIncompleteStaleAndPathConfusedMessages() {
        fun parse(raw: String, path: String = PhoneWearPaths.UNLINK) =
            PhoneWearProtocol.parse(path, raw.toByteArray(), now)
        val day = 24L * 60 * 60 * 1_000
        val head = """"protocolVersion":1,"operationId":"$operationId""""
        val owner = ""","ownerId":"$ownerId","accountGeneration":7"""

        listOf(
            "not json",
            """{"type":"unlink",$head}""", // sentAt missing
            """{"type":"unlink",$head,"sentAt":$now,"ownerId":"$ownerId"}""", // half a binding
            """{"type":"unlink",$head,"sentAt":$now,"accountGeneration":7}""",
            """{"type":"unlink",$head,"sentAt":$now,"ownerId":"not-an-owner","accountGeneration":7}""",
            """{"type":"unlink",$head,"sentAt":$now,"ownerId":"$ownerId","accountGeneration":0}""",
            """{"type":"unlink","protocolVersion":2,"operationId":"$operationId","sentAt":$now$owner}""",
            """{"type":"unlink","protocolVersion":1,"operationId":"op-1","sentAt":$now$owner}""",
            """{"type":"delete_set",$head,"sentAt":$now$owner}""",
            """{"type":"unlink",$head,"sentAt":${now - 8 * day}$owner}""", // too old
            """{"type":"unlink",$head,"sentAt":${now + 10 * 60 * 1_000}$owner}""" // from the future
        ).forEach { raw ->
            assertTrue(raw, parse(raw) is PhoneWearParseResult.Invalid)
        }
        // An unlink body sent on another path is not an unlink (and not a valid mutation).
        assertTrue(
            parse("""{"type":"unlink",$head,"sentAt":$now$owner}""", PhoneWearPaths.DELETE_SET)
                is PhoneWearParseResult.Invalid
        )
        // Inside the existing freshness window it is accepted.
        assertTrue(
            parse("""{"type":"unlink",$head,"sentAt":${now - 6 * day}$owner}""")
                is PhoneWearParseResult.Valid
        )
    }

    private fun assertThrows(block: () -> Unit) {
        val failed = try {
            block()
            false
        } catch (_: IllegalArgumentException) {
            true
        }
        assertTrue(failed)
    }
}

private const val TEST_EPOCH = "11111111-2222-4333-8444-555555555555"
