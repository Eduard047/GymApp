package com.example.gymapp.uiaudit

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.navigation.NavHostController
import com.example.gymapp.GymApplication
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.navigation.AppDestination
import com.example.gymapp.util.AppLanguage
import java.io.File
import java.security.MessageDigest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Debug-only UI-audit capture hooks, driven by string extras on the launch intent of the
 * (already exported) launcher activity. Nothing here is reachable in release or qa builds,
 * which carry a no-op stub of the same name.
 *
 * Extras: `uiAuditSeed` (backup JSON inside the app's private files dir), `uiAuditRoute`
 * (screen_id), `uiAuditLanguage` (en|ru|uk). Any extra present also suppresses the intro
 * splash and the first-run tutorial for that launch. Invalid values are logged and ignored.
 */
object UiAuditHooks {
    const val EXTRA_SEED = "uiAuditSeed"
    const val EXTRA_ROUTE = "uiAuditRoute"
    const val EXTRA_LANGUAGE = "uiAuditLanguage"

    private const val TAG = "UiAudit"
    private const val AUDIT_PROFILE_NAME = "UI Audit"
    private const val PREFS = "ui_audit_debug"
    private const val KEY_SEED_HASH = "seed_sha256"

    @Volatile
    var isActive: Boolean = false
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val seedMutex = Mutex()
    private val request = MutableStateFlow<RouteRequest?>(null)

    private class RouteRequest(val screenId: String, val seedReady: Job?)

    /** Small router keyed by screen_id; step 2 adds sheet/dialog entries here. */
    private val routes: Map<String, suspend (NavHostController, GymApplication) -> Unit> = mapOf(
        "today" to { nav, _ -> openTab(nav, AppDestination.Workouts) },
        "exercises" to { nav, _ -> openTab(nav, AppDestination.Exercises) },
        "progress-overview" to { nav, _ -> openTab(nav, AppDestination.Progress) },
        // Local profiles only ever show the Settings section on the Profile tab.
        "profile" to { nav, _ -> openTab(nav, AppDestination.Profile) },
        "settings" to { nav, _ -> openTab(nav, AppDestination.Profile) },
        "workout-detail" to { nav, app ->
            val sessionId = latestSessionId(app)
            if (sessionId == null) {
                Log.w(TAG, "workout-detail: no workout available")
            } else {
                openTab(nav, AppDestination.Workouts)
                nav.navigate(AppDestination.workoutDetailRoute(sessionId))
            }
        },
        "workout-plan" to { nav, _ ->
            openTab(nav, AppDestination.Workouts)
            nav.navigate(AppDestination.AddWorkout.route) { launchSingleTop = true }
        }
    )

    fun handleIntent(activity: AppCompatActivity, intent: Intent?) {
        val present = runCatching {
            intent != null && (
                intent.hasExtra(EXTRA_SEED) || intent.hasExtra(EXTRA_ROUTE) ||
                    intent.hasExtra(EXTRA_LANGUAGE)
                )
        }.getOrDefault(false)
        isActive = present
        if (!present || intent == null) return
        val seed = runCatching { intent.getStringExtra(EXTRA_SEED) }.getOrNull()
        val route = runCatching { intent.getStringExtra(EXTRA_ROUTE) }.getOrNull()
        val language = runCatching { intent.getStringExtra(EXTRA_LANGUAGE) }.getOrNull()
        val app = activity.application as GymApplication

        language?.let { applyLanguage(app, it) }
        val seedJob = seed?.let { startSeed(app, it) }
        route?.let { screenId ->
            if (screenId in routes) {
                request.value = RouteRequest(screenId, seedJob)
            } else {
                Log.w(TAG, "Unknown $EXTRA_ROUTE value; supported: ${routes.keys}")
            }
        }
    }

    @Composable
    fun RouteEffect(navController: NavHostController) {
        val pending by request.collectAsState()
        val current = pending ?: return
        LaunchedEffect(navController, current) {
            try {
                current.seedReady?.join()
                // Wait until the NavHost graph exists (it is absent while signed out).
                navController.currentBackStackEntryFlow.first()
                val app = navController.context.applicationContext as GymApplication
                requireNotNull(routes[current.screenId]).invoke(navController, app)
                request.compareAndSet(current, null)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Log.w(TAG, "Route ${current.screenId} failed: ${error.javaClass.simpleName}")
                request.compareAndSet(current, null)
            }
        }
    }

    private fun openTab(nav: NavHostController, destination: AppDestination) {
        nav.navigate(destination.route) {
            popUpTo(nav.graph.startDestinationId) { saveState = false }
            launchSingleTop = true
            restoreState = false
        }
    }

    private suspend fun latestSessionId(app: GymApplication): Long? {
        val session = app.cloudAuthManager.authState.value.session ?: return null
        return app.repositoryFor(session).observeSessions().first()
            .maxByOrNull { it.session.date }?.session?.id
    }

    private fun applyLanguage(app: GymApplication, tag: String) {
        val language = AppLanguage.fromTag(tag.trim().lowercase())
        if (language == null) {
            Log.w(TAG, "Invalid $EXTRA_LANGUAGE value; expected en|ru|uk")
            return
        }
        // Persists to the debug app's own gym_settings so the in-app selector stays consistent.
        runCatching {
            if (app.languageManager.currentLanguage() != language) {
                app.languageManager.setLanguage(language)
            }
        }.onFailure { Log.w(TAG, "Language switch failed: ${it.javaClass.simpleName}") }
    }

    /** Opens the audit profile synchronously (before first composition), imports in background. */
    private fun startSeed(app: GymApplication, seedPath: String): Job? {
        val file = resolveSeedFile(app, seedPath)
        if (file == null) {
            Log.w(TAG, "Invalid $EXTRA_SEED: must be a file inside the app's private files dir")
            return null
        }
        val auth = app.cloudAuthManager
        when (val session = auth.authState.value.session) {
            null -> {
                val opened = runCatching {
                    val saved = auth.savedLocalProfiles()
                        .firstOrNull { it.displayName == AUDIT_PROFILE_NAME }
                    if (saved != null) {
                        auth.setLocal(saved.id, resumeExisting = true)
                    } else {
                        auth.setLocal(AUDIT_PROFILE_NAME)
                    }
                }
                if (opened.isFailure) {
                    Log.w(TAG, "Audit profile unavailable: ${opened.exceptionOrNull()?.javaClass?.simpleName}")
                    return null
                }
            }
            is AccountSession.Local -> if (session.displayName != AUDIT_PROFILE_NAME) {
                Log.w(TAG, "Active local profile is not the audit profile; seed skipped")
                return null
            }
            is AccountSession.Cloud -> {
                Log.w(TAG, "Cloud account active; seed skipped")
                return null
            }
        }
        return scope.launch {
            runCatching { importSeed(app, file) }
                .onFailure {
                    if (it is CancellationException) throw it
                    Log.w(TAG, "Seed import failed: ${it.javaClass.simpleName}")
                }
        }
    }

    private suspend fun importSeed(app: GymApplication, file: File) = seedMutex.withLock {
        val session = app.cloudAuthManager.authState.value.session as? AccountSession.Local
            ?: return@withLock
        require(session.displayName == AUDIT_PROFILE_NAME)
        require(file.length() in 1..WorkoutDataLimits.MAX_BACKUP_BYTES.toLong())
        val bytes = file.readBytes()
        val hash = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val repository = app.repositoryFor(session)
        val hasData = repository.observeSessions().first().isNotEmpty()
        if (hasData && prefs.getString(KEY_SEED_HASH, null) == hash) {
            Log.i(TAG, "Seed unchanged; skipping import")
            return@withLock
        }
        // Different (or first) seed: replace the audit profile's data instead of appending.
        repository.clearAllAccountData()
        // Same bounds/validation as Profile > Backup > Import.
        val imported = repository.importBackupJson(
            rawJson = bytes.toString(Charsets.UTF_8),
            activeAccountId = session.displayName
        )
        prefs.edit().putString(KEY_SEED_HASH, hash).apply()
        Log.i(TAG, "Seed imported workouts=$imported")
    }

    private fun resolveSeedFile(app: GymApplication, path: String): File? = runCatching {
        val root = app.filesDir.canonicalFile
        // Absolute, relative to files/ ("seed.json"), or relative to the app data dir
        // ("files/seed.json", as seen from `run-as`). Must resolve inside files/.
        val given = File(path)
        val candidates = if (given.isAbsolute) {
            listOf(given)
        } else {
            listOf(File(root, path), File(root.parentFile, path))
        }
        candidates.map { it.canonicalFile }.firstOrNull {
            it.isFile && it.path.startsWith(root.path + File.separator)
        }
    }.getOrNull()
}
