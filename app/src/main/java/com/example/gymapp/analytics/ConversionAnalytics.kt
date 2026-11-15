package com.example.gymapp.analytics

import android.content.Context
import android.os.Bundle
import com.example.gymapp.BuildConfig
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.analytics.FirebaseAnalytics
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Consent Mode v2 signals sent to Firebase. Ad personalization is never granted: the app only
 * measures conversions and never builds audiences.
 */
data class AnalyticsConsentState(
    val analyticsStorage: Boolean,
    val adStorage: Boolean,
    val adUserData: Boolean,
    val adPersonalization: Boolean
)

internal fun consentStateFor(granted: Boolean) = AnalyticsConsentState(
    analyticsStorage = granted,
    adStorage = granted,
    adUserData = granted,
    adPersonalization = false
)

/** The only seam to Firebase Analytics; tests use a recording fake. */
interface AnalyticsSink {
    /** False for the no-op sink used by builds without a Firebase client. */
    val available: Boolean
    fun setCollectionEnabled(enabled: Boolean)
    fun setConsent(state: AnalyticsConsentState)
    fun resetAnalyticsData()
    fun logEvent(name: String, params: Map<String, String>)
}

/** Used when no Firebase client is configured (debug/CI builds): every call is ignored. */
object NoOpAnalyticsSink : AnalyticsSink {
    override val available: Boolean = false
    override fun setCollectionEnabled(enabled: Boolean) = Unit
    override fun setConsent(state: AnalyticsConsentState) = Unit
    override fun resetAnalyticsData() = Unit
    override fun logEvent(name: String, params: Map<String, String>) = Unit
}

/** Where the consent choice and the one-shot first-workout flag live; SharedPreferences in the app. */
interface ConversionAnalyticsStorage {
    /** True = allowed, false = declined, null = never asked. */
    fun readConsent(): Boolean?
    fun writeConsent(granted: Boolean)
    fun readFirstWorkoutLogged(): Boolean
    fun writeFirstWorkoutLogged()
}

/**
 * Consent-gated conversion measurement for Google Ads (via Google Analytics for Firebase). It owns
 * every Firebase Analytics call; the rest of the app only talks to this class. Nothing is sent
 * unless the user has allowed measurement, and events never carry user content.
 */
class ConversionAnalytics internal constructor(
    private val storage: ConversionAnalyticsStorage,
    private val sink: AnalyticsSink
) {
    constructor(context: Context) : this(
        SharedPreferencesConversionAnalyticsStorage(context.applicationContext),
        if (BuildConfig.FIREBASE_CONFIGURED) {
            FirebaseAnalyticsSink(context.applicationContext)
        } else {
            NoOpAnalyticsSink
        }
    )

    /** True when this build can measure at all; the consent prompt and settings row are hidden otherwise. */
    val available: Boolean get() = sink.available

    private val _consent = MutableStateFlow(storage.readConsent())

    /** Current choice: true = allowed, false = declined, null = not asked yet. */
    val consent: StateFlow<Boolean?> = _consent.asStateFlow()

    /** Re-applies a stored "allowed" at startup. Declined or unasked needs nothing: the manifest defaults are off. */
    fun applyStoredChoice() {
        if (_consent.value == true) applyToSink(true)
    }

    fun setConsent(granted: Boolean) {
        storage.writeConsent(granted)
        _consent.value = granted
        applyToSink(granted)
        if (!granted) sink.resetAnalyticsData()
    }

    /** Right after an email account was created. */
    fun logSignUp() {
        if (_consent.value != true) return
        sink.logEvent(EVENT_SIGN_UP, mapOf(PARAM_METHOD to METHOD_EMAIL))
    }

    /**
     * After a workout was finished and saved. [totalWorkoutCount] is the number of saved workouts
     * including the one just finished, so only a brand-new history (exactly 1) can be a first
     * workout; users who already had workouts never fire it. Fires at most once per install.
     */
    fun onWorkoutFinished(totalWorkoutCount: Int) {
        if (_consent.value != true) return
        if (totalWorkoutCount != 1) return
        if (storage.readFirstWorkoutLogged()) return
        sink.logEvent(EVENT_FIRST_WORKOUT, emptyMap())
        storage.writeFirstWorkoutLogged()
    }

    private fun applyToSink(granted: Boolean) {
        sink.setCollectionEnabled(granted)
        sink.setConsent(consentStateFor(granted))
    }

    companion object {
        const val EVENT_SIGN_UP = "sign_up"
        const val EVENT_FIRST_WORKOUT = "first_workout"
        const val PARAM_METHOD = "method"
        const val METHOD_EMAIL = "email"
        const val PREFS_NAME = "gym_analytics_consent_v1"
        const val KEY_CONSENT = "consent"
        const val KEY_FIRST_WORKOUT_LOGGED = "first_workout_logged"
    }
}

private class SharedPreferencesConversionAnalyticsStorage(context: Context) :
    ConversionAnalyticsStorage {
    private val preferences =
        context.getSharedPreferences(ConversionAnalytics.PREFS_NAME, Context.MODE_PRIVATE)

    override fun readConsent(): Boolean? =
        if (preferences.contains(ConversionAnalytics.KEY_CONSENT)) {
            preferences.getBoolean(ConversionAnalytics.KEY_CONSENT, false)
        } else {
            null
        }

    override fun writeConsent(granted: Boolean) {
        preferences.edit().putBoolean(ConversionAnalytics.KEY_CONSENT, granted).apply()
    }

    override fun readFirstWorkoutLogged(): Boolean =
        preferences.getBoolean(ConversionAnalytics.KEY_FIRST_WORKOUT_LOGGED, false)

    override fun writeFirstWorkoutLogged() {
        preferences.edit().putBoolean(ConversionAnalytics.KEY_FIRST_WORKOUT_LOGGED, true).apply()
    }
}

/** Shared by push and analytics: the default FirebaseApp built from the reviewed BuildConfig client. */
internal object GymFirebaseApp {
    @Synchronized
    fun ensureInitialized(context: Context): Boolean = runCatching {
        runCatching { FirebaseApp.getInstance() }.getOrElse {
            val options = FirebaseOptions.Builder()
                .setProjectId(BuildConfig.FIREBASE_PROJECT_ID)
                .setApplicationId(BuildConfig.FIREBASE_APPLICATION_ID)
                .setApiKey(BuildConfig.FIREBASE_API_KEY)
                .setGcmSenderId(BuildConfig.FIREBASE_SENDER_ID)
                .build()
            checkNotNull(FirebaseApp.initializeApp(context.applicationContext, options))
        }
        true
    }.getOrDefault(false)
}

/** Real sink. Created lazily on first use and never throws: a Firebase failure must not affect the app. */
private class FirebaseAnalyticsSink(private val context: Context) : AnalyticsSink {
    override val available: Boolean = true

    private val analytics: FirebaseAnalytics? by lazy {
        runCatching {
            if (GymFirebaseApp.ensureInitialized(context)) {
                FirebaseAnalytics.getInstance(context)
            } else {
                null
            }
        }.getOrNull()
    }

    override fun setCollectionEnabled(enabled: Boolean) {
        runCatching { analytics?.setAnalyticsCollectionEnabled(enabled) }
    }

    override fun setConsent(state: AnalyticsConsentState) {
        runCatching {
            analytics?.setConsent(
                mapOf(
                    FirebaseAnalytics.ConsentType.ANALYTICS_STORAGE to state.analyticsStorage.status(),
                    FirebaseAnalytics.ConsentType.AD_STORAGE to state.adStorage.status(),
                    FirebaseAnalytics.ConsentType.AD_USER_DATA to state.adUserData.status(),
                    FirebaseAnalytics.ConsentType.AD_PERSONALIZATION to state.adPersonalization.status()
                )
            )
        }
    }

    override fun resetAnalyticsData() {
        runCatching { analytics?.resetAnalyticsData() }
    }

    override fun logEvent(name: String, params: Map<String, String>) {
        runCatching {
            val bundle = Bundle()
            params.forEach { (key, value) -> bundle.putString(key, value) }
            analytics?.logEvent(name, bundle)
        }
    }

    private fun Boolean.status() =
        if (this) FirebaseAnalytics.ConsentStatus.GRANTED else FirebaseAnalytics.ConsentStatus.DENIED
}
