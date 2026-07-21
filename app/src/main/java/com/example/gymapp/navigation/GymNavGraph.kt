package com.example.gymapp.navigation

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Language
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.example.gymapp.R
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAuthManager
import com.example.gymapp.auth.authErrorText
import com.example.gymapp.auth.databaseName
import com.example.gymapp.auth.LeaderboardRow
import com.example.gymapp.data.repository.BackupOwner
import com.example.gymapp.data.repository.canonicalWorkoutPayloadDigest
import com.example.gymapp.gymApplication
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.ui.screens.AddWorkoutScreen
import com.example.gymapp.ui.screens.AppIntroSplash
import com.example.gymapp.ui.screens.AuthScreen
import com.example.gymapp.ui.screens.ExerciseListScreen
import com.example.gymapp.ui.screens.ExerciseProgressScreen
import com.example.gymapp.ui.screens.GymBackground
import com.example.gymapp.ui.screens.MissionsScreen
import com.example.gymapp.ui.screens.ProfileScreen
import com.example.gymapp.ui.screens.RanksScreen
import com.example.gymapp.ui.screens.PostWorkoutSummaryScreen
import com.example.gymapp.ui.screens.PasswordUpdateScreen
import com.example.gymapp.ui.screens.WorkoutDetailScreen
import com.example.gymapp.ui.screens.WorkoutListScreen
import com.example.gymapp.ui.viewmodel.AddWorkoutViewModel
import com.example.gymapp.ui.viewmodel.ExerciseListViewModel
import com.example.gymapp.ui.viewmodel.ExerciseProgressViewModel
import com.example.gymapp.ui.viewmodel.PostWorkoutSummaryViewModel
import com.example.gymapp.ui.viewmodel.WorkoutDetailViewModel
import com.example.gymapp.ui.viewmodel.WorkoutListViewModel
import com.example.gymapp.sync.PhoneSyncClient
import com.example.gymapp.sync.CloudSnapshotApplyDecision
import com.example.gymapp.sync.CloudSyncBaselineStore
import com.example.gymapp.sync.cloudSnapshotApplyDecision
import com.example.gymapp.util.AppLanguage
import com.example.gymapp.util.LanguageManager
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.RestTimerController
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

internal fun shouldEnableCloudAutosave(
    pullSucceeded: Boolean,
    canonicalRoundTripSafe: Boolean,
    pulledSession: AccountSession.Cloud,
    activeSession: AccountSession?
): Boolean = pullSucceeded &&
    canonicalRoundTripSafe &&
    isSameCloudSessionGeneration(pulledSession, activeSession)

internal fun isSameCloudSessionGeneration(
    expected: AccountSession.Cloud,
    active: AccountSession?
): Boolean = active is AccountSession.Cloud &&
    active.userId == expected.userId &&
    active.sessionGeneration == expected.sessionGeneration

internal fun shouldInitializeMissingRemoteState(localProjectionEmpty: Boolean): Boolean =
    localProjectionEmpty

internal fun accountUiIsolationKey(
    session: AccountSession?,
    needsPasswordUpdate: Boolean
): String {
    val identity = when (session) {
        null -> "signed-out"
        is AccountSession.Cloud -> "cloud:${session.userId}:${session.sessionGeneration}"
        is AccountSession.Local -> "local:${session.databaseName()}"
    } + ":password-update=$needsPasswordUpdate"
    return MessageDigest.getInstance("SHA-256")
        .digest(identity.toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { byte -> "%02x".format(byte) }
}

internal fun isCanonicalAndroidCloudEnvelope(root: JSONObject, activeUserId: String): Boolean =
    runCatching {
        val requiredKeys = setOf(
            "schemaVersion",
            "exportedAt",
            "app",
            "diagnostics",
            "owner",
            "exercises",
            "sessions",
            "summary"
        )
        require(root.keySet() == requiredKeys || root.keySet() == requiredKeys + "catalogSeedVersion")
        require(root.exactIntegralNumber("schemaVersion") == 2L)
        require(root.exactIntegralNumber("exportedAt") != null)
        if (root.has("catalogSeedVersion")) {
            require(root.exactIntegralNumber("catalogSeedVersion") in 0L..1L)
        }
        require(root.opt("app") == "GymApp")
        require(root.opt("diagnostics") is Boolean)

        val owner = root.optJSONObject("owner") ?: error("Missing owner")
        require(owner.keySet().all { it in setOf("accountId", "userId", "email", "remote") })
        require(owner.opt("accountId") == activeUserId)
        require(owner.opt("userId") == activeUserId)
        require(owner.opt("remote") == true)

        val exercises = root.optJSONArray("exercises") ?: error("Missing exercises")
        require(exercises.allObjectsMatch(setOf("name", "catalogKey"), setOf("name")))

        val sessions = root.optJSONArray("sessions") ?: error("Missing sessions")
        repeat(sessions.length()) { sessionIndex ->
            val session = sessions.optJSONObject(sessionIndex) ?: error("Invalid session")
            require(session.keySet().all { it in setOf("date", "note", "exercises") })
            require(session.keySet().containsAll(setOf("date", "exercises")))
            val blocks = session.optJSONArray("exercises") ?: error("Invalid session exercises")
            repeat(blocks.length()) { blockIndex ->
                val block = blocks.optJSONObject(blockIndex) ?: error("Invalid exercise block")
                require(block.keySet().all { it in setOf("name", "catalogKey", "sets") })
                require(block.keySet().containsAll(setOf("name", "sets")))
                val sets = block.optJSONArray("sets") ?: error("Invalid exercise sets")
                require(sets.allObjectsMatch(setOf("weight", "reps"), setOf("weight", "reps")))
            }
        }

        val summary = root.optJSONObject("summary") ?: error("Missing summary")
        require(summary.keySet() == setOf("exerciseCount", "sessionCount", "setCount", "totalVolume"))
        true
    }.getOrDefault(false)

private fun JSONObject.keySet(): Set<String> = buildSet {
    val iterator = keys()
    while (iterator.hasNext()) add(iterator.next())
}

private fun JSONObject.exactIntegralNumber(key: String): Long? {
    val value = opt(key) as? Number ?: return null
    val number = value.toDouble()
    if (!number.isFinite() || number % 1.0 != 0.0) return null
    val longValue = value.toLong()
    return longValue.takeIf { it.toDouble() == number }
}

private fun JSONArray.allObjectsMatch(allowed: Set<String>, required: Set<String>): Boolean {
    repeat(length()) { index ->
        val item = optJSONObject(index) ?: return false
        val keys = item.keySet()
        if (!keys.all { it in allowed } || !keys.containsAll(required)) return false
    }
    return true
}

@OptIn(ExperimentalMaterial3Api::class, FlowPreview::class)
@Composable
fun GymAppRoot(
    repositoryProvider: (AccountSession?) -> GymRepository,
    authManager: CloudAuthManager,
    languageManager: LanguageManager,
    restTimerController: RestTimerController
) {
    val authState by authManager.authState.collectAsState()
    val uiIsolationKey = accountUiIsolationKey(
        session = authState.session,
        needsPasswordUpdate = authState.needsPasswordUpdate
    )
    // A new account generation gets a new controller and graph identity. Navigation Compose can
    // otherwise retain equal-route back-stack entries and their repository-bound ViewModelStores.
    val navController = key(uiIsolationKey) { rememberNavController() }
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val selectedLanguage by languageManager.selectedLanguage.collectAsState()
    val repository = remember(uiIsolationKey) { repositoryProvider(authState.session) }
    val coroutineScope = key(uiIsolationKey) { rememberCoroutineScope() }
    val applicationContext = LocalContext.current.applicationContext
    val cloudSyncBaselineStore = remember(applicationContext) {
        CloudSyncBaselineStore(applicationContext)
    }
    var showIntro by rememberSaveable { mutableStateOf(true) }
    var cloudPullGeneration by key(uiIsolationKey) {
        remember { mutableStateOf<String?>(null) }
    }

    LaunchedEffect(Unit) {
        delay(1400)
        showIntro = false
    }

    val isBottomTabRoute = AppDestination.bottomTabs.any { it.route == currentRoute }
    val hasInContentRootHeader = currentRoute == AppDestination.Workouts.route ||
        currentRoute == AppDestination.Exercises.route
    val cloudSession = (authState.session as? AccountSession.Cloud)
        ?.takeUnless { authState.needsPasswordUpdate }

    LaunchedEffect(uiIsolationKey) {
        if (authState.session is AccountSession.Local) {
            repository.seedBuiltInExercises()
            repository.seedDefaultExerciseMuscleMappings()
        }
    }

    LaunchedEffect(cloudSession?.sessionGeneration) {
        val session = cloudSession ?: return@LaunchedEffect
        cloudPullGeneration = null
        val pullResult = runCatching {
            val remoteState = authManager.loadRemoteState(session)
            if (remoteState != null && remoteState.length() > 0) {
                val isAuthoritativeCanonical = withContext(Dispatchers.Default) {
                    isCanonicalAndroidCloudEnvelope(remoteState, session.userId)
                }
                if (!isAuthoritativeCanonical) {
                    // Legacy cross-client rows remain readable, but they are never allowed to
                    // delete local data or arm an automatic write-back.
                    repository.importBackupJsonObject(
                        remoteState,
                        activeUserId = session.userId,
                        activeRemote = true
                    )
                    false
                } else {
                    val remoteDigest = withContext(Dispatchers.Default) {
                        canonicalWorkoutPayloadDigest(remoteState)
                    }
                    val localState = repository.getCloudWorkoutProjectionState()
                    when (cloudSnapshotApplyDecision(
                        localDigest = localState.digest,
                        remoteDigest = remoteDigest,
                        lastSyncedDigest = cloudSyncBaselineStore.read(session.userId),
                        localProjectionEmpty = localState.isEmpty
                    )) {
                        CloudSnapshotApplyDecision.Conflict -> false

                        CloudSnapshotApplyDecision.AlreadyCurrent -> {
                            check(isSameCloudSessionGeneration(
                                session,
                                authManager.authState.value.session
                            )) { "Cloud account changed while confirming the sync baseline." }
                            check(cloudSyncBaselineStore.write(session.userId, checkNotNull(remoteDigest))) {
                                "Could not persist the cloud sync baseline. Automatic upload is paused."
                            }
                            check(isSameCloudSessionGeneration(
                                session,
                                authManager.authState.value.session
                            )) { "Cloud account changed while confirming the sync baseline." }
                            true
                        }

                        CloudSnapshotApplyDecision.ReplaceAuthoritatively -> {
                            repository.replaceWithBackupJsonObject(
                                root = remoteState,
                                expectedLocalState = localState,
                                activeUserId = session.userId,
                                activeRemote = true
                            )
                            val replacedState = repository.getCloudWorkoutProjectionState()
                            check(replacedState.digest == remoteDigest) {
                                "Cloud state did not round-trip safely. Automatic upload is paused."
                            }
                            check(isSameCloudSessionGeneration(
                                session,
                                authManager.authState.value.session
                            )) { "Cloud account changed while confirming the sync baseline." }
                            check(cloudSyncBaselineStore.write(session.userId, replacedState.digest)) {
                                "Could not persist the cloud sync baseline. Automatic upload is paused."
                            }
                            check(isSameCloudSessionGeneration(
                                session,
                                authManager.authState.value.session
                            )) { "Cloud account changed while confirming the sync baseline." }
                            true
                        }
                    }
                }
            } else {
                // Missing remote state may initialize only a genuinely empty account database.
                // A non-empty projection could be stale data from a deleted remote row.
                shouldInitializeMissingRemoteState(
                    repository.getCloudWorkoutProjectionState().isEmpty
                )
            }
        }
        pullResult.onFailure { throwable ->
            if (throwable is CancellationException) throw throwable
            authManager.setMessage(
                authErrorText(throwable, R.string.cloud_sync_load_failed)
            )
        }
        pullResult.onSuccess { canonicalRoundTripSafe ->
            // A successful authoritative pull may have replaced the local rows. Re-apply the
            // public built-in catalog before autosave starts so every account gets the same list.
            repository.seedBuiltInExercises()
            repository.seedDefaultExerciseMuscleMappings()
            if (!canonicalRoundTripSafe) {
                authManager.setMessage(
                    LocalizedText(R.string.cloud_sync_conflict)
                )
            }
        }
        val activeSession = authManager.authState.value.session as? AccountSession.Cloud
        if (shouldEnableCloudAutosave(
                pullSucceeded = pullResult.isSuccess,
                canonicalRoundTripSafe = pullResult.getOrDefault(false),
                pulledSession = session,
                activeSession = activeSession
            )
        ) {
            cloudPullGeneration = session.sessionGeneration
        }
    }

    LaunchedEffect(cloudSession?.sessionGeneration, cloudPullGeneration) {
        val session = cloudSession ?: return@LaunchedEffect
        if (cloudPullGeneration != session.sessionGeneration) return@LaunchedEffect
        combine(
            repository.observeSessions(),
            repository.observeExercises(),
            repository.observeExerciseMuscleMappings()
        ) { sessions, exercises, mappings ->
            Triple(sessions.size, exercises.size, mappings.size)
        }
            .debounce(1_500)
            .collect {
                if (authManager.authState.value.isLoading) return@collect
                runCatching {
                    val owner = BackupOwner(
                        accountId = session.userId,
                        userId = session.userId,
                        email = session.email,
                        remote = true
                    )
                    val state = repository.buildCloudBackupJson(owner = owner)
                    val stateDigest = withContext(Dispatchers.Default) {
                        checkNotNull(canonicalWorkoutPayloadDigest(state))
                    }
                    val stats = repository.getSyncProfileStats()
                    authManager.saveRemoteState(
                        session = session,
                        state = state,
                        xp = stats.xp,
                        level = stats.level,
                        workouts = stats.workouts
                    )
                    check(isSameCloudSessionGeneration(
                        session,
                        authManager.authState.value.session
                    )) { "Cloud account changed while confirming the sync baseline." }
                    check(cloudSyncBaselineStore.write(session.userId, stateDigest)) {
                        "Could not persist the cloud sync baseline. Automatic upload is paused."
                    }
                    check(isSameCloudSessionGeneration(
                        session,
                        authManager.authState.value.session
                    )) { "Cloud account changed while confirming the sync baseline." }
                }.onFailure { throwable ->
                    if (throwable is CancellationException) throw throwable
                    cloudPullGeneration = null
                    authManager.setMessage(
                        authErrorText(throwable, R.string.cloud_sync_save_failed)
                    )
                }
            }
    }
    val titleRes = when {
        currentRoute == AppDestination.Workouts.route -> R.string.title_workouts
        currentRoute == AppDestination.Missions.route -> R.string.title_missions
        currentRoute == AppDestination.Exercises.route -> R.string.title_exercises
        currentRoute == AppDestination.Progress.route -> R.string.title_progress
        currentRoute == AppDestination.Profile.route -> R.string.title_profile
        currentRoute == AppDestination.Ranks.route -> R.string.title_ranks
        currentRoute == AppDestination.AddWorkout.route -> R.string.title_add_workout
        currentRoute?.startsWith("workout_detail/") == true -> R.string.title_workout_detail
        currentRoute?.startsWith("post_workout_summary/") == true -> R.string.title_post_workout_summary
        else -> R.string.app_name
    }
    val topAppBarScrollBehavior = TopAppBarDefaults.enterAlwaysScrollBehavior()

    key(uiIsolationKey) {
        GymBackground {
            Box(modifier = Modifier.fillMaxSize()) {
            if (authState.needsPasswordUpdate) {
                PasswordUpdateScreen(
                    uiState = authState,
                    onUpdatePassword = { password ->
                        coroutineScope.launch {
                            authManager.setLoading(true)
                            runCatching {
                                authManager.updatePassword(password)
                            }.onFailure { throwable ->
                                authManager.setMessage(
                                    authErrorText(
                                        throwable,
                                        R.string.auth_password_update_failed
                                    )
                                )
                            }
                        }
                    },
                    onCancel = authManager::logout,
                    modifier = Modifier.fillMaxSize()
                )
                return@Box
            }

            if (authState.session == null) {
                AuthScreen(
                    uiState = authState,
                    onLogin = { email, password ->
                        coroutineScope.launch {
                            authManager.setLoading(true)
                            runCatching {
                                authManager.login(email, password)
                                authManager.setMessage(null)
                            }.onFailure { throwable ->
                                authManager.setMessage(
                                    authErrorText(throwable, R.string.auth_message_login_failed)
                                )
                            }
                        }
                    },
                    onSignUp = { email, password, displayName ->
                        coroutineScope.launch {
                            authManager.setLoading(true)
                            runCatching {
                                val session = authManager.signUp(email, password, displayName)
                                if (session == null) {
                                    authManager.setMessage(
                                        LocalizedText(R.string.auth_message_account_created),
                                        isError = false
                                    )
                                    return@runCatching
                                }
                                authManager.setMessage(null)
                            }.onFailure { throwable ->
                                authManager.setMessage(
                                    authErrorText(throwable, R.string.auth_message_signup_failed)
                                )
                            }
                        }
                    },
                    onResendConfirmation = { email ->
                        coroutineScope.launch {
                            authManager.setLoading(true)
                            runCatching {
                                authManager.resendSignUpConfirmation(email)
                                authManager.setMessage(
                                    LocalizedText(R.string.auth_message_confirmation_sent),
                                    isError = false
                                )
                            }.onFailure { throwable ->
                                authManager.setMessage(
                                    authErrorText(
                                        throwable,
                                        R.string.auth_message_confirmation_failed
                                    )
                                )
                            }
                        }
                    },
                    onPasswordReset = { email ->
                        coroutineScope.launch {
                            authManager.setLoading(true)
                            runCatching {
                                authManager.requestPasswordReset(email)
                                authManager.setMessage(
                                    LocalizedText(R.string.auth_message_password_reset_sent),
                                    isError = false
                                )
                            }.onFailure { throwable ->
                                authManager.setMessage(
                                    authErrorText(
                                        throwable,
                                        R.string.auth_message_password_reset_failed
                                    )
                                )
                            }
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                )
                AnimatedVisibility(
                    visible = showIntro,
                    enter = fadeIn() + slideInVertically(initialOffsetY = { it / 8 }),
                    exit = fadeOut() + scaleOut(targetScale = 1.03f)
                ) {
                    AppIntroSplash()
                }
                return@Box
            }

            Scaffold(
                modifier = Modifier
                    .fillMaxSize()
                    .nestedScroll(topAppBarScrollBehavior.nestedScrollConnection),
                containerColor = Color.Transparent,
                contentColor = MaterialTheme.colorScheme.onBackground,
                topBar = {
                    AppTopBar(
                        titleRes = titleRes,
                        isRootDestination = isBottomTabRoute,
                        showRootTitle = !hasInContentRootHeader,
                        selectedLanguage = selectedLanguage,
                        onBack = { navController.navigateUp() },
                        onLanguageSelected = { languageManager.setLanguage(it) },
                        scrollBehavior = topAppBarScrollBehavior
                    )
                },
                bottomBar = {
                    if (isBottomTabRoute) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .navigationBarsPadding()
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                            contentAlignment = Alignment.BottomCenter
                        ) {
                            Surface(
                                color = MaterialTheme.colorScheme.surface,
                                shape = MaterialTheme.shapes.extraLarge,
                                tonalElevation = 0.dp,
                                shadowElevation = 4.dp,
                                border = BorderStroke(
                                    1.dp,
                                    MaterialTheme.colorScheme.outlineVariant.copy(
                                        alpha = 1f
                                    )
                                )
                            ) {
                                NavigationBar(
                                    modifier = Modifier.height(76.dp),
                                    containerColor = Color.Transparent,
                                    tonalElevation = 0.dp
                                ) {
                                    AppDestination.bottomTabs.forEach { tab ->
                                        NavigationBarItem(
                                            selected = currentRoute == tab.route,
                                            onClick = {
                                                navController.navigate(tab.route) {
                                                    popUpTo(navController.graph.startDestinationId) {
                                                        saveState = true
                                                    }
                                                    launchSingleTop = true
                                                    restoreState = true
                                                }
                                            },
                                            colors = NavigationBarItemDefaults.colors(
                                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                                selectedTextColor = MaterialTheme.colorScheme.primary,
                                                indicatorColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
                                                unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                                unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant
                                            ),
                                            icon = {
                                                Box(
                                                    modifier = Modifier.size(24.dp),
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    Icon(
                                                        imageVector = tab.icon,
                                                        contentDescription = stringResource(tab.labelRes),
                                                        modifier = Modifier.size(20.dp)
                                                    )
                                                }
                                            },
                                            label = {
                                                Text(
                                                    text = stringResource(tab.labelRes),
                                                    style = MaterialTheme.typography.labelSmall.copy(
                                                        fontSize = 10.sp
                                                    ),
                                                    modifier = Modifier.fillMaxWidth(),
                                                    textAlign = TextAlign.Center,
                                                    maxLines = 1,
                                                    overflow = TextOverflow.Ellipsis
                                                )
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                },
                floatingActionButton = {
                    when {
                        currentRoute?.startsWith("workout_detail/") == true -> {
                            val sessionId = navBackStackEntry?.arguments?.getLong("sessionId")
                            if (sessionId != null) {
                                ExtendedFloatingActionButton(
                                    modifier = Modifier.navigationBarsPadding(),
                                    onClick = {
                                        navController.navigate(AppDestination.postWorkoutSummaryRoute(sessionId)) {
                                            launchSingleTop = true
                                        }
                                    },
                                    containerColor = MaterialTheme.colorScheme.tertiary,
                                    contentColor = MaterialTheme.colorScheme.onTertiary,
                                    expanded = true,
                                    text = { Text(text = stringResource(R.string.action_finish_workout)) },
                                    icon = {
                                        Icon(
                                            imageVector = Icons.Default.CheckCircle,
                                            contentDescription = stringResource(R.string.action_finish_workout)
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
            ) { innerPadding ->
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                ) {
                    NavHost(
                        navController = navController,
                        startDestination = AppDestination.Workouts.route,
                        route = "gym-root-$uiIsolationKey",
                        modifier = Modifier.fillMaxSize()
                    ) {
                        composable(route = AppDestination.Workouts.route) {
                            val viewModel: WorkoutListViewModel = viewModel(
                                factory = WorkoutListViewModel.factory(repository)
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            WorkoutListScreen(
                                uiState = uiState,
                                onSessionClick = { sessionId ->
                                    navController.navigate(AppDestination.workoutDetailRoute(sessionId))
                                },
                                onPreviousMonth = viewModel::previousMonth,
                                onCurrentMonth = viewModel::currentMonth,
                                onNextMonth = viewModel::nextMonth,
                                onMuscleMapPeriodSelected = viewModel::selectMuscleMapPeriod,
                                onMuscleSelected = viewModel::selectMuscle,
                                onDeleteSession = viewModel::deleteSession,
                                onAddWorkout = {
                                    navController.navigate(AppDestination.AddWorkout.route)
                                },
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(route = AppDestination.Missions.route) {
                            val viewModel: WorkoutListViewModel = viewModel(
                                factory = WorkoutListViewModel.factory(repository)
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            MissionsScreen(
                                uiState = uiState,
                                onOpenRanks = {
                                    navController.navigate(AppDestination.Ranks.route) {
                                        launchSingleTop = true
                                    }
                                },
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(route = AppDestination.Ranks.route) {
                            val viewModel: WorkoutListViewModel = viewModel(
                                factory = WorkoutListViewModel.factory(repository)
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            RanksScreen(
                                uiState = uiState,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(route = AppDestination.AddWorkout.route) {
                            val context = LocalContext.current
                            val syncClient = remember(context) { PhoneSyncClient(context) }
                            val viewModel: AddWorkoutViewModel = viewModel(
                                factory = AddWorkoutViewModel.factory(
                                    repository = repository,
                                    syncClient = syncClient,
                                    trainingProfileManager = context.gymApplication.trainingProfileManager
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()
                            val smartCoachPlanNote = stringResource(R.string.smart_coach_plan_note)

                            LaunchedEffect(uiState.createdSessionId) {
                                val createdSessionId = uiState.createdSessionId
                                if (createdSessionId != null) {
                                    navController.navigate(AppDestination.postWorkoutSummaryRoute(createdSessionId)) {
                                        popUpTo(AppDestination.AddWorkout.route) {
                                            inclusive = true
                                        }
                                    }
                                    viewModel.consumeCreatedSession()
                                }
                            }

                            AddWorkoutScreen(
                                uiState = uiState,
                                onNoteChange = viewModel::updateNote,
                                onTrainingSplitSelected = viewModel::updateTrainingSplit,
                                onWorkoutsPerWeekSelected = viewModel::updateWorkoutsPerWeek,
                                onTrainingGoalSelected = viewModel::updateTrainingGoal,
                                onCalorieModeSelected = viewModel::updateCalorieMode,
                                onGenerateSmartWorkout = {
                                    viewModel.generateSmartWorkout(smartCoachPlanNote)
                                },
                                onAddExerciseDraft = viewModel::addExerciseDraft,
                                onRemoveExerciseDraft = viewModel::removeExerciseDraft,
                                onExerciseSelected = viewModel::updateExerciseSelection,
                                onAddSet = viewModel::addSet,
                                onAddSetFromPrevious = viewModel::addSetFromPrevious,
                                onRemoveSet = viewModel::removeSet,
                                onSetWeightChanged = viewModel::updateSetWeight,
                                onSetRepsChanged = viewModel::updateSetReps,
                                onApplyLastWeight = viewModel::applyLastWeight,
                                onApplyWorkoutRecommendation = viewModel::applyWorkoutRecommendation,
                                onRepeatLastWorkout = viewModel::repeatLastWorkout,
                                onOpenTemplatePicker = viewModel::openWorkoutTemplatePicker,
                                onCloseTemplatePicker = viewModel::closeWorkoutTemplatePicker,
                                onCopyWorkoutTemplate = viewModel::copyWorkoutTemplate,
                                onSyncPlanToWatch = viewModel::syncPlanToWatch,
                                onSaveWorkout = viewModel::saveWorkout,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(
                            route = AppDestination.PostWorkoutSummary.route,
                            arguments = listOf(
                                navArgument("sessionId") { type = NavType.LongType }
                            )
                        ) { backStackEntry ->
                            val sessionId = backStackEntry.arguments?.getLong("sessionId") ?: return@composable
                            val viewModel: PostWorkoutSummaryViewModel = viewModel(
                                key = "post_workout_summary_$sessionId",
                                factory = PostWorkoutSummaryViewModel.factory(
                                    repository = repository,
                                    sessionId = sessionId
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            PostWorkoutSummaryScreen(
                                uiState = uiState,
                                onViewWorkout = {
                                    navController.navigate(AppDestination.workoutDetailRoute(sessionId)) {
                                        popUpTo(AppDestination.PostWorkoutSummary.route) {
                                            inclusive = true
                                        }
                                    }
                                },
                                onDone = {
                                    val returnedToWorkouts = navController.popBackStack(
                                        AppDestination.Workouts.route,
                                        inclusive = false
                                    )
                                    if (!returnedToWorkouts) {
                                        navController.navigate(AppDestination.Workouts.route) {
                                            popUpTo(navController.graph.startDestinationId) {
                                                saveState = true
                                            }
                                            launchSingleTop = true
                                            restoreState = true
                                        }
                                    }
                                },
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(
                            route = AppDestination.WorkoutDetail.route,
                            arguments = listOf(
                                navArgument("sessionId") { type = NavType.LongType }
                            )
                        ) { backStackEntry ->
                            val sessionId = backStackEntry.arguments?.getLong("sessionId") ?: return@composable
                            val viewModel: WorkoutDetailViewModel = viewModel(
                                key = "workout_detail_$sessionId",
                                factory = WorkoutDetailViewModel.factory(
                                    repository = repository,
                                    sessionId = sessionId,
                                    restTimerController = restTimerController
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            WorkoutDetailScreen(
                                uiState = uiState,
                                events = viewModel.events,
                                onAddExerciseToWorkout = viewModel::addExerciseToWorkout,
                                onAddSet = viewModel::addSet,
                                onDeleteSet = viewModel::deleteSet,
                                onDeleteSession = viewModel::deleteSession,
                                onSessionDeleted = { navController.popBackStack() },
                                onUpdateSet = viewModel::updateSet,
                                onUndoDelete = viewModel::undoDeleteSet,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(route = AppDestination.Exercises.route) {
                            val viewModel: ExerciseListViewModel = viewModel(
                                factory = ExerciseListViewModel.factory(repository, authManager)
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            ExerciseListScreen(
                                uiState = uiState,
                                onNameChange = viewModel::updateNewExerciseName,
                                onAddExercise = viewModel::addExercise,
                                onExerciseClick = viewModel::openExerciseHistory,
                                onStartRenameExercise = viewModel::startRenameExercise,
                                onRenameExerciseNameChange = viewModel::updateEditingExerciseName,
                                onSaveRenameExercise = viewModel::saveRenameExercise,
                                onDismissRenameExercise = viewModel::closeRenameExercise,
                                onDeleteExercise = viewModel::deleteExercise,
                                onEditExerciseMapping = viewModel::openExerciseMapping,
                                onToggleExerciseMappingMuscle = viewModel::toggleExerciseMappingMuscle,
                                onSaveExerciseMapping = viewModel::saveExerciseMapping,
                                onDismissExerciseMapping = viewModel::closeExerciseMapping,
                                onDismissHistory = viewModel::closeExerciseHistory,
                                onToggleFavorite = viewModel::toggleFavorite,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(route = AppDestination.Progress.route) {
                            val viewModel: ExerciseProgressViewModel = viewModel(
                                factory = ExerciseProgressViewModel.factory(repository)
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            ExerciseProgressScreen(
                                uiState = uiState,
                                onSelectExercise = viewModel::selectExercise,
                                onDeleteHistoryEntry = viewModel::deleteHistoryEntry,
                                onPreviousMonth = viewModel::previousMonth,
                                onCurrentMonth = viewModel::currentMonth,
                                onNextMonth = viewModel::nextMonth,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(route = AppDestination.Profile.route) {
                            val viewModel: WorkoutListViewModel = viewModel(
                                factory = WorkoutListViewModel.factory(repository)
                            )
                            val uiState by viewModel.uiState.collectAsState()
                            val profileViewModel: ExerciseListViewModel = viewModel(
                                key = "profile_account_tools",
                                factory = ExerciseListViewModel.factory(repository, authManager)
                            )
                            val profileState by profileViewModel.uiState.collectAsState()
                            var rows by remember { mutableStateOf<List<LeaderboardRow>>(emptyList()) }
                            var isLoading by remember { mutableStateOf(false) }
                            var error by remember { mutableStateOf<LocalizedText?>(null) }

                            fun refreshLeaderboard() {
                                val session = authState.session as? AccountSession.Cloud
                                if (session == null) {
                                    error = LocalizedText(R.string.leaderboard_login_required)
                                    rows = emptyList()
                                    return
                                }
                                coroutineScope.launch {
                                    isLoading = true
                                    error = null
                                    val localRows = runCatching {
                                        val remoteProfile = authManager.loadOwnProfile(session)
                                        val localStats = repository.getSyncProfileStats()
                                        LeaderboardRow(
                                            displayName = remoteProfile?.displayName ?: session.displayName,
                                            xp = localStats.xp,
                                            level = localStats.level,
                                            workouts = localStats.workouts,
                                            isCurrentUser = true
                                        )
                                    }.getOrElse {
                                        LeaderboardRow(
                                            displayName = session.displayName,
                                            xp = uiState.soloProgress.totalXp,
                                            level = uiState.soloProgress.level,
                                            workouts = uiState.dashboardStats.workoutCount,
                                            isCurrentUser = true
                                        )
                                    }

                                    runCatching {
                                        val loadedRows = authManager.loadLeaderboard(session)
                                        if (loadedRows.any { it.isCurrentUser }) {
                                            loadedRows
                                        } else {
                                            listOf(localRows) + loadedRows
                                        }
                                    }.onSuccess { loadedRows ->
                                        rows = loadedRows
                                        isLoading = false
                                    }.onFailure { throwable ->
                                        error = authErrorText(
                                            throwable,
                                            R.string.leaderboard_load_failed
                                        )
                                        rows = listOf(localRows)
                                        isLoading = false
                                    }
                                }
                            }

                            LaunchedEffect(cloudSession?.userId) {
                                refreshLeaderboard()
                            }

                            ProfileScreen(
                                accountState = profileState,
                                rows = rows,
                                soloProgress = uiState.soloProgress,
                                isLeaderboardLoading = isLoading,
                                leaderboardError = error,
                                onRefreshLeaderboard = { refreshLeaderboard() },
                                onExportBackup = profileViewModel::exportBackup,
                                onExportDiagnostics = profileViewModel::exportDiagnostics,
                                onClearBackup = profileViewModel::clearBackupJson,
                                onOpenImport = profileViewModel::openImport,
                                onCloseImport = profileViewModel::closeImport,
                                onImportJsonChange = profileViewModel::updateImportJson,
                                onImportBackup = profileViewModel::importBackup,
                                onLogout = profileViewModel::logout,
                                modifier = Modifier.fillMaxSize()
                            )
                        }
                    }
                }
            }

            AnimatedVisibility(
                visible = showIntro,
                enter = fadeIn() + slideInVertically(initialOffsetY = { it / 8 }),
                exit = fadeOut() + scaleOut(targetScale = 1.03f)
            ) {
                AppIntroSplash()
            }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppTopBar(
    titleRes: Int,
    isRootDestination: Boolean,
    showRootTitle: Boolean,
    selectedLanguage: AppLanguage,
    onBack: () -> Unit,
    onLanguageSelected: (AppLanguage) -> Unit,
    scrollBehavior: TopAppBarScrollBehavior
) {
    if (isRootDestination) {
        TopAppBar(
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = Color.Transparent,
                titleContentColor = MaterialTheme.colorScheme.onBackground
            ),
            title = {
                if (showRootTitle) {
                    Text(
                        text = stringResource(titleRes),
                        style = MaterialTheme.typography.headlineLarge
                    )
                }
            },
            actions = {
                LanguageSelector(
                    selectedLanguage = selectedLanguage,
                    onLanguageSelected = onLanguageSelected
                )
            },
            scrollBehavior = scrollBehavior
        )
    } else {
        CenterAlignedTopAppBar(
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                containerColor = Color.Transparent,
                titleContentColor = MaterialTheme.colorScheme.onBackground
            ),
            title = {
                Text(
                    text = stringResource(titleRes),
                    style = MaterialTheme.typography.titleLarge
                )
            },
            navigationIcon = {
                Surface(
                    modifier = Modifier.padding(start = 12.dp),
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.84f),
                    shape = MaterialTheme.shapes.small,
                    border = BorderStroke(
                        1.dp,
                        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.9f)
                    )
                ) {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back)
                        )
                    }
                }
            },
            actions = {
                LanguageSelector(
                    selectedLanguage = selectedLanguage,
                    onLanguageSelected = onLanguageSelected
                )
            },
            scrollBehavior = scrollBehavior
        )
    }
}

@Composable
private fun LanguageSelector(
    selectedLanguage: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Box(modifier = Modifier.padding(end = 12.dp)) {
        Surface(
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.84f),
            shape = MaterialTheme.shapes.small,
            border = BorderStroke(
                1.dp,
                MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.9f)
            )
        ) {
            IconButton(onClick = { expanded = true }) {
                Icon(
                    imageVector = Icons.Default.Language,
                    contentDescription = stringResource(R.string.cd_language)
                )
            }
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            DropdownMenuItem(
                text = {
                    Text(
                        text = stringResource(R.string.language_english),
                        color = if (selectedLanguage == AppLanguage.EN) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        }
                    )
                },
                onClick = {
                    onLanguageSelected(AppLanguage.EN)
                    expanded = false
                }
            )
            DropdownMenuItem(
                text = {
                    Text(
                        text = stringResource(R.string.language_ukrainian),
                        color = if (selectedLanguage == AppLanguage.UK) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        }
                    )
                },
                onClick = {
                    onLanguageSelected(AppLanguage.UK)
                    expanded = false
                }
            )
            DropdownMenuItem(
                text = {
                    Text(
                        text = stringResource(R.string.language_russian),
                        color = if (selectedLanguage == AppLanguage.RU) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        }
                    )
                },
                onClick = {
                    onLanguageSelected(AppLanguage.RU)
                    expanded = false
                }
            )
        }
    }
}
