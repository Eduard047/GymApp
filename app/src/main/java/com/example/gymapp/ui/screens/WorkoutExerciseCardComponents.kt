package com.example.gymapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gymapp.R
import com.example.gymapp.data.repository.VoiceWorkoutDraftParser
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.tabularDigits
import java.text.NumberFormat

/*
 * Stateless building blocks of an exercise card, shared by the active-workout screen and the saved
 * workout screen so both read and edit with the same look: card shell and header, set rows (editable
 * and recorded), the inline set editor pieces, the dashed footer button and the remove-exercise menu
 * and dialog. They hold no screen state of their own beyond transient menu visibility.
 */

internal val PlainSetRowPadding = 10.dp

/** The panel every exercise card sits in: 16dp padding, 12dp between header, body and footer. */
@Composable
internal fun WorkoutExerciseCardShell(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    AppPanel(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            content = content
        )
    }
}

/** Exercise thumbnail at the size the card header uses. */
@Composable
internal fun WorkoutExerciseMedia(
    exerciseId: Long,
    exerciseName: String,
    ownerKey: String,
    editable: Boolean = false
) {
    ExerciseMediaPreview(
        exerciseId = exerciseId,
        exerciseName = exerciseName,
        ownerKey = ownerKey,
        width = 76.dp,
        height = 64.dp,
        editable = editable
    )
}

/**
 * Card header: optional [media], a tappable title block (title plus the [subtitle] lines) with an
 * expand/collapse chevron, and an optional [menu] slot (the overflow button) at the end.
 */
@Composable
internal fun WorkoutExerciseCardHeader(
    title: String,
    expanded: Boolean,
    onToggleExpanded: () -> Unit,
    modifier: Modifier = Modifier,
    stateText: String? = null,
    media: (@Composable () -> Unit)? = null,
    menu: (@Composable () -> Unit)? = null,
    accessibilityActions: List<CustomAccessibilityAction> = emptyList(),
    subtitle: @Composable ColumnScope.() -> Unit
) {
    val toggleLabel = stringResource(
        if (expanded) R.string.cd_collapse_exercise else R.string.cd_expand_exercise
    )
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        media?.invoke()
        Row(
            modifier = Modifier
                .weight(1f)
                .heightIn(min = 48.dp)
                .clickable(
                    onClickLabel = toggleLabel,
                    role = Role.Button,
                    onClick = onToggleExpanded
                )
                .semantics {
                    contentDescription = title
                    if (stateText != null) stateDescription = stateText
                    if (accessibilityActions.isNotEmpty()) {
                        this.customActions = accessibilityActions
                    }
                },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface
                )
                subtitle()
            }
            Icon(
                imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        menu?.invoke()
    }
}

/** Card header overflow: "Remove exercise" (only composed when the exercise may be removed). */
@Composable
internal fun WorkoutExerciseMenu(enabled: Boolean, onRemove: () -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }, enabled = enabled) {
            Icon(
                imageVector = Icons.Default.MoreVert,
                contentDescription = stringResource(R.string.active_workout_more_options),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        DropdownMenu(expanded = expanded && enabled, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = {
                    Text(
                        text = stringResource(R.string.active_workout_remove_exercise),
                        color = MaterialTheme.colorScheme.error
                    )
                },
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error
                    )
                },
                onClick = {
                    expanded = false
                    onRemove()
                }
            )
        }
    }
}

/**
 * Confirms removing an exercise; states how many recorded sets go with it. Same destructive dialog
 * pattern as the persisted-delete dialogs: impact line in the error colour, outlined Cancel and a
 * filled error-coloured confirm button.
 */
@Composable
internal fun WorkoutRemoveExerciseDialog(
    exerciseName: String,
    recordedCount: Int,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = stringResource(R.string.active_workout_remove_exercise_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(text = exerciseName, style = MaterialTheme.typography.titleSmall)
                Text(
                    text = if (recordedCount > 0) {
                        pluralStringResource(
                            R.plurals.active_workout_remove_exercise_recorded_sets,
                            recordedCount,
                            recordedCount
                        )
                    } else {
                        stringResource(R.string.active_workout_remove_exercise_message)
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error
                )
            }
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                    contentColor = MaterialTheme.colorScheme.onError
                )
            ) {
                Text(text = stringResource(R.string.active_workout_remove_exercise_confirm))
            }
        },
        dismissButton = {
            OutlinedButton(onClick = onDismiss) {
                Text(text = stringResource(R.string.action_cancel))
            }
        }
    )
}

/** Outlined footer action: dashed (primary 50%) for "+ Set", solid (primary 70%) for "Finish". */
@Composable
internal fun WorkoutFooterButton(
    label: String,
    accessibilityLabel: String,
    dashed: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val primary = MaterialTheme.colorScheme.primary
    val contentColor = if (enabled) primary else primary.copy(alpha = 0.38f)
    val borderColor = primary.copy(alpha = if (dashed) 0.5f else 0.7f).let {
        if (enabled) it else it.copy(alpha = it.alpha * 0.5f)
    }
    val shape = RoundedCornerShape(12.dp)
    val density = LocalDensity.current
    Box(
        modifier = modifier
            .heightIn(min = 44.dp)
            .clip(shape)
            .clickable(
                enabled = enabled,
                role = Role.Button,
                onClick = onClick
            )
            .semantics(mergeDescendants = true) { contentDescription = accessibilityLabel }
            .drawBehind {
                val strokeWidth = with(density) { 1.dp.toPx() }
                val inset = strokeWidth / 2f
                drawRoundRect(
                    color = borderColor,
                    topLeft = Offset(inset, inset),
                    size = Size(size.width - strokeWidth, size.height - strokeWidth),
                    cornerRadius = CornerRadius(with(density) { 12.dp.toPx() } - inset),
                    style = Stroke(
                        width = strokeWidth,
                        pathEffect = if (dashed) {
                            PathEffect.dashPathEffect(
                                floatArrayOf(with(density) { 4.dp.toPx() }, with(density) { 3.dp.toPx() })
                            )
                        } else {
                            null
                        }
                    )
                )
            }
            .padding(horizontal = 12.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.titleSmall,
            color = contentColor,
            maxLines = 1,
            textAlign = TextAlign.Center,
            modifier = Modifier.clearAndSetSemantics {}
        )
    }
}

/** "60 kg × 8" for a set's weight and reps inputs (blank counts as 0). */
@Composable
internal fun rememberSetSummary(weightInput: String, repsInput: String): String = stringResource(
    R.string.active_workout_set_summary,
    weightInput.ifBlank { "0" },
    repsInput.ifBlank { "0" }
)

/**
 * A set that can be edited in place: one plain line (number badge, "60 kg × 8", optional
 * [summaryBadge], chevron) that expands into [editor]. Tap toggles the editor; long-press opens
 * "Delete set" ([deleteLabel] in the menu, [deleteActionLabel] for TalkBack) when [canDelete]. [trailing] sits at the end of the line, outside the tap target.
 * Expansion is owned by the caller.
 */
@Composable
internal fun EditableSetRow(
    number: Int,
    summary: String,
    rowDescription: String,
    editHint: String,
    deleteLabel: String,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    canDelete: Boolean,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
    deleteActionLabel: String = deleteLabel,
    summaryBadge: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    editor: @Composable ColumnScope.() -> Unit
) {
    var menuOpen by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val currentExpanded by rememberUpdatedState(expanded)
    val currentOnExpandedChange by rememberUpdatedState(onExpandedChange)
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = PlainSetRowPadding),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 44.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(modifier = Modifier.weight(1f)) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 44.dp)
                        .pointerInput(canDelete) {
                            // Tap expands the editor; long-press opens "Delete set" (mirrors Undo on a recorded set).
                            detectTapGestures(
                                onTap = { currentOnExpandedChange(!currentExpanded) },
                                onLongPress = {
                                    if (canDelete) {
                                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                        menuOpen = true
                                    }
                                }
                            )
                        }
                        .semantics {
                            role = Role.Button
                            contentDescription = rowDescription
                            stateDescription = if (expanded) "▲" else "▼"
                            onClick(label = editHint) {
                                currentOnExpandedChange(!currentExpanded)
                                true
                            }
                            if (canDelete) {
                                customActions = listOf(
                                    CustomAccessibilityAction(deleteActionLabel) {
                                        menuOpen = false
                                        onDelete()
                                        true
                                    }
                                )
                            }
                        },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(22.dp)
                            .border(1.5.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape)
                            .clearAndSetSemantics {},
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = number.toString(),
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontWeight = FontWeight.Bold
                            ).tabularDigits(),
                            color = secondary
                        )
                    }
                    Text(
                        text = summary,
                        style = MaterialTheme.typography.titleSmall,
                        color = secondary,
                        modifier = Modifier
                            .weight(1f)
                            .clearAndSetSemantics {}
                    )
                    summaryBadge?.invoke()
                    Icon(
                        imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                        contentDescription = null,
                        tint = secondary,
                        modifier = Modifier.size(20.dp)
                    )
                }
                DropdownMenu(expanded = menuOpen && canDelete, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text(deleteLabel, color = MaterialTheme.colorScheme.error) },
                        onClick = {
                            menuOpen = false
                            onDelete()
                        }
                    )
                }
            }
            trailing?.invoke()
        }
        if (expanded) {
            editor()
        }
    }
}

/** Compact inline editor of a plain set row: weight field, "×" and a reps stepper on one line. */
@Composable
internal fun SetPendingEditor(
    number: Int,
    weightInput: String,
    repsInput: String,
    enabled: Boolean,
    onWeightChanged: (String) -> Unit,
    onRepsChanged: (String) -> Unit
) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            modifier = Modifier
                .heightIn(min = 44.dp)
                .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape)
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            SetWeightField(
                value = weightInput,
                onValueChange = onWeightChanged,
                enabled = enabled,
                description = stringResource(R.string.active_workout_weight_field_cd, number),
                fontSize = 17.sp
            )
            Text(
                text = stringResource(R.string.active_workout_unit_kg),
                style = MaterialTheme.typography.bodySmall,
                color = secondary
            )
        }
        Text(
            text = "×",
            style = MaterialTheme.typography.titleSmall,
            color = secondary,
            modifier = Modifier.clearAndSetSemantics {}
        )
        val reps = repsInput.trim().toIntOrNull()
        val canDecrease = enabled && canStepReps(reps, -1)
        val canIncrease = enabled && canStepReps(reps, 1)
        val decreaseLabel = stringResource(R.string.active_workout_decrease_reps)
        val increaseLabel = stringResource(R.string.active_workout_increase_reps)
        val repsDescription = stringResource(R.string.active_workout_reps_field_cd, number)
        Row(
            modifier = Modifier
                .heightIn(min = 44.dp)
                .background(MaterialTheme.colorScheme.surfaceVariant, CircleShape)
                .clearAndSetSemantics {
                    contentDescription = repsDescription
                    stateDescription = repsInput
                    customActions = listOf(
                        CustomAccessibilityAction(decreaseLabel) {
                            if (canDecrease) {
                                onRepsChanged(steppedReps(reps, -1).toString())
                                true
                            } else {
                                false
                            }
                        },
                        CustomAccessibilityAction(increaseLabel) {
                            if (canIncrease) {
                                onRepsChanged(steppedReps(reps, 1).toString())
                                true
                            } else {
                                false
                            }
                        }
                    )
                },
            verticalAlignment = Alignment.CenterVertically
        ) {
            StepButton(
                icon = Icons.Default.Remove,
                text = null,
                enabled = canDecrease,
                onClick = { onRepsChanged(steppedReps(reps, -1).toString()) }
            )
            Text(
                text = repsInput.ifBlank { "0" },
                style = MaterialTheme.typography.titleSmall.tabularDigits(),
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.widthIn(min = 20.dp),
                textAlign = TextAlign.Center
            )
            StepButton(
                icon = Icons.Default.Add,
                text = null,
                enabled = canIncrease,
                onClick = { onRepsChanged(steppedReps(reps, 1).toString()) }
            )
        }
    }
}

/**
 * A recorded set: one line — check, "60 kg × 8", optional record badge, and an optional [trailing]
 * block (the active workout's rest countdown) that wraps under the summary when it does not fit.
 * When [longPressActionLabel] is set, a long-press menu / accessibility action runs
 * [onLongPressAction] (Undo on the active workout). [modifier] is applied inside the row padding.
 */
@Composable
internal fun RecordedSetRow(
    summary: String,
    description: String,
    isPersonalRecord: Boolean,
    modifier: Modifier = Modifier,
    longPressActionLabel: String? = null,
    onLongPressAction: (() -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null
) {
    val canAct = longPressActionLabel != null && onLongPressAction != null
    val haptics = LocalHapticFeedback.current
    var menuOpen by remember { mutableStateOf(false) }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = PlainSetRowPadding)
            .then(modifier)
            .pointerInput(canAct) {
                if (canAct) {
                    detectTapGestures(onLongPress = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        menuOpen = true
                    })
                }
            }
    ) {
        AdaptiveTrailingRow(
            modifier = Modifier.fillMaxWidth(),
            leading = {
                Row(
                    modifier = Modifier.clearAndSetSemantics {
                        contentDescription = description
                        if (canAct) {
                            customActions = listOf(
                                CustomAccessibilityAction(checkNotNull(longPressActionLabel)) {
                                    menuOpen = false
                                    checkNotNull(onLongPressAction)()
                                    true
                                }
                            )
                        }
                    },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(22.dp)
                            .background(MaterialTheme.colorScheme.secondary.copy(alpha = 0.18f), CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.secondary,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                    Text(
                        text = summary,
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1
                    )
                    if (isPersonalRecord) {
                        PersonalRecordBadge()
                    }
                }
            },
            trailing = trailing
        )
        if (canAct) {
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(
                    text = { Text(checkNotNull(longPressActionLabel)) },
                    onClick = {
                        menuOpen = false
                        checkNotNull(onLongPressAction)()
                    }
                )
            }
        }
    }
}

/**
 * [leading] at the start and [trailing] at the end of one line when both fit, otherwise
 * [trailing] on its own line under [leading] (large font sizes).
 */
@Composable
internal fun AdaptiveTrailingRow(
    modifier: Modifier,
    leading: @Composable () -> Unit,
    trailing: (@Composable () -> Unit)?
) {
    Layout(
        content = {
            leading()
            trailing?.invoke()
        },
        modifier = modifier
    ) { measurables, constraints ->
        val gap = 8.dp.roundToPx()
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val lead = measurables[0].measure(loose)
        val trail = measurables.getOrNull(1)?.measure(loose)
        val width = constraints.maxWidth
        if (trail == null) {
            layout(width, lead.height) { lead.placeRelative(0, 0) }
        } else if (lead.width + gap + trail.width <= width) {
            val height = maxOf(lead.height, trail.height)
            layout(width, height) {
                lead.placeRelative(0, (height - lead.height) / 2)
                trail.placeRelative(width - trail.width, (height - trail.height) / 2)
            }
        } else {
            layout(width, lead.height + trail.height) {
                lead.placeRelative(0, 0)
                trail.placeRelative(0, lead.height)
            }
        }
    }
}

@Composable
internal fun rememberDecimalFormat(): NumberFormat {
    val locale = LocalConfiguration.current.locales[0]
    return remember(locale) {
        NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 3 }
    }
}

/** "60 kg × 8": editable weight (plain text, underline only while focused), read-only reps. */
@Composable
internal fun SetValueLine(
    number: Int,
    weightInput: String,
    repsInput: String,
    enabled: Boolean,
    onWeightChanged: (String) -> Unit
) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val valueStyle = TextStyle(
        fontSize = 30.sp,
        fontWeight = FontWeight.SemiBold
    ).tabularDigits()
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.Center
    ) {
        SetWeightField(
            value = weightInput,
            onValueChange = onWeightChanged,
            enabled = enabled,
            description = stringResource(R.string.active_workout_weight_field_cd, number),
            fontSize = 30.sp
        )
        Text(
            text = stringResource(R.string.active_workout_unit_kg),
            fontSize = 15.sp,
            color = secondary,
            modifier = Modifier.padding(start = 4.dp, bottom = 6.dp)
        )
        Text(
            text = "×",
            style = valueStyle,
            color = secondary,
            modifier = Modifier
                .padding(start = 4.dp)
                .clearAndSetSemantics {}
        )
        Text(
            text = repsInput.ifBlank { "0" },
            style = valueStyle,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            modifier = Modifier
                .padding(start = 4.dp)
                .clearAndSetSemantics {}
        )
    }
}

@Composable
internal fun SetWeightField(
    value: String,
    onValueChange: (String) -> Unit,
    enabled: Boolean,
    description: String,
    fontSize: TextUnit
) {
    val focusManager = LocalFocusManager.current
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val primary = MaterialTheme.colorScheme.primary
    val style = TextStyle(
        fontSize = fontSize,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurface,
        textAlign = TextAlign.End
    ).tabularDigits()
    val placeholderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
    // Fit the width to the measured text: at least one digit, at most six, plus room for the caret.
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val fieldWidth = remember(value, style, density) {
        val text = value.ifEmpty { "0" }
        val digit = measurer.measure("0", style, maxLines = 1).size.width
        val widest = measurer.measure("0".repeat(6), style, maxLines = 1).size.width
        val measured = measurer.measure(text, style, maxLines = 1).size.width
        with(density) { measured.coerceIn(digit, widest).toDp() + 6.dp }
    }
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        enabled = enabled,
        singleLine = true,
        textStyle = style,
        cursorBrush = SolidColor(primary),
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Decimal,
            imeAction = ImeAction.Done
        ),
        keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
        interactionSource = interaction,
        modifier = Modifier
            .width(fieldWidth)
            .semantics { contentDescription = description },
        decorationBox = { innerTextField ->
            Box(
                modifier = Modifier.drawBehind {
                    if (focused) {
                        val stroke = 1.5.dp.toPx()
                        drawLine(
                            color = primary,
                            start = Offset(0f, size.height - stroke / 2f),
                            end = Offset(size.width, size.height - stroke / 2f),
                            strokeWidth = stroke
                        )
                    }
                },
                contentAlignment = Alignment.CenterEnd
            ) {
                if (value.isEmpty()) {
                    Text(text = "0", style = style.copy(color = placeholderColor))
                }
                innerTextField()
            }
        }
    )
}

/** Weight and reps step capsules side by side (stacked at large font scales). */
@Composable
internal fun SetStepCapsules(
    weightInput: String,
    repsInput: String,
    allowedWeights: List<Double>,
    enabled: Boolean,
    format: NumberFormat,
    onWeightChanged: (String) -> Unit,
    onRepsChanged: (String) -> Unit
) {
    val plan = weightStepPlan(weightForStepping(weightInput), allowedWeights)
    val reps = repsInput.trim().toIntOrNull()
    val minusDelta = format.format(plan.minus.delta)
    val plusDelta = format.format(plan.plus.delta)
    val weightValue = weightForStepping(weightInput)?.let { format.format(it) } ?: weightInput
    val stepWeightTo = { side: WeightStepSide ->
        onWeightChanged(VoiceWorkoutDraftParser.formatWeight(side.target))
    }
    val weightCapsule: @Composable (Modifier) -> Unit = { modifier ->
        StepCapsule(
            modifier = modifier,
            minusText = "−$minusDelta",
            minusIcon = null,
            minusEnabled = enabled && plan.minus.canMove,
            onMinus = { stepWeightTo(plan.minus) },
            centerLabel = stringResource(R.string.active_workout_step_weight_center),
            plusText = "+$plusDelta",
            plusIcon = null,
            plusEnabled = enabled && plan.plus.canMove,
            onPlus = { stepWeightTo(plan.plus) },
            label = stringResource(R.string.active_workout_step_weight_label),
            value = stringResource(R.string.active_workout_step_weight_value, weightValue),
            decreaseActionLabel = stringResource(R.string.active_workout_decrease_weight, minusDelta),
            increaseActionLabel = stringResource(R.string.active_workout_increase_weight, plusDelta)
        )
    }
    val repsCapsule: @Composable (Modifier) -> Unit = { modifier ->
        StepCapsule(
            modifier = modifier,
            minusText = null,
            minusIcon = Icons.Default.Remove,
            minusEnabled = enabled && canStepReps(reps, -1),
            onMinus = { onRepsChanged(steppedReps(reps, -1).toString()) },
            centerLabel = stringResource(R.string.active_workout_step_reps_center),
            plusText = null,
            plusIcon = Icons.Default.Add,
            plusEnabled = enabled && canStepReps(reps, 1),
            onPlus = { onRepsChanged(steppedReps(reps, 1).toString()) },
            label = stringResource(R.string.active_workout_step_reps_label),
            value = repsInput,
            decreaseActionLabel = stringResource(R.string.active_workout_decrease_reps),
            increaseActionLabel = stringResource(R.string.active_workout_increase_reps)
        )
    }
    // Two equal columns; a single column at large font scales, like Dynamic Type accessibility sizes.
    if (LocalConfiguration.current.fontScale >= 1.5f) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            weightCapsule(Modifier.fillMaxWidth())
            repsCapsule(Modifier.fillMaxWidth())
        }
    } else {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            weightCapsule(Modifier.weight(1f))
            repsCapsule(Modifier.weight(1f))
        }
    }
}

/**
 * Slim (34dp) capsule with a step button at each end (each a full 44dp target) and a small
 * centre label. The whole capsule is one accessibility element with increase/decrease actions.
 */
@Composable
internal fun StepCapsule(
    modifier: Modifier,
    minusText: String?,
    minusIcon: ImageVector?,
    minusEnabled: Boolean,
    onMinus: () -> Unit,
    centerLabel: String,
    plusText: String?,
    plusIcon: ImageVector?,
    plusEnabled: Boolean,
    onPlus: () -> Unit,
    label: String,
    value: String,
    decreaseActionLabel: String,
    increaseActionLabel: String,
    emphasizeCenter: Boolean = false
) {
    Box(
        modifier = modifier
            .heightIn(min = 44.dp)
            .clearAndSetSemantics {
                contentDescription = label
                stateDescription = value
                customActions = listOf(
                    CustomAccessibilityAction(decreaseActionLabel) {
                        if (minusEnabled) {
                            onMinus()
                            true
                        } else {
                            false
                        }
                    },
                    CustomAccessibilityAction(increaseActionLabel) {
                        if (plusEnabled) {
                            onPlus()
                            true
                        } else {
                            false
                        }
                    }
                )
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(34.dp)
                .background(MaterialTheme.colorScheme.surface, CircleShape)
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            StepButton(icon = minusIcon, text = minusText, enabled = minusEnabled, onClick = onMinus)
            Text(
                text = centerLabel,
                style = if (emphasizeCenter) {
                    MaterialTheme.typography.titleSmall
                } else {
                    MaterialTheme.typography.labelSmall
                },
                color = if (emphasizeCenter) {
                    MaterialTheme.colorScheme.onSurface
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                maxLines = 1,
                textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f)
            )
            StepButton(icon = plusIcon, text = plusText, enabled = plusEnabled, onClick = onPlus)
        }
    }
}

@Composable
internal fun StepButton(
    icon: ImageVector?,
    text: String?,
    enabled: Boolean,
    onClick: () -> Unit
) {
    val tint = MaterialTheme.colorScheme.primary.copy(alpha = if (enabled) 1f else 0.38f)
    Box(
        modifier = Modifier
            .defaultMinSize(minWidth = 44.dp, minHeight = 44.dp)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        if (icon != null) {
            Icon(imageVector = icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        } else if (text != null) {
            Text(
                text = text,
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                color = tint,
                maxLines = 1,
                modifier = Modifier.padding(horizontal = 4.dp)
            )
        }
    }
}

@Composable
internal fun PersonalRecordBadge() {
    Surface(
        shape = RoundedCornerShape(percent = 50),
        color = MaterialTheme.colorScheme.primary,
        contentColor = MaterialTheme.colorScheme.onPrimary
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                imageVector = Icons.Default.EmojiEvents,
                contentDescription = null,
                modifier = Modifier.size(14.dp)
            )
            Text(
                text = stringResource(R.string.active_workout_personal_record),
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1
            )
        }
    }
}
