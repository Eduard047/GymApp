package com.example.gymapp.ui.theme

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ButtonElevation
import androidx.compose.material3.IconButtonColors
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape

/*
 * Solid primary actions. `colorScheme.primary` is the text-safe accent blue (`#0062CC` light,
 * `#409CFF` dark: >= 4.6:1 on every surface), right for text and icons but not the Apple fill.
 * Filled primary controls therefore use the system blue fill per appearance (`#007AFF` light,
 * `#0A84FF` dark) with a white label (4.02:1 / 3.65:1, filled-button labels need >= 3:1), matching iOS
 * and the web app.
 */

/**
 * DESIGN.md `accent-mark`: chart lines, rings, today marks and progress fills. System blue per
 * appearance (`#007AFF` light, `#0A84FF` dark); `colorScheme.primary` stays for text and icons.
 */
@Composable
fun accentMarkColor(): Color =
    if (isSystemInDarkTheme()) AccentMarkNight else SystemBlue

/** Container of a solid primary control (button, FAB). */
@Composable
fun primaryActionContainerColor(): Color =
    if (isSystemInDarkTheme()) BrandFillNight else BrandFill

/** Label/icon color on a solid primary control. */
@Composable
fun primaryActionContentColor(): Color = Color.White

/** Default colors of a filled primary [Button]. */
@Composable
fun primaryButtonColors(): ButtonColors =
    ButtonDefaults.buttonColors(
        containerColor = primaryActionContainerColor(),
        contentColor = primaryActionContentColor()
    )

/** Default colors of a filled primary icon button. */
@Composable
fun primaryFilledIconButtonColors(): IconButtonColors =
    IconButtonDefaults.filledIconButtonColors(
        containerColor = primaryActionContainerColor(),
        contentColor = primaryActionContentColor()
    )

/**
 * Drop-in for `androidx.compose.material3.Button` whose default colors follow [primaryButtonColors].
 * Import this instead of the Material one wherever a plain filled primary button is wanted.
 */
@Composable
fun Button(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    shape: Shape = GymCapsuleShape,
    colors: ButtonColors = primaryButtonColors(),
    elevation: ButtonElevation? = ButtonDefaults.buttonElevation(),
    border: BorderStroke? = null,
    contentPadding: PaddingValues = ButtonDefaults.ContentPadding,
    interactionSource: MutableInteractionSource? = null,
    content: @Composable RowScope.() -> Unit
) {
    // A label that wraps to two lines stays centred, as in [TintedButton].
    androidx.compose.runtime.CompositionLocalProvider(
        androidx.compose.material3.LocalTextStyle provides androidx.compose.material3.LocalTextStyle.current
            .copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    ) {
        androidx.compose.material3.Button(
            onClick = onClick,
            modifier = modifier,
            enabled = enabled,
            shape = shape,
            colors = colors,
            elevation = elevation,
            border = border,
            contentPadding = contentPadding,
            interactionSource = interactionSource,
            content = content
        )
    }
}

/** Colors of a [TintedButton]: accent 15% fill with an accent label (disabled: 7% fill, 38% label). */
@Composable
fun tintedButtonColors(): ButtonColors {
    val primary = MaterialTheme.colorScheme.primary
    return ButtonDefaults.buttonColors(
        containerColor = primary.copy(alpha = 0.15f),
        contentColor = primary,
        disabledContainerColor = primary.copy(alpha = 0.07f),
        disabledContentColor = primary.copy(alpha = 0.38f)
    )
}

/**
 * Secondary action: a borderless tinted capsule (same style as the active-workout footer "+ Set"),
 * the replacement for Material's outlined button. A caller may still pass [border] for a state that carries
 * meaning (e.g. a destructive confirmation).
 */
@Composable
fun TintedButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    shape: Shape = GymCapsuleShape,
    colors: ButtonColors = tintedButtonColors(),
    border: BorderStroke? = null,
    contentPadding: PaddingValues = ButtonDefaults.ContentPadding,
    interactionSource: MutableInteractionSource? = null,
    content: @Composable RowScope.() -> Unit
) {
    // A label that wraps to two lines stays centred (the button merges its own style into this one).
    androidx.compose.runtime.CompositionLocalProvider(
        androidx.compose.material3.LocalTextStyle provides androidx.compose.material3.LocalTextStyle.current
            .copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    ) {
        androidx.compose.material3.Button(
            onClick = onClick,
            modifier = modifier,
            enabled = enabled,
            shape = shape,
            colors = colors,
            elevation = null,
            border = border,
            contentPadding = contentPadding,
            interactionSource = interactionSource,
            content = content
        )
    }
}
