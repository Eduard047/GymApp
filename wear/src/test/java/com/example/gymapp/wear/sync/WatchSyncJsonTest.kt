package com.example.gymapp.wear.sync

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchSyncJsonTest {
    @Test
    fun malformedFullSyncIsRejectedInsteadOfBecomingEmptyHistory() {
        val result = WatchSyncJson.parseFullSyncPayload("{not-json")

        assertTrue(result is WatchSyncParseResult.Invalid)
    }

    @Test
    fun authenticatedEmptyFullSyncRemainsAnExplicitValidState() {
        val payload = envelope(revision = 4L)
            .put("sessions", JSONArray())
            .put("exerciseCatalog", JSONArray())

        val result = WatchSyncJson.parseFullSyncPayload(payload.toString())

        assertTrue(result is WatchSyncParseResult.Valid)
        assertEquals(0, (result as WatchSyncParseResult.Valid).value.sessions.size)
    }

    @Test
    fun oneInvalidSetRejectsTheWholeFullSync() {
        val invalidSet = JSONObject()
            .put("id", 10L)
            .put("sessionId", 1L)
            .put("exerciseName", "Squat")
            .put("weight", SyncPaths.MAX_WEIGHT + 1.0)
            .put("reps", 5)
            .put("orderIndex", 0)
        val session = JSONObject()
            .put("id", 1L)
            .put("startedAt", System.currentTimeMillis())
            .put("sets", JSONArray().put(invalidSet))
        val payload = envelope()
            .put("sessions", JSONArray().put(session))

        assertTrue(WatchSyncJson.parseFullSyncPayload(payload.toString()) is WatchSyncParseResult.Invalid)
    }

    @Test
    fun oversizedPlanIsRejectedWithoutTruncation() {
        val sets = JSONArray()
        repeat(SyncPaths.MAX_PLAN_SETS + 1) {
            sets.put(
                JSONObject()
                    .put("exerciseName", "Bench Press")
                    .put("weight", 50.0)
                    .put("reps", 8)
            )
        }
        val now = System.currentTimeMillis()
        val payload = envelope(sentAt = now)
            .put("expiresAt", now + 60_000L)
            .put("sets", sets)

        assertTrue(WatchSyncJson.parseWorkoutPlanPayload(payload.toString()) is WatchSyncParseResult.Invalid)
    }

    @Test
    fun expiredPlanIsRejected() {
        val now = System.currentTimeMillis()
        val payload = envelope(sentAt = now)
            .put("expiresAt", now - 1L)
            .put(
                "sets",
                JSONArray().put(
                    JSONObject()
                        .put("exerciseName", "Deadlift")
                        .put("weight", 100.0)
                        .put("reps", 3)
                )
            )

        assertTrue(WatchSyncJson.parseWorkoutPlanPayload(payload.toString()) is WatchSyncParseResult.Invalid)
    }

    @Test
    fun mutationAcknowledgementRequiresBoundedCorrelationFields() {
        val valid = JSONObject()
            .put("protocolVersion", SyncPaths.PROTOCOL_VERSION)
            .put("ownerId", "owner-1")
            .put("accountGeneration", 1L)
            .put("operationId", "operation-1")
            .put("status", "accepted")
            .put("sentAt", System.currentTimeMillis())
        val missingOperation = JSONObject(valid.toString()).apply { remove("operationId") }

        assertTrue(WatchSyncJson.parseMutationAck(valid.toString()) is WatchSyncParseResult.Valid)
        assertTrue(
            WatchSyncJson.parseMutationAck(missingOperation.toString()) is WatchSyncParseResult.Invalid
        )
    }

    @Test
    fun deeplyNestedUnknownJsonIsRejectedBeforeObjectParsing() {
        val nested = "[".repeat(33) + "0" + "]".repeat(33)
        val payload = envelope()
            .put("sessions", JSONArray())
            .toString()
            .dropLast(1) + ",\"unknown\":$nested}"

        assertTrue(WatchSyncJson.parseFullSyncPayload(payload) is WatchSyncParseResult.Invalid)
    }

    @Test
    fun protocolCountersAboveJsonSafeRangeAreRejected() {
        val tooLarge = SyncPaths.MAX_PROTOCOL_COUNTER + 1L
        val fullSync = envelope(revision = tooLarge)
            .put("sessions", JSONArray())
        val mutationAck = JSONObject()
            .put("protocolVersion", SyncPaths.PROTOCOL_VERSION)
            .put("ownerId", "owner-1")
            .put("accountGeneration", tooLarge)
            .put("operationId", "operation-1")
            .put("status", "accepted")
            .put("sentAt", System.currentTimeMillis())

        assertTrue(
            WatchSyncJson.parseFullSyncPayload(fullSync.toString()) is WatchSyncParseResult.Invalid
        )
        assertTrue(
            WatchSyncJson.parseMutationAck(mutationAck.toString()) is WatchSyncParseResult.Invalid
        )
    }

    private fun envelope(
        revision: Long = 1L,
        sentAt: Long = System.currentTimeMillis()
    ): JSONObject = JSONObject()
        .put("protocolVersion", SyncPaths.PROTOCOL_VERSION)
        .put("ownerId", "owner-1")
        .put("accountGeneration", 1L)
        .put("revision", revision)
        .put("messageId", "message-$revision")
        .put("sentAt", sentAt)
}
