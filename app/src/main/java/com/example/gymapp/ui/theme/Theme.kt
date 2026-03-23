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
    primary = Frost,
    onPrimary = Night,
    primaryContainer = SlateBlue,
    onPrimaryContainer = Frost,
    secondary = SageGlow,
    onSecondary = Night,
    secondaryContainer = Color(0xFF1D4036),
    onSecondaryContainer = Frost,
    tertiary = ClayGlow,
    onTertiary = Night,
    tertiaryContainer = Color(0xFF4A2B1A),
    onTertiaryContainer = Frost,
    background = Night,
    surface = NightSurface,
    surfaceVariant = NightSurfaceAlt,
    onSurfaceVariant = FrostMuted,
    onSurface = Frost,
    onBackground = Frost,
    outline = Color(0xFF304858),
    outlineVariant = Color(0xFF213644)
)

private val LightColorScheme = lightColorScheme(
    primary = InkBlue,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFDCEAF4),
    onPrimaryContainer = InkBlue,
    secondary = SageGreen,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFD7E8E0),
    onSecondaryContainer = Ink,
    tertiary = ClayOrange,
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFF7DDCF),
    onTertiaryContainer = Ink,
    background = Mist,
    surface = Cloud,
    surfaceVariant = Sand,
    onSurfaceVariant = Color(0xFF5A6772),
    onSurface = Ink,
    onBackground = Ink,
    outline = Color(0xFFC3B5A4),
    outlineVariant = Color(0xFFE0D4C6)
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
