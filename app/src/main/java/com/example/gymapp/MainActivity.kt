package com.example.gymapp

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.example.gymapp.navigation.GymAppRoot
import com.example.gymapp.ui.theme.GymAppTheme
import kotlinx.coroutines.launch

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
        handleAuthRedirect(intent)

        enableEdgeToEdge()
        setContent {
            GymAppTheme {
                GymAppRoot(
                    repositoryProvider = app::repositoryFor,
                    authManager = app.cloudAuthManager,
                    languageManager = app.languageManager,
                    restTimerController = app.restTimerController
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAuthRedirect(intent)
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

    private fun handleAuthRedirect(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != "com.setforge.gymapp" || uri.host != "auth" || uri.path != "/callback") {
            return
        }

        val app = application as GymApplication
        app.cloudAuthManager.setLoading(true)
        lifecycleScope.launch {
            runCatching {
                app.cloudAuthManager.completeEmailConfirmation(uri)
            }.onSuccess {
                Toast.makeText(
                    this@MainActivity,
                    "Email confirmed. You're logged in.",
                    Toast.LENGTH_LONG
                ).show()
            }.onFailure { throwable ->
                app.cloudAuthManager.setMessage(
                    throwable.message ?: "Email confirmation failed. Try logging in again."
                )
            }
        }
    }
}
