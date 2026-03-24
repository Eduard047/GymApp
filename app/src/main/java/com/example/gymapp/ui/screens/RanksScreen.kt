package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.viewmodel.RankProgressUiModel
import com.example.gymapp.ui.viewmodel.WorkoutListUiState

@Composable
fun RanksScreen(
    uiState: WorkoutListUiState,
    modifier: Modifier = Modifier
) {
    val totalXp = uiState.soloProgress.totalXp
    val rankTiers = uiState.rankLadder
        .sortedWith(compareBy<RankProgressUiModel> { it.requiredXp }.thenBy { it.levelRequirement })

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = 12.dp,
            vertical = 10.dp
        ),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            HeroPanel(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            text = stringResource(R.string.title_ranks),
                            style = MaterialTheme.typography.headlineMedium,
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                        Text(
                            text = stringResource(R.string.ranks_supporting),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.88f)
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        MetricTile(
                            label = stringResource(R.string.solo_total_xp),
                            value = totalXp.toString(),
                            modifier = Modifier.weight(1f),
                            emphasized = true,
                            onHero = true
                        )
                        MetricTile(
                            label = stringResource(R.string.ranks_current_level_label),
                            value = uiState.soloProgress.level.toString(),
                            modifier = Modifier.weight(1f),
                            onHero = true
                        )
                    }

                    Text(
                        text = stringResource(
                            R.string.ranks_current_title_value,
                            uiState.soloProgress.title
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.82f)
                    )
                }
            }
        }

        if (rankTiers.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.ranks_empty_title),
                    supporting = stringResource(R.string.ranks_empty_supporting)
                )
            }
        } else {
            items(
                items = rankTiers,
                key = { it.id }
            ) { tier ->
                RankTierCard(
                    tier = tier,
                    totalXp = totalXp
                )
            }
        }
    }
}

@Composable
private fun RankTierCard(
    tier: RankProgressUiModel,
    totalXp: Int,
    modifier: Modifier = Modifier
) {
    val accentColor = when {
        tier.isCurrent -> MaterialTheme.colorScheme.tertiary
        tier.isUnlocked -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    val statusText = when {
        tier.isCurrent -> stringResource(R.string.rank_status_current)
        tier.isUnlocked -> stringResource(R.string.rank_status_unlocked)
        else -> stringResource(R.string.rank_status_locked)
    }
    val progressValue = if (tier.isUnlocked) 1f else tier.progressFraction.coerceIn(0f, 1f)
    val progressText = stringResource(
        R.string.rank_progress_value,
        totalXp.coerceAtMost(tier.requiredXp),
        tier.requiredXp
    )

    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = tier.isCurrent
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = tier.title,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = if (tier.isCurrent) {
                            stringResource(R.string.rank_status_current)
                        } else if (tier.isUnlocked) {
                            stringResource(R.string.rank_status_unlocked)
                        } else {
                            stringResource(R.string.rank_status_locked)
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                InfoPill(
                    text = statusText,
                    accent = accentColor
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.rank_required_level_label),
                    value = tier.levelRequirement.toString(),
                    modifier = Modifier.weight(1f)
                )
                MetricTile(
                    label = stringResource(R.string.rank_required_xp_label),
                    value = tier.requiredXp.toString(),
                    modifier = Modifier.weight(1f)
                )
            }

            LinearProgressIndicator(
                progress = { progressValue },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp),
                color = accentColor,
                trackColor = MaterialTheme.colorScheme.surfaceVariant
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = progressText,
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (!tier.isUnlocked) {
                    Text(
                        text = stringResource(R.string.rank_xp_left, tier.xpRemaining),
                        style = MaterialTheme.typography.labelLarge,
                        color = accentColor,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}
