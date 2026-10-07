package com.example.gymapp.ui.components

import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.text.style.Hyphens
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp
import com.example.gymapp.R
import com.example.gymapp.ui.theme.BrandFill
import com.example.gymapp.ui.theme.BrandFillBright
import com.example.gymapp.ui.theme.BrandFillBrightNight
import com.example.gymapp.ui.theme.BrandFillNight
import com.example.gymapp.ui.theme.GymCompactShape
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.ui.theme.GymDataTypography
import com.example.gymapp.ui.theme.GymPanelShape
import com.example.gymapp.ui.theme.GymSpacing

private val DefaultAdaptiveContentWidth = 760.dp

internal fun adaptiveHorizontalPadding(
    windowWidth: Dp,
    minimumPadding: Dp = GymSpacing.ScreenHorizontal,
    maximumContentWidth: Dp = DefaultAdaptiveContentWidth
): Dp = if (windowWidth > maximumContentWidth + minimumPadding * 2) {
    (windowWidth - maximumContentWidth) / 2
} else {
    minimumPadding
}

@Composable
fun adaptiveScreenHorizontalPadding(
    maximumContentWidth: Dp = DefaultAdaptiveContentWidth
): Dp = adaptiveHorizontalPadding(
    windowWidth = LocalConfiguration.current.screenWidthDp.dp,
    maximumContentWidth = maximumContentWidth
)

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
    contentPadding: Dp = 20.dp,
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
                    .padding(contentPadding)
            ) {
                content()
            }
        }
    }
}

/**
 * Brand-blue gradient container shared with iOS (`GymHeroPanel` with the brand gradient): the
 * compact hero surface used where the generic hero blue would dominate the screen.
 */
@Composable
fun BrandHeroPanel(
    modifier: Modifier = Modifier,
    contentPadding: Dp = 16.dp,
    content: @Composable () -> Unit
) {
    BrandHeroPanel(
        modifier = modifier,
        contentPadding = PaddingValues(contentPadding),
        content = content
    )
}

/** [BrandHeroPanel] with per-edge content padding (e.g. the compact identity strip on Auth). */
@Composable
fun BrandHeroPanel(
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues,
    content: @Composable () -> Unit
) {
    val brush = if (isSystemInDarkTheme()) {
        Brush.linearGradient(listOf(BrandFillNight, BrandFillBrightNight))
    } else {
        Brush.linearGradient(listOf(BrandFill, BrandFillBright))
    }
    CompositionLocalProvider(LocalContentColor provides Color.White) {
        Box(
            modifier = modifier
                .clip(GymPanelShape)
                .background(brush)
                .padding(contentPadding)
        ) {
            content()
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
            modifier = Modifier.semantics { heading() },
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

/**
 * Linear progress bar shared by the Progress screens. Matches iOS: a plain filled track with no
 * Material3 stop-indicator dot and no gap between the indicator and the track.
 */
@Composable
fun GymProgressBar(
    progress: () -> Float,
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.primary,
    trackColor: Color = MaterialTheme.colorScheme.surfaceVariant
) {
    LinearProgressIndicator(
        progress = { progress().coerceIn(0f, 1f) },
        modifier = modifier,
        color = color,
        trackColor = trackColor,
        gapSize = 0.dp,
        drawStopIndicator = {}
    )
}

/** Smallest fraction of the style size a single-word label may shrink to. */
internal const val WORD_SHRINK_MIN_SCALE = 0.75f
private const val WORD_SHRINK_STEP = 0.05f

/** True when [text] is a single word that must never be broken across lines. */
internal fun isSingleWordLabel(text: String): Boolean {
    val trimmed = text.trim()
    return trimmed.isNotEmpty() && trimmed.none { it.isWhitespace() }
}

/**
 * Next shrink factor for a single-word label that still overflows, or the same factor once the
 * [WORD_SHRINK_MIN_SCALE] floor is reached.
 */
internal fun nextWordShrinkScale(current: Float): Float =
    (current - WORD_SHRINK_STEP).coerceAtLeast(WORD_SHRINK_MIN_SCALE)

private fun TextUnit.scaledBy(scale: Float): TextUnit =
    if (isSpecified) this * scale else this

/**
 * Label text that never breaks inside a word (like iOS `minimumScaleFactor`): a single word stays
 * on one line and shrinks down to [WORD_SHRINK_MIN_SCALE] of the style size until it fits, while
 * multi-word labels wrap at word boundaries up to [maxLines].
 */
@Composable
fun WordShrinkText(
    text: String,
    style: TextStyle,
    modifier: Modifier = Modifier,
    fontWeight: FontWeight? = null,
    color: Color = Color.Unspecified,
    textAlign: TextAlign? = null,
    maxLines: Int = 2
) {
    val baseStyle = style.copy(hyphens = Hyphens.None, lineBreak = LineBreak.Heading)
    if (!isSingleWordLabel(text)) {
        Text(
            text = text,
            modifier = modifier,
            style = baseStyle,
            fontWeight = fontWeight,
            color = color,
            textAlign = textAlign,
            maxLines = maxLines,
            overflow = TextOverflow.Ellipsis
        )
        return
    }
    var scale by remember(text, style) { mutableFloatStateOf(1f) }
    var fits by remember(text, style) { mutableStateOf(false) }
    Text(
        text = text,
        modifier = modifier.drawWithContent { if (fits) drawContent() },
        style = baseStyle.copy(
            fontSize = baseStyle.fontSize.scaledBy(scale),
            lineHeight = baseStyle.lineHeight.scaledBy(scale)
        ),
        fontWeight = fontWeight,
        color = color,
        textAlign = textAlign,
        maxLines = 1,
        softWrap = false,
        overflow = TextOverflow.Ellipsis,
        onTextLayout = { layout ->
            if (layout.hasVisualOverflow && scale > WORD_SHRINK_MIN_SCALE) {
                scale = nextWordShrinkScale(scale)
            } else {
                fits = true
            }
        }
    )
}

@Composable
fun MetricTile(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    emphasized: Boolean = false,
    onHero: Boolean = false,
    utilityValue: Boolean = false,
    compactValue: Boolean = false
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

    val valueStyle = metricTileValueStyle(
        emphasized = emphasized,
        utilityValue = utilityValue,
        compactValue = compactValue
    )
    // Values stay on one line and shrink to fit instead of wrapping or hyphenating.
    var valueScale by remember(value, valueStyle) { mutableFloatStateOf(1f) }
    var valueFits by remember(value, valueStyle) { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxHeight()
            .heightIn(min = 78.dp)
            .clip(shape)
            .background(tileContainerColor, shape)
            .border(BorderStroke(1.dp, borderColor), shape)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        // Multi-word labels wrap at word boundaries; a single word shrinks to fit instead of breaking.
        WordShrinkText(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            color = labelColor,
            maxLines = 2
        )
        Text(
            text = value,
            style = valueStyle.copy(
                fontSize = valueStyle.fontSize * valueScale,
                lineHeight = valueStyle.lineHeight * valueScale,
                hyphens = Hyphens.None
            ),
            fontWeight = FontWeight.Bold,
            color = tileContentColor,
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Clip,
            onTextLayout = { layout ->
                if (layout.hasVisualOverflow && valueScale > METRIC_TILE_MIN_VALUE_SCALE) {
                    valueScale = (valueScale - METRIC_TILE_VALUE_SCALE_STEP)
                        .coerceAtLeast(METRIC_TILE_MIN_VALUE_SCALE)
                } else {
                    valueFits = true
                }
            },
            modifier = Modifier.drawWithContent { if (valueFits) drawContent() }
        )
    }
}

private const val METRIC_TILE_MIN_VALUE_SCALE = 0.6f
private const val METRIC_TILE_VALUE_SCALE_STEP = 0.08f

@Composable
private fun metricTileValueStyle(
    emphasized: Boolean,
    utilityValue: Boolean,
    compactValue: Boolean
): TextStyle = when {
    compactValue -> MaterialTheme.typography.titleMedium
    utilityValue && emphasized -> GymDataTypography.copy(fontSize = 20.sp, lineHeight = 26.sp)
    utilityValue -> GymDataTypography.copy(fontSize = 16.sp, lineHeight = 22.sp)
    emphasized -> MaterialTheme.typography.titleLarge
    else -> MaterialTheme.typography.titleMedium
}

@Composable
fun InfoPill(
    text: String,
    modifier: Modifier = Modifier,
    accent: Color = MaterialTheme.colorScheme.primary,
    leadingIcon: ImageVector? = null
) {
    Surface(
        modifier = modifier,
        color = accent.copy(alpha = 0.12f),
        contentColor = accent,
        shape = RoundedCornerShape(999.dp),
        border = BorderStroke(1.dp, accent.copy(alpha = 0.22f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 11.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            if (leadingIcon != null) {
                Icon(
                    imageVector = leadingIcon,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
            }
            Text(
                text = text,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun EmptyStatePanel(
    title: String,
    supporting: String? = null,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    icon: ImageVector? = null
) {
    val centered = icon != null
    AppPanel(
        modifier = modifier
    ) {
        Column(
            modifier = (if (centered) Modifier.fillMaxWidth() else Modifier)
                .padding(GymSpacing.XLarge),
            horizontalAlignment = if (centered) Alignment.CenterHorizontally else Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(GymSpacing.Small)
        ) {
            if (icon != null) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(32.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
            }
            Text(
                text = title,
                modifier = Modifier.semantics { heading() },
                style = MaterialTheme.typography.titleMedium,
                textAlign = if (centered) TextAlign.Center else TextAlign.Unspecified
            )
            if (!supporting.isNullOrBlank()) {
                Text(
                    text = supporting,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = if (centered) TextAlign.Center else TextAlign.Unspecified
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
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null
) {
    val titleColumn: @Composable (Modifier) -> Unit = { columnModifier ->
        Column(
            modifier = columnModifier,
            verticalArrangement = Arrangement.spacedBy(GymSpacing.XSmall)
        ) {
            Text(
                text = title,
                modifier = Modifier.semantics { heading() },
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
    if (trailing == null) {
        titleColumn(modifier.fillMaxWidth())
    } else {
        Row(
            modifier = modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
        ) {
            titleColumn(Modifier.weight(1f))
            trailing()
        }
    }
}

/** Brand fill shared with iOS (`GymTheme.brandFill`): solid base color per appearance. */
@Composable
fun brandFillColor(): Color =
    if (isSystemInDarkTheme()) BrandFillNight else BrandFill

/**
 * Primary-action colors shared with iOS (`GymPrimaryButtonStyle(fillColor: brandFill)`): the brand
 * fill with white content, so the button sits in the same blue family as the brand hero.
 */
@Composable
fun brandButtonColors(): ButtonColors {
    val fill = brandFillColor()
    return ButtonDefaults.buttonColors(
        containerColor = fill,
        contentColor = Color.White,
        disabledContainerColor = fill.copy(alpha = 0.6f),
        disabledContentColor = Color.White.copy(alpha = 0.85f)
    )
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
        val fontScale = androidx.compose.ui.platform.LocalDensity.current.fontScale
        val stackVertically = maxWidth < 280.dp || fontScale >= 1.8f
        val useTwoColumns = items.size >= 4 && (maxWidth < 480.dp || fontScale > 1.15f)
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
                    WordShrinkText(
                        text = item.label,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
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
        } else if (useTwoColumns) {
            Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(GymSpacing.Small)) {
                items.chunked(2).forEach { group ->
                    Row(horizontalArrangement = Arrangement.spacedBy(GymSpacing.Small)) {
                        group.forEach { item -> content(item, Modifier.weight(1f)) }
                        if (group.size == 1) androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                    }
                }
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
            // Four metrics as 3 + 1 would stretch the last tile across the row; keep a 2 x 2 grid.
            maxWidth < 330.dp || metrics.size == 4 -> 2
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
                        modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
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
    val accessibilityLabel = label ?: stringResource(R.string.state_loading)
    AppPanel(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .semantics(mergeDescendants = true) {
                    contentDescription = accessibilityLabel
                    liveRegion = LiveRegionMode.Polite
                }
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

/** Tabular figures on the default font, matching iOS `.monospacedDigit()` for numeric readouts. */
fun TextStyle.tabularDigits(): TextStyle = copy(fontFeatureSettings = "tnum")
