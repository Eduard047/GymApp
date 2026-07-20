package com.example.gymapp.auth

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import com.example.gymapp.BuildConfig
import com.example.gymapp.R
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.util.LocalizedText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
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
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.OffsetDateTime
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

private const val SUPABASE_URL = "https://owrcbsrectdgaotndtxy.supabase.co"
private const val SUPABASE_KEY = "sb_publishable_vvOMzx6V_sPBpD-b3VZfzg_y14u8kIg"
private val AUTH_REDIRECT_URL =
    "https://gymapptracker.com/confirmed.html?platform=android${BuildConfig.AUTH_BRIDGE_VARIANT_QUERY}"
private const val WEB_AUTH_REDIRECT_URL = "https://gymapptracker.com/confirmed.html?platform=web"
private const val NEEDS_PASSWORD_UPDATE_KEY = "needs_password_update"
private const val PENDING_SIGNUP_KEY = "pending_signup_confirmation"
private const val PENDING_RECOVERY_KEY = "pending_password_recovery"
private const val AUTH_TRANSACTION_MAX_AGE_MILLIS = 24 * 60 * 60 * 1_000L
private const val MAX_CLOUD_RESPONSE_BYTES = 256 * 1_024
private const val MAX_CLOUD_STATE_RESPONSE_BYTES = 10 * 1_024 * 1_024
private const val MAX_CLOUD_REQUEST_BYTES = 10 * 1_024 * 1_024
private const val MAX_CLOUD_ERROR_RESPONSE_BYTES = 64 * 1_024
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

private data class PendingAuthTransaction(
    val state: String,
    val codeVerifier: String,
    val email: String,
    val createdAtMillis: Long
) {
    fun isFresh(nowMillis: Long = System.currentTimeMillis()): Boolean {
        return createdAtMillis in (nowMillis - AUTH_TRANSACTION_MAX_AGE_MILLIS)..nowMillis
    }
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
    descriptions: List<String>
): Boolean {
    val allowedKeys = setOf("state", "purpose", "code", "error", "error_description")
    val hasCode = codes.size == 1 && isValidPKCEAuthCode(codes.single())
    val hasError = errors.size == 1 && isSafeCallbackValue(errors.single(), 128)
    val hasDescription = descriptions.isEmpty() ||
        (descriptions.size == 1 && isSafeCallbackValue(descriptions.single(), 1_024))
    return !hasFragment &&
        queryKeys.all { it in allowedKeys && !it.contains("token", ignoreCase = true) } &&
        receivedStates.size == 1 &&
        receivedStates.single().matches(Regex("^[A-Za-z0-9_-]{32}$")) &&
        purposes.size == 1 && purposes.single() in setOf("signup", "recovery") &&
        hasCode != hasError &&
        hasDescription &&
        (descriptions.isEmpty() || hasError)
}

data class LeaderboardRow(
    val profileId: String? = null,
    val displayName: String,
    val xp: Int,
    val level: Int,
    val workouts: Int,
    val isCurrentUser: Boolean = false
)

data class CloudProfile(
    val userId: String,
    val displayName: String,
    val xp: Int,
    val level: Int,
    val workouts: Int
)

internal fun activeCloudSessionFor(
    current: AccountSession?,
    expected: AccountSession.Cloud
): AccountSession.Cloud? {
    return (current as? AccountSession.Cloud)?.takeIf {
        it.userId == expected.userId &&
            it.sessionGeneration == expected.sessionGeneration
    }
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

internal fun clearAuthPreferencesSynchronously(preferences: SharedPreferences): Boolean =
    preferences.edit().clear().commit()

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

class CloudAuthManager(context: Context) {
    private data class StoredSessionRead(
        val session: AccountSession? = null,
        val recoveryMessage: LocalizedText? = null
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
    private val localDatabaseBindingStore = LocalDatabaseBindingStore(context.applicationContext)
    private val authStateLock = Any()
    private val refreshMutex = Mutex()
    private val remoteStateMutex = Mutex()
    private val logoutRevokeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
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
        validateAuthInput(email = cleanEmail, password = password)
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
        validateAuthInput(email = cleanEmail, password = password, displayName = cleanName)
        val authAttempt = beginAuthAttempt()
        val transaction = beginAuthTransaction(
            key = PENDING_SIGNUP_KEY,
            email = cleanEmail,
            expectedAuthMutationVersion = authAttempt
        )
        val redirectURL = "$AUTH_REDIRECT_URL&state=${transaction.state}&purpose=signup"
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
            clearPendingAuthTransaction(PENDING_SIGNUP_KEY, transaction.state)
            throw error
        }
    }

    suspend fun resendSignUpConfirmation(email: String) = withContext(Dispatchers.IO) {
        val cleanEmail = normalizeEmail(email)
        validateEmail(cleanEmail)
        // Supabase resend does not reliably recreate the original PKCE transaction.
        // Invalidate its verifier and finish resend confirmations on HTTPS instead;
        // the user then returns to Android and signs in with the confirmed password.
        clearPendingAuthTransaction(PENDING_SIGNUP_KEY)
        request(
            path = "/auth/v1/resend?redirect_to=${java.net.URLEncoder.encode(WEB_AUTH_REDIRECT_URL, "UTF-8")}",
            method = "POST",
            body = JSONObject()
                .put("type", "signup")
                .put("email", cleanEmail)
                .toString()
        )
    }

    suspend fun requestPasswordReset(email: String) = withContext(Dispatchers.IO) {
        val cleanEmail = normalizeEmail(email)
        validateEmail(cleanEmail)
        val transaction = beginAuthTransaction(
            key = PENDING_RECOVERY_KEY,
            email = cleanEmail,
            expectedAuthMutationVersion = authMutationSnapshot()
        )
        val redirectURL = "$AUTH_REDIRECT_URL&state=${transaction.state}&purpose=recovery"
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
            clearPendingAuthTransaction(PENDING_RECOVERY_KEY, transaction.state)
            throw error
        }
    }

    fun setLocal(displayName: String) {
        val candidate = displayName.trim().ifBlank { "Local" }
        val validatedName = normalizedLocalDisplayNameOrNull(candidate)
            ?: throw IllegalArgumentException("Local account name is invalid or too long.")
        val session = AccountSession.Local(validatedName)
        synchronized(authStateLock) {
            check(localDatabaseBindingStore.registerNewSession(session)) {
                "The local workout database could not be safely registered."
            }
            check(
                prefs.edit()
                    .putString("mode", "local")
                    .putString("local_name", session.displayName)
                    .remove("cloud")
                    .remove(NEEDS_PASSWORD_UPDATE_KEY)
                    .remove(PENDING_SIGNUP_KEY)
                    .remove(PENDING_RECOVERY_KEY)
                    .commit()
            ) { "The local account could not be persisted." }
            authMutationVersion += 1
            remoteStateRevisions.clear()
            _authState.value = AuthUiState(session = session)
        }
    }

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

    fun logout() {
        val revokeRequest = synchronized(authStateLock) {
            val capturedRequest = localCloudLogoutRequest(_authState.value.session)
            authMutationVersion += 1
            remoteStateRevisions.clear()
            if (!clearAuthPreferencesSynchronously(prefs)) {
                _authState.value = _authState.value.copy(
                    isLoading = false,
                    message = LocalizedText(R.string.auth_message_logout_failed),
                    messageIsError = true
                )
                return@synchronized null
            }
            _authState.value = AuthUiState()
            capturedRequest
        }
        if (revokeRequest != null) {
            logoutRevokeScope.launch {
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
        require(
            isStructurallySafePKCECallback(
                queryKeys = uri.queryParameterNames,
                hasFragment = !uri.fragment.isNullOrEmpty(),
                receivedStates = stateValues,
                purposes = purposeValues,
                codes = codeValues,
                errors = errorValues,
                descriptions = descriptionValues
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
        request(
            path = "/auth/v1/user",
            method = "PUT",
            token = freshSession.accessToken,
            body = JSONObject().put("password", password).toString()
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

    suspend fun freshCloudSession(session: AccountSession.Cloud): AccountSession.Cloud {
        val currentSession = requireActiveCloudSession(session)
        if (!currentSession.needsRefresh()) return currentSession
        if (currentSession.refreshToken.isNullOrBlank()) return currentSession

        return refreshMutex.withLock {
            val latestSession = requireActiveCloudSession(session)
            if (!latestSession.needsRefresh() || latestSession.refreshToken.isNullOrBlank()) {
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

    suspend fun saveRemoteState(
        session: AccountSession.Cloud,
        state: JSONObject,
        xp: Int,
        level: Int,
        workouts: Int
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
            val revisionResponse = request(
                path = writeRequest.path,
                method = writeRequest.method,
                token = freshSession.accessToken,
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
            request(
                path = "/rest/v1/profiles?on_conflict=user_id",
                method = "POST",
                token = freshSession.accessToken,
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
        }
    }

    suspend fun loadOwnProfile(session: AccountSession.Cloud): CloudProfile? = withContext(Dispatchers.IO) {
        val freshSession = freshCloudSession(session)
        val response = request(
            path = "/rest/v1/profiles?select=user_id,display_name,xp,level,workouts" +
                "&user_id=eq.${encodePostgrestQueryValue(freshSession.userId)}&limit=1",
            method = "GET",
            token = freshSession.accessToken
        )
        requireActiveCloudSession(freshSession)
        val row = JSONArray(response).optJSONObject(0) ?: return@withContext null
        CloudProfile(
            userId = row.optString("user_id"),
            displayName = row.optString("display_name").ifBlank { session.displayName },
            xp = row.optInt("xp"),
            level = row.optInt("level", 1),
            workouts = row.optInt("workouts")
        )
    }

    suspend fun loadLeaderboard(session: AccountSession.Cloud, limit: Int = 50): List<LeaderboardRow> =
        withContext(Dispatchers.IO) {
            val freshSession = freshCloudSession(session)
            val safeLimit = limit.coerceIn(1, 100)
            val response = request(
                path = "/rest/v1/leaderboard_public?select=profile_id,display_name,xp,level,workouts,is_current_user&order=xp.desc,workouts.desc,profile_id.asc&limit=$safeLimit",
                method = "GET",
                token = freshSession.accessToken
            )
            requireActiveCloudSession(freshSession)
            val rows = JSONArray(response)
            List(rows.length()) { index ->
                val row = rows.optJSONObject(index) ?: JSONObject()
                LeaderboardRow(
                    profileId = row.optString("profile_id").takeIf { it.isNotBlank() },
                    displayName = row.optString("display_name"),
                    xp = row.optInt("xp"),
                    level = row.optInt("level", 1),
                    workouts = row.optInt("workouts"),
                    isCurrentUser = row.optBoolean("is_current_user")
                )
            }
        }

    private fun beginAuthAttempt(): Long = synchronized(authStateLock) {
        authMutationVersion += 1
        authMutationVersion
    }

    private fun beginAuthAttempt(expectedAuthMutationVersion: Long): Long =
        synchronized(authStateLock) {
            check(authMutationVersion == expectedAuthMutationVersion) {
                INACTIVE_CLOUD_SESSION_MESSAGE
            }
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
        val response = request(
            path = "/rest/v1/user_states?select=state,updated_at" +
                "&user_id=eq.${encodePostgrestQueryValue(session.userId)}&limit=1",
            method = "GET",
            token = session.accessToken,
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
        val json = JSONObject(
            request(
                path = "/auth/v1/token?grant_type=refresh_token",
                method = "POST",
                body = JSONObject().put("refresh_token", refreshToken).toString()
            )
        )
        val accessToken = json.optString("access_token")
        if (accessToken.isBlank()) {
            requireActiveCloudSession(session)
            return@withContext session
        }
        val refreshed = session.copy(
            accessToken = accessToken,
            refreshToken = json.optString("refresh_token").takeIf { it.isNotBlank() } ?: session.refreshToken
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
        synchronized(authStateLock) {
            check(authMutationVersion == expectedAuthMutationVersion) {
                INACTIVE_CLOUD_SESSION_MESSAGE
            }
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
        )
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
            prefs.edit()
                .putString(
                    key,
                    JSONObject()
                        .put("state", transaction.state)
                        .put("codeVerifier", transaction.codeVerifier)
                        .put("email", transaction.email)
                        .put("createdAtMillis", transaction.createdAtMillis)
                        .toString()
                )
                .apply()
        }
    }

    private fun pendingAuthTransaction(key: String): PendingAuthTransaction? {
        return runCatching {
            val json = JSONObject(prefs.getString(key, null).orEmpty())
            PendingAuthTransaction(
                state = json.getString("state"),
                codeVerifier = json.getString("codeVerifier"),
                email = normalizeEmail(json.getString("email")),
                createdAtMillis = json.getLong("createdAtMillis")
            ).takeIf { transaction ->
                transaction.state.matches(Regex("^[A-Za-z0-9_-]{32}$")) &&
                    transaction.codeVerifier.matches(Regex("^[A-Za-z0-9_-]{43,128}$")) &&
                    transaction.email.length <= 254
            }
        }.getOrNull()
    }

    private fun clearPendingAuthTransaction(key: String, expectedState: String? = null) {
        synchronized(authStateLock) {
            if (expectedState == null || pendingAuthTransaction(key)?.state == expectedState) {
                prefs.edit().remove(key).apply()
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
        prefs.edit()
            .putString("mode", "cloud")
            .putString(
                "cloud",
                JSONObject()
                    .put("userId", session.userId)
                    .put("email", session.email)
                    .put("displayName", session.displayName)
                    .put("accessToken", session.accessToken)
                    .put("refreshToken", session.refreshToken)
                    .put("sessionGeneration", session.sessionGeneration)
                    .toString()
            )
            .apply()
    }

    private fun readSession(): StoredSessionRead {
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
                    if (localDatabaseBindingStore.restoreStoredSession(session)) {
                        StoredSessionRead(session = session)
                    } else {
                        StoredSessionRead(
                            recoveryMessage = LocalizedText(
                                R.string.auth_error_local_database_unavailable
                            )
                        )
                    }
                }
            }
            "cloud" -> runCatching {
                val json = JSONObject(prefs.getString("cloud", null).orEmpty())
                StoredSessionRead(
                    session = AccountSession.Cloud(
                        userId = json.optString("userId"),
                        email = json.optString("email"),
                        displayName = json.optString("displayName"),
                        accessToken = json.optString("accessToken"),
                        refreshToken = json.optString("refreshToken").takeIf { it.isNotBlank() },
                        sessionGeneration = json.optString("sessionGeneration")
                            .takeIf { it.length in 16..128 }
                            ?: newCloudSessionGeneration()
                    )
                )
            }.getOrElse {
                StoredSessionRead(
                    recoveryMessage = LocalizedText(R.string.auth_error_saved_cloud_invalid)
                )
            }
            else -> StoredSessionRead()
        }
    }

    private fun request(
        path: String,
        method: String,
        token: String? = null,
        prefer: String? = null,
        body: String? = null,
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
                error(friendlySupabaseError(responseCode, text))
            }
            text.ifBlank { "[]" }
        } finally {
            connection.disconnect()
        }
    }

    private fun friendlySupabaseError(responseCode: Int, text: String): String {
        val parsed = runCatching { JSONObject(text) }.getOrNull()
        val code = parsed?.optString("error_code")
            ?.takeIf { it.isNotBlank() }
            ?: parsed?.optString("code")?.takeIf { it.isNotBlank() }
        val message = parsed?.optString("msg")
            ?.takeIf { it.isNotBlank() }
            ?: parsed?.optString("message")?.takeIf { it.isNotBlank() }
            ?: parsed?.optString("error_description")?.takeIf { it.isNotBlank() }
            ?: parsed?.optString("error")?.takeIf { it.isNotBlank() }

        return when {
            responseCode == 429 || code == "over_email_send_rate_limit" || message?.contains("rate limit", ignoreCase = true) == true ->
                "Too many authentication emails were requested. Try again later, or contact support if the newest email never arrives."

            code == "user_already_exists" || message?.contains("already registered", ignoreCase = true) == true ->
                "An account with this email already exists. Log in instead."

            responseCode == 400 && message?.contains("invalid login", ignoreCase = true) == true ->
                "Email or password is incorrect."

            responseCode == 401 || message?.contains("invalid login credentials", ignoreCase = true) == true ->
                "Email or password is incorrect."

            message?.contains("email not confirmed", ignoreCase = true) == true ->
                "Confirm your email first, then log in."

            responseCode in 500..599 ->
                "Cloud login is temporarily unavailable. Try again later."

            !message.isNullOrBlank() ->
                message

            else ->
                "Cloud request failed. Check your connection and try again."
        }
    }

    private fun validateAuthInput(email: String, password: String, displayName: String = "") {
        validateEmail(email)
        require(password.length in 8..72 && password.any { it.isLetter() } && password.any { it.isDigit() }) {
            "Password must be 8-72 characters and include letters and numbers."
        }
        if (displayName.isNotBlank()) {
            require(displayName.length in 2..32 && displayName.all { it.isLetterOrDigit() || it == ' ' || it == '.' || it == '-' || it == '_' }) {
                "Display name can use letters, numbers, spaces, dot, dash and underscore."
            }
        }
    }

    private fun validateEmail(email: String) {
        val cleanEmail = normalizeEmail(email)
        require(Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$").matches(cleanEmail) && cleanEmail.length <= 254) {
            "Enter a valid email address."
        }
    }

    private fun validateNewPassword(password: String) {
        require(password.length in 8..72 && password.any { it.isLetter() } && password.any { it.isDigit() }) {
            "Password must be 8-72 characters and include letters and numbers."
        }
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
