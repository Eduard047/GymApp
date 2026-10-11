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
 * Solid primary actions. In the dark appearance `colorScheme.primary` is the pale Active Current
 * `#8BB9FF`, which is right for text, icons, and marks but fails as a fill with a white label.
 * Filled primary controls therefore use the dedicated dark fill `#2E72D2` with white content
 * (4.7:1), matching iOS and the web app; the light appearance keeps `colorScheme.primary` /
 * `onPrimary` (`#216BD7` with white, 5.1:1) unchanged.
 */

/** Container of a solid primary control (button, FAB). */
@Composable
fun primaryActionContainerColor(): Color =
    if (isSystemInDarkTheme()) BrandFillNight else MaterialTheme.colorScheme.primary

/** Label/icon color on a solid primary control. */
@Composable
fun primaryActionContentColor(): Color =
    if (isSystemInDarkTheme()) Color.White else MaterialTheme.colorScheme.onPrimary

/** Default colors of a filled primary [Button]; light appearance is identical to Material's default. */
@Composable
fun primaryButtonColors(): ButtonColors =
    if (isSystemInDarkTheme()) {
        ButtonDefaults.buttonColors(
            containerColor = primaryActionContainerColor(),
            contentColor = primaryActionContentColor()
        )
    } else {
        ButtonDefaults.buttonColors()
    }

/** Default colors of a filled primary icon button. */
@Composable
fun primaryFilledIconButtonColors(): IconButtonColors =
    if (isSystemInDarkTheme()) {
        IconButtonDefaults.filledIconButtonColors(
            containerColor = primaryActionContainerColor(),
            contentColor = primaryActionContentColor()
        )
    } else {
        IconButtonDefaults.filledIconButtonColors()
    }

/**
 * Drop-in for `androidx.compose.material3.Button` whose default colors follow [primaryButtonColors].
 * Import this instead of the Material one wherever a plain filled primary button is wanted.
 */
@Composable
fun Button(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    shape: Shape = ButtonDefaults.shape,
    colors: ButtonColors = primaryButtonColors(),
    elevation: ButtonElevation? = ButtonDefaults.buttonElevation(),
    border: BorderStroke? = null,
    contentPadding: PaddingValues = ButtonDefaults.ContentPadding,
    interactionSource: MutableInteractionSource? = null,
    content: @Composable RowScope.() -> Unit
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
