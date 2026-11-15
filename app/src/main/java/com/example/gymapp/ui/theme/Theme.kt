package com.example.gymapp.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.LocalIndication
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LocalRippleConfiguration
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val DarkColorScheme = darkColorScheme(
    primary = SystemBlueTextNight,
    onPrimary = Color.Black,
    primaryContainer = BlueSoftNight,
    onPrimaryContainer = Frost,
    secondary = RecoveryGreenNight,
    onSecondary = Color.Black,
    secondaryContainer = Color(0xFF20402A),
    onSecondaryContainer = Frost,
    tertiary = MomentumVioletNight,
    onTertiary = Color.Black,
    tertiaryContainer = Color(0xFF292946),
    onTertiaryContainer = Frost,
    error = DestructiveNight,
    onError = OnDestructiveNight,
    errorContainer = Color(0xFF4E2524),
    onErrorContainer = Frost,
    background = Night,
    surface = NightSurface,
    surfaceVariant = NightRaised,
    // Neutral surfaces never take a primary tint (no tonal-elevation blue).
    surfaceTint = Color.Transparent,
    // Dialogs, menus and date pickers read these roles; keep them on the raised-tile colour
    // instead of the stock Material violet-grey container.
    // Sheets use GymModalBottomSheet (solid surface container); these roles stay on the screen background.
    surfaceDim = Night,
    surfaceBright = NightRaised,
    surfaceContainerLowest = Night,
    surfaceContainerLow = Night,
    surfaceContainer = HeroTileNight,
    surfaceContainerHigh = HeroTileNight,
    surfaceContainerHighest = NightFill,
    inverseSurface = Mist,
    inverseOnSurface = Ink,
    inversePrimary = SystemBlue,
    onSurfaceVariant = FrostMuted,
    onSurface = Frost,
    onBackground = Frost,
    outline = NightOutline,
    outlineVariant = NightSeparator,
    scrim = Color.Black
)

private val LightColorScheme = lightColorScheme(
    primary = SystemBlueText,
    onPrimary = Color.White,
    primaryContainer = BlueSoft,
    onPrimaryContainer = Ink,
    secondary = RecoveryGreen,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFE3F7E8),
    onSecondaryContainer = Ink,
    tertiary = MomentumViolet,
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFEBEBFA),
    onTertiaryContainer = Ink,
    error = DestructiveLight,
    onError = Color.White,
    errorContainer = Color(0xFFFFE7E6),
    onErrorContainer = Ink,
    background = Canvas,
    surface = Paper,
    surfaceVariant = Mist,
    surfaceTint = Color.Transparent,
    // Dialogs, menus and date pickers read these roles; keep them on white instead of the stock
    // Material violet-grey container.
    // Sheets use GymModalBottomSheet (solid surface container); these roles stay on the screen background.
    surfaceDim = Mist,
    surfaceBright = Paper,
    surfaceContainerLowest = Paper,
    surfaceContainerLow = Canvas,
    surfaceContainer = Paper,
    surfaceContainerHigh = Paper,
    surfaceContainerHighest = Mist,
    inverseSurface = NightRaised,
    inverseOnSurface = Frost,
    inversePrimary = SystemBlueNight,
    onSurfaceVariant = InkMuted,
    onSurface = Ink,
    onBackground = Ink,
    outline = SeparatorLight,
    outlineVariant = Mist,
    scrim = Color.Black
)

@OptIn(ExperimentalMaterial3Api::class)
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
        shapes = Shapes
    ) {
        // No ripple anywhere: a flat press tint (focus keeps a steady tint) is the pressed state.
        CompositionLocalProvider(
            LocalIndication provides PressHighlight(MaterialTheme.colorScheme.onSurface),
            LocalRippleConfiguration provides null,
            content = content
        )
    }
}
