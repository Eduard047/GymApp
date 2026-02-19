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
    primary = EnergyBlue,
    onPrimary = Color.White,
    primaryContainer = Color(0xFF1F3F5E),
    onPrimaryContainer = Color.White,
    secondary = TurboOrangeDark,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFF4A2A1A),
    onSecondaryContainer = Color.White,
    tertiary = AccentPurpleDark,
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFF3B3266),
    onTertiaryContainer = Color.White,
    background = SurfaceDark,
    surface = SurfaceVariantDark,
    surfaceVariant = Color(0xFF1A2E4A),
    onSurfaceVariant = Color.White,
    onSurface = Color.White,
    onBackground = Color.White
)

private val LightColorScheme = lightColorScheme(
    primary = EnergyBlue,
    onPrimary = androidx.compose.ui.graphics.Color.White,
    secondary = TurboOrange,
    tertiary = AccentPurple,
    background = SurfaceLight,
    surface = androidx.compose.ui.graphics.Color.White,
    surfaceVariant = SurfaceVariantLight,
    onSurface = OnSurfaceLight,
    onBackground = OnSurfaceLight
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
        content = content
    )
}
