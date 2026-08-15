package com.example.gymapp.ui.viewmodel

import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.LiveCanonicalExercise
import com.example.gymapp.auth.LiveCanonicalPlan
import com.example.gymapp.auth.LiveCanonicalSet
import com.example.gymapp.auth.LiveCompletedSet
import com.example.gymapp.auth.LiveInboxRoom
import com.example.gymapp.auth.LiveParticipant
import com.example.gymapp.auth.LiveProfile
import com.example.gymapp.auth.LiveProgress
import com.example.gymapp.auth.LiveRoomSnapshot
import com.example.gymapp.auth.LiveWorkoutSnapshot
import com.example.gymapp.auth.LiveWorkoutSummary
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.data.repository.LivePendingOperation
import com.example.gymapp.data.repository.LivePendingOperationKind
import com.example.gymapp.data.repository.LiveWorkoutBinding
import com.example.gymapp.data.repository.LiveWorkoutDraftSendReceipt
import com.example.gymapp.data.repository.LiveWorkoutLocalRecoveryState
import com.example.gymapp.data.repository.LiveWorkoutReservation
import com.example.gymapp.data.repository.LiveWorkoutReservationPhase
import com.example.gymapp.data.entity.ActiveWorkoutDetails
import com.example.gymapp.data.entity.ActiveWorkoutEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseWithDetails
import com.example.gymapp.data.entity.ActiveWorkoutSetEntity
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutExerciseWithDetails
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveWorkoutQueueReconcileTest {
    @Test
    fun `restart receipt requires exact current friendship and sent draft binding`() {
        val receipt = draftSendReceipt()
        val session = AccountSession.Cloud(
            userId = receipt.userId,
            email = "synthetic@example.test",
            displayName = "Synthetic",
            accessToken = "synthetic-access-token",
            refreshToken = null,
            sessionGeneration = receipt.sessionGeneration
        )
        val friend = SocialFriend(
            friendshipId = receipt.recipientFriendshipId,
            profileId = receipt.recipientProfileId,
            displayName = "Partner",
            xp = null,
            level = null,
            workouts = null,
            progressShared = false,
            statsAvailable = false,
            progressUpdatedAt = null,
            friendshipRevision = receipt.recipientFriendshipRevision
        )
        val request = LiveWorkoutDraftSendRequest(
            receipt.draftBindingId,
            receipt.draftFingerprint
        )

        assertTrue(liveWorkoutDraftSendReceiptMatches(receipt, session, friend, request))
        assertEquals(
            false,
            liveWorkoutDraftSendReceiptMatches(
                receipt,
                session,
                friend.copy(friendshipRevision = friend.friendshipRevision + 1),
                request
            )
        )
        assertEquals(
            false,
            liveWorkoutDraftSendReceiptMatches(
                receipt,
                session,
                friend,
                request.copy(draftBindingId = "72345678-1234-4123-8123-123456789abc")
            )
        )
    }

    @Test
    fun `pending restart receipt resolves only the exact recipient owner room`() {
        val receipt = draftSendReceipt()
        val reservation = draftSendReservation(receipt)
        val exact = inboxRoom().copy(
            status = "waiting",
            startedAt = null,
            peer = LiveProfile(receipt.recipientProfileId, "Partner")
        )

        assertEquals(
            exact,
            resolveAuthoritativeLiveWorkoutDraftSendRoom(
                receipt,
                reservation,
                boundRoomId = null,
                openRooms = listOf(exact)
            )
        )
        assertEquals(
            null,
            resolveAuthoritativeLiveWorkoutDraftSendRoom(
                receipt,
                reservation,
                boundRoomId = null,
                openRooms = listOf(
                    exact.copy(peer = LiveProfile("p_ffffffffffffffffffffffffffffffff", "Other"))
                )
            )
        )
        assertEquals(
            null,
            resolveAuthoritativeLiveWorkoutDraftSendRoom(
                receipt,
                reservation.copy(operationId = "22345678-1234-4123-8123-123456789abc"),
                boundRoomId = null,
                openRooms = listOf(exact)
            )
        )
    }

    @Test
    fun `unknown successful completion is dropped and unchanged next request keeps its id`() {
        val binding = binding(
            listOf(
                operation("11111111-1111-4111-8111-111111111111", "s_01_01", 1, 80.0),
                operation("22222222-2222-4222-8222-222222222222", "s_01_02", 2, 82.5)
            )
        )
        val result = reconcileLiveQueueWithSnapshot(
            binding = binding,
            snapshot = snapshot(
                revision = 2,
                completed = listOf(LiveCompletedSet("s_01_01", 80.0, 8, NOW)),
                undoable = "s_01_01"
            )
        )

        assertTrue(result is LiveQueueReconcileResult.Reconciled)
        val rebased = (result as LiveQueueReconcileResult.Reconciled).binding
        assertEquals(2, rebased.progressRevision)
        assertEquals(1, rebased.pendingOperations.size)
        assertEquals("s_01_02", rebased.pendingOperations.single().serverSetId)
        assertEquals(2, rebased.pendingOperations.single().expectedProgressRevision)
        assertEquals(
            "22222222-2222-4222-8222-222222222222",
            rebased.pendingOperations.single().clientOperationId
        )
    }

    @Test
    fun `same set with different remote values detaches instead of overwriting`() {
        val result = reconcileLiveQueueWithSnapshot(
            binding = binding(listOf(operation("11111111-1111-4111-8111-111111111111", "s_01_01", 1, 80.0))),
            snapshot = snapshot(
                revision = 2,
                completed = listOf(LiveCompletedSet("s_01_01", 120.0, 8, NOW)),
                undoable = "s_01_01"
            )
        )

        assertEquals(LiveQueueReconcileResult.Unsafe, result)
    }

    @Test
    fun `already finished receipt is removed after reconnect`() {
        val finish = LivePendingOperation(
            clientOperationId = "11111111-1111-4111-8111-111111111111",
            kind = LivePendingOperationKind.Finish,
            expectedProgressRevision = 1,
            serverSetId = null,
            weight = null,
            reps = null
        )
        val result = reconcileLiveQueueWithSnapshot(
            binding = binding(listOf(finish)),
            snapshot = snapshot(2, emptyList(), null, selfState = "finished", finishedAt = NOW)
        ) as LiveQueueReconcileResult.Reconciled

        assertTrue(result.binding.pendingOperations.isEmpty())
        assertTrue(result.binding.localFinished)
    }

    @Test
    fun `complete then undo stays ordered when neither request reached the server`() {
        val complete = operation(
            "11111111-1111-4111-8111-111111111111",
            "s_01_01",
            1,
            80.0
        )
        val undo = LivePendingOperation(
            clientOperationId = "22222222-2222-4222-8222-222222222222",
            kind = LivePendingOperationKind.UndoSet,
            expectedProgressRevision = 2,
            serverSetId = "s_01_01",
            weight = null,
            reps = null
        )

        val result = reconcileLiveQueueWithSnapshot(
            binding = binding(listOf(complete, undo)),
            snapshot = snapshot(1, emptyList(), null)
        ) as LiveQueueReconcileResult.Reconciled

        assertEquals(listOf(complete, undo), result.binding.pendingOperations)
    }

    @Test
    fun `complete then undo drops exactly the remotely applied prefix`() {
        val complete = operation(
            "11111111-1111-4111-8111-111111111111",
            "s_01_01",
            1,
            80.0
        )
        val undo = LivePendingOperation(
            clientOperationId = "22222222-2222-4222-8222-222222222222",
            kind = LivePendingOperationKind.UndoSet,
            expectedProgressRevision = 2,
            serverSetId = "s_01_01",
            weight = null,
            reps = null
        )
        val queue = listOf(complete, undo)

        val afterComplete = reconcileLiveQueueWithSnapshot(
            binding = binding(queue),
            snapshot = snapshot(
                revision = 2,
                completed = listOf(LiveCompletedSet("s_01_01", 80.0, 8, NOW)),
                undoable = "s_01_01"
            )
        ) as LiveQueueReconcileResult.Reconciled
        assertEquals(listOf(undo), afterComplete.binding.pendingOperations)

        val afterUndo = reconcileLiveQueueWithSnapshot(
            binding = binding(queue),
            snapshot = snapshot(revision = 3, completed = emptyList(), undoable = null)
        ) as LiveQueueReconcileResult.Reconciled
        assertTrue(afterUndo.binding.pendingOperations.isEmpty())
    }

    @Test
    fun `unrelated own progress revision fails closed`() {
        val result = reconcileLiveQueueWithSnapshot(
            binding = binding(
                listOf(
                    operation(
                        "11111111-1111-4111-8111-111111111111",
                        "s_01_01",
                        1,
                        80.0
                    )
                )
            ),
            snapshot = snapshot(
                revision = 3,
                completed = listOf(LiveCompletedSet("s_01_02", 82.5, 8, NOW)),
                undoable = "s_01_02"
            )
        )

        assertEquals(LiveQueueReconcileResult.Unsafe, result)
    }

    @Test
    fun `new session adopts only exact snapshot local mapping and applied queue prefix`() {
        val queued = operation(
            "11111111-1111-4111-8111-111111111111",
            "s_01_01",
            1,
            80.0
        )
        val previous = binding(listOf(queued))
        val authoritative = snapshot(
            revision = 2,
            completed = listOf(LiveCompletedSet("s_01_01", 80.0, 8, NOW)),
            undoable = "s_01_01"
        )

        val result = reconcileSessionMismatchedLiveBinding(
            previous = previous,
            newSessionGeneration = NEW_SESSION_GENERATION,
            inboxRoom = inboxRoom(),
            snapshot = authoritative,
            local = LiveWorkoutLocalRecoveryState(
                active = activeWorkout(firstCompleted = true),
                exactHistory = emptyList()
            )
        ) as LiveSessionBindingReconcileResult.Adopted

        assertEquals(NEW_SESSION_GENERATION, result.binding.sessionGeneration)
        assertEquals(2, result.binding.progressRevision)
        assertTrue(result.binding.pendingOperations.isEmpty())
    }

    @Test
    fun `new session rejects missing or wrong local mapping`() {
        val previous = binding(emptyList())
        val authoritative = snapshot(1, emptyList(), null)

        assertEquals(
            LiveSessionBindingReconcileResult.Unsafe,
            reconcileSessionMismatchedLiveBinding(
                previous = previous,
                newSessionGeneration = NEW_SESSION_GENERATION,
                inboxRoom = inboxRoom(),
                snapshot = authoritative,
                local = LiveWorkoutLocalRecoveryState(null, emptyList())
            )
        )
        assertEquals(
            LiveSessionBindingReconcileResult.Unsafe,
            reconcileSessionMismatchedLiveBinding(
                previous = previous,
                newSessionGeneration = NEW_SESSION_GENERATION,
                inboxRoom = inboxRoom(),
                snapshot = authoritative,
                local = LiveWorkoutLocalRecoveryState(
                    active = activeWorkout(firstLocalSetId = WRONG_LOCAL_SET_ID),
                    exactHistory = emptyList()
                )
            )
        )
    }

    @Test
    fun `finished local history is required for finished binding adoption`() {
        val previous = binding(emptyList()).copy(
            progressRevision = 2,
            localFinished = true
        )
        val authoritative = snapshot(
            revision = 2,
            completed = listOf(LiveCompletedSet("s_01_01", 80.0, 8, NOW)),
            undoable = "s_01_01",
            selfState = "finished",
            finishedAt = NOW
        )
        val matchingHistory = workoutHistory(weight = 80.0)

        val adopted = reconcileSessionMismatchedLiveBinding(
            previous = previous,
            newSessionGeneration = NEW_SESSION_GENERATION,
            inboxRoom = inboxRoom(memberState = "finished"),
            snapshot = authoritative,
            local = LiveWorkoutLocalRecoveryState(null, listOf(matchingHistory))
        )
        val rejected = reconcileSessionMismatchedLiveBinding(
            previous = previous,
            newSessionGeneration = NEW_SESSION_GENERATION,
            inboxRoom = inboxRoom(memberState = "finished"),
            snapshot = authoritative,
            local = LiveWorkoutLocalRecoveryState(
                null,
                listOf(workoutHistory(weight = 120.0))
            )
        )

        assertTrue(adopted is LiveSessionBindingReconcileResult.Adopted)
        assertEquals(LiveSessionBindingReconcileResult.Unsafe, rejected)
    }

    @Test
    fun `exact terminal snapshot clears stale generation without local adoption`() {
        val terminal = snapshot(1, emptyList(), null).copy(
            room = snapshot(1, emptyList(), null).room.copy(
                status = "cancelled",
                startedAt = null,
                activeExpiresAt = null,
                endedAt = NOW
            )
        )

        assertEquals(
            LiveSessionBindingReconcileResult.Terminal,
            reconcileSessionMismatchedLiveBinding(
                previous = binding(emptyList()),
                newSessionGeneration = NEW_SESSION_GENERATION,
                inboxRoom = null,
                snapshot = terminal,
                local = LiveWorkoutLocalRecoveryState(null, emptyList())
            )
        )
    }

    private fun operation(
        id: String,
        setId: String,
        revision: Int,
        weight: Double
    ) = LivePendingOperation(
        clientOperationId = id,
        kind = LivePendingOperationKind.CompleteSet,
        expectedProgressRevision = revision,
        serverSetId = setId,
        weight = weight,
        reps = 8
    )

    private fun inboxRoom(memberState: String = "joined") = LiveInboxRoom(
        roomId = ROOM_ID,
        status = "active",
        roomRevision = 4,
        role = "owner",
        memberState = memberState,
        membershipRevision = 2,
        createdAt = NOW,
        startedAt = NOW,
        activeExpiresAt = LATER,
        summary = LiveWorkoutSummary(1, 2, listOf("Bench press")),
        peer = LiveProfile("p_0123456789abcdef0123456789abcdef", "Partner")
    )

    private fun draftSendReceipt() = LiveWorkoutDraftSendReceipt(
        userId = "42345678-1234-4123-8123-123456789abc",
        sessionGeneration = "52345678-1234-4123-8123-123456789abc",
        draftBindingId = "62345678-1234-4123-8123-123456789abc",
        recipientProfileId = "p_0123456789abcdef0123456789abcdef",
        recipientFriendshipId = "f_0123456789abcdef0123456789abcdef",
        recipientFriendshipRevision = 7,
        operationId = "12345678-1234-4123-8123-123456789abc",
        roomId = null,
        draftFingerprint = "a".repeat(64),
        createdAt = 1_786_330_800_000L,
        expiresAt = 1_786_935_600_000L
    )

    private fun draftSendReservation(receipt: LiveWorkoutDraftSendReceipt) =
        LiveWorkoutReservation(
            userId = receipt.userId,
            sessionGeneration = receipt.sessionGeneration,
            role = "owner",
            operationId = receipt.operationId,
            roomId = null,
            phase = LiveWorkoutReservationPhase.Preparing,
            createdAt = receipt.createdAt,
            expiresAt = receipt.expiresAt
        )

    private fun activeWorkout(
        firstCompleted: Boolean = false,
        firstLocalSetId: String = FIRST_LOCAL_SET_ID
    ) = ActiveWorkoutDetails(
        activeWorkout = ActiveWorkoutEntity(
            id = 1,
            date = STARTED_AT,
            note = null,
            startedAt = STARTED_AT,
            revision = if (firstCompleted) 1 else 0,
            undoableSetId = firstLocalSetId.takeIf { firstCompleted }
        ),
        exercises = listOf(
            ActiveWorkoutExerciseWithDetails(
                activeWorkoutExercise = ActiveWorkoutExerciseEntity(
                    id = "82345678-1234-4123-8123-123456789abc",
                    activeWorkoutId = 1,
                    exerciseName = "Bench press",
                    catalogKey = "bench_press",
                    orderIndex = 0
                ),
                sets = listOf(
                    ActiveWorkoutSetEntity(
                        id = firstLocalSetId,
                        activeWorkoutExerciseId = "82345678-1234-4123-8123-123456789abc",
                        weight = 80.0,
                        reps = 8,
                        orderIndex = 0,
                        completedAt = STARTED_AT.takeIf { firstCompleted }
                    ),
                    ActiveWorkoutSetEntity(
                        id = SECOND_LOCAL_SET_ID,
                        activeWorkoutExerciseId = "82345678-1234-4123-8123-123456789abc",
                        weight = 82.5,
                        reps = 8,
                        orderIndex = 1,
                        completedAt = null
                    )
                )
            )
        )
    )

    private fun workoutHistory(weight: Double) = WorkoutSessionDetails(
        session = WorkoutSessionEntity(id = 41, date = STARTED_AT, note = null),
        workoutExercises = listOf(
            WorkoutExerciseWithDetails(
                workoutExercise = WorkoutExerciseEntity(
                    id = 42,
                    sessionId = 41,
                    exerciseId = 43,
                    orderIndex = 0
                ),
                exercise = ExerciseEntity(id = 43, name = "Bench press"),
                sets = listOf(
                    SetEntryEntity(
                        id = 44,
                        workoutExerciseId = 42,
                        weight = weight,
                        reps = 8,
                        orderIndex = 0
                    )
                )
            )
        )
    )

    private fun binding(queue: List<LivePendingOperation>) = LiveWorkoutBinding(
        userId = "42345678-1234-4123-8123-123456789abc",
        sessionGeneration = "52345678-1234-4123-8123-123456789abc",
        roomId = ROOM_ID,
        role = "owner",
        peerProfileId = "p_0123456789abcdef0123456789abcdef",
        peerDisplayName = "Partner",
        roomRevision = 3,
        membershipRevision = 1,
        progressRevision = 1,
        workoutStartedAt = STARTED_AT,
        serverToLocalSetIds = mapOf(
            "s_01_01" to FIRST_LOCAL_SET_ID,
            "s_01_02" to SECOND_LOCAL_SET_ID
        ),
        localFinished = queue.any { it.kind == LivePendingOperationKind.Finish },
        pendingOperations = queue
    )

    private fun snapshot(
        revision: Int,
        completed: List<LiveCompletedSet>,
        undoable: String?,
        selfState: String = "joined",
        finishedAt: String? = null
    ): LiveWorkoutSnapshot {
        val summary = LiveWorkoutSummary(1, 2, listOf("Bench press"))
        val plan = LiveCanonicalPlan(
            listOf(
                LiveCanonicalExercise(
                    exerciseId = "e_01",
                    name = "Bench press",
                    catalogKey = "bench_press",
                    sets = listOf(
                        LiveCanonicalSet("s_01_01", 80.0, 8),
                        LiveCanonicalSet("s_01_02", 82.5, 8)
                    )
                )
            )
        )
        val self = LiveParticipant(
            isSelf = true,
            profile = LiveProfile("p_${"1".repeat(32)}", "Owner"),
            role = "owner",
            state = selfState,
            membershipRevision = 2,
            joinedAt = NOW,
            finishedAt = finishedAt,
            departedAt = null,
            progress = LiveProgress(revision, completed, undoable, finishedAt)
        )
        val peer = LiveParticipant(
            isSelf = false,
            profile = LiveProfile("p_0123456789abcdef0123456789abcdef", "Partner"),
            role = "participant",
            state = "joined",
            membershipRevision = 1,
            joinedAt = NOW,
            finishedAt = null,
            departedAt = null,
            progress = LiveProgress(1, emptyList(), null, null)
        )
        return LiveWorkoutSnapshot(
            room = LiveRoomSnapshot(
                roomId = ROOM_ID,
                status = "active",
                roomRevision = 4,
                closeReason = null,
                createdAt = NOW,
                inviteExpiresAt = LATER,
                startedAt = NOW,
                activeExpiresAt = LATER,
                endedAt = null,
                summary = summary
            ),
            plan = plan,
            participants = listOf(self, peer)
        )
    }

    private companion object {
        const val ROOM_ID = "lr_0123456789abcdef0123456789abcdef"
        const val NOW = "2026-08-10T09:00:00Z"
        const val LATER = "2026-08-10T11:00:00Z"
        const val STARTED_AT = 1_786_352_400_000L
        const val FIRST_LOCAL_SET_ID = "62345678-1234-4123-8123-123456789abc"
        const val SECOND_LOCAL_SET_ID = "72345678-1234-4123-8123-123456789abc"
        const val WRONG_LOCAL_SET_ID = "92345678-1234-4123-8123-123456789abc"
        const val NEW_SESSION_GENERATION = "92345678-1234-4123-8123-123456789abd"
    }
}
