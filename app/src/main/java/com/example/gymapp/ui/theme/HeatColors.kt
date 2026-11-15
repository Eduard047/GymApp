package com.example.gymapp.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import kotlin.math.ceil
import kotlin.math.min

/**
 * One neutral-to-system-blue scale shared by the activity heatmap and the muscle map (and iOS `GymTheme.heat*`,
 * PWA `--heat-0..4`). Step 0 is empty, steps 1-4 are load. Every step is an opaque colour: light
 * mode gets darker with more load, dark mode gets lighter. The legend uses the same steps as the
 * cells, so swatches and cells always match.
 */
object HeatStepColors {
    const val STEPS = 5

    private val lightFill = listOf(
        Color(0xFFE5E5EA), Color(0xFFCCE4FF), Color(0xFF99C9FF), Color(0xFF4DA3FF), Color(0xFF007AFF)
    )
    private val darkFill = listOf(
        Color(0xFF2C2C2E), Color(0xFF0B3A6E), Color(0xFF0A5AAE), Color(0xFF0A73E6), Color(0xFF0A84FF)
    )

    // Light: black on every step (5.2:1 on the darkest). Dark: white on steps 0-3 (>= 4.56:1), black
    // on the brightest step 4 (5.76:1; white would be 3.65:1).
    private val lightText = listOf(
        Color(0xFF000000), Color(0xFF000000), Color(0xFF000000), Color(0xFF000000), Color(0xFF000000)
    )
    private val darkText = listOf(
        Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0xFF000000)
    )

    /** Today marker: system-blue mark per appearance (drawn outside the cell). */
    private val lightRing = SystemBlue
    private val darkRing = SystemBlueNight

    fun fill(step: Int, dark: Boolean): Color =
        (if (dark) darkFill else lightFill)[step.coerceIn(0, STEPS - 1)]

    fun text(step: Int, dark: Boolean): Color =
        (if (dark) darkText else lightText)[step.coerceIn(0, STEPS - 1)]

    fun ring(dark: Boolean): Color = if (dark) darkRing else lightRing

    /** Maps a 0..1 intensity to a step: (0,.25] -> 1, (.25,.5] -> 2, (.5,.75] -> 3, (.75,1] -> 4. */
    fun step(intensity: Float): Int =
        if (intensity <= 0f) 0 else min(4, ceil(intensity * 4.0 - 1e-9).toInt())

    @Composable
    fun fill(step: Int): Color = fill(step, isSystemInDarkTheme())

    @Composable
    fun text(step: Int): Color = text(step, isSystemInDarkTheme())

    @Composable
    fun ring(): Color = ring(isSystemInDarkTheme())

    /** Hairline that keeps the otherwise near-panel step 0 visible. */
    @Composable
    fun emptyOutline(): Color = if (isSystemInDarkTheme()) HeroOutlineNight else HeroOutline
}
