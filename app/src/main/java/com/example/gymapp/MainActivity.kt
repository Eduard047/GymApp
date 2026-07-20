package com.example.gymapp

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.example.gymapp.auth.AuthCallbackKind
import com.example.gymapp.auth.authErrorText
import com.example.gymapp.navigation.GymAppRoot
import com.example.gymapp.ui.theme.GymAppTheme
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val app = application as GymApplication
        runCatching {
            app.languageManager.applySavedLanguage()
        }.onFailure { throwable ->
            Log.e("MainActivity", "Failed to apply saved language", throwable)
        }

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

    private fun handleAuthRedirect(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme != BuildConfig.AUTH_CALLBACK_SCHEME ||
            uri.host != "auth" ||
            uri.path != "/callback"
        ) {
            return
        }
        // Do not retain token-bearing implicit callback data on the Activity intent.
        intent.data = null

        val app = application as GymApplication
        app.cloudAuthManager.setLoading(true)
        lifecycleScope.launch {
            runCatching {
                app.cloudAuthManager.completeAuthCallback(uri)
            }.onSuccess { result ->
                val messageResource = when (result.kind) {
                    AuthCallbackKind.PasswordRecovery ->
                        R.string.auth_recovery_verified
                    AuthCallbackKind.EmailConfirmation ->
                        R.string.auth_message_email_confirmed
                }
                Toast.makeText(
                    this@MainActivity,
                    getString(messageResource),
                    Toast.LENGTH_LONG
                ).show()
            }.onFailure { throwable ->
                app.cloudAuthManager.setMessage(
                    authErrorText(throwable, R.string.auth_message_callback_failed)
                )
            }
        }
    }
}
