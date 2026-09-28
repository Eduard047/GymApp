package com.example.gymapp.auth

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.catalog.normalizeExerciseIdentityName
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.CancellationException

/**
 * A friend's latest result on one exercise, shown on the matching exercise card during a workout
 * ("Саша: 85 × 8 · 3 дня назад"), as on iOS.
 */
internal data class FriendGhost(
    val friendName: String,
    val weightKg: Double,
    val reps: Int,
    /** The friend's workout day, `yyyy-MM-dd`. */
    val workoutDay: String,
    val startedAtMillis: Long
)

internal object FriendGhosts {
    const val MAXIMUM_FRIENDS = 10

    /** Built-in exercises match by catalog key, custom ones by normalized name. */
    fun exerciseKey(catalogKey: String?, name: String): String {
        BuiltInExerciseCatalog.definitionForKey(catalogKey)?.let { return "catalog:${it.key}" }
        BuiltInExerciseCatalog.inferKey(name)?.let { return "catalog:$it" }
        return "custom:${normalizeExerciseIdentityName(name)}"
    }

    /** The most recently active friends first, at most [MAXIMUM_FRIENDS]. */
    fun friendsToQuery(friends: List<SocialFriend>): List<SocialFriend> =
        friends.withIndex()
            .sortedWith(
                compareByDescending<IndexedValue<SocialFriend>> { parseMillis(it.value.progressUpdatedAt) ?: Long.MIN_VALUE }
                    .thenBy { it.index }
            )
            .take(MAXIMUM_FRIENDS)
            .map { it.value }

    /**
     * The latest result per exercise across the friends' pages. The most recent workout wins;
     * within it the heaviest set, then the most reps. Pages come only from friends who share
     * workout details.
     */
    fun ghosts(pages: List<SocialFriendWorkoutPage>): Map<String, FriendGhost> {
        val result = mutableMapOf<String, FriendGhost>()
        for (page in pages) {
            for (workout in page.items) {
                val startedAt = parseMillis(workout.startedAt) ?: continue
                for (exercise in workout.exercises) {
                    val top = exercise.sets.maxWithOrNull(
                        compareBy<SocialFriendWorkoutSet> { it.weightKg }.thenBy { it.reps }
                    ) ?: continue
                    if (top.reps <= 0) continue
                    val key = exerciseKey(exercise.catalogKey, exercise.name)
                    val existing = result[key]
                    if (existing != null && existing.startedAtMillis >= startedAt) continue
                    result[key] = FriendGhost(
                        friendName = page.displayName,
                        weightKg = top.weightKg,
                        reps = top.reps,
                        workoutDay = workout.workoutDay,
                        startedAtMillis = startedAt
                    )
                }
            }
        }
        return result
    }

    /** Whole days from the friend's workout day to [today]; 0 for an unreadable day. */
    fun daysAgo(workoutDay: String, today: LocalDate): Int {
        val day = runCatching { LocalDate.parse(workoutDay) }.getOrNull() ?: return 0
        return ChronoUnit.DAYS.between(day, today).coerceAtLeast(0L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    private fun parseMillis(value: String?): Long? =
        value?.let { runCatching { OffsetDateTime.parse(it).toInstant().toEpochMilli() }.getOrNull() }
}

/**
 * Loads friends' latest results once when a workout starts. Only friends whose workout-detail
 * sharing is on (checked with a fresh capability request) are read; every failure simply leaves
 * that friend out, like iOS.
 */
internal suspend fun loadFriendGhosts(
    authManager: CloudAuthManager,
    session: AccountSession.Cloud
): Map<String, FriendGhost> {
    val friends = try {
        authManager.loadSocialDashboard(session).friends
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (_: Exception) {
        return emptyMap()
    }
    val pages = mutableListOf<SocialFriendWorkoutPage>()
    for (friend in FriendGhosts.friendsToQuery(friends)) {
        try {
            if (!authManager.loadSocialFriendWorkoutDetailCapability(session, friend.profileId).available) continue
            authManager.loadSocialFriendWorkoutPage(session, friend.profileId)?.let(pages::add)
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Exception) {
            continue
        }
    }
    return FriendGhosts.ghosts(pages)
}
