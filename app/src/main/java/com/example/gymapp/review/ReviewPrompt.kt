package com.example.gymapp.review

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.util.Log
import com.example.gymapp.BuildConfig
import com.google.android.play.core.review.ReviewManager
import com.google.android.play.core.review.ReviewManagerFactory
import com.google.android.play.core.review.testing.FakeReviewManager

/**
 * Native Play In-App Review prompt.
 *
 * Asked at most [ReviewPromptPolicy.MAX_REQUESTS] times per install, never more often than every
 * [ReviewPromptPolicy.MIN_DAYS_BETWEEN_REQUESTS] days, and only right after the user taps Done on the
 * post-workout summary of a workout with at least [ReviewPromptPolicy.MIN_LOGGED_SETS] logged set.
 * The iOS client declares the same constants (Domain/ReviewPromptPolicy.swift); keep both in sync.
 *
 * It does not depend on analytics consent and is not tied to an account (counters are per install).
 */
object ReviewPromptPolicy {
    const val MIN_DAYS_BETWEEN_REQUESTS = 90
    const val MAX_REQUESTS = 3
    const val MIN_LOGGED_SETS = 1

    private const val MILLIS_PER_DAY = 24L * 60L * 60L * 1000L

    fun isEligible(
        savedWorkoutCount: Int,
        loggedSetsInWorkout: Int,
        lastRequestAtMillis: Long?,
        requestCount: Int,
        nowMillis: Long,
        isDemo: Boolean = false
    ): Boolean {
        if (isDemo) return false
        if (loggedSetsInWorkout < MIN_LOGGED_SETS) return false
        if (savedWorkoutCount < 1) return false
        if (requestCount >= MAX_REQUESTS) return false
        if (lastRequestAtMillis != null) {
            val elapsed = nowMillis - lastRequestAtMillis
            // A clock that moved backwards must not unlock an earlier prompt.
            if (elapsed < MIN_DAYS_BETWEEN_REQUESTS * MILLIS_PER_DAY) return false
        }
        return true
    }
}

/** Per-install counters kept in their own preferences file (not account scoped). */
class ReviewPromptStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun lastRequestAtMillis(): Long? =
        if (prefs.contains(KEY_LAST_REQUEST_AT)) prefs.getLong(KEY_LAST_REQUEST_AT, 0L) else null

    fun requestCount(): Int = prefs.getInt(KEY_REQUEST_COUNT, 0)

    fun recordAttempt(nowMillis: Long) {
        prefs.edit()
            .putLong(KEY_LAST_REQUEST_AT, nowMillis)
            .putInt(KEY_REQUEST_COUNT, requestCount() + 1)
            .apply()
    }

    private companion object {
        const val PREFS_NAME = "gym_review_prompt"
        const val KEY_LAST_REQUEST_AT = "last_review_request_at"
        const val KEY_REQUEST_COUNT = "review_request_count"
    }
}

object ReviewPromptRequester {
    private const val TAG = "GymReviewPrompt"

    /**
     * Call only from the post-workout summary Done path. The attempt is recorded before the Play API is
     * touched, and every failure is swallowed: the dialog may be skipped by Play quota, and the app never
     * learns whether it was shown.
     */
    fun maybeRequest(
        context: Context,
        savedWorkoutCount: Int,
        loggedSetsInWorkout: Int,
        isDemo: Boolean = false,
        nowMillis: Long = System.currentTimeMillis()
    ) {
        runCatching {
            val store = ReviewPromptStore(context)
            val eligible = ReviewPromptPolicy.isEligible(
                savedWorkoutCount = savedWorkoutCount,
                loggedSetsInWorkout = loggedSetsInWorkout,
                lastRequestAtMillis = store.lastRequestAtMillis(),
                requestCount = store.requestCount(),
                nowMillis = nowMillis,
                isDemo = isDemo
            )
            if (!eligible) {
                debugLog("skip: not eligible (workouts=$savedWorkoutCount, sets=$loggedSetsInWorkout)")
                return
            }
            val activity = context.findActivity()
            if (activity == null || activity.isFinishing || activity.isDestroyed) {
                debugLog("skip: no live activity")
                return
            }
            store.recordAttempt(nowMillis)
            debugLog("fire: requesting review flow")
            val manager: ReviewManager = if (BuildConfig.DEBUG) {
                FakeReviewManager(activity.applicationContext)
            } else {
                ReviewManagerFactory.create(activity.applicationContext)
            }
            manager.requestReviewFlow()
                .addOnSuccessListener { info ->
                    runCatching {
                        if (!activity.isFinishing && !activity.isDestroyed) {
                            manager.launchReviewFlow(activity, info)
                                .addOnFailureListener { debugLog("launch failed: ${it.message}") }
                        }
                    }
                }
                .addOnFailureListener { debugLog("request failed: ${it.message}") }
        }.onFailure { debugLog("failed: ${it.message}") }
    }

    private fun debugLog(message: String) {
        if (BuildConfig.DEBUG) Log.d(TAG, message)
    }

    private tailrec fun Context.findActivity(): Activity? = when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }
}
