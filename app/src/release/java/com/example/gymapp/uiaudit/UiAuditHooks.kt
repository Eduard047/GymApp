package com.example.gymapp.uiaudit

import android.content.Intent
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController

/** Non-debug build types ship no UI-audit capture hooks; every entry point is a no-op. */
object UiAuditHooks {
    val isActive: Boolean get() = false

    @Suppress("UNUSED_PARAMETER")
    fun handleIntent(activity: AppCompatActivity, intent: Intent?) = Unit

    @Suppress("UNUSED_PARAMETER")
    @Composable
    fun RouteEffect(navController: NavHostController) = Unit
}
