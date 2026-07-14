package com.example.gymapp.wear.sync

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import org.json.JSONArray

object WatchExerciseCatalogStorage {
    private const val PREFS_NAME = "watch_exercise_catalog"
    private const val KEY_EXERCISE_NAMES_JSON = "exercise_names_json"

    fun save(context: Context, exerciseNames: List<String>) {
        val normalized = exerciseNames
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .distinctBy { it.lowercase() }

        val encoded = JSONArray().apply {
            normalized.forEach { put(it) }
        }.toString()

        val committed = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_EXERCISE_NAMES_JSON, encoded)
            .commit()
        check(committed) { "Could not persist exercise catalog" }
    }

    fun load(context: Context): List<String> {
        val encoded = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_EXERCISE_NAMES_JSON, null)
            ?.takeIf { it.isNotBlank() }
            ?: return emptyList()

        return runCatching {
            val array = JSONArray(encoded)
            buildList {
                val unique = linkedSetOf<String>()
                for (index in 0 until array.length()) {
                    val value = array.optString(index, "").trim()
                    if (value.isNotBlank()) {
                        unique += value
                    }
                }
                addAll(unique)
            }
        }.getOrElse { emptyList() }
    }

    fun observe(context: Context): Flow<List<String>> {
        val appContext = context.applicationContext
        return callbackFlow {
            val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
                if (key == KEY_EXERCISE_NAMES_JSON) {
                    trySend(load(appContext))
                }
            }
            prefs.registerOnSharedPreferenceChangeListener(listener)
            trySend(load(appContext))
            awaitClose {
                prefs.unregisterOnSharedPreferenceChangeListener(listener)
            }
        }.distinctUntilChanged()
    }
}
