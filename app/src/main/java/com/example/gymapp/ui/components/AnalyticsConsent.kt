package com.example.gymapp.ui.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.example.gymapp.GymApplication
import com.example.gymapp.R
import com.example.gymapp.analytics.ConversionAnalytics

@Composable
internal fun rememberConversionAnalytics(): ConversionAnalytics =
    (LocalContext.current.applicationContext as GymApplication).conversionAnalytics

/**
 * One-time ad-measurement consent, shown on first launch (before sign-in, so sign-up can be counted)
 * once the intro has left and no first-run tutorial is showing or due (never two overlays at once).
 * Two equal-weight choices; it cannot be dismissed without choosing. Never
 * shown in builds that cannot measure. The same choice can be changed later in Settings.
 */
@Composable
fun AnalyticsConsentDialog(
    conversionAnalytics: ConversionAnalytics,
    introVisible: Boolean,
    tutorialPending: Boolean
) {
    val consent by conversionAnalytics.consent.collectAsState()
    if (introVisible || tutorialPending || consent != null || !conversionAnalytics.available) return
    AlertDialog(
        onDismissRequest = {},
        title = { Text(text = stringResource(R.string.analytics_consent_title)) },
        text = { Text(text = stringResource(R.string.analytics_consent_body)) },
        confirmButton = {
            TextButton(onClick = { conversionAnalytics.setConsent(true) }) {
                Text(text = stringResource(R.string.analytics_consent_allow))
            }
        },
        dismissButton = {
            TextButton(onClick = { conversionAnalytics.setConsent(false) }) {
                Text(text = stringResource(R.string.analytics_consent_deny))
            }
        }
    )
}
