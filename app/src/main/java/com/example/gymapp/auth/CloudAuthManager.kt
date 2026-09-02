package com.example.gymapp.auth

import android.content.Context
import android.content.SharedPreferences
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import com.example.gymapp.BuildConfig
import com.example.gymapp.R
import com.example.gymapp.data.repository.SharedWorkoutLink
import com.example.gymapp.data.repository.SharedWorkoutPlan
import com.example.gymapp.data.repository.LiveWorkoutBinding
import com.example.gymapp.data.repository.LiveWorkoutSidecarStore
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.ActivityOnlyWorkoutItem
import com.example.gymapp.sync.ActivityOnlyWorkoutReadResult
import com.example.gymapp.sync.ActivityOnlyWorkoutSyncResponse
import com.example.gymapp.sync.activityOnlyWorkoutSyncRequestJson
import com.example.gymapp.sync.parseActivityOnlyWorkoutReadResponse
import com.example.gymapp.sync.parseActivityOnlyWorkoutSyncResponse
import com.example.gymapp.push.PushRegistration
import com.example.gymapp.push.PushRevocation
import com.example.gymapp.push.PushRpcSerialGate
import com.example.gymapp.push.parsePushRegistrationResponse
import com.example.gymapp.push.parsePushRevocationResponse
import com.example.gymapp.push.pushRegistrationRequestJson
import com.example.gymapp.push.pushRevocationRequestJson
import com.example.gymapp.util.LocalizedText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.OffsetDateTime
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

internal const val SUPABASE_URL = "https://owrcbsrectdgaotndtxy.supabase.co"
internal const val SUPABASE_KEY = "sb_publishable_vvOMzx6V_sPBpD-b3VZfzg_y14u8kIg"
private val AUTH_REDIRECT_URL = if (BuildConfig.APPLICATION_ID == "com.setforge.gymapp") {
    "https://gymapptracker.com/auth/android-callback.html"
} else {
    "https://gymapptracker.com/confirmed.html?platform=android${BuildConfig.AUTH_BRIDGE_VARIANT_QUERY}"
}
private const val NEEDS_PASSWORD_UPDATE_KEY = "needs_password_update"
private const val PENDING_SIGNUP_KEY = "pending_signup_confirmation"
private const val PENDING_RECOVERY_KEY = "pending_password_recovery"
private const val AUTH_TRANSACTION_MAX_AGE_MILLIS = 24 * 60 * 60 * 1_000L
private const val MAX_CLOUD_RESPONSE_BYTES = 256 * 1_024
private const val MAX_CLOUD_STATE_RESPONSE_BYTES = 10 * 1_024 * 1_024
private const val MAX_CLOUD_REQUEST_BYTES = 10 * 1_024 * 1_024
private const val MAX_CLOUD_ERROR_RESPONSE_BYTES = 64 * 1_024
private const val MAX_ACTIVITY_ONLY_CLOUD_RESPONSE_BYTES = 1_048_576
private const val MAX_STORED_SESSION_BYTES = 64 * 1_024
private const val MAX_AUTH_TOKEN_CHARS = 16 * 1_024
internal const val MAX_LOGIN_PASSWORD_UTF8_BYTES = 1_024
private const val INACTIVE_CLOUD_SESSION_MESSAGE =
    "This cloud session is no longer active. Sign in again before syncing."
private const val STALE_REMOTE_STATE_MESSAGE =
    "Cloud data changed on another device. Reload it before syncing again."

internal fun requireSafeCloudStateResponse(response: String) {
    WorkoutDataLimits.requireSafeJsonEnvelope(
        rawJson = response,
        maximumBytes = MAX_CLOUD_STATE_RESPONSE_BYTES
    )
}

internal data class WorkoutDurationSyncAcknowledgement(
    val syncedCount: Int,
    val changedCount: Int
)

/** Strict production v2 acknowledgement; malformed or server-error envelopes fail closed. */
internal fun parseWorkoutDurationSyncAcknowledgement(
    rawResponse: String,
    expectedCount: Int
): WorkoutDurationSyncAcknowledgement {
    require(expectedCount in 0..WorkoutDataLimits.MAX_SESSIONS)
    WorkoutDataLimits.requireSafeJsonEnvelope(rawResponse, MAX_CLOUD_RESPONSE_BYTES)
    val root = JSONObject(rawResponse)

    fun exactInt(key: String, range: IntRange): Int {
        val raw = root.opt(key)
        require(raw is Number) { "Workout duration sync response is invalid." }
        val value = runCatching { java.math.BigDecimal(raw.toString()).intValueExact() }
            .getOrElse { throw IllegalArgumentException("Workout duration sync response is invalid.") }
        require(value in range) { "Workout duration sync response is invalid." }
        return value
    }

    require(exactInt("version", 2..2) == 2) {
        "Workout duration sync response is invalid."
    }
    if (root.has("error")) {
        require(root.keys().asSequence().toSet() == setOf("version", "error", "retryAfter")) {
            "Workout duration sync response is invalid."
        }
        val error = root.opt("error") as? String
            ?: throw IllegalArgumentException("Workout duration sync response is invalid.")
        require(error.isNotBlank() && error.length <= 64) {
            "Workout duration sync response is invalid."
        }
        exactInt("retryAfter", 1..600)
        error("Workout duration synchronization was rejected: $error")
    }
    require(root.keys().asSequence().toSet() == setOf("version", "syncedCount", "changedCount")) {
        "Workout duration sync response is invalid."
    }
    val syncedCount = exactInt("syncedCount", 0..WorkoutDataLimits.MAX_SESSIONS)
    val changedCount = exactInt(
        "changedCount",
        0..(WorkoutDataLimits.MAX_SESSIONS * 2)
    )
    require(syncedCount == expectedCount) {
        "Workout duration sync response is invalid."
    }
    return WorkoutDurationSyncAcknowledgement(syncedCount, changedCount)
}

sealed class AccountSession {
    data class Cloud(
        val userId: String,
        val email: String,
        val displayName: String,
        val accessToken: String,
        val refreshToken: String?,
        internal val sessionGeneration: String = newCloudSessionGeneration()
    ) : AccountSession()

    data class Local(val displayName: String) : AccountSession()
}

fun AccountSession.databaseName(): String {
    if (this is AccountSession.Local) {
        return checkNotNull(localDatabaseLogicalName(displayName)) {
            "The local account name cannot be used as a database identity."
        }
    }
    val raw = "cloud_${(this as AccountSession.Cloud).userId}"
    return raw.replace(Regex("[^A-Za-z0-9_.-]"), "_").ifBlank { "local_default" }
}

data class AuthUiState(
    val session: AccountSession? = null,
    val isLoading: Boolean = false,
    val message: LocalizedText? = null,
    val messageIsError: Boolean = true,
    val pendingConfirmationEmail: String? = null,
    val needsPasswordUpdate: Boolean = false
)

enum class AuthCallbackKind {
    EmailConfirmation,
    PasswordRecovery
}

data class AuthCallbackResult(
    val session: AccountSession.Cloud,
    val kind: AuthCallbackKind
)

internal data class PendingAuthTransaction(
    val state: String,
    val codeVerifier: String,
    val email: String,
    val createdAtMillis: Long
) {
    fun isFresh(nowMillis: Long = System.currentTimeMillis()): Boolean {
        return createdAtMillis in (nowMillis - AUTH_TRANSACTION_MAX_AGE_MILLIS)..nowMillis
    }
}

internal fun reusablePendingSignupTransaction(
    existing: PendingAuthTransaction?,
    email: String,
    nowMillis: Long = System.currentTimeMillis()
): PendingAuthTransaction? = existing?.takeIf { transaction ->
    transaction.email == email && transaction.isFresh(nowMillis)
}

internal fun isDeterministicAuthInitiationHttpFailure(responseCode: Int?): Boolean {
    return responseCode != null &&
        responseCode in 400..499 &&
        responseCode !in setOf(408, 425)
}

internal fun isUnavailableSocialMyFriendCodeRpc(
    responseCode: Int,
    errorCode: String?
): Boolean = responseCode == 404 && errorCode in setOf("PGRST202", "42883")

internal fun isUnavailableSocialWorkoutInboxPageRpc(
    responseCode: Int,
    errorCode: String?
): Boolean = responseCode == 404 && errorCode in setOf("PGRST202", "42883")

internal fun isUnavailableActivityOnlyWorkoutRpc(
    responseCode: Int,
    errorCode: String?
): Boolean = responseCode == 404 && errorCode in setOf("PGRST202", "PGRST203")

internal fun isRetryableActivityOnlyWorkoutSqlState(errorCode: String?): Boolean =
    errorCode in setOf("55P03", "57014")

/** Retries only outcome-unknown transport failures; [operation] must close over one exact body. */
internal suspend fun <T> retryActivityOnlyWorkoutOutcomeUnknown(
    maximumAttempts: Int = 3,
    isRetryableSqlFailure: (Throwable) -> Boolean,
    retryDelay: suspend (attempt: Int) -> Unit = { attempt -> delay(150L * attempt) },
    operation: suspend () -> T
): T {
    require(maximumAttempts in 1..3)
    var lastTransient: Throwable? = null
    repeat(maximumAttempts) { attempt ->
        try {
            return operation()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (error !is IOException && !isRetryableSqlFailure(error)) throw error
            lastTransient = error
        }
        if (attempt + 1 < maximumAttempts) retryDelay(attempt + 1)
    }
    throw checkNotNull(lastTransient)
}

internal fun socialWorkoutInboxPageRequestBody(
    cursor: SocialWorkoutInboxCursor?,
    limit: Int = SOCIAL_WORKOUT_INBOX_PAGE_SIZE
): JSONObject {
    require(limit in 1..SOCIAL_WORKOUT_INBOX_PAGE_SIZE) {
        "Workout inbox page size is invalid."
    }
    cursor?.let {
        require(isValidRemoteStateRevision(it.createdAt) &&
            isValidSocialWorkoutInviteId(it.inviteId)) {
            "Workout inbox cursor is invalid."
        }
    }
    return JSONObject()
        .put("p_cursor_created_at", cursor?.createdAt ?: JSONObject.NULL)
        .put("p_cursor_invite_id", cursor?.inviteId ?: JSONObject.NULL)
        .put("p_cursor_pending", cursor?.pending ?: JSONObject.NULL)
        .put("p_limit", limit)
}

internal fun authCallbackKind(purpose: String?): AuthCallbackKind {
    return if (purpose.equals("recovery", ignoreCase = true)) {
        AuthCallbackKind.PasswordRecovery
    } else {
        AuthCallbackKind.EmailConfirmation
    }
}

internal fun isExpectedAuthState(
    receivedStates: List<String>,
    expectedState: String?,
    pendingIsFresh: Boolean
): Boolean {
    return receivedStates.size == 1 &&
        receivedStates.single().matches(Regex("^[A-Za-z0-9_-]{32}$")) &&
        expectedState != null &&
        pendingIsFresh &&
        receivedStates.single() == expectedState
}

internal fun isSafeCallbackValue(value: String, maxLength: Int): Boolean {
    return value.isNotEmpty() &&
        value.length <= maxLength &&
        value.none { it.code in 0x00..0x1F || it.code == 0x7F }
}

internal fun isValidPKCEAuthCode(value: String): Boolean {
    return value.matches(
        Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")
    )
}

internal fun isStructurallySafePKCECallback(
    queryKeys: Set<String>,
    hasFragment: Boolean,
    receivedStates: List<String>,
    purposes: List<String>,
    codes: List<String>,
    errors: List<String>,
    descriptions: List<String>,
    errorCodes: List<String> = emptyList()
): Boolean {
    val allowedKeys = setOf(
        "state", "purpose", "code", "error", "error_description", "error_code"
    )
    val hasCode = codes.size == 1 && isValidPKCEAuthCode(codes.single())
    val hasError = errors.size == 1 && isSafeCallbackValue(errors.single(), 128)
    val hasDescription = descriptions.isEmpty() ||
        (descriptions.size == 1 && isSafeCallbackValue(descriptions.single(), 1_024))
    val hasSafeErrorCode = errorCodes.isEmpty() ||
        (hasError && errorCodes.size == 1 && isSafeCallbackValue(errorCodes.single(), 128))
    return !hasFragment &&
        queryKeys.all { it in allowedKeys && !it.contains("token", ignoreCase = true) } &&
        receivedStates.size == 1 &&
        receivedStates.single().matches(Regex("^[A-Za-z0-9_-]{32}$")) &&
        purposes.size == 1 && purposes.single() in setOf("signup", "recovery") &&
        hasCode != hasError &&
        hasDescription &&
        hasSafeErrorCode &&
        (descriptions.isEmpty() || hasError)
}

internal fun activeCloudSessionFor(
    current: AccountSession?,
    expected: AccountSession.Cloud
): AccountSession.Cloud? {
    return (current as? AccountSession.Cloud)?.takeIf {
        it.userId == expected.userId &&
            it.sessionGeneration == expected.sessionGeneration
    }
}

internal enum class CloudAccountDeletionSessionDisposition {
    ClearCapturedSession,
    AlreadySignedOut,
    PreserveDifferentSession
}

internal data class CloudAccountDeletionCompletion(
    val disposition: CloudAccountDeletionSessionDisposition,
    val durableAuthCleanupCompleted: Boolean
)

internal fun shouldRetireCloudAccountDeletionJournal(
    completion: CloudAccountDeletionCompletion,
    localCleanupFailures: Int
): Boolean = localCleanupFailures == 0 && completion.durableAuthCleanupCompleted

internal fun cloudAccountDeletionSessionDisposition(
    current: AccountSession?,
    deletedSession: AccountSession.Cloud
): CloudAccountDeletionSessionDisposition = when {
    activeCloudSessionFor(current, deletedSession) != null ->
        CloudAccountDeletionSessionDisposition.ClearCapturedSession
    current == null -> CloudAccountDeletionSessionDisposition.AlreadySignedOut
    else -> CloudAccountDeletionSessionDisposition.PreserveDifferentSession
}

internal class AccountDeletionPreparationException : IllegalStateException(
    "Account deletion could not be prepared safely on this device."
)

internal suspend fun <T> runPreparedAccountDeletionRequest(
    persistIntent: () -> Boolean,
    request: suspend () -> T
): T {
    if (!persistIntent()) throw AccountDeletionPreparationException()
    return request()
}

internal fun authStateAfterUnknownAccountDeletionOutcome(
    current: AccountSession?,
    deletedSession: AccountSession.Cloud
): AuthUiState? = if (activeCloudSessionFor(current, deletedSession) != null) {
    AuthUiState(
        message = LocalizedText(R.string.account_delete_outcome_unknown),
        messageIsError = true
    )
} else {
    null
}

internal class CloudLogoutRequest(
    val path: String,
    val method: String,
    val accessToken: String,
    val sessionGeneration: String
)

internal fun localCloudLogoutRequest(session: AccountSession?): CloudLogoutRequest? {
    return (session as? AccountSession.Cloud)?.let {
        CloudLogoutRequest(
            path = "/auth/v1/logout?scope=local",
            method = "POST",
            accessToken = it.accessToken,
            sessionGeneration = it.sessionGeneration
        )
    }
}

internal data class CloudAccountDeletionRequest(
    val path: String,
    val method: String,
    val headers: Map<String, String>,
    val body: String
)

internal fun cloudAccountDeletionPreparationRequest(): CloudAccountDeletionRequest =
    CloudAccountDeletionRequest(
        path = "/functions/v1/delete-account",
        method = "POST",
        headers = emptyMap(),
        body = JSONObject().put("action", "prepare").toString()
    )

internal fun cloudAccountDeletionRequest(grant: String): CloudAccountDeletionRequest =
    CloudAccountDeletionRequest(
        path = "/functions/v1/delete-account",
        method = "POST",
        headers = mapOf("X-GymApp-Delete" to "confirmed"),
        body = JSONObject()
            .put("action", "delete")
            .put("confirmation", "DELETE")
            .put("grant", grant)
            .toString()
    )

internal fun accountDeletionGrantFromResponse(response: String): String? = runCatching {
    val json = JSONObject(response)
    val keys = buildSet {
        val iterator = json.keys()
        while (iterator.hasNext()) add(iterator.next())
    }
    json.optString("grant").takeIf {
        keys == setOf("grant", "expiresAt") &&
            it.matches(Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")) &&
            runCatching { OffsetDateTime.parse(json.getString("expiresAt")) }.isSuccess
    }
}.getOrNull()

internal fun isSuccessfulCloudAccountDeletionResponse(response: String): Boolean = runCatching {
    val json = JSONObject(response)
    val keys = buildSet {
        val iterator = json.keys()
        while (iterator.hasNext()) add(iterator.next())
    }
    keys == setOf("deleted") && json.opt("deleted") == true
}.getOrDefault(false)

internal fun passwordUpdateBody(
    newPassword: String,
    currentPassword: String? = null,
    nonce: String? = null
): String = JSONObject()
    .put("password", newPassword)
    .apply {
        if (currentPassword != null) put("current_password", currentPassword)
        if (nonce != null) put("nonce", nonce)
    }
    .toString()

internal fun isValidPasswordReauthenticationNonce(value: String): Boolean =
    value.matches(Regex("^[0-9]{6,8}$"))

internal fun isPasswordReauthenticationRequired(
    errorCode: String?,
    providerMessage: String?
): Boolean = errorCode.equals("reauthentication_needed", ignoreCase = true) ||
    providerMessage?.trim()?.equals("reauthentication needed", ignoreCase = true) == true

internal class PasswordReauthenticationRequiredException : IllegalStateException(
    "Enter the verification code sent to your email."
)

internal class LiveWorkoutGatewayException(
    val responseCode: Int,
    val errorCode: String?,
    safeMessage: String
) : IllegalStateException(safeMessage) {
    val isConflict: Boolean
        get() = responseCode == 409 && errorCode == "conflict"

    val isResourceUnavailable: Boolean
        get() = responseCode == 404 && errorCode == "resource_unavailable"
}

internal fun isTerminalRefreshFailure(
    responseCode: Int,
    errorCode: String?,
    providerMessage: String?
): Boolean {
    val normalizedCode = errorCode.orEmpty().lowercase()
    val normalizedMessage = providerMessage.orEmpty().lowercase()
    return responseCode == 401 ||
        normalizedCode in setOf(
            "bad_jwt",
            "refresh_token_already_used",
            "refresh_token_not_found",
            "invalid_refresh_token"
        ) ||
        normalizedMessage.contains("invalid refresh token") ||
        normalizedMessage.contains("refresh token not found") ||
        normalizedMessage.contains("refresh token already used")
}

internal fun parseStoredCloudSession(raw: String?): AccountSession.Cloud? = runCatching {
    require(!raw.isNullOrBlank())
    require(raw.toByteArray(Charsets.UTF_8).size <= MAX_STORED_SESSION_BYTES)
    val json = JSONObject(raw)
    val userId = json.getString("userId")
    require(isCanonicalUuid(userId))

    val email = json.getString("email").trim().lowercase()
    require(isStructurallyValidEmail(email))

    val displayName = json.getString("displayName").trim()
    require(displayName.codePointCount(0, displayName.length) in 1..128)
    require(displayName.toByteArray(Charsets.UTF_8).size <= 512)
    require(displayName.none { it.isISOControl() })

    val accessToken = json.getString("accessToken")
    require(isStructurallyValidSupabaseAccessToken(accessToken, userId))

    val refreshToken = json.optString("refreshToken")
        .takeIf { it.isNotBlank() && it != "null" }
    require(refreshToken == null || isStructurallyValidAuthToken(refreshToken))

    AccountSession.Cloud(
        userId = userId,
        email = email,
        displayName = displayName,
        accessToken = accessToken,
        refreshToken = refreshToken,
        sessionGeneration = json.optString("sessionGeneration")
            .takeIf(::isCanonicalUuid)
            ?: newCloudSessionGeneration()
    )
}.getOrNull()

private fun isCanonicalUuid(value: String): Boolean = runCatching {
    UUID.fromString(value).toString().equals(value, ignoreCase = true)
}.getOrDefault(false)

private fun isStructurallyValidEmail(value: String): Boolean =
    value.length <= 254 && Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$").matches(value)

private fun isStructurallyValidAuthToken(value: String): Boolean =
    value.length in 1..MAX_AUTH_TOKEN_CHARS && value.none(Char::isWhitespace) &&
        value.none(Char::isISOControl)

private fun isStructurallyValidSupabaseAccessToken(value: String, expectedUserId: String): Boolean {
    if (!isStructurallyValidAuthToken(value)) return false
    val parts = value.split('.')
    if (parts.size != 3 || parts.any { it.isBlank() }) return false
    return runCatching {
        val payload = JSONObject(String(Base64.getUrlDecoder().decode(parts[1]), Charsets.UTF_8))
        payload.optString("sub").equals(expectedUserId, ignoreCase = true) &&
            payload.optLong("exp") > 0L
    }.getOrDefault(false)
}

internal fun clearAuthPreferencesSynchronously(preferences: SharedPreferences): Boolean =
    preferences.edit().clear().commit()

private fun sharedPreferencesSnapshot(preferences: SharedPreferences): Map<String, Any?> =
    preferences.all.mapValues { (_, value) ->
        @Suppress("UNCHECKED_CAST")
        if (value is Set<*>) (value as Set<String>).toSet() else value
    }

private fun restoreSharedPreferencesSnapshot(
    preferences: SharedPreferences,
    snapshot: Map<String, Any?>
): Boolean = runCatching {
    val editor = preferences.edit().clear()
    snapshot.forEach { (key, value) ->
        when (value) {
            is String -> editor.putString(key, value)
            is Boolean -> editor.putBoolean(key, value)
            is Int -> editor.putInt(key, value)
            is Long -> editor.putLong(key, value)
            is Float -> editor.putFloat(key, value)
            is Set<*> -> {
                @Suppress("UNCHECKED_CAST")
                editor.putStringSet(key, (value as Set<String>).toSet())
            }
            else -> error("Unsupported authentication preference type.")
        }
    }
    editor.commit()
}.getOrDefault(false)

internal fun signedOutAuthStateAfterLocalLogout(preferencesCleared: Boolean): AuthUiState =
    AuthUiState(
        message = if (preferencesCleared) {
            null
        } else {
            LocalizedText(R.string.auth_message_logout_failed)
        },
        messageIsError = !preferencesCleared
    )

internal sealed interface RemoteStateRevision {
    data object Missing : RemoteStateRevision
    data object Conflicted : RemoteStateRevision

    data class Present(val updatedAt: String) : RemoteStateRevision {
        init {
            require(isValidRemoteStateRevision(updatedAt)) {
                "The cloud returned an invalid state revision."
            }
        }
    }
}

internal data class RemoteStateWriteRequest(
    val path: String,
    val method: String,
    val prefer: String
)

internal fun remoteStateWriteRequest(
    userId: String,
    revision: RemoteStateRevision
): RemoteStateWriteRequest {
    val encodedUserId = encodePostgrestQueryValue(userId)
    return when (revision) {
        RemoteStateRevision.Missing -> RemoteStateWriteRequest(
            path = "/rest/v1/user_states?on_conflict=user_id&select=updated_at",
            method = "POST",
            prefer = "resolution=ignore-duplicates,return=representation,missing=default"
        )

        RemoteStateRevision.Conflicted -> error(STALE_REMOTE_STATE_MESSAGE)

        is RemoteStateRevision.Present -> RemoteStateWriteRequest(
            path = "/rest/v1/user_states?user_id=eq.$encodedUserId" +
                "&updated_at=eq.${encodePostgrestQueryValue(revision.updatedAt)}" +
                "&select=updated_at",
            method = "PATCH",
            prefer = "return=representation"
        )
    }
}

internal fun isValidRemoteStateRevision(value: String): Boolean {
    return value.length in 1..64 && runCatching {
        OffsetDateTime.parse(value)
    }.isSuccess
}

internal fun readUtf8ResponseBody(input: InputStream, maxBytes: Int): String {
    require(maxBytes > 0) { "Response limit must be positive." }
    val output = ByteArrayOutputStream(minOf(maxBytes, 8 * 1_024))
    val buffer = ByteArray(8 * 1_024)
    var total = 0
    while (true) {
        val count = input.read(buffer)
        if (count < 0) break
        total += count
        check(total <= maxBytes) { "Cloud response exceeded the safe size limit." }
        output.write(buffer, 0, count)
    }
    return output.toString(Charsets.UTF_8.name())
}

private fun encodePostgrestQueryValue(value: String): String {
    return URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")
}

private fun newCloudSessionGeneration(): String = UUID.randomUUID().toString()

private fun materializeLocalDatabase(context: Context, databaseName: String): Boolean =
    runCatching {
        SQLiteDatabase.openOrCreateDatabase(context.getDatabasePath(databaseName), null).use { database ->
            database.rawQuery("PRAGMA quick_check(1)", null).use { cursor ->
                check(cursor.moveToFirst() && cursor.getString(0) == "ok")
            }
        }
        context.getDatabasePath(databaseName).isFile
    }.getOrDefault(false)

private fun deleteOnlyNewEmptyLocalDatabaseFiles(context: Context, databaseName: String): Boolean {
    val database = context.getDatabasePath(databaseName)
    // A rejected first-open transaction must never delete a file with user rows. SQLite creates
    // a small schema-only DB here; anything larger is retained for recovery and the auth/index
    // rollback still prevents it from being accepted as another identity.
    if (database.isFile && database.length() > MAX_EMPTY_LOCAL_DATABASE_BYTES) return false
    return context.deleteDatabase(databaseName) || !database.exists()
}

private const val MAX_EMPTY_LOCAL_DATABASE_BYTES = 4L * 1_024L * 1_024L

class CloudAuthManager internal constructor(
    context: Context,
    localProfileRegistryOverride: LocalProfileRegistry? = null,
    localAuthCommitterOverride: ((SharedPreferences.Editor) -> Boolean)? = null,
    localAuthClearerOverride: (() -> Boolean)? = null,
    localSidecarClearerOverride: (() -> Boolean)? = null,
    localDatabaseMaterializerOverride: ((String) -> Boolean)? = null,
    localDatabaseRollbackOverride: ((String) -> Boolean)? = null,
    localProfileDeletionJournalOverride: LocalProfileDeletionJournal? = null
) {
    private class SupabaseHttpException(
        val responseCode: Int,
        val errorCode: String?,
        val providerMessage: String?,
        safeMessage: String
    ) : IllegalStateException(safeMessage)

    private data class SupabaseErrorFields(
        val code: String?,
        val message: String?
    )

    private data class StoredSessionRead(
        val session: AccountSession? = null,
        val recoveryMessage: LocalizedText? = null
    )

    private data class PendingAuthTransactionSelection(
        val transaction: PendingAuthTransaction,
        val wasCreated: Boolean
    )

    private data class RemoteRevisionKey(
        val userId: String,
        val sessionGeneration: String
    )

    private data class RemoteStateRow(
        val state: JSONObject,
        val revision: RemoteStateRevision.Present
    )

    private val prefs = context.applicationContext.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
    private val secureAuthStore = AndroidKeystoreAuthStore(context.applicationContext)
    private val localDatabaseBindingStore = LocalDatabaseBindingStore(context.applicationContext)
    private val localProfileRegistry = localProfileRegistryOverride
        ?: LocalProfileRegistry(context.applicationContext)
    private val localAuthCommitter = localAuthCommitterOverride ?: { editor: SharedPreferences.Editor ->
        editor.commit()
    }
    private val localAuthClearer = localAuthClearerOverride ?: {
        clearAllAuthStorageSynchronously()
    }
    private val liveWorkoutSidecarStore = LiveWorkoutSidecarStore(context.applicationContext)
    private val socialWorkoutInviteRequestStore =
        SocialWorkoutInviteRequestStore(context.applicationContext)
    private val localSidecarClearer = localSidecarClearerOverride
        // Live bindings are already exact cloud-owner/session scoped. Opening or deleting a
        // local profile must not destroy another account's durable offline queue.
        ?: { true }
    private val localDatabaseMaterializer = localDatabaseMaterializerOverride ?: { databaseName ->
        materializeLocalDatabase(context.applicationContext, databaseName)
    }
    private val localDatabaseRollback = localDatabaseRollbackOverride ?: { databaseName ->
        deleteOnlyNewEmptyLocalDatabaseFiles(context.applicationContext, databaseName)
    }
    private val accountDeletionJournal = CloudAccountDeletionJournal(context.applicationContext)
    private val localProfileDeletionJournal = localProfileDeletionJournalOverride
        ?: LocalProfileDeletionJournal(context.applicationContext)
    private val authStateLock = Any()
    private val refreshMutex = Mutex()
    private val remoteStateMutex = Mutex()
    private val activityOnlyWorkoutMutex = Mutex()
    private val pushRpcGate = PushRpcSerialGate()
    private val logoutRevokeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Volatile
    private var pushInstallationForLogout: ((AccountSession.Cloud) -> String?)? = null
    private val remoteStateRevisions = ConcurrentHashMap<RemoteRevisionKey, RemoteStateRevision>()
    private var authMutationVersion = 0L
    private val initialSessionRead = readSession()
    private val initialSession = initialSessionRead.session
    private val _authState = MutableStateFlow(
        AuthUiState(
            session = initialSession,
            message = initialSessionRead.recoveryMessage,
            messageIsError = initialSessionRead.recoveryMessage != null,
            needsPasswordUpdate = initialSession is AccountSession.Cloud &&
                prefs.getBoolean(NEEDS_PASSWORD_UPDATE_KEY, false)
        )
    )
    val authState: StateFlow<AuthUiState> = _authState.asStateFlow()

    suspend fun login(email: String, password: String): AccountSession.Cloud {
        val cleanEmail = normalizeEmail(email)
        validateEmail(cleanEmail)
        require(password.isNotEmpty()) { "Enter your password." }
        require(password.toByteArray(Charsets.UTF_8).size <= MAX_LOGIN_PASSWORD_UTF8_BYTES) {
            "Password is too long."
        }
        val authAttempt = beginAuthAttempt()
        return requireNotNull(
            authenticate(
                path = "/auth/v1/token?grant_type=password",
                payload = JSONObject()
                    .put("email", cleanEmail)
                    .put("password", password),
                expectedAuthMutationVersion = authAttempt
            )
        )
    }

    suspend fun signUp(email: String, password: String, displayName: String): AccountSession.Cloud? {
        val cleanEmail = normalizeEmail(email)
        val cleanName = sanitizeDisplayName(displayName.ifBlank { cleanEmail.substringBefore("@") })
        validateEmail(cleanEmail)
        validateNewPassword(password)
        if (cleanName.isNotBlank()) {
            require(cleanName.length in 2..32 && cleanName.all { it.isLetterOrDigit() || it == ' ' || it == '.' || it == '-' || it == '_' }) {
                "Display name can use letters, numbers, spaces, dot, dash and underscore."
            }
        }
        val authAttempt = beginAuthAttempt()
        val transaction = beginAuthTransaction(
            key = PENDING_SIGNUP_KEY,
            email = cleanEmail,
            expectedAuthMutationVersion = authAttempt
        )
        val redirectSeparator = if (AUTH_REDIRECT_URL.contains('?')) '&' else '?'
        val redirectURL = "$AUTH_REDIRECT_URL$redirectSeparator" +
            "state=${transaction.state}&purpose=signup"
        return try {
            authenticate(
                path = "/auth/v1/signup?redirect_to=${java.net.URLEncoder.encode(redirectURL, "UTF-8")}",
                payload = JSONObject()
                    .put("email", cleanEmail)
                    .put("password", password)
                    .put(
                        "data",
                        JSONObject().put("display_name", cleanName)
                    )
                    .put("code_challenge", codeChallenge(transaction.codeVerifier))
                    .put("code_challenge_method", "s256"),
                allowEmailConfirmationPending = true,
                expectedAuthMutationVersion = authAttempt
            )
        } catch (error: Throwable) {
            if (isDeterministicAuthInitiationFailure(error)) {
                clearPendingAuthTransaction(PENDING_SIGNUP_KEY, transaction.state)
            }
            throw error
        }
    }

    suspend fun resendSignUpConfirmation(email: String) = withContext(Dispatchers.IO) {
        val cleanEmail = normalizeEmail(email)
        validateEmail(cleanEmail)
        val transactionSelection = reusableSignupAuthTransaction(
            email = cleanEmail,
            expectedAuthMutationVersion = authMutationSnapshot()
        )
        val transaction = transactionSelection.transaction
        val redirectSeparator = if (AUTH_REDIRECT_URL.contains('?')) '&' else '?'
        val redirectURL = "$AUTH_REDIRECT_URL$redirectSeparator" +
            "state=${transaction.state}&purpose=signup"
        try {
            request(
                path = "/auth/v1/resend?redirect_to=${java.net.URLEncoder.encode(redirectURL, "UTF-8")}",
                method = "POST",
                body = JSONObject()
                    .put("type", "signup")
                    .put("email", cleanEmail)
                    .put("code_challenge", codeChallenge(transaction.codeVerifier))
                    .put("code_challenge_method", "s256")
                    .toString()
            )
        } catch (error: Throwable) {
            if (transactionSelection.wasCreated && isDeterministicAuthInitiationFailure(error)) {
                clearPendingAuthTransaction(PENDING_SIGNUP_KEY, transaction.state)
            }
            throw error
        }
    }

    suspend fun requestPasswordReset(email: String) = withContext(Dispatchers.IO) {
        val cleanEmail = normalizeEmail(email)
        validateEmail(cleanEmail)
        val transaction = beginAuthTransaction(
            key = PENDING_RECOVERY_KEY,
            email = cleanEmail,
            expectedAuthMutationVersion = authMutationSnapshot()
        )
        val redirectSeparator = if (AUTH_REDIRECT_URL.contains('?')) '&' else '?'
        val redirectURL = "$AUTH_REDIRECT_URL$redirectSeparator" +
            "state=${transaction.state}&purpose=recovery"
        try {
            request(
                path = "/auth/v1/recover?redirect_to=${java.net.URLEncoder.encode(redirectURL, "UTF-8")}",
                method = "POST",
                body = JSONObject()
                    .put("email", cleanEmail)
                    .put("code_challenge", codeChallenge(transaction.codeVerifier))
                    .put("code_challenge_method", "s256")
                    .toString()
            )
        } catch (error: Throwable) {
            if (isDeterministicAuthInitiationFailure(error)) {
                clearPendingAuthTransaction(PENDING_RECOVERY_KEY, transaction.state)
            }
            throw error
        }
    }

    fun savedLocalProfiles(): List<SavedLocalProfile> {
        val deletion = localProfileDeletionJournal.snapshot()
        if (deletion.unreadable || deletion.record != null) return emptyList()
        return localProfileRegistry.list()
    }

    internal fun pendingLocalProfileDeletion(): PendingLocalProfileDeletion? =
        localProfileDeletionJournal.pending()

    private fun requireNoPendingLocalProfileDeletion() {
        val deletion = localProfileDeletionJournal.snapshot()
        check(!deletion.unreadable && deletion.record == null) {
            "Local profile cleanup is pending. Restart GymApp and try again."
        }
    }

    internal fun prepareLocalProfileDeletion(
        expectedSession: AccountSession.Local
    ): PendingLocalProfileDeletion = synchronized(authStateLock) {
        val active = _authState.value.session as? AccountSession.Local
            ?: error("The local profile is no longer active.")
        check(active.displayName == expectedSession.displayName) {
            "The local profile changed before deletion."
        }
        val storedProfileId = prefs.all["local_profile_id"] as? String
            ?: error("The local profile identity is unavailable.")
        val storedProfile = localProfileRegistry.findById(storedProfileId)
            ?: error("The saved local profile is unavailable.")
        check(storedProfile.displayName == active.displayName) {
            "The saved local profile owner does not match the active session."
        }
        val physicalDatabaseName = localDatabaseBindingStore.physicalDatabaseName(active)
        val record = PendingLocalProfileDeletion.create(storedProfile, physicalDatabaseName)
            ?: error("The local profile deletion target is invalid.")
        check(localProfileDeletionJournal.mark(record)) {
            "The local profile deletion could not be prepared safely."
        }
        if (!localAuthClearer()) {
            // The durable journal remains authoritative if auth cleanup had an unknown
            // result. Never clear an account sidecar before this point: a rejected or
            // interrupted prepare must not destroy still-active workout state.
            authMutationVersion += 1
            _authState.value = AuthUiState(
                message = LocalizedText(R.string.local_profile_delete_cleanup_pending)
            )
            error("The local profile deletion will continue after restart.")
        }
        authMutationVersion += 1
        remoteStateRevisions.clear()
        _authState.value = AuthUiState()
        record
    }

    internal fun clearPendingLocalProfileDeletionSidecar(
        record: PendingLocalProfileDeletion
    ): Boolean = synchronized(authStateLock) {
        val pending = localProfileDeletionJournal.snapshot()
        pending.record == record && !pending.unreadable &&
            _authState.value.session == null && localSidecarClearer()
    }

    internal fun finalizeLocalProfileDeletion(record: PendingLocalProfileDeletion): Boolean {
        val pending = localProfileDeletionJournal.snapshot()
        if (pending.unreadable || pending.record != record) return false
        val session = AccountSession.Local(record.displayName)
        if (!localDatabaseBindingStore.removeDeletedSession(
                session,
                record.physicalDatabaseName
            )
        ) {
            return false
        }
        if (!localProfileRegistry.remove(record.profileId)) return false
        return localProfileDeletionJournal.clear(record)
    }

    fun setLocal(displayNameOrProfileId: String, resumeExisting: Boolean = false) {
        synchronized(authStateLock) {
            check(_authState.value.session == null) { "The account changed before the local profile opened." }
            requireNoPendingLocalProfileDeletion()
            val existingProfile = if (resumeExisting) {
                localProfileRegistry.findById(displayNameOrProfileId)
                    ?: error("This saved profile is no longer available.")
            } else {
                null
            }
            val candidate = existingProfile?.displayName
                ?: displayNameOrProfileId.trim()
            val validatedName = if (resumeExisting) {
                normalizedLocalDisplayNameOrNull(candidate)
            } else {
                validatedNewLocalDisplayNameOrNull(candidate)
            } ?: throw IllegalArgumentException(
                "Display name must be 2–32 characters and use letters, numbers, spaces, dot, dash or underscore."
            )
            val session = AccountSession.Local(validatedName)
            val bindingBefore = localDatabaseBindingStore.snapshot(session)
                ?: error("The local workout database binding is corrupt.")
            val alreadySaved = localProfileRegistry.contains(validatedName)
            check(resumeExisting || !alreadySaved) {
                if (alreadySaved) {
                    "A saved local profile already uses this name. Select it from Saved profiles."
                } else {
                    "The selected local profile is no longer available."
                }
            }
            if (!alreadySaved) {
                check(localProfileRegistry.canAdd(validatedName)) {
                    "The saved local profile limit was reached."
                }
            }
            val registered = if (resumeExisting) {
                localDatabaseBindingStore.restoreStoredSession(
                    session,
                    allowPendingLogicalCreation = existingProfile != null
                )
            } else {
                localDatabaseBindingStore.registerNewSession(session)
            }
            check(registered) {
                "The local workout database could not be safely registered."
            }
            val registryBefore = localProfileRegistry.snapshot()
            val profileId = existingProfile?.id ?: UUID.randomUUID().toString()
            if (!alreadySaved) {
                if (!localProfileRegistry.ensurePresent(validatedName, profileId)) {
                    val registryRestored = localProfileRegistry.restore(registryBefore)
                    val bindingRolledBack = localDatabaseBindingStore.restore(bindingBefore)
                    check(registryRestored && bindingRolledBack) {
                        "The rejected local profile could not be rolled back safely."
                    }
                    error("The local profile could not be added safely.")
                }
            }
            val authPreferencesBefore = sharedPreferencesSnapshot(prefs)
            val persisted = runCatching {
                localAuthCommitter(
                    prefs.edit()
                    .putString("mode", "local")
                    .putString("local_name", session.displayName)
                    .putString("local_profile_id", profileId)
                    .remove("cloud")
                    .remove(NEEDS_PASSWORD_UPDATE_KEY)
                    .remove(PENDING_SIGNUP_KEY)
                    .remove(PENDING_RECOVERY_KEY)
                )
            }.getOrDefault(false)
            if (!persisted) {
                val authRestored = restoreSharedPreferencesSnapshot(prefs, authPreferencesBefore)
                val registryRestored = localProfileRegistry.restore(registryBefore)
                val bindingRolledBack = localDatabaseBindingStore.restore(bindingBefore)
                check(authRestored && registryRestored && bindingRolledBack) {
                    "The rejected local profile could not be rolled back safely."
                }
                error("The local account could not be persisted.")
            }
            check(secureAuthStore.clear()) {
                "Protected cloud credentials could not be cleared for the local account transition."
            }
            val physicalDatabaseName = runCatching {
                localDatabaseBindingStore.physicalDatabaseName(session)
            }.getOrElse { error ->
                rollbackRejectedLocalProfile(
                    session = session,
                    authPreferencesBefore = authPreferencesBefore,
                    registryBefore = registryBefore,
                    bindingBefore = bindingBefore,
                    cause = error
                )
            }
            val materialized = runCatching {
                localDatabaseMaterializer(physicalDatabaseName)
            }.getOrDefault(false)
            if (!materialized || !localDatabaseBindingStore.finalizeMaterializedSession(session)) {
                val databaseRolledBack = resumeExisting || localDatabaseRollback(physicalDatabaseName)
                rollbackRejectedLocalProfile(
                    session = session,
                    authPreferencesBefore = authPreferencesBefore,
                    registryBefore = registryBefore,
                    bindingBefore = bindingBefore,
                    additionalRollbackSucceeded = databaseRolledBack
                )
            }
            if (!localSidecarClearer()) {
                val databaseRolledBack = resumeExisting || localDatabaseRollback(physicalDatabaseName)
                rollbackRejectedLocalProfile(
                    session = session,
                    authPreferencesBefore = authPreferencesBefore,
                    registryBefore = registryBefore,
                    bindingBefore = bindingBefore,
                    additionalRollbackSucceeded = databaseRolledBack
                )
            }
            authMutationVersion += 1
            remoteStateRevisions.clear()
            _authState.value = AuthUiState(session = session)
        }
    }

    private fun rollbackRejectedLocalProfile(
        session: AccountSession.Local,
        authPreferencesBefore: Map<String, *>,
        registryBefore: LocalProfileRegistrySnapshot,
        bindingBefore: LocalDatabaseBindingSnapshot,
        additionalRollbackSucceeded: Boolean = true,
        cause: Throwable? = null
    ): Nothing {
        val authRestored = restoreSharedPreferencesSnapshot(prefs, authPreferencesBefore)
        val registryRestored = localProfileRegistry.restore(registryBefore)
        val bindingRolledBack = localDatabaseBindingStore.restore(bindingBefore)
        check(
            authRestored && registryRestored && bindingRolledBack &&
                additionalRollbackSucceeded
        ) {
            "The rejected local profile could not be rolled back safely."
        }
        throw IllegalStateException("The local workout database could not be activated.", cause)
    }

    internal fun testSeedLiveWorkoutSidecar(
        session: AccountSession.Cloud,
        binding: LiveWorkoutBinding
    ): Boolean = liveWorkoutSidecarStore.save(session, binding)

    internal fun testLoadLiveWorkoutSidecar(
        session: AccountSession.Cloud
    ): LiveWorkoutBinding? = liveWorkoutSidecarStore.load(session)

    fun setLoading(isLoading: Boolean) {
        synchronized(authStateLock) {
            _authState.value = _authState.value.copy(isLoading = isLoading, message = null)
        }
    }

    fun setMessage(message: LocalizedText?, isError: Boolean = true) {
        synchronized(authStateLock) {
            _authState.value = _authState.value.copy(
                isLoading = false,
                message = message,
                messageIsError = isError
            )
        }
    }

    fun showEmailConfirmation(email: String) {
        val cleanEmail = normalizeEmail(email)
        validateEmail(cleanEmail)
        synchronized(authStateLock) {
            _authState.value = _authState.value.copy(
                isLoading = false,
                message = null,
                messageIsError = false,
                pendingConfirmationEmail = cleanEmail
            )
        }
    }

    fun dismissEmailConfirmation(clearPendingRequest: Boolean) {
        if (clearPendingRequest) {
            clearPendingAuthTransaction(PENDING_SIGNUP_KEY)
        }
        synchronized(authStateLock) {
            _authState.value = _authState.value.copy(
                isLoading = false,
                message = null,
                pendingConfirmationEmail = null
            )
        }
    }

    fun logout() {
        var pushInstallationId: String? = null
        val revokeRequest = synchronized(authStateLock) {
            val capturedSession = _authState.value.session
            val capturedRequest = localCloudLogoutRequest(capturedSession)
            pushInstallationId = (capturedSession as? AccountSession.Cloud)?.let { session ->
                runCatching { pushInstallationForLogout?.invoke(session) }.getOrNull()
            }
            authMutationVersion += 1
            remoteStateRevisions.clear()
            val preferencesCleared = clearAllAuthStorageSynchronously()
            if (!preferencesCleared) {
                // A storage failure must never keep the captured access token active in memory.
                // Retry the disk clear asynchronously while the process remains signed out.
                prefs.edit().clear().apply()
            }
            _authState.value = signedOutAuthStateAfterLocalLogout(preferencesCleared)
            capturedRequest
        }
        if (revokeRequest != null) {
            logoutRevokeScope.launch {
                pushInstallationId?.let { installationId ->
                    // Revoke the account-bound delivery address before revoking the auth token.
                    // Local push state was already cleared synchronously by the provider.
                    // The mutex drains an in-flight registration first, so that this final
                    // revocation cannot be followed by a stale server-side re-registration.
                    pushRpcGate.runExclusive {
                        try {
                            request(
                                path = "/rest/v1/rpc/notification_revoke_installation",
                                method = "POST",
                                token = revokeRequest.accessToken,
                                body = pushRevocationRequestJson(installationId),
                                maxResponseBytes = 4 * 1_024
                            )
                        } catch (_: Exception) {
                            // Offline logout must remain local-first and successful.
                        }
                    }
                }
                // This request is deliberately detached from auth state. Its captured token
                // belongs to the locally invalidated generation, so a late result cannot
                // restore or otherwise alter a newer session.
                try {
                    request(
                        path = revokeRequest.path,
                        method = revokeRequest.method,
                        token = revokeRequest.accessToken,
                        maxResponseBytes = MAX_CLOUD_ERROR_RESPONSE_BYTES
                    )
                } catch (_: Exception) {
                    // Local logout must remain successful while offline or if revocation fails.
                }
            }
        }
    }

    internal fun setPushInstallationForLogout(
        provider: (AccountSession.Cloud) -> String?
    ) {
        pushInstallationForLogout = provider
    }

    suspend fun completeAuthCallback(uri: Uri): AuthCallbackResult = withContext(Dispatchers.IO) {
        completePKCEAuthCallback(uri, authMutationSnapshot())
    }

    private fun completePKCEAuthCallback(
        uri: Uri,
        initialAuthMutationVersion: Long
    ): AuthCallbackResult {
        val stateValues = uri.getQueryParameters("state")
        val purposeValues = uri.getQueryParameters("purpose")
        val codeValues = uri.getQueryParameters("code")
        val errorValues = uri.getQueryParameters("error")
        val descriptionValues = uri.getQueryParameters("error_description")
        val errorCodeValues = uri.getQueryParameters("error_code")
        require(
            isStructurallySafePKCECallback(
                queryKeys = uri.queryParameterNames,
                hasFragment = !uri.fragment.isNullOrEmpty(),
                receivedStates = stateValues,
                purposes = purposeValues,
                codes = codeValues,
                errors = errorValues,
                descriptions = descriptionValues,
                errorCodes = errorCodeValues
            )
        ) {
            "Authentication rejected an unsafe or malformed callback. Request a new email."
        }

        val purpose = purposeValues.single()
        val pendingKey = if (purpose == "recovery") PENDING_RECOVERY_KEY else PENDING_SIGNUP_KEY
        val transaction = pendingAuthTransaction(pendingKey)
        require(
            isExpectedAuthState(
                receivedStates = stateValues,
                expectedState = transaction?.state,
                pendingIsFresh = transaction?.isFresh() == true
            )
        ) {
            "This authentication request was not started on this device or has expired. Request a new email."
        }
        val validTransaction = checkNotNull(transaction)

        val callbackError = descriptionValues.singleOrNull()?.takeIf { it.isNotBlank() }
            ?: errorValues.singleOrNull()?.takeIf { it.isNotBlank() }
        require(callbackError == null) { callbackError.orEmpty() }
        val authCode = codeValues.singleOrNull().orEmpty()
        require(isValidPKCEAuthCode(authCode)) {
            "Authentication link did not contain a valid authorization code. Request a new email."
        }

        val expectedAuthMutationVersion = beginAuthAttempt(initialAuthMutationVersion)
        val authResponse = JSONObject(
            request(
                path = "/auth/v1/token?grant_type=pkce",
                method = "POST",
                body = JSONObject()
                    .put("auth_code", authCode)
                    .put("code_verifier", validTransaction.codeVerifier)
                    .toString()
            )
        )
        val session = cloudSessionFromAuthResponse(authResponse)
        require(normalizeEmail(session.email) == validTransaction.email) {
            "Authentication returned a different account. Request a new email."
        }
        val isRecovery = purpose == "recovery"
        synchronized(authStateLock) {
            check(authMutationVersion == expectedAuthMutationVersion) {
                INACTIVE_CLOUD_SESSION_MESSAGE
            }
            requireNoPendingLocalProfileDeletion()
            authMutationVersion += 1
            remoteStateRevisions.clear()
            persist(session)
            clearPendingAuthTransaction(pendingKey, validTransaction.state)
            prefs.edit().putBoolean(NEEDS_PASSWORD_UPDATE_KEY, isRecovery).apply()
            _authState.value = AuthUiState(
                session = session,
                messageIsError = false,
                needsPasswordUpdate = isRecovery
            )
        }
        return AuthCallbackResult(session = session, kind = authCallbackKind(purpose))
    }

    suspend fun updatePassword(password: String) = withContext(Dispatchers.IO) {
        validateNewPassword(password)
        val session = synchronized(authStateLock) {
            _authState.value.session as? AccountSession.Cloud
        } ?: error("Password recovery session is no longer available. Request a new reset email.")
        val freshSession = freshCloudSession(session)
        authenticatedRequest(
            session = freshSession,
            path = "/auth/v1/user",
            method = "PUT",
            body = passwordUpdateBody(newPassword = password)
        )
        synchronized(authStateLock) {
            val activeSession = activeCloudSessionFor(_authState.value.session, freshSession)
                ?: error(INACTIVE_CLOUD_SESSION_MESSAGE)
            prefs.edit().remove(NEEDS_PASSWORD_UPDATE_KEY).apply()
            _authState.value = _authState.value.copy(
                session = activeSession,
                isLoading = false,
                message = LocalizedText(R.string.auth_message_password_updated),
                messageIsError = false,
                needsPasswordUpdate = false
            )
        }
    }

    suspend fun changePassword(
        currentPassword: String,
        newPassword: String,
        nonce: String? = null
    ) = withContext(Dispatchers.IO) {
        require(currentPassword.isNotEmpty()) { "Enter your current password." }
        require(currentPassword.toByteArray(Charsets.UTF_8).size <= 1_024) {
            "Current password is too long."
        }
        validateNewPassword(newPassword)
        require(currentPassword != newPassword) {
            "Choose a new password that differs from the current password."
        }
        if (nonce != null) {
            require(isValidPasswordReauthenticationNonce(nonce)) {
                "Enter the verification code sent to your email."
            }
        }
        val session = synchronized(authStateLock) {
            _authState.value.session as? AccountSession.Cloud
        } ?: error(INACTIVE_CLOUD_SESSION_MESSAGE)
        val freshSession = freshCloudSession(session)
        try {
            authenticatedRequest(
                session = freshSession,
                path = "/auth/v1/user",
                method = "PUT",
                body = passwordUpdateBody(
                    newPassword = newPassword,
                    currentPassword = currentPassword,
                    nonce = nonce
                )
            )
        } catch (error: SupabaseHttpException) {
            if (nonce == null && isPasswordReauthenticationRequired(
                    error.errorCode,
                    error.providerMessage
                )
            ) {
                authenticatedRequest(
                    session = freshSession,
                    path = "/auth/v1/reauthenticate",
                    method = "GET",
                    maxResponseBytes = MAX_CLOUD_ERROR_RESPONSE_BYTES
                )
                synchronized(authStateLock) {
                    check(activeCloudSessionFor(_authState.value.session, freshSession) != null) {
                        INACTIVE_CLOUD_SESSION_MESSAGE
                    }
                }
                throw PasswordReauthenticationRequiredException()
            }
            throw error
        }
        synchronized(authStateLock) {
            val activeSession = activeCloudSessionFor(_authState.value.session, freshSession)
                ?: error(INACTIVE_CLOUD_SESSION_MESSAGE)
            _authState.value = _authState.value.copy(
                session = activeSession,
                isLoading = false,
                message = LocalizedText(R.string.auth_message_password_updated),
                messageIsError = false
            )
        }
    }

    /** Deletes the authenticated Supabase account. Local account data is cleared by the caller. */
    suspend fun deleteCloudAccount(
        expectedSession: AccountSession.Cloud,
        currentPassword: String
    ): AccountSession.Cloud = withContext(Dispatchers.IO) {
        require(currentPassword.isNotEmpty()) { "Enter your current password." }
        require(currentPassword.toByteArray(Charsets.UTF_8).size <= 1_024) {
            "Current password is too long."
        }
        val session = synchronized(authStateLock) {
            activeCloudSessionFor(_authState.value.session, expectedSession)
        } ?: error(INACTIVE_CLOUD_SESSION_MESSAGE)
        val reauthenticated = cloudSessionFromAuthResponse(
            JSONObject(
                request(
                    path = "/auth/v1/token?grant_type=password",
                    method = "POST",
                    body = JSONObject()
                        .put("email", session.email)
                        .put("password", currentPassword)
                        .toString()
                )
            )
        )
        require(reauthenticated.userId == session.userId &&
            reauthenticated.email.equals(session.email, ignoreCase = true)) {
            "Account reauthentication returned a different owner."
        }
        val freshSession = synchronized(authStateLock) {
            activeCloudSessionFor(_authState.value.session, session)
                ?: error(INACTIVE_CLOUD_SESSION_MESSAGE)
            persist(reauthenticated)
            _authState.value = _authState.value.copy(session = reauthenticated)
            reauthenticated
        }
        val requestSession = requireActiveCloudSession(freshSession)
        val preparationRequest = cloudAccountDeletionPreparationRequest()
        val grant = accountDeletionGrantFromResponse(
            request(
                path = preparationRequest.path,
                method = preparationRequest.method,
                token = requestSession.accessToken,
                body = preparationRequest.body,
                additionalHeaders = preparationRequest.headers,
                maxResponseBytes = 2 * 1_024
            )
        ) ?: error("Cloud account deletion preparation returned an invalid response.")
        val deletionRequest = cloudAccountDeletionRequest(grant)
        val deletionRecord = checkNotNull(
            PendingCloudAccountDeletion.fromSession(freshSession)
        ) { "Cloud account identity is invalid." }
        val response = try {
            runPreparedAccountDeletionRequest(
                persistIntent = {
                    accountDeletionJournal.markPending(freshSession)
                },
                request = {
                    request(
                        path = deletionRequest.path,
                        method = deletionRequest.method,
                        token = requestSession.accessToken,
                        body = deletionRequest.body,
                        additionalHeaders = deletionRequest.headers
                    )
                }
            )
        } catch (error: AccountDeletionPreparationException) {
            // Nothing crossed the network boundary, so the current account remains authoritative.
            throw error
        } catch (error: SupabaseHttpException) {
            if (error.responseCode in 400..499) {
                // A bounded 4xx proves this attempt did not delete the account.
                accountDeletionJournal.clear(deletionRecord)
                if (error.responseCode == 401) expireCloudSession(freshSession)
            } else {
                signOutAfterUnknownAccountDeletionOutcome(freshSession)
            }
            throw error
        } catch (error: Throwable) {
            // Network failure, cancellation, response overflow, and malformed transport state can
            // all happen after dispatch. Keep the owner marker and make local state inaccessible.
            signOutAfterUnknownAccountDeletionOutcome(freshSession)
            throw error
        }
        if (!isSuccessfulCloudAccountDeletionResponse(response)) {
            signOutAfterUnknownAccountDeletionOutcome(freshSession)
            error("Cloud account deletion returned an invalid response.")
        }
        // The exact success response is the commit point. A concurrent local logout must
        // not turn a completed remote deletion into an apparent failure or skip cleanup.
        freshSession
    }

    internal fun clearPendingCloudAccountDeletion(
        expectedSession: AccountSession.Cloud
    ): Boolean {
        val record = PendingCloudAccountDeletion.fromSession(expectedSession) ?: return false
        return accountDeletionJournal.clear(record)
    }

    private fun signOutAfterUnknownAccountDeletionOutcome(
        expectedSession: AccountSession.Cloud
    ) = synchronized(authStateLock) {
        val fallbackState = authStateAfterUnknownAccountDeletionOutcome(
            current = _authState.value.session,
            deletedSession = expectedSession
        ) ?: return@synchronized
        authMutationVersion += 1
        remoteStateRevisions.clear()
        liveWorkoutSidecarStore.clearCloudAccountLocalState(expectedSession.userId)
        if (!clearAllAuthStorageSynchronously()) {
            prefs.edit().clear().apply()
        }
        _authState.value = fallbackState
    }

    internal fun completeCloudAccountDeletion(
        expectedSession: AccountSession.Cloud
    ): CloudAccountDeletionCompletion = synchronized(authStateLock) {
        val disposition = cloudAccountDeletionSessionDisposition(
            current = _authState.value.session,
            deletedSession = expectedSession
        )
        var durableAuthCleanupCompleted = false
        if (disposition == CloudAccountDeletionSessionDisposition.ClearCapturedSession) {
            authMutationVersion += 1
            remoteStateRevisions.clear()
            liveWorkoutSidecarStore.clearCloudAccountLocalState(expectedSession.userId)
            val preferencesCleared = clearAllAuthStorageSynchronously()
            durableAuthCleanupCompleted = preferencesCleared
            if (!preferencesCleared) {
                // The server-side account is already gone. Keep the process signed out and
                // schedule a second best-effort disk clear instead of reviving a dead session.
                prefs.edit().clear().apply()
            }
            _authState.value = AuthUiState(
                message = if (preferencesCleared) {
                    null
                } else {
                    LocalizedText(R.string.auth_message_logout_failed)
                },
                messageIsError = !preferencesCleared
            )
        } else if (disposition == CloudAccountDeletionSessionDisposition.AlreadySignedOut) {
            // A concurrent logout may have cleared only the in-memory state. Retry the durable
            // clear before allowing the deletion journal to retire.
            liveWorkoutSidecarStore.clearCloudAccountLocalState(expectedSession.userId)
            durableAuthCleanupCompleted = clearAllAuthStorageSynchronously()
            if (!durableAuthCleanupCompleted) prefs.edit().clear().apply()
        }
        // When another account has already become active, retain the owner-bound journal until
        // startup recovery. This avoids a crash window where an asynchronous preference write
        // could otherwise leave the deleted session on disk, and the journal never targets the
        // replacement owner.
        CloudAccountDeletionCompletion(
            disposition = disposition,
            durableAuthCleanupCompleted = durableAuthCleanupCompleted
        )
    }

    suspend fun freshCloudSession(session: AccountSession.Cloud): AccountSession.Cloud {
        val currentSession = requireActiveCloudSession(session)
        if (!currentSession.needsRefresh()) return currentSession
        if (currentSession.refreshToken.isNullOrBlank()) {
            expireCloudSession(currentSession)
            error(INACTIVE_CLOUD_SESSION_MESSAGE)
        }

        return refreshMutex.withLock {
            val latestSession = requireActiveCloudSession(session)
            if (!latestSession.needsRefresh() || latestSession.refreshToken.isNullOrBlank()) {
                if (latestSession.needsRefresh()) {
                    expireCloudSession(latestSession)
                    error(INACTIVE_CLOUD_SESSION_MESSAGE)
                }
                latestSession
            } else {
                refreshSession(latestSession)
            }
        }
    }

    suspend fun loadRemoteState(session: AccountSession.Cloud): JSONObject? = withContext(Dispatchers.IO) {
        remoteStateMutex.withLock {
            val freshSession = freshCloudSession(session)
            val key = remoteRevisionKey(freshSession)
            val row = fetchRemoteStateRow(freshSession)
            cacheRemoteStateRevision(
                session = freshSession,
                key = key,
                revision = row?.revision ?: RemoteStateRevision.Missing
            )
            row?.state
        }
    }

    internal suspend fun loadActivityOnlyWorkouts(
        session: AccountSession.Cloud
    ): ActivityOnlyWorkoutReadResult = withContext(Dispatchers.IO) {
        activityOnlyWorkoutMutex.withLock {
            val freshSession = freshCloudSession(session)
            val response = try {
                authenticatedRequest(
                    session = freshSession,
                    path = "/rest/v1/rpc/garmin_read_activity_only_workouts",
                    method = "POST",
                    body = "{}",
                    maxResponseBytes = MAX_ACTIVITY_ONLY_CLOUD_RESPONSE_BYTES
                )
            } catch (error: SupabaseHttpException) {
                if (isUnavailableActivityOnlyWorkoutRpc(
                        responseCode = error.responseCode,
                        errorCode = error.errorCode
                    )
                ) {
                    return@withLock ActivityOnlyWorkoutReadResult.Unavailable
                }
                throw error
            }
            requireActiveCloudSession(freshSession)
            ActivityOnlyWorkoutReadResult.Available(
                parseActivityOnlyWorkoutReadResponse(response)
            )
        }
    }

    /**
     * Sends a pre-identified full CAS snapshot. Every transient retry reuses the exact serialized
     * body, so a timeout after commit can only become an idempotent server replay. UUID lifecycle
     * belongs to the durable Room journal and is never changed by this transport method.
     */
    internal suspend fun syncActivityOnlyWorkouts(
        session: AccountSession.Cloud,
        expectedRevision: Long,
        requestId: String,
        items: List<ActivityOnlyWorkoutItem>
    ): ActivityOnlyWorkoutSyncResponse {
        val exactBody = activityOnlyWorkoutSyncRequestJson(
            expectedRevision = expectedRevision,
            requestId = requestId,
            items = items
        ).toString()
        return withContext(Dispatchers.IO) {
            activityOnlyWorkoutMutex.withLock {
                retryActivityOnlyWorkoutOutcomeUnknown(
                    isRetryableSqlFailure = { error ->
                        error is SupabaseHttpException &&
                            isRetryableActivityOnlyWorkoutSqlState(error.errorCode)
                    }
                ) {
                    val freshSession = freshCloudSession(session)
                    val response = authenticatedRequest(
                        session = freshSession,
                        path = "/rest/v1/rpc/garmin_sync_activity_only_workouts",
                        method = "POST",
                        body = exactBody,
                        maxResponseBytes = MAX_ACTIVITY_ONLY_CLOUD_RESPONSE_BYTES
                    )
                    requireActiveCloudSession(freshSession)
                    parseActivityOnlyWorkoutSyncResponse(response)
                }
            }
        }
    }

    suspend fun saveRemoteState(
        session: AccountSession.Cloud,
        state: JSONObject,
        xp: Int,
        level: Int,
        workouts: Int,
        workoutDurations: JSONArray = JSONArray()
    ) = withContext(Dispatchers.IO) {
        remoteStateMutex.withLock {
            val freshSession = freshCloudSession(session)
            val key = remoteRevisionKey(freshSession)
            val revision = remoteStateRevisions[key] ?: run {
                val existingRow = fetchRemoteStateRow(freshSession)
                if (existingRow != null) {
                    cacheRemoteStateRevision(
                        session = freshSession,
                        key = key,
                        revision = RemoteStateRevision.Conflicted
                    )
                    error(STALE_REMOTE_STATE_MESSAGE)
                }
                RemoteStateRevision.Missing.also {
                    cacheRemoteStateRevision(
                        session = freshSession,
                        key = key,
                        revision = it
                    )
                }
            }
            val writeRequest = remoteStateWriteRequest(freshSession.userId, revision)
            val writeBody = when (revision) {
                RemoteStateRevision.Missing -> JSONArray()
                    .put(
                        JSONObject()
                            .put("user_id", freshSession.userId)
                            .put("state", state)
                    )
                    .toString()

                is RemoteStateRevision.Present -> JSONObject()
                    .put("state", state)
                    .toString()

                RemoteStateRevision.Conflicted -> error(STALE_REMOTE_STATE_MESSAGE)
            }
            val revisionResponse = authenticatedRequest(
                session = freshSession,
                path = writeRequest.path,
                method = writeRequest.method,
                prefer = writeRequest.prefer,
                body = writeBody
            )
            requireActiveCloudSession(freshSession)
            val storedRevision = singleRemoteStateRevision(revisionResponse)
            if (storedRevision == null) {
                cacheRemoteStateRevision(
                    session = freshSession,
                    key = key,
                    revision = RemoteStateRevision.Conflicted
                )
                error(STALE_REMOTE_STATE_MESSAGE)
            }
            cacheRemoteStateRevision(
                session = freshSession,
                key = key,
                revision = storedRevision
            )

            requireActiveCloudSession(freshSession)
            authenticatedRequest(
                session = freshSession,
                path = "/rest/v1/profiles?on_conflict=user_id",
                method = "POST",
                prefer = "resolution=merge-duplicates,missing=default",
                body = JSONArray()
                    .put(
                        JSONObject()
                            .put("user_id", freshSession.userId)
                            .put("display_name", freshSession.displayName)
                            .put("xp", xp.coerceAtLeast(0))
                            .put("level", level.coerceAtLeast(1))
                            .put("workouts", workouts.coerceAtLeast(0))
                    )
                    .toString()
            )
            requireActiveCloudSession(freshSession)

            try {
                val durationResponse = authenticatedRequest(
                    session = freshSession,
                    path = "/rest/v1/rpc/social_sync_workout_durations",
                    method = "POST",
                    body = JSONObject().put("p_items", workoutDurations).toString()
                )
                parseWorkoutDurationSyncAcknowledgement(
                    rawResponse = durationResponse,
                    expectedCount = workoutDurations.length()
                )
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                // The core row and public profile are already committed. Duration is an
                // optional forward-compatible sidecar, so a transient RPC failure must not
                // turn that successful write into a stale-revision retry loop.
            }
            requireActiveCloudSession(freshSession)
        }
    }

    internal suspend fun loadSocialDashboard(session: AccountSession.Cloud): SocialDashboard =
        socialRpc(session, "social_dashboard", JSONObject()) { response ->
            parseSocialDashboard(response)
        }

    internal suspend fun loadSocialMyFriendCode(
        session: AccountSession.Cloud
    ): SocialMyFriendCode? = try {
        socialRpc(
            session = session,
            function = "social_my_friend_code",
            body = JSONObject(),
            maxResponseBytes = SOCIAL_MY_FRIEND_CODE_MAX_BYTES,
            parser = ::parseSocialMyFriendCode
        )
    } catch (error: SupabaseHttpException) {
        if (isUnavailableSocialMyFriendCodeRpc(error.responseCode, error.errorCode)) {
            null
        } else {
            throw error
        }
    }

    internal suspend fun loadSocialFriendDetails(
        session: AccountSession.Cloud,
        profileId: String
    ): SocialFriendDetails {
        require(isValidSocialProfileId(profileId)) { "Friend profile ID is invalid." }
        return socialRpc(
            session = session,
            function = "social_friend_details",
            body = JSONObject().put("p_profile_id", profileId),
            parser = ::parseSocialFriendDetails
        ).also { details ->
            require(details.friend.profileId == profileId) { "Social response is invalid." }
        }
    }

    internal suspend fun loadSocialFriendWorkoutPage(
        session: AccountSession.Cloud,
        profileId: String,
        expectedActivityRevision: String? = null
    ): SocialFriendWorkoutPage? {
        require(isValidSocialProfileId(profileId)) { "Friend profile ID is invalid." }
        val body = JSONObject()
            .put("p_profile_id", profileId)
            .put("p_cursor", JSONObject.NULL)
            .put("p_limit", SOCIAL_MAX_FRIEND_WORKOUT_PAGE)
        expectedActivityRevision?.let { body.put("p_expected_activity_revision", it) }
        return try {
            socialRpc(
                session = session,
                function = "social_friend_workout_page",
                body = body,
                parser = ::parseSocialFriendWorkoutPage
            ).also { page ->
                require(page.profileId == profileId) { "Social response is invalid." }
                require(expectedActivityRevision == null ||
                    page.activityRevision == expectedActivityRevision) {
                    "Social response is invalid."
                }
            }
        } catch (error: SupabaseHttpException) {
            if (error.errorCode in setOf("P0002", "PGRST202", "42883")) null else throw error
        }
    }

    internal suspend fun loadSocialFriendWorkoutDetailCapability(
        session: AccountSession.Cloud,
        profileId: String
    ): SocialFriendWorkoutDetailCapability {
        require(isValidSocialProfileId(profileId)) { "Friend profile ID is invalid." }
        return try {
            socialRpc(
                session = session,
                function = "social_friend_workout_detail_capability",
                body = JSONObject().put("p_profile_id", profileId),
                parser = ::parseSocialFriendWorkoutDetailCapability
            )
        } catch (error: SupabaseHttpException) {
            if (isUnavailableSocialMyFriendCodeRpc(error.responseCode, error.errorCode)) {
                SocialFriendWorkoutDetailCapability(available = false)
            } else {
                throw error
            }
        }
    }

    internal suspend fun loadSocialWorkoutDetailPrivacy(
        session: AccountSession.Cloud
    ): SocialWorkoutDetailPrivacy = socialRpc(
        session = session,
        function = "social_workout_detail_privacy",
        body = JSONObject(),
        parser = ::parseSocialWorkoutDetailPrivacy
    )

    internal suspend fun updateSocialWorkoutDetailPrivacy(
        session: AccountSession.Cloud,
        shareWorkoutDetails: Boolean,
        expectedRevision: Int
    ): SocialWorkoutDetailPrivacy {
        require(expectedRevision > 0) { "Privacy revision is invalid." }
        return socialRpc(
            session = session,
            function = "social_update_workout_detail_privacy",
            body = JSONObject()
                .put("p_share_workout_details", shareWorkoutDetails)
                .put("p_expected_revision", expectedRevision),
            parser = ::parseSocialWorkoutDetailPrivacy
        ).also { result ->
            require(result.shareWorkoutDetails == shareWorkoutDetails) {
                "Social response is invalid."
            }
        }
    }

    internal suspend fun sendSocialFriendRequest(
        session: AccountSession.Cloud,
        friendCode: String
    ) {
        val normalized = requireNotNull(normalizeSocialFriendCode(friendCode)) {
            "Friend code is invalid."
        }
        socialRpc(
            session = session,
            function = "social_send_friend_request",
            body = JSONObject().put("p_friend_code", normalized),
            parser = ::parseSocialSubmittedMutation
        )
    }

    internal suspend fun respondSocialFriendRequest(
        session: AccountSession.Cloud,
        friendshipId: String,
        decision: String,
        expectedRevision: Int
    ): SocialFriendshipMutation {
        require(isValidSocialFriendshipId(friendshipId)) { "Friend request ID is invalid." }
        require(decision in setOf("accept", "decline")) { "Friend request decision is invalid." }
        require(expectedRevision > 0) { "Friend request revision is invalid." }
        val expectedStatus = if (decision == "accept") "accepted" else "declined"
        return socialRpc(
            session = session,
            function = "social_respond_friend_request",
            body = JSONObject()
                .put("p_friendship_id", friendshipId)
                .put("p_decision", decision)
                .put("p_expected_revision", expectedRevision)
        ) { response ->
            parseSocialFriendshipMutation(response, setOf(expectedStatus))
        }.also { mutation ->
            require(mutation.friendshipId == friendshipId) { "Social response is invalid." }
        }
    }

    internal suspend fun cancelSocialFriendRequest(
        session: AccountSession.Cloud,
        friendshipId: String,
        expectedRevision: Int
    ): SocialFriendshipMutation = socialFriendshipRemovalRpc(
        session = session,
        function = "social_cancel_friend_request",
        friendshipId = friendshipId,
        expectedRevision = expectedRevision
    )

    internal suspend fun removeSocialFriend(
        session: AccountSession.Cloud,
        friendshipId: String,
        expectedRevision: Int
    ): SocialFriendshipMutation = socialFriendshipRemovalRpc(
        session = session,
        function = "social_remove_friend",
        friendshipId = friendshipId,
        expectedRevision = expectedRevision
    )

    internal suspend fun blockSocialProfile(
        session: AccountSession.Cloud,
        profileId: String
    ): SocialBlockMutation = socialBlockRpc(session, profileId, shouldBlock = true)

    internal suspend fun unblockSocialProfile(
        session: AccountSession.Cloud,
        profileId: String
    ): SocialBlockMutation = socialBlockRpc(session, profileId, shouldBlock = false)

    internal suspend fun updateSocialPrivacy(
        session: AccountSession.Cloud,
        privacy: SocialPrivacy,
        expectedRevision: Int
    ): SocialPrivacyMutation {
        require(expectedRevision > 0) { "Privacy revision is invalid." }
        return socialRpc(
            session = session,
            function = "social_update_privacy",
            body = JSONObject()
                .put("p_allow_requests", privacy.allowRequests)
                .put("p_share_progress", privacy.shareProgress)
                .put("p_share_recent_workouts", privacy.shareRecentWorkouts)
                .put("p_share_records", privacy.shareRecords)
                .put("p_expected_revision", expectedRevision),
            parser = ::parseSocialPrivacyMutation
        ).also { mutation ->
            require(mutation.privacy == privacy) { "Social response is invalid." }
        }
    }

    internal suspend fun sendSocialWorkoutInvite(
        session: AccountSession.Cloud,
        profileId: String,
        clientRequestId: String,
        workout: SharedWorkoutPlan
    ) {
        require(isValidSocialProfileId(profileId)) { "Friend profile ID is invalid." }
        require(isValidSocialClientRequestId(clientRequestId)) { "Workout request ID is invalid." }
        val workoutJson = socialWorkoutJson(workout)
        socialRpc(
            session = session,
            function = "social_send_workout_invite",
            body = JSONObject()
                .put("p_profile_id", profileId)
                .put("p_client_request_id", clientRequestId)
                .put("p_workout", workoutJson),
            parser = ::parseSocialSubmittedMutation
        )
    }

    internal suspend fun loadSocialWorkoutInbox(
        session: AccountSession.Cloud,
        cursor: SocialWorkoutInboxCursor? = null,
        limit: Int = SOCIAL_WORKOUT_INBOX_PAGE_SIZE
    ): SocialWorkoutInbox {
        val pageRequest = socialWorkoutInboxPageRequestBody(cursor, limit)
        return try {
            socialRpc(
                session = session,
                function = "social_workout_inbox_page",
                body = pageRequest,
                parser = { raw -> parseSocialWorkoutInboxPage(raw, expectedLimit = limit) }
            )
        } catch (error: SupabaseHttpException) {
            if (cursor == null && isUnavailableSocialWorkoutInboxPageRpc(
                    error.responseCode,
                    error.errorCode
                )
            ) {
                socialRpc(
                    session = session,
                    function = "social_workout_inbox",
                    body = JSONObject(),
                    parser = ::parseSocialWorkoutInbox
                )
            } else {
                throw error
            }
        }
    }

    internal suspend fun loadSocialWorkoutInvitePlan(
        session: AccountSession.Cloud,
        inviteId: String,
        expectedRevision: Int
    ): SharedWorkoutPlan? {
        require(isValidSocialWorkoutInviteId(inviteId)) { "Workout invite ID is invalid." }
        require(expectedRevision > 0) { "Workout invite revision is invalid." }
        return try {
            socialRpc(
                session = session,
                function = "social_workout_invite_plan",
                body = JSONObject()
                    .put("p_invite_id", inviteId)
                    .put("p_expected_revision", expectedRevision),
                parser = ::parseSocialWorkoutInvitePlan
            ).also { plan ->
                require(plan.inviteId == inviteId &&
                    plan.inviteRevision == expectedRevision) {
                    "Social response is invalid."
                }
            }.workout
        } catch (error: SupabaseHttpException) {
            if (error.errorCode == "P0002") null else throw error
        }
    }

    internal suspend fun respondSocialWorkoutInvite(
        session: AccountSession.Cloud,
        inviteId: String,
        decision: String,
        expectedRevision: Int
    ): SocialWorkoutInviteMutation {
        require(isValidSocialWorkoutInviteId(inviteId)) { "Workout invite ID is invalid." }
        require(decision in setOf("accept", "decline")) { "Workout invite decision is invalid." }
        require(expectedRevision > 0) { "Workout invite revision is invalid." }
        val expectedStatus = if (decision == "accept") "accepted" else "declined"
        return socialRpc(
            session = session,
            function = "social_respond_workout_invite",
            body = JSONObject()
                .put("p_invite_id", inviteId)
                .put("p_decision", decision)
                .put("p_expected_revision", expectedRevision),
            parser = ::parseSocialWorkoutInviteMutation
        ).also { mutation ->
            require(mutation.inviteId == inviteId && mutation.status == expectedStatus) {
                "Social response is invalid."
            }
        }
    }

    internal suspend fun cancelSocialWorkoutInvite(
        session: AccountSession.Cloud,
        inviteId: String,
        expectedRevision: Int
    ): SocialWorkoutInviteCancellation {
        require(isValidSocialWorkoutInviteId(inviteId)) { "Workout invite ID is invalid." }
        require(expectedRevision > 0) { "Workout invite revision is invalid." }
        return socialRpc(
            session = session,
            function = "social_cancel_workout_invite",
            body = JSONObject()
                .put("p_invite_id", inviteId)
                .put("p_expected_revision", expectedRevision),
            parser = ::parseSocialWorkoutInviteCancellation
        ).also { mutation ->
            require(mutation.inviteId == inviteId) { "Social response is invalid." }
        }
    }

    internal suspend fun loadLiveWorkoutInbox(
        session: AccountSession.Cloud
    ): LiveWorkoutInbox = liveWorkoutGateway(
        session = session,
        action = "live_inbox",
        body = JSONObject(),
        parser = ::parseLiveWorkoutInbox
    )

    internal suspend fun sendLiveWorkoutInvite(
        session: AccountSession.Cloud,
        profileId: String,
        clientRequestId: String,
        workout: SharedWorkoutPlan
    ): LiveSendInviteResult {
        require(isValidSocialProfileId(profileId)) { "Friend profile ID is invalid." }
        require(isValidSocialClientRequestId(clientRequestId)) { "Workout request ID is invalid." }
        return liveWorkoutGateway(
            session = session,
            action = "live_send_invite",
            body = JSONObject()
                .put("profileId", profileId)
                .put("clientRequestId", clientRequestId)
                .put("workout", liveSendWorkoutJson(workout)),
            parser = ::parseLiveSendInviteResult
        )
    }

    internal suspend fun respondLiveWorkoutInvite(
        session: AccountSession.Cloud,
        roomId: String,
        decision: String,
        expectedRoomRevision: Int,
        clientOperationId: String
    ): LiveRespondInviteResult {
        requireLiveMutationInput(roomId, clientOperationId)
        require(decision in setOf("accept", "decline")) { "Live workout decision is invalid." }
        require(expectedRoomRevision > 0) { "Live workout revision is invalid." }
        return liveWorkoutGateway(
            session = session,
            action = "live_respond_invite",
            body = JSONObject()
                .put("roomId", roomId)
                .put("decision", decision)
                .put("expectedRoomRevision", expectedRoomRevision)
                .put("clientOperationId", clientOperationId),
            parser = ::parseLiveRespondInviteResult
        ).also { require(it.roomId == roomId) { "Live workout response is invalid." } }
    }

    internal suspend fun startLiveWorkout(
        session: AccountSession.Cloud,
        roomId: String,
        expectedRoomRevision: Int,
        clientOperationId: String
    ): LiveStartResult {
        requireLiveMutationInput(roomId, clientOperationId)
        require(expectedRoomRevision > 0) { "Live workout revision is invalid." }
        return liveWorkoutGateway(
            session = session,
            action = "live_start",
            body = JSONObject()
                .put("roomId", roomId)
                .put("expectedRoomRevision", expectedRoomRevision)
                .put("clientOperationId", clientOperationId),
            parser = ::parseLiveStartResult
        ).also { result ->
            val returnedRoomId = when (result) {
                is LiveStartResult.Started -> result.value.roomId
                is LiveStartResult.Closed -> result.value.roomId
            }
            require(returnedRoomId == roomId) { "Live workout response is invalid." }
        }
    }

    internal suspend fun loadLiveWorkoutSnapshot(
        session: AccountSession.Cloud,
        roomId: String
    ): LiveWorkoutSnapshot {
        require(isValidLiveRoomId(roomId)) { "Live workout room ID is invalid." }
        return liveWorkoutGateway(
            session = session,
            action = "live_snapshot",
            body = JSONObject().put("roomId", roomId),
            parser = ::parseLiveWorkoutSnapshot
        ).also { require(it.room.roomId == roomId) { "Live workout response is invalid." } }
    }

    internal suspend fun applyLiveWorkoutSet(
        session: AccountSession.Cloud,
        roomId: String,
        clientOperationId: String,
        expectedProgressRevision: Int,
        kind: String,
        setId: String,
        weight: Double? = null,
        reps: Int? = null
    ): LiveApplyResult {
        requireLiveMutationInput(roomId, clientOperationId)
        require(expectedProgressRevision > 0) { "Live workout progress revision is invalid." }
        require(Regex("^s_[0-9]{2}_[0-9]{2}$").matches(setId)) {
            "Live workout set ID is invalid."
        }
        require(kind in setOf("complete_set", "undo_set")) {
            "Live workout operation is invalid."
        }
        val operation = JSONObject().put("kind", kind).put("setId", setId)
        if (kind == "complete_set") {
            require(weight != null && weight.isFinite() && weight in 0.0..SharedWorkoutLink.MAX_WEIGHT) {
                "Live workout weight is invalid."
            }
            require(reps != null && reps in 1..SharedWorkoutLink.MAX_REPS) {
                "Live workout repetitions are invalid."
            }
            operation.put("weight", weight).put("reps", reps)
        } else {
            require(weight == null && reps == null) { "Live workout operation is invalid." }
        }
        return liveWorkoutGateway(
            session = session,
            action = "live_apply",
            body = JSONObject()
                .put("roomId", roomId)
                .put("clientOperationId", clientOperationId)
                .put("expectedProgressRevision", expectedProgressRevision)
                .put("operation", operation),
            parser = ::parseLiveApplyResult
        ).also { result ->
            val returnedRoomId = when (result) {
                is LiveApplyResult.Applied -> result.value.roomId.also {
                    require(result.value.kind == kind && result.value.setId == setId) {
                        "Live workout response is invalid."
                    }
                }
                is LiveApplyResult.Closed -> result.value.roomId
            }
            require(returnedRoomId == roomId) { "Live workout response is invalid." }
        }
    }

    internal suspend fun finishLiveWorkout(
        session: AccountSession.Cloud,
        roomId: String,
        clientOperationId: String,
        expectedProgressRevision: Int
    ): LiveFinishResult {
        requireLiveMutationInput(roomId, clientOperationId)
        require(expectedProgressRevision > 0) { "Live workout progress revision is invalid." }
        return liveWorkoutGateway(
            session = session,
            action = "live_finish",
            body = JSONObject()
                .put("roomId", roomId)
                .put("clientOperationId", clientOperationId)
                .put("expectedProgressRevision", expectedProgressRevision),
            parser = ::parseLiveFinishResult
        ).also { result ->
            val returnedRoomId = when (result) {
                is LiveFinishResult.Finished -> result.value.roomId
                is LiveFinishResult.Closed -> result.value.roomId
            }
            require(returnedRoomId == roomId) { "Live workout response is invalid." }
        }
    }

    internal suspend fun leaveLiveWorkout(
        session: AccountSession.Cloud,
        roomId: String,
        clientOperationId: String,
        expectedMembershipRevision: Int
    ): LiveEndedResult {
        requireLiveMutationInput(roomId, clientOperationId)
        require(expectedMembershipRevision > 0) { "Live workout membership revision is invalid." }
        return liveWorkoutGateway(
            session = session,
            action = "live_leave",
            body = JSONObject()
                .put("roomId", roomId)
                .put("clientOperationId", clientOperationId)
                .put("expectedMembershipRevision", expectedMembershipRevision)
        ) { parseLiveEndedResult(it, "left") }
            .also { require(it.roomId == roomId) { "Live workout response is invalid." } }
    }

    internal suspend fun cancelLiveWorkout(
        session: AccountSession.Cloud,
        roomId: String,
        clientOperationId: String,
        expectedRoomRevision: Int
    ): LiveEndedResult {
        requireLiveMutationInput(roomId, clientOperationId)
        require(expectedRoomRevision > 0) { "Live workout revision is invalid." }
        return liveWorkoutGateway(
            session = session,
            action = "live_cancel",
            body = JSONObject()
                .put("roomId", roomId)
                .put("clientOperationId", clientOperationId)
                .put("expectedRoomRevision", expectedRoomRevision)
        ) { parseLiveEndedResult(it, "cancelled") }
            .also { require(it.roomId == roomId) { "Live workout response is invalid." } }
    }

    internal suspend fun freshLiveAccessToken(
        session: AccountSession.Cloud
    ): String = withContext(Dispatchers.IO) {
        val freshSession = freshCloudSession(session)
        requireActiveCloudSession(freshSession).accessToken
    }

    internal fun isLiveSessionActive(session: AccountSession.Cloud): Boolean =
        synchronized(authStateLock) {
            activeCloudSessionFor(_authState.value.session, session) != null
        }

    internal fun retainSocialWorkoutInviteRequest(
        session: AccountSession.Cloud,
        fingerprint: String
    ): String? = synchronized(authStateLock) {
        if (activeCloudSessionFor(_authState.value.session, session) == null) null
        else socialWorkoutInviteRequestStore.retainOrCreate(session, fingerprint)
    }

    internal fun clearSocialWorkoutInviteRequest(
        session: AccountSession.Cloud,
        fingerprint: String,
        expectedRequestId: String
    ): Boolean = socialWorkoutInviteRequestStore.clear(
        session,
        fingerprint,
        expectedRequestId
    )

    internal fun clearCloudAccountSocialWorkoutRequestState(userId: String): Boolean =
        socialWorkoutInviteRequestStore.clearCloudAccountLocalState(userId)

    internal suspend fun registerPushInstallation(
        session: AccountSession.Cloud,
        installationId: String,
        providerToken: String,
        locale: String?,
        appVersion: String
    ): PushRegistration = withContext(Dispatchers.IO) {
        pushRpcGate.runExclusive {
            val body = pushRegistrationRequestJson(
                installationId = installationId,
                providerToken = providerToken,
                locale = locale,
                appVersion = appVersion
            )
            val freshSession = freshCloudSession(session)
            val response = authenticatedRequest(
                session = freshSession,
                path = "/rest/v1/rpc/notification_register_installation",
                method = "POST",
                body = body,
                maxResponseBytes = 4 * 1_024
            )
            requireActiveCloudSession(freshSession)
            parsePushRegistrationResponse(response, installationId)
        }
    }

    internal suspend fun revokePushInstallation(
        session: AccountSession.Cloud,
        installationId: String
    ): PushRevocation = withContext(Dispatchers.IO) {
        pushRpcGate.runExclusive {
            val body = pushRevocationRequestJson(installationId)
            val freshSession = freshCloudSession(session)
            val response = authenticatedRequest(
                session = freshSession,
                path = "/rest/v1/rpc/notification_revoke_installation",
                method = "POST",
                body = body,
                maxResponseBytes = 4 * 1_024
            )
            requireActiveCloudSession(freshSession)
            parsePushRevocationResponse(response, installationId)
        }
    }

    private fun requireLiveMutationInput(roomId: String, clientOperationId: String) {
        require(isValidLiveRoomId(roomId)) { "Live workout room ID is invalid." }
        require(isValidSocialClientRequestId(clientOperationId)) {
            "Live workout operation ID is invalid."
        }
    }

    private suspend fun <T> liveWorkoutGateway(
        session: AccountSession.Cloud,
        action: String,
        body: JSONObject,
        parser: (String) -> T
    ): T = withContext(Dispatchers.IO) {
        val requestBody = liveGatewayRequestJson(action, body)
        val freshSession = freshCloudSession(session)
        val response = try {
            authenticatedRequest(
                session = freshSession,
                path = "/functions/v1/social-live-gateway",
                method = "POST",
                body = requestBody,
                maxResponseBytes = MAX_CLOUD_RESPONSE_BYTES
            )
        } catch (error: SupabaseHttpException) {
            throw LiveWorkoutGatewayException(
                responseCode = error.responseCode,
                errorCode = error.errorCode,
                safeMessage = error.providerMessage?.take(512)
                    ?: "Live workout request failed."
            )
        }
        requireActiveCloudSession(freshSession)
        parser(unwrapLiveGatewaySuccess(response))
    }

    private suspend fun socialFriendshipRemovalRpc(
        session: AccountSession.Cloud,
        function: String,
        friendshipId: String,
        expectedRevision: Int
    ): SocialFriendshipMutation {
        require(isValidSocialFriendshipId(friendshipId)) { "Friendship ID is invalid." }
        require(expectedRevision > 0) { "Friendship revision is invalid." }
        return socialRpc(
            session = session,
            function = function,
            body = JSONObject()
                .put("p_friendship_id", friendshipId)
                .put("p_expected_revision", expectedRevision)
        ) { response ->
            parseSocialFriendshipMutation(response, setOf("removed"))
        }.also { mutation ->
            require(mutation.friendshipId == friendshipId) { "Social response is invalid." }
        }
    }

    private suspend fun socialBlockRpc(
        session: AccountSession.Cloud,
        profileId: String,
        shouldBlock: Boolean
    ): SocialBlockMutation {
        require(isValidSocialProfileId(profileId)) { "Friend profile ID is invalid." }
        val function = if (shouldBlock) "social_block_profile" else "social_unblock_profile"
        return socialRpc(
            session = session,
            function = function,
            body = JSONObject().put("p_profile_id", profileId),
            parser = ::parseSocialBlockMutation
        ).also { mutation ->
            require(mutation.profileId == profileId && mutation.blocked == shouldBlock) {
                "Social response is invalid."
            }
        }
    }

    private suspend fun <T> socialRpc(
        session: AccountSession.Cloud,
        function: String,
        body: JSONObject,
        maxResponseBytes: Int = MAX_CLOUD_RESPONSE_BYTES,
        parser: (String) -> T
    ): T = withContext(Dispatchers.IO) {
        require(function.matches(Regex("^social_[a-z_]{1,64}$"))) { "Social RPC is invalid." }
        val freshSession = freshCloudSession(session)
        val response = authenticatedRequest(
            session = freshSession,
            path = "/rest/v1/rpc/$function",
            method = "POST",
            body = body.toString(),
            maxResponseBytes = maxResponseBytes
        )
        requireActiveCloudSession(freshSession)
        parser(response)
    }

    private fun beginAuthAttempt(): Long = synchronized(authStateLock) {
        requireNoPendingLocalProfileDeletion()
        authMutationVersion += 1
        authMutationVersion
    }

    private fun beginAuthAttempt(expectedAuthMutationVersion: Long): Long =
        synchronized(authStateLock) {
            check(authMutationVersion == expectedAuthMutationVersion) {
                INACTIVE_CLOUD_SESSION_MESSAGE
            }
            requireNoPendingLocalProfileDeletion()
            authMutationVersion += 1
            authMutationVersion
        }

    private fun authMutationSnapshot(): Long = synchronized(authStateLock) {
        authMutationVersion
    }

    private fun requireCurrentAuthAttempt(expectedAuthMutationVersion: Long) {
        synchronized(authStateLock) {
            check(authMutationVersion == expectedAuthMutationVersion) {
                INACTIVE_CLOUD_SESSION_MESSAGE
            }
        }
    }

    private fun requireActiveCloudSession(
        expected: AccountSession.Cloud
    ): AccountSession.Cloud = synchronized(authStateLock) {
        activeCloudSessionFor(_authState.value.session, expected)
            ?: error(INACTIVE_CLOUD_SESSION_MESSAGE)
    }

    private fun remoteRevisionKey(session: AccountSession.Cloud): RemoteRevisionKey {
        return RemoteRevisionKey(
            userId = session.userId,
            sessionGeneration = session.sessionGeneration
        )
    }

    private fun cacheRemoteStateRevision(
        session: AccountSession.Cloud,
        key: RemoteRevisionKey,
        revision: RemoteStateRevision
    ) {
        synchronized(authStateLock) {
            activeCloudSessionFor(_authState.value.session, session)
                ?: error(INACTIVE_CLOUD_SESSION_MESSAGE)
            remoteStateRevisions[key] = revision
        }
    }

    private fun fetchRemoteStateRow(session: AccountSession.Cloud): RemoteStateRow? {
        val response = authenticatedRequest(
            session = session,
            path = "/rest/v1/user_states?select=state,updated_at" +
                "&user_id=eq.${encodePostgrestQueryValue(session.userId)}&limit=1",
            method = "GET",
            maxResponseBytes = MAX_CLOUD_STATE_RESPONSE_BYTES
        )
        requireActiveCloudSession(session)
        runCatching { requireSafeCloudStateResponse(response) }
            .getOrElse { error("The cloud returned an invalid state response.") }
        val rows = runCatching { JSONArray(response) }
            .getOrElse { error("The cloud returned an invalid state response.") }
        check(rows.length() <= 1) { "The cloud returned an invalid state response." }
        val row = rows.optJSONObject(0) ?: return null
        val state = row.optJSONObject("state")
            ?: error("The cloud returned an invalid state response.")
        val revision = runCatching {
            RemoteStateRevision.Present(row.optString("updated_at"))
        }.getOrElse {
            error("The cloud returned an invalid state revision.")
        }
        return RemoteStateRow(state = state, revision = revision)
    }

    private fun singleRemoteStateRevision(response: String): RemoteStateRevision.Present? {
        runCatching { requireSafeCloudStateResponse(response) }.getOrElse { return null }
        val rows = runCatching { JSONArray(response) }.getOrNull() ?: return null
        if (rows.length() != 1) return null
        val updatedAt = rows.optJSONObject(0)?.optString("updated_at").orEmpty()
        return runCatching { RemoteStateRevision.Present(updatedAt) }.getOrNull()
    }

    private suspend fun refreshSession(session: AccountSession.Cloud): AccountSession.Cloud = withContext(Dispatchers.IO) {
        val refreshToken = session.refreshToken ?: return@withContext session
        val refreshResponse = try {
            request(
                path = "/auth/v1/token?grant_type=refresh_token",
                method = "POST",
                body = JSONObject().put("refresh_token", refreshToken).toString()
            )
        } catch (error: SupabaseHttpException) {
            if (isTerminalRefreshFailure(
                    responseCode = error.responseCode,
                    errorCode = error.errorCode,
                    providerMessage = error.providerMessage
                )
            ) {
                expireCloudSession(session)
                error(INACTIVE_CLOUD_SESSION_MESSAGE)
            }
            throw error
        }
        val json = JSONObject(refreshResponse)
        val accessToken = json.optString("access_token")
        require(isStructurallyValidSupabaseAccessToken(accessToken, session.userId)) {
            "Authentication returned an invalid session. Request a new email."
        }
        val refreshedToken = json.optString("refresh_token")
            .takeIf { it.isNotBlank() }
            ?: session.refreshToken
        require(isStructurallyValidAuthToken(refreshedToken)) {
            "Authentication returned an invalid session. Request a new email."
        }
        val refreshed = session.copy(
            accessToken = accessToken,
            refreshToken = refreshedToken
        )
        synchronized(authStateLock) {
            activeCloudSessionFor(_authState.value.session, session)
                ?: error(INACTIVE_CLOUD_SESSION_MESSAGE)
            persist(refreshed)
            _authState.value = _authState.value.copy(session = refreshed)
        }
        refreshed
    }

    private suspend fun authenticate(
        path: String,
        payload: JSONObject,
        allowEmailConfirmationPending: Boolean = false,
        expectedAuthMutationVersion: Long
    ): AccountSession.Cloud? = withContext(Dispatchers.IO) {
        val json = JSONObject(
            request(
                path = path,
                method = "POST",
                body = payload.toString()
            )
        )
        val accessToken = json.optString("access_token")
        val user = json.optJSONObject("user")
        val userId = user?.optString("id").orEmpty()
        if (accessToken.isBlank() || userId.isBlank()) {
            if (allowEmailConfirmationPending && userId.isNotBlank()) {
                requireCurrentAuthAttempt(expectedAuthMutationVersion)
                return@withContext null
            }
            error("Email confirmation may be required before login.")
        }
        val email = user?.optString("email").orEmpty()
        val displayName = user?.optJSONObject("user_metadata")
            ?.optString("display_name")
            ?.takeIf { it.isNotBlank() }
            ?: payload.optJSONObject("data")?.optString("display_name")?.takeIf { it.isNotBlank() }
            ?: email.substringBefore("@")
            ?: "Cloud"
        val session = AccountSession.Cloud(
            userId = userId,
            email = email,
            displayName = displayName,
            accessToken = accessToken,
            refreshToken = json.optString("refresh_token").takeIf { it.isNotBlank() }
        )
        require(isStructurallyValidCloudSession(session)) {
            "Authentication returned an invalid session. Request a new email."
        }
        synchronized(authStateLock) {
            check(authMutationVersion == expectedAuthMutationVersion) {
                INACTIVE_CLOUD_SESSION_MESSAGE
            }
            requireNoPendingLocalProfileDeletion()
            authMutationVersion += 1
            remoteStateRevisions.clear()
            persist(session)
            prefs.edit().remove(NEEDS_PASSWORD_UPDATE_KEY).apply()
            clearPendingAuthTransaction(PENDING_SIGNUP_KEY)
            clearPendingAuthTransaction(PENDING_RECOVERY_KEY)
            _authState.value = AuthUiState(session = session, isLoading = true)
        }
        session
    }

    private fun cloudSessionFromAuthResponse(json: JSONObject): AccountSession.Cloud {
        val accessToken = json.optString("access_token")
        val user = json.optJSONObject("user")
        val userId = user?.optString("id").orEmpty()
        require(accessToken.isNotBlank() && userId.isNotBlank()) {
            "Authentication returned an invalid session. Request a new email."
        }
        val email = user?.optString("email").orEmpty()
        val displayName = user?.optJSONObject("user_metadata")
            ?.optString("display_name")
            ?.takeIf { it.isNotBlank() }
            ?: email.substringBefore("@").ifBlank { "Cloud" }
        return AccountSession.Cloud(
            userId = userId,
            email = email,
            displayName = displayName,
            accessToken = accessToken,
            refreshToken = json.optString("refresh_token").takeIf { it.isNotBlank() }
        ).also { session ->
            require(isStructurallyValidCloudSession(session)) {
                "Authentication returned an invalid session. Request a new email."
            }
        }
    }

    private fun beginAuthTransaction(
        key: String,
        email: String,
        expectedAuthMutationVersion: Long
    ): PendingAuthTransaction = synchronized(authStateLock) {
        check(authMutationVersion == expectedAuthMutationVersion) {
            INACTIVE_CLOUD_SESSION_MESSAGE
        }
        PendingAuthTransaction(
            state = randomURLSafeString(24),
            codeVerifier = randomURLSafeString(64),
            email = email,
            createdAtMillis = System.currentTimeMillis()
        ).also { transaction ->
            val encoded = JSONObject()
                .put("state", transaction.state)
                .put("codeVerifier", transaction.codeVerifier)
                .put("email", transaction.email)
                .put("createdAtMillis", transaction.createdAtMillis)
                .toString()
            check(secureAuthStore.putString(key, encoded)) {
                "The authentication transaction could not be protected."
            }
            check(prefs.edit().remove(key).commit()) {
                "The legacy authentication transaction could not be removed."
            }
        }
    }

    private fun reusableSignupAuthTransaction(
        email: String,
        expectedAuthMutationVersion: Long
    ): PendingAuthTransactionSelection = synchronized(authStateLock) {
        check(authMutationVersion == expectedAuthMutationVersion) {
            INACTIVE_CLOUD_SESSION_MESSAGE
        }
        reusablePendingSignupTransaction(
            existing = pendingAuthTransaction(PENDING_SIGNUP_KEY),
            email = email
        )?.let { existing ->
            PendingAuthTransactionSelection(existing, wasCreated = false)
        } ?: PendingAuthTransactionSelection(
            transaction = beginAuthTransaction(
                key = PENDING_SIGNUP_KEY,
                email = email,
                expectedAuthMutationVersion = expectedAuthMutationVersion
            ),
            wasCreated = true
        )
    }

    private fun isDeterministicAuthInitiationFailure(error: Throwable): Boolean {
        return isDeterministicAuthInitiationHttpFailure(
            (error as? SupabaseHttpException)?.responseCode
        )
    }

    private fun pendingAuthTransaction(key: String): PendingAuthTransaction? {
        return runCatching {
            val protected = secureAuthStore.getString(key)
            val legacy = prefs.getString(key, null)
            val raw = protected ?: legacy
            val json = JSONObject(raw.orEmpty())
            PendingAuthTransaction(
                state = json.getString("state"),
                codeVerifier = json.getString("codeVerifier"),
                email = normalizeEmail(json.getString("email")),
                createdAtMillis = json.getLong("createdAtMillis")
            ).takeIf { transaction ->
                transaction.state.matches(Regex("^[A-Za-z0-9_-]{32}$")) &&
                    transaction.codeVerifier.matches(Regex("^[A-Za-z0-9_-]{43,128}$")) &&
                    transaction.email.length <= 254
            }?.also {
                if (protected == null) {
                    check(secureAuthStore.putString(key, checkNotNull(legacy)))
                    check(prefs.edit().remove(key).commit())
                }
            }
        }.getOrNull()
    }

    private fun clearPendingAuthTransaction(key: String, expectedState: String? = null) {
        synchronized(authStateLock) {
            if (expectedState == null || pendingAuthTransaction(key)?.state == expectedState) {
                secureAuthStore.remove(key)
                prefs.edit().remove(key).commit()
            }
        }
    }

    private fun randomURLSafeString(byteCount: Int): String {
        val bytes = ByteArray(byteCount)
        SecureRandom().nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    private fun codeChallenge(verifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.UTF_8))
        return Base64.getUrlEncoder().withoutPadding().encodeToString(digest)
    }

    private fun persist(session: AccountSession.Cloud) {
        check(
            !shouldSuppressRestoredCloudSession(
                accountDeletionJournal.snapshot(),
                session.userId
            )
        ) {
            "Local deletion cleanup is still pending for this account. Restart GymApp and try again."
        }
        val encoded = JSONObject()
            .put("userId", session.userId)
            .put("email", session.email)
            .put("displayName", session.displayName)
            .put("accessToken", session.accessToken)
            .put("refreshToken", session.refreshToken)
            .put("sessionGeneration", session.sessionGeneration)
            .toString()
        check(secureAuthStore.putString("cloud", encoded)) {
            "Cloud credentials could not be protected."
        }
        check(prefs.edit().putString("mode", "cloud").remove("cloud").commit()) {
            secureAuthStore.remove("cloud")
            "Cloud authentication state could not be committed."
        }
    }

    private fun readSession(): StoredSessionRead {
        val pendingDeletion = localProfileDeletionJournal.snapshot()
        if (pendingDeletion.unreadable || pendingDeletion.record != null) {
            clearAllAuthStorageSynchronously()
            return StoredSessionRead(
                recoveryMessage = LocalizedText(R.string.local_profile_delete_cleanup_pending)
            )
        }
        return when (prefs.all["mode"] as? String) {
            "local" -> {
                val storedName = prefs.all["local_name"] as? String
                val validatedName = storedName?.let(::validatedLocalDisplayNameOrNull)
                if (validatedName == null) {
                    StoredSessionRead(
                        recoveryMessage = LocalizedText(R.string.auth_error_saved_local_invalid)
                    )
                } else {
                    val session = AccountSession.Local(validatedName)
                    val storedProfileId = prefs.all["local_profile_id"] as? String
                    val storedProfile = storedProfileId?.let(localProfileRegistry::findById)
                    val profileBindingIsValid = storedProfileId == null ||
                        storedProfile?.displayName?.let(::normalizedLocalDisplayNameOrNull) ==
                        normalizedLocalDisplayNameOrNull(validatedName)
                    val mayResumePendingCreation = storedProfileId != null && storedProfile != null
                    val bindingRestored =
                        profileBindingIsValid && localDatabaseBindingStore.restoreStoredSession(
                            session,
                            allowPendingLogicalCreation = mayResumePendingCreation
                        )
                    val pendingCreation = bindingRestored &&
                        localDatabaseBindingStore.requiresActivationFinalization(session)
                    val pendingPhysicalDatabaseName = if (pendingCreation) {
                        runCatching {
                            localDatabaseBindingStore.physicalDatabaseName(session)
                        }.getOrNull()
                    } else {
                        null
                    }
                    val pendingActivated = !pendingCreation ||
                        pendingPhysicalDatabaseName != null && runCatching {
                            localDatabaseMaterializer(pendingPhysicalDatabaseName)
                        }.getOrDefault(false) &&
                        localDatabaseBindingStore.finalizeMaterializedSession(session)
                    if (bindingRestored && pendingActivated) {
                        if (storedProfileId == null) {
                            localProfileRegistry.ensurePresent(validatedName)
                        }
                        StoredSessionRead(session = session)
                    } else {
                        if (pendingCreation && storedProfileId != null) {
                            val databaseRolledBack = pendingPhysicalDatabaseName != null &&
                                localDatabaseRollback(pendingPhysicalDatabaseName)
                            if (databaseRolledBack && clearAllAuthStorageSynchronously()) {
                                // Only remove the durable identity after its auth pointer and
                                // any partially created DB files are gone. A failed cleanup is
                                // left journaled for a future retry, but never published.
                                val registryRolledBack = localProfileRegistry.remove(storedProfileId)
                                val bindingRolledBack = registryRolledBack &&
                                    localDatabaseBindingStore.rollbackPendingNewSession(session)
                                if (!bindingRolledBack) {
                                    if (registryRolledBack) {
                                        localProfileRegistry.ensurePresent(
                                            validatedName,
                                            storedProfileId
                                        )
                                    }
                                    // Fail closed without crashing the launch loop. The remaining
                                    // durable marker prevents reassignment or silent overwrite.
                                    return StoredSessionRead(
                                        recoveryMessage = LocalizedText(
                                            R.string.auth_error_local_database_unavailable
                                        )
                                    )
                                }
                            }
                        }
                        StoredSessionRead(
                            recoveryMessage = LocalizedText(
                                R.string.auth_error_local_database_unavailable
                            )
                        )
                    }
                }
            }
            "cloud" -> run {
                val protected = secureAuthStore.getString("cloud")
                val legacy = prefs.getString("cloud", null)
                val raw = protected ?: legacy
                parseStoredCloudSession(raw)?.also {
                    if (protected == null) {
                        check(secureAuthStore.putString("cloud", checkNotNull(legacy)))
                        check(prefs.edit().remove("cloud").commit())
                    }
                }
            }
                ?.let { session ->
                    if (shouldSuppressRestoredCloudSession(
                            accountDeletionJournal.snapshot(),
                            session.userId
                        )
                    ) {
                        // A deletion request with an unknown or successful outcome must never
                        // restore that owner's local session while durable cleanup is retried.
                        if (!clearAllAuthStorageSynchronously()) {
                            prefs.edit().clear().apply()
                        }
                        StoredSessionRead(
                            recoveryMessage = LocalizedText(
                                R.string.account_delete_outcome_unknown
                            )
                        )
                    } else {
                        StoredSessionRead(session = session)
                    }
                } ?: run {
                    prefs.edit()
                        .remove("mode")
                        .remove("cloud")
                        .remove(NEEDS_PASSWORD_UPDATE_KEY)
                        .commit()
                    StoredSessionRead(
                        recoveryMessage = LocalizedText(R.string.auth_error_saved_cloud_invalid)
                    )
                }
            else -> StoredSessionRead()
        }
    }

    private fun clearAllAuthStorageSynchronously(): Boolean {
        val protectedCleared = secureAuthStore.clear()
        val legacyCleared = clearAuthPreferencesSynchronously(prefs)
        return protectedCleared && legacyCleared
    }

    private fun isStructurallyValidCloudSession(session: AccountSession.Cloud): Boolean =
        isCanonicalUuid(session.userId) &&
            isStructurallyValidEmail(session.email.trim().lowercase()) &&
            session.displayName.isNotBlank() &&
            session.displayName.codePointCount(0, session.displayName.length) <= 128 &&
            session.displayName.toByteArray(Charsets.UTF_8).size <= 512 &&
            session.displayName.none(Char::isISOControl) &&
            isStructurallyValidSupabaseAccessToken(session.accessToken, session.userId) &&
            (session.refreshToken == null || isStructurallyValidAuthToken(session.refreshToken))

    private fun expireCloudSession(expectedSession: AccountSession.Cloud) {
        synchronized(authStateLock) {
            if (activeCloudSessionFor(_authState.value.session, expectedSession) == null) return
            authMutationVersion += 1
            remoteStateRevisions.clear()
            if (!clearAllAuthStorageSynchronously()) {
                prefs.edit().clear().apply()
            }
            _authState.value = AuthUiState(
                message = LocalizedText(R.string.auth_error_session_inactive),
                messageIsError = true
            )
        }
    }

    private fun authenticatedRequest(
        session: AccountSession.Cloud,
        path: String,
        method: String,
        prefer: String? = null,
        body: String? = null,
        additionalHeaders: Map<String, String> = emptyMap(),
        maxResponseBytes: Int = MAX_CLOUD_RESPONSE_BYTES
    ): String {
        requireActiveCloudSession(session)
        return try {
            request(
                path = path,
                method = method,
                token = session.accessToken,
                prefer = prefer,
                body = body,
                additionalHeaders = additionalHeaders,
                maxResponseBytes = maxResponseBytes
            )
        } catch (error: SupabaseHttpException) {
            if (error.responseCode == 401) {
                expireCloudSession(session)
                error(INACTIVE_CLOUD_SESSION_MESSAGE)
            }
            throw error
        }
    }

    private fun request(
        path: String,
        method: String,
        token: String? = null,
        prefer: String? = null,
        body: String? = null,
        additionalHeaders: Map<String, String> = emptyMap(),
        maxResponseBytes: Int = MAX_CLOUD_RESPONSE_BYTES
    ): String {
        require(maxResponseBytes in 1..MAX_CLOUD_STATE_RESPONSE_BYTES) {
            "Cloud response limit is invalid."
        }
        val bodyBytes = body?.toByteArray(Charsets.UTF_8)
        check(bodyBytes == null || bodyBytes.size <= MAX_CLOUD_REQUEST_BYTES) {
            "Cloud request exceeded the safe size limit."
        }
        val connection = (URL("$SUPABASE_URL$path").openConnection() as HttpURLConnection).apply {
            requestMethod = method
            instanceFollowRedirects = false
            connectTimeout = 15_000
            readTimeout = 20_000
            setRequestProperty("apikey", SUPABASE_KEY)
            setRequestProperty("Content-Type", "application/json")
            token?.let { setRequestProperty("Authorization", "Bearer $it") }
            prefer?.let { setRequestProperty("Prefer", it) }
            additionalHeaders.forEach { (name, value) ->
                require(name.matches(Regex("^[A-Za-z0-9-]{1,64}$"))) {
                    "Cloud request header name is invalid."
                }
                require(value.length <= 1_024 && value.none(Char::isISOControl)) {
                    "Cloud request header value is invalid."
                }
                setRequestProperty(name, value)
            }
            if (bodyBytes != null) {
                doOutput = true
            }
        }
        return try {
            if (bodyBytes != null) {
                connection.outputStream.use { it.write(bodyBytes) }
            }
            val responseCode = connection.responseCode
            val isSuccess = responseCode in 200..299
            val responseLimit = if (isSuccess) {
                maxResponseBytes
            } else {
                MAX_CLOUD_ERROR_RESPONSE_BYTES
            }
            val declaredLength = connection.contentLengthLong
            check(declaredLength < 0L || declaredLength <= responseLimit.toLong()) {
                "Cloud response exceeded the safe size limit."
            }
            val stream = if (isSuccess) connection.inputStream else connection.errorStream
            val text = stream?.use { input ->
                readUtf8ResponseBody(input, maxBytes = responseLimit)
            }.orEmpty()
            if (!isSuccess) {
                val fields = parseSupabaseError(text)
                throw SupabaseHttpException(
                    responseCode = responseCode,
                    errorCode = fields.code,
                    providerMessage = fields.message,
                    safeMessage = friendlySupabaseError(responseCode, text)
                )
            }
            text.ifBlank { "[]" }
        } finally {
            connection.disconnect()
        }
    }

    private fun friendlySupabaseError(responseCode: Int, text: String): String {
        val fields = parseSupabaseError(text)
        val code = fields.code
        val message = fields.message

        return when {
            responseCode == 429 || code == "over_email_send_rate_limit" || message?.contains("rate limit", ignoreCase = true) == true ->
                "Too many authentication emails were requested. Try again later, or contact support if the newest email never arrives."

            code == "user_already_exists" || message?.contains("already registered", ignoreCase = true) == true ->
                "An account with this email already exists. Log in instead."

            responseCode == 400 && message?.contains("invalid login", ignoreCase = true) == true ->
                "Email or password is incorrect."

            message?.contains("invalid login credentials", ignoreCase = true) == true ->
                "Email or password is incorrect."

            message?.contains("email not confirmed", ignoreCase = true) == true ->
                "Confirm your email first, then log in."

            responseCode == 401 ->
                "Cloud request failed. Check your connection and try again."

            responseCode in 500..599 ->
                "Cloud login is temporarily unavailable. Try again later."

            !message.isNullOrBlank() ->
                message

            else ->
                "Cloud request failed. Check your connection and try again."
        }
    }

    private fun parseSupabaseError(text: String): SupabaseErrorFields {
        val parsed = runCatching { JSONObject(text) }.getOrNull()
        val nested = parsed?.optJSONObject("error")
        return SupabaseErrorFields(
            code = nested?.optString("code")
                ?.takeIf { it.isNotBlank() }
                ?: parsed?.optString("error_code")
                ?.takeIf { it.isNotBlank() }
                ?: parsed?.optString("code")?.takeIf { it.isNotBlank() }
                ?: (parsed?.opt("error") as? String)?.takeIf {
                    it.matches(Regex("^[a-z][a-z0-9_]{0,63}$"))
                },
            message = nested?.optString("message")
                ?.takeIf { it.isNotBlank() }
                ?: parsed?.optString("msg")
                ?.takeIf { it.isNotBlank() }
                ?: parsed?.optString("message")?.takeIf { it.isNotBlank() }
                ?: parsed?.optString("error_description")?.takeIf { it.isNotBlank() }
                ?: parsed?.optString("error")?.takeIf { it.isNotBlank() }
        )
    }

    private fun validateEmail(email: String) {
        val cleanEmail = normalizeEmail(email)
        require(Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$").matches(cleanEmail) && cleanEmail.length <= 254) {
            "Enter a valid email address."
        }
    }

    private fun validateNewPassword(password: String) {
        require(isValidNewPassword(password)) { NEW_PASSWORD_POLICY_ERROR }
    }

    private fun normalizeEmail(email: String): String {
        return email.trim().lowercase()
    }

    private fun sanitizeDisplayName(value: String): String {
        return value
            .filter { it.isLetterOrDigit() || it == ' ' || it == '.' || it == '-' || it == '_' }
            .replace(Regex("\\s+"), " ")
            .trim()
            .take(32)
    }

    private fun AccountSession.Cloud.needsRefresh(nowSeconds: Long = System.currentTimeMillis() / 1_000L): Boolean {
        val expiresAt = accessTokenExpirationSeconds() ?: return false
        return expiresAt - nowSeconds <= 60
    }

    private fun AccountSession.Cloud.accessTokenExpirationSeconds(): Long? {
        return runCatching {
            val payload = accessToken.split(".").getOrNull(1) ?: return@runCatching null
            val decoded = Base64.getUrlDecoder().decode(payload)
            JSONObject(String(decoded, Charsets.UTF_8)).optLong("exp").takeIf { it > 0L }
        }.getOrNull()
    }
}
