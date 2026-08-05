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
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
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
import com.example.gymapp.auth.CloudAccountDeletionSessionDisposition
import com.example.gymapp.auth.CloudAuthManager
import com.example.gymapp.auth.activeCloudSessionFor
import com.example.gymapp.auth.authErrorText
import com.example.gymapp.auth.databaseName
import com.example.gymapp.auth.LeaderboardRow
import com.example.gymapp.auth.requiresEmailConfirmation
import com.example.gymapp.data.repository.BackupOwner
import com.example.gymapp.data.repository.canonicalWorkoutPayloadDigest
import com.example.gymapp.gymApplication
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.ui.screens.AddWorkoutScreen
import com.example.gymapp.ui.screens.ActiveWorkoutScreen
import com.example.gymapp.ui.screens.AppIntroSplash
import com.example.gymapp.ui.screens.AuthScreen
import com.example.gymapp.ui.screens.CloudSyncConflictDialog
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
import com.example.gymapp.ui.viewmodel.ActiveWorkoutViewModel
import com.example.gymapp.ui.viewmodel.ExerciseListViewModel
import com.example.gymapp.ui.viewmodel.ExerciseProgressViewModel
import com.example.gymapp.ui.viewmodel.PostWorkoutSummaryViewModel
import com.example.gymapp.ui.viewmodel.WorkoutDetailViewModel
import com.example.gymapp.ui.viewmodel.WorkoutListViewModel
import com.example.gymapp.sync.PhoneSyncClient
import com.example.gymapp.sync.CloudSnapshotApplyDecision
import com.example.gymapp.sync.CloudSyncConflictSnapshot
import com.example.gymapp.sync.CloudSyncBaselineStore
import com.example.gymapp.sync.attachSharedCloudExtensions
import com.example.gymapp.sync.cloudSnapshotApplyDecision
import com.example.gymapp.sync.isCanonicalSharedCloudEnvelope
import com.example.gymapp.sync.isSharedCloudStateCandidate
import com.example.gymapp.sync.prepareSharedCloudState
import com.example.gymapp.sync.runCurrentCloudSyncConflictAction
import com.example.gymapp.util.AppLanguage
import com.example.gymapp.util.LanguageManager
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.RestTimerController
import com.example.gymapp.util.restTimerAccountKey
import com.example.gymapp.util.asString
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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

internal suspend fun runConfirmedAccountDeletionLocalCleanup(
    clearRoom: suspend () -> Unit,
    clearBaseline: () -> Boolean,
    clearTrainingProfile: () -> Boolean
): Int {
    var failures = 0
    if (runCatching { clearRoom() }.isFailure) failures += 1
    if (runCatching { check(clearBaseline()) }.isFailure) failures += 1
    if (runCatching { check(clearTrainingProfile()) }.isFailure) failures += 1
    return failures
}

internal fun accountActionsEnabled(
    authLoading: Boolean,
    deletionInProgress: Boolean
): Boolean = !authLoading && !deletionInProgress

internal fun shouldInitializeMissingRemoteState(localProjectionEmpty: Boolean): Boolean =
    localProjectionEmpty

internal fun shouldSeedCatalogAfterCloudPull(canonicalRoundTripSafe: Boolean): Boolean =
    canonicalRoundTripSafe

internal enum class CloudSyncRetryMode {
    Pull,
    ResumeAutosave
}

internal fun isRetryableCloudSyncMessage(message: LocalizedText?): Boolean =
    message?.resourceId in setOf(
        R.string.auth_error_connection,
        R.string.auth_error_cloud_unavailable,
        R.string.cloud_sync_load_failed,
        R.string.cloud_sync_conflict,
        R.string.cloud_sync_save_failed,
        R.string.cloud_sync_account_changed,
        R.string.cloud_sync_baseline_failed,
        R.string.cloud_sync_round_trip_failed,
        R.string.cloud_sync_resolution_failed
    )

internal fun cloudSyncRetryModeForSaveFailure(message: LocalizedText): CloudSyncRetryMode =
    if (message.resourceId == R.string.cloud_sync_conflict) {
        CloudSyncRetryMode.Pull
    } else {
        CloudSyncRetryMode.ResumeAutosave
    }

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
    isCanonicalSharedCloudEnvelope(root, activeUserId)

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
    val selectedLanguage by languageManager.selectedLanguage.collectAsState()
    // A new account generation gets a new controller and graph identity. Navigation Compose can
    // otherwise retain equal-route back-stack entries and their repository-bound ViewModelStores.
    // Language is part of the identity too: retained ViewModels can contain already-formatted
    // labels, so keeping them across a locale switch produces a mixed-language screen.
    val navController = key(uiIsolationKey, selectedLanguage) { rememberNavController() }
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val repository = remember(uiIsolationKey) { repositoryProvider(authState.session) }
    val activeWorkout by repository.observeActiveWorkout().collectAsState(initial = null)
    val coroutineScope = key(uiIsolationKey) { rememberCoroutineScope() }
    val accountDeletionScope = rememberCoroutineScope()
    val applicationContext = LocalContext.current.applicationContext
    val cloudSyncBaselineStore = remember(applicationContext) {
        CloudSyncBaselineStore(applicationContext)
    }
    var sharedCloudExtensions by key(uiIsolationKey) {
        // Extensions are populated only by a successfully validated pull. Automatic upload is
        // never enabled before that pull, so a process restart cannot drop another client's
        // namespace: the current remote row is fetched and its CAS revision is rebound first.
        remember { mutableStateOf<JSONObject?>(null) }
    }
    var showIntro by rememberSaveable { mutableStateOf(true) }
    var accountDeletionInProgress by remember { mutableStateOf(false) }
    var cloudPullGeneration by key(uiIsolationKey) {
        remember { mutableStateOf<String?>(null) }
    }
    var cloudSyncRetryVersion by key(uiIsolationKey) {
        remember { mutableStateOf(0) }
    }
    var cloudSyncRetryMode by key(uiIsolationKey) {
        remember { mutableStateOf<CloudSyncRetryMode?>(null) }
    }
    var cloudSyncConflict by key(uiIsolationKey) {
        remember { mutableStateOf<CloudSyncConflictSnapshot?>(null) }
    }
    var showCloudSyncConflictDialog by key(uiIsolationKey) {
        remember { mutableStateOf(false) }
    }
    var cloudConflictResolutionInProgress by key(uiIsolationKey) {
        remember { mutableStateOf(false) }
    }
    var cloudSyncConflictNoticeVersion by key(uiIsolationKey) {
        remember { mutableStateOf(0) }
    }
    val snackbarHostState = key(uiIsolationKey) { remember { SnackbarHostState() } }

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

    LaunchedEffect(cloudSession?.sessionGeneration, cloudSyncRetryVersion) {
        val session = cloudSession ?: return@LaunchedEffect
        cloudPullGeneration = null
        cloudSyncRetryMode = null
        val pullResult = runCatching {
            val remoteState = authManager.loadRemoteState(session)
            if (remoteState != null && remoteState.length() > 0) {
                val preparedSharedState = if (isSharedCloudStateCandidate(remoteState)) {
                    withContext(Dispatchers.Default) {
                        prepareSharedCloudState(remoteState, session.userId)
                    }
                } else {
                    null
                }
                if (preparedSharedState == null) {
                    // Legacy cross-client rows remain readable, but they never arm an automatic
                    // write-back. Import them into the reviewed device snapshot, then require an
                    // explicit choice before publishing the canonical replacement.
                    repository.importBackupJsonObject(
                        remoteState,
                        activeUserId = session.userId,
                        activeRemote = true
                    )
                    val importedLocalState = repository.getCloudWorkoutProjectionState()
                    cloudSyncConflict = CloudSyncConflictSnapshot(
                        userId = session.userId,
                        sessionGeneration = session.sessionGeneration,
                        localDigest = importedLocalState.digest,
                        remoteDigest = null,
                        remoteExists = true
                    )
                    showCloudSyncConflictDialog = true
                    false
                } else {
                    sharedCloudExtensions = preparedSharedState.extensions
                    val remoteDigest = preparedSharedState.workoutDigest
                    val localState = repository.getCloudWorkoutProjectionState()
                    when (cloudSnapshotApplyDecision(
                        localDigest = localState.digest,
                        remoteDigest = remoteDigest,
                        lastSyncedDigest = cloudSyncBaselineStore.read(session.userId),
                        localProjectionEmpty = localState.isEmpty
                    )) {
                        CloudSnapshotApplyDecision.Conflict -> {
                            cloudSyncConflict = CloudSyncConflictSnapshot(
                                userId = session.userId,
                                sessionGeneration = session.sessionGeneration,
                                localDigest = localState.digest,
                                remoteDigest = remoteDigest,
                                remoteExists = true
                            )
                            showCloudSyncConflictDialog = true
                            false
                        }

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

                        CloudSnapshotApplyDecision.UploadLocal -> {
                            check(isSameCloudSessionGeneration(
                                session,
                                authManager.authState.value.session
                            )) { "Cloud account changed while resuming local upload." }
                            // The remote digest is still the last confirmed baseline, so the
                            // account-specific Room state is the only changed side. The revision
                            // cached by loadRemoteState keeps the resumed upload compare-and-swap
                            // protected if another device writes before it reaches the server.
                            true
                        }
                    }
                }
            } else {
                sharedCloudExtensions = null
                // Missing remote state may initialize only a genuinely empty account database.
                // A non-empty projection could be stale data from a deleted remote row.
                val localState = repository.getCloudWorkoutProjectionState()
                shouldInitializeMissingRemoteState(localState.isEmpty).also { safeToInitialize ->
                    if (!safeToInitialize) {
                        cloudSyncConflict = CloudSyncConflictSnapshot(
                            userId = session.userId,
                            sessionGeneration = session.sessionGeneration,
                            localDigest = localState.digest,
                            remoteDigest = null,
                            remoteExists = false
                        )
                        showCloudSyncConflictDialog = true
                    }
                }
            }
        }
        pullResult.onFailure { throwable ->
            if (throwable is CancellationException) throw throwable
            if (isSameCloudSessionGeneration(session, authManager.authState.value.session)) {
                cloudSyncRetryMode = CloudSyncRetryMode.Pull
                authManager.setMessage(
                    authErrorText(throwable, R.string.cloud_sync_load_failed)
                )
            }
        }
        pullResult.onSuccess { canonicalRoundTripSafe ->
            if (shouldSeedCatalogAfterCloudPull(canonicalRoundTripSafe) &&
                isSameCloudSessionGeneration(session, authManager.authState.value.session)
            ) {
                // A conflict must not mutate the reviewed local snapshot. Seed only after a safe
                // pull or after the user explicitly resolves the conflict below.
                repository.seedBuiltInExercises()
                repository.seedDefaultExerciseMuscleMappings()
                cloudSyncConflict = null
                showCloudSyncConflictDialog = false
                if (authManager.authState.value.message?.resourceId == R.string.cloud_sync_conflict) {
                    authManager.setMessage(null, isError = false)
                }
            }
            if (!canonicalRoundTripSafe &&
                isSameCloudSessionGeneration(session, authManager.authState.value.session)
            ) {
                cloudSyncRetryMode = if (cloudSyncConflict == null) {
                    CloudSyncRetryMode.Pull
                } else {
                    null
                }
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
            repository.observeExerciseMuscleMappings(),
            repository.observeExerciseLoadProfiles()
        ) { sessions, exercises, mappings, loadProfiles ->
            listOf(sessions.size, exercises.size, mappings.size, loadProfiles.hashCode())
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
                    val state = attachSharedCloudExtensions(
                        canonicalCore = repository.buildCloudBackupJson(owner = owner),
                        extensions = sharedCloudExtensions
                    )
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
                    if (isSameCloudSessionGeneration(
                            session,
                            authManager.authState.value.session
                        )
                    ) {
                        val message = authErrorText(throwable, R.string.cloud_sync_save_failed)
                        cloudSyncRetryMode = cloudSyncRetryModeForSaveFailure(message)
                        authManager.setMessage(message)
                    }
                }
            }
    }

    val resolveCloudSyncConflict: (Boolean) -> Unit = resolve@{ useCloudVersion ->
        if (cloudConflictResolutionInProgress) return@resolve
        val conflict = cloudSyncConflict ?: return@resolve
        val session = cloudSession ?: return@resolve
        if (conflict.userId != session.userId ||
            conflict.sessionGeneration != session.sessionGeneration
        ) return@resolve

        cloudConflictResolutionInProgress = true
        coroutineScope.launch {
            val result = runCatching {
                check(isSameCloudSessionGeneration(
                    session,
                    authManager.authState.value.session
                )) { "Cloud account changed while confirming the sync baseline." }

                // Reload immediately before the choice so the cached server revision can protect
                // a local upload and both reviewed digests can be checked again.
                val remoteState = authManager.loadRemoteState(session)
                    ?.takeIf { it.length() > 0 }
                val preparedRemote = remoteState?.let { candidate ->
                    if (isSharedCloudStateCandidate(candidate)) {
                        withContext(Dispatchers.Default) {
                            prepareSharedCloudState(candidate, session.userId)
                        }
                    } else {
                        null
                    }
                }
                sharedCloudExtensions = preparedRemote?.extensions
                val remoteDigest = preparedRemote?.workoutDigest
                val localState = repository.getCloudWorkoutProjectionState()

                runCurrentCloudSyncConflictAction(
                    conflict = conflict,
                    userId = session.userId,
                    sessionGeneration = session.sessionGeneration,
                    localDigest = localState.digest,
                    remoteDigest = remoteDigest,
                    remoteExists = remoteState != null
                ) {
                    if (useCloudVersion) {
                        val acceptedRemote = checkNotNull(remoteState) {
                            "Cloud data changed on another device. Reload it before syncing again."
                        }
                        val acceptedPrepared = checkNotNull(preparedRemote) {
                            "Cloud state did not round-trip safely. Automatic upload is paused."
                        }
                        val acceptedDigest = acceptedPrepared.workoutDigest
                        repository.replaceWithBackupJsonObject(
                            root = acceptedRemote,
                            expectedLocalState = localState,
                            activeUserId = session.userId,
                            activeRemote = true
                        )
                        val replacedState = repository.getCloudWorkoutProjectionState()
                        check(replacedState.digest == acceptedDigest) {
                            "Cloud state did not round-trip safely. Automatic upload is paused."
                        }
                        check(isSameCloudSessionGeneration(
                            session,
                            authManager.authState.value.session
                        )) { "Cloud account changed while confirming the sync baseline." }
                        check(cloudSyncBaselineStore.write(session.userId, acceptedDigest)) {
                            "Could not persist the cloud sync baseline. Automatic upload is paused."
                        }
                    } else {
                        val owner = BackupOwner(
                            accountId = session.userId,
                            userId = session.userId,
                            email = session.email,
                            remote = true
                        )
                        val localBackup = attachSharedCloudExtensions(
                            canonicalCore = repository.buildCloudBackupJson(owner = owner),
                            extensions = sharedCloudExtensions
                        )
                        val localDigest = withContext(Dispatchers.Default) {
                            checkNotNull(canonicalWorkoutPayloadDigest(localBackup))
                        }
                        check(localDigest == localState.digest) {
                            "Local workout data changed while cloud state was loading. Automatic replacement is paused."
                        }
                        val stats = repository.getSyncProfileStats()
                        check(isSameCloudSessionGeneration(
                            session,
                            authManager.authState.value.session
                        )) { "Cloud account changed while confirming the sync baseline." }
                        authManager.saveRemoteState(
                            session = session,
                            state = localBackup,
                            xp = stats.xp,
                            level = stats.level,
                            workouts = stats.workouts
                        )
                        check(isSameCloudSessionGeneration(
                            session,
                            authManager.authState.value.session
                        )) { "Cloud account changed while confirming the sync baseline." }
                        check(cloudSyncBaselineStore.write(session.userId, localDigest)) {
                            "Could not persist the cloud sync baseline. Automatic upload is paused."
                        }
                    }
                    // Apply additive public-catalog migrations only after the selected version is
                    // safely accepted; autosave will then publish the additive change if needed.
                    repository.seedBuiltInExercises()
                    repository.seedDefaultExerciseMuscleMappings()
                }
            }

            result.exceptionOrNull()?.let { throwable ->
                if (throwable is CancellationException) throw throwable
            }
            cloudConflictResolutionInProgress = false
            result.onSuccess {
                if (isSameCloudSessionGeneration(
                        session,
                        authManager.authState.value.session
                    )
                ) {
                    cloudSyncConflict = null
                    showCloudSyncConflictDialog = false
                    cloudSyncRetryMode = null
                    cloudPullGeneration = session.sessionGeneration
                    authManager.setMessage(
                        LocalizedText(
                            if (useCloudVersion) R.string.cloud_sync_used_cloud
                            else R.string.cloud_sync_kept_device
                        ),
                        isError = false
                    )
                }
            }.onFailure { throwable ->
                if (isSameCloudSessionGeneration(
                        session,
                        authManager.authState.value.session
                    )
                ) {
                    cloudSyncConflict = null
                    showCloudSyncConflictDialog = false
                    cloudPullGeneration = null
                    cloudSyncRetryMode = CloudSyncRetryMode.Pull
                    authManager.setMessage(
                        authErrorText(throwable, R.string.cloud_sync_resolution_failed)
                    )
                }
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
        currentRoute == AppDestination.ActiveWorkout.route -> R.string.active_workout_title
        currentRoute?.startsWith("workout_detail/") == true -> R.string.title_workout_detail
        currentRoute?.startsWith("post_workout_summary/") == true -> R.string.title_post_workout_summary
        else -> R.string.app_name
    }
    val topAppBarScrollBehavior = TopAppBarDefaults.enterAlwaysScrollBehavior()

    key(uiIsolationKey, selectedLanguage) {
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
                                if (requiresEmailConfirmation(throwable)) {
                                    authManager.showEmailConfirmation(email)
                                } else {
                                    authManager.setMessage(
                                        authErrorText(throwable, R.string.auth_message_login_failed)
                                    )
                                }
                            }
                        }
                    },
                    onSignUp = { email, password, displayName ->
                        coroutineScope.launch {
                            authManager.setLoading(true)
                            runCatching {
                                val session = authManager.signUp(email, password, displayName)
                                if (session == null) {
                                    authManager.showEmailConfirmation(email)
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
                    onDismissEmailConfirmation = authManager::dismissEmailConfirmation,
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
                    onContinueLocal = { displayName ->
                        authManager.setLoading(true)
                        runCatching {
                            authManager.setLocal(displayName)
                        }.onFailure { throwable ->
                            authManager.setMessage(
                                authErrorText(
                                    throwable,
                                    R.string.auth_message_local_profile_failed
                                )
                            )
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

            val signedInMessage = authState.message?.asString()
            val retryLabel = stringResource(R.string.action_retry)
            val resolveLabel = stringResource(R.string.cloud_sync_resolve_action)
            val closeLabel = stringResource(R.string.action_close)
            LaunchedEffect(
                signedInMessage,
                authState.messageIsError,
                authState.message?.resourceId,
                cloudSyncConflict,
                cloudSyncConflictNoticeVersion,
                currentRoute
            ) {
                if (signedInMessage == null) {
                    cloudSyncRetryMode = null
                    snackbarHostState.currentSnackbarData?.dismiss()
                    return@LaunchedEffect
                }
                val retryMode = cloudSyncRetryMode
                val conflictShownInProfile =
                    currentRoute == AppDestination.Profile.route &&
                        authState.message?.resourceId == R.string.cloud_sync_conflict
                if (conflictShownInProfile) {
                    snackbarHostState.currentSnackbarData?.dismiss()
                    return@LaunchedEffect
                }
                val resolvableConflict =
                    authState.message?.resourceId == R.string.cloud_sync_conflict &&
                        cloudSyncConflict != null
                val retryable = retryMode != null &&
                    isRetryableCloudSyncMessage(authState.message)
                val result = snackbarHostState.showSnackbar(
                    message = signedInMessage,
                    actionLabel = when {
                        resolvableConflict -> resolveLabel
                        retryable -> retryLabel
                        authState.messageIsError -> closeLabel
                        else -> null
                    },
                    duration = if (authState.messageIsError) {
                        SnackbarDuration.Indefinite
                    } else {
                        SnackbarDuration.Short
                    }
                )
                if (result == SnackbarResult.ActionPerformed) {
                    if (resolvableConflict) {
                        showCloudSyncConflictDialog = true
                        return@LaunchedEffect
                    }
                    if (retryable) {
                        when (retryMode) {
                            CloudSyncRetryMode.Pull -> cloudSyncRetryVersion += 1
                            CloudSyncRetryMode.ResumeAutosave -> {
                                cloudPullGeneration =
                                    (authManager.authState.value.session as? AccountSession.Cloud)
                                        ?.sessionGeneration
                            }
                        }
                    }
                    cloudSyncRetryMode = null
                    authManager.setMessage(null, isError = false)
                } else if (!authState.messageIsError) {
                    cloudSyncRetryMode = null
                    authManager.setMessage(null, isError = false)
                }
            }

            Scaffold(
                modifier = Modifier
                    .fillMaxSize()
                    .nestedScroll(topAppBarScrollBehavior.nestedScrollConnection),
                containerColor = Color.Transparent,
                contentColor = MaterialTheme.colorScheme.onBackground,
                snackbarHost = { SnackbarHost(hostState = snackbarHostState) },
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
                                    modifier = Modifier
                                        .height(76.dp)
                                        .padding(horizontal = 8.dp),
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
                                    navController.navigate(
                                        if (activeWorkout == null) {
                                            AppDestination.AddWorkout.route
                                        } else {
                                            AppDestination.ActiveWorkout.route
                                        }
                                    )
                                },
                                hasActiveWorkout = activeWorkout != null,
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

                            LaunchedEffect(uiState.activeWorkoutStarted) {
                                if (uiState.activeWorkoutStarted) {
                                    navController.navigate(AppDestination.ActiveWorkout.route) {
                                        popUpTo(AppDestination.AddWorkout.route) {
                                            inclusive = true
                                        }
                                    }
                                    viewModel.consumeActiveWorkoutStarted()
                                }
                            }

                            AddWorkoutScreen(
                                uiState = uiState,
                                exerciseMediaOwnerKey = checkNotNull(authState.session).databaseName(),
                                onWorkoutDateSelected = viewModel::updateWorkoutDate,
                                onNoteChange = viewModel::updateNote,
                                onTrainingSplitSelected = viewModel::updateTrainingSplit,
                                onWorkoutsPerWeekSelected = viewModel::updateWorkoutsPerWeek,
                                onTrainingGoalSelected = viewModel::updateTrainingGoal,
                                onCalorieModeSelected = viewModel::updateCalorieMode,
                                onSmartWorkoutEffortSelected = viewModel::updateSmartWorkoutEffort,
                                onGenerateSmartWorkout = {
                                    viewModel.generateSmartWorkout(smartCoachPlanNote)
                                },
                                onOpenSmartAlternatives = viewModel::openSmartWorkoutAlternatives,
                                onCloseSmartAlternatives = viewModel::closeSmartWorkoutAlternatives,
                                onApplySmartAlternative = viewModel::applySmartWorkoutAlternative,
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
                                onStartWorkout = viewModel::startWorkout,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(route = AppDestination.ActiveWorkout.route) {
                            val viewModel: ActiveWorkoutViewModel = viewModel(
                                factory = ActiveWorkoutViewModel.factory(
                                    repository = repository,
                                    restTimerController = restTimerController
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            LaunchedEffect(
                                uiState.finishedSessionId,
                                uiState.wasDiscarded,
                                uiState.isMissing
                            ) {
                                val finishedSessionId = uiState.finishedSessionId
                                when {
                                    finishedSessionId != null -> {
                                        navController.navigate(
                                            AppDestination.postWorkoutSummaryRoute(finishedSessionId)
                                        ) {
                                            popUpTo(AppDestination.ActiveWorkout.route) {
                                                inclusive = true
                                            }
                                        }
                                        viewModel.consumeNavigation()
                                    }
                                    uiState.wasDiscarded || uiState.isMissing -> {
                                        navController.navigate(AppDestination.Workouts.route) {
                                            popUpTo(AppDestination.ActiveWorkout.route) {
                                                inclusive = true
                                            }
                                            launchSingleTop = true
                                        }
                                        viewModel.consumeNavigation()
                                    }
                                }
                            }

                            ActiveWorkoutScreen(
                                uiState = uiState,
                                onSetWeightChanged = viewModel::updateSetWeight,
                                onSetRepsChanged = viewModel::updateSetReps,
                                onRecordSet = viewModel::recordSet,
                                onFinishWorkout = viewModel::finishWorkout,
                                onDiscardWorkout = viewModel::discardWorkout,
                                onDismissMessage = viewModel::dismissMessage,
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
                                exerciseMediaOwnerKey = checkNotNull(authState.session).databaseName(),
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
                                    restTimerController = restTimerController,
                                    timerAccountKey = checkNotNull(
                                        restTimerAccountKey(authState.session)
                                    )
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            WorkoutDetailScreen(
                                uiState = uiState,
                                exerciseMediaOwnerKey = checkNotNull(authState.session).databaseName(),
                                events = viewModel.events,
                                onAddExerciseToWorkout = viewModel::addExerciseToWorkout,
                                onAddSet = viewModel::addSet,
                                onStartExerciseRestTimer = viewModel::startExerciseRestTimer,
                                onStopExerciseRestTimer = viewModel::stopExerciseRestTimer,
                                onDeleteSet = viewModel::requestDeleteSet,
                                onConfirmDeleteSet = viewModel::confirmSetDeletion,
                                onDismissDeleteSet = viewModel::dismissSetDeletion,
                                onDeleteSession = viewModel::deleteSession,
                                onSessionDeleted = { navController.popBackStack() },
                                onUpdateSet = viewModel::updateSet,
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
                                exerciseMediaOwnerKey = checkNotNull(authState.session).databaseName(),
                                onNameChange = viewModel::updateNewExerciseName,
                                onAddExercise = viewModel::addExercise,
                                onExerciseClick = viewModel::openExerciseHistory,
                                onStartRenameExercise = viewModel::startRenameExercise,
                                onRenameExerciseNameChange = viewModel::updateEditingExerciseName,
                                onSaveRenameExercise = viewModel::saveRenameExercise,
                                onDismissRenameExercise = viewModel::closeRenameExercise,
                                onDeleteExercise = viewModel::requestDeleteExercise,
                                onConfirmDeleteExercise = viewModel::confirmExerciseDeletion,
                                onDismissDeleteExercise = viewModel::dismissExerciseDeletion,
                                onEditExerciseMapping = viewModel::openExerciseMapping,
                                onToggleExerciseMappingMuscle = viewModel::toggleExerciseMappingMuscle,
                                onSaveExerciseMapping = viewModel::saveExerciseMapping,
                                onDismissExerciseMapping = viewModel::closeExerciseMapping,
                                onEditExerciseLoadProfile = viewModel::openExerciseLoadProfile,
                                onExerciseLoadDirectionChange = viewModel::updateExerciseLoadDirection,
                                onExerciseLoadWeightsChange = viewModel::updateExerciseLoadWeights,
                                onApplyExerciseLoadPreset = viewModel::applyExerciseLoadPreset,
                                onSaveExerciseLoadProfile = viewModel::saveExerciseLoadProfile,
                                onClearExerciseLoadProfile = viewModel::clearExerciseLoadProfile,
                                onDismissExerciseLoadProfile = viewModel::closeExerciseLoadProfile,
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
                                exerciseMediaOwnerKey = checkNotNull(authState.session).databaseName(),
                                events = viewModel.events,
                                onSelectExercise = viewModel::selectExercise,
                                onDeleteHistoryEntry = viewModel::requestDeleteHistoryEntry,
                                onConfirmDeleteHistoryEntry = viewModel::confirmSetDeletion,
                                onDismissDeleteHistoryEntry = viewModel::dismissSetDeletion,
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
                                cloudSyncChoiceRequired =
                                    cloudSyncConflict != null ||
                                        authState.message?.resourceId ==
                                            R.string.cloud_sync_conflict,
                                cloudSyncChoiceReady = cloudSyncConflict != null,
                                onReviewCloudSync = {
                                    if (cloudSyncConflict != null) {
                                        showCloudSyncConflictDialog = true
                                    } else {
                                        cloudSyncRetryMode = CloudSyncRetryMode.Pull
                                        cloudSyncRetryVersion += 1
                                    }
                                },
                                onExportBackup = profileViewModel::exportBackup,
                                onExportDiagnostics = profileViewModel::exportDiagnostics,
                                onClearBackup = profileViewModel::clearBackupJson,
                                onOpenImport = profileViewModel::openImport,
                                onCloseImport = profileViewModel::closeImport,
                                onImportJsonChange = profileViewModel::updateImportJson,
                                onImportBackup = profileViewModel::importBackup,
                                onLogout = {
                                    if (accountActionsEnabled(
                                            authLoading = authState.isLoading,
                                            deletionInProgress = accountDeletionInProgress
                                        )
                                    ) {
                                        profileViewModel.logout()
                                    }
                                },
                                isAccountActionLoading = !accountActionsEnabled(
                                    authLoading = authState.isLoading,
                                    deletionInProgress = accountDeletionInProgress
                                ),
                                onChangePassword = changePassword@ { currentPassword, newPassword ->
                                    if (!accountActionsEnabled(
                                            authLoading = authState.isLoading,
                                            deletionInProgress = accountDeletionInProgress
                                        )
                                    ) {
                                        return@changePassword
                                    }
                                    coroutineScope.launch {
                                        authManager.setLoading(true)
                                        runCatching {
                                            authManager.changePassword(
                                                currentPassword = currentPassword,
                                                newPassword = newPassword
                                            )
                                        }.onFailure { throwable ->
                                            if (authManager.authState.value.session != null) {
                                                authManager.setMessage(
                                                    authErrorText(
                                                        throwable,
                                                        R.string.account_change_password_failed
                                                    )
                                                )
                                            }
                                        }
                                    }
                                },
                                onDeleteCloudAccount = deleteAccount@ {
                                    if (!accountActionsEnabled(
                                            authLoading = authState.isLoading,
                                            deletionInProgress = accountDeletionInProgress
                                        )
                                    ) {
                                        return@deleteAccount
                                    }
                                    val capturedSession = authManager.authState.value.session
                                        as? AccountSession.Cloud ?: return@deleteAccount
                                    val capturedRepository = repository
                                    accountDeletionInProgress = true
                                    authManager.setLoading(true)
                                    accountDeletionScope.launch {
                                        runCatching {
                                            withContext(NonCancellable) {
                                                val deletedSession = authManager.deleteCloudAccount(
                                                    capturedSession
                                                )
                                                val cleanupFailures =
                                                    runConfirmedAccountDeletionLocalCleanup(
                                                        clearRoom = {
                                                            capturedRepository.clearAllAccountData()
                                                        },
                                                        clearBaseline = {
                                                            cloudSyncBaselineStore.clear(
                                                                deletedSession.userId
                                                            )
                                                        },
                                                        clearTrainingProfile = {
                                                            applicationContext.gymApplication
                                                                .trainingProfileManager
                                                                .clearAccount(deletedSession)
                                                        }
                                                    )
                                                val completion = authManager
                                                    .completeCloudAccountDeletion(deletedSession)
                                                if (cleanupFailures > 0 &&
                                                    completion !=
                                                    CloudAccountDeletionSessionDisposition
                                                        .PreserveDifferentSession
                                                ) {
                                                    authManager.setMessage(
                                                        LocalizedText(
                                                            R.string
                                                                .account_delete_local_cleanup_failed
                                                        )
                                                    )
                                                }
                                            }
                                        }.onFailure { throwable ->
                                            if (activeCloudSessionFor(
                                                    authManager.authState.value.session,
                                                    capturedSession
                                                ) != null
                                            ) {
                                                authManager.setMessage(
                                                    authErrorText(
                                                        throwable,
                                                        R.string.account_delete_failed
                                                    )
                                                )
                                            }
                                        }
                                        accountDeletionInProgress = false
                                    }
                                },
                                garminDeviceState = applicationContext.gymApplication
                                    .garminSyncManager.deviceUiState.collectAsState().value,
                                onResetGarminPairing = {
                                    coroutineScope.launch {
                                        applicationContext.gymApplication.garminSyncManager
                                            .resetSecureGarminPairing()
                                    }
                                },
                                modifier = Modifier.fillMaxSize()
                            )
                        }
                    }
                }
            }

            val conflict = cloudSyncConflict
            if (showCloudSyncConflictDialog && conflict != null) {
                CloudSyncConflictDialog(
                    cloudVersionAvailable = conflict.remoteDigest != null,
                    cloudVersionNeedsRepair =
                        conflict.remoteExists && conflict.remoteDigest == null,
                    resolving = cloudConflictResolutionInProgress,
                    onKeepDeviceVersion = { resolveCloudSyncConflict(false) },
                    onUseCloudVersion = { resolveCloudSyncConflict(true) },
                    onDismiss = {
                        showCloudSyncConflictDialog = false
                        cloudSyncConflictNoticeVersion += 1
                    }
                )
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
                scrolledContainerColor = Color.Transparent,
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
                scrolledContainerColor = Color.Transparent,
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
