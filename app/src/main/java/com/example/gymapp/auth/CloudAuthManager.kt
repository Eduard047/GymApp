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
private const val NEEDS_PASSWORD_UPDATE_KEY = "needs_password_update"
private const val PENDING_SIGNUP_KEY = "pending_signup_confirmation"
private const val PENDING_RECOVERY_KEY = "pending_password_recovery"
private const val AUTH_TRANSACTION_MAX_AGE_MILLIS = 24 * 60 * 60 * 1_000L
private const val MAX_CLOUD_RESPONSE_BYTES = 256 * 1_024
private const val MAX_CLOUD_STATE_RESPONSE_BYTES = 10 * 1_024 * 1_024
private const val MAX_CLOUD_REQUEST_BYTES = 10 * 1_024 * 1_024
private const val MAX_CLOUD_ERROR_RESPONSE_BYTES = 64 * 1_024
private const val MAX_STORED_SESSION_BYTES = 64 * 1_024
private const val MAX_AUTH_TOKEN_CHARS = 16 * 1_024
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

internal fun cloudAccountDeletionRequest(): CloudAccountDeletionRequest =
    CloudAccountDeletionRequest(
        path = "/functions/v1/delete-account",
        method = "POST",
        headers = mapOf("X-GymApp-Delete" to "confirmed"),
        body = JSONObject().put("confirmation", "DELETE").toString()
    )

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

class CloudAuthManager(context: Context) {
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
    private val localDatabaseBindingStore = LocalDatabaseBindingStore(context.applicationContext)
    private val accountDeletionJournal = CloudAccountDeletionJournal(context.applicationContext)
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
        validateEmail(cleanEmail)
        require(password.isNotEmpty()) { "Enter your password." }
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
        val redirectURL = "$AUTH_REDIRECT_URL&state=${transaction.state}&purpose=signup"
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
            if (isDeterministicAuthInitiationFailure(error)) {
                clearPendingAuthTransaction(PENDING_RECOVERY_KEY, transaction.state)
            }
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
        val revokeRequest = synchronized(authStateLock) {
            val capturedRequest = localCloudLogoutRequest(_authState.value.session)
            authMutationVersion += 1
            remoteStateRevisions.clear()
            val preferencesCleared = clearAuthPreferencesSynchronously(prefs)
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
        expectedSession: AccountSession.Cloud
    ): AccountSession.Cloud = withContext(Dispatchers.IO) {
        val session = synchronized(authStateLock) {
            activeCloudSessionFor(_authState.value.session, expectedSession)
        } ?: error(INACTIVE_CLOUD_SESSION_MESSAGE)
        val freshSession = freshCloudSession(session)
        val requestSession = requireActiveCloudSession(freshSession)
        val deletionRequest = cloudAccountDeletionRequest()
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
        if (!clearAuthPreferencesSynchronously(prefs)) {
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
            val preferencesCleared = clearAuthPreferencesSynchronously(prefs)
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
            durableAuthCleanupCompleted = clearAuthPreferencesSynchronously(prefs)
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
        }
    }

    suspend fun loadOwnProfile(session: AccountSession.Cloud): CloudProfile? = withContext(Dispatchers.IO) {
        val freshSession = freshCloudSession(session)
        val response = authenticatedRequest(
            session = freshSession,
            path = "/rest/v1/profiles?select=user_id,display_name,xp,level,workouts" +
                "&user_id=eq.${encodePostgrestQueryValue(freshSession.userId)}&limit=1",
            method = "GET"
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
            val response = authenticatedRequest(
                session = freshSession,
                path = "/rest/v1/leaderboard_public?select=profile_id,display_name,xp,level,workouts,is_current_user&order=xp.desc,workouts.desc,profile_id.asc&limit=$safeLimit",
                method = "GET"
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
            }.filter(LeaderboardRow::isCurrentUser)
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
        check(
            !shouldSuppressRestoredCloudSession(
                accountDeletionJournal.snapshot(),
                session.userId
            )
        ) {
            "Local deletion cleanup is still pending for this account. Restart GymApp and try again."
        }
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
            "cloud" -> parseStoredCloudSession(prefs.getString("cloud", null))
                ?.let { session ->
                    if (shouldSuppressRestoredCloudSession(
                            accountDeletionJournal.snapshot(),
                            session.userId
                        )
                    ) {
                        // A deletion request with an unknown or successful outcome must never
                        // restore that owner's local session while durable cleanup is retried.
                        if (!clearAuthPreferencesSynchronously(prefs)) {
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
            if (!clearAuthPreferencesSynchronously(prefs)) {
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
        return SupabaseErrorFields(
            code = parsed?.optString("error_code")
                ?.takeIf { it.isNotBlank() }
                ?: parsed?.optString("code")?.takeIf { it.isNotBlank() },
            message = parsed?.optString("msg")
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
