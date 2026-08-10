package com.example.gymapp.ui.viewmodel

import com.example.gymapp.auth.LiveInboxRoom
import com.example.gymapp.auth.LiveProfile
import com.example.gymapp.auth.LiveWorkoutInbox
import com.example.gymapp.auth.LiveWorkoutSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LiveWorkoutInboxBindingTest {
    @Test
    fun `missing bound room detaches instead of falling back to another active room`() {
        val detached = mutableListOf<String>()
        var generationChecks = 0

        val selected = resolveLiveInboxRoom(
            boundRoomId = BOUND_ROOM_ID,
            inbox = LiveWorkoutInbox(
                invitations = emptyList(),
                rooms = listOf(activeRoom(OTHER_ROOM_ID))
            ),
            isSessionGenerationActive = {
                generationChecks += 1
                true
            },
            detachBoundRoom = detached::add
        )

        assertNull(selected)
        assertEquals(1, generationChecks)
        assertEquals(listOf(BOUND_ROOM_ID), detached)
    }

    @Test
    fun `stale session generation cannot detach bound room`() {
        val detached = mutableListOf<String>()

        val selected = resolveLiveInboxRoom(
            boundRoomId = BOUND_ROOM_ID,
            inbox = LiveWorkoutInbox(invitations = emptyList(), rooms = emptyList()),
            isSessionGenerationActive = { false },
            detachBoundRoom = detached::add
        )

        assertNull(selected)
        assertEquals(emptyList<String>(), detached)
    }

    private fun activeRoom(roomId: String) = LiveInboxRoom(
        roomId = roomId,
        status = "active",
        roomRevision = 3,
        role = "participant",
        memberState = "joined",
        membershipRevision = 2,
        createdAt = "2026-08-10T10:00:00Z",
        startedAt = "2026-08-10T10:05:00Z",
        activeExpiresAt = "2026-08-10T13:05:00Z",
        summary = LiveWorkoutSummary(
            exerciseCount = 1,
            setCount = 1,
            exerciseNames = listOf("Bench Press")
        ),
        peer = LiveProfile("gp_peer0000000000000000000000001", "Peer")
    )

    private companion object {
        const val BOUND_ROOM_ID = "lr_00000000000000000000000000000001"
        const val OTHER_ROOM_ID = "lr_00000000000000000000000000000002"
    }
}
