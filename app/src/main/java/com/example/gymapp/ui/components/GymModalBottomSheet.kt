package com.example.gymapp.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.res.stringResource
import com.example.gymapp.R
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The DESIGN.md `Sheets` contract for every Android bottom sheet: 32 dp top radius, a 36x5 capsule
 * drag handle 8 dp from the top, content directly on a solid `surface` container, the themed scrim,
 * and `skipPartiallyExpanded` chosen per content (true for short confirms and fixed-height pickers).
 *
 * Enter and exit come from Material's anchored-draggable spring, which scales with the system
 * animator duration scale, so "remove animations" already removes the slide. On top of that, with
 * reduced motion the sheet cross-fades in over [GymMotion.FadeInMillis]. Back and predictive back
 * dismiss through [onDismissRequest]. Every sheet's content must still show its own visible
 * Close/Done/Cancel control for non-gesture users.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GymModalBottomSheet(
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    skipPartiallyExpanded: Boolean = false,
    sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = skipPartiallyExpanded),
    content: @Composable ColumnScope.() -> Unit
) {
    val colors = MaterialTheme.colorScheme
    val reduceMotion = rememberReduceMotion()
    val fadeIn = rememberSheetFadeIn(enabled = reduceMotion)
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        modifier = modifier.then(fadeIn),
        sheetState = sheetState,
        shape = GymSheetShape,
        containerColor = colors.surface,
        contentColor = colors.onSurface,
        tonalElevation = 0.dp,
        scrimColor = gymSheetScrimColor(isDark = colors.background.luminance() < 0.5f),
        dragHandle = { GymSheetDragHandle() }
    ) {
        content()
    }
}

/** `radii.sheet-top`: 32 dp on both top corners, square at the bottom edge. */
internal val GymSheetShape = RoundedCornerShape(topStart = 32.dp, topEnd = 32.dp)

internal val GymSheetHandleWidth: Dp = 36.dp
internal val GymSheetHandleHeight: Dp = 5.dp
internal val GymSheetHandleTopPadding: Dp = 8.dp

/** DESIGN `scrim`: rgba(7,19,33,0.40) in light, rgba(0,0,0,0.56) in dark. */
internal fun gymSheetScrimColor(isDark: Boolean): Color =
    if (isDark) Color(0f, 0f, 0f, 0.56f) else Color(7 / 255f, 19 / 255f, 33 / 255f, 0.40f)

@Composable
private fun GymSheetDragHandle() {
    Box(
        modifier = Modifier
            .padding(top = GymSheetHandleTopPadding, bottom = GymSheetHandleTopPadding)
            .size(width = GymSheetHandleWidth, height = GymSheetHandleHeight)
            .background(MaterialTheme.colorScheme.outline, CircleShape)
    )
}

/** Reduced motion: the whole sheet cross-fades in over 150 ms instead of relying on the slide. */
@Composable
private fun rememberSheetFadeIn(enabled: Boolean): Modifier {
    if (!enabled) return Modifier
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val alpha by animateFloatAsState(
        targetValue = if (shown) 1f else 0f,
        animationSpec = GymMotion.fadeInSpec(),
        label = "sheetReducedMotionFade"
    )
    return Modifier.graphicsLayer { this.alpha = alpha }
}

/**
 * A visible end-aligned "Close" for sheets whose content has no Done/Cancel of its own, so people who
 * cannot drag or use back still have a dismiss control. Dismissing here is the same outcome as a drag.
 */
@Composable
fun GymSheetCloseRow(
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    label: String = stringResource(R.string.action_close)
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End
    ) {
        TextButton(onClick = onClose, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(label)
        }
    }
}

/** Sheet title with the visible Close on the same row, for fixed-height pickers that cannot spare a row. */
@Composable
fun GymSheetTitleRow(
    title: String,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.headlineSmall
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            style = style,
            modifier = Modifier
                .weight(1f)
                .semantics { heading() }
        )
        TextButton(onClick = onClose, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(stringResource(R.string.action_close))
        }
    }
}
