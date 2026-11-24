package com.example.gymapp.health

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.AppleBackButton
import com.example.gymapp.ui.components.AppleNavigationBar
import com.example.gymapp.ui.theme.GymAppTheme
import com.example.gymapp.util.withAppLanguage

/**
 * Shown by Health Connect when the user asks why GymApp reads workout data (the
 * ACTION_SHOW_PERMISSIONS_RATIONALE intent, and the Android 14 VIEW_PERMISSION_USAGE alias).
 * It displays text only, takes no input and reads nothing from the incoming intent.
 *
 * Drawn with the app theme: a title bar with Back, a scrolling top-aligned text column inside the
 * system-bar insets, and system-bar icons that follow light/dark. The text follows the in-app
 * language on every Android version.
 *
 * Strings: health_data_title (bar), health_import_rationale_title and health_import_rationale_body
 * (EN / UK / RU).
 */
class HealthPermissionRationaleActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: Context) {
        // Not an AppCompat activity, so the in-app language is applied by hand (below Android 13).
        super.attachBaseContext(newBase.withAppLanguage())
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Transparent system bars whose icons follow the light/dark theme.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            GymAppTheme {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.background)
                ) {
                    AppleNavigationBar(
                        title = stringResource(R.string.health_data_title),
                        leading = {
                            AppleBackButton(
                                onClick = { finish() },
                                contentDescription = stringResource(R.string.cd_back)
                            )
                        }
                    )
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f)
                            .verticalScroll(rememberScrollState())
                            .navigationBarsPadding()
                            .padding(horizontal = 20.dp, vertical = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Text(
                            text = stringResource(R.string.health_import_rationale_title),
                            style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold),
                            color = MaterialTheme.colorScheme.onBackground
                        )
                        Text(
                            text = stringResource(R.string.health_import_rationale_body),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}
