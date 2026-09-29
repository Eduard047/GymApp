package com.example.gymapp.ui.screens

import com.example.gymapp.ui.components.GymProgressBar
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.AchievementPreviewCard
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.theme.GymCompactShape
import com.example.gymapp.ui.theme.GymPanelShape
import com.example.gymapp.ui.viewmodel.MissionProgressUiModel
import com.example.gymapp.ui.viewmodel.WorkoutListUiState
import com.example.gymapp.util.asString
import com.example.gymapp.util.formatXp
import java.util.Locale

@Composable
fun MissionsScreen(
    uiState: WorkoutListUiState,
    onOpenRanks: () -> Unit = {},
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

    var selectedPeriodIndex by rememberSaveable { mutableIntStateOf(0) }
    val selectedPeriod = MissionPeriod.entries.getOrElse(selectedPeriodIndex) {
        MissionPeriod.Daily
    }
    val selectedMissions = when (selectedPeriod) {
        MissionPeriod.Daily -> uiState.dailyMissions
        MissionPeriod.Weekly -> uiState.weeklyMissions
        MissionPeriod.Monthly -> uiState.monthlyMissions
    }
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val levelSummary = stringResource(
        R.string.missions_level_summary,
        uiState.soloProgress.level,
        uiState.soloProgress.title,
        formatXp(uiState.soloProgress.totalXp, locale)
    )

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = 16.dp,
            vertical = 12.dp
        ),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            MissionLevelRow(summary = levelSummary, onClick = onOpenRanks)
        }

        item {
            MissionPeriodSelector(
                selectedPeriod = selectedPeriod,
                onPeriodSelected = { selectedPeriodIndex = it.ordinal }
            )
        }

        if (selectedMissions.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.missions_empty_title)
                )
            }
        } else {
            items(
                items = selectedMissions,
                key = { "${selectedPeriod.name}-${it.id}" }
            ) { mission ->
                MissionCard(mission = mission)
            }
        }

        item {
            AchievementPreviewCard(achievements = uiState.achievements)
        }
    }
}

@Composable
private fun MissionPeriodSelector(
    selectedPeriod: MissionPeriod,
    onPeriodSelected: (MissionPeriod) -> Unit,
    modifier: Modifier = Modifier
) {
    val groupLabel = stringResource(R.string.missions_period_group)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = groupLabel }
            .clip(GymCompactShape)
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.58f))
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.66f),
                shape = GymCompactShape
            )
            .padding(3.dp)
            .selectableGroup(),
        horizontalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        MissionPeriod.entries.forEach { period ->
            val selected = period == selectedPeriod
            Surface(
                modifier = Modifier
                    .weight(1f)
                    .selectable(
                        selected = selected,
                        onClick = { onPeriodSelected(period) },
                        role = Role.Tab
                    ),
                shape = GymCompactShape,
                color = if (selected) {
                    MaterialTheme.colorScheme.surface
                } else {
                    Color.Transparent
                },
                contentColor = if (selected) {
                    MaterialTheme.colorScheme.onSurface
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                tonalElevation = if (selected) 2.dp else 0.dp
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .padding(horizontal = 4.dp, vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = stringResource(period.titleRes),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

@Composable
private fun MissionLevelRow(
    summary: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val openRanks = stringResource(R.string.action_view_ranks)
    AppPanel(
        modifier = modifier
            .fillMaxWidth()
            .clip(GymPanelShape)
            .clickable(onClickLabel = openRanks, role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = Icons.Default.EmojiEvents,
                contentDescription = null,
                modifier = Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.primary
            )
            Text(
                text = summary,
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun MissionCard(
    mission: MissionProgressUiModel,
    modifier: Modifier = Modifier
) {
    val barColor = if (mission.isComplete) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.secondary
    }
    val statusText = if (mission.isComplete) {
        stringResource(R.string.missions_status_completed)
    } else {
        stringResource(R.string.missions_status_in_progress)
    }
    val progressValue = mission.progressFraction
        .takeIf(Float::isFinite)
        ?.coerceIn(0f, 1f)
        ?: 0f
    val accessibilityState = "${mission.cadenceLabel}. $statusText"

    AppPanel(
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                stateDescription = accessibilityState
                progressBarRangeInfo = ProgressBarRangeInfo(progressValue, 0f..1f)
            },
        highlighted = mission.isComplete
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 13.dp),
            verticalArrangement = Arrangement.spacedBy(9.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    modifier = Modifier.size(28.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = if (mission.isComplete) {
                            Icons.Default.Verified
                        } else {
                            missionIcon(mission.id)
                        },
                        contentDescription = null,
                        modifier = Modifier.size(24.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = mission.title,
                        modifier = Modifier.semantics { heading() },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = mission.summary,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                Column(
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = stringResource(
                            R.string.missions_progress_value,
                            mission.progress,
                            mission.goal
                        ),
                        style = MaterialTheme.typography.bodyMedium,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1
                    )
                    if (mission.isComplete) {
                        InfoPill(
                            text = stringResource(R.string.missions_status_completed),
                            leadingIcon = Icons.Default.Check
                        )
                    }
                }
            }

            GymProgressBar(
                progress = { progressValue },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(7.dp),
                color = barColor,
                trackColor = MaterialTheme.colorScheme.surfaceVariant
            )
        }
    }
}

private fun missionIcon(missionId: String): ImageVector = when {
    missionId == "daily-check-in" -> Icons.Default.FitnessCenter
    "active-days" in missionId -> Icons.Default.EventAvailable
    "workouts" in missionId -> Icons.Default.CalendarMonth
    "sets" in missionId -> Icons.Default.FormatListNumbered
    "exercises" in missionId -> Icons.Default.Dashboard
    else -> Icons.Default.TrackChanges
}

private enum class MissionPeriod(val titleRes: Int) {
    Daily(R.string.missions_daily_short),
    Weekly(R.string.missions_weekly_short),
    Monthly(R.string.missions_monthly_short)
}
