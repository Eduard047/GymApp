package com.example.gymapp.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState

/*
 * Android chrome in the Apple grammar (compose-apple-native): a plain navigation bar (accent chevron,
 * centred 17sp title, plain trailing actions, no boxes or borders) and a docked tab bar (hairline on
 * top, filled glyph when selected, no pill, no ripple).
 */

/** Height of the fixed navigation bar below the status bar. */
private val NavigationBarContentHeight = 48.dp

/** Height of the tab bar below its top hairline, above the navigation-bar inset. */
private val TabBarContentHeight = 56.dp

/** Tab labels follow the system text size up to this scale, then stop growing so every tab stays on one line. */
private const val TabLabelMaxFontScale = 1.3f

/** Back chevron, drawn as a stroke so it reads like the system one rather than a Material arrow. */
private val AppleBackChevron: ImageVector by lazy {
    ImageVector.Builder(
        name = "AppleBackChevron",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
        autoMirror = true
    ).path(
        stroke = SolidColor(Color.Black),
        strokeLineWidth = 2.6f,
        strokeLineCap = StrokeCap.Round,
        strokeLineJoin = StrokeJoin.Round
    ) {
        moveTo(15f, 4.5f)
        lineTo(7.5f, 12f)
        lineTo(15f, 19.5f)
    }.build()
}

private enum class NavigationBarSlot { Leading, Title, Trailing }

/**
 * Fixed navigation bar: [leading] on the left, [title] centred (17sp Semibold, one line, ellipsis),
 * [trailing] on the right. The title stays centred while it fits between the sides, otherwise it shifts
 * into the free span between them, and only then truncates; it never touches an action. No background, border or shadow: the screen ground shows through.
 */
@Composable
fun AppleNavigationBar(
    title: String,
    modifier: Modifier = Modifier,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null
) {
    val titleGap = 4.dp
    Layout(
        modifier = modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .height(NavigationBarContentHeight),
        content = {
            Box(Modifier.layoutId(NavigationBarSlot.Leading), contentAlignment = Alignment.CenterStart) {
                leading?.invoke()
            }
            Text(
                text = title,
                modifier = Modifier.layoutId(NavigationBarSlot.Title),
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onBackground,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Box(Modifier.layoutId(NavigationBarSlot.Trailing), contentAlignment = Alignment.CenterEnd) {
                trailing?.invoke()
            }
        }
    ) { measurables, constraints ->
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        val sideConstraints = constraints.copy(minWidth = 0, minHeight = 0, maxHeight = height)
        val leadingPlaceable = measurables.first { it.layoutId == NavigationBarSlot.Leading }.measure(sideConstraints)
        val trailingPlaceable = measurables.first { it.layoutId == NavigationBarSlot.Trailing }.measure(sideConstraints)
        val gap = titleGap.roundToPx()
        val titleMeasurable = measurables.first { it.layoutId == NavigationBarSlot.Title }
        // Centred when it fits between the two sides' wider half; otherwise it uses the whole free span
        // between the actions (off-centre) before it ever truncates.
        val centredMax = (width - 2 * (maxOf(leadingPlaceable.width, trailingPlaceable.width) + gap)).coerceAtLeast(0)
        val spanMax = (width - leadingPlaceable.width - trailingPlaceable.width - 2 * gap).coerceAtLeast(0)
        val titleConstraints = constraints.copy(minWidth = 0, minHeight = 0, maxHeight = height)
        val naturalWidth = titleMeasurable.maxIntrinsicWidth(height)
        val titlePlaceable = titleMeasurable.measure(
            titleConstraints.copy(maxWidth = if (naturalWidth <= centredMax) centredMax else spanMax)
        )
        val centredX = (width - titlePlaceable.width) / 2
        val titleX = centredX.coerceIn(
            leadingPlaceable.width + gap,
            (width - trailingPlaceable.width - gap - titlePlaceable.width).coerceAtLeast(leadingPlaceable.width + gap)
        )
        layout(width, height) {
            leadingPlaceable.placeRelative(0, (height - leadingPlaceable.height) / 2)
            trailingPlaceable.placeRelative(width - trailingPlaceable.width, (height - trailingPlaceable.height) / 2)
            titlePlaceable.placeRelative(titleX, (height - titlePlaceable.height) / 2)
        }
    }
}

/**
 * Plain accent chevron with a 48dp hit area: no container, border or ripple. [clickHint] replaces the
 * announced action ("minimize" instead of a plain click) the way the previous bar did.
 */
@Composable
fun AppleBackButton(
    onClick: () -> Unit,
    contentDescription: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    clickHint: String? = null
) {
    val source = remember { MutableInteractionSource() }
    Box(
        modifier = modifier
            .sizeIn(minWidth = 48.dp, minHeight = 48.dp)
            .pressScale(source)
            .clickable(
                interactionSource = source,
                indication = null,
                enabled = enabled,
                role = Role.Button,
                onClick = onClick
            )
            .semantics {
                if (clickHint != null) onClick(label = clickHint, action = null)
            },
        contentAlignment = Alignment.CenterStart
    ) {
        Icon(
            imageVector = AppleBackChevron,
            contentDescription = contentDescription,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier
                .padding(start = 8.dp)
                .size(26.dp)
                .alpha(if (enabled) 1f else 0.38f)
        )
    }
}

/** One tab of [AppleTabBar]. */
class AppleTabItem(
    val selected: Boolean,
    val label: String,
    val outlineIcon: ImageVector,
    val filledIcon: ImageVector,
    /** Spoken instead of [label] on the glyph when the tab carries a badge. */
    val badgeDescription: String? = null,
    val badgeCount: Int = 0,
    val modifier: Modifier = Modifier,
    val onClick: () -> Unit
)

/**
 * Docked tab bar: full width, [Color] background of the screen (or the glass material when [glassState] is
 * given and glass is active), hairline on top, 56dp plus the navigation-bar inset. Selected tab = primary
 * colour with the filled glyph, others `onSurfaceVariant` with the outline glyph. No pill, no ripple.
 * Every label has the same size (10sp Medium) at every font scale.
 */
@Composable
fun AppleTabBar(
    tabs: List<AppleTabItem>,
    modifier: Modifier = Modifier,
    glassState: HazeState? = null
) {
    val colors = MaterialTheme.colorScheme
    val glassActive = glassState != null && rememberGymGlassActive(glassState)
    val density = LocalDensity.current
    // sp is multiplied by the system font scale; cancel the part above the cap so labels stay equal and fit.
    val labelSize: TextUnit = (10f * minOf(density.fontScale, TabLabelMaxFontScale) / density.fontScale).sp
    Column(
        modifier = modifier
            .fillMaxWidth()
            .gymGlass(state = glassState, material = GymGlassMaterial.Bar, shape = RectangleShape)
            .background(if (glassActive) Color.Transparent else colors.background)
            .navigationBarsPadding()
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(Dp.Hairline)
                .background(colors.outlineVariant)
        )
        Row(
            Modifier
                .fillMaxWidth()
                .height(TabBarContentHeight)
                .selectableGroup()
        ) {
            tabs.forEach { tab ->
                val tint = if (tab.selected) colors.primary else colors.onSurfaceVariant
                Column(
                    modifier = tab.modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .selectable(
                            selected = tab.selected,
                            role = Role.Tab,
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = tab.onClick
                        ),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    BadgedBox(
                        badge = {
                            if (tab.badgeCount > 0) {
                                Badge { Text(tab.badgeCount.toString()) }
                            }
                        }
                    ) {
                        Icon(
                            imageVector = if (tab.selected) tab.filledIcon else tab.outlineIcon,
                            contentDescription = tab.badgeDescription?.takeIf { tab.badgeCount > 0 } ?: tab.label,
                            tint = tint,
                            modifier = Modifier.size(26.dp)
                        )
                    }
                    Text(
                        text = tab.label,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 2.dp),
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontSize = labelSize,
                            lineHeight = labelSize * 1.2f,
                            letterSpacing = 0.sp,
                            fontWeight = FontWeight.Medium
                        ),
                        color = tint,
                        textAlign = TextAlign.Center,
                        maxLines = 1,
                        softWrap = false,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}
