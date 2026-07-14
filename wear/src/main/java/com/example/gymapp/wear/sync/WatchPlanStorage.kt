package com.example.gymapp.wear.sync

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged

object WatchPlanStorage {
    private const val PREFS_NAME = "watch_plan_sync"
    private const val KEY_PLAN_JSON = "workout_plan_json"

    fun save(context: Context, rawJson: String) {
        val committed = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PLAN_JSON, rawJson)
            .commit()
        check(committed) { "Could not persist workout plan" }
    }

    fun load(context: Context): String? {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_PLAN_JSON, null)
            ?.takeIf { it.isNotBlank() }
    }

    fun observe(context: Context): Flow<String?> = callbackFlow {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, changedKey ->
            if (changedKey == KEY_PLAN_JSON) {
                trySend(prefs.getString(KEY_PLAN_JSON, null)?.takeIf { it.isNotBlank() })
            }
        }

        prefs.registerOnSharedPreferenceChangeListener(listener)
        trySend(prefs.getString(KEY_PLAN_JSON, null)?.takeIf { it.isNotBlank() })
        awaitClose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }.distinctUntilChanged()

    fun clear(context: Context) {
        val committed = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_PLAN_JSON)
            .commit()
        check(committed) { "Could not clear workout plan" }
    }
}
