package com.example.gymapp.ui.viewmodel

import com.example.gymapp.auth.LiveCanonicalExercise
import com.example.gymapp.auth.LiveCanonicalPlan
import com.example.gymapp.auth.LiveCanonicalSet
import com.example.gymapp.auth.LiveCompletedSet
import com.example.gymapp.auth.LiveParticipant
import com.example.gymapp.auth.LiveProfile
import com.example.gymapp.auth.LiveProgress
import com.example.gymapp.auth.LiveRoomSnapshot
import com.example.gymapp.auth.LiveWorkoutSnapshot
import com.example.gymapp.auth.LiveWorkoutSummary
import org.junit.Assert.assertEquals
import org.junit.Test

class LiveExerciseLaneSummaryTest {
    @Test
    fun mapsBothParticipantsByStableServerSetId() {
        val summaries = liveExerciseLaneSummaries(snapshot())

        assertEquals(2, summaries.size)
        assertEquals(
            LiveExerciseLaneSummary(
                "Bench Press",
                selfCompletedSets = listOf(true, false),
                peerCompletedSets = listOf(false, true)
            ),
            summaries[0]
        )
        assertEquals(
            LiveExerciseLaneSummary(
                "Barbell Row",
                selfCompletedSets = listOf(false),
                peerCompletedSets = listOf(true)
            ),
            summaries[1]
        )
    }

    @Test
    fun waitingRoomDoesNotExposeProgressLanes() {
        val waiting = snapshot().copy(room = snapshot().room.copy(status = "waiting"))

        assertEquals(emptyList<LiveExerciseLaneSummary>(), liveExerciseLaneSummaries(waiting))
    }

    private fun snapshot(): LiveWorkoutSnapshot {
        val plan = LiveCanonicalPlan(
            listOf(
                LiveCanonicalExercise(
                    "e_01",
                    "Bench Press",
                    "bench_press",
                    listOf(
                        LiveCanonicalSet("s_01_01", 80.0, 8),
                        LiveCanonicalSet("s_01_02", 82.5, 6)
                    )
                ),
                LiveCanonicalExercise(
                    "e_02",
                    "Barbell Row",
                    "barbell_row",
                    listOf(LiveCanonicalSet("s_02_01", 60.0, 10))
                )
            )
        )
        val selfCompleted = listOf(completed("s_01_01", 80.0, 8))
        val peerCompleted = listOf(
            completed("s_01_02", 82.5, 6),
            completed("s_02_01", 60.0, 10)
        )
        return LiveWorkoutSnapshot(
            room = LiveRoomSnapshot(
                roomId = "lr_${"a".repeat(32)}",
                status = "active",
                roomRevision = 3,
                closeReason = null,
                createdAt = NOW,
                inviteExpiresAt = LATER,
                startedAt = NOW,
                activeExpiresAt = LATER,
                endedAt = null,
                summary = LiveWorkoutSummary(2, 3, listOf("Bench Press", "Barbell Row"))
            ),
            plan = plan,
            participants = listOf(
                participant(true, "You", selfCompleted),
                participant(false, "Friend", peerCompleted)
            )
        )
    }

    private fun participant(
        isSelf: Boolean,
        name: String,
        completed: List<LiveCompletedSet>
    ) = LiveParticipant(
        isSelf = isSelf,
        profile = LiveProfile(
            "p_${(if (isSelf) "1" else "2").repeat(32)}",
            name
        ),
        role = if (isSelf) "owner" else "participant",
        state = "joined",
        membershipRevision = 1,
        joinedAt = NOW,
        finishedAt = null,
        departedAt = null,
        progress = LiveProgress(1, completed, completed.lastOrNull()?.setId, null)
    )

    private fun completed(setId: String, weight: Double, reps: Int) = LiveCompletedSet(
        setId = setId,
        weight = weight,
        reps = reps,
        completedAt = NOW
    )

    private companion object {
        const val NOW = "2026-08-11T12:00:00Z"
        const val LATER = "2026-08-11T14:00:00Z"
    }
}
