package com.example.gymapp.garmin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.IntentCompat
import com.example.gymapp.GymApplication
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class GarminDebugReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        debugScope.launch {
            try {
                val app = context.applicationContext as GymApplication
                val exercise = intent.getStringExtra("exercise")
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: "Bench Press"
                val weight = IntentCompat.getSerializableExtra(
                    intent,
                    "weight",
                    Number::class.java
                )?.toDouble() ?: 50.0
                val reps = IntentCompat.getSerializableExtra(
                    intent,
                    "reps",
                    Number::class.java
                )?.toInt() ?: 10
                Log.i(TAG, "Debug Garmin sync started exercise=$exercise weight=$weight reps=$reps")
                val result = runCatching {
                    app.garminSyncManager.cacheAndPushPlan(
                        sets = listOf(NamedWorkoutSetDraft(exercise, weight, reps)),
                        exerciseCatalog = listOf(exercise)
                    )
                }.getOrDefault(false)
                Log.i(
                    TAG,
                    "Debug Garmin sync result=$result status=${app.garminSyncManager.lastPlanSyncStatus}"
                )
            } finally {
                pendingResult.finish()
            }
        }
    }

    private companion object {
        const val TAG = "GarminDebug"
        val debugScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    }
}
