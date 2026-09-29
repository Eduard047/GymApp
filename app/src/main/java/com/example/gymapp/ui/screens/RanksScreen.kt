package com.example.gymapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.viewmodel.RankProgressUiModel
import com.example.gymapp.ui.viewmodel.WorkoutListUiState
import com.example.gymapp.util.asString
import com.example.gymapp.util.formatXp
import java.util.Locale

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

    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
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
                            stringResource(R.string.ranks_xp_value, formatXp(totalXp, locale)),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.82f)
                    )

                    if (nextRank != null) {
                        RankProgressTrack(
                            progress = heroProgress,
                            trackColor = Color.White.copy(alpha = 0.25f),
                            fillColor = Color.White,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(6.dp)
                                .clearAndSetSemantics { }
                        )

                        Text(
                            text = stringResource(
                                R.string.ranks_xp_to_next,
                                formatXp(nextRank.xpRemaining, locale),
                                nextRank.title
                            ),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.White.copy(alpha = 0.78f),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
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
            item {
                AppPanel(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        rankTiers.forEachIndexed { index, tier ->
                            RankLadderRow(
                                tier = tier,
                                isNext = tier.id == nextRank?.id,
                                nextProgress = heroProgress
                            )
                            if (index < rankTiers.lastIndex) {
                                HorizontalDivider(
                                    modifier = Modifier.padding(start = 50.dp),
                                    color = MaterialTheme.colorScheme.outlineVariant
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RankLadderRow(
    tier: RankProgressUiModel,
    isNext: Boolean,
    nextProgress: Float,
    modifier: Modifier = Modifier
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val iconColor = if (tier.isUnlocked) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    val statusText = when {
        tier.isCurrent -> stringResource(R.string.rank_status_current)
        tier.isUnlocked -> stringResource(R.string.rank_status_unlocked)
        else -> stringResource(R.string.rank_status_locked)
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .then(
                if (tier.isCurrent) {
                    Modifier.background(
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.08f),
                        RoundedCornerShape(12.dp)
                    )
                } else {
                    Modifier
                }
            )
            .padding(vertical = 10.dp)
            .semantics(mergeDescendants = true) {
                selected = tier.isCurrent
                stateDescription = statusText
            },
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(
                    if (tier.isUnlocked) {
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)
                    } else {
                        MaterialTheme.colorScheme.surfaceVariant
                    }
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = if (tier.isUnlocked) {
                    Icons.Default.EmojiEvents
                } else {
                    Icons.Default.Lock
                },
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = iconColor
            )
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = tier.title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = stringResource(
                    R.string.rank_level_from_xp,
                    tier.levelRequirement,
                    formatXp(tier.requiredXp, locale)
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (isNext) {
                RankProgressTrack(
                    progress = nextProgress,
                    trackColor = MaterialTheme.colorScheme.outlineVariant,
                    fillColor = MaterialTheme.colorScheme.primary,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(6.dp)
                )
                Text(
                    text = stringResource(R.string.rank_xp_to_go, formatXp(tier.xpRemaining, locale)),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

/** Capsule progress bar with a deliberately visible track, matching the iOS ranks screen. */
@Composable
private fun RankProgressTrack(
    progress: Float,
    trackColor: Color,
    fillColor: Color,
    modifier: Modifier = Modifier
) {
    val fraction = progress.takeIf(Float::isFinite)?.coerceIn(0f, 1f) ?: 0f
    Box(
        modifier = modifier
            .clip(CircleShape)
            .background(trackColor)
    ) {
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .fillMaxWidth(fraction)
                .clip(CircleShape)
                .background(fillColor)
        )
    }
}
