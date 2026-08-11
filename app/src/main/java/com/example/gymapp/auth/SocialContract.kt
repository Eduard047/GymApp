package com.example.gymapp.auth

import com.example.gymapp.data.repository.SharedWorkoutLink
import com.example.gymapp.data.repository.SharedWorkoutExercise
import com.example.gymapp.data.repository.SharedWorkoutPlan
import com.example.gymapp.data.repository.SharedWorkoutSet
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.normalizedExerciseName
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

internal const val SOCIAL_CONTRACT_VERSION = 1
internal const val SOCIAL_MAX_FRIENDS = 200
internal const val SOCIAL_MAX_INCOMING_REQUESTS = 100
internal const val SOCIAL_MAX_OUTGOING_REQUESTS = 25
internal const val SOCIAL_MAX_BLOCKED_PROFILES = 200
internal const val SOCIAL_MAX_RECENT_WORKOUTS = 5
internal const val SOCIAL_MAX_WORKOUT_EXERCISES = 20
internal const val SOCIAL_MAX_EXERCISE_RECORDS = 100
internal const val SOCIAL_MAX_WORKOUT_INVITES = 25
internal const val SOCIAL_MAX_INVITE_JSON_BYTES = 32 * 1_024
internal const val SOCIAL_MY_FRIEND_CODE_MAX_BYTES = 256

private val socialProfileIdPattern = Regex("^p_[0-9a-f]{32}$")
private val socialShortFriendCodePattern = Regex("^g_[0-9a-f]{12}$")
private val socialHumanFriendCodePattern = Regex(
    "^GYM-([0-9A-F]{4})-([0-9A-F]{4})-([0-9A-F]{4})$"
)
private val socialFriendshipIdPattern = Regex("^f_[0-9a-f]{32}$")
private val socialCatalogKeyPattern = Regex("^[a-z0-9_]{1,64}$")
private val socialWorkoutDayPattern = Regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
private val socialWorkoutInviteIdPattern = Regex("^wi_[0-9a-f]{32}$")
private val socialClientRequestIdPattern = Regex(
    "^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
)

internal data class SocialPrivacy(
    val allowRequests: Boolean,
    val shareProgress: Boolean,
    val shareRecentWorkouts: Boolean,
    val shareRecords: Boolean
)

internal data class SocialSelfProfile(
    val profileId: String,
    val friendCode: String,
    val displayName: String,
    val xp: Int?,
    val level: Int?,
    val workouts: Int?,
    val statsAvailable: Boolean,
    val progressUpdatedAt: String?,
    val privacy: SocialPrivacy,
    val settingsRevision: Int
)

internal data class SocialMyFriendCode(
    val version: Int,
    val friendCode: String
)

internal data class SocialFriend(
    val friendshipId: String,
    val profileId: String,
    val displayName: String,
    val xp: Int?,
    val level: Int?,
    val workouts: Int?,
    val progressShared: Boolean,
    val statsAvailable: Boolean,
    val progressUpdatedAt: String?,
    val friendshipRevision: Int
)

internal data class SocialFriendRequest(
    val friendshipId: String,
    val profileId: String,
    val displayName: String,
    val requestedAt: String,
    val friendshipRevision: Int
)

internal data class SocialBlockedProfile(
    val profileId: String,
    val displayName: String,
    val blockedAt: String
)

internal data class SocialDashboard(
    val self: SocialSelfProfile,
    val friends: List<SocialFriend>,
    val incoming: List<SocialFriendRequest>,
    val outgoing: List<SocialFriendRequest>,
    val blocked: List<SocialBlockedProfile>,
    val pendingWorkoutInviteCount: Int
)

internal data class SocialFriendDetailProfile(
    val profileId: String,
    val displayName: String,
    val xp: Int?,
    val level: Int?,
    val workouts: Int?,
    val progressShared: Boolean,
    val statsAvailable: Boolean,
    val progressUpdatedAt: String?
)

internal data class SocialSharing(
    val progress: Boolean,
    val recentWorkouts: Boolean,
    val records: Boolean
)

internal data class SocialWorkoutExerciseLabel(
    val catalogKey: String?,
    val name: String
)

internal data class SocialRecentWorkout(
    val workoutDay: String,
    val exerciseCount: Int,
    val setCount: Int,
    val exercises: List<SocialWorkoutExerciseLabel>
)

internal data class SocialExerciseRecord(
    val catalogKey: String?,
    val name: String,
    val bestWeightKg: Double,
    val bestReps: Int,
    val workoutCount: Int,
    val lastWorkoutDay: String
)

internal data class SocialFriendDetails(
    val friend: SocialFriendDetailProfile,
    val sharing: SocialSharing,
    val activityUpdatedAt: String?,
    val recentWorkouts: List<SocialRecentWorkout>,
    val exerciseRecords: List<SocialExerciseRecord>,
    val integrity: String
)

internal data class SocialFriendshipMutation(
    val friendshipId: String,
    val status: String,
    val friendshipRevision: Int
)

internal data class SocialBlockMutation(
    val profileId: String,
    val blocked: Boolean
)

internal data class SocialPrivacyMutation(
    val privacy: SocialPrivacy,
    val settingsRevision: Int
)

internal data class SocialWorkoutInviteSummary(
    val exerciseCount: Int,
    val setCount: Int,
    val exerciseNames: List<String>
)

internal data class SocialIncomingWorkoutInvite(
    val inviteId: String,
    val profileId: String,
    val displayName: String,
    val status: String,
    val inviteRevision: Int,
    val createdAt: String,
    val expiresAt: String,
    val respondedAt: String?,
    val summary: SocialWorkoutInviteSummary,
    val workout: SharedWorkoutPlan
)

internal data class SocialOutgoingWorkoutInvite(
    val inviteId: String,
    val profileId: String,
    val displayName: String,
    val status: String,
    val inviteRevision: Int,
    val createdAt: String,
    val expiresAt: String,
    val respondedAt: String?,
    val summary: SocialWorkoutInviteSummary
)

internal data class SocialWorkoutInbox(
    val pendingIncomingCount: Int,
    val incoming: List<SocialIncomingWorkoutInvite>,
    val outgoing: List<SocialOutgoingWorkoutInvite>
)

internal data class SocialWorkoutInviteMutation(
    val inviteId: String,
    val status: String,
    val inviteRevision: Int,
    val workout: SharedWorkoutPlan?
)

internal data class SocialWorkoutInviteCancellation(
    val inviteId: String,
    val status: String,
    val inviteRevision: Int
)

internal fun isValidSocialProfileId(value: String): Boolean =
    socialProfileIdPattern.matches(value)

internal fun isValidSocialShortFriendCode(value: String): Boolean =
    socialShortFriendCodePattern.matches(value)

internal fun isValidSocialFriendshipId(value: String): Boolean =
    socialFriendshipIdPattern.matches(value)

internal fun isValidSocialWorkoutInviteId(value: String): Boolean =
    socialWorkoutInviteIdPattern.matches(value)

internal fun isValidSocialClientRequestId(value: String): Boolean =
    socialClientRequestIdPattern.matches(value)

internal fun normalizeSocialFriendCode(value: String): String? {
    if (value.length > 128 || value.toByteArray(Charsets.UTF_8).size > 128) return null
    val trimmed = value.trim()
    val canonical = trimmed.lowercase()
    if (isValidSocialProfileId(canonical) || isValidSocialShortFriendCode(canonical)) {
        return canonical
    }
    val human = socialHumanFriendCodePattern.matchEntire(trimmed.uppercase()) ?: return null
    return "g_${human.groupValues.drop(1).joinToString(separator = "").lowercase()}"
}

internal fun formatSocialFriendCode(value: String): String {
    val canonical = normalizeSocialFriendCode(value) ?: return value
    if (!isValidSocialShortFriendCode(canonical)) return canonical
    return canonical.removePrefix("g_")
        .uppercase()
        .chunked(4)
        .joinToString(separator = "-", prefix = "GYM-")
}

internal fun rankedSocialFriends(friends: List<SocialFriend>): List<SocialFriend> =
    friends.sortedWith(
        compareByDescending<SocialFriend> { it.statsAvailable }
            .thenByDescending { it.xp ?: -1 }
            .thenByDescending { it.workouts ?: -1 }
            .thenBy { it.displayName.lowercase() }
            .thenBy { it.profileId }
    )

internal fun parseSocialDashboard(raw: String): SocialDashboard {
    val root = socialRoot(
        raw,
        setOf(
            "version", "self", "friends", "incoming", "outgoing", "blocked",
            "pendingWorkoutInviteCount"
        )
    )
    val self = root.requiredObject("self").let { profile ->
        profile.requireExactKeys(
            setOf(
                "profileId", "friendCode", "displayName", "xp", "level", "workouts",
                "statsAvailable", "progressUpdatedAt", "privacy", "settingsRevision"
            )
        )
        SocialSelfProfile(
            profileId = profile.requiredProfileId("profileId"),
            friendCode = profile.requiredProfileId("friendCode"),
            displayName = profile.requiredDisplayName("displayName"),
            xp = profile.nullableInt("xp", 0, Int.MAX_VALUE),
            level = profile.nullableInt("level", 1, Int.MAX_VALUE),
            workouts = profile.nullableInt("workouts", 0, Int.MAX_VALUE),
            statsAvailable = profile.requiredBoolean("statsAvailable"),
            progressUpdatedAt = profile.nullableTimestamp("progressUpdatedAt"),
            privacy = parseSocialPrivacy(profile.requiredObject("privacy")),
            settingsRevision = profile.requiredRevision("settingsRevision")
        ).also { parsed ->
            require(parsed.friendCode == parsed.profileId) { "Social response is invalid." }
            requireCoherentSelfStats(parsed)
        }
    }
    return SocialDashboard(
        self = self,
        friends = root.requiredArray("friends", SOCIAL_MAX_FRIENDS).mapObjects(::parseSocialFriend),
        incoming = root.requiredArray("incoming", SOCIAL_MAX_INCOMING_REQUESTS)
            .mapObjects { parseSocialFriendRequest(it, "pending") },
        outgoing = root.requiredArray("outgoing", SOCIAL_MAX_OUTGOING_REQUESTS)
            .mapObjects { parseSocialFriendRequest(it, "pending") },
        blocked = root.requiredArray("blocked", SOCIAL_MAX_BLOCKED_PROFILES)
            .mapObjects(::parseSocialBlockedProfile),
        pendingWorkoutInviteCount = root.requiredInt(
            "pendingWorkoutInviteCount",
            0,
            SOCIAL_MAX_WORKOUT_INVITES
        )
    ).also(::requireUniqueSocialDashboardIds)
}

internal fun parseSocialMyFriendCode(raw: String): SocialMyFriendCode {
    require(raw.toByteArray(Charsets.UTF_8).size <= SOCIAL_MY_FRIEND_CODE_MAX_BYTES) {
        "Social response is invalid."
    }
    val root = socialRoot(raw, setOf("version", "friendCode"))
    return SocialMyFriendCode(
        version = root.requiredInt(
            "version",
            SOCIAL_CONTRACT_VERSION,
            SOCIAL_CONTRACT_VERSION
        ),
        friendCode = root.requiredShortFriendCode("friendCode")
    )
}

internal fun parseSocialFriendDetails(raw: String): SocialFriendDetails {
    val root = socialRoot(
        raw,
        setOf(
            "version", "friend", "sharing", "activityUpdatedAt", "recentWorkouts",
            "exerciseRecords", "integrity"
        )
    )
    val friendObject = root.requiredObject("friend")
    friendObject.requireExactKeys(
        setOf(
            "profileId", "displayName", "xp", "level", "workouts", "progressShared",
            "statsAvailable", "progressUpdatedAt"
        )
    )
    val friend = SocialFriendDetailProfile(
        profileId = friendObject.requiredProfileId("profileId"),
        displayName = friendObject.requiredDisplayName("displayName"),
        xp = friendObject.nullableInt("xp", 0, Int.MAX_VALUE),
        level = friendObject.nullableInt("level", 1, Int.MAX_VALUE),
        workouts = friendObject.nullableInt("workouts", 0, Int.MAX_VALUE),
        progressShared = friendObject.requiredBoolean("progressShared"),
        statsAvailable = friendObject.requiredBoolean("statsAvailable"),
        progressUpdatedAt = friendObject.nullableTimestamp("progressUpdatedAt")
    ).also(::requireCoherentFriendStats)
    val sharingObject = root.requiredObject("sharing")
    sharingObject.requireExactKeys(setOf("progress", "recentWorkouts", "records"))
    val sharing = SocialSharing(
        progress = sharingObject.requiredBoolean("progress"),
        recentWorkouts = sharingObject.requiredBoolean("recentWorkouts"),
        records = sharingObject.requiredBoolean("records")
    )
    require(friend.progressShared == sharing.progress) { "Social response is invalid." }
    val recent = root.requiredArray("recentWorkouts", SOCIAL_MAX_RECENT_WORKOUTS)
        .mapObjects(::parseSocialRecentWorkout)
    val records = root.requiredArray("exerciseRecords", SOCIAL_MAX_EXERCISE_RECORDS)
        .mapObjects(::parseSocialExerciseRecord)
    val activityUpdatedAt = root.nullableTimestamp("activityUpdatedAt")
    require(sharing.recentWorkouts || recent.isEmpty()) { "Social response is invalid." }
    require(sharing.records || records.isEmpty()) { "Social response is invalid." }
    require(activityUpdatedAt != null || (recent.isEmpty() && records.isEmpty())) {
        "Social response is invalid."
    }
    require(activityUpdatedAt == null || sharing.recentWorkouts || sharing.records) {
        "Social response is invalid."
    }
    require(records.map(::socialExerciseRecordIdentity).toSet().size == records.size) {
        "Social response is invalid."
    }
    val integrity = root.requiredString("integrity", 32)
    require(integrity == "self_reported") { "Social response is invalid." }
    return SocialFriendDetails(
        friend = friend,
        sharing = sharing,
        activityUpdatedAt = activityUpdatedAt,
        recentWorkouts = recent,
        exerciseRecords = records,
        integrity = integrity
    )
}

internal fun parseSocialSubmittedMutation(raw: String) {
    val root = socialRoot(raw, setOf("version", "result"))
    require(root.requiredString("result", 64) == "submitted_or_unavailable") {
        "Social response is invalid."
    }
}

internal fun parseSocialFriendshipMutation(
    raw: String,
    allowedStatuses: Set<String>
): SocialFriendshipMutation {
    val root = socialRoot(
        raw,
        setOf("version", "friendshipId", "status", "friendshipRevision")
    )
    val status = root.requiredString("status", 16)
    require(status in allowedStatuses) { "Social response is invalid." }
    return SocialFriendshipMutation(
        friendshipId = root.requiredFriendshipId("friendshipId"),
        status = status,
        friendshipRevision = root.requiredRevision("friendshipRevision")
    )
}

internal fun parseSocialBlockMutation(raw: String): SocialBlockMutation {
    val root = socialRoot(raw, setOf("version", "profileId", "blocked"))
    return SocialBlockMutation(
        profileId = root.requiredProfileId("profileId"),
        blocked = root.requiredBoolean("blocked")
    )
}

internal fun parseSocialPrivacyMutation(raw: String): SocialPrivacyMutation {
    val root = socialRoot(raw, setOf("version", "privacy", "settingsRevision"))
    return SocialPrivacyMutation(
        privacy = parseSocialPrivacy(root.requiredObject("privacy")),
        settingsRevision = root.requiredRevision("settingsRevision")
    )
}

internal fun socialWorkoutJson(plan: SharedWorkoutPlan): JSONObject {
    val normalized = SharedWorkoutLink.normalize(plan.exercises)
    requireUniqueSocialWorkoutIdentities(normalized.exercises)
    val exercises = JSONArray()
    normalized.exercises.forEach { exercise ->
        val exerciseObject = JSONObject()
        exercise.catalogKey?.let { exerciseObject.put("catalogKey", it) }
        exerciseObject.put("name", exercise.name)
        exerciseObject.put(
            "sets",
            JSONArray().also { sets ->
                exercise.sets.forEach { set ->
                    sets.put(
                        JSONObject()
                            .put("weight", set.weight)
                            .put("reps", set.reps)
                    )
                }
            }
        )
        exercises.put(exerciseObject)
    }
    return JSONObject()
        .put("version", 1)
        .put("exercises", exercises)
        .also { result ->
            require(result.toString().toByteArray(Charsets.UTF_8).size <= SOCIAL_MAX_INVITE_JSON_BYTES) {
                "Workout invite is too large."
            }
        }
}

internal fun parseSocialWorkoutInbox(raw: String): SocialWorkoutInbox {
    val root = socialRoot(
        raw,
        setOf("version", "pendingIncomingCount", "incoming", "outgoing")
    )
    val incoming = root.requiredArray("incoming", SOCIAL_MAX_WORKOUT_INVITES)
        .mapObjects(::parseSocialIncomingWorkoutInvite)
    val outgoing = root.requiredArray("outgoing", SOCIAL_MAX_WORKOUT_INVITES)
        .mapObjects(::parseSocialOutgoingWorkoutInvite)
    val pendingCount = root.requiredInt("pendingIncomingCount", 0, SOCIAL_MAX_WORKOUT_INVITES)
    require(pendingCount == incoming.count { it.status == "pending" }) {
        "Social response is invalid."
    }
    require(incoming.map { it.inviteId }.toSet().size == incoming.size) {
        "Social response is invalid."
    }
    require(outgoing.map { it.inviteId }.toSet().size == outgoing.size) {
        "Social response is invalid."
    }
    require((incoming.map { it.inviteId } + outgoing.map { it.inviteId }).toSet().size ==
        incoming.size + outgoing.size) { "Social response is invalid." }
    return SocialWorkoutInbox(
        pendingIncomingCount = pendingCount,
        incoming = incoming,
        outgoing = outgoing
    )
}

internal fun parseSocialWorkoutInviteMutation(raw: String): SocialWorkoutInviteMutation {
    val root = socialRoot(
        raw,
        setOf("version", "inviteId", "status", "inviteRevision", "workout")
    )
    val status = root.requiredString("status", 16)
    require(status in setOf("accepted", "declined")) { "Social response is invalid." }
    val workout = if (root.isNull("workout")) {
        null
    } else {
        parseSocialWorkoutObject(root.requiredObject("workout"))
    }
    require((status == "accepted") == (workout != null)) { "Social response is invalid." }
    return SocialWorkoutInviteMutation(
        inviteId = root.requiredWorkoutInviteId("inviteId"),
        status = status,
        inviteRevision = root.requiredRevision("inviteRevision"),
        workout = workout
    )
}

internal fun parseSocialWorkoutInviteCancellation(raw: String): SocialWorkoutInviteCancellation {
    val root = socialRoot(raw, setOf("version", "inviteId", "status", "inviteRevision"))
    require(root.requiredString("status", 16) == "cancelled") { "Social response is invalid." }
    return SocialWorkoutInviteCancellation(
        inviteId = root.requiredWorkoutInviteId("inviteId"),
        status = "cancelled",
        inviteRevision = root.requiredRevision("inviteRevision")
    )
}

private fun parseSocialIncomingWorkoutInvite(raw: JSONObject): SocialIncomingWorkoutInvite {
    raw.requireExactKeys(
        setOf(
            "inviteId", "profileId", "displayName", "status", "inviteRevision", "createdAt",
            "expiresAt", "respondedAt", "summary", "workout"
        )
    )
    val status = raw.requiredIncomingWorkoutInviteStatus("status")
    val summary = parseSocialWorkoutInviteSummary(raw.requiredObject("summary"))
    val workout = parseSocialWorkoutObject(raw.requiredObject("workout"))
    val respondedAt = raw.nullableTimestamp("respondedAt")
    require((status == "pending") == (respondedAt == null)) {
        "Social response is invalid."
    }
    require(
        summary.exerciseCount == workout.exerciseCount &&
            summary.setCount == workout.setCount &&
            summary.exerciseNames == workout.exercises.map { it.name }
    ) { "Social response is invalid." }
    return SocialIncomingWorkoutInvite(
        inviteId = raw.requiredWorkoutInviteId("inviteId"),
        profileId = raw.requiredProfileId("profileId"),
        displayName = raw.requiredDisplayName("displayName"),
        status = status,
        inviteRevision = raw.requiredRevision("inviteRevision"),
        createdAt = raw.requiredTimestamp("createdAt"),
        expiresAt = raw.requiredTimestamp("expiresAt"),
        respondedAt = respondedAt,
        summary = summary,
        workout = workout
    )
}

private fun parseSocialOutgoingWorkoutInvite(raw: JSONObject): SocialOutgoingWorkoutInvite {
    raw.requireExactKeys(
        setOf(
            "inviteId", "profileId", "displayName", "status", "inviteRevision", "createdAt",
            "expiresAt", "respondedAt", "summary"
        )
    )
    val status = raw.requiredWorkoutInviteStatus("status")
    val respondedAt = raw.nullableTimestamp("respondedAt")
    require((status == "pending") == (respondedAt == null)) {
        "Social response is invalid."
    }
    return SocialOutgoingWorkoutInvite(
        inviteId = raw.requiredWorkoutInviteId("inviteId"),
        profileId = raw.requiredProfileId("profileId"),
        displayName = raw.requiredDisplayName("displayName"),
        status = status,
        inviteRevision = raw.requiredRevision("inviteRevision"),
        createdAt = raw.requiredTimestamp("createdAt"),
        expiresAt = raw.requiredTimestamp("expiresAt"),
        respondedAt = respondedAt,
        summary = parseSocialWorkoutInviteSummary(raw.requiredObject("summary"))
    )
}

private fun parseSocialWorkoutInviteSummary(raw: JSONObject): SocialWorkoutInviteSummary {
    raw.requireExactKeys(setOf("exerciseCount", "setCount", "exerciseNames"))
    val exerciseCount = raw.requiredInt("exerciseCount", 1, SharedWorkoutLink.MAX_EXERCISES)
    val names = raw.requiredArray("exerciseNames", SharedWorkoutLink.MAX_EXERCISES)
        .mapStrings { name -> requireSafeSocialExerciseName(name) }
    require(names.size == exerciseCount) { "Social response is invalid." }
    return SocialWorkoutInviteSummary(
        exerciseCount = exerciseCount,
        setCount = raw.requiredInt("setCount", 1, SharedWorkoutLink.MAX_TOTAL_SETS),
        exerciseNames = names
    )
}

private fun parseSocialWorkoutObject(raw: JSONObject): SharedWorkoutPlan {
    require(raw.toString().toByteArray(Charsets.UTF_8).size <= SOCIAL_MAX_INVITE_JSON_BYTES) {
        "Social response is invalid."
    }
    raw.requireExactKeys(setOf("version", "exercises"))
    require(raw.requiredInt("version", 1, 1) == 1) { "Social response is invalid." }
    val exerciseObjects = raw.requiredArray("exercises", SharedWorkoutLink.MAX_EXERCISES)
    require(exerciseObjects.length() >= 1) { "Social response is invalid." }
    val exercises = exerciseObjects.mapObjects { exercise ->
        val keys = exercise.keys().asSequence().toSet()
        require(keys == setOf("name", "sets") || keys == setOf("catalogKey", "name", "sets")) {
            "Social response is invalid."
        }
        val sets = exercise.requiredArray("sets", SharedWorkoutLink.MAX_SETS_PER_EXERCISE)
        require(sets.length() >= 1) { "Social response is invalid." }
        SharedWorkoutExercise(
            catalogKey = if (exercise.has("catalogKey")) {
                exercise.requiredCatalogKey("catalogKey")
            } else {
                null
            },
            name = requireSafeSocialExerciseName(exercise.opt("name")),
            sets = sets.mapObjects { set ->
                set.requireExactKeys(setOf("weight", "reps"))
                SharedWorkoutSet(
                    weight = set.requiredDouble("weight", 0.0, SharedWorkoutLink.MAX_WEIGHT),
                    reps = set.requiredInt("reps", 1, SharedWorkoutLink.MAX_REPS)
                )
            }
        )
    }
    requireUniqueSocialWorkoutIdentities(exercises)
    return SharedWorkoutPlan(exercises)
}

private fun requireUniqueSocialWorkoutIdentities(exercises: List<SharedWorkoutExercise>) {
    val names = linkedSetOf<String>()
    val catalogKeys = linkedSetOf<String>()
    exercises.forEach { exercise ->
        val portableName = exercise.name.normalizedExerciseName()
        require(portableName.isNotEmpty() && names.add(portableName)) {
            "Social response is invalid."
        }
        exercise.catalogKey?.let { catalogKey ->
            require(catalogKeys.add(catalogKey)) { "Social response is invalid." }
        }
    }
}

private fun parseSocialPrivacy(raw: JSONObject): SocialPrivacy {
    raw.requireExactKeys(
        setOf("allowRequests", "shareProgress", "shareRecentWorkouts", "shareRecords")
    )
    return SocialPrivacy(
        allowRequests = raw.requiredBoolean("allowRequests"),
        shareProgress = raw.requiredBoolean("shareProgress"),
        shareRecentWorkouts = raw.requiredBoolean("shareRecentWorkouts"),
        shareRecords = raw.requiredBoolean("shareRecords")
    )
}

private fun parseSocialFriend(raw: JSONObject): SocialFriend {
    raw.requireExactKeys(
        setOf(
            "friendshipId", "profileId", "displayName", "xp", "level", "workouts",
            "progressShared", "statsAvailable", "progressUpdatedAt", "friendshipRevision", "status"
        )
    )
    require(raw.requiredString("status", 16) == "accepted") { "Social response is invalid." }
    return SocialFriend(
        friendshipId = raw.requiredFriendshipId("friendshipId"),
        profileId = raw.requiredProfileId("profileId"),
        displayName = raw.requiredDisplayName("displayName"),
        xp = raw.nullableInt("xp", 0, Int.MAX_VALUE),
        level = raw.nullableInt("level", 1, Int.MAX_VALUE),
        workouts = raw.nullableInt("workouts", 0, Int.MAX_VALUE),
        progressShared = raw.requiredBoolean("progressShared"),
        statsAvailable = raw.requiredBoolean("statsAvailable"),
        progressUpdatedAt = raw.nullableTimestamp("progressUpdatedAt"),
        friendshipRevision = raw.requiredRevision("friendshipRevision")
    ).also(::requireCoherentFriendStats)
}

private fun parseSocialFriendRequest(raw: JSONObject, expectedStatus: String): SocialFriendRequest {
    raw.requireExactKeys(
        setOf(
            "friendshipId", "profileId", "displayName", "requestedAt",
            "friendshipRevision", "status"
        )
    )
    require(raw.requiredString("status", 16) == expectedStatus) { "Social response is invalid." }
    return SocialFriendRequest(
        friendshipId = raw.requiredFriendshipId("friendshipId"),
        profileId = raw.requiredProfileId("profileId"),
        displayName = raw.requiredDisplayName("displayName"),
        requestedAt = raw.requiredTimestamp("requestedAt"),
        friendshipRevision = raw.requiredRevision("friendshipRevision")
    )
}

private fun parseSocialBlockedProfile(raw: JSONObject): SocialBlockedProfile {
    raw.requireExactKeys(setOf("profileId", "displayName", "blockedAt"))
    return SocialBlockedProfile(
        profileId = raw.requiredProfileId("profileId"),
        displayName = raw.requiredDisplayName("displayName"),
        blockedAt = raw.requiredTimestamp("blockedAt")
    )
}

private fun parseSocialRecentWorkout(raw: JSONObject): SocialRecentWorkout {
    raw.requireExactKeys(setOf("workoutDay", "exerciseCount", "setCount", "exercises"))
    val exerciseCount = raw.requiredInt(
        "exerciseCount",
        1,
        WorkoutDataLimits.MAX_EXERCISES_PER_SESSION
    )
    val labels = raw.requiredArray("exercises", SOCIAL_MAX_WORKOUT_EXERCISES)
        .mapObjects(::parseSocialWorkoutExerciseLabel)
    require(labels.size == minOf(exerciseCount, SOCIAL_MAX_WORKOUT_EXERCISES)) {
        "Social response is invalid."
    }
    return SocialRecentWorkout(
        workoutDay = raw.requiredWorkoutDay("workoutDay"),
        exerciseCount = exerciseCount,
        setCount = raw.requiredInt(
            "setCount",
            1,
            WorkoutDataLimits.MAX_EXERCISES_PER_SESSION *
                WorkoutDataLimits.MAX_SETS_PER_EXERCISE
        ),
        exercises = labels
    )
}

private fun parseSocialWorkoutExerciseLabel(raw: JSONObject): SocialWorkoutExerciseLabel {
    raw.requireExactKeys(setOf("catalogKey", "name"))
    return SocialWorkoutExerciseLabel(
        catalogKey = raw.nullableCatalogKey("catalogKey"),
        name = raw.requiredExerciseName("name")
    )
}

private fun parseSocialExerciseRecord(raw: JSONObject): SocialExerciseRecord {
    raw.requireExactKeys(
        setOf("catalogKey", "name", "bestWeightKg", "bestReps", "workoutCount", "lastWorkoutDay")
    )
    return SocialExerciseRecord(
        catalogKey = raw.nullableCatalogKey("catalogKey"),
        name = raw.requiredExerciseName("name"),
        bestWeightKg = raw.requiredDouble("bestWeightKg", 0.0, SharedWorkoutLink.MAX_WEIGHT),
        bestReps = raw.requiredInt("bestReps", 1, SharedWorkoutLink.MAX_REPS),
        workoutCount = raw.requiredInt("workoutCount", 1, WorkoutDataLimits.MAX_SESSIONS),
        lastWorkoutDay = raw.requiredWorkoutDay("lastWorkoutDay")
    )
}

private fun socialExerciseRecordIdentity(record: SocialExerciseRecord): String =
    record.catalogKey?.let { "catalog:$it" }
        ?: "name:${record.name.normalizedExerciseName()}"

private fun requireCoherentSelfStats(profile: SocialSelfProfile) {
    val fields = listOf(profile.xp, profile.level, profile.workouts)
    require(if (profile.statsAvailable) fields.all { it != null } else fields.all { it == null }) {
        "Social response is invalid."
    }
    require(profile.statsAvailable == (profile.progressUpdatedAt != null)) {
        "Social response is invalid."
    }
}

private fun requireCoherentFriendStats(profile: SocialFriend) {
    requireCoherentFriendStats(
        profile.progressShared,
        profile.statsAvailable,
        profile.xp,
        profile.level,
        profile.workouts,
        profile.progressUpdatedAt
    )
}

private fun requireCoherentFriendStats(profile: SocialFriendDetailProfile) {
    requireCoherentFriendStats(
        profile.progressShared,
        profile.statsAvailable,
        profile.xp,
        profile.level,
        profile.workouts,
        profile.progressUpdatedAt
    )
}

private fun requireCoherentFriendStats(
    progressShared: Boolean,
    statsAvailable: Boolean,
    xp: Int?,
    level: Int?,
    workouts: Int?,
    progressUpdatedAt: String?
) {
    val fields = listOf(xp, level, workouts)
    require(if (statsAvailable) fields.all { it != null } else fields.all { it == null }) {
        "Social response is invalid."
    }
    require(progressShared || !statsAvailable) { "Social response is invalid." }
    require(statsAvailable == (progressUpdatedAt != null)) { "Social response is invalid." }
}

private fun requireUniqueSocialDashboardIds(dashboard: SocialDashboard) {
    require(dashboard.friends.map { it.friendshipId }.toSet().size == dashboard.friends.size)
    require(dashboard.friends.map { it.profileId }.toSet().size == dashboard.friends.size)
    require(dashboard.incoming.map { it.friendshipId }.toSet().size == dashboard.incoming.size)
    require(dashboard.outgoing.map { it.friendshipId }.toSet().size == dashboard.outgoing.size)
    require(dashboard.blocked.map { it.profileId }.toSet().size == dashboard.blocked.size)
    val visibleProfiles = buildList {
        addAll(dashboard.friends.map { it.profileId })
        addAll(dashboard.incoming.map { it.profileId })
        addAll(dashboard.outgoing.map { it.profileId })
        addAll(dashboard.blocked.map { it.profileId })
    }
    require(visibleProfiles.toSet().size == visibleProfiles.size)
    require(dashboard.self.profileId !in visibleProfiles)
}

private fun socialRoot(raw: String, expectedKeys: Set<String>): JSONObject {
    require(raw.toByteArray(Charsets.UTF_8).size <= 256 * 1_024) { "Social response is invalid." }
    val root = runCatching { JSONObject(raw) }
        .getOrElse { throw IllegalArgumentException("Social response is invalid.") }
    root.requireExactKeys(expectedKeys)
    require(root.requiredInt("version", SOCIAL_CONTRACT_VERSION, SOCIAL_CONTRACT_VERSION) ==
        SOCIAL_CONTRACT_VERSION) { "Social response is invalid." }
    return root
}

private fun JSONObject.requireExactKeys(expected: Set<String>) {
    require(keys().asSequence().toSet() == expected) { "Social response is invalid." }
}

private fun JSONObject.requiredObject(key: String): JSONObject = opt(key) as? JSONObject
    ?: throw IllegalArgumentException("Social response is invalid.")

private fun JSONObject.requiredArray(key: String, max: Int): JSONArray {
    val value = opt(key) as? JSONArray ?: throw IllegalArgumentException("Social response is invalid.")
    require(value.length() in 0..max) { "Social response is invalid." }
    return value
}

private fun <T> JSONArray.mapObjects(mapper: (JSONObject) -> T): List<T> =
    List(length()) { index ->
        val value = opt(index) as? JSONObject
            ?: throw IllegalArgumentException("Social response is invalid.")
        mapper(value)
    }

private fun <T> JSONArray.mapStrings(mapper: (String) -> T): List<T> =
    List(length()) { index ->
        val value = opt(index) as? String
            ?: throw IllegalArgumentException("Social response is invalid.")
        mapper(value)
    }

private fun JSONObject.requiredString(key: String, maxCodePoints: Int): String {
    val value = opt(key) as? String ?: throw IllegalArgumentException("Social response is invalid.")
    require(
        value.isNotEmpty() &&
            value.codePointCount(0, value.length) <= maxCodePoints &&
            !value.hasUnsafeSocialScalar()
    ) { "Social response is invalid." }
    return value
}

private fun JSONObject.requiredDisplayName(key: String): String {
    val value = requiredString(key, 40)
    require(value == value.trim(' ') && value.toByteArray(Charsets.UTF_8).size <= 160) {
        "Social response is invalid."
    }
    return value
}

private fun JSONObject.requiredExerciseName(key: String): String {
    val value = requiredString(key, SharedWorkoutLink.MAX_NAME_CODE_POINTS)
    require(value == value.trim(' ') && value.toByteArray(Charsets.UTF_8).size <=
        SharedWorkoutLink.MAX_NAME_UTF8_BYTES) { "Social response is invalid." }
    return value
}

private fun JSONObject.requiredProfileId(key: String): String = requiredString(key, 34)
    .also { require(isValidSocialProfileId(it)) { "Social response is invalid." } }

private fun JSONObject.requiredShortFriendCode(key: String): String = requiredString(key, 14)
    .also { require(isValidSocialShortFriendCode(it)) { "Social response is invalid." } }

private fun JSONObject.requiredFriendshipId(key: String): String = requiredString(key, 34)
    .also { require(isValidSocialFriendshipId(it)) { "Social response is invalid." } }

private fun JSONObject.requiredWorkoutInviteId(key: String): String = requiredString(key, 35)
    .also { require(isValidSocialWorkoutInviteId(it)) { "Social response is invalid." } }

private fun JSONObject.requiredCatalogKey(key: String): String =
    requiredString(key, SharedWorkoutLink.MAX_CATALOG_KEY_CHARACTERS).also {
        require(socialCatalogKeyPattern.matches(it)) { "Social response is invalid." }
    }

private fun JSONObject.requiredWorkoutInviteStatus(key: String): String =
    requiredString(key, 16).also {
        require(it in setOf("pending", "accepted", "declined", "cancelled", "expired")) {
            "Social response is invalid."
        }
    }

private fun JSONObject.requiredIncomingWorkoutInviteStatus(key: String): String =
    requiredString(key, 16).also {
        require(it in setOf("pending", "accepted")) { "Social response is invalid." }
    }

private fun JSONObject.requiredBoolean(key: String): Boolean = opt(key) as? Boolean
    ?: throw IllegalArgumentException("Social response is invalid.")

private fun JSONObject.requiredRevision(key: String): Int = requiredInt(key, 1, Int.MAX_VALUE)

private fun JSONObject.requiredInt(key: String, minimum: Int, maximum: Int): Int {
    val raw = opt(key) as? Number ?: throw IllegalArgumentException("Social response is invalid.")
    val value = raw.toDouble()
    require(value.isFinite() && value % 1.0 == 0.0 && value in minimum.toDouble()..maximum.toDouble()) {
        "Social response is invalid."
    }
    return value.toInt()
}

private fun JSONObject.nullableInt(key: String, minimum: Int, maximum: Int): Int? {
    if (!has(key) || isNull(key)) {
        require(has(key)) { "Social response is invalid." }
        return null
    }
    return requiredInt(key, minimum, maximum)
}

private fun JSONObject.requiredDouble(key: String, minimum: Double, maximum: Double): Double {
    val raw = opt(key) as? Number ?: throw IllegalArgumentException("Social response is invalid.")
    val value = raw.toDouble()
    require(value.isFinite() && value in minimum..maximum) { "Social response is invalid." }
    return value
}

private fun JSONObject.requiredTimestamp(key: String): String = requiredString(key, 64)
    .also { require(isValidRemoteStateRevision(it)) { "Social response is invalid." } }

private fun JSONObject.nullableTimestamp(key: String): String? {
    if (!has(key) || isNull(key)) {
        require(has(key)) { "Social response is invalid." }
        return null
    }
    return requiredTimestamp(key)
}

private fun JSONObject.requiredWorkoutDay(key: String): String = requiredString(key, 10).also {
    require(socialWorkoutDayPattern.matches(it) && runCatching { LocalDate.parse(it) }.isSuccess) {
        "Social response is invalid."
    }
}

private fun JSONObject.nullableCatalogKey(key: String): String? {
    if (!has(key) || isNull(key)) {
        require(has(key)) { "Social response is invalid." }
        return null
    }
    val value = requiredString(key, SharedWorkoutLink.MAX_CATALOG_KEY_CHARACTERS)
    require(socialCatalogKeyPattern.matches(value)) { "Social response is invalid." }
    return value
}

private fun requireSafeSocialExerciseName(raw: Any?): String {
    val value = raw as? String ?: throw IllegalArgumentException("Social response is invalid.")
    require(
        value.isNotEmpty() &&
            value == value.trim(' ') &&
            value.codePointCount(0, value.length) <= SharedWorkoutLink.MAX_NAME_CODE_POINTS &&
            value.toByteArray(Charsets.UTF_8).size <= SharedWorkoutLink.MAX_NAME_UTF8_BYTES &&
            !value.hasUnsafeSocialScalar()
    ) { "Social response is invalid." }
    return value
}

private fun String.hasUnsafeSocialScalar(): Boolean {
    var index = 0
    while (index < length) {
        val codePoint = Character.codePointAt(this, index)
        when (Character.getType(codePoint)) {
            Character.CONTROL.toInt(),
            Character.FORMAT.toInt(),
            Character.LINE_SEPARATOR.toInt(),
            Character.PARAGRAPH_SEPARATOR.toInt() -> return true
        }
        index += Character.charCount(codePoint)
    }
    return false
}
