package com.example.gymapp.service

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.example.gymapp.MainActivity
import com.example.gymapp.R
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ActiveWorkoutDetails
import com.example.gymapp.data.repository.LiveWorkoutSidecarStore
import com.example.gymapp.data.repository.RecordActiveWorkoutSetResult
import com.example.gymapp.data.repository.WorkoutRecommendationEngine
import com.example.gymapp.gymApplication
import com.example.gymapp.util.restTimerAccountKey
import java.text.NumberFormat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** The workout's sets in plan order, as the notification needs them. */
internal fun ActiveWorkoutDetails.notificationExercises(): List<WorkoutNotificationExercise> =
    exercises
        .sortedBy { it.activeWorkoutExercise.orderIndex }
        .map { exercise ->
            WorkoutNotificationExercise(
                name = exercise.activeWorkoutExercise.exerciseName,
                sets = exercise.sets.sortedBy { it.orderIndex }.map { set ->
                    WorkoutNotificationSet(
                        id = set.id,
                        weight = set.weight,
                        reps = set.reps,
                        completed = set.completedAt != null
                    )
                }
            )
        }

/** Whether the running workout belongs to a live room with a friend. */
internal fun isLiveWorkout(context: Context, session: AccountSession?, details: ActiveWorkoutDetails): Boolean {
    val cloud = session as? AccountSession.Cloud ?: return false
    val binding = runCatching { LiveWorkoutSidecarStore(context).load(cloud) }.getOrNull() ?: return false
    return binding.workoutStartedAt == details.activeWorkout.startedAt && !binding.localFinished
}

/**
 * Posts and clears the ongoing "active workout" notification. It stays while a workout is
 * running and is cleared when the workout is finished or discarded.
 */
internal object ActiveWorkoutNotifier {
    private const val CHANNEL_ID = "active_workout"
    private const val NOTIFICATION_ID = 4020
    private const val REQUEST_OPEN_APP = 4021
    private const val REQUEST_LOG_SET = 4022
    private const val REQUEST_SKIP_REST = 4023

    internal const val ACTION_LOG_SET = "com.setforge.gymapp.action.ACTIVE_WORKOUT_LOG_SET"
    internal const val ACTION_SKIP_REST = "com.setforge.gymapp.action.ACTIVE_WORKOUT_SKIP_REST"
    internal const val EXTRA_SESSION_STARTED_AT = "extra_session_started_at"
    internal const val EXTRA_REVISION = "extra_revision"
    internal const val EXTRA_SET_ID = "extra_set_id"
    internal const val EXTRA_REST_ENDS_AT = "extra_rest_ends_at"

    fun show(context: Context, content: ActiveWorkoutNotificationContent) {
        if (!canPost(context)) return
        ensureChannel(context)
        runCatching {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, build(context, content))
        }
    }

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    private fun build(context: Context, content: ActiveWorkoutNotificationContent): Notification {
        val locale = context.resources.configuration.locales[0]
        val numberFormat = NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 2 }
        val title = content.exerciseName
            ?.let { BuiltInExerciseCatalog.displayName(it, locale.language) }
            ?: context.getString(R.string.active_workout_notification_title)
        val progress = context.getString(
            R.string.active_workout_notification_progress,
            content.completedSets,
            content.totalSets
        )
        val restEndsAt = content.restEndsAt
        val text = when {
            restEndsAt != null -> context.getString(R.string.active_workout_notification_resting)
            content.nextWeight != null && content.nextReps != null -> context.getString(
                R.string.active_workout_notification_next,
                numberFormat.format(content.nextWeight),
                content.nextReps
            )
            else -> context.getString(R.string.active_workout_notification_all_done)
        }
        val subText = if (content.setNumber > 0) {
            context.getString(R.string.active_workout_notification_set, content.setNumber, content.setCount) +
                " · " + progress
        } else {
            progress
        }
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(text)
            .setSubText(subText)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(ContextCompat.getColor(context, R.color.active_workout_notification))
            .setColorized(true)
            .setProgress(content.totalSets.coerceAtLeast(1), content.completedSets, false)
            .setContentIntent(openAppIntent(context))
        if (restEndsAt != null) {
            builder.setWhen(restEndsAt)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setChronometerCountDown(true)
        } else {
            builder.setShowWhen(false)
        }
        val nextSetId = content.nextSetId
        if (content.canLogSet && nextSetId != null) {
            builder.addAction(
                android.R.drawable.ic_input_add,
                context.getString(R.string.active_workout_notification_log_set),
                logSetIntent(context, content, nextSetId)
            )
        }
        if (restEndsAt != null) {
            builder.addAction(
                android.R.drawable.ic_media_next,
                context.getString(R.string.active_workout_notification_skip_rest),
                skipRestIntent(context, content, restEndsAt)
            )
        }
        return builder.build()
    }

    private fun openAppIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        REQUEST_OPEN_APP,
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun logSetIntent(
        context: Context,
        content: ActiveWorkoutNotificationContent,
        setId: String
    ): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_LOG_SET,
        Intent(context, ActiveWorkoutNotificationReceiver::class.java).apply {
            action = ACTION_LOG_SET
            putExtra(EXTRA_SESSION_STARTED_AT, content.sessionStartedAt)
            putExtra(EXTRA_REVISION, content.revision)
            putExtra(EXTRA_SET_ID, setId)
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun skipRestIntent(
        context: Context,
        content: ActiveWorkoutNotificationContent,
        restEndsAt: Long
    ): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_SKIP_REST,
        Intent(context, ActiveWorkoutNotificationReceiver::class.java).apply {
            action = ACTION_SKIP_REST
            putExtra(EXTRA_SESSION_STARTED_AT, content.sessionStartedAt)
            putExtra(EXTRA_REST_ENDS_AT, restEndsAt)
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.active_workout_notification_channel_name),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = context.getString(R.string.active_workout_notification_channel_description)
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
        )
    }

    private fun canPost(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
}

/**
 * Handles the notification's Log set and Skip rest buttons without opening the app. Log set
 * records exactly the set the notification showed, at its planned weight and reps, through the
 * same revision-checked repository call as the in-app button, so a repeated or stale tap records
 * nothing. Skip rest only ends the rest it was shown for and never records a set.
 */
class ActiveWorkoutNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != ActiveWorkoutNotifier.ACTION_LOG_SET && action != ActiveWorkoutNotifier.ACTION_SKIP_REST) return
        val pending = goAsync()
        val appContext = context.applicationContext
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            try {
                handle(appContext, action, intent)
            } catch (_: Exception) {
                // A failed tap leaves the workout unchanged; the app shows the current state.
            } finally {
                pending.finish()
            }
        }
    }

    private suspend fun handle(context: Context, action: String, intent: Intent) {
        val app = context.gymApplication
        val session = app.cloudAuthManager.authState.value.session ?: return
        val accountKey = restTimerAccountKey(session) ?: return
        val repository = app.repositoryFor(session)
        val details = repository.getActiveWorkoutSnapshot() ?: run {
            ActiveWorkoutNotifier.cancel(context)
            return
        }
        val startedAt = intent.getLongExtra(ActiveWorkoutNotifier.EXTRA_SESSION_STARTED_AT, -1L)
        if (details.activeWorkout.startedAt != startedAt) return
        val timer = app.restTimerController
        when (action) {
            ActiveWorkoutNotifier.ACTION_LOG_SET -> {
                if (isLiveWorkout(context, session, details)) return
                val setId = intent.getStringExtra(ActiveWorkoutNotifier.EXTRA_SET_ID) ?: return
                val revision = intent.getLongExtra(ActiveWorkoutNotifier.EXTRA_REVISION, -1L)
                if (details.activeWorkout.revision != revision) return
                val exercise = details.exercises.firstOrNull { block -> block.sets.any { it.id == setId } } ?: return
                val set = exercise.sets.first { it.id == setId }
                if (set.completedAt != null) return
                val result = repository.recordActiveWorkoutSet(
                    setId = setId,
                    expectedRevision = revision,
                    weight = set.weight,
                    reps = set.reps
                )
                if (result is RecordActiveWorkoutSetResult.Recorded) {
                    timer.startActiveWorkoutRest(
                        accountKey = accountKey,
                        sessionStartedAt = startedAt,
                        seconds = WorkoutRecommendationEngine.recommendedRestSeconds(
                            exercise.activeWorkoutExercise.exerciseName
                        )
                    )
                }
            }
            ActiveWorkoutNotifier.ACTION_SKIP_REST -> {
                val restEndsAt = intent.getLongExtra(ActiveWorkoutNotifier.EXTRA_REST_ENDS_AT, -1L)
                val snapshot = timer.activeWorkoutTimerSnapshot.value
                if (snapshot?.accountKey != accountKey || snapshot.sessionStartedAt != startedAt ||
                    snapshot.restEndsAt != restEndsAt
                ) return
                timer.stopActiveWorkoutRest(accountKey, startedAt)
            }
        }
        // Refresh right away in case no app screen is observing the workout.
        val updated = repository.getActiveWorkoutSnapshot() ?: return
        ActiveWorkoutNotifier.show(
            context,
            activeWorkoutNotificationContent(
                sessionStartedAt = updated.activeWorkout.startedAt,
                revision = updated.activeWorkout.revision,
                exercises = updated.notificationExercises(),
                restEndsAt = timer.activeWorkoutTimerSnapshot.value
                    ?.takeIf { it.accountKey == accountKey && it.sessionStartedAt == updated.activeWorkout.startedAt }
                    ?.restEndsAt,
                nowMillis = System.currentTimeMillis(),
                isLiveWorkout = isLiveWorkout(context, session, updated)
            )
        )
    }
}
