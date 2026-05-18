package com.example.gymapp

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import com.example.gymapp.navigation.GymAppRoot
import com.example.gymapp.ui.theme.GymAppTheme

class MainActivity : AppCompatActivity() {
    private val requestNotificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val app = application as GymApplication
        runCatching {
            app.languageManager.applySavedLanguage()
        }.onFailure { throwable ->
            Log.e("MainActivity", "Failed to apply saved language", throwable)
        }

        ensureNotificationPermission()

        enableEdgeToEdge()
        setContent {
            GymAppTheme {
                GymAppRoot(
                    repository = app.repository,
                    authManager = app.cloudAuthManager,
                    languageManager = app.languageManager,
                    restTimerController = app.restTimerController
                )
            }
        }
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }

        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
