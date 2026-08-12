package com.example.gymapp.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gymapp.ui.theme.GymCompactShape
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.ui.theme.GymDataTypography
import com.example.gymapp.ui.theme.GymPanelShape
import com.example.gymapp.ui.theme.GymSpacing

@Composable
fun AppPanel(
    modifier: Modifier = Modifier,
    containerColor: Color = MaterialTheme.colorScheme.surface,
    contentColor: Color = MaterialTheme.colorScheme.onSurface,
    highlighted: Boolean = false,
    content: @Composable () -> Unit
) {
    val shape = GymPanelShape
    val panelColor = if (highlighted) {
        MaterialTheme.colorScheme.primaryContainer
    } else {
        containerColor
    }
    val strokeColor = if (highlighted) {
        MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)
    } else {
        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.62f)
    }

    Surface(
        modifier = modifier,
        shape = shape,
        color = panelColor,
        contentColor = contentColor,
        border = BorderStroke(1.dp, strokeColor),
        tonalElevation = 0.dp,
        shadowElevation = 0.dp
    ) {
        CompositionLocalProvider(LocalContentColor provides contentColor) {
            content()
        }
    }
}

@Composable
fun HeroPanel(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val shape = GymPanelShape
    // Hero panels represent the current focus, so they use the primary blue role.
    // The darker container role keeps the same hierarchy in dark appearance.
    val darkTheme = isSystemInDarkTheme()
    val container = if (darkTheme) {
        MaterialTheme.colorScheme.primaryContainer
    } else {
        MaterialTheme.colorScheme.primary
    }
    val heroContentColor = if (darkTheme) {
        MaterialTheme.colorScheme.onPrimaryContainer
    } else {
        MaterialTheme.colorScheme.onPrimary
    }
    Surface(
        modifier = modifier,
        shape = shape,
        color = container,
        contentColor = heroContentColor,
        border = BorderStroke(1.dp, heroContentColor.copy(alpha = 0.18f)),
        tonalElevation = 0.dp,
        shadowElevation = 0.dp
    ) {
        CompositionLocalProvider(LocalContentColor provides heroContentColor) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(20.dp)
            ) {
                content()
            }
        }
    }
}

@Composable
fun SectionTitle(
    eyebrow: String,
    title: String,
    supporting: String? = null,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        if (sectionTitleShowsEyebrow(eyebrow)) {
            Text(
                text = eyebrow.uppercase(),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.secondary
            )
        }
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurface
        )
        if (!supporting.isNullOrBlank()) {
            Text(
                text = supporting,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

internal fun sectionTitleShowsEyebrow(eyebrow: String): Boolean = eyebrow.isNotBlank()

@Composable
fun MetricTile(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    emphasized: Boolean = false,
    onHero: Boolean = false,
    utilityValue: Boolean = false
) {
    val shape = GymCompactShape
    val tileContainerColor = if (onHero) {
        Color.White.copy(alpha = 0.11f)
    } else {
        MaterialTheme.colorScheme.surfaceVariant
    }
    val tileContentColor = if (onHero) {
        Color.White
    } else {
        MaterialTheme.colorScheme.onSurface
    }
    val labelColor = if (onHero) {
        Color.White.copy(alpha = 0.76f)
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    val borderColor = if (onHero) {
        Color.White.copy(alpha = 0.14f)
    } else {
        MaterialTheme.colorScheme.outlineVariant
    }

    Column(
        modifier = modifier
            .heightIn(min = 78.dp)
            .clip(shape)
            .background(tileContainerColor, shape)
            .border(BorderStroke(1.dp, borderColor), shape)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.35.sp,
            color = labelColor,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = value,
            style = when {
                utilityValue && emphasized -> GymDataTypography.copy(fontSize = 20.sp, lineHeight = 26.sp)
                utilityValue -> GymDataTypography.copy(fontSize = 16.sp, lineHeight = 22.sp)
                emphasized -> MaterialTheme.typography.titleLarge
                else -> MaterialTheme.typography.titleMedium
            },
            fontWeight = FontWeight.Bold,
            color = tileContentColor,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
fun InfoPill(
    text: String,
    modifier: Modifier = Modifier,
    accent: Color = MaterialTheme.colorScheme.primary
) {
    Surface(
        modifier = modifier,
        color = accent.copy(alpha = 0.12f),
        contentColor = accent,
        shape = RoundedCornerShape(999.dp),
        border = BorderStroke(1.dp, accent.copy(alpha = 0.22f))
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 11.dp, vertical = 7.dp),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
fun EmptyStatePanel(
    title: String,
    supporting: String? = null,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null
) {
    AppPanel(
        modifier = modifier
    ) {
        Column(
            modifier = Modifier.padding(GymSpacing.XLarge),
            verticalArrangement = Arrangement.spacedBy(GymSpacing.Small)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium
            )
            if (!supporting.isNullOrBlank()) {
                Text(
                    text = supporting,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (!actionLabel.isNullOrBlank() && onAction != null) {
                Button(
                    onClick = onAction,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = GymSpacing.MinimumTouch)
                ) {
                    Text(actionLabel)
                }
            }
        }
    }
}

@Composable
fun ScreenHeader(
    title: String,
    supporting: String? = null,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.XSmall)
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.headlineLarge,
            color = MaterialTheme.colorScheme.onSurface
        )
        if (!supporting.isNullOrBlank()) {
            Text(
                text = supporting,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

data class GymSegmentItem<T>(
    val value: T,
    val label: String
)

@Composable
fun <T> GymSegmentedControl(
    items: List<GymSegmentItem<T>>,
    selected: T,
    onSelected: (T) -> Unit,
    modifier: Modifier = Modifier
) {
    if (items.isEmpty()) return
    BoxWithConstraints(modifier = modifier.fillMaxWidth()) {
        val stackVertically = maxWidth < 280.dp
        val content: @Composable (GymSegmentItem<T>, Modifier) -> Unit = { item, itemModifier ->
            val isSelected = item.value == selected
            Surface(
                modifier = itemModifier
                    .heightIn(min = GymSpacing.MinimumTouch)
                    .selectable(
                        selected = isSelected,
                        role = Role.Tab,
                        onClick = { onSelected(item.value) }
                    ),
                shape = GymControlShape,
                color = if (isSelected) {
                    MaterialTheme.colorScheme.primary
                } else {
                    Color.Transparent
                },
                contentColor = if (isSelected) {
                    MaterialTheme.colorScheme.onPrimary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                border = BorderStroke(
                    1.dp,
                    if (isSelected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.outlineVariant
                    }
                )
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = GymSpacing.Medium, vertical = GymSpacing.Small),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = item.label,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }

        if (stackVertically) {
            Column(
                modifier = Modifier.selectableGroup(),
                verticalArrangement = Arrangement.spacedBy(GymSpacing.Small)
            ) {
                items.forEach { item -> content(item, Modifier.fillMaxWidth()) }
            }
        } else {
            Row(
                modifier = Modifier.selectableGroup(),
                horizontalArrangement = Arrangement.spacedBy(GymSpacing.Small)
            ) {
                items.forEach { item -> content(item, Modifier.weight(1f)) }
            }
        }
    }
}

data class GymMetric(
    val label: String,
    val value: String,
    val emphasized: Boolean = false
)

internal data class SpotterSetSemanticState(
    val ordinal: Int,
    val isCompleted: Boolean
)

internal fun spotterSetSemanticStates(
    completed: List<Boolean>
): List<SpotterSetSemanticState> = completed.mapIndexed { index, isCompleted ->
    SpotterSetSemanticState(ordinal = index + 1, isCompleted = isCompleted)
}

@Composable
fun MetricStrip(
    metrics: List<GymMetric>,
    modifier: Modifier = Modifier,
    onHero: Boolean = false
) {
    if (metrics.isEmpty()) return
    BoxWithConstraints(modifier = modifier.fillMaxWidth()) {
        val columnCount = when {
            metrics.size == 1 -> 1
            maxWidth < 330.dp -> 2
            else -> minOf(3, metrics.size)
        }
        Column(verticalArrangement = Arrangement.spacedBy(GymSpacing.Small)) {
            metrics.chunked(columnCount).forEach { rowMetrics ->
                if (rowMetrics.size == 1) {
                    val metric = rowMetrics.single()
                    MetricTile(
                        label = metric.label,
                        value = metric.value,
                        modifier = Modifier.fillMaxWidth(),
                        emphasized = metric.emphasized,
                        onHero = onHero,
                        utilityValue = true
                    )
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(GymSpacing.Small)
                    ) {
                        rowMetrics.forEach { metric ->
                            MetricTile(
                                label = metric.label,
                                value = metric.value,
                                modifier = Modifier.weight(1f),
                                emphasized = metric.emphasized,
                                onHero = onHero,
                                utilityValue = true
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SpotterLaneCard(
    exerciseName: String,
    selfLabel: String,
    selfCompleted: List<Boolean>,
    peerLabel: String,
    peerCompleted: List<Boolean>,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        containerColor = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Column(
            modifier = Modifier.padding(GymSpacing.Medium),
            verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
        ) {
            Text(
                text = exerciseName,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            SpotterSetRail(
                label = selfLabel,
                completed = selfCompleted,
                accent = MaterialTheme.colorScheme.primary
            )
            SpotterSetRail(
                label = peerLabel,
                completed = peerCompleted,
                accent = MaterialTheme.colorScheme.tertiary
            )
        }
    }
}

@Composable
private fun SpotterSetRail(
    label: String,
    completed: List<Boolean>,
    accent: Color
) {
    val completedCount = completed.count { it }
    val semanticStates = spotterSetSemanticStates(completed)
    val exactStateDescriptions = semanticStates.map { state ->
        stringResource(
            if (state.isCompleted) {
                com.example.gymapp.R.string.live_workout_set_completed_accessibility
            } else {
                com.example.gymapp.R.string.live_workout_set_pending_accessibility
            },
            state.ordinal
        )
    }
    val progressDescription = stringResource(
        com.example.gymapp.R.string.live_workout_set_progress_accessibility,
        completedCount,
        completed.size
    )
    Column(
        modifier = Modifier.clearAndSetSemantics {
            contentDescription = buildString {
                append(label)
                if (exactStateDescriptions.isNotEmpty()) {
                    append(". ")
                    append(exactStateDescriptions.joinToString(separator = ". "))
                }
            }
            stateDescription = progressDescription
        },
        verticalArrangement = Arrangement.spacedBy(GymSpacing.XSmall)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(GymSpacing.Small),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = "$completedCount/${completed.size}",
                style = GymDataTypography,
                color = accent
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(GymSpacing.XSmall)
        ) {
            semanticStates.forEach { state ->
                Surface(
                    modifier = Modifier.size(12.dp),
                    shape = RoundedCornerShape(4.dp),
                    color = if (state.isCompleted) accent else accent.copy(alpha = 0.14f),
                    border = BorderStroke(
                        1.dp,
                        accent.copy(alpha = if (state.isCompleted) 0.8f else 0.24f)
                    ),
                    content = {}
                )
            }
        }
    }
}

@Composable
fun SocialActionCard(
    eyebrow: String,
    title: String,
    supporting: String,
    primaryLabel: String,
    onPrimary: () -> Unit,
    secondaryLabel: String? = null,
    onSecondary: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    AppPanel(modifier = modifier.fillMaxWidth(), highlighted = true) {
        Column(
            modifier = Modifier.padding(GymSpacing.Large),
            verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
        ) {
            SectionTitle(eyebrow = eyebrow, title = title, supporting = supporting)
            Button(
                onClick = onPrimary,
                enabled = enabled,
                modifier = Modifier.fillMaxWidth().heightIn(min = GymSpacing.MinimumTouch)
            ) {
                Text(primaryLabel, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            if (!secondaryLabel.isNullOrBlank() && onSecondary != null) {
                OutlinedButton(
                    onClick = onSecondary,
                    enabled = enabled,
                    modifier = Modifier.fillMaxWidth().heightIn(min = GymSpacing.MinimumTouch)
                ) {
                    Text(secondaryLabel, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
fun LoadingStatePanel(
    modifier: Modifier = Modifier,
    label: String? = null
) {
    AppPanel(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(GymSpacing.XLarge),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
            if (!label.isNullOrBlank()) {
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(start = GymSpacing.Medium)
                )
            }
        }
    }
}
