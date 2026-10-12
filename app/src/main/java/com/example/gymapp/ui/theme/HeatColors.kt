package com.example.gymapp.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import kotlin.math.ceil
import kotlin.math.min

/**
 * One blue scale shared by the activity heatmap and the muscle map (and iOS `GymTheme.heat*`,
 * PWA `--heat-0..4`). Step 0 is empty, steps 1-4 are load. Every step is an opaque colour: light
 * mode gets darker with more load, dark mode gets lighter. The legend uses the same steps as the
 * cells, so swatches and cells always match.
 */
object HeatStepColors {
    const val STEPS = 5

    private val lightFill = listOf(
        Color(0xFFFFFFFF), Color(0xFFC4D9F8), Color(0xFF7FAAEB), Color(0xFF216BD7), Color(0xFF164396)
    )
    private val darkFill = listOf(
        Color(0xFF172C47), Color(0xFF1E4378), Color(0xFF2B63B0), Color(0xFF4A8EEF), Color(0xFF7FB2FF)
    )

    // Steps 0-2 use the label colour, steps 3-4 the inverse; every pair is >= 4.5:1.
    private val lightText = listOf(
        Color(0xFF10233F), Color(0xFF10233F), Color(0xFF10233F), Color(0xFFFFFFFF), Color(0xFFFFFFFF)
    )
    private val darkText = listOf(
        Color(0xFFF2F6FC), Color(0xFFF2F6FC), Color(0xFFF2F6FC), Color(0xFF071321), Color(0xFF071321)
    )

    /** Today marker: Active Current mark per appearance (drawn outside the cell). */
    private val lightRing = Color(0xFF216BD7)
    private val darkRing = Color(0xFF7FB2FF)

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
