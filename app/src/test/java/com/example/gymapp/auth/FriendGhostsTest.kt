package com.example.gymapp.auth

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FriendGhostsTest {
    private fun exercise(catalogKey: String?, name: String, weights: List<Double>, reps: List<Int>) =
        SocialFriendWorkoutExercise(
            catalogKey = catalogKey,
            name = name,
            sets = weights.indices.map { SocialFriendWorkoutSet(weightKg = weights[it], reps = reps[it]) }
        )

    private fun workout(startedAt: String, day: String, exercises: List<SocialFriendWorkoutExercise>) =
        SocialFriendWorkout(
            workoutId = "w-$startedAt",
            startedAt = startedAt,
            workoutDay = day,
            exerciseCount = exercises.size,
            setCount = exercises.sumOf { it.sets.size },
            truncated = false,
            exercises = exercises
        )

    private fun page(name: String, items: List<SocialFriendWorkout>) = SocialFriendWorkoutPage(
        profileId = "p_" + "a".repeat(32),
        displayName = name,
        activityRevision = null,
        items = items,
        nextCursor = null,
        integrity = "ok"
    )

    @Test
    fun builtInExercisesMatchByCatalogKeyAndCustomOnesByNormalizedName() {
        assertEquals("catalog:bench_press", FriendGhosts.exerciseKey("bench_press", "Anything"))
        assertEquals("catalog:bench_press", FriendGhosts.exerciseKey(null, "Bench Press"))
        assertEquals("catalog:bench_press", FriendGhosts.exerciseKey(null, "Жим штанги лежачи"))
        assertEquals(
            FriendGhosts.exerciseKey(null, "  Cable   Kickback "),
            FriendGhosts.exerciseKey(null, "cable kickback")
        )
        assertTrue(FriendGhosts.exerciseKey("unknown_key", "Zercher Carry").startsWith("custom:"))
    }

    @Test
    fun latestWorkoutWinsAcrossFriendsAndTheTopSetIsShown() {
        val sasha = page("Саша", listOf(
            workout("2026-09-25T10:00:00Z", "2026-09-25", listOf(
                exercise("bench_press", "Bench Press", listOf(80.0, 85.0, 85.0), listOf(8, 8, 6))
            )),
            workout("2026-09-20T10:00:00Z", "2026-09-20", listOf(
                exercise("bench_press", "Bench Press", listOf(90.0), listOf(3))
            ))
        ))
        val olena = page("Олена", listOf(
            workout("2026-09-22T10:00:00.123Z", "2026-09-22", listOf(
                exercise("bench_press", "Bench Press", listOf(60.0), listOf(10)),
                exercise(null, "Cable Kickback", listOf(15.0), listOf(12))
            ))
        ))

        val ghosts = FriendGhosts.ghosts(listOf(olena, sasha))

        val bench = ghosts.getValue("catalog:bench_press")
        assertEquals("Саша", bench.friendName)
        assertEquals(85.0, bench.weightKg, 0.0)
        assertEquals(8, bench.reps)
        assertEquals("Олена", ghosts.getValue(FriendGhosts.exerciseKey(null, "Cable Kickback")).friendName)
    }

    @Test
    fun emptyExercisesAndUnparseableTimestampsAreSkipped() {
        val sasha = page("Саша", listOf(
            workout("not-a-date", "2026-09-25", listOf(exercise("squat", "Squat", listOf(100.0), listOf(5)))),
            workout("2026-09-24T10:00:00Z", "2026-09-24", listOf(exercise("deadlift", "Deadlift", emptyList(), emptyList())))
        ))

        assertTrue(FriendGhosts.ghosts(listOf(sasha)).isEmpty())
    }

    @Test
    fun daysAgoCountsWholeCalendarDays() {
        val today = LocalDate.of(2026, 9, 28)
        assertEquals(3, FriendGhosts.daysAgo("2026-09-25", today))
        assertEquals(1, FriendGhosts.daysAgo("2026-09-27", today))
        assertEquals(0, FriendGhosts.daysAgo("2026-09-28", today))
        assertEquals(0, FriendGhosts.daysAgo("2026-09-30", today))
        assertEquals(0, FriendGhosts.daysAgo("garbage", today))
    }

    @Test
    fun atMostTenFriendsAreQueriedMostRecentlyActiveFirst() {
        val friends = (0 until 12).map { index ->
            val updatedAt = when (index) {
                11 -> "2026-09-27T10:00:00Z"
                0 -> null
                else -> "2026-09-0${index % 9 + 1}T10:00:00Z"
            }
            SocialFriend(
                friendshipId = "f$index",
                profileId = "p_" + (index % 10).toString().repeat(32),
                displayName = "Friend $index",
                xp = null,
                level = null,
                workouts = null,
                progressShared = true,
                statsAvailable = true,
                progressUpdatedAt = updatedAt,
                friendshipRevision = 1
            )
        }

        val chosen = FriendGhosts.friendsToQuery(friends)

        assertEquals(10, chosen.size)
        assertEquals("Friend 11", chosen.first().displayName)
        assertTrue(chosen.none { it.displayName == "Friend 0" })
    }
}
