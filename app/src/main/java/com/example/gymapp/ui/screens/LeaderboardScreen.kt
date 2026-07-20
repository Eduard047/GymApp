package com.example.gymapp.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.auth.LeaderboardRow
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.viewmodel.SoloProgressUiModel
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.asString

@Composable
fun LeaderboardScreen(
    rows: List<LeaderboardRow>,
    soloProgress: SoloProgressUiModel,
    isLoading: Boolean,
    error: LocalizedText?,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, top = 10.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            HeroPanel(modifier = Modifier.fillMaxWidth()) {
                BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                    if (maxWidth < 380.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            LeaderboardHeroCopy()
                            LeaderboardHeroStats(
                                soloProgress = soloProgress,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    } else {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(16.dp),
                            verticalAlignment = Alignment.Top
                        ) {
                            LeaderboardHeroCopy(modifier = Modifier.weight(1f))
                            LeaderboardHeroStats(
                                soloProgress = soloProgress,
                                modifier = Modifier.width(138.dp)
                            )
                        }
                    }
                }
            }
        }

        item {
            AppPanel(
                modifier = Modifier.fillMaxWidth(),
                highlighted = true
            ) {
                BoxWithConstraints(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp)
                ) {
                    if (maxWidth < 380.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            LeaderboardRefreshCopy(isLoading = isLoading)
                            LeaderboardRefreshButton(
                                isLoading = isLoading,
                                onRefresh = onRefresh,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    } else {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            LeaderboardRefreshCopy(
                                isLoading = isLoading,
                                modifier = Modifier.weight(1f)
                            )
                            LeaderboardRefreshButton(
                                isLoading = isLoading,
                                onRefresh = onRefresh
                            )
                        }
                    }
                }
            }
        }

        error?.let { message ->
            item {
                LeaderboardStatusBanner(message = message.asString())
            }
        }

        if (rows.isEmpty() && !isLoading) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.leaderboard_empty),
                    supporting = stringResource(R.string.leaderboard_hero_supporting),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        itemsIndexed(rows) { index, row ->
            LeaderboardRowCard(place = index + 1, row = row)
        }
    }
}

@Composable
private fun LeaderboardHeroCopy(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.EmojiEvents,
                contentDescription = null,
                tint = Color.White
            )
            Text(
                text = stringResource(R.string.leaderboard_hero_title),
                style = MaterialTheme.typography.headlineMedium,
                color = Color.White
            )
        }
        Text(
            text = stringResource(R.string.leaderboard_hero_supporting),
            style = MaterialTheme.typography.bodyMedium,
            color = Color.White.copy(alpha = 0.84f)
        )
    }
}

@Composable
private fun LeaderboardHeroStats(
    soloProgress: SoloProgressUiModel,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(7.dp)
    ) {
        MetricTile(
            label = stringResource(R.string.leaderboard_your_xp),
            value = "${soloProgress.totalXp} XP",
            modifier = Modifier.fillMaxWidth(),
            emphasized = true,
            onHero = true
        )
        Text(
            text = "${stringResource(R.string.solo_level_badge, soloProgress.level)} • ${soloProgress.title}",
            style = MaterialTheme.typography.labelMedium,
            color = Color.White.copy(alpha = 0.80f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun LeaderboardRefreshCopy(
    isLoading: Boolean,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            text = stringResource(R.string.leaderboard_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = if (isLoading) {
                stringResource(R.string.leaderboard_loading_supporting)
            } else {
                stringResource(R.string.leaderboard_synced_supporting)
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun LeaderboardRefreshButton(
    isLoading: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier
) {
    Button(
        onClick = onRefresh,
        enabled = !isLoading,
        modifier = modifier
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                color = Color.White,
                strokeWidth = 2.dp
            )
        } else {
            Icon(
                imageVector = Icons.Default.Refresh,
                contentDescription = null
            )
        }
        Text(
            text = if (isLoading) {
                stringResource(R.string.leaderboard_loading_action)
            } else {
                stringResource(R.string.leaderboard_refresh_action)
            },
            modifier = Modifier.padding(start = 8.dp)
        )
    }
}

@Composable
private fun LeaderboardStatusBanner(
    message: String,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.error.copy(alpha = 0.11f),
        contentColor = MaterialTheme.colorScheme.onSurface,
        shape = MaterialTheme.shapes.extraSmall,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.error.copy(alpha = 0.26f))
    ) {
        Text(
            text = message,
            modifier = Modifier.padding(12.dp),
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 6,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun LeaderboardRowCard(
    place: Int,
    row: LeaderboardRow,
    modifier: Modifier = Modifier
) {
    val placeColor = when (place) {
        1 -> MaterialTheme.colorScheme.tertiary
        2 -> MaterialTheme.colorScheme.secondary
        3 -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }

    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = row.isCurrentUser
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Surface(
                modifier = Modifier
                    .width(50.dp)
                    .heightIn(min = 50.dp),
                color = placeColor.copy(alpha = 0.14f),
                contentColor = placeColor,
                shape = MaterialTheme.shapes.small,
                border = BorderStroke(1.dp, placeColor.copy(alpha = 0.28f))
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    if (place <= 3) {
                        Icon(
                            imageVector = Icons.Default.EmojiEvents,
                            contentDescription = null,
                            modifier = Modifier.size(15.dp)
                        )
                    }
                    Text(
                        text = place.toString(),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = row.displayName.ifBlank {
                        stringResource(R.string.leaderboard_unknown_user)
                    },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = stringResource(R.string.leaderboard_row_detail, row.level, row.workouts),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Text(
                text = "${row.xp} XP",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = if (row.isCurrentUser) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurface
                }
            )
        }
    }
}
