package com.example.gymapp.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/** Icon column shared by every [SettingsRow], so titles line up whichever glyph a row uses. */
private val SettingsRowIconColumn = 28.dp
private val SettingsRowIconGap = 12.dp
private val SettingsPanelHorizontalPadding = 16.dp

/** What a [SettingsRow] shows at its trailing edge. */
enum class SettingsRowTrailing {
    None,
    /** The row opens another screen or sheet. */
    Chevron,
    /** The row leaves the app for a web page. */
    ExternalLink
}

/**
 * One surface holding a family of [SettingsRow]s. Rows are separated with
 * [SettingsRowDivider], which starts under the title rather than under the icon.
 */
@Composable
fun SettingsPanel(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    AppPanel(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(horizontal = SettingsPanelHorizontalPadding),
            content = content
        )
    }
}

/** Hairline between two rows of the same [SettingsPanel]. */
@Composable
fun SettingsRowDivider(modifier: Modifier = Modifier) {
    HorizontalDivider(
        modifier = modifier.padding(start = SettingsRowIconColumn + SettingsRowIconGap),
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.62f)
    )
}

/**
 * Compact settings row: brand-tinted icon column, one-line semibold title, optional secondary
 * subtitle that wraps to two lines. The whole row is the tap target when [onClick] is set.
 */
@Composable
fun SettingsRow(
    icon: ImageVector,
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    onClick: (() -> Unit)? = null,
    onClickLabel: String? = null,
    enabled: Boolean = true,
    trailing: SettingsRowTrailing = if (onClick != null) {
        SettingsRowTrailing.Chevron
    } else {
        SettingsRowTrailing.None
    },
    iconTint: Color = MaterialTheme.colorScheme.primary,
    titleColor: Color = MaterialTheme.colorScheme.onSurface,
    /** Replaces the [trailing] glyph, for rows whose trailing edge carries a value or menu. */
    trailingContent: (@Composable () -> Unit)? = null
) {
    val clickable = if (onClick != null) {
        Modifier.clickable(
            enabled = enabled,
            onClickLabel = onClickLabel,
            role = Role.Button,
            onClick = onClick
        )
    } else {
        Modifier
    }
    val dimmed = if (enabled) 1f else 0.5f
    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(clickable)
            .heightIn(min = if (subtitle == null) 48.dp else 56.dp)
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SettingsRowIconGap)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(24.dp),
            tint = iconTint.copy(alpha = iconTint.alpha * dimmed)
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = titleColor.copy(alpha = titleColor.alpha * dimmed),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            if (subtitle != null) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = dimmed),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        if (trailingContent != null) {
            trailingContent()
        } else when (trailing) {
            SettingsRowTrailing.None -> Unit
            SettingsRowTrailing.Chevron -> Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = dimmed)
            )
            SettingsRowTrailing.ExternalLink -> Icon(
                imageVector = Icons.AutoMirrored.Filled.OpenInNew,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = dimmed)
            )
        }
    }
}
