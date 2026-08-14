package com.example.gymapp.auth

import android.content.Context
import com.example.gymapp.data.repository.SharedWorkoutLink
import com.example.gymapp.data.repository.SharedWorkoutPlan
import java.security.MessageDigest
import java.util.UUID

internal const val SOCIAL_WORKOUT_REQUEST_PREFERENCES =
    "gym_social_workout_invite_requests"
private const val SOCIAL_WORKOUT_REQUEST_KEY_PREFIX = "request:"
private const val MAX_PENDING_REQUESTS_PER_ACCOUNT = 25
private const val MAX_PENDING_REQUESTS_ON_DEVICE = 100
private val SOCIAL_WORKOUT_REQUEST_DIGEST_PATTERN = Regex("^[0-9a-f]{64}$")

internal fun socialWorkoutInviteRequestFingerprint(
    profileId: String,
    plan: SharedWorkoutPlan
): String {
    require(isValidSocialProfileId(profileId)) { "Friend profile ID is invalid." }
    val canonicalPlan = SharedWorkoutLink.encode(plan.exercises)
    return MessageDigest.getInstance("SHA-256")
        .digest("v1\u0000$profileId\u0000$canonicalPlan".toByteArray(Charsets.UTF_8))
        .joinToString("") { byte ->
            (byte.toInt() and 0xff).toString(16).padStart(2, '0')
        }
}

/** Durable, minimal idempotency state; it stores no workout payload or display identity. */
internal class SocialWorkoutInviteRequestStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        SOCIAL_WORKOUT_REQUEST_PREFERENCES,
        Context.MODE_PRIVATE
    )

    @Synchronized
    fun retainOrCreate(session: AccountSession.Cloud, fingerprint: String): String? {
        if (!isCanonicalUuid(session.userId) ||
            !SOCIAL_WORKOUT_REQUEST_DIGEST_PATTERN.matches(fingerprint)
        ) return null
        val key = requestKey(session.userId, fingerprint)
        val storedValue = preferences.all[key]
        if (storedValue != null) {
            val stored = storedValue as? String ?: return null
            return stored.takeIf(::isCanonicalUuid)
        }
        val accountPrefix = "$SOCIAL_WORKOUT_REQUEST_KEY_PREFIX${session.userId}:"
        val requestKeys = preferences.all.keys.filter {
            it.startsWith(SOCIAL_WORKOUT_REQUEST_KEY_PREFIX)
        }
        if (requestKeys.count { it.startsWith(accountPrefix) } >= MAX_PENDING_REQUESTS_PER_ACCOUNT ||
            requestKeys.size >= MAX_PENDING_REQUESTS_ON_DEVICE
        ) return null
        val requestId = UUID.randomUUID().toString()
        return requestId.takeIf {
            preferences.edit().putString(key, requestId).commit() &&
                preferences.getString(key, null) == requestId
        }
    }

    @Synchronized
    fun clear(
        session: AccountSession.Cloud,
        fingerprint: String,
        expectedRequestId: String
    ): Boolean {
        if (!SOCIAL_WORKOUT_REQUEST_DIGEST_PATTERN.matches(fingerprint) ||
            !isCanonicalUuid(expectedRequestId)
        ) return false
        val key = requestKey(session.userId, fingerprint)
        val storedValue = preferences.all[key] ?: return true
        val current = storedValue as? String ?: return false
        if (current != expectedRequestId) return false
        return preferences.edit().remove(key).commit() && !preferences.contains(key)
    }

    @Synchronized
    fun clearCloudAccountLocalState(userId: String): Boolean {
        val canonicalUserId = runCatching { UUID.fromString(userId).toString() }.getOrNull()
            ?: return false
        val keys = preferences.all.keys.filter { key ->
            val parts = key.split(':')
            parts.size == 3 && parts[0] == "request" &&
                parts[1].equals(canonicalUserId, ignoreCase = true)
        }
        if (keys.isEmpty()) return true
        val editor = preferences.edit()
        keys.forEach(editor::remove)
        return editor.commit() && keys.none(preferences::contains)
    }

    private fun requestKey(userId: String, fingerprint: String): String =
        "$SOCIAL_WORKOUT_REQUEST_KEY_PREFIX$userId:$fingerprint"

    private fun isCanonicalUuid(value: String): Boolean = runCatching {
        UUID.fromString(value).toString() == value
    }.getOrDefault(false)
}
