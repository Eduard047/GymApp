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
    primaryContainer = Color(0xFF203A78),
    onPrimaryContainer = Frost,
    secondary = Color(0xFFB8C8E8),
    onSecondary = Night,
    secondaryContainer = Color(0xFF26334A),
    onSecondaryContainer = Frost,
    tertiary = AmberNight,
    onTertiary = Night,
    tertiaryContainer = Color(0xFF4D3518),
    onTertiaryContainer = Frost,
    background = Night,
    surface = NightSurface,
    surfaceVariant = NightSurfaceAlt,
    onSurfaceVariant = FrostMuted,
    onSurface = Frost,
    onBackground = Frost,
    outline = Color(0xFF455368),
    outlineVariant = Color(0xFF2D3A4D)
)

private val LightColorScheme = lightColorScheme(
    primary = Cobalt,
    onPrimary = Color.White,
    primaryContainer = CobaltSoft,
    onPrimaryContainer = Navy,
    secondary = Navy,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFE7EBF2),
    onSecondaryContainer = Ink,
    tertiary = Amber,
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFFFE8C9),
    onTertiaryContainer = Ink,
    background = Canvas,
    surface = Paper,
    surfaceVariant = Mist,
    onSurfaceVariant = InkMuted,
    onSurface = Ink,
    onBackground = Ink,
    outline = Color(0xFFC8C2B6),
    outlineVariant = Color(0xFFDDD7CB)
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
