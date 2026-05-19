package com.example.gymapp.auth

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

private const val SUPABASE_URL = "https://owrcbsrectdgaotndtxy.supabase.co"
private const val SUPABASE_KEY = "sb_publishable_vvOMzx6V_sPBpD-b3VZfzg_y14u8kIg"
private const val AUTH_REDIRECT_URL = "https://eduard047.github.io/GymApp/"

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
    val message: String? = null
)

class CloudAuthManager(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
    private val _authState = MutableStateFlow(AuthUiState(session = readSession()))
    val authState: StateFlow<AuthUiState> = _authState.asStateFlow()

    suspend fun login(email: String, password: String): AccountSession.Cloud {
        validateAuthInput(email = email, password = password)
        return authenticate(
            path = "/auth/v1/token?grant_type=password",
            payload = JSONObject()
                .put("email", email.trim())
                .put("password", password)
        )
    }

    suspend fun signUp(email: String, password: String, displayName: String): AccountSession.Cloud {
        val cleanName = sanitizeDisplayName(displayName.ifBlank { email.substringBefore("@") })
        validateAuthInput(email = email, password = password, displayName = cleanName)
        return authenticate(
            path = "/auth/v1/signup?redirect_to=${java.net.URLEncoder.encode(AUTH_REDIRECT_URL, "UTF-8")}",
            payload = JSONObject()
                .put("email", email.trim())
                .put("password", password)
                .put(
                    "data",
                    JSONObject().put("display_name", cleanName)
                )
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

    fun setMessage(message: String?) {
        _authState.value = _authState.value.copy(isLoading = false, message = message)
    }

    fun logout() {
        prefs.edit().clear().apply()
        _authState.value = AuthUiState()
    }

    suspend fun freshCloudSession(session: AccountSession.Cloud): AccountSession.Cloud {
        return if (session.refreshToken.isNullOrBlank()) {
            session
        } else {
            refreshSession(session)
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

    private suspend fun authenticate(path: String, payload: JSONObject): AccountSession.Cloud = withContext(Dispatchers.IO) {
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
            error(text.ifBlank { "Network request failed: ${connection.responseCode}" })
        }
        return text.ifBlank { "[]" }
    }

    private fun validateAuthInput(email: String, password: String, displayName: String = "") {
        val cleanEmail = email.trim()
        require(Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$").matches(cleanEmail) && cleanEmail.length <= 254) {
            "Enter a valid email address."
        }
        require(password.length in 8..72 && password.any { it.isLetter() } && password.any { it.isDigit() }) {
            "Password must be 8-72 characters and include letters and numbers."
        }
        if (displayName.isNotBlank()) {
            require(displayName.length in 2..32 && displayName.all { it.isLetterOrDigit() || it == ' ' || it == '.' || it == '-' || it == '_' }) {
                "Display name can use letters, numbers, spaces, dot, dash and underscore."
            }
        }
    }

    private fun sanitizeDisplayName(value: String): String {
        return value
            .filter { it.isLetterOrDigit() || it == ' ' || it == '.' || it == '-' || it == '_' }
            .replace(Regex("\\s+"), " ")
            .trim()
            .take(32)
    }
}
