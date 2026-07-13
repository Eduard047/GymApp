package com.example.gymapp.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.viewmodel.AchievementPreviewUiModel
import com.example.gymapp.ui.viewmodel.ActivityHeatmapDayUiModel
import com.example.gymapp.ui.viewmodel.ActivityHeatmapUiModel
import com.example.gymapp.ui.viewmodel.MissionProgressUiModel
import com.example.gymapp.ui.viewmodel.SoloProgressUiModel

@Composable
fun SoloProgressHero(
    progress: SoloProgressUiModel,
    modifier: Modifier = Modifier
) {
    HeroPanel(modifier = modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(
                text = stringResource(R.string.solo_progress_eyebrow),
                style = MaterialTheme.typography.labelLarge,
                color = Color.White.copy(alpha = 0.84f)
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Surface(
                        color = Color.White.copy(alpha = 0.12f),
                        contentColor = Color.White,
                        shape = MaterialTheme.shapes.large,
                        border = BorderStroke(
                            width = 1.dp,
                            color = Color.White.copy(alpha = 0.14f)
                        )
                    ) {
                        Text(
                            text = stringResource(R.string.solo_level_badge, progress.level),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp)
                        )
                    }
                    Text(
                        text = progress.title,
                        style = MaterialTheme.typography.headlineMedium,
                        color = Color.White
                    )
                    Text(
                        text = progress.summary,
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.88f)
                    )
                }

                Surface(
                    color = Color.White.copy(alpha = 0.12f),
                    contentColor = Color.White,
                    shape = MaterialTheme.shapes.large,
                    border = BorderStroke(
                        width = 1.dp,
                        color = Color.White.copy(alpha = 0.14f)
                    )
                ) {
                    Column(
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                        horizontalAlignment = Alignment.End
                    ) {
                        Text(
                            text = stringResource(R.string.solo_total_xp),
                            style = MaterialTheme.typography.labelMedium,
                            color = Color.White.copy(alpha = 0.74f)
                        )
                        Text(
                            text = progress.totalXp.toString(),
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = stringResource(R.string.solo_total_xp_earned),
                            style = MaterialTheme.typography.bodySmall,
                            color = Color.White.copy(alpha = 0.76f)
                        )
                    }
                }
            }

            LinearProgressIndicator(
                progress = { progress.progressFraction },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(10.dp)
                    .clip(MaterialTheme.shapes.small),
                color = Color.White,
                trackColor = Color.White.copy(alpha = 0.2f)
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SoloHeroStat(
                    label = stringResource(R.string.solo_month_xp_label),
                    value = stringResource(R.string.solo_month_xp_value, progress.monthXp),
                    modifier = Modifier.weight(1f),
                    emphasized = true
                )
                SoloHeroStat(
                    label = stringResource(R.string.solo_streak_label),
                    value = stringResource(
                        R.string.solo_streak_weekly_value,
                        progress.weeklyStreakWeeks
                    ),
                    modifier = Modifier.weight(1f)
                )
                SoloHeroStat(
                    label = stringResource(R.string.solo_next_title_label),
                    value = progress.nextTitle,
                    modifier = Modifier.weight(1f)
                )
            }

            Text(
                text = stringResource(
                    R.string.solo_xp_to_next_level,
                    progress.currentLevelXp,
                    progress.xpForNextLevel
                ),
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.8f)
            )
        }
    }
}

@Composable
fun ActivityHeatmapCard(
    heatmap: ActivityHeatmapUiModel,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = stringResource(R.string.activity_heatmap_title),
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = heatmap.monthLabel,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = stringResource(R.string.activity_heatmap_active_days, heatmap.activeDays),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.activity_heatmap_sessions),
                    value = heatmap.sessionCount.toString(),
                    modifier = Modifier.weight(1f)
                )
                MetricTile(
                    label = stringResource(R.string.activity_heatmap_volume),
                    value = heatmap.totalVolume.toInt().toString(),
                    modifier = Modifier.weight(1f)
                )
            }

            Text(
                text = stringResource(R.string.activity_heatmap_legend),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                stringArrayResource(R.array.activity_heatmap_weekdays).forEach { weekday ->
                    Text(
                        text = weekday,
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .weight(1f)
                            .clearAndSetSemantics { }
                    )
                }
            }

            heatmap.weeks.forEach { week ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    week.forEach { day ->
                        HeatmapDayCell(
                            day = day,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.activity_heatmap_less),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                repeat(4) { index ->
                    val intensity = (index + 1) / 4f
                    Box(
                        modifier = Modifier
                            .size(12.dp)
                            .clip(MaterialTheme.shapes.extraSmall)
                            .background(heatmapColor(intensity, true, false))
                    )
                }
                Text(
                    text = stringResource(R.string.activity_heatmap_more),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
fun MissionProgressCard(
    title: String,
    supporting: String,
    missions: List<MissionProgressUiModel>,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = supporting,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            missions.forEach { mission ->
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            Text(
                                text = mission.title,
                                style = MaterialTheme.typography.titleSmall
                            )
                            Text(
                                text = mission.summary,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        InfoPill(
                            text = mission.cadenceLabel,
                            accent = if (mission.isComplete) {
                                MaterialTheme.colorScheme.tertiary
                            } else {
                                MaterialTheme.colorScheme.primary
                            }
                        )
                    }

                    LinearProgressIndicator(
                        progress = { mission.progressFraction },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(8.dp)
                            .clip(MaterialTheme.shapes.small),
                        color = if (mission.isComplete) {
                            MaterialTheme.colorScheme.tertiary
                        } else {
                            MaterialTheme.colorScheme.primary
                        },
                        trackColor = MaterialTheme.colorScheme.surfaceVariant
                    )

                    Text(
                        text = mission.progressLabel,
                        style = MaterialTheme.typography.labelLarge,
                        color = if (mission.isComplete) {
                            MaterialTheme.colorScheme.tertiary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        }
                    )
                }
            }
        }
    }
}

@Composable
fun AchievementPreviewCard(
    achievements: List<AchievementPreviewUiModel>,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.achievements_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.achievements_supporting),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            achievements.forEach { achievement ->
                val accentColor = if (achievement.isUnlocked) {
                    MaterialTheme.colorScheme.tertiary
                } else {
                    MaterialTheme.colorScheme.primary
                }
                val badgeText = "${(achievement.progressFraction * 100).toInt().coerceIn(0, 100)}%"

                Surface(
                    color = if (achievement.isUnlocked) {
                        accentColor.copy(alpha = 0.1f)
                    } else {
                        MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.46f)
                    },
                    shape = MaterialTheme.shapes.large,
                    border = BorderStroke(
                        width = 1.dp,
                        color = accentColor.copy(alpha = if (achievement.isUnlocked) 0.24f else 0.14f)
                    )
                ) {
                    Row(
                        modifier = Modifier.padding(14.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        Box(
                            modifier = Modifier
                                .size(42.dp)
                                .clip(MaterialTheme.shapes.medium)
                                .background(accentColor.copy(alpha = 0.14f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = badgeText,
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = FontWeight.Bold,
                                color = accentColor
                            )
                        }

                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.Top
                            ) {
                                Column(
                                    modifier = Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(2.dp)
                                ) {
                                    Text(
                                        text = achievement.title,
                                        style = MaterialTheme.typography.titleSmall
                                    )
                                    Text(
                                        text = achievement.description,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Text(
                                    text = achievement.statusLabel,
                                    style = MaterialTheme.typography.labelLarge,
                                    color = accentColor,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }

                            LinearProgressIndicator(
                                progress = { achievement.progressFraction },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(6.dp)
                                    .clip(MaterialTheme.shapes.small),
                                color = accentColor,
                                trackColor = MaterialTheme.colorScheme.surfaceVariant
                            )

                            Text(
                                text = achievement.progressLabel,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SoloHeroStat(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    emphasized: Boolean = false
) {
    Surface(
        modifier = modifier,
        color = Color.White.copy(alpha = if (emphasized) 0.18f else 0.1f),
        contentColor = Color.White,
        shape = MaterialTheme.shapes.large,
        border = BorderStroke(
            width = 1.dp,
            color = Color.White.copy(alpha = if (emphasized) 0.2f else 0.12f)
        )
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = Color.White.copy(alpha = 0.72f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = value,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun HeatmapDayCell(
    day: ActivityHeatmapDayUiModel,
    modifier: Modifier = Modifier
) {
    val cellShape = RoundedCornerShape(7.dp)
    val backgroundColor = heatmapColor(
        intensity = day.intensity,
        isCurrentMonth = day.isCurrentMonth,
        isToday = day.isToday
    )
    val accessibilityDescription = if (day.isCurrentMonth) {
        stringResource(
            R.string.activity_heatmap_day_a11y,
            day.dayLabel,
            day.sessionCount,
            day.totalVolume.toInt()
        )
    } else {
        ""
    }

    val accessibilityModifier = if (day.isCurrentMonth) {
        Modifier.semantics {
            contentDescription = accessibilityDescription
        }
    } else {
        Modifier.clearAndSetSemantics { }
    }

    Box(
        modifier = modifier
            .height(38.dp)
            .then(accessibilityModifier)
            .clip(cellShape)
            .background(backgroundColor)
            .border(
                width = if (day.isToday) 2.dp else 0.dp,
                color = if (day.isToday) MaterialTheme.colorScheme.primary else Color.Transparent,
                shape = cellShape
            ),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = day.dayNumber?.toString().orEmpty(),
            style = MaterialTheme.typography.labelMedium,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold,
            color = if (day.isCurrentMonth && day.intensity > 0.55f) {
                MaterialTheme.colorScheme.onPrimary
            } else {
                MaterialTheme.colorScheme.onSurface.copy(alpha = if (day.isCurrentMonth) 0.82f else 0.22f)
            },
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun heatmapColor(
    intensity: Float,
    isCurrentMonth: Boolean,
    isToday: Boolean
): Color {
    if (!isCurrentMonth) {
        return MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.24f)
    }

    val base = when {
        intensity <= 0f -> MaterialTheme.colorScheme.surfaceVariant
        intensity < 0.35f -> MaterialTheme.colorScheme.secondary.copy(alpha = 0.28f)
        intensity < 0.7f -> MaterialTheme.colorScheme.primary.copy(alpha = 0.42f)
        else -> MaterialTheme.colorScheme.tertiary.copy(alpha = 0.72f)
    }

    return if (isToday) {
        base.copy(alpha = 0.95f)
    } else {
        base
    }
}
