package com.example.gymapp.ui.components

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource

/**
 * The DESIGN.md `Materials (glass)` layers. [Bar] is the bottom/tab bar, [Sheet] a sheet, menu or
 * popover, [Chip] a floating pill such as a toast.
 */
enum class GymGlassMaterial { Bar, Sheet, Chip }

/** The numbers of one material in one theme: blur radius, fill opacity and which colour is the fill. */
internal data class GymGlassSpec(
    val blurRadius: Dp,
    val fillAlpha: Float,
    /** True when the fill is the screen `background` colour, false when it is `surface`. */
    val fillFromBackground: Boolean
)

/** `materials:` in DESIGN.md. Bar fills with `background` in light and `surface` in dark. */
internal fun gymGlassSpec(material: GymGlassMaterial, isDark: Boolean): GymGlassSpec = when (material) {
    GymGlassMaterial.Bar -> GymGlassSpec(
        blurRadius = 20.dp,
        fillAlpha = if (isDark) 0.78f else 0.80f,
        fillFromBackground = !isDark
    )
    GymGlassMaterial.Sheet -> GymGlassSpec(
        blurRadius = 28.dp,
        fillAlpha = if (isDark) 0.84f else 0.86f,
        fillFromBackground = false
    )
    GymGlassMaterial.Chip -> GymGlassSpec(
        blurRadius = 14.dp,
        fillAlpha = if (isDark) 0.66f else 0.70f,
        fillFromBackground = false
    )
}

/** RenderEffect blur needs Android 12 (API 31); below it, or with reduced transparency, glass stays solid. */
internal const val GymGlassMinSdk = 31

/**
 * Whether glass may blur at all. The decision is deliberately free of layout: callers keep the same
 * size and position either way and only swap the fill.
 */
internal fun gymGlassBlurEnabled(sdkInt: Int, reduceTransparency: Boolean): Boolean =
    sdkInt >= GymGlassMinSdk && !reduceTransparency

/** The fill colour of [spec] over the given theme colours, before the opacity is applied. */
internal fun gymGlassFillBase(spec: GymGlassSpec, background: Color, surface: Color): Color =
    if (spec.fillFromBackground) background else surface

/** Holds the blur source shared by one glass source and the glass layers that read it. */
@Composable
fun rememberGymHazeState(): HazeState = remember { HazeState() }

/**
 * Android has no system "reduce transparency" switch, so battery saver is the signal that the user
 * wants the GPU to do less; it is observed live and glass falls back to solid while it is on.
 */
@Composable
fun rememberGymReduceTransparency(): Boolean {
    val context = LocalContext.current
    var powerSave by remember(context) { mutableStateOf(context.isPowerSaveOn()) }
    DisposableEffect(context) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context, intent: Intent) {
                powerSave = receiverContext.isPowerSaveOn()
            }
        }
        runCatching {
            ContextCompat.registerReceiver(
                context,
                receiver,
                IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED),
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
        }
        powerSave = context.isPowerSaveOn()
        onDispose { runCatching { context.unregisterReceiver(receiver) } }
    }
    return powerSave
}

private fun Context.isPowerSaveOn(): Boolean =
    runCatching { (getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isPowerSaveMode == true }
        .getOrDefault(false)

/** True when [state] exists and this device and setting allow a live blur. */
@Composable
fun rememberGymGlassActive(state: HazeState?): Boolean {
    if (state == null) return false
    val reduceTransparency = rememberGymReduceTransparency()
    return gymGlassBlurEnabled(Build.VERSION.SDK_INT, reduceTransparency)
}

/**
 * Marks the content that scrolls beneath glass as the blur source. A no-op when glass is inactive, so
 * the source layer is only recorded while something is actually blurring it.
 */
@Composable
fun Modifier.gymGlassSource(state: HazeState?): Modifier =
    if (state != null && rememberGymGlassActive(state)) this.hazeSource(state) else this

/**
 * Draws [material] behind this node: a backdrop blur of the [gymGlassSource] content with the material's
 * fill at its opacity, clipped to [shape]. Inactive glass returns the modifier unchanged; the caller
 * keeps its existing solid surface and shadow (see [rememberGymGlassActive]). No gradients, no noise.
 */
@Composable
fun Modifier.gymGlass(
    state: HazeState?,
    material: GymGlassMaterial,
    shape: Shape = RectangleShape
): Modifier {
    if (state == null || !rememberGymGlassActive(state)) return this
    val colors = MaterialTheme.colorScheme
    val spec = gymGlassSpec(material, isDark = colors.background.luminance() < 0.5f)
    val base = gymGlassFillBase(spec, background = colors.background, surface = colors.surface)
    val style = remember(spec, base) {
        HazeStyle(
            backgroundColor = base,
            tint = HazeTint(base.copy(alpha = spec.fillAlpha)),
            blurRadius = spec.blurRadius,
            noiseFactor = 0f
        )
    }
    return this.clip(shape).hazeEffect(state = state, style = style)
}
