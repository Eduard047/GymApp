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
import java.net.URLDecoder
import java.util.Base64

private const val SUPABASE_URL = "https://owrcbsrectdgaotndtxy.supabase.co"
private const val SUPABASE_KEY = "sb_publishable_vvOMzx6V_sPBpD-b3VZfzg_y14u8kIg"
private const val AUTH_REDIRECT_URL = "https://gymapptracker.com/confirmed.html?platform=android"

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
    val messageIsError: Boolean = true
)

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
    private val _authState = MutableStateFlow(AuthUiState(session = readSession()))
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
        return authenticate(
            path = "/auth/v1/signup?redirect_to=${java.net.URLEncoder.encode(AUTH_REDIRECT_URL, "UTF-8")}",
            payload = JSONObject()
                .put("email", cleanEmail)
                .put("password", password)
                .put(
                    "data",
                    JSONObject().put("display_name", cleanName)
                ),
            allowEmailConfirmationPending = true
        )
    }

    suspend fun resendSignUpConfirmation(email: String) = withContext(Dispatchers.IO) {
        val cleanEmail = normalizeEmail(email)
        validateEmail(cleanEmail)
        request(
            path = "/auth/v1/resend?redirect_to=${java.net.URLEncoder.encode(AUTH_REDIRECT_URL, "UTF-8")}",
            method = "POST",
            body = JSONObject()
                .put("type", "signup")
                .put("email", cleanEmail)
                .toString()
        )
    }

    fun setLocal(displayName: String) {
        val session = AccountSession.Local(displayName.trim().ifBlank { "Local" })
        prefs.edit()
            .putString("mode", "local")
            .putString("local_name", session.displayName)
            .remove("cloud")
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

    suspend fun completeEmailConfirmation(uri: Uri): AccountSession.Cloud = withContext(Dispatchers.IO) {
        val params = uri.authRedirectParams()
        val accessToken = params["access_token"].orEmpty()
        require(accessToken.isNotBlank()) {
            "Email confirmation link did not include a valid session. Try logging in."
        }

        val user = JSONObject(
            request(
                path = "/auth/v1/user",
                method = "GET",
                token = accessToken
            )
        )
        val userId = user.optString("id")
        require(userId.isNotBlank()) {
            "Email was confirmed, but the account session could not be loaded. Try logging in."
        }

        val email = user.optString("email")
        val displayName = user.optJSONObject("user_metadata")
            ?.optString("display_name")
            ?.takeIf { it.isNotBlank() }
            ?: email.substringBefore("@").ifBlank { "Cloud" }
        val session = AccountSession.Cloud(
            userId = userId,
            email = email,
            displayName = displayName,
            accessToken = accessToken,
            refreshToken = params["refresh_token"]?.takeIf { it.isNotBlank() }
        )
        persist(session)
        _authState.value = AuthUiState(session = session)
        session
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
        _authState.value = AuthUiState(session = session, isLoading = true)
        session
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
                "Too many confirmation emails were requested. Supabase may block new emails for up to an hour on the built-in sender. Try again later, or contact support if the email never arrives."

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

    private fun Uri.authRedirectParams(): Map<String, String> {
        val values = linkedMapOf<String, String>()
        queryParameterNames.forEach { key ->
            values[key] = getQueryParameter(key).orEmpty()
        }
        fragment.orEmpty()
            .split("&")
            .filter { it.isNotBlank() && it.contains("=") }
            .forEach { pair ->
                val key = pair.substringBefore("=")
                val value = pair.substringAfter("=")
                values[urlDecode(key)] = urlDecode(value)
            }
        return values
    }

    private fun urlDecode(value: String): String {
        return URLDecoder.decode(value, Charsets.UTF_8.name())
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
