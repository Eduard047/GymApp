package com.example.gymapp.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.theme.TintedButton

/** Short explanation sheet opened from an (i) button: a title, one paragraph and a Close button. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InfoSheet(
    title: String,
    text: String,
    onDismiss: () -> Unit
) {
    GymModalBottomSheet(
        onDismissRequest = onDismiss,
        skipPartiallyExpanded = true
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = GymSpacing.XLarge)
                .padding(bottom = GymSpacing.XXLarge),
            verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.semantics { heading() }
            )
            Text(
                text = text,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            TintedButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.action_close))
            }
        }
    }
}

/**
 * Header line of a grouped block with an optional (i) button that opens an [InfoSheet] holding the
 * explanation that would otherwise sit under the title as filler text. Same metrics as the
 * [GroupedSection] header so the two read as one.
 */
@Composable
fun GroupedHeaderWithInfo(
    title: String,
    infoText: String?,
    modifier: Modifier = Modifier
) {
    var showInfo by rememberSaveable { mutableStateOf(false) }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = GroupedListDefaults.TextInset),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .weight(1f)
                .semantics { heading() }
        )
        if (infoText != null) {
            IconButton(onClick = { showInfo = true }) {
                Icon(
                    imageVector = Icons.Outlined.Info,
                    contentDescription = stringResource(R.string.progress_info_action),
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
    if (showInfo && infoText != null) {
        InfoSheet(title = title, text = infoText, onDismiss = { showInfo = false })
    }
}

/** A titled grouped block holding free-form [content] (a chart, a heat grid) in one container. */
@Composable
fun GroupedChartSection(
    title: String,
    modifier: Modifier = Modifier,
    infoText: String? = null,
    content: @Composable () -> Unit
) {
    Column(modifier.fillMaxWidth()) {
        GroupedHeaderWithInfo(title = title, infoText = infoText)
        GroupedSection {
            row { content() }
        }
    }
}
