package com.example.gymapp.auth

import com.example.gymapp.data.repository.SharedWorkoutLink
import com.example.gymapp.data.repository.SharedWorkoutPlan
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.time.OffsetDateTime

internal const val LIVE_WORKOUT_CONTRACT_VERSION = 1
internal const val LIVE_MAX_INBOX_INVITATIONS = 25
internal const val LIVE_MAX_INBOX_ROOMS = 5
internal const val LIVE_MAX_PARTICIPANTS = 2

private val liveRoomIdPattern = Regex("^lr_[0-9a-f]{32}$")
private val liveExerciseIdPattern = Regex("^e_[0-9]{2}$")
private val liveSetIdPattern = Regex("^s_[0-9]{2}_[0-9]{2}$")

internal data class LiveWorkoutSummary(
    val exerciseCount: Int,
    val setCount: Int,
    val exerciseNames: List<String>
)

internal data class LiveProfile(
    val profileId: String,
    val displayName: String
)

internal data class LiveInvitation(
    val roomId: String,
    val status: String,
    val roomRevision: Int,
    val createdAt: String,
    val inviteExpiresAt: String,
    val summary: LiveWorkoutSummary,
    val owner: LiveProfile
)

internal data class LiveInboxRoom(
    val roomId: String,
    val status: String,
    val roomRevision: Int,
    val role: String,
    val memberState: String,
    val membershipRevision: Int,
    val createdAt: String,
    val startedAt: String?,
    val activeExpiresAt: String?,
    val summary: LiveWorkoutSummary,
    val peer: LiveProfile
)

internal data class LiveWorkoutInbox(
    val invitations: List<LiveInvitation>,
    val rooms: List<LiveInboxRoom>
)

internal data class LiveWorkoutRealtimeSignal(
    val kind: String,
    val roomId: String,
    val roomRevision: Int
)

internal data class LiveCanonicalSet(
    val setId: String,
    val weight: Double,
    val reps: Int
)

internal data class LiveCanonicalExercise(
    val exerciseId: String,
    val name: String,
    val catalogKey: String?,
    val sets: List<LiveCanonicalSet>
)

internal data class LiveCanonicalPlan(
    val exercises: List<LiveCanonicalExercise>
) {
    val setIds: Set<String>
        get() = exercises.flatMap { exercise -> exercise.sets.map(LiveCanonicalSet::setId) }.toSet()
}

internal data class LiveCompletedSet(
    val setId: String,
    val weight: Double,
    val reps: Int,
    val completedAt: String
)

internal data class LiveProgress(
    val revision: Int,
    val completedSets: List<LiveCompletedSet>,
    val undoableSetId: String?,
    val finishedAt: String?
)

internal data class LiveParticipant(
    val isSelf: Boolean,
    val profile: LiveProfile,
    val role: String,
    val state: String,
    val membershipRevision: Int,
    val joinedAt: String?,
    val finishedAt: String?,
    val departedAt: String?,
    val progress: LiveProgress?
)

internal data class LiveRoomSnapshot(
    val roomId: String,
    val status: String,
    val roomRevision: Int,
    val closeReason: String?,
    val createdAt: String,
    val inviteExpiresAt: String,
    val startedAt: String?,
    val activeExpiresAt: String?,
    val endedAt: String?,
    val summary: LiveWorkoutSummary
)

internal data class LiveWorkoutSnapshot(
    val room: LiveRoomSnapshot,
    val plan: LiveCanonicalPlan,
    val participants: List<LiveParticipant>
) {
    val self: LiveParticipant
        get() = participants.single(LiveParticipant::isSelf)
    val peer: LiveParticipant
        get() = participants.single { !it.isSelf }
}

internal data class LiveSendInviteResult(
    val result: String,
    val roomId: String?,
    val status: String?,
    val roomRevision: Int?
)

internal data class LiveRespondInviteResult(
    val result: String,
    val roomId: String,
    val status: String,
    val roomRevision: Int,
    val membershipRevision: Int,
    val endedAt: String?
)

internal data class LiveStartedResult(
    val roomId: String,
    val roomRevision: Int,
    val startedAt: String,
    val activeExpiresAt: String,
    val myProgressRevision: Int
)

internal data class LiveClosedResult(
    val roomId: String,
    val roomRevision: Int,
    val endedAt: String
)

internal sealed interface LiveStartResult {
    data class Started(val value: LiveStartedResult) : LiveStartResult
    data class Closed(val value: LiveClosedResult) : LiveStartResult
}

internal data class LiveAppliedResult(
    val roomId: String,
    val roomRevision: Int,
    val progressRevision: Int,
    val kind: String,
    val setId: String,
    val completedAt: String?
)

internal sealed interface LiveApplyResult {
    data class Applied(val value: LiveAppliedResult) : LiveApplyResult
    data class Closed(val value: LiveClosedResult) : LiveApplyResult
}

internal data class LiveFinishedResult(
    val roomId: String,
    val status: String,
    val roomRevision: Int,
    val progressRevision: Int,
    val membershipRevision: Int,
    val finishedAt: String
)

internal sealed interface LiveFinishResult {
    data class Finished(val value: LiveFinishedResult) : LiveFinishResult
    data class Closed(val value: LiveClosedResult) : LiveFinishResult
}

internal data class LiveEndedResult(
    val result: String,
    val roomId: String,
    val roomRevision: Int,
    val membershipRevision: Int,
    val endedAt: String
)

internal fun isValidLiveRoomId(value: String): Boolean = liveRoomIdPattern.matches(value)

internal fun liveSendWorkoutJson(plan: SharedWorkoutPlan): JSONObject = socialWorkoutJson(plan)

internal fun liveGatewayRequestJson(action: String, payload: JSONObject): String {
    require(action in setOf(
        "live_inbox", "live_send_invite", "live_respond_invite", "live_start", "live_snapshot",
        "live_apply", "live_finish", "live_leave", "live_cancel"
    )) { "Live workout action is invalid." }
    require(payload.toString().toByteArray(Charsets.UTF_8).size <= 64 * 1_024) {
        "Live workout request is too large."
    }
    return JSONObject()
        .put("version", LIVE_WORKOUT_CONTRACT_VERSION)
        .put("action", action)
        .put("payload", payload)
        .toString()
}

internal fun unwrapLiveGatewaySuccess(raw: String): String {
    require(raw.toByteArray(Charsets.UTF_8).size <= 256 * 1_024) {
        "Live workout response is invalid."
    }
    val wrapper = runCatching { parseStrictLiveObject(raw) }
        .getOrElse { throw IllegalArgumentException("Live workout response is invalid.") }
    wrapper.liveExactKeys(setOf("version", "result"))
    require(wrapper.liveInt("version", 1, 1) == LIVE_WORKOUT_CONTRACT_VERSION) {
        "Live workout response is invalid."
    }
    val result = wrapper.liveObject("result").toString()
    require(result.toByteArray(Charsets.UTF_8).size <= 256 * 1_024) {
        "Live workout response is invalid."
    }
    return result
}

internal fun parseLiveWorkoutInbox(raw: String): LiveWorkoutInbox {
    val root = liveRoot(raw, setOf("version", "invitations", "rooms"))
    val invitations = root.liveArray("invitations", LIVE_MAX_INBOX_INVITATIONS)
        .liveObjects(::parseLiveInvitation)
    val rooms = root.liveArray("rooms", LIVE_MAX_INBOX_ROOMS).liveObjects(::parseLiveInboxRoom)
    require((invitations.map { it.roomId } + rooms.map { it.roomId }).toSet().size ==
        invitations.size + rooms.size) { "Live workout response is invalid." }
    return LiveWorkoutInbox(invitations, rooms)
}

internal fun parseLiveWorkoutRealtimeSignal(raw: String): LiveWorkoutRealtimeSignal {
    val root = liveRoot(raw, setOf("version", "kind", "roomId", "roomRevision"))
    val kind = root.liveString("kind", 32)
    require(kind in setOf(
        "invite", "joined", "started", "progress", "participant_finished", "room_closed"
    )) { "Live workout response is invalid." }
    return LiveWorkoutRealtimeSignal(
        kind = kind,
        roomId = root.liveRoomId("roomId"),
        roomRevision = root.liveRevision("roomRevision")
    )
}

internal fun parseLiveSendInviteResult(raw: String): LiveSendInviteResult {
    val root = liveRoot(
        raw,
        setOf("version", "result", "roomId", "status", "roomRevision")
    )
    val result = root.liveString("result", 64)
    require(result in setOf("submitted", "submitted_or_unavailable")) {
        "Live workout response is invalid."
    }
    if (result == "submitted_or_unavailable") {
        require(root.isNull("roomId") && root.isNull("status") && root.isNull("roomRevision")) {
            "Live workout response is invalid."
        }
        return LiveSendInviteResult(result, null, null, null)
    }
    val roomId = root.liveRoomId("roomId")
    val status = root.liveString("status", 16)
    require(status == "waiting") { "Live workout response is invalid." }
    return LiveSendInviteResult(result, roomId, status, root.liveRevision("roomRevision"))
}

internal fun parseLiveRespondInviteResult(raw: String): LiveRespondInviteResult {
    val result = liveResultDiscriminator(raw)
    val expected = if (result == "joined") {
        setOf("version", "result", "roomId", "status", "roomRevision", "membershipRevision")
    } else {
        setOf(
            "version", "result", "roomId", "status", "roomRevision", "membershipRevision",
            "endedAt"
        )
    }
    val root = liveRoot(raw, expected)
    require(result in setOf("joined", "declined")) { "Live workout response is invalid." }
    val status = root.liveString("status", 16)
    // `ready` is the legacy response emitted by the atomic start-on-accept RPC even though
    // its committed room is already active. Callers must still restore from a fresh snapshot.
    require((result == "joined" && status in setOf("active", "ready")) ||
        (result == "declined" && status == "cancelled")) {
        "Live workout response is invalid."
    }
    return LiveRespondInviteResult(
        result = result,
        roomId = root.liveRoomId("roomId"),
        status = status,
        roomRevision = root.liveRevision("roomRevision"),
        membershipRevision = root.liveRevision("membershipRevision"),
        endedAt = if (result == "declined") root.liveTimestamp("endedAt") else null
    )
}

internal fun parseLiveStartResult(raw: String): LiveStartResult {
    if (liveResultDiscriminator(raw) == "closed") {
        return LiveStartResult.Closed(parseLiveClosed(raw))
    }
    val root = liveRoot(
        raw,
        setOf(
            "version", "result", "roomId", "status", "roomRevision", "startedAt",
            "activeExpiresAt", "myProgressRevision"
        )
    )
    require(root.liveString("result", 16) == "started" &&
        root.liveString("status", 16) == "active") { "Live workout response is invalid." }
    return LiveStartResult.Started(
        LiveStartedResult(
            roomId = root.liveRoomId("roomId"),
            roomRevision = root.liveRevision("roomRevision"),
            startedAt = root.liveTimestamp("startedAt"),
            activeExpiresAt = root.liveTimestamp("activeExpiresAt"),
            myProgressRevision = root.liveRevision("myProgressRevision")
        )
    )
}

internal fun parseLiveWorkoutSnapshot(raw: String): LiveWorkoutSnapshot {
    val root = liveRoot(raw, setOf("version", "room", "plan", "participants"))
    val room = parseLiveRoomSnapshot(root.liveObject("room"))
    val plan = parseLivePlan(root.liveObject("plan"))
    val participants = root.liveArray("participants", LIVE_MAX_PARTICIPANTS)
        .also { require(it.length() == LIVE_MAX_PARTICIPANTS) { "Live workout response is invalid." } }
        .liveObjects(::parseLiveParticipant)
    require(participants.count(LiveParticipant::isSelf) == 1) {
        "Live workout response is invalid."
    }
    require(participants.map { it.profile.profileId }.toSet().size == participants.size) {
        "Live workout response is invalid."
    }
    require(participants.map { it.role }.toSet() == setOf("owner", "participant")) {
        "Live workout response is invalid."
    }
    val planSetIds = plan.setIds
    participants.mapNotNull(LiveParticipant::progress).forEach { progress ->
        require(progress.completedSets.all { it.setId in planSetIds } &&
            (progress.undoableSetId == null || progress.undoableSetId in planSetIds)) {
            "Live workout response is invalid."
        }
    }
    if (room.status in setOf("waiting", "ready")) {
        require(participants.all { it.progress == null }) { "Live workout response is invalid." }
    }
    if (room.status in setOf("active", "completed")) {
        require(participants.all { it.progress != null }) { "Live workout response is invalid." }
    }
    when (room.status) {
        "waiting" -> require(
            participants.single { it.role == "owner" }.state == "joined" &&
                participants.single { it.role == "participant" }.state == "invited"
        ) { "Live workout response is invalid." }
        "ready" -> require(participants.all { it.state == "joined" }) {
            "Live workout response is invalid."
        }
        "active" -> require(participants.all { it.state in setOf("joined", "finished") }) {
            "Live workout response is invalid."
        }
        "completed" -> require(participants.all { it.state == "finished" }) {
            "Live workout response is invalid."
        }
    }
    require(room.summary.exerciseCount == plan.exercises.size &&
        room.summary.setCount == plan.setIds.size &&
        room.summary.exerciseNames == plan.exercises.map { it.name }) {
        "Live workout response is invalid."
    }
    return LiveWorkoutSnapshot(room, plan, participants)
}

internal fun parseLiveApplyResult(raw: String): LiveApplyResult {
    if (liveResultDiscriminator(raw) == "closed") {
        return LiveApplyResult.Closed(parseLiveClosed(raw))
    }
    val root = liveRoot(
        raw,
        setOf(
            "version", "result", "roomId", "roomRevision", "progressRevision", "kind",
            "setId", "completedAt"
        )
    )
    require(root.liveString("result", 16) == "applied") { "Live workout response is invalid." }
    val kind = root.liveString("kind", 32)
    require(kind in setOf("complete_set", "undo_set")) { "Live workout response is invalid." }
    val completedAt = root.liveNullableTimestamp("completedAt")
    require((kind == "complete_set") == (completedAt != null)) {
        "Live workout response is invalid."
    }
    return LiveApplyResult.Applied(
        LiveAppliedResult(
            roomId = root.liveRoomId("roomId"),
            roomRevision = root.liveRevision("roomRevision"),
            progressRevision = root.liveRevision("progressRevision"),
            kind = kind,
            setId = root.liveSetId("setId"),
            completedAt = completedAt
        )
    )
}

internal fun parseLiveFinishResult(raw: String): LiveFinishResult {
    if (liveResultDiscriminator(raw) == "closed") {
        return LiveFinishResult.Closed(parseLiveClosed(raw))
    }
    val root = liveRoot(
        raw,
        setOf(
            "version", "result", "roomId", "status", "roomRevision", "progressRevision",
            "membershipRevision", "finishedAt"
        )
    )
    require(root.liveString("result", 16) == "finished") { "Live workout response is invalid." }
    val status = root.liveString("status", 16)
    require(status in setOf("active", "completed")) { "Live workout response is invalid." }
    return LiveFinishResult.Finished(
        LiveFinishedResult(
            roomId = root.liveRoomId("roomId"),
            status = status,
            roomRevision = root.liveRevision("roomRevision"),
            progressRevision = root.liveRevision("progressRevision"),
            membershipRevision = root.liveRevision("membershipRevision"),
            finishedAt = root.liveTimestamp("finishedAt")
        )
    )
}

internal fun parseLiveEndedResult(raw: String, expectedResult: String): LiveEndedResult {
    require(expectedResult in setOf("left", "cancelled")) { "Live workout response is invalid." }
    val root = liveRoot(
        raw,
        setOf(
            "version", "result", "roomId", "status", "roomRevision", "membershipRevision",
            "endedAt"
        )
    )
    require(root.liveString("result", 16) == expectedResult &&
        root.liveString("status", 16) == "cancelled") { "Live workout response is invalid." }
    return LiveEndedResult(
        result = expectedResult,
        roomId = root.liveRoomId("roomId"),
        roomRevision = root.liveRevision("roomRevision"),
        membershipRevision = root.liveRevision("membershipRevision"),
        endedAt = root.liveTimestamp("endedAt")
    )
}

private fun parseLiveInvitation(raw: JSONObject): LiveInvitation {
    raw.liveExactKeys(
        setOf(
            "roomId", "status", "roomRevision", "createdAt", "inviteExpiresAt", "summary",
            "owner"
        )
    )
    require(raw.liveString("status", 16) == "waiting") { "Live workout response is invalid." }
    return LiveInvitation(
        roomId = raw.liveRoomId("roomId"),
        status = "waiting",
        roomRevision = raw.liveRevision("roomRevision"),
        createdAt = raw.liveTimestamp("createdAt"),
        inviteExpiresAt = raw.liveTimestamp("inviteExpiresAt"),
        summary = parseLiveSummary(raw.liveObject("summary")),
        owner = parseLiveProfile(raw.liveObject("owner"))
    )
}

private fun parseLiveInboxRoom(raw: JSONObject): LiveInboxRoom {
    raw.liveExactKeys(
        setOf(
            "roomId", "status", "roomRevision", "role", "memberState", "membershipRevision",
            "createdAt", "startedAt", "activeExpiresAt", "summary", "peer"
        )
    )
    val status = raw.liveString("status", 16)
    require(status in setOf("waiting", "ready", "active")) { "Live workout response is invalid." }
    val startedAt = raw.liveNullableTimestamp("startedAt")
    val expiresAt = raw.liveNullableTimestamp("activeExpiresAt")
    require((status == "active") == (startedAt != null && expiresAt != null)) {
        "Live workout response is invalid."
    }
    val role = raw.liveString("role", 16)
    val memberState = raw.liveString("memberState", 16)
    require(role in setOf("owner", "participant") && memberState in setOf("joined", "finished")) {
        "Live workout response is invalid."
    }
    return LiveInboxRoom(
        roomId = raw.liveRoomId("roomId"),
        status = status,
        roomRevision = raw.liveRevision("roomRevision"),
        role = role,
        memberState = memberState,
        membershipRevision = raw.liveRevision("membershipRevision"),
        createdAt = raw.liveTimestamp("createdAt"),
        startedAt = startedAt,
        activeExpiresAt = expiresAt,
        summary = parseLiveSummary(raw.liveObject("summary")),
        peer = parseLiveProfile(raw.liveObject("peer"))
    )
}

private fun parseLiveRoomSnapshot(raw: JSONObject): LiveRoomSnapshot {
    raw.liveExactKeys(
        setOf(
            "roomId", "status", "roomRevision", "closeReason", "createdAt", "inviteExpiresAt",
            "startedAt", "activeExpiresAt", "endedAt", "summary"
        )
    )
    val status = raw.liveString("status", 16)
    require(status in setOf("waiting", "ready", "active", "completed", "cancelled", "expired")) {
        "Live workout response is invalid."
    }
    val closeReason = raw.liveNullableString("closeReason", 32)
    if (closeReason != null) {
        require(closeReason in setOf(
            "completed", "declined", "cancelled", "left", "friend_removed", "blocked",
            "account_deleted", "expired"
        )) {
            "Live workout response is invalid."
        }
    }
    val startedAt = raw.liveNullableTimestamp("startedAt")
    val activeExpiresAt = raw.liveNullableTimestamp("activeExpiresAt")
    val endedAt = raw.liveNullableTimestamp("endedAt")
    when (status) {
        "waiting", "ready" -> require(
            startedAt == null && activeExpiresAt == null && endedAt == null && closeReason == null
        ) { "Live workout response is invalid." }
        "active" -> require(
            startedAt != null && activeExpiresAt != null && endedAt == null && closeReason == null
        ) { "Live workout response is invalid." }
        "completed" -> require(
            startedAt != null && activeExpiresAt != null && endedAt != null &&
                closeReason == "completed"
        ) { "Live workout response is invalid." }
        "cancelled" -> require(
            endedAt != null && closeReason in setOf(
                "declined", "cancelled", "left", "friend_removed", "blocked", "account_deleted"
            )
        ) { "Live workout response is invalid." }
        "expired" -> require(endedAt != null && closeReason == "expired") {
            "Live workout response is invalid."
        }
    }
    return LiveRoomSnapshot(
        roomId = raw.liveRoomId("roomId"),
        status = status,
        roomRevision = raw.liveRevision("roomRevision"),
        closeReason = closeReason,
        createdAt = raw.liveTimestamp("createdAt"),
        inviteExpiresAt = raw.liveTimestamp("inviteExpiresAt"),
        startedAt = startedAt,
        activeExpiresAt = activeExpiresAt,
        endedAt = endedAt,
        summary = parseLiveSummary(raw.liveObject("summary"))
    )
}

private fun parseLivePlan(raw: JSONObject): LiveCanonicalPlan {
    raw.liveExactKeys(setOf("version", "exercises"))
    require(raw.liveInt("version", 1, 1) == 1) { "Live workout response is invalid." }
    val exercises = raw.liveArray("exercises", SharedWorkoutLink.MAX_EXERCISES)
        .also { require(it.length() in 1..SharedWorkoutLink.MAX_EXERCISES) {
            "Live workout response is invalid."
        } }
        .liveObjects { exercise ->
            val keys = exercise.keys().asSequence().toSet()
            require(keys == setOf("exerciseId", "name", "sets") ||
                keys == setOf("exerciseId", "name", "catalogKey", "sets")) {
                "Live workout response is invalid."
            }
            val sets = exercise.liveArray("sets", SharedWorkoutLink.MAX_SETS_PER_EXERCISE)
                .also { require(it.length() in 1..SharedWorkoutLink.MAX_SETS_PER_EXERCISE) {
                    "Live workout response is invalid."
                } }
                .liveObjects { set ->
                    set.liveExactKeys(setOf("setId", "weight", "reps"))
                    LiveCanonicalSet(
                        setId = set.liveSetId("setId"),
                        weight = set.liveDouble("weight", 0.0, SharedWorkoutLink.MAX_WEIGHT),
                        reps = set.liveInt("reps", 1, SharedWorkoutLink.MAX_REPS)
                    )
                }
            LiveCanonicalExercise(
                exerciseId = exercise.liveString("exerciseId", 4).also {
                    require(liveExerciseIdPattern.matches(it)) { "Live workout response is invalid." }
                },
                name = exercise.liveExerciseName("name"),
                catalogKey = if (exercise.has("catalogKey")) {
                    exercise.liveString("catalogKey", SharedWorkoutLink.MAX_CATALOG_KEY_CHARACTERS)
                        .also { require(Regex("^[a-z0-9_]{1,64}$").matches(it)) {
                            "Live workout response is invalid."
                        } }
                } else null,
                sets = sets
            )
        }
    require(exercises.sumOf { it.sets.size } <= SharedWorkoutLink.MAX_TOTAL_SETS &&
        exercises.map { it.exerciseId }.toSet().size == exercises.size &&
        exercises.flatMap { it.sets }.map { it.setId }.toSet().size ==
        exercises.sumOf { it.sets.size }) { "Live workout response is invalid." }
    exercises.forEachIndexed { exerciseIndex, exercise ->
        val expectedExerciseId = "e_${(exerciseIndex + 1).toString().padStart(2, '0')}"
        require(exercise.exerciseId == expectedExerciseId) { "Live workout response is invalid." }
        exercise.sets.forEachIndexed { setIndex, set ->
            val expectedSetId = "s_${(exerciseIndex + 1).toString().padStart(2, '0')}_${
                (setIndex + 1).toString().padStart(2, '0')
            }"
            require(set.setId == expectedSetId) { "Live workout response is invalid." }
        }
    }
    return LiveCanonicalPlan(exercises)
}

private fun parseLiveParticipant(raw: JSONObject): LiveParticipant {
    raw.liveExactKeys(
        setOf(
            "isSelf", "profile", "role", "state", "membershipRevision", "joinedAt",
            "finishedAt", "departedAt", "progress"
        )
    )
    val role = raw.liveString("role", 16)
    val state = raw.liveString("state", 16)
    require(role in setOf("owner", "participant") &&
        state in setOf("invited", "joined", "finished", "left", "revoked") &&
        (role != "owner" || state != "invited")) {
        "Live workout response is invalid."
    }
    val finishedAt = raw.liveNullableTimestamp("finishedAt")
    val departedAt = raw.liveNullableTimestamp("departedAt")
    require((state == "finished") == (finishedAt != null) &&
        ((state in setOf("left", "revoked")) == (departedAt != null))) {
        "Live workout response is invalid."
    }
    val progress = if (raw.isNull("progress")) null else parseLiveProgress(raw.liveObject("progress"))
    require((state == "finished") == (progress?.finishedAt != null)) {
        "Live workout response is invalid."
    }
    return LiveParticipant(
        isSelf = raw.liveBoolean("isSelf"),
        profile = parseLiveProfile(raw.liveObject("profile")),
        role = role,
        state = state,
        membershipRevision = raw.liveRevision("membershipRevision"),
        joinedAt = raw.liveNullableTimestamp("joinedAt"),
        finishedAt = finishedAt,
        departedAt = departedAt,
        progress = progress
    )
}

private fun parseLiveProgress(raw: JSONObject): LiveProgress {
    raw.liveExactKeys(
        setOf("version", "revision", "completedSets", "undoableSetId", "finishedAt")
    )
    require(
        raw.liveInt(
            "version",
            LIVE_WORKOUT_CONTRACT_VERSION,
            LIVE_WORKOUT_CONTRACT_VERSION
        ) == LIVE_WORKOUT_CONTRACT_VERSION
    ) {
        "Live workout response is invalid."
    }
    val completedSets = raw.liveArray("completedSets", SharedWorkoutLink.MAX_TOTAL_SETS)
        .liveObjects { set ->
            set.liveExactKeys(setOf("setId", "weight", "reps", "completedAt"))
            LiveCompletedSet(
                setId = set.liveSetId("setId"),
                weight = set.liveDouble("weight", 0.0, SharedWorkoutLink.MAX_WEIGHT),
                reps = set.liveInt("reps", 1, SharedWorkoutLink.MAX_REPS),
                completedAt = set.liveTimestamp("completedAt")
            )
        }
    require(completedSets.map { it.setId }.toSet().size == completedSets.size) {
        "Live workout response is invalid."
    }
    val undoableSetId = raw.liveNullableString("undoableSetId", 9)?.also {
        require(liveSetIdPattern.matches(it) && completedSets.lastOrNull()?.setId == it) {
            "Live workout response is invalid."
        }
    }
    require((undoableSetId == null) == completedSets.isEmpty()) {
        "Live workout response is invalid."
    }
    val finishedAt = raw.liveNullableTimestamp("finishedAt")
    return LiveProgress(
        revision = raw.liveRevision("revision"),
        completedSets = completedSets,
        undoableSetId = undoableSetId,
        finishedAt = finishedAt
    )
}

private fun parseLiveSummary(raw: JSONObject): LiveWorkoutSummary {
    raw.liveExactKeys(setOf("exerciseCount", "setCount", "exerciseNames"))
    val names = raw.liveArray("exerciseNames", SharedWorkoutLink.MAX_EXERCISES)
        .liveStrings { value -> requireSafeLiveExerciseName(value) }
    val exerciseCount = raw.liveInt("exerciseCount", 1, SharedWorkoutLink.MAX_EXERCISES)
    require(names.size == exerciseCount) { "Live workout response is invalid." }
    return LiveWorkoutSummary(
        exerciseCount = exerciseCount,
        setCount = raw.liveInt("setCount", 1, SharedWorkoutLink.MAX_TOTAL_SETS),
        exerciseNames = names
    )
}

private fun parseLiveProfile(raw: JSONObject): LiveProfile {
    raw.liveExactKeys(setOf("profileId", "displayName"))
    return LiveProfile(
        profileId = raw.liveString("profileId", 34).also {
            require(isValidSocialProfileId(it)) { "Live workout response is invalid." }
        },
        displayName = raw.liveString("displayName", 40).also {
            require(it == it.trim(' ') && it.toByteArray(Charsets.UTF_8).size <= 160) {
                "Live workout response is invalid."
            }
        }
    )
}

private fun parseLiveClosed(raw: String): LiveClosedResult {
    val root = liveRoot(
        raw,
        setOf("version", "result", "roomId", "status", "roomRevision", "endedAt")
    )
    require(root.liveString("result", 16) == "closed" &&
        root.liveString("status", 16) == "expired") { "Live workout response is invalid." }
    return LiveClosedResult(
        roomId = root.liveRoomId("roomId"),
        roomRevision = root.liveRevision("roomRevision"),
        endedAt = root.liveTimestamp("endedAt")
    )
}

private fun liveResultDiscriminator(raw: String): String {
    require(raw.toByteArray(Charsets.UTF_8).size <= 256 * 1_024) {
        "Live workout response is invalid."
    }
    return runCatching { parseStrictLiveObject(raw).opt("result") as? String }.getOrNull()
        ?: throw IllegalArgumentException("Live workout response is invalid.")
}

private fun liveRoot(raw: String, expectedKeys: Set<String>): JSONObject {
    require(raw.toByteArray(Charsets.UTF_8).size <= 256 * 1_024) {
        "Live workout response is invalid."
    }
    val root = runCatching { parseStrictLiveObject(raw) }
        .getOrElse { throw IllegalArgumentException("Live workout response is invalid.") }
    root.liveExactKeys(expectedKeys)
    require(root.liveInt("version", 1, 1) == LIVE_WORKOUT_CONTRACT_VERSION) {
        "Live workout response is invalid."
    }
    return root
}

private fun parseStrictLiveObject(raw: String): JSONObject {
    val tokener = JSONTokener(raw)
    val value = tokener.nextValue() as? JSONObject
        ?: throw IllegalArgumentException("Live workout response is invalid.")
    require(tokener.nextClean() == 0.toChar()) { "Live workout response is invalid." }
    return value
}

private fun JSONObject.liveExactKeys(expected: Set<String>) {
    require(keys().asSequence().toSet() == expected) { "Live workout response is invalid." }
}

private fun JSONObject.liveObject(key: String): JSONObject = opt(key) as? JSONObject
    ?: throw IllegalArgumentException("Live workout response is invalid.")

private fun JSONObject.liveArray(key: String, maximum: Int): JSONArray {
    val value = opt(key) as? JSONArray
        ?: throw IllegalArgumentException("Live workout response is invalid.")
    require(value.length() in 0..maximum) { "Live workout response is invalid." }
    return value
}

private fun <T> JSONArray.liveObjects(transform: (JSONObject) -> T): List<T> =
    List(length()) { index ->
        transform(opt(index) as? JSONObject
            ?: throw IllegalArgumentException("Live workout response is invalid."))
    }

private fun <T> JSONArray.liveStrings(transform: (String) -> T): List<T> =
    List(length()) { index ->
        transform(opt(index) as? String
            ?: throw IllegalArgumentException("Live workout response is invalid."))
    }

private fun JSONObject.liveString(key: String, maxCodePoints: Int): String {
    val value = opt(key) as? String
        ?: throw IllegalArgumentException("Live workout response is invalid.")
    require(value.isNotEmpty() && value.codePointCount(0, value.length) <= maxCodePoints &&
        value.none { it.isISOControl() || Character.getType(it) == Character.FORMAT.toInt() }) {
        "Live workout response is invalid."
    }
    return value
}

private fun JSONObject.liveNullableString(key: String, maxCodePoints: Int): String? {
    require(has(key)) { "Live workout response is invalid." }
    return if (isNull(key)) null else liveString(key, maxCodePoints)
}

private fun JSONObject.liveBoolean(key: String): Boolean = opt(key) as? Boolean
    ?: throw IllegalArgumentException("Live workout response is invalid.")

private fun JSONObject.liveInt(key: String, minimum: Int, maximum: Int): Int {
    val raw = opt(key) as? Number
        ?: throw IllegalArgumentException("Live workout response is invalid.")
    val value = raw.toDouble()
    require(value.isFinite() && value % 1.0 == 0.0 && value in minimum.toDouble()..maximum.toDouble()) {
        "Live workout response is invalid."
    }
    return value.toInt()
}

private fun JSONObject.liveDouble(key: String, minimum: Double, maximum: Double): Double {
    val raw = opt(key) as? Number
        ?: throw IllegalArgumentException("Live workout response is invalid.")
    val value = raw.toDouble()
    require(value.isFinite() && value in minimum..maximum) { "Live workout response is invalid." }
    return value
}

private fun JSONObject.liveRevision(key: String): Int = liveInt(key, 1, Int.MAX_VALUE)

private fun JSONObject.liveRoomId(key: String): String = liveString(key, 35).also {
    require(liveRoomIdPattern.matches(it)) { "Live workout response is invalid." }
}

private fun JSONObject.liveSetId(key: String): String = liveString(key, 9).also {
    require(liveSetIdPattern.matches(it)) { "Live workout response is invalid." }
}

private fun JSONObject.liveTimestamp(key: String): String = liveString(key, 64).also {
    require(runCatching { OffsetDateTime.parse(it) }.isSuccess) {
        "Live workout response is invalid."
    }
}

private fun JSONObject.liveNullableTimestamp(key: String): String? {
    require(has(key)) { "Live workout response is invalid." }
    return if (isNull(key)) null else liveTimestamp(key)
}

private fun JSONObject.liveExerciseName(key: String): String =
    requireSafeLiveExerciseName(opt(key))

private fun requireSafeLiveExerciseName(raw: Any?): String {
    val value = raw as? String ?: throw IllegalArgumentException("Live workout response is invalid.")
    require(value.isNotEmpty() && value == value.trim(' ') &&
        value.codePointCount(0, value.length) <= SharedWorkoutLink.MAX_NAME_CODE_POINTS &&
        value.toByteArray(Charsets.UTF_8).size <= SharedWorkoutLink.MAX_NAME_UTF8_BYTES &&
        value.none { it.isISOControl() || Character.getType(it) == Character.FORMAT.toInt() }) {
        "Live workout response is invalid."
    }
    return value
}
