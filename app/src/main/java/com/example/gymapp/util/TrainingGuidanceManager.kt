package com.example.gymapp.util

import android.content.Context
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.databaseName
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.WorkoutFeedback
import com.example.gymapp.data.repository.WorkoutFeedbackRecord
import java.security.MessageDigest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject

internal enum class FirstRunTutorialCompletion(val wireValue: String) {
    Completed("completed"),
    Skipped("skipped");

    companion object {
        fun fromWireValue(value: String?): FirstRunTutorialCompletion? = entries.firstOrNull {
            it.wireValue == value
        }
    }
}

internal data class FirstRunTutorialProgress(
    val version: Int = 0,
    val completion: FirstRunTutorialCompletion? = null
) {
    val isTerminal: Boolean
        get() = version > 0 && completion != null
}

class TrainingGuidanceManager(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE
    )
    private val lock = Any()
    private var activeAccountKey: String? = null
    private val _activationDismissed = MutableStateFlow(false)
    private val _feedback = MutableStateFlow<Map<Long, WorkoutFeedbackRecord>>(emptyMap())
    private val _tutorialProgress = MutableStateFlow(FirstRunTutorialProgress())

    val activationDismissed: StateFlow<Boolean> = _activationDismissed.asStateFlow()
    val feedback: StateFlow<Map<Long, WorkoutFeedbackRecord>> = _feedback.asStateFlow()
    internal val tutorialProgress: StateFlow<FirstRunTutorialProgress> =
        _tutorialProgress.asStateFlow()

    internal val activeBinding: String?
        get() = synchronized(lock) { activeAccountKey }

    internal fun accountBinding(session: AccountSession): String =
        accountKey(session.databaseName())

    internal fun switchAccount(session: AccountSession?) {
        val nextKey = session?.databaseName()?.let(::accountKey)
        synchronized(lock) {
            if (nextKey == activeAccountKey) return
            activeAccountKey = nextKey
            _activationDismissed.value = nextKey?.let { key ->
                preferences.all[scopedKey(key, KEY_ACTIVATION_DISMISSED)] as? Boolean ?: false
            } ?: false
            _feedback.value = nextKey?.let(::readFeedback).orEmpty()
            _tutorialProgress.value = nextKey?.let(::readTutorialProgress)
                ?: FirstRunTutorialProgress()
        }
    }

    internal fun shouldRunAutomaticTutorial(
        version: Int,
        expectedAccountBinding: String
    ): Boolean = synchronized(lock) {
        version > 0 &&
            activeAccountKey == expectedAccountBinding &&
            (_tutorialProgress.value.version < version ||
                !_tutorialProgress.value.isTerminal)
    }

    internal fun recordTutorialCompletion(
        version: Int,
        completion: FirstRunTutorialCompletion,
        expectedAccountBinding: String
    ): Boolean = synchronized(lock) {
        if (version <= 0 || activeAccountKey != expectedAccountBinding) return false
        val previous = _tutorialProgress.value
        val next = FirstRunTutorialProgress(version, completion)
        val versionKey = scopedKey(expectedAccountBinding, KEY_TUTORIAL_VERSION)
        val completionKey = scopedKey(expectedAccountBinding, KEY_TUTORIAL_COMPLETION)
        val saved = preferences.edit()
            .putInt(versionKey, next.version)
            .putString(completionKey, next.completion?.wireValue)
            .commit()
        if (saved) {
            _tutorialProgress.value = next
        } else {
            val rollback = preferences.edit()
            if (previous.isTerminal) {
                rollback
                    .putInt(versionKey, previous.version)
                    .putString(completionKey, previous.completion?.wireValue)
            } else {
                rollback.remove(versionKey).remove(completionKey)
            }
            rollback.commit()
            _tutorialProgress.value = previous
        }
        saved
    }

    fun dismissActivation(): Boolean = setActivationDismissed(true)

    internal fun dismissActivation(expectedAccountBinding: String): Boolean =
        setActivationDismissed(true, expectedAccountBinding)

    fun setActivationDismissed(dismissed: Boolean): Boolean =
        setActivationDismissed(dismissed, expectedAccountBinding = null)

    internal fun setActivationDismissed(
        dismissed: Boolean,
        expectedAccountBinding: String?
    ): Boolean = synchronized(lock) {
        val key = activeAccountKey ?: return false
        if (expectedAccountBinding != null && key != expectedAccountBinding) return false
        val previousDismissed = _activationDismissed.value
        val saved = preferences.edit()
            .putBoolean(scopedKey(key, KEY_ACTIVATION_DISMISSED), dismissed)
            .commit()
        if (saved) {
            _activationDismissed.value = dismissed
        } else {
            // Keep both the observable state and SharedPreferences' in-memory
            // snapshot on the last accepted value when the disk commit fails.
            preferences.edit()
                .putBoolean(scopedKey(key, KEY_ACTIVATION_DISMISSED), previousDismissed)
                .commit()
            _activationDismissed.value = previousDismissed
        }
        saved
    }

    internal fun restoreActivationDismissedForBinding(
        dismissed: Boolean,
        accountBinding: String
    ): Boolean = synchronized(lock) {
        if (!accountBinding.matches(ACCOUNT_KEY_PATTERN)) return@synchronized false
        val saved = preferences.edit()
            .putBoolean(scopedKey(accountBinding, KEY_ACTIVATION_DISMISSED), dismissed)
            .commit()
        if (saved && activeAccountKey == accountBinding) {
            _activationDismissed.value = dismissed
        }
        saved
    }

    fun saveFeedback(
        sessionId: Long,
        sessionStartedAtMillis: Long,
        feedback: WorkoutFeedback,
        ownedSessions: Map<Long, Long>,
        expectedAccountBinding: String
    ): Boolean = synchronized(lock) {
        val key = activeAccountKey ?: return false
        if (key != expectedAccountBinding) return false
        if (sessionId <= 0L || ownedSessions[sessionId] != sessionStartedAtMillis ||
            ownedSessions.size > WorkoutDataLimits.MAX_SESSIONS ||
            !WorkoutDataLimits.isValidTimestamp(sessionStartedAtMillis)
        ) {
            return false
        }
        val next = (_feedback.value + (
            sessionId to WorkoutFeedbackRecord(sessionId, feedback, sessionStartedAtMillis)
        ))
            .filter { (ownedId, record) -> ownedSessions[ownedId] == record.sessionStartedAtMillis }
            .values
            .sortedWith(
                compareByDescending<WorkoutFeedbackRecord> { it.sessionStartedAtMillis }
                    .thenByDescending { it.sessionId }
            )
            .take(MAX_FEEDBACK_ENTRIES)
            .associateBy(WorkoutFeedbackRecord::sessionId)
        persistFeedback(key, next)
    }

    fun pruneFeedback(
        ownedSessions: Map<Long, Long>,
        expectedAccountBinding: String
    ): Boolean = synchronized(lock) {
        val key = activeAccountKey ?: return false
        if (key != expectedAccountBinding) return false
        if (ownedSessions.size > WorkoutDataLimits.MAX_SESSIONS ||
            ownedSessions.any { (id, startedAt) ->
                id <= 0L || !WorkoutDataLimits.isValidTimestamp(startedAt)
            }
        ) {
            return false
        }
        val next = _feedback.value.filter { (id, record) ->
            ownedSessions[id] == record.sessionStartedAtMillis
        }
        if (next == _feedback.value) return true
        persistFeedback(key, next)
    }

    fun clearAccount(session: AccountSession): Boolean =
        clearAccountByDatabaseName(session.databaseName())

    internal fun clearAccountByDatabaseName(databaseName: String): Boolean {
        val key = accountKey(databaseName)
        synchronized(lock) {
            val cleared = preferences.edit()
                .remove(scopedKey(key, KEY_ACTIVATION_DISMISSED))
                .remove(scopedKey(key, KEY_FEEDBACK))
                .remove(scopedKey(key, KEY_TUTORIAL_VERSION))
                .remove(scopedKey(key, KEY_TUTORIAL_COMPLETION))
                .commit()
            if (cleared && activeAccountKey == key) {
                _activationDismissed.value = false
                _feedback.value = emptyMap()
                _tutorialProgress.value = FirstRunTutorialProgress()
            }
            return cleared
        }
    }

    private fun persistFeedback(
        accountKey: String,
        entries: Map<Long, WorkoutFeedbackRecord>
    ): Boolean {
        val array = JSONArray()
        entries.values
            .sortedWith(
                compareBy<WorkoutFeedbackRecord> { it.sessionStartedAtMillis }
                    .thenBy { it.sessionId }
            )
            .forEach { record ->
                array.put(
                    JSONArray()
                        .put(record.sessionId)
                        .put(record.feedback.wireValue)
                        .put(record.sessionStartedAtMillis)
                )
            }
        val encoded = JSONObject().put("v", 1).put("f", array).toString()
        if (encoded.toByteArray(Charsets.UTF_8).size > MAX_FEEDBACK_BYTES) return false
        val saved = preferences.edit()
            .putString(scopedKey(accountKey, KEY_FEEDBACK), encoded)
            .commit()
        if (saved) _feedback.value = entries
        return saved
    }

    private fun readFeedback(accountKey: String): Map<Long, WorkoutFeedbackRecord> {
        val raw = preferences.all[scopedKey(accountKey, KEY_FEEDBACK)] as? String
            ?: return emptyMap()
        if (raw.toByteArray(Charsets.UTF_8).size > MAX_FEEDBACK_BYTES) return emptyMap()
        return runCatching {
            WorkoutDataLimits.requireSafeJsonEnvelope(raw, MAX_FEEDBACK_BYTES)
            val root = JSONObject(raw)
            require(root.keys().asSequence().toSet() == setOf("v", "f"))
            require((root.opt("v") as? Number)?.toDouble() == 1.0)
            val array = root.getJSONArray("f")
            require(array.length() <= MAX_FEEDBACK_ENTRIES)
            val result = linkedMapOf<Long, WorkoutFeedbackRecord>()
            repeat(array.length()) { index ->
                val item = array.optJSONArray(index) ?: error("Invalid feedback entry")
                require(item.length() == 3)
                val sessionId = exactLong(item.opt(0))
                val wireValue = item.opt(1) as? String ?: error("Invalid feedback")
                val recordedAt = exactLong(item.opt(2))
                val value = WorkoutFeedback.fromWireValue(wireValue) ?: error("Invalid feedback")
                require(sessionId > 0L && WorkoutDataLimits.isValidTimestamp(recordedAt))
                require(result.put(sessionId, WorkoutFeedbackRecord(sessionId, value, recordedAt)) == null)
            }
            result.toMap()
        }.getOrElse { emptyMap() }
    }

    private fun readTutorialProgress(accountKey: String): FirstRunTutorialProgress {
        val version = (preferences.all[scopedKey(accountKey, KEY_TUTORIAL_VERSION)] as? Int)
            ?.takeIf { it > 0 }
            ?: return FirstRunTutorialProgress()
        val completion = FirstRunTutorialCompletion.fromWireValue(
            preferences.all[scopedKey(accountKey, KEY_TUTORIAL_COMPLETION)] as? String
        ) ?: return FirstRunTutorialProgress()
        return FirstRunTutorialProgress(version, completion)
    }

    private fun scopedKey(accountKey: String, field: String): String = "$accountKey:$field"

    private fun exactLong(raw: Any?): Long = when (raw) {
        is Byte -> raw.toLong()
        is Short -> raw.toLong()
        is Int -> raw.toLong()
        is Long -> raw
        else -> error("Integer is invalid")
    }

    private fun accountKey(databaseName: String): String {
        val identity = databaseName.toByteArray(Charsets.UTF_8)
        require(identity.isNotEmpty() && identity.size <= 512 && databaseName.none(Char::isISOControl))
        return MessageDigest.getInstance("SHA-256")
            .digest(ACCOUNT_KEY_SALT.toByteArray(Charsets.UTF_8) + identity)
            .joinToString("") { byte -> "%02x".format(byte) }
    }

    private companion object {
        const val PREFERENCES_NAME = "gym_training_guidance_v1"
        const val ACCOUNT_KEY_SALT = "GymAppTrainingGuidanceAccountV1:"
        const val KEY_ACTIVATION_DISMISSED = "activation_dismissed"
        const val KEY_FEEDBACK = "feedback"
        const val KEY_TUTORIAL_VERSION = "tutorial_version"
        const val KEY_TUTORIAL_COMPLETION = "tutorial_completion"
        const val MAX_FEEDBACK_ENTRIES = 128
        const val MAX_FEEDBACK_BYTES = 32 * 1_024
        val ACCOUNT_KEY_PATTERN = Regex("^[0-9a-f]{64}$")
    }
}
