package com.example.gymapp

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.lifecycle.lifecycleScope
import com.example.gymapp.auth.AuthCallbackKind
import com.example.gymapp.auth.authErrorText
import com.example.gymapp.data.repository.IncomingSharedWorkoutUrl
import com.example.gymapp.data.repository.SharedWorkoutLink
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

        handleIncomingIntent(intent)

        configureEdgeToEdge()
        setContent {
            GymAppTheme {
                GymAppRoot(
                    repositoryProvider = app::repositoryFor,
                    authManager = app.cloudAuthManager,
                    languageManager = app.languageManager,
                    restTimerController = app.restTimerController,
                    sharedWorkoutInbox = app.sharedWorkoutInbox,
                    pushManager = app.pushManager,
                    pushNavigationInbox = app.pushNavigationInbox
                )
            }
        }
    }

    private fun configureEdgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val isDarkTheme =
            resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
                Configuration.UI_MODE_NIGHT_YES
        WindowCompat.getInsetsController(window, window.decorView).run {
            isAppearanceLightStatusBars = !isDarkTheme
            isAppearanceLightNavigationBars = !isDarkTheme
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        (application as GymApplication).pushManager.refreshSystemState()
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent != null && intent.action?.startsWith(PUSH_TAP_ACTION_PREFIX) == true) {
            val app = application as GymApplication
            app.pushManager.consumeNotificationTap(intent)?.let(app.pushNavigationInbox::offer)
            return
        }
        val uri = intent?.data
        if (uri != null) {
            when (
                val sharedWorkout = SharedWorkoutLink.parseIncomingUrl(
                    rawUrl = uri.toString(),
                    customScheme = BuildConfig.AUTH_CALLBACK_SCHEME
                )
            ) {
                IncomingSharedWorkoutUrl.NotSharedWorkout -> Unit
                IncomingSharedWorkoutUrl.InvalidSharedWorkout -> {
                    intent.data = null
                    Toast.makeText(
                        this,
                        getString(R.string.message_shared_workout_invalid),
                        Toast.LENGTH_LONG
                    ).show()
                    return
                }
                is IncomingSharedWorkoutUrl.Valid -> {
                    // Do not retain a potentially large attacker-controlled template URI on the
                    // exported Activity. The bounded immutable plan is handed to the UI instead.
                    intent.data = null
                    (application as GymApplication).sharedWorkoutInbox.offer(sharedWorkout.plan)
                    return
                }
            }
        }
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

private const val PUSH_TAP_ACTION_PREFIX = "com.setforge.gymapp.action.PUSH_TAP."
