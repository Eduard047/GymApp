package com.example.gymapp

import android.app.Application
import android.content.Context
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.util.LanguageManager
import com.example.gymapp.util.RestTimerController
import com.example.gymapp.util.TrainingProfileManager

class GymApplication : Application() {
    val database: GymDatabase by lazy { GymDatabase.getInstance(this) }
    val repository: GymRepository by lazy { GymRepository(database) }
    val languageManager: LanguageManager by lazy { LanguageManager(this) }
    val trainingProfileManager: TrainingProfileManager by lazy { TrainingProfileManager(this) }
    val restTimerController: RestTimerController by lazy { RestTimerController(this) }
}

val Context.gymApplication: GymApplication
    get() = applicationContext as GymApplication

