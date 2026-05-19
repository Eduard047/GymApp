package com.example.gymapp

import android.app.Application
import android.content.Context
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAuthManager
import com.example.gymapp.auth.databaseName
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.util.LanguageManager
import com.example.gymapp.util.RestTimerController
import com.example.gymapp.util.TrainingProfileManager

class GymApplication : Application() {
    private val repositories = mutableMapOf<String, GymRepository>()
    val legacyRepository: GymRepository by lazy { repositoryFor(null) }
    val cloudAuthManager: CloudAuthManager by lazy { CloudAuthManager(this) }
    val languageManager: LanguageManager by lazy { LanguageManager(this) }
    val trainingProfileManager: TrainingProfileManager by lazy { TrainingProfileManager(this) }
    val restTimerController: RestTimerController by lazy { RestTimerController(this) }

    fun repositoryFor(session: AccountSession?): GymRepository {
        val databaseName = session?.databaseName() ?: "gym_database"
        return repositories.getOrPut(databaseName) {
            GymRepository(GymDatabase.getInstance(this, databaseName))
        }
    }
}

val Context.gymApplication: GymApplication
    get() = applicationContext as GymApplication

