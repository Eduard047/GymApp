package com.example.gymapp.ui.screens

import com.example.gymapp.auth.SocialExerciseRecord
import com.example.gymapp.auth.SocialFriendRequest
import org.junit.Assert.assertEquals
import org.junit.Test

class FriendDetailPresentationTest {
    @Test
    fun setsAt140By2And60By18NeverRenderAsAnInvented140By18Set() {
        val heaviestLoggedSet = 140.0 to 2
        val highestRepLoggedSet = 60.0 to 18
        val record = SocialExerciseRecord(
            catalogKey = "bench_press",
            name = "Bench Press",
            bestWeightKg = heaviestLoggedSet.first,
            bestReps = highestRepLoggedSet.second,
            workoutCount = 4,
            lastWorkoutDay = "2026-08-09"
        )

        assertEquals(
            listOf(
                FriendRecordMetric.BestWeight(140.0),
                FriendRecordMetric.BestRepetitions(18)
            ),
            friendRecordMetrics(record)
        )
    }

    @Test
    fun incomingRequestBlockTargetsOpaqueProfileRatherThanFriendship() {
        val request = SocialFriendRequest(
            friendshipId = "f_${"a".repeat(32)}",
            profileId = "p_${"b".repeat(32)}",
            displayName = "Requester",
            requestedAt = "2026-08-09T10:00:00Z",
            friendshipRevision = 1
        )

        assertEquals(request.profileId, incomingFriendRequestBlockTarget(request))
    }
}
