package com.example.gymapp.auth

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveWorkoutContractTest {
    @Test
    fun `gateway request accepts only canonical versioned live actions`() {
        val actions = listOf(
            "live_inbox",
            "live_send_invite",
            "live_respond_invite",
            "live_start",
            "live_snapshot",
            "live_apply",
            "live_finish",
            "live_leave",
            "live_cancel"
        )

        actions.forEach { action ->
            val request = JSONObject(
                liveGatewayRequestJson(action, JSONObject().put("roomId", ROOM_ID))
            )
            assertEquals(
                setOf("version", "action", "payload"),
                request.keys().asSequence().toSet()
            )
            assertEquals(1, request.getInt("version"))
            assertEquals(action, request.getString("action"))
            assertEquals(ROOM_ID, request.getJSONObject("payload").getString("roomId"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            liveGatewayRequestJson("snapshot", JSONObject())
        }
    }

    @Test
    fun `gateway success unwrap is strict and preserves inner contract`() {
        val inner = JSONObject()
            .put("version", 1)
            .put("result", "submitted_or_unavailable")
            .put("roomId", JSONObject.NULL)
            .put("status", JSONObject.NULL)
            .put("roomRevision", JSONObject.NULL)
        val wrapped = JSONObject().put("version", 1).put("result", inner)

        val parsed = parseLiveSendInviteResult(unwrapLiveGatewaySuccess(wrapped.toString()))

        assertEquals("submitted_or_unavailable", parsed.result)
        wrapped.put("trace", "private")
        assertThrows(IllegalArgumentException::class.java) {
            unwrapLiveGatewaySuccess(wrapped.toString())
        }
    }

    @Test
    fun `realtime signal is strict and only acts as an invalidation hint`() {
        val parsed = parseLiveWorkoutRealtimeSignal(
            JSONObject()
                .put("version", 1)
                .put("kind", "progress")
                .put("roomId", ROOM_ID)
                .put("roomRevision", 7)
                .toString()
        )

        assertEquals("progress", parsed.kind)
        assertEquals(7, parsed.roomRevision)

        assertThrows(IllegalArgumentException::class.java) {
            parseLiveWorkoutRealtimeSignal(
                JSONObject()
                    .put("version", 1)
                    .put("kind", "progress")
                    .put("roomId", ROOM_ID)
                    .put("roomRevision", 7)
                    .put("completedSets", JSONArray())
                    .toString()
            )
        }
    }

    @Test
    fun `inbox parser accepts bounded exact contract`() {
        val response = JSONObject()
            .put("version", 1)
            .put("invitations", JSONArray().put(invitationJson()))
            .put("rooms", JSONArray())
            .toString()

        val parsed = parseLiveWorkoutInbox(response)

        assertEquals(1, parsed.invitations.size)
        assertEquals(ROOM_ID, parsed.invitations.single().roomId)
        assertTrue(parsed.rooms.isEmpty())
    }

    @Test
    fun `inbox parser rejects unknown fields and duplicate rooms`() {
        val withUnknownField = JSONObject()
            .put("version", 1)
            .put("invitations", JSONArray())
            .put("rooms", JSONArray())
            .put("debug", true)

        assertThrows(IllegalArgumentException::class.java) {
            parseLiveWorkoutInbox(withUnknownField.toString())
        }

        val response = JSONObject()
            .put("version", 1)
            .put("invitations", JSONArray().put(invitationJson()))
            .put("rooms", JSONArray().put(roomJson()))

        assertThrows(IllegalArgumentException::class.java) {
            parseLiveWorkoutInbox(response.toString())
        }

        assertThrows(IllegalArgumentException::class.java) {
            parseLiveWorkoutInbox(
                JSONObject()
                    .put("version", 1)
                    .put("invitations", JSONArray())
                    .put("rooms", JSONArray())
                    .toString() + " trailing"
            )
        }
    }

    @Test
    fun `snapshot parser validates canonical set mapping and progress`() {
        val parsed = parseLiveWorkoutSnapshot(snapshotJson().toString())

        assertEquals(setOf("s_01_01"), parsed.plan.setIds)
        assertEquals("s_01_01", parsed.self.progress?.undoableSetId)
        assertEquals("Partner", parsed.peer.profile.displayName)
    }

    @Test
    fun `snapshot parser rejects progress for a set outside canonical plan`() {
        val response = snapshotJson()
        response.getJSONArray("participants")
            .getJSONObject(0)
            .getJSONObject("progress")
            .getJSONArray("completedSets")
            .getJSONObject(0)
            .put("setId", "s_01_02")

        assertThrows(IllegalArgumentException::class.java) {
            parseLiveWorkoutSnapshot(response.toString())
        }
    }

    @Test
    fun `snapshot parser rejects an undo marker that is not the latest completed set`() {
        val response = snapshotJson()
        val progress = response.getJSONArray("participants")
            .getJSONObject(0)
            .getJSONObject("progress")
        progress.put("undoableSetId", JSONObject.NULL)

        assertThrows(IllegalArgumentException::class.java) {
            parseLiveWorkoutSnapshot(response.toString())
        }
    }

    @Test
    fun `send parser preserves indistinguishable unavailable result`() {
        val parsed = parseLiveSendInviteResult(
            JSONObject()
                .put("version", 1)
                .put("result", "submitted_or_unavailable")
                .put("roomId", JSONObject.NULL)
                .put("status", JSONObject.NULL)
                .put("roomRevision", JSONObject.NULL)
                .toString()
        )

        assertEquals("submitted_or_unavailable", parsed.result)
        assertNull(parsed.roomId)
        assertNull(parsed.status)
        assertNull(parsed.roomRevision)
    }

    @Test
    fun `accept parser prefers active and keeps ready only as response compatibility`() {
        fun response(status: String) = JSONObject()
            .put("version", 1)
            .put("result", "joined")
            .put("roomId", ROOM_ID)
            .put("status", status)
            .put("roomRevision", 5)
            .put("membershipRevision", 2)
            .toString()

        assertEquals("active", parseLiveRespondInviteResult(response("active")).status)
        assertEquals("ready", parseLiveRespondInviteResult(response("ready")).status)
        assertThrows(IllegalArgumentException::class.java) {
            parseLiveRespondInviteResult(response("waiting"))
        }
    }

    @Test
    fun `apply parser requires completion timestamp only for complete`() {
        val complete = parseLiveApplyResult(
            JSONObject()
                .put("version", 1)
                .put("result", "applied")
                .put("roomId", ROOM_ID)
                .put("roomRevision", 4)
                .put("progressRevision", 2)
                .put("kind", "complete_set")
                .put("setId", "s_01_01")
                .put("completedAt", NOW)
                .toString()
        )

        assertTrue(complete is LiveApplyResult.Applied)

        val incoherent = JSONObject()
            .put("version", 1)
            .put("result", "applied")
            .put("roomId", ROOM_ID)
            .put("roomRevision", 4)
            .put("progressRevision", 2)
            .put("kind", "undo_set")
            .put("setId", "s_01_01")
            .put("completedAt", NOW)

        assertThrows(IllegalArgumentException::class.java) {
            parseLiveApplyResult(incoherent.toString())
        }
    }

    @Test
    fun `gateway exception exposes only expected recovery categories`() {
        val conflict = LiveWorkoutGatewayException(409, "conflict", "stale")
        val unavailable = LiveWorkoutGatewayException(404, "resource_unavailable", "gone")

        assertTrue(conflict.isConflict)
        assertFalse(conflict.isResourceUnavailable)
        assertTrue(unavailable.isResourceUnavailable)
        assertFalse(unavailable.isConflict)
    }

    private fun invitationJson(): JSONObject = JSONObject()
        .put("roomId", ROOM_ID)
        .put("status", "waiting")
        .put("roomRevision", 1)
        .put("createdAt", NOW)
        .put("inviteExpiresAt", LATER)
        .put("summary", summaryJson())
        .put("owner", profileJson("p_${"1".repeat(32)}", "Owner"))

    private fun roomJson(): JSONObject = JSONObject()
        .put("roomId", ROOM_ID)
        .put("status", "waiting")
        .put("roomRevision", 1)
        .put("role", "owner")
        .put("memberState", "joined")
        .put("membershipRevision", 1)
        .put("createdAt", NOW)
        .put("startedAt", JSONObject.NULL)
        .put("activeExpiresAt", JSONObject.NULL)
        .put("summary", summaryJson())
        .put("peer", profileJson("p_${"2".repeat(32)}", "Partner"))

    private fun snapshotJson(): JSONObject {
        val complete = JSONObject()
            .put("setId", "s_01_01")
            .put("weight", 80.0)
            .put("reps", 8)
            .put("completedAt", NOW)
        val selfProgress = JSONObject()
            .put("revision", 2)
            .put("completedSets", JSONArray().put(complete))
            .put("undoableSetId", "s_01_01")
            .put("finishedAt", JSONObject.NULL)
        val peerProgress = JSONObject()
            .put("revision", 1)
            .put("completedSets", JSONArray())
            .put("undoableSetId", JSONObject.NULL)
            .put("finishedAt", JSONObject.NULL)
        val participants = JSONArray()
            .put(participantJson(true, "p_${"1".repeat(32)}", "Owner", "owner", selfProgress))
            .put(participantJson(false, "p_${"2".repeat(32)}", "Partner", "participant", peerProgress))
        val plan = JSONObject()
            .put("version", 1)
            .put(
                "exercises",
                JSONArray().put(
                    JSONObject()
                        .put("exerciseId", "e_01")
                        .put("name", "Bench press")
                        .put("catalogKey", "bench_press")
                        .put(
                            "sets",
                            JSONArray().put(
                                JSONObject()
                                    .put("setId", "s_01_01")
                                    .put("weight", 80.0)
                                    .put("reps", 8)
                            )
                        )
                )
            )
        return JSONObject()
            .put("version", 1)
            .put(
                "room",
                JSONObject()
                    .put("roomId", ROOM_ID)
                    .put("status", "active")
                    .put("roomRevision", 3)
                    .put("closeReason", JSONObject.NULL)
                    .put("createdAt", NOW)
                    .put("inviteExpiresAt", LATER)
                    .put("startedAt", NOW)
                    .put("activeExpiresAt", LATER)
                    .put("endedAt", JSONObject.NULL)
                    .put("summary", summaryJson())
            )
            .put("plan", plan)
            .put("participants", participants)
    }

    private fun participantJson(
        isSelf: Boolean,
        profileId: String,
        name: String,
        role: String,
        progress: JSONObject
    ): JSONObject = JSONObject()
        .put("isSelf", isSelf)
        .put("profile", profileJson(profileId, name))
        .put("role", role)
        .put("state", "joined")
        .put("membershipRevision", 1)
        .put("joinedAt", NOW)
        .put("finishedAt", JSONObject.NULL)
        .put("departedAt", JSONObject.NULL)
        .put("progress", progress)

    private fun summaryJson(): JSONObject = JSONObject()
        .put("exerciseCount", 1)
        .put("setCount", 1)
        .put("exerciseNames", JSONArray().put("Bench press"))

    private fun profileJson(id: String, name: String): JSONObject = JSONObject()
        .put("profileId", id)
        .put("displayName", name)

    private companion object {
        const val ROOM_ID = "lr_0123456789abcdef0123456789abcdef"
        const val NOW = "2026-08-10T09:00:00Z"
        const val LATER = "2026-08-10T11:00:00Z"
    }
}
