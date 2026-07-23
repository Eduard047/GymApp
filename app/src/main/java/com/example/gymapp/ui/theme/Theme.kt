package com.example.gymapp.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val DarkColorScheme = darkColorScheme(
    primary = CobaltNight,
    onPrimary = Night,
    primaryContainer = Color(0xFF173D70),
    onPrimaryContainer = Frost,
    secondary = Color(0xFF77DDB7),
    onSecondary = Night,
    secondaryContainer = Color(0xFF163F3A),
    onSecondaryContainer = Frost,
    tertiary = AmberNight,
    onTertiary = Night,
    tertiaryContainer = Color(0xFF3A315F),
    onTertiaryContainer = Frost,
    background = Night,
    surface = NightSurface,
    surfaceVariant = NightSurfaceAlt,
    onSurfaceVariant = FrostMuted,
    onSurface = Frost,
    onBackground = Frost,
    outline = Color(0xFF49617D),
    outlineVariant = Color(0xFF263E59)
)

private val LightColorScheme = lightColorScheme(
    primary = Cobalt,
    onPrimary = Color.White,
    primaryContainer = CobaltSoft,
    onPrimaryContainer = Navy,
    secondary = RecoveryMint,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFE6FBF4),
    onSecondaryContainer = Ink,
    tertiary = MomentumViolet,
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFEDE9FF),
    onTertiaryContainer = Ink,
    background = Canvas,
    surface = Paper,
    surfaceVariant = Mist,
    onSurfaceVariant = InkMuted,
    onSurface = Ink,
    onBackground = Ink,
    outline = Color(0xFFB7C4D7),
    outlineVariant = Color(0xFFDCE5F2)
)

@Composable
fun GymAppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }

        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        shapes = Shapes,
        content = content
    )
}
