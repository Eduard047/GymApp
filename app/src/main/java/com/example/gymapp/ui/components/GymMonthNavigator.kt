package com.example.gymapp.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.NavigateBefore
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R

/**
 * Compact inline month control shared with iOS (`GymMonthNavigator`): no card, 44dp chevrons and
 * a centre label that also returns to the current month when another month is selected.
 */
@Composable
fun GymMonthNavigator(
    monthLabel: String,
    isCurrentMonth: Boolean,
    onPrevious: () -> Unit,
    onCurrent: () -> Unit,
    onNext: () -> Unit,
    modifier: Modifier = Modifier
) {
    val centerDescription = stringResource(
        if (isCurrentMonth) R.string.cd_month_current else R.string.cd_month_return,
        monthLabel
    )
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        IconButton(onClick = onPrevious, modifier = Modifier.size(44.dp)) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.NavigateBefore,
                contentDescription = stringResource(R.string.cd_prev_month),
                modifier = Modifier.size(20.dp)
            )
        }
        Row(
            modifier = Modifier
                .heightIn(min = 44.dp)
                .clickable(enabled = !isCurrentMonth, role = Role.Button, onClick = onCurrent)
                .semantics { contentDescription = centerDescription },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Text(
                text = monthLabel,
                modifier = Modifier.clearAndSetSemantics { },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            if (isCurrentMonth) {
                Text(
                    text = stringResource(R.string.action_current_month),
                    modifier = Modifier.clearAndSetSemantics { },
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1
                )
            }
        }
        IconButton(
            onClick = onNext,
            enabled = !isCurrentMonth,
            modifier = Modifier.size(44.dp)
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.NavigateNext,
                contentDescription = stringResource(R.string.cd_next_month),
                modifier = Modifier.size(20.dp)
            )
        }
    }
}
