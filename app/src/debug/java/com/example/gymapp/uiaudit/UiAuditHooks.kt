package com.example.gymapp.uiaudit

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.InternalComposeUiApi
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.navigation.NavHostController
import android.view.View
import android.view.ViewGroup
import com.example.gymapp.GymApplication
import com.example.gymapp.R
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.WorkoutExerciseDraft
import com.example.gymapp.data.repository.WorkoutSetDraft
import com.example.gymapp.navigation.AppDestination
import com.example.gymapp.util.AppLanguage
import java.io.File
import java.lang.ref.WeakReference
import java.security.MessageDigest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
    private var activityRef: WeakReference<Activity>? = null

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
        },
        // Plan editor + the exercise catalog sheet, opened through the editor's own button.
        "exercise-picker" to { nav, app ->
            if (auditRepository(app, "exercise-picker") != null) {
                openTab(nav, AppDestination.Workouts)
                nav.navigate(AppDestination.AddWorkout.route) { launchSingleTop = true }
                val label = nav.context.getString(R.string.action_add_exercise)
                if (!clickLabelled(label)) Log.w(TAG, "exercise-picker: add button not found")
            }
        },
        // Starts the audit profile's active draft once (a second request just reopens it).
        "workout-active" to { nav, app ->
            val repository = auditRepository(app, "workout-active")
            if (repository != null && ensureActiveWorkout(repository)) {
                openTab(nav, AppDestination.Workouts)
                nav.navigate(AppDestination.ActiveWorkout.route) { launchSingleTop = true }
            }
        },
        // Plan editor sheets and dialogs. The two list-backed ones need a drafted plan, built by the editor's own
        // "Repeat last workout" button (the only local-profile data they touch is the in-memory/retained draft).
        "workout-templates" to { nav, app ->
            if (auditRepository(app, "workout-templates") != null) {
                openPlanEditor(nav)
                if (openPlanOptions(nav, "workout-templates")) {
                    step("workout-templates", "copy-previous button", string(nav, R.string.action_copy_workout_day))
                }
            }
        },
        "workout-smart-alternatives" to { nav, app ->
            if (auditRepository(app, "workout-smart-alternatives") != null && draftPlan(nav, "workout-smart-alternatives")) {
                if (step("workout-smart-alternatives", "exercise actions", formatMatcher(nav, R.string.cd_exercise_actions))) {
                    step("workout-smart-alternatives", "replace with similar", string(nav, R.string.editor_replace_with_similar))
                }
            }
        },
        "discard-plan-dialog" to { nav, app ->
            if (auditRepository(app, "discard-plan-dialog") != null && draftPlan(nav, "discard-plan-dialog")) {
                step("discard-plan-dialog", "discard draft", string(nav, R.string.workout_plan_discard_draft), scroll = true)
            }
        },
        "clear-plan-dialog" to { nav, app ->
            if (auditRepository(app, "clear-plan-dialog") != null && draftPlan(nav, "clear-plan-dialog")) {
                // "More options" is also the label of the collapsed card; wait until the drafted exercise exists so the
                // list-header menu button (not the card) is the topmost match.
                awaitNode(formatMatcher(nav, R.string.cd_exercise_actions))
                if (step("clear-plan-dialog", "plan menu", string(nav, R.string.workout_plan_exercises_more_options), topmost = true)) {
                    step("clear-plan-dialog", "clear plan", string(nav, R.string.workout_plan_clear_action))
                }
            }
        },
        // Workout detail: share sheet, and the two delete dialogs (edit mode first). Presented only, never confirmed.
        "workout-share" to { nav, app ->
            if (openLatestDetail(nav, app, "workout-share")) {
                step("workout-share", "share action", string(nav, R.string.action_share_workout))
            }
        },
        "delete-workout-dialog" to { nav, app ->
            if (openLatestDetail(nav, app, "delete-workout-dialog") &&
                step("delete-workout-dialog", "edit workout", string(nav, R.string.action_edit_workout))
            ) {
                step("delete-workout-dialog", "delete workout", formatMatcher(nav, R.string.cd_delete_workout_on))
            }
        },
        "delete-set-dialog" to { nav, app ->
            if (openLatestDetail(nav, app, "delete-set-dialog") &&
                step("delete-set-dialog", "edit workout", string(nav, R.string.action_edit_workout)) &&
                // Set rows are only composed inside an expanded exercise card; the seed's newest workout starts with Squat.
                step("delete-set-dialog", "expand exercise", { it == "Squat" })
            ) {
                // The set row's accessibility "Delete set N for X" action runs the same confirmation as long-press.
                if (!invokeCustomAction(formatMatcher(nav, R.string.cd_delete_set_named), scroll = true)) {
                    Log.w(TAG, "delete-set-dialog: delete-set action not found")
                    dumpClickables("delete-set-dialog")
                }
            }
        },
        // Active-workout overlays; all reuse the audit profile's active draft (idempotent, leaves it behind).
        "workout-active-menu" to { nav, app ->
            if (openActive(nav, app, "workout-active-menu")) {
                step("workout-active-menu", "overflow button", string(nav, R.string.active_workout_more_options), toolbar = true)
            }
        },
        "workout-adaptation" to { nav, app ->
            if (openActive(nav, app, "workout-adaptation") &&
                step("workout-adaptation", "overflow button", string(nav, R.string.active_workout_more_options), toolbar = true) &&
                step("workout-adaptation", "adapt item", string(nav, R.string.training_adapt_workout))
            ) {
                // "Too hard today" previews the change directly (rest chooser variants need extra taps).
                step("workout-adaptation", "too-hard item", string(nav, R.string.training_too_hard))
            }
        },
        "plate-calculator" to { nav, app ->
            if (openActive(nav, app, "plate-calculator")) {
                step("plate-calculator", "plates capsule", string(nav, R.string.plate_calculator_content_description))
            }
        },
        "finish-exercise-dialog" to { nav, app ->
            if (openActive(nav, app, "finish-exercise-dialog")) {
                step("finish-exercise-dialog", "save exercise", string(nav, R.string.active_workout_save_exercise))
            }
        },
        // Today's discard dialog (not the toolbar one): Today > "More workout options" > "Discard workout".
        "discard-active-workout-dialog" to { nav, app ->
            val repository = auditRepository(app, "discard-active-workout-dialog")
            if (repository != null && ensureActiveWorkout(repository)) {
                openTab(nav, AppDestination.Workouts)
                if (step("discard-active-workout-dialog", "more options", string(nav, R.string.active_workout_more_options))) {
                    step("discard-active-workout-dialog", "discard action", string(nav, R.string.active_workout_discard_action))
                }
            }
        },
        // Read-only: the summary of the newest seeded workout; nothing is finished or created.
        "workout-summary" to { nav, app ->
            val sessionId = if (auditRepository(app, "workout-summary") != null) {
                latestSessionId(app)
            } else {
                null
            }
            if (sessionId == null) {
                Log.w(TAG, "workout-summary: no workout available")
            } else {
                openTab(nav, AppDestination.Workouts)
                nav.navigate(AppDestination.postWorkoutSummaryRoute(sessionId))
            }
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
        activityRef = WeakReference(activity)
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

    /** The repository of the "UI Audit" local profile, or null (logged) for any other session. */
    private fun auditRepository(app: GymApplication, route: String): GymRepository? {
        val session = app.cloudAuthManager.authState.value.session
        if (session is AccountSession.Local && session.displayName == AUDIT_PROFILE_NAME) {
            return app.repositoryFor(session)
        }
        Log.w(TAG, "$route: only available in the \"$AUDIT_PROFILE_NAME\" local profile")
        return null
    }

    private fun string(nav: NavHostController, id: Int): (String) -> Boolean {
        val label = nav.context.getString(id)
        return { it == label }
    }

    /** Matches a localized format string (e.g. "Delete set %1$d for %2$s") against any argument values. */
    private fun formatMatcher(nav: NavHostController, id: Int): (String) -> Boolean {
        val regex = Regex(
            nav.context.getString(id).split(Regex("%\\d*\\$?[sd]")).joinToString(".*") { Regex.escape(it) },
            RegexOption.DOT_MATCHES_ALL
        )
        return { regex.matches(it) }
    }

    private suspend fun step(
        route: String,
        what: String,
        matcher: (String) -> Boolean,
        topmost: Boolean = false,
        scroll: Boolean = false,
        toolbar: Boolean = false
    ): Boolean {
        val ok = clickMatching(matcher, topmost, scroll, toolbar)
        if (!ok) {
            Log.w(TAG, "$route: $what not found")
            dumpClickables(route)
        }
        return ok
    }

    private fun openPlanEditor(nav: NavHostController) {
        openTab(nav, AppDestination.Workouts)
        nav.navigate(AppDestination.AddWorkout.route) { launchSingleTop = true }
    }

    /** Plan editor with a drafted plan, filled by the editor's own "Repeat last workout" button. */
    private suspend fun draftPlan(nav: NavHostController, route: String): Boolean {
        openPlanEditor(nav)
        return openPlanOptions(nav, route) &&
            step(route, "repeat-last button", string(nav, R.string.action_repeat_last_workout))
    }

    /** The template/repeat buttons live inside the collapsed "More options" card. */
    private suspend fun openPlanOptions(nav: NavHostController, route: String): Boolean =
        step(route, "more options card", string(nav, R.string.workout_plan_more_options))

    private suspend fun openLatestDetail(nav: NavHostController, app: GymApplication, route: String): Boolean {
        if (auditRepository(app, route) == null) return false
        val sessionId = latestSessionId(app)
        if (sessionId == null) {
            Log.w(TAG, "$route: no workout available")
            return false
        }
        openTab(nav, AppDestination.Workouts)
        nav.navigate(AppDestination.workoutDetailRoute(sessionId))
        return true
    }

    private suspend fun openActive(nav: NavHostController, app: GymApplication, route: String): Boolean {
        val repository = auditRepository(app, route)
        if (repository == null || !ensureActiveWorkout(repository)) return false
        openTab(nav, AppDestination.Workouts)
        nav.navigate(AppDestination.ActiveWorkout.route) { launchSingleTop = true }
        return true
    }

    /**
     * True when an active draft exists afterwards; starts one only if none exists. Like iOS, the draft is a
     * copy of the newest seeded workout's exercises and sets (nothing completed).
     */
    private suspend fun ensureActiveWorkout(repository: GymRepository): Boolean {
        if (repository.getActiveWorkoutSnapshot() != null) return true
        val template = repository.getLatestWorkoutTemplate()
        var drafts = template?.workoutExercises
            ?.filter { it.sets.isNotEmpty() }
            ?.map { item ->
                WorkoutExerciseDraft(
                    exerciseId = item.workoutExercise.exerciseId,
                    sets = item.sets.sortedBy { it.orderIndex }.map { WorkoutSetDraft(weight = it.weight, reps = it.reps) }
                )
            }
            .orEmpty()
        if (drafts.isEmpty()) {
            val catalog = repository.observeExercises().first()
            val preferred = listOf("Bench Press", "Barbell Row", "Dips")
                .mapNotNull { name -> catalog.firstOrNull { it.name == name } }
            val picked = preferred.ifEmpty { catalog.take(3) }
            if (picked.isEmpty()) {
                Log.w(TAG, "workout-active: no exercises available")
                return false
            }
            drafts = picked.mapIndexed { index, exercise ->
                WorkoutExerciseDraft(
                    exerciseId = exercise.id,
                    sets = List(3) { WorkoutSetDraft(weight = 60.0 + 10.0 * index, reps = 10 - index) }
                )
            }
        }
        repository.startActiveWorkout(
            date = System.currentTimeMillis(),
            note = null,
            workoutExercises = drafts
        )
        return repository.getActiveWorkoutSnapshot() != null
    }

    /** Clicks the first clickable semantics node whose text/description equals [label]. */
    private suspend fun clickLabelled(label: String): Boolean = clickMatching({ it == label })

    /**
     * Clicks the first clickable node (popups and dialogs first) whose text/description satisfies [matches].
     * [topmost] picks the match highest on screen (e.g. the toolbar button over a same-named card button);
     * [scroll] scrolls the first scrollable list down between retries for controls that are not composed yet.
     */
    @OptIn(InternalComposeUiApi::class)
    private suspend fun clickMatching(
        matches: (String) -> Boolean,
        topmost: Boolean = false,
        scroll: Boolean = false,
        toolbar: Boolean = false
    ): Boolean {
        repeat(30) { attempt ->
            val clicked = withContext(Dispatchers.Main) {
                composeRoots().any { root ->
                    val rootHeight = (root as View).height
                    val nodes = findNodes(root.semanticsOwner.rootSemanticsNode) { candidate ->
                        candidate.config.getOrNull(SemanticsActions.OnClick) != null &&
                            labelsOf(candidate).any(matches) &&
                            // The toolbar overflow is the only visible same-named button in the top band (off-screen lazy
                            // items report a clamped bounds top of 0, so use the unclamped position).
                            (!toolbar || candidate.positionInRoot.y.let { it > 0f && it < rootHeight * 0.12f })
                    }
                    val node = if (topmost) nodes.minByOrNull { it.boundsInRoot.top } else nodes.firstOrNull()
                    val action = node?.config?.getOrNull(SemanticsActions.OnClick)?.action
                    action != null && action()
                }
            }
            if (clicked) return true
            if (scroll && attempt >= 4 && attempt % 2 == 0) scrollDown()
            delay(200)
        }
        return false
    }

    /** Diagnostics for a failed lookup: labels of clickable nodes and custom actions per window (no user data). */
    @OptIn(InternalComposeUiApi::class)
    private suspend fun dumpClickables(route: String) = withContext(Dispatchers.Main) {
        composeRoots().forEachIndexed { index, root ->
            val rows = findNodes(root.semanticsOwner.rootSemanticsNode) {
                it.config.getOrNull(SemanticsActions.OnClick) != null ||
                    it.config.getOrNull(SemanticsActions.CustomActions) != null
            }.take(40).joinToString(" | ") { node ->
                val actions = node.config.getOrNull(SemanticsActions.CustomActions).orEmpty().map { it.label }
                "${labelsOf(node).firstOrNull()?.take(24)}@${node.boundsInRoot.top.toInt()}" +
                    (if (actions.isEmpty()) "" else "+$actions")
            }
            Log.w(TAG, "$route: window#$index $rows")
        }
    }

    /** Waits (max ~6s) until any semantics node in any window has a label satisfying [matches]. */
    @OptIn(InternalComposeUiApi::class)
    private suspend fun awaitNode(matches: (String) -> Boolean): Boolean {
        repeat(30) {
            val found = withContext(Dispatchers.Main) {
                composeRoots().any { root ->
                    findNodes(root.semanticsOwner.rootSemanticsNode) { labelsOf(it).any(matches) }.isNotEmpty()
                }
            }
            if (found) return true
            delay(200)
        }
        return false
    }

    /** Runs the first accessibility custom action whose label satisfies [matches]. */
    @OptIn(InternalComposeUiApi::class)
    private suspend fun invokeCustomAction(matches: (String) -> Boolean, scroll: Boolean = false): Boolean {
        repeat(30) { attempt ->
            val done = withContext(Dispatchers.Main) {
                composeRoots().any { root ->
                    val action = findNodes(root.semanticsOwner.rootSemanticsNode) { candidate ->
                        candidate.config.getOrNull(SemanticsActions.CustomActions)
                            .orEmpty().any { matches(it.label) }
                    }.firstOrNull()?.config?.getOrNull(SemanticsActions.CustomActions)
                        .orEmpty().firstOrNull { matches(it.label) }
                    action != null && action.action()
                }
            }
            if (done) return true
            if (scroll && attempt >= 4 && attempt % 2 == 0) scrollDown()
            delay(200)
        }
        return false
    }

    @OptIn(InternalComposeUiApi::class)
    private suspend fun scrollDown() {
        withContext(Dispatchers.Main) {
            val activity = activityRef?.get() ?: return@withContext
            val root = findComposeRoot(activity.window.decorView) ?: return@withContext
            val list = findNodes(root.semanticsOwner.rootSemanticsNode) {
                it.config.getOrNull(SemanticsActions.ScrollBy) != null
            }.firstOrNull()
            list?.config?.getOrNull(SemanticsActions.ScrollBy)?.action?.invoke(0f, 700f)
        }
    }

    private fun labelsOf(node: SemanticsNode): List<String> =
        node.config.getOrNull(SemanticsProperties.Text).orEmpty().map { it.text } +
            node.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty()

    private fun findNodes(node: SemanticsNode, predicate: (SemanticsNode) -> Boolean): List<SemanticsNode> =
        (if (predicate(node)) listOf(node) else emptyList()) +
            node.children.flatMap { findNodes(it, predicate) }

    /**
     * Compose roots of every window of this process, topmost first: dropdown menus and dialogs live in their own
     * windows, outside the activity's decor view. Falls back to the activity window if the window list is unreadable.
     */
    @OptIn(InternalComposeUiApi::class)
    private fun composeRoots(): List<ViewRootForTest> {
        val activity = activityRef?.get() ?: return emptyList()
        val views = LinkedHashSet<View>()
        views.addAll(windowRootViews())
        views.add(activity.window.decorView)
        return views.mapNotNull { findComposeRoot(it) }
    }

    @Suppress("UNCHECKED_CAST")
    private fun windowRootViews(): List<View> = runCatching {
        val global = Class.forName("android.view.WindowManagerGlobal")
        val instance = global.getMethod("getInstance").invoke(null)
        val field = global.getDeclaredField("mViews").apply { isAccessible = true }
        (field.get(instance) as List<View>).toList().asReversed()
    }.onFailure { Log.w(TAG, "window list unavailable: ${it.javaClass.simpleName}") }
        .getOrDefault(emptyList())

    @OptIn(InternalComposeUiApi::class)
    private fun findComposeRoot(view: View): ViewRootForTest? {
        if (view is ViewRootForTest) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findComposeRoot(view.getChildAt(i))?.let { return it }
            }
        }
        return null
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
