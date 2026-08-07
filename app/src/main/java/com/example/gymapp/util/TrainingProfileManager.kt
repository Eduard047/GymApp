package com.example.gymapp.util

import android.content.Context
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.databaseName
import java.security.MessageDigest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class TrainingSplit {
    UpperLower,
    FullBody,
    PushPullLegs,
    Custom
}

enum class TrainingGoal {
    AestheticFatLoss,
    MuscleGain,
    Strength,
    Balanced
}

enum class CalorieMode {
    Deficit,
    Maintenance,
    Surplus
}

data class TrainingProfile(
    val split: TrainingSplit = TrainingSplit.UpperLower,
    val workoutsPerWeek: Int = 4,
    val goal: TrainingGoal = TrainingGoal.AestheticFatLoss,
    val calorieMode: CalorieMode = CalorieMode.Deficit
)

internal fun trainingProfileAccountKey(session: AccountSession?): String? {
    val stableIdentity = session?.databaseName() ?: return null
    return trainingProfileAccountKey(stableIdentity)
}

private fun trainingProfileAccountKey(stableIdentity: String): String {
    val identityBytes = stableIdentity.toByteArray(Charsets.UTF_8)
    require(identityBytes.isNotEmpty() && identityBytes.size <= 512)
    require(stableIdentity.none(Char::isISOControl))
    return MessageDigest.getInstance("SHA-256")
        .digest("GymAppTrainingProfileAccountV1:".toByteArray(Charsets.UTF_8) + identityBytes)
        .joinToString(separator = "") { byte -> "%02x".format(byte) }
}

class TrainingProfileManager(
    context: Context
) {
    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val lock = Any()
    private var activeAccountKey: String? = null
    private val _profile = MutableStateFlow(TrainingProfile())
    val profile: StateFlow<TrainingProfile> = _profile.asStateFlow()

    init {
        // The legacy file had no owner binding. Assigning it to whichever account logs in next
        // would expose another person's fitness settings, so it is deliberately discarded.
        appContext.deleteSharedPreferences(LEGACY_PREFS_NAME)
    }

    internal fun switchAccount(session: AccountSession?) {
        val nextAccountKey = trainingProfileAccountKey(session)
        synchronized(lock) {
            if (activeAccountKey == nextAccountKey) return
            activeAccountKey = nextAccountKey
            _profile.value = nextAccountKey?.let(::readProfile) ?: TrainingProfile()
        }
    }

    fun updateSplit(split: TrainingSplit) {
        synchronized(lock) {
            updateProfileLocked(_profile.value.copy(split = split))
        }
    }

    fun updateWorkoutsPerWeek(value: Int) {
        synchronized(lock) {
            updateProfileLocked(_profile.value.copy(workoutsPerWeek = value.coerceIn(2, 6)))
        }
    }

    fun updateGoal(goal: TrainingGoal) {
        synchronized(lock) {
            updateProfileLocked(_profile.value.copy(goal = goal))
        }
    }

    fun updateCalorieMode(mode: CalorieMode) {
        synchronized(lock) {
            updateProfileLocked(_profile.value.copy(calorieMode = mode))
        }
    }

    fun clearAccount(session: AccountSession): Boolean {
        return clearAccountByDatabaseName(session.databaseName())
    }

    internal fun clearAccountByDatabaseName(databaseName: String): Boolean {
        val accountKey = trainingProfileAccountKey(databaseName)
        synchronized(lock) {
            val cleared = preferences.edit()
                .remove(scopedKey(accountKey, KEY_SPLIT))
                .remove(scopedKey(accountKey, KEY_WORKOUTS_PER_WEEK))
                .remove(scopedKey(accountKey, KEY_GOAL))
                .remove(scopedKey(accountKey, KEY_CALORIE_MODE))
                .commit()
            if (cleared && activeAccountKey == accountKey) {
                _profile.value = TrainingProfile()
            }
            return cleared
        }
    }

    private fun updateProfileLocked(profile: TrainingProfile) {
        val accountKey = activeAccountKey ?: return
        preferences.edit()
            .putString(scopedKey(accountKey, KEY_SPLIT), profile.split.name)
            .putInt(scopedKey(accountKey, KEY_WORKOUTS_PER_WEEK), profile.workoutsPerWeek)
            .putString(scopedKey(accountKey, KEY_GOAL), profile.goal.name)
            .putString(scopedKey(accountKey, KEY_CALORIE_MODE), profile.calorieMode.name)
            .apply()
        _profile.value = profile
    }

    private fun readProfile(accountKey: String): TrainingProfile {
        require(accountKey.matches(ACCOUNT_KEY_PATTERN))
        return TrainingProfile(
            split = preferences.enumValue(
                scopedKey(accountKey, KEY_SPLIT),
                TrainingSplit.UpperLower
            ),
            workoutsPerWeek = preferences.getInt(
                scopedKey(accountKey, KEY_WORKOUTS_PER_WEEK),
                4
            ).coerceIn(2, 6),
            goal = preferences.enumValue(
                scopedKey(accountKey, KEY_GOAL),
                TrainingGoal.AestheticFatLoss
            ),
            calorieMode = preferences.enumValue(
                scopedKey(accountKey, KEY_CALORIE_MODE),
                CalorieMode.Deficit
            )
        )
    }

    private fun scopedKey(accountKey: String, field: String): String = "$accountKey:$field"

    private inline fun <reified T : Enum<T>> android.content.SharedPreferences.enumValue(
        key: String,
        fallback: T
    ): T {
        val rawValue = getString(key, null) ?: return fallback
        return enumValues<T>().firstOrNull { it.name == rawValue } ?: fallback
    }

    private companion object {
        const val PREFS_NAME = "gym_training_profiles"
        const val LEGACY_PREFS_NAME = "gym_training_profile"
        const val KEY_SPLIT = "split"
        const val KEY_WORKOUTS_PER_WEEK = "workouts_per_week"
        const val KEY_GOAL = "goal"
        const val KEY_CALORIE_MODE = "calorie_mode"
        val ACCOUNT_KEY_PATTERN = Regex("^[0-9a-f]{64}$")
    }
}
