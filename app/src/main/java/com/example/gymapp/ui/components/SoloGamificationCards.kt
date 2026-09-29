package com.example.gymapp.ui.components

import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import com.example.gymapp.util.DateTimeUtils
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import com.example.gymapp.ui.screens.formatTodayHeroCount
import com.example.gymapp.ui.screens.formatTodayHeroVolume
import com.example.gymapp.ui.viewmodel.TodayHeroMetricsUiModel
import com.example.gymapp.util.formatXp
import java.text.NumberFormat
import java.util.Locale
import com.example.gymapp.data.repository.BadgeRarity
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Replay
import com.example.gymapp.ui.viewmodel.AchievementPreviewUiModel
import com.example.gymapp.ui.viewmodel.ActivityHeatmapDayUiModel
import com.example.gymapp.ui.viewmodel.ActivityHeatmapUiModel
import com.example.gymapp.ui.viewmodel.MissionProgressUiModel
import com.example.gymapp.ui.viewmodel.SoloProgressUiModel

@Composable
fun SoloProgressHero(
    progress: SoloProgressUiModel,
    modifier: Modifier = Modifier,
    onOpenRanks: () -> Unit = {}
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val xpToNext = stringResource(
        R.string.solo_xp_to_next_level,
        progress.currentLevelXp,
        progress.xpForNextLevel
    )
    BrandHeroPanel(modifier = modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                text = stringResource(R.string.solo_progress_eyebrow),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.8f)
            )

            SoloHeroIdentity(progress = progress, locale = locale)

            GymProgressBar(
                progress = { progress.progressFraction },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .semantics { contentDescription = xpToNext },
                color = Color.White,
                trackColor = Color.White.copy(alpha = 0.2f)
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.solo_month_xp_label),
                    value = stringResource(R.string.solo_xp_amount, formatXp(progress.monthXp, locale)),
                    modifier = Modifier.weight(1f),
                    emphasized = true,
                    onHero = true,
                    compactValue = true
                )
                MetricTile(
                    label = stringResource(R.string.solo_next_title_label),
                    value = if (progress.isTopRank) {
                        stringResource(R.string.solo_top_rank)
                    } else {
                        progress.nextTitle
                    },
                    modifier = Modifier.weight(1f),
                    emphasized = true,
                    onHero = true,
                    compactValue = true
                )
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color.White.copy(alpha = 0.13f))
                    .clickable(role = Role.Button, onClick = onOpenRanks)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)
            ) {
                Icon(
                    imageVector = Icons.Default.EmojiEvents,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = Color.White
                )
                Text(
                    text = stringResource(R.string.action_view_ranks),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White
                )
            }
        }
    }
}

/**
 * Level pill, rank title and total XP. The XP sits at the trailing edge of the pill/title row
 * when that row fits on one line, and moves to its own "N XP earned" line otherwise.
 */
@Composable
private fun SoloHeroIdentity(progress: SoloProgressUiModel, locale: Locale) {
    val levelText = stringResource(R.string.solo_level_badge, progress.level)
    val compactXp = stringResource(R.string.solo_xp_amount, formatXp(progress.totalXp, locale))
    val earnedXp = stringResource(R.string.solo_total_xp_earned_line, formatXp(progress.totalXp, locale))
    val totalXpLabel = stringResource(R.string.solo_total_xp)
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val pillStyle = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold)
    val titleStyle = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold)
    val xpStyle = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = "$totalXpLabel: ${formatXp(progress.totalXp, locale)}"
            },
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
            val fitsOnOneLine = remember(
                levelText, progress.title, compactXp, maxWidth, density, pillStyle, titleStyle, xpStyle
            ) {
                val available = with(density) { maxWidth.roundToPx() }
                val gap = with(density) { 8.dp.roundToPx() }
                val pillPadding = with(density) { 22.dp.roundToPx() }
                fun width(text: String, style: TextStyle) =
                    measurer.measure(text, style, maxLines = 1, softWrap = false).size.width
                val pill = width(levelText, pillStyle) + pillPadding
                val title = width(progress.title, titleStyle)
                val xp = width(compactXp, xpStyle)
                pill + gap + title + gap + xp <= available
            }
            if (fitsOnOneLine) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    SoloLevelPill(text = levelText, style = pillStyle)
                    Text(
                        text = progress.title,
                        style = titleStyle,
                        color = Color.White,
                        maxLines = 1,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        text = compactXp,
                        style = xpStyle,
                        color = Color.White,
                        maxLines = 1
                    )
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        SoloLevelPill(text = levelText, style = pillStyle)
                        Text(
                            text = progress.title,
                            style = titleStyle,
                            color = Color.White,
                            modifier = Modifier.weight(1f)
                        )
                    }
                    Text(
                        text = earnedXp,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.9f)
                    )
                }
            }
        }
        Text(
            text = progress.summary,
            style = MaterialTheme.typography.bodyMedium,
            color = Color.White.copy(alpha = 0.86f)
        )
    }
}

@Composable
private fun SoloLevelPill(text: String, style: TextStyle) {
    Text(
        text = text,
        style = style,
        color = Color.White,
        maxLines = 1,
        softWrap = false,
        modifier = Modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(Color.White.copy(alpha = 0.13f))
            .padding(horizontal = 11.dp, vertical = 7.dp)
    )
}

@Composable
fun LifetimeProgressCard(
    metrics: TodayHeroMetricsUiModel,
    modifier: Modifier = Modifier
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.progress_lifetime_title),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.semantics { heading() }
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.progress_lifetime_workouts),
                    value = NumberFormat.getIntegerInstance(locale)
                        .format(metrics.totalWorkouts.coerceAtLeast(0).toLong()),
                    modifier = Modifier.weight(1f),
                    emphasized = true
                )
                MetricTile(
                    label = stringResource(R.string.focus_lens_week_streak),
                    value = stringResource(
                        R.string.focus_lens_week_streak_value,
                        metrics.weeklyStreakWeeks
                    ),
                    modifier = Modifier.weight(1f),
                    emphasized = true
                )
                MetricTile(
                    label = stringResource(R.string.focus_lens_volume),
                    value = formatTodayHeroVolume(metrics.totalVolume, locale),
                    modifier = Modifier.weight(1f),
                    emphasized = true
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ActivityHeatmapCard(
    heatmap: ActivityHeatmapUiModel,
    modifier: Modifier = Modifier,
    isCurrentMonth: Boolean = true,
    onPreviousMonth: () -> Unit = {},
    onCurrentMonth: () -> Unit = {},
    onNextMonth: () -> Unit = {}
) {
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Title and pill share a row when they fit and the pill wraps under the title
            // otherwise; the month navigator always sits on its own line so its width never
            // moves the pill.
            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = stringResource(R.string.activity_heatmap_title),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier
                        .align(Alignment.CenterVertically)
                        .semantics { heading() }
                )
                InfoPill(
                    text = pluralStringResource(
                        R.plurals.activity_heatmap_active_days,
                        heatmap.activeDays,
                        heatmap.activeDays
                    ),
                    leadingIcon = Icons.Default.EventAvailable
                )
            }

            GymMonthNavigator(
                monthLabel = heatmap.monthLabel,
                isCurrentMonth = isCurrentMonth,
                onPrevious = onPreviousMonth,
                onCurrent = onCurrentMonth,
                onNext = onNextMonth
            )

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

                    GymProgressBar(
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

/** Gallery columns: 3 normally, 2 at large font scales (mirrors iOS accessibility sizes). */
internal fun achievementGridColumns(fontScale: Float): Int = if (fontScale >= 1.4f) 2 else 3

/** "x / t" progress with the current value clamped to the goal and compact large numbers. */
internal fun achievementProgressText(progress: Int, goal: Int, locale: Locale): String =
    "${formatTodayHeroCount(progress.coerceAtMost(goal), locale)} / " +
        formatTodayHeroCount(goal, locale)

/** True when a badge category label adds information beyond the achievement name. */
internal fun achievementShowsCategory(name: String, category: String): Boolean =
    category.isNotBlank() && !category.equals(name, ignoreCase = true)

@Composable
private fun achievementAccent(rarity: BadgeRarity): Color = when (rarity) {
    BadgeRarity.COMMON -> MaterialTheme.colorScheme.secondary
    BadgeRarity.UNCOMMON -> MaterialTheme.colorScheme.primary
    BadgeRarity.RARE -> MaterialTheme.colorScheme.tertiary
    BadgeRarity.EPIC -> Color(0xFF8057C7)
    BadgeRarity.LEGENDARY -> Color(0xFFD28A16)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AchievementPreviewCard(
    achievements: List<AchievementPreviewUiModel>,
    modifier: Modifier = Modifier
) {
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    val selected = achievements.firstOrNull { it.id == selectedId }
    val columns = achievementGridColumns(LocalDensity.current.fontScale)
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val unlockedCount = achievements.count { it.isUnlocked }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                text = stringResource(R.string.achievements_title),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary
            )
            Text(
                text = stringResource(R.string.achievements_gallery_title),
                modifier = Modifier.semantics { heading() },
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = stringResource(R.string.achievements_gallery_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            InfoPill(
                text = "$unlockedCount / ${achievements.size}",
                leadingIcon = Icons.Default.Verified
            )
            Text(
                text = stringResource(R.string.achievements_unlocked_caption),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            achievements.chunked(columns).forEach { rowItems ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    rowItems.forEach { achievement ->
                        AchievementBadgeTile(
                            achievement = achievement,
                            locale = locale,
                            onClick = { selectedId = achievement.id },
                            modifier = Modifier.weight(1f)
                        )
                    }
                    repeat(columns - rowItems.size) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }

    if (selected != null) {
        ModalBottomSheet(onDismissRequest = { selectedId = null }) {
            AchievementDetailsContent(achievement = selected, locale = locale)
        }
    }
}

@Composable
private fun AchievementBadgeTile(
    achievement: AchievementPreviewUiModel,
    locale: Locale,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val accent = achievementAccent(achievement.badgeRarity)
    val unlocked = achievement.isUnlocked
    val ringColor = if (unlocked) accent else MaterialTheme.colorScheme.primary
    val fraction = achievement.progressFraction
        .takeIf(Float::isFinite)
        ?.coerceIn(0f, 1f)
        ?: 0f
    val description = stringResource(
        R.string.achievement_tile_a11y,
        achievement.title,
        stringResource(
            if (unlocked) R.string.achievement_status_unlocked else R.string.achievement_status_locked
        ),
        achievementProgressText(achievement.progress, achievement.goal, locale)
    )
    Column(
        modifier = modifier
            .heightIn(min = 108.dp)
            .clip(MaterialTheme.shapes.medium)
            .clickable(role = Role.Button, onClick = onClick)
            .clearAndSetSemantics {
                contentDescription = description
                role = Role.Button
                onClick {
                    onClick()
                    true
                }
            }
            .padding(horizontal = 6.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(modifier = Modifier.size(60.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
                progress = { fraction },
                modifier = Modifier.fillMaxSize(),
                color = ringColor,
                trackColor = MaterialTheme.colorScheme.outlineVariant,
                strokeWidth = 4.dp,
                strokeCap = StrokeCap.Round
            )
            Icon(
                imageVector = achievementBadgeIcon(achievement.id),
                contentDescription = null,
                modifier = Modifier.size(22.dp),
                tint = if (unlocked) {
                    accent
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                }
            )
            if (!unlocked) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .offset(x = (-3).dp, y = (-3).dp)
                        .size(18.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.surface)
                        .border(1.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.Lock,
                        contentDescription = null,
                        modifier = Modifier.size(10.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
        Text(
            text = achievement.title,
            modifier = Modifier.alpha(if (unlocked) 1f else 0.55f),
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun AchievementDetailsContent(
    achievement: AchievementPreviewUiModel,
    locale: Locale
) {
    val accent = achievementAccent(achievement.badgeRarity)
    val unlocked = achievement.isUnlocked
    val tone = if (unlocked) accent else MaterialTheme.colorScheme.onSurfaceVariant
    val fraction = achievement.progressFraction
        .takeIf(Float::isFinite)
        ?.coerceIn(0f, 1f)
        ?: 0f
    val unlockedDay = achievement.unlockedAtEpochDay

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(start = 20.dp, end = 20.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(84.dp)
                    .clip(CircleShape)
                    .background(tone.copy(alpha = 0.12f))
                    .clearAndSetSemantics { },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = achievementBadgeIcon(achievement.id),
                    contentDescription = null,
                    modifier = Modifier.size(34.dp),
                    tint = tone
                )
            }
            Text(
                text = achievement.title,
                modifier = Modifier.semantics { heading() },
                style = MaterialTheme.typography.titleLarge,
                textAlign = TextAlign.Center
            )
            if (achievementShowsCategory(achievement.title, achievement.badgeName)) {
                Text(
                    text = achievement.badgeName,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            InfoPill(
                text = achievementRarityLabel(achievement.badgeRarity),
                accent = accent
            )
        }

        Text(
            text = achievement.description,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            GymProgressBar(
                progress = { fraction },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(6.dp)
                    .clip(MaterialTheme.shapes.small),
                color = if (unlocked) accent else MaterialTheme.colorScheme.primary,
                trackColor = MaterialTheme.colorScheme.surfaceVariant
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = achievementProgressText(achievement.progress, achievement.goal, locale),
                    style = MaterialTheme.typography.labelMedium,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "+${achievement.rewardXp} XP",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = if (unlocked) accent else MaterialTheme.colorScheme.primary
                )
            }
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (unlockedDay != null) {
                Icon(
                    imageVector = Icons.Default.EventAvailable,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = accent
                )
                Text(
                    text = stringResource(
                        R.string.achievement_status_unlocked_on,
                        DateTimeUtils.formatEpochDayShort(unlockedDay, locale)
                    ),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = accent
                )
            } else {
                Icon(
                    imageVector = Icons.Default.Lock,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = stringResource(R.string.achievement_status_locked),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

private fun achievementBadgeIcon(id: String): ImageVector = when {
    id.startsWith("streak_") -> Icons.Default.LocalFireDepartment
    id.startsWith("volume_") -> Icons.AutoMirrored.Filled.TrendingUp
    id == "comeback" -> Icons.Default.Replay
    id == "first_workout" -> Icons.Default.FitnessCenter
    else -> Icons.Default.EmojiEvents
}

@Composable
private fun achievementRarityLabel(rarity: BadgeRarity): String = stringResource(
    when (rarity) {
        BadgeRarity.COMMON -> R.string.achievement_rarity_common
        BadgeRarity.UNCOMMON -> R.string.achievement_rarity_uncommon
        BadgeRarity.RARE -> R.string.achievement_rarity_rare
        BadgeRarity.EPIC -> R.string.achievement_rarity_epic
        BadgeRarity.LEGENDARY -> R.string.achievement_rarity_legendary
    }
)

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
