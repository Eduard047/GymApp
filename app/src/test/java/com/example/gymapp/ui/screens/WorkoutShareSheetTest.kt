package com.example.gymapp.ui.screens

import com.example.gymapp.auth.SocialFriend
import org.junit.Assert.assertEquals
import org.junit.Test

class WorkoutShareSheetTest {
    @Test
    fun preferredFriendIsPresentedFirstWithoutRemovingRankedFriends() {
        val first = friend(profileId = "p_${"1".repeat(32)}", displayName = "Alpha", xp = 900)
        val preferred = friend(profileId = "p_${"2".repeat(32)}", displayName = "Beta", xp = 100)

        val rows = workoutShareFriends(listOf(first, preferred), preferred.profileId)

        assertEquals(listOf(preferred.profileId, first.profileId), rows.map { it.profileId })
    }

    @Test
    fun absentPreferenceKeepsExistingRanking() {
        val first = friend(profileId = "p_${"1".repeat(32)}", displayName = "Alpha", xp = 900)
        val second = friend(profileId = "p_${"2".repeat(32)}", displayName = "Beta", xp = 100)

        assertEquals(
            listOf(first.profileId, second.profileId),
            workoutShareFriends(listOf(second, first), null).map { it.profileId }
        )
    }

    private fun friend(profileId: String, displayName: String, xp: Int) = SocialFriend(
        friendshipId = "f_${profileId.removePrefix("p_")}",
        profileId = profileId,
        displayName = displayName,
        xp = xp,
        level = 1,
        workouts = 1,
        progressShared = true,
        statsAvailable = true,
        progressUpdatedAt = "2026-08-11T12:00:00Z",
        friendshipRevision = 1
    )
}
