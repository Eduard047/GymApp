package com.example.gymapp.auth

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

private const val SUPABASE_URL = "https://owrcbsrectdgaotndtxy.supabase.co"
private const val SUPABASE_KEY = "sb_publishable_vvOMzx6V_sPBpD-b3VZfzg_y14u8kIg"
private const val AUTH_REDIRECT_URL = "https://gymapptracker.com/confirmed.html?platform=android"
private const val WEB_AUTH_REDIRECT_URL = "https://gymapptracker.com/confirmed.html?platform=web"
private const val NEEDS_PASSWORD_UPDATE_KEY = "needs_password_update"
private const val PENDING_SIGNUP_KEY = "pending_signup_confirmation"
private const val PENDING_RECOVERY_KEY = "pending_password_recovery"
private const val AUTH_TRANSACTION_MAX_AGE_MILLIS = 24 * 60 * 60 * 1_000L

sealed class AccountSession {
    data class Cloud(
        val userId: String,
        val email: String,
        val displayName: String,
        val accessToken: String,
        val refreshToken: String?
    ) : AccountSession()

    data class Local(val displayName: String) : AccountSession()
}

fun AccountSession.databaseName(): String {
    val raw = when (this) {
        is AccountSession.Cloud -> "cloud_$userId"
        is AccountSession.Local -> "local_${displayName.lowercase().trim()}"
    }
    return raw.replace(Regex("[^A-Za-z0-9_.-]"), "_").ifBlank { "local_default" }
}

data class AuthUiState(
    val session: AccountSession? = null,
    val isLoading: Boolean = false,
    val message: String? = null,
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

class CloudAuthManager(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
    private val refreshMutex = Mutex()
    private val initialSession = readSession()
    private val _authState = MutableStateFlow(
        AuthUiState(
            session = initialSession,
            needsPasswordUpdate = initialSession is AccountSession.Cloud &&
                prefs.getBoolean(NEEDS_PASSWORD_UPDATE_KEY, false)
        )
    )
    val authState: StateFlow<AuthUiState> = _authState.asStateFlow()

    suspend fun login(email: String, password: String): AccountSession.Cloud {
        val cleanEmail = normalizeEmail(email)
        validateAuthInput(email = cleanEmail, password = password)
        return requireNotNull(
            authenticate(
            path = "/auth/v1/token?grant_type=password",
            payload = JSONObject()
                .put("email", cleanEmail)
                .put("password", password)
            )
        )
    }

    suspend fun signUp(email: String, password: String, displayName: String): AccountSession.Cloud? {
        val cleanEmail = normalizeEmail(email)
        val cleanName = sanitizeDisplayName(displayName.ifBlank { cleanEmail.substringBefore("@") })
        validateAuthInput(email = cleanEmail, password = password, displayName = cleanName)
        val transaction = beginAuthTransaction(PENDING_SIGNUP_KEY, cleanEmail)
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
                allowEmailConfirmationPending = true
            )
        } catch (error: Throwable) {
            clearPendingAuthTransaction(PENDING_SIGNUP_KEY)
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
        val transaction = beginAuthTransaction(PENDING_RECOVERY_KEY, cleanEmail)
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
            clearPendingAuthTransaction(PENDING_RECOVERY_KEY)
            throw error
        }
    }

    fun setLocal(displayName: String) {
        val session = AccountSession.Local(displayName.trim().ifBlank { "Local" })
        prefs.edit()
            .putString("mode", "local")
            .putString("local_name", session.displayName)
            .remove("cloud")
            .remove(NEEDS_PASSWORD_UPDATE_KEY)
            .remove(PENDING_SIGNUP_KEY)
            .remove(PENDING_RECOVERY_KEY)
            .apply()
        _authState.value = AuthUiState(session = session)
    }

    fun setLoading(isLoading: Boolean) {
        _authState.value = _authState.value.copy(isLoading = isLoading, message = null)
    }

    fun setMessage(message: String?, isError: Boolean = true) {
        _authState.value = _authState.value.copy(isLoading = false, message = message, messageIsError = isError)
    }

    fun logout() {
        prefs.edit().clear().apply()
        _authState.value = AuthUiState()
    }

    suspend fun completeAuthCallback(uri: Uri): AuthCallbackResult = withContext(Dispatchers.IO) {
        completePKCEAuthCallback(uri)
    }

    private fun completePKCEAuthCallback(uri: Uri): AuthCallbackResult {
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
        persist(session)
        clearPendingAuthTransaction(pendingKey)
        val isRecovery = purpose == "recovery"
        prefs.edit().putBoolean(NEEDS_PASSWORD_UPDATE_KEY, isRecovery).apply()
        _authState.value = AuthUiState(
            session = session,
            messageIsError = false,
            needsPasswordUpdate = isRecovery
        )
        return AuthCallbackResult(session = session, kind = authCallbackKind(purpose))
    }

    suspend fun updatePassword(password: String) = withContext(Dispatchers.IO) {
        validateNewPassword(password)
        val session = _authState.value.session as? AccountSession.Cloud
            ?: error("Password recovery session is no longer available. Request a new reset email.")
        val freshSession = freshCloudSession(session)
        request(
            path = "/auth/v1/user",
            method = "PUT",
            token = freshSession.accessToken,
            body = JSONObject().put("password", password).toString()
        )
        prefs.edit().remove(NEEDS_PASSWORD_UPDATE_KEY).apply()
        _authState.value = _authState.value.copy(
            session = freshSession,
            isLoading = false,
            message = "Password updated.",
            messageIsError = false,
            needsPasswordUpdate = false
        )
    }

    suspend fun freshCloudSession(session: AccountSession.Cloud): AccountSession.Cloud {
        val currentSession = (_authState.value.session as? AccountSession.Cloud)
            ?.takeIf { it.userId == session.userId }
            ?: session
        if (!currentSession.needsRefresh()) return currentSession
        if (currentSession.refreshToken.isNullOrBlank()) return currentSession

        return refreshMutex.withLock {
            val latestSession = (_authState.value.session as? AccountSession.Cloud)
                ?.takeIf { it.userId == session.userId }
                ?: currentSession
            if (!latestSession.needsRefresh() || latestSession.refreshToken.isNullOrBlank()) {
                latestSession
            } else {
                refreshSession(latestSession)
            }
        }
    }

    suspend fun loadRemoteState(session: AccountSession.Cloud): JSONObject? = withContext(Dispatchers.IO) {
        val freshSession = freshCloudSession(session)
        val response = request(
            path = "/rest/v1/user_states?select=state&user_id=eq.${session.userId}&limit=1",
            method = "GET",
            token = freshSession.accessToken
        )
        val rows = JSONArray(response)
        rows.optJSONObject(0)?.optJSONObject("state")
    }

    suspend fun saveRemoteState(
        session: AccountSession.Cloud,
        state: JSONObject,
        xp: Int,
        level: Int,
        workouts: Int
    ) = withContext(Dispatchers.IO) {
        val freshSession = freshCloudSession(session)
        val now = System.currentTimeMillis()
        request(
            path = "/rest/v1/user_states?on_conflict=user_id",
            method = "POST",
            token = freshSession.accessToken,
            prefer = "resolution=merge-duplicates",
            body = JSONArray()
                .put(
                    JSONObject()
                        .put("user_id", session.userId)
                        .put("state", state)
                )
                .toString()
        )
        request(
            path = "/rest/v1/profiles?on_conflict=user_id",
            method = "POST",
            token = freshSession.accessToken,
            prefer = "resolution=merge-duplicates",
            body = JSONArray()
                .put(
                    JSONObject()
                        .put("user_id", session.userId)
                        .put("display_name", session.displayName)
                        .put("xp", xp)
                        .put("level", level)
                        .put("workouts", workouts)
                        .put("updated_at", java.time.Instant.ofEpochMilli(now).toString())
                )
                .toString()
        )
    }

    suspend fun loadOwnProfile(session: AccountSession.Cloud): CloudProfile? = withContext(Dispatchers.IO) {
        val freshSession = freshCloudSession(session)
        val response = request(
            path = "/rest/v1/profiles?select=user_id,display_name,xp,level,workouts&user_id=eq.${session.userId}&limit=1",
            method = "GET",
            token = freshSession.accessToken
        )
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
            val rows = JSONArray(response)
            List(rows.length()) { index ->
                val row = rows.optJSONObject(index) ?: JSONObject()
                LeaderboardRow(
                    profileId = row.optString("profile_id").takeIf { it.isNotBlank() },
                    displayName = row.optString("display_name").ifBlank { "GymApp user" },
                    xp = row.optInt("xp"),
                    level = row.optInt("level", 1),
                    workouts = row.optInt("workouts"),
                    isCurrentUser = row.optBoolean("is_current_user")
                )
            }
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
        if (accessToken.isBlank()) return@withContext session
        val refreshed = session.copy(
            accessToken = accessToken,
            refreshToken = json.optString("refresh_token").takeIf { it.isNotBlank() } ?: session.refreshToken
        )
        persist(refreshed)
        _authState.value = _authState.value.copy(session = refreshed)
        refreshed
    }

    private suspend fun authenticate(
        path: String,
        payload: JSONObject,
        allowEmailConfirmationPending: Boolean = false
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
        persist(session)
        prefs.edit().remove(NEEDS_PASSWORD_UPDATE_KEY).apply()
        clearPendingAuthTransaction(PENDING_SIGNUP_KEY)
        clearPendingAuthTransaction(PENDING_RECOVERY_KEY)
        _authState.value = AuthUiState(session = session, isLoading = true)
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

    private fun beginAuthTransaction(key: String, email: String): PendingAuthTransaction {
        val transaction = PendingAuthTransaction(
            state = randomURLSafeString(24),
            codeVerifier = randomURLSafeString(64),
            email = email,
            createdAtMillis = System.currentTimeMillis()
        )
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
        return transaction
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

    private fun clearPendingAuthTransaction(key: String) {
        prefs.edit().remove(key).apply()
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
                    .toString()
            )
            .apply()
    }

    private fun readSession(): AccountSession? {
        return when (prefs.getString("mode", null)) {
            "local" -> null
            "cloud" -> runCatching {
                val json = JSONObject(prefs.getString("cloud", null).orEmpty())
                AccountSession.Cloud(
                    userId = json.optString("userId"),
                    email = json.optString("email"),
                    displayName = json.optString("displayName"),
                    accessToken = json.optString("accessToken"),
                    refreshToken = json.optString("refreshToken").takeIf { it.isNotBlank() }
                )
            }.getOrNull()
            else -> null
        }
    }

    private fun request(
        path: String,
        method: String,
        token: String? = null,
        prefer: String? = null,
        body: String? = null
    ): String {
        val connection = (URL("$SUPABASE_URL$path").openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15_000
            readTimeout = 20_000
            setRequestProperty("apikey", SUPABASE_KEY)
            setRequestProperty("Content-Type", "application/json")
            token?.let { setRequestProperty("Authorization", "Bearer $it") }
            prefer?.let { setRequestProperty("Prefer", it) }
            if (body != null) {
                doOutput = true
                outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
        }
        val stream = if (connection.responseCode in 200..299) {
            connection.inputStream
        } else {
            connection.errorStream
        }
        val text = stream?.use { input ->
            BufferedReader(InputStreamReader(input)).readText()
        }.orEmpty()
        if (connection.responseCode !in 200..299) {
            error(friendlySupabaseError(connection.responseCode, text))
        }
        return text.ifBlank { "[]" }
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
