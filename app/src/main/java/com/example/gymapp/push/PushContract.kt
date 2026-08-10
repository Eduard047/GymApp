package com.example.gymapp.push

import java.util.UUID

internal const val PUSH_CONTRACT_VERSION = 1
internal const val PUSH_CHANNEL_ID = "gymapp_social"

internal enum class SocialPushType(val wireValue: String) {
    FriendRequestReceived("friend_request_received"),
    FriendRequestAccepted("friend_request_accepted"),
    WorkoutInviteReceived("workout_invite_received"),
    WorkoutInviteAccepted("workout_invite_accepted");

    companion object {
        fun fromWireValue(value: String): SocialPushType? = entries.firstOrNull {
            it.wireValue == value
        }
    }
}

internal enum class LivePushKind(val wireValue: String) {
    Invite("invite"),
    Joined("joined"),
    Started("started"),
    ParticipantFinished("participant_finished"),
    RoomClosed("room_closed");

    companion object {
        fun fromWireValue(value: String): LivePushKind? = entries.firstOrNull {
            it.wireValue == value
        }
    }
}

internal sealed interface PushPayload {
    val bindingId: String
    val objectRevision: Int

    data class Social(
        override val bindingId: String,
        val type: SocialPushType,
        val objectId: String,
        override val objectRevision: Int
    ) : PushPayload

    data class Live(
        override val bindingId: String,
        val kind: LivePushKind,
        val roomId: String,
        override val objectRevision: Int
    ) : PushPayload
}

internal sealed interface PushNavigationTarget {
    data object Social : PushNavigationTarget
    data class Live(val roomId: String) : PushNavigationTarget
}

internal fun PushPayload.navigationTarget(): PushNavigationTarget = when (this) {
    is PushPayload.Social -> PushNavigationTarget.Social
    is PushPayload.Live -> PushNavigationTarget.Live(roomId)
}

/**
 * Parses only the provider-neutral, data-only payload emitted by the GymApp dispatcher.
 * Any notification payload is rejected because FCM can auto-render it without account checks.
 */
internal fun parsePushPayload(
    data: Map<String, String>,
    hasNotificationPayload: Boolean
): PushPayload? {
    if (hasNotificationPayload || data.size != 5) return null
    if (data.values.any { value ->
            value.isEmpty() || value.length > MAX_PUSH_FIELD_CHARS || value.any(Char::isISOControl)
        }
    ) {
        return null
    }
    if (data["version"] != PUSH_CONTRACT_VERSION.toString()) return null
    val bindingId = data["bindingId"]?.takeIf(::isCanonicalV4Uuid) ?: return null

    return when (data.keys) {
        SOCIAL_PUSH_KEYS -> {
            val type = data["type"]?.let(SocialPushType::fromWireValue) ?: return null
            val objectId = data["objectId"] ?: return null
            if (!isValidSocialObjectId(type, objectId)) return null
            val revision = data["objectRevision"]?.let(::parsePushRevision) ?: return null
            PushPayload.Social(
                bindingId = bindingId,
                type = type,
                objectId = objectId,
                objectRevision = revision
            )
        }

        LIVE_PUSH_KEYS -> {
            val kind = data["kind"]?.let(LivePushKind::fromWireValue) ?: return null
            val roomId = data["roomId"]?.takeIf(LIVE_ROOM_ID_PATTERN::matches) ?: return null
            val revision = data["roomRevision"]?.let(::parsePushRevision) ?: return null
            PushPayload.Live(
                bindingId = bindingId,
                kind = kind,
                roomId = roomId,
                objectRevision = revision
            )
        }

        else -> null
    }
}

internal fun isCanonicalUuid(value: String): Boolean = runCatching {
    UUID.fromString(value).toString() == value
}.getOrDefault(false)

internal fun isCanonicalV4Uuid(value: String): Boolean =
    CANONICAL_V4_UUID_PATTERN.matches(value) && isCanonicalUuid(value)

private fun parsePushRevision(value: String): Int? {
    if (!REVISION_PATTERN.matches(value)) return null
    return value.toLongOrNull()?.takeIf { it in 0..Int.MAX_VALUE.toLong() }?.toInt()
}

private fun isValidSocialObjectId(type: SocialPushType, objectId: String): Boolean = when (type) {
    SocialPushType.FriendRequestReceived,
    SocialPushType.FriendRequestAccepted -> FRIENDSHIP_ID_PATTERN.matches(objectId)

    SocialPushType.WorkoutInviteReceived,
    SocialPushType.WorkoutInviteAccepted -> WORKOUT_INVITE_ID_PATTERN.matches(objectId)
}

private const val MAX_PUSH_FIELD_CHARS = 128
private val SOCIAL_PUSH_KEYS = setOf(
    "version",
    "bindingId",
    "type",
    "objectId",
    "objectRevision"
)
private val LIVE_PUSH_KEYS = setOf(
    "version",
    "bindingId",
    "kind",
    "roomId",
    "roomRevision"
)
private val CANONICAL_V4_UUID_PATTERN = Regex(
    "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
)
private val REVISION_PATTERN = Regex("^(0|[1-9][0-9]{0,9})$")
private val FRIENDSHIP_ID_PATTERN = Regex("^f_[0-9a-f]{32}$")
private val WORKOUT_INVITE_ID_PATTERN = Regex("^wi_[0-9a-f]{32}$")
private val LIVE_ROOM_ID_PATTERN = Regex("^lr_[0-9a-f]{32}$")
