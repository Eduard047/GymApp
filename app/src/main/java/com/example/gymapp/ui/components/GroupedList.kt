package com.example.gymapp.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import com.example.gymapp.ui.theme.NightSeparator
import com.example.gymapp.ui.theme.SeparatorLight
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Metrics of the inset-grouped list (iOS Settings / Health grammar). */
object GroupedListDefaults {
    /** Container radius. */
    val CornerRadius = 12.dp

    /** Header and footer inset from the container edge; also the row's horizontal padding. */
    val TextInset = 16.dp

    val HeaderToCard = 8.dp
    val CardToFooter = 8.dp
    val RowMinHeight = 52.dp
    val RowPaddingVertical = 12.dp
    val IconTile = 30.dp
    val IconToText = 12.dp

    /** Separator inset for rows without a leading icon. */
    val SeparatorInset = 16.dp

    /** Separator inset when every row has a leading [GroupedRowIconTile]: 16 + 30 + 12. */
    val SeparatorInsetWithIcon = 58.dp
}

/** One physical pixel as Dp: `Dp.Hairline` only works for borders and collapses to 0 as a height. */
@Composable
internal fun hairlineThickness(): Dp = with(LocalDensity.current) { 1.toDp() }

/** Hairline colour of the grouped list: #38383A on dark surfaces, #C6C6C8 on light ones (iOS separators). */
@Composable
internal fun groupedSeparatorColor(): Color =
    if (MaterialTheme.colorScheme.background.luminance() < 0.5f) NightSeparator else SeparatorLight

/** Collects the rows of a [GroupedSection]; each one is separated from the next by a hairline. */
class GroupedScope internal constructor() {
    internal val rows = mutableListOf<@Composable () -> Unit>()

    /** Adds a free-form row (an inline editor, a segmented control, a custom layout). */
    fun row(content: @Composable () -> Unit) {
        rows += content
    }

    /** Adds a standard [GroupedRow]. */
    fun row(
        title: String,
        modifier: Modifier = Modifier,
        value: String? = null,
        icon: (@Composable () -> Unit)? = null,
        chevron: Boolean = false,
        titleColor: Color = Color.Unspecified,
        onClick: (() -> Unit)? = null,
        subtitle: String? = null,
        trailing: (@Composable () -> Unit)? = null,
        valueColor: Color = Color.Unspecified
    ) {
        rows += { GroupedRow(title, modifier, value, icon, chevron, titleColor, onClick, subtitle, trailing, valueColor) }
    }
}

/**
 * Inset-grouped list: an optional [header] above (13sp Medium, secondary, 8dp over the container), one
 * rounded container in the surface colour holding the rows with hairline separators, and an optional
 * [footer] below (13sp, secondary). The container carries no border and no shadow. Pass
 * [separatorInset] = [GroupedListDefaults.SeparatorInsetWithIcon] when every row has an icon tile.
 */
@Composable
fun GroupedSection(
    modifier: Modifier = Modifier,
    header: String? = null,
    footer: String? = null,
    separatorInset: Dp = GroupedListDefaults.SeparatorInset,
    content: GroupedScope.() -> Unit
) {
    val rows = GroupedScope().apply(content).rows
    Column(modifier.fillMaxWidth()) {
        if (header != null) {
            Text(
                text = header,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    start = GroupedListDefaults.TextInset,
                    end = GroupedListDefaults.TextInset,
                    bottom = GroupedListDefaults.HeaderToCard
                )
            )
        }
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(GroupedListDefaults.CornerRadius))
                .background(MaterialTheme.colorScheme.surface)
        ) {
            rows.forEachIndexed { index, row ->
                row()
                if (index < rows.lastIndex) {
                    Box(
                        Modifier
                            .padding(start = separatorInset)
                            .fillMaxWidth()
                            .height(hairlineThickness())
                            .background(groupedSeparatorColor())
                    )
                }
            }
        }
        if (footer != null) {
            Text(
                text = footer,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    start = GroupedListDefaults.TextInset,
                    end = GroupedListDefaults.TextInset,
                    top = GroupedListDefaults.CardToFooter
                )
            )
        }
    }
}

/**
 * One row of a [GroupedSection]: min 52dp, 16 x 12 padding, optional leading [icon] (usually a
 * [GroupedRowIconTile]), title on the left, secondary [value] and optional [chevron] on the right.
 * An optional one-line [subtitle] sits under the title and [trailing] holds a control such as a switch.
 * [titleColor] defaults to the primary text colour; use the accent for a trailing "Add ..." row and
 * the error colour for a destructive one. A clickable row shows the app press tint, no ripple.
 */
@Composable
fun GroupedRow(
    title: String,
    modifier: Modifier = Modifier,
    value: String? = null,
    icon: (@Composable () -> Unit)? = null,
    chevron: Boolean = false,
    titleColor: Color = Color.Unspecified,
    onClick: (() -> Unit)? = null,
    subtitle: String? = null,
    trailing: (@Composable () -> Unit)? = null,
    valueColor: Color = Color.Unspecified
) {
    val resolvedTitleColor = if (titleColor == Color.Unspecified) MaterialTheme.colorScheme.onSurface else titleColor
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = GroupedListDefaults.RowMinHeight)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .padding(
                horizontal = GroupedListDefaults.TextInset,
                vertical = GroupedListDefaults.RowPaddingVertical
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GroupedListDefaults.IconToText)
    ) {
        icon?.invoke()
        if (subtitle == null) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = resolvedTitleColor,
                modifier = Modifier.weight(1f)
            )
        } else {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyLarge,
                    color = resolvedTitleColor
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        if (value != null) {
            Text(
                text = value,
                style = MaterialTheme.typography.bodyLarge,
                color = if (valueColor == Color.Unspecified) MaterialTheme.colorScheme.onSurfaceVariant else valueColor,
                textAlign = TextAlign.End,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.widthIn(max = 180.dp)
            )
        }
        trailing?.invoke()
        if (chevron) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
            )
        }
    }
}

/** 30dp rounded tile with a white 18dp glyph on [tint]; the leading icon of a [GroupedRow]. */
@Composable
fun GroupedRowIconTile(
    icon: ImageVector,
    tint: Color,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .size(GroupedListDefaults.IconTile)
            .clip(RoundedCornerShape(7.dp))
            .background(tint),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(18.dp),
            tint = Color.White
        )
    }
}
