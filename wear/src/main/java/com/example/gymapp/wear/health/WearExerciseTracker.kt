package com.example.gymapp.wear.health

import android.annotation.SuppressLint
import android.content.Context
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseTrackedStatus
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import androidx.health.services.client.clearUpdateCallback
import androidx.health.services.client.endExercise
import androidx.health.services.client.getCapabilities
import androidx.health.services.client.getCurrentExerciseInfo
import androidx.health.services.client.startExercise
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

enum class WearHealthStatus {
    /** No workout is being tracked. */
    Idle,
    Starting,
    Active,

    /** The user denied the heart-rate permission: the workout works, without heart rate. */
    Denied,

    /** Health Services is missing, busy with another app, or the device has no heart-rate sensor. */
    Unavailable
}

/** Live health data for the UI. Null values mean "no data yet / not available". */
data class WearHealthState(
    val status: WearHealthStatus = WearHealthStatus.Idle,
    val heartRate: Int? = null,
    val averageHeartRate: Int? = null,
    val maxHeartRate: Int? = null,
    /** Total energy of the session in whole kcal, from Health Services CALORIES_TOTAL. */
    val caloriesKcal: Int? = null
)

/**
 * Process-wide owner of the Health Services strength-training exercise. The session also counts
 * as an exercise on the watch. All failures degrade to a state with no heart rate; none of them
 * may break logging the workout.
 */
class WearExerciseTracker(context: Context) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutex = Mutex()
    private val exerciseClient by lazy { HealthServices.getClient(appContext).exerciseClient }

    private var accumulator = HeartRateAccumulator()
    private var calories: Int? = null
    private var active = false

    private val _state = MutableStateFlow(WearHealthState())
    val state: StateFlow<WearHealthState> = _state.asStateFlow()

    private val callback = object : ExerciseUpdateCallback {
        override fun onRegistered() = Unit

        override fun onRegistrationFailed(throwable: Throwable) {
            publish(WearHealthStatus.Unavailable)
        }

        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            update.latestMetrics.getData(DataType.HEART_RATE_BPM).forEach { accumulator.add(it.value) }
            update.latestMetrics.getData(DataType.CALORIES_TOTAL)?.total?.let { total ->
                if (total.isFinite() && total >= 0.0) calories = total.toInt()
            }
            if (!active) return
            if (update.exerciseStateInfo.state.isEnded) {
                // Ended from outside (another app took the exercise, Health Services stopped
                // it): keep the samples collected so far, drop the keep-alive, show "off".
                active = false
                WearExerciseService.stop(appContext)
                publish(WearHealthStatus.Unavailable)
                return
            }
            publish(WearHealthStatus.Active)
        }

        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) = Unit

        override fun onAvailabilityChanged(dataType: androidx.health.services.client.data.DataType<*, *>, availability: Availability) = Unit
    }

    /** Average/max so far, or null when no valid sample has arrived (or tracking is off). */
    fun snapshot(): HeartRateSummary? = accumulator.summary()

    fun start() {
        scope.launch { mutex.withLock { startLocked() } }
    }

    fun stop() {
        scope.launch { mutex.withLock { stopLocked() } }
    }

    /** The user declined the permission prompt. */
    fun reportPermissionDenied() {
        if (!active) publish(WearHealthStatus.Denied)
    }

    private suspend fun startLocked() {
        if (active) return
        if (!WearHealthPermissions.hasHeartRate(appContext)) {
            publish(WearHealthStatus.Denied)
            return
        }
        accumulator = HeartRateAccumulator()
        calories = null
        publish(WearHealthStatus.Starting)
        try {
            when (exerciseOwner(exerciseClient.getCurrentExerciseInfo().exerciseTrackedStatus)) {
                ExerciseOwner.OtherApp -> {
                    publish(WearHealthStatus.Unavailable)
                    return
                }
                // A leftover session of ours (process died mid-workout): close it first.
                ExerciseOwner.ThisApp -> runCatching { exerciseClient.endExercise() }
                ExerciseOwner.Nobody -> Unit
            }
            val capabilities = exerciseClient.getCapabilities()
            val type = listOf(ExerciseType.STRENGTH_TRAINING, ExerciseType.WEIGHTLIFTING)
                .firstOrNull { it in capabilities.supportedExerciseTypes }
            val supported = type?.let { capabilities.getExerciseTypeCapabilities(it).supportedDataTypes }
            if (type == null || supported == null || DataType.HEART_RATE_BPM !in supported) {
                publish(WearHealthStatus.Unavailable)
                return
            }
            val dataTypes = buildSet {
                add(DataType.HEART_RATE_BPM)
                if (DataType.CALORIES_TOTAL in supported && WearHealthPermissions.hasActivityRecognition(appContext)) {
                    add(DataType.CALORIES_TOTAL)
                }
            }
            exerciseClient.setUpdateCallback(callback)
            exerciseClient.startExercise(
                ExerciseConfig.builder(type)
                    .setDataTypes(dataTypes)
                    .setIsAutoPauseAndResumeEnabled(false)
                    .setIsGpsEnabled(false)
                    .build()
            )
            active = true
            WearExerciseService.start(appContext)
            publish(WearHealthStatus.Active)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            runCatching { exerciseClient.clearUpdateCallback(callback) }
            active = false
            publish(WearHealthStatus.Unavailable)
        }
    }

    private suspend fun stopLocked() {
        if (active) {
            // Cleared first, so the "ended" update our own endExercise() triggers is ignored.
            active = false
            runCatching { exerciseClient.endExercise() }
            runCatching { exerciseClient.clearUpdateCallback(callback) }
        }
        WearExerciseService.stop(appContext)
        accumulator = HeartRateAccumulator()
        calories = null
        _state.value = WearHealthState()
    }

    private enum class ExerciseOwner { Nobody, ThisApp, OtherApp }

    // ExerciseTrackedStatus holds the documented values of the public
    // ExerciseInfo.exerciseTrackedStatus Int (Google's Health Services samples compare against
    // them); only the IntDef annotation class itself is library-restricted, so lint's
    // RestrictedApi is a false positive for these constants.
    @SuppressLint("RestrictedApi")
    private fun exerciseOwner(trackedStatus: Int): ExerciseOwner = when (trackedStatus) {
        ExerciseTrackedStatus.OTHER_APP_IN_PROGRESS -> ExerciseOwner.OtherApp
        ExerciseTrackedStatus.OWNED_EXERCISE_IN_PROGRESS -> ExerciseOwner.ThisApp
        else -> ExerciseOwner.Nobody
    }

    private fun publish(status: WearHealthStatus) {
        val summary = accumulator.summary()
        _state.value = WearHealthState(
            status = status,
            heartRate = accumulator.current,
            averageHeartRate = summary?.average,
            maxHeartRate = summary?.max,
            caloriesKcal = calories
        )
    }
}
