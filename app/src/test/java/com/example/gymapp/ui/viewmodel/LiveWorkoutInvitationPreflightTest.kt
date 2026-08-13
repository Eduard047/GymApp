package com.example.gymapp.ui.viewmodel

import com.example.gymapp.auth.LiveCanonicalExercise
import com.example.gymapp.auth.LiveCanonicalPlan
import com.example.gymapp.auth.LiveCanonicalSet
import com.example.gymapp.auth.LiveInvitation
import com.example.gymapp.auth.LiveParticipant
import com.example.gymapp.auth.LiveProfile
import com.example.gymapp.auth.LiveRespondInviteResult
import com.example.gymapp.auth.LiveRoomSnapshot
import com.example.gymapp.auth.LiveWorkoutSnapshot
import com.example.gymapp.auth.LiveWorkoutSummary
import com.example.gymapp.data.repository.normalizeLiveCanonicalPlan
import com.example.gymapp.data.repository.validateLiveCanonicalExerciseResolution
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveWorkoutInvitationPreflightTest {
    @Test
    fun `authoritative still invited inbox releases restart reservation but not in flight accept`() {
        assertTrue(shouldReleaseParticipantLiveReservation(
            role = "participant",
            invitationStillWaiting = true,
            responseInFlight = false,
            ignoreInFlight = false
        ))
        assertTrue(!shouldReleaseParticipantLiveReservation(
            role = "participant",
            invitationStillWaiting = true,
            responseInFlight = true,
            ignoreInFlight = false
        ))
        assertTrue(!shouldReleaseParticipantLiveReservation(
            role = "owner",
            invitationStillWaiting = true,
            responseInFlight = false,
            ignoreInFlight = false
        ))
    }

    @Test
    fun `valid frozen plan is accepted only after preflight`() = runBlocking {
        val plan = validPlan()
        val invitation = invitation(plan)
        val snapshot = waitingSnapshot(plan)
        val calls = mutableListOf<String>()

        val result = acceptLiveInvitationAfterPreflight(
            invitation = invitation,
            ensureCanJoin = { calls += "active-check" },
            loadSnapshot = {
                calls += "snapshot"
                snapshot
            },
            validatePlan = { plan ->
                calls += "preflight"
                validateLiveCanonicalExerciseResolution(
                    plan = normalizeLiveCanonicalPlan(plan),
                    existingExercises = emptyList()
                )
            },
            reserveBeforeRespond = {
                calls += "reserve"
                assertEquals("00000000-0000-4000-8000-000000000001", it)
            },
            respond = { expectedRoomRevision, clientOperationId ->
                calls += "respond"
                assertEquals(4, expectedRoomRevision)
                assertEquals("00000000-0000-4000-8000-000000000001", clientOperationId)
                LiveRespondInviteResult(
                    result = "joined",
                    roomId = ROOM_ID,
                    status = "ready",
                    roomRevision = 5,
                    membershipRevision = 2,
                    endedAt = null
                )
            },
            newOperationId = { "00000000-0000-4000-8000-000000000001" }
        )

        assertEquals("joined", result.result)
        assertEquals(listOf("active-check", "snapshot", "preflight", "reserve", "respond"), calls)
    }

    @Test
    fun `accept reserves before rpc and reconciles exact operation after failure`() = runBlocking {
        val plan = validPlan()
        val calls = mutableListOf<String>()
        val operationId = "00000000-0000-4000-8000-000000000001"

        val failure = runCatching {
            acceptLiveInvitationAfterPreflight(
                invitation = invitation(plan),
                ensureCanJoin = { calls += "active-check" },
                loadSnapshot = { calls += "snapshot"; waitingSnapshot(plan) },
                validatePlan = { calls += "preflight" },
                reserveBeforeRespond = {
                    calls += "reserve:$it"
                },
                releaseAfterFailedRespond = {
                    calls += "release:$it"
                },
                respond = { _, clientOperationId ->
                    calls += "respond:$clientOperationId"
                    error("synthetic lost response")
                },
                newOperationId = { operationId }
            )
        }.exceptionOrNull()

        assertNotNull(failure)
        assertEquals(
            listOf(
                "active-check", "snapshot", "preflight", "reserve:$operationId",
                "respond:$operationId", "release:$operationId"
            ),
            calls
        )
    }

    @Test
    fun `active local workout blocks before snapshot and accept mutation`() = runBlocking {
        val plan = validPlan()
        val invitation = invitation(plan)
        var snapshotCalls = 0
        var validationCalls = 0
        var respondCalls = 0

        val failure = runCatching {
            acceptLiveInvitationAfterPreflight(
                invitation = invitation,
                ensureCanJoin = { error("A local workout is already active.") },
                loadSnapshot = {
                    snapshotCalls += 1
                    waitingSnapshot(plan)
                },
                validatePlan = {
                    validationCalls += 1
                },
                respond = { _, _ ->
                    respondCalls += 1
                    error("Accept mutation must not run while a local workout is active.")
                }
            )
        }.exceptionOrNull()

        assertNotNull(failure)
        assertTrue(failure is IllegalStateException)
        assertEquals(0, snapshotCalls)
        assertEquals(0, validationCalls)
        assertEquals(0, respondCalls)
        assertEquals("waiting", invitation.status)
    }

    @Test
    fun `portable alias collision fails before accept mutation`() = runBlocking {
        val plan = aliasCollisionPlan()
        val invitation = invitation(plan)
        val snapshot = waitingSnapshot(plan)
        var respondCalls = 0

        val failure = runCatching {
            acceptLiveInvitationAfterPreflight(
                invitation = invitation,
                ensureCanJoin = {},
                loadSnapshot = { snapshot },
                validatePlan = { plan ->
                    validateLiveCanonicalExerciseResolution(
                        plan = normalizeLiveCanonicalPlan(plan),
                        existingExercises = emptyList()
                    )
                },
                respond = { _, _ ->
                    respondCalls += 1
                    error("Accept mutation must not run after a failed preflight.")
                },
                newOperationId = { "00000000-0000-4000-8000-000000000001" }
            )
        }.exceptionOrNull()

        assertNotNull(failure)
        assertTrue(failure is IllegalArgumentException)
        assertEquals(0, respondCalls)
        assertEquals("waiting", snapshot.room.status)
        assertEquals("invited", snapshot.self.state)
    }

    private fun invitation(plan: LiveCanonicalPlan): LiveInvitation = LiveInvitation(
        roomId = ROOM_ID,
        status = "waiting",
        roomRevision = 4,
        createdAt = CREATED_AT,
        inviteExpiresAt = EXPIRES_AT,
        summary = summary(plan),
        owner = LiveProfile("gp_owner000000000000000000000001", "Owner")
    )

    private fun waitingSnapshot(plan: LiveCanonicalPlan): LiveWorkoutSnapshot = LiveWorkoutSnapshot(
        room = LiveRoomSnapshot(
            roomId = ROOM_ID,
            status = "waiting",
            roomRevision = 4,
            closeReason = null,
            createdAt = CREATED_AT,
            inviteExpiresAt = EXPIRES_AT,
            startedAt = null,
            activeExpiresAt = null,
            endedAt = null,
            summary = summary(plan)
        ),
        plan = plan,
        participants = listOf(
            LiveParticipant(
                isSelf = false,
                profile = LiveProfile("gp_owner000000000000000000000001", "Owner"),
                role = "owner",
                state = "joined",
                membershipRevision = 1,
                joinedAt = CREATED_AT,
                finishedAt = null,
                departedAt = null,
                progress = null
            ),
            LiveParticipant(
                isSelf = true,
                profile = LiveProfile("gp_self0000000000000000000000001", "Athlete"),
                role = "participant",
                state = "invited",
                membershipRevision = 1,
                joinedAt = null,
                finishedAt = null,
                departedAt = null,
                progress = null
            )
        )
    )

    private fun aliasCollisionPlan(): LiveCanonicalPlan = LiveCanonicalPlan(
        exercises = listOf(
            LiveCanonicalExercise(
                exerciseId = "e_01",
                name = "Bench Press",
                catalogKey = "bench_press",
                sets = listOf(LiveCanonicalSet("s_01_01", 80.0, 8))
            ),
            LiveCanonicalExercise(
                exerciseId = "e_02",
                name = "Жим штанги лежачи",
                catalogKey = "bench_press",
                sets = listOf(LiveCanonicalSet("s_02_01", 80.0, 8))
            )
        )
    )

    private fun validPlan(): LiveCanonicalPlan = LiveCanonicalPlan(
        exercises = listOf(
            LiveCanonicalExercise(
                exerciseId = "e_01",
                name = "Bench Press",
                catalogKey = "bench_press",
                sets = listOf(LiveCanonicalSet("s_01_01", 80.0, 8))
            )
        )
    )

    private fun summary(plan: LiveCanonicalPlan) = LiveWorkoutSummary(
        exerciseCount = plan.exercises.size,
        setCount = plan.exercises.sumOf { it.sets.size },
        exerciseNames = plan.exercises.map { it.name }
    )

    private companion object {
        const val ROOM_ID = "lr_00000000000000000000000000000001"
        const val CREATED_AT = "2026-08-10T10:00:00Z"
        const val EXPIRES_AT = "2026-08-10T10:15:00Z"
    }
}
