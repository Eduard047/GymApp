package com.example.gymapp

import android.app.Application
import android.content.Context
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAccountDeletionJournal
import com.example.gymapp.auth.CloudAuthManager
import com.example.gymapp.auth.LocalDatabaseBindingStore
import com.example.gymapp.auth.PendingLocalProfileDeletion
import com.example.gymapp.auth.databaseName
import com.example.gymapp.auth.recoverPendingLocalProfileDeletion
import com.example.gymapp.auth.recoverPendingCloudAccountDeletion
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.LiveWorkoutSidecarStore
import com.example.gymapp.data.repository.SharedWorkoutInbox
import com.example.gymapp.garmin.GarminSyncManager
import com.example.gymapp.push.AndroidPushManager
import com.example.gymapp.push.PushNavigationInbox
import com.example.gymapp.sync.CloudSyncBaselineStore
import com.example.gymapp.sync.CloudSyncStatusStore
import com.example.gymapp.ui.media.ExerciseMediaStore
import com.example.gymapp.ui.screens.clearPrivateBackupShareArtifacts
import com.example.gymapp.util.LanguageManager
import com.example.gymapp.util.RestTimerController
import com.example.gymapp.util.TrainingGuidanceManager
import com.example.gymapp.util.TrainingProfileManager
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

class GymApplication : Application() {
    private val repositories = ConcurrentHashMap<String, GymRepository>()
    private val localDatabaseBindingStore by lazy { LocalDatabaseBindingStore(this) }
    private val cloudAccountDeletionJournal by lazy { CloudAccountDeletionJournal(this) }
    private val liveWorkoutSidecarStore by lazy { LiveWorkoutSidecarStore(this) }
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val legacyRepository: GymRepository by lazy { repositoryFor(null) }
    val cloudAuthManager: CloudAuthManager by lazy {
        CloudAuthManager(
            context = this,
            localDatabaseMaterializerOverride = ::materializeLocalDatabaseForAuthentication,
            localDatabaseRollbackOverride = ::rollbackNewLocalDatabaseForAuthentication
        )
    }
    val languageManager: LanguageManager by lazy { LanguageManager(this) }
    val trainingProfileManager: TrainingProfileManager by lazy { TrainingProfileManager(this) }
    val trainingGuidanceManager: TrainingGuidanceManager by lazy { TrainingGuidanceManager(this) }
    val restTimerController: RestTimerController by lazy { RestTimerController(this) }
    val garminSyncManager: GarminSyncManager by lazy { GarminSyncManager(this) }
    internal val sharedWorkoutInbox = SharedWorkoutInbox()
    internal val pushNavigationInbox = PushNavigationInbox()
    internal val pushManager: AndroidPushManager by lazy {
        AndroidPushManager(this, cloudAuthManager, pushNavigationInbox)
    }

    override fun onCreate() {
        super.onCreate()
        deleteSharedPreferences(RETIRED_PHONE_WEAR_PREFERENCES)
        val authManager = cloudAuthManager
        val profileManager = trainingProfileManager
        val guidanceManager = trainingGuidanceManager
        val timerController = restTimerController
        val garminManager = garminSyncManager
        val nativePushManager = pushManager
        val pendingAccountDeletions = cloudAccountDeletionJournal.pending()
        val pendingLocalProfileDeletion = authManager.pendingLocalProfileDeletion()
        applicationScope.launch(start = CoroutineStart.UNDISPATCHED) {
            authManager.authState.collect { state ->
                profileManager.switchAccount(state.session)
                guidanceManager.switchAccount(state.session)
                timerController.switchAccount(state.session)
            }
        }
        if (pendingAccountDeletions.isNotEmpty()) {
            applicationScope.launch(Dispatchers.IO) {
                val baselineStore = CloudSyncBaselineStore(this@GymApplication)
                val syncStatusStore = CloudSyncStatusStore(this@GymApplication)
                pendingAccountDeletions.forEach { record ->
                    recoverPendingCloudAccountDeletion(
                        record = record,
                        clearRoom = {
                            repositoryForDatabaseNames(
                                logicalDatabaseName = record.databaseName,
                                physicalDatabaseName = record.databaseName
                            ).clearAllAccountData()
                        },
                        clearBaseline = { baselineStore.clear(record.userId) },
                        clearTrainingProfile = {
                            val profileCleared = profileManager.clearAccountByDatabaseName(
                                record.databaseName
                            )
                            val guidanceCleared = guidanceManager.clearAccountByDatabaseName(
                                record.databaseName
                            )
                            profileCleared && guidanceCleared
                        },
                        clearSyncStatus = { syncStatusStore.clear(record.userId) },
                        clearCustomMedia = {
                            ExerciseMediaStore.clearOwner(
                                this@GymApplication,
                                record.databaseName
                            )
                        },
                        clearBackupShares = {
                            clearPrivateBackupShareArtifacts(
                                File(cacheDir, "backup-share"),
                                record.databaseName
                            )
                        },
                        clearRestTimers = {
                            timerController.clearAccount(
                                record.databaseName,
                                record.sessionGeneration
                            )
                        },
                        clearLiveState = {
                            clearCloudAccountLiveState(record.userId)
                        },
                        clearGarminState = {
                            garminManager.clearCloudAccountLocalState(
                                record.userId,
                                record.sessionGeneration
                            )
                        },
                        clearJournal = cloudAccountDeletionJournal::clear
                    )
                }
            }
        }
        pendingLocalProfileDeletion?.let { record ->
            applicationScope.launch(Dispatchers.IO) {
                clearPendingLocalProfileDeletion(record)
            }
        }
        garminManager.initialize()
        nativePushManager.initialize()
    }

    fun repositoryFor(session: AccountSession?): GymRepository {
        val logicalDatabaseName = session?.databaseName() ?: "gym_database"
        val physicalDatabaseName = when (session) {
            is AccountSession.Local -> localDatabaseBindingStore.physicalDatabaseName(session)
            else -> logicalDatabaseName
        }
        val repository = repositoryForDatabaseNames(logicalDatabaseName, physicalDatabaseName)
        repository.bindLiveWorkoutReservationGuard(
            sidecarStore = liveWorkoutSidecarStore.takeIf { session is AccountSession.Cloud },
            userId = (session as? AccountSession.Cloud)?.userId
        )
        if (session is AccountSession.Local) {
            // Force Room to create/open the exact journal-bound file before clearing the
            // durable one-shot creation marker. A process death before this point resumes
            // only through the matching auth + saved-profile identity on the next launch.
            repository.openDatabaseForAccountActivation()
            check(localDatabaseBindingStore.finalizeMaterializedSession(session)) {
                "The local database activation journal could not be finalized."
            }
        }
        return repository
    }

    suspend fun deleteCurrentLocalProfile(expectedSession: AccountSession.Local): Boolean =
        kotlinx.coroutines.withContext(Dispatchers.IO) {
            val record = cloudAuthManager.prepareLocalProfileDeletion(expectedSession)
            clearPendingLocalProfileDeletion(record)
        }

    internal fun clearCloudAccountLiveState(userId: String): Boolean {
        val liveCleared = liveWorkoutSidecarStore.clearCloudAccountLocalState(userId)
        val socialRequestsCleared =
            cloudAuthManager.clearCloudAccountSocialWorkoutRequestState(userId)
        return liveCleared && socialRequestsCleared
    }

    private fun clearPendingLocalProfileDeletion(
        record: PendingLocalProfileDeletion
    ): Boolean = recoverPendingLocalProfileDeletion(
        record = record,
        // Sidecar cleanup is intentionally part of this durable retry pipeline.
        // prepareLocalProfileDeletion never destroys it before auth is signed out.
        clearLiveSidecar = {
            cloudAuthManager.clearPendingLocalProfileDeletionSidecar(record)
        },
        clearDatabase = { captured ->
            repositories.remove(captured.logicalDatabaseName)
            GymDatabase.closeInstance(captured.physicalDatabaseName)
            deleteDatabase(captured.physicalDatabaseName) ||
                !getDatabasePath(captured.physicalDatabaseName).exists()
        },
        clearTrainingProfile = trainingProfileManager::clearAccountByDatabaseName,
        clearTrainingGuidance = trainingGuidanceManager::clearAccountByDatabaseName,
        clearCustomMedia = { owner -> ExerciseMediaStore.clearOwner(this, owner) },
        clearBackupShares = { owner ->
            clearPrivateBackupShareArtifacts(File(cacheDir, "backup-share"), owner)
        },
        clearRestTimers = restTimerController::clearLocalAccount,
        finalizeIdentity = cloudAuthManager::finalizeLocalProfileDeletion
    )

    private fun materializeLocalDatabaseForAuthentication(databaseName: String): Boolean =
        runCatching {
            repositoryForDatabaseNames(databaseName, databaseName).openDatabaseForAccountActivation()
            getDatabasePath(databaseName).isFile
        }.getOrDefault(false)

    private fun rollbackNewLocalDatabaseForAuthentication(databaseName: String): Boolean {
        repositories.remove(databaseName)
        GymDatabase.closeInstance(databaseName)
        return deleteDatabase(databaseName) || !getDatabasePath(databaseName).exists()
    }

    private fun repositoryForDatabaseNames(
        logicalDatabaseName: String,
        physicalDatabaseName: String
    ): GymRepository = repositories.computeIfAbsent(logicalDatabaseName) {
        GymRepository(GymDatabase.getInstance(this, physicalDatabaseName))
    }
}

val Context.gymApplication: GymApplication
    get() = applicationContext as GymApplication

private const val RETIRED_PHONE_WEAR_PREFERENCES = "phone_wear_sync"
