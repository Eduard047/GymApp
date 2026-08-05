package com.example.gymapp

import android.app.Application
import android.content.Context
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAuthManager
import com.example.gymapp.auth.LocalDatabaseBindingStore
import com.example.gymapp.auth.databaseName
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.SharedWorkoutInbox
import com.example.gymapp.garmin.GarminSyncManager
import com.example.gymapp.util.LanguageManager
import com.example.gymapp.util.RestTimerController
import com.example.gymapp.util.TrainingProfileManager
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
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val legacyRepository: GymRepository by lazy { repositoryFor(null) }
    val cloudAuthManager: CloudAuthManager by lazy { CloudAuthManager(this) }
    val languageManager: LanguageManager by lazy { LanguageManager(this) }
    val trainingProfileManager: TrainingProfileManager by lazy { TrainingProfileManager(this) }
    val restTimerController: RestTimerController by lazy { RestTimerController(this) }
    val garminSyncManager: GarminSyncManager by lazy { GarminSyncManager(this) }
    internal val sharedWorkoutInbox = SharedWorkoutInbox()

    override fun onCreate() {
        super.onCreate()
        deleteSharedPreferences(RETIRED_PHONE_WEAR_PREFERENCES)
        val authManager = cloudAuthManager
        val profileManager = trainingProfileManager
        val timerController = restTimerController
        applicationScope.launch(start = CoroutineStart.UNDISPATCHED) {
            authManager.authState.collect { state ->
                profileManager.switchAccount(state.session)
                timerController.switchAccount(state.session)
            }
        }
        garminSyncManager.initialize()
    }

    fun repositoryFor(session: AccountSession?): GymRepository {
        val logicalDatabaseName = session?.databaseName() ?: "gym_database"
        val physicalDatabaseName = when (session) {
            is AccountSession.Local -> localDatabaseBindingStore.physicalDatabaseName(session)
            else -> logicalDatabaseName
        }
        return repositories.computeIfAbsent(logicalDatabaseName) {
            GymRepository(GymDatabase.getInstance(this, physicalDatabaseName))
        }
    }
}

val Context.gymApplication: GymApplication
    get() = applicationContext as GymApplication

private const val RETIRED_PHONE_WEAR_PREFERENCES = "phone_wear_sync"
