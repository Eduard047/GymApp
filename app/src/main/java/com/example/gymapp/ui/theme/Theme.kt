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
    primary = SageGlow,
    onPrimary = Night,
    primaryContainer = Color(0xFF214C40),
    onPrimaryContainer = Frost,
    secondary = SkyGlow,
    onSecondary = Night,
    secondaryContainer = Color(0xFF183D5E),
    onSecondaryContainer = Frost,
    tertiary = ClayGlow,
    onTertiary = Night,
    tertiaryContainer = Color(0xFF4A2B1A),
    onTertiaryContainer = Frost,
    background = Night,
    surface = NightSurface.copy(alpha = 0.92f),
    surfaceVariant = NightSurfaceAlt.copy(alpha = 0.9f),
    onSurfaceVariant = FrostMuted,
    onSurface = Frost,
    onBackground = Frost,
    outline = Color(0xFF4E6A7A),
    outlineVariant = Color(0xFF304354)
)

private val LightColorScheme = lightColorScheme(
    primary = SageGreen,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFDDF4EB),
    onPrimaryContainer = InkBlue,
    secondary = SlateBlue,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFDDEEF7),
    onSecondaryContainer = Ink,
    tertiary = ClayOrange,
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFF7DDCF),
    onTertiaryContainer = Ink,
    background = Color(0xFFEAF1F5),
    surface = Cloud.copy(alpha = 0.94f),
    surfaceVariant = Sand.copy(alpha = 0.88f),
    onSurfaceVariant = Color(0xFF5B6975),
    onSurface = Ink,
    onBackground = Ink,
    outline = Color(0xFFB3C2CB),
    outlineVariant = Color.White
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
