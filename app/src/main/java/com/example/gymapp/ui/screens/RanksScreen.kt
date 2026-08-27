package com.example.gymapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.viewmodel.RankProgressUiModel
import com.example.gymapp.ui.viewmodel.WorkoutListUiState
import com.example.gymapp.util.asString

@Composable
fun RanksScreen(
    uiState: WorkoutListUiState,
    onRetryLoad: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    if (uiState.isLoading) {
        Box(
            modifier = modifier.fillMaxSize().padding(horizontal = 16.dp),
            contentAlignment = Alignment.Center
        ) {
            LoadingStatePanel(label = stringResource(R.string.workouts_loading))
        }
        return
    }
    uiState.loadError?.let { error ->
        Box(
            modifier = modifier.fillMaxSize().padding(horizontal = 16.dp),
            contentAlignment = Alignment.Center
        ) {
            EmptyStatePanel(
                title = error.asString(),
                actionLabel = stringResource(R.string.action_retry),
                onAction = onRetryLoad
            )
        }
        return
    }

    val totalXp = uiState.soloProgress.totalXp
    val rankTiers = uiState.rankLadder
        .sortedWith(compareBy<RankProgressUiModel> { it.requiredXp }.thenBy { it.levelRequirement })
    val currentRank = rankTiers.firstOrNull { it.isCurrent }
        ?: rankTiers.lastOrNull { it.isUnlocked }
    val nextRank = currentRank?.let { rank ->
        rankTiers.firstOrNull { it.requiredXp > rank.requiredXp }
    } ?: rankTiers.firstOrNull { !it.isUnlocked }
    val heroProgress = when {
        nextRank != null -> nextRank.progressFraction
        rankTiers.isNotEmpty() -> 1f
        else -> uiState.soloProgress.progressFraction
    }.takeIf(Float::isFinite)?.coerceIn(0f, 1f) ?: 0f
    val currentTitle = currentRank?.title ?: uiState.soloProgress.title

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = 16.dp,
            vertical = 12.dp
        ),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            HeroPanel(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.EmojiEvents,
                            contentDescription = null,
                            modifier = Modifier.size(30.dp),
                            tint = Color.White
                        )
                        Text(
                            text = currentTitle,
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                    }

                    Text(
                        text = "${stringResource(R.string.post_workout_level, uiState.soloProgress.level)} · " +
                            stringResource(R.string.solo_month_xp_value, totalXp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.82f)
                    )

                    LinearProgressIndicator(
                        progress = { heroProgress },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(7.dp),
                        color = Color.White,
                        trackColor = Color.White.copy(alpha = 0.18f)
                    )

                    Text(
                        text = if (nextRank != null) {
                            "${stringResource(R.string.solo_next_title_label)}: ${nextRank.title} · " +
                                stringResource(
                                    R.string.post_workout_level,
                                    nextRank.levelRequirement
                                )
                        } else {
                            stringResource(R.string.ranks_current_title_value, currentTitle)
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.78f),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
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
    val iconColor = if (tier.isUnlocked) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    val progressColor = if (tier.isUnlocked) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.secondary
    }
    val statusText = when {
        tier.isCurrent -> stringResource(R.string.rank_status_current)
        tier.isUnlocked -> stringResource(R.string.rank_status_unlocked)
        else -> stringResource(R.string.rank_status_locked)
    }
    val progressValue = (if (tier.isUnlocked) 1f else tier.progressFraction)
        .takeIf(Float::isFinite)
        ?.coerceIn(0f, 1f)
        ?: 0f
    val progressText = stringResource(
        R.string.rank_progress_value,
        totalXp.coerceAtMost(tier.requiredXp),
        tier.requiredXp
    )
    val remainingText = if (tier.isUnlocked) {
        null
    } else {
        stringResource(R.string.rank_xp_left, tier.xpRemaining)
    }
    val accessibilityState = listOfNotNull(statusText, progressText, remainingText).joinToString(". ")

    AppPanel(
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                stateDescription = accessibilityState
                progressBarRangeInfo = ProgressBarRangeInfo(progressValue, 0f..1f)
            },
        highlighted = tier.isCurrent
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(iconColor.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = if (tier.isUnlocked) {
                        Icons.Default.EmojiEvents
                    } else {
                        Icons.Default.Lock
                    },
                    contentDescription = null,
                    modifier = Modifier.size(23.dp),
                    tint = iconColor
                )
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = tier.title,
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (tier.isCurrent) {
                        InfoPill(
                            text = stringResource(R.string.rank_status_current),
                            accent = MaterialTheme.colorScheme.primary
                        )
                    }
                }

                Text(
                    text = "${stringResource(R.string.post_workout_level, tier.levelRequirement)} · " +
                        stringResource(R.string.solo_month_xp_value, tier.requiredXp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                LinearProgressIndicator(
                    progress = { progressValue },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(6.dp),
                    color = progressColor,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant
                )
            }
        }
    }
}
