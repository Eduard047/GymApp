package com.example.gymapp.wear.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material3.ColorScheme
import androidx.wear.compose.material3.MaterialTheme

/** Spec §2 tokens: the phone's dark palette, shared by both watches. */
object WatchColors {
    val Background = Color(0xFF000000)
    val Surface = Color(0xFF1C1C1E)
    val SurfaceHigh = Color(0xFF2C2C2E)
    val Accent = Color(0xFF0A84FF)
    val AccentTonal = Color(0xFF02203D)
    val Text = Color(0xFFFFFFFF)
    val TextSecondary = Color(0xFFAEAEB2)
    val Separator = Color(0xFF38383A)
    val Destructive = Color(0xFFFF453A)
    val DestructiveTonal = Color(0xFF330E0C)
    val Success = Color(0xFF30D158)
    val Warning = Color(0xFFFF9F0A)

    private val zones = listOf(
        Color(0xFF8E8E93),
        Color(0xFF64D2FF),
        Color(0xFF30D158),
        Color(0xFFFF9F0A),
        Color(0xFFFF453A)
    )

    fun zone(zone: Int): Color = zones[(zone - 1).coerceIn(0, zones.lastIndex)]
}

private val GymWatchColorScheme = ColorScheme(
    primary = WatchColors.Accent,
    primaryDim = WatchColors.Accent,
    primaryContainer = WatchColors.AccentTonal,
    onPrimary = WatchColors.Text,
    onPrimaryContainer = WatchColors.Text,
    secondary = WatchColors.Accent,
    secondaryDim = WatchColors.Accent,
    secondaryContainer = WatchColors.SurfaceHigh,
    onSecondary = WatchColors.Text,
    onSecondaryContainer = WatchColors.Text,
    tertiary = WatchColors.Accent,
    tertiaryDim = WatchColors.Accent,
    tertiaryContainer = WatchColors.SurfaceHigh,
    onTertiary = WatchColors.Text,
    onTertiaryContainer = WatchColors.Text,
    surfaceContainerLow = WatchColors.Surface,
    surfaceContainer = WatchColors.Surface,
    surfaceContainerHigh = WatchColors.SurfaceHigh,
    onSurface = WatchColors.Text,
    onSurfaceVariant = WatchColors.TextSecondary,
    outline = WatchColors.Separator,
    outlineVariant = WatchColors.Separator,
    background = WatchColors.Background,
    onBackground = WatchColors.Text,
    error = WatchColors.Destructive,
    errorDim = WatchColors.Destructive,
    errorContainer = WatchColors.DestructiveTonal,
    onError = WatchColors.Background,
    onErrorContainer = WatchColors.Destructive
)

@Composable
fun GymWatchTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = GymWatchColorScheme, content = content)
}

/** All numerals are tabular (spec §2 Typography). */
fun TextStyle.tabular(): TextStyle = copy(fontFeatureSettings = "tnum")

/** Small SF-style glyphs (24dp grid), tinted by [androidx.wear.compose.material3.Icon]. */
object WatchIcons {
    val Heart: ImageVector = glyph(
        "HeartFill",
        "M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5 2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09" +
            "C13.09,3.81 14.76,3 16.5,3 19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z"
    )
    val HeartSlash: ImageVector = ImageVector.Builder("HeartSlash", 24.dp, 24.dp, 24f, 24f)
        .addPath(
            pathData = addPathNodes(
                "M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5 2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09" +
                    "C13.09,3.81 14.76,3 16.5,3 19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z"
            ),
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2f
        )
        .addPath(
            pathData = addPathNodes("M3,3L21,21"),
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2f,
            strokeLineCap = StrokeCap.Round
        )
        .build()
    val Play: ImageVector = glyph("Play", "M8,5v14l11,-7z")
    val Check: ImageVector = glyph("Check", "M9,16.17L4.83,12l-1.42,1.41L9,19 21,7l-1.41,-1.41z")
    val Trash: ImageVector = glyph(
        "Trash",
        "M6,19c0,1.1 0.9,2 2,2h8c1.1,0 2,-0.9 2,-2V7H6v12zM19,4h-3.5l-1,-1h-5l-1,1H5v2h14V4z"
    )
    val Chevron: ImageVector = glyph("Chevron", "M10,6L8.59,7.41 13.17,12l-4.58,4.59L10,18l6,-6z")
    val Warning: ImageVector = glyph("Warning", "M1,21h22L12,2 1,21zM13,18h-2v-2h2v2zM13,14h-2v-4h2v4z")

    private fun glyph(name: String, path: String): ImageVector =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
            .addPath(pathData = addPathNodes(path), fill = SolidColor(Color.Black))
            .build()
}
