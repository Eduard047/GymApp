package com.example.gymapp.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gymapp.R
import com.example.gymapp.data.repository.WorkoutFeedback
import com.example.gymapp.ui.components.AchievementRingTile
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.GymProgressBar
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.achievementGridColumns
import com.example.gymapp.ui.components.achievementRarityLabel
import com.example.gymapp.ui.components.tabularDigits
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.viewmodel.CompletedMissionUiState
import com.example.gymapp.ui.viewmodel.NewBadgeUiState
import com.example.gymapp.ui.viewmodel.PostWorkoutPrUiState
import com.example.gymapp.ui.viewmodel.PostWorkoutSummaryUiState
import com.example.gymapp.util.DateTimeUtils
import java.text.NumberFormat
import java.util.Locale

@Composable
fun PostWorkoutSummaryScreen(
    uiState: PostWorkoutSummaryUiState,
    exerciseMediaOwnerKey: String,
    onViewWorkout: () -> Unit,
    onDone: () -> Unit,
    onFeedbackSelected: (WorkoutFeedback) -> Unit,
    modifier: Modifier = Modifier
) {
    when {
        uiState.isLoading -> {
            Column(
                modifier = modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator()
            }
        }

        !uiState.isSessionFound -> {
            Column(
                modifier = modifier
                    .fillMaxSize()
                    .padding(12.dp),
                verticalArrangement = Arrangement.Center
            ) {
                EmptyStatePanel(
                    title = stringResource(R.string.post_workout_unavailable_title),
                    supporting = stringResource(R.string.post_workout_unavailable_supporting)
                )
            }
        }

        else -> {
            LazyColumn(
                modifier = modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 14.dp, top = 12.dp, end = 14.dp, bottom = 30.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                item {
                    HeroCard(uiState = uiState)
                }

                item {
                    WorkoutFeedbackCard(
                        selected = uiState.feedback,
                        onSelected = onFeedbackSelected
                    )
                }

                if (uiState.personalRecords.isNotEmpty()) {
                    item {
                        PersonalRecordsCard(
                            records = uiState.personalRecords,
                            exerciseMediaOwnerKey = exerciseMediaOwnerKey
                        )
                    }
                }

                if (uiState.completedMissions.isNotEmpty()) {
                    item {
                        CompletedMissionsCard(missions = uiState.completedMissions)
                    }
                }

                if (uiState.newBadges.isNotEmpty()) {
                    item {
                        NewBadgesCard(badges = uiState.newBadges)
                    }
                }

                item {
                    Column(
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Button(
                            onClick = onDone,
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = 48.dp)
                        ) {
                            Text(text = stringResource(R.string.post_workout_done), maxLines = 1)
                        }
                        TextButton(
                            onClick = onViewWorkout,
                            modifier = Modifier
                                .align(Alignment.CenterHorizontally)
                                .heightIn(min = 48.dp)
                        ) {
                            Text(
                                text = stringResource(R.string.post_workout_details),
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

/** "Sat, Sep 26 · 4h 31m": short date, then the duration when it is known. */
internal fun postWorkoutSubtitle(
    sessionDate: Long,
    durationSeconds: Long?,
    locale: Locale
): String {
    val datePart = DateTimeUtils.formatShortDate(sessionDate, locale)
    val durationText = durationSeconds
        ?.takeIf { it > 0L }
        ?.let { DateTimeUtils.formatCompactDuration(it, locale) }
        .orEmpty()
    return if (durationText.isEmpty()) datePart else "$datePart · $durationText"
}

/** Record weights and estimates: at most one decimal, none for whole numbers ("60", "72,5"). */
internal fun formatPostWorkoutRecordValue(value: Double, locale: Locale): String =
    NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = 0
        maximumFractionDigits = 1
    }.format(value)

@Composable
private fun SectionHeading(text: String) {
    Text(
        text = text,
        modifier = Modifier.semantics { heading() },
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold
    )
}

@Composable
private fun WorkoutFeedbackCard(
    selected: WorkoutFeedback?,
    onSelected: (WorkoutFeedback) -> Unit
) {
    val options = listOf(
        WorkoutFeedback.Easy to stringResource(R.string.workout_feedback_easy),
        WorkoutFeedback.Normal to stringResource(R.string.workout_feedback_normal),
        WorkoutFeedback.Hard to stringResource(R.string.workout_feedback_hard)
    )
    val stacked = LocalDensity.current.fontScale >= 1.5f

    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = selected != null) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionHeading(text = stringResource(R.string.workout_feedback_title))
            if (stacked) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    options.forEach { (feedback, label) ->
                        FeedbackChip(
                            label = label,
                            selected = selected == feedback,
                            onClick = { onSelected(feedback) },
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    options.forEach { (feedback, label) ->
                        FeedbackChip(
                            label = label,
                            selected = selected == feedback,
                            onClick = { onSelected(feedback) },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun FeedbackChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .heightIn(min = 44.dp)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick),
        shape = GymControlShape,
        color = if (selected) {
            MaterialTheme.colorScheme.primary
        } else {
            MaterialTheme.colorScheme.surfaceVariant
        },
        contentColor = if (selected) {
            MaterialTheme.colorScheme.onPrimary
        } else {
            MaterialTheme.colorScheme.onSurface
        },
        border = BorderStroke(
            1.dp,
            if (selected) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.outlineVariant
            }
        )
    ) {
        ShrinkToFitLabel(
            text = label,
            modifier = Modifier
                .padding(horizontal = 8.dp, vertical = 10.dp)
                .fillMaxWidth()
        )
    }
}

/** One-line label that scales down (to 80%) before it would be cut off, like iOS `minimumScaleFactor(0.8)`. */
@Composable
private fun ShrinkToFitLabel(text: String, modifier: Modifier = Modifier) {
    val base = MaterialTheme.typography.titleSmall
    var scale by remember(text) { mutableFloatStateOf(1f) }
    Text(
        text = text,
        modifier = modifier,
        style = base.copy(
            fontSize = base.fontSize * scale,
            lineHeight = base.lineHeight * scale
        ),
        fontWeight = FontWeight.SemiBold,
        maxLines = 1,
        softWrap = false,
        overflow = TextOverflow.Ellipsis,
        textAlign = TextAlign.Center,
        onTextLayout = { layout ->
            if (layout.hasVisualOverflow && scale > 0.8f) {
                scale = (scale - 0.05f).coerceAtLeast(0.8f)
            }
        }
    )
}

@Composable
private fun HeroCard(uiState: PostWorkoutSummaryUiState) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val subtitle = postWorkoutSubtitle(uiState.sessionDate, uiState.durationSeconds, locale)

    HeroPanel(modifier = Modifier.fillMaxWidth()) {
        // Read inside the panel: only here LocalContentColor is the hero's own content color.
        val onHero = LocalContentColor.current
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top
            ) {
                Icon(
                    imageVector = Icons.Default.Verified,
                    contentDescription = null,
                    tint = onHero,
                    modifier = Modifier.size(32.dp)
                )
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = stringResource(R.string.post_workout_complete_title),
                        modifier = Modifier.semantics { heading() },
                        style = MaterialTheme.typography.titleLarge,
                        color = onHero,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = onHero.copy(alpha = 0.82f)
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = stringResource(R.string.post_workout_xp_gain, uiState.xpGained),
                    style = MaterialTheme.typography.headlineLarge.tabularDigits(),
                    fontSize = 34.sp,
                    fontFamily = FontFamily.SansSerif,
                    fontWeight = FontWeight.SemiBold,
                    color = onHero
                )
                Text(
                    text = stringResource(R.string.post_workout_session_xp),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = onHero.copy(alpha = 0.72f)
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = stringResource(
                        R.string.post_workout_level_rank,
                        uiState.currentLevel,
                        uiState.levelTitle
                    ),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = onHero
                )
                GymProgressBar(
                    progress = { uiState.levelProgress },
                    modifier = Modifier
                        .fillMaxWidth()
                        .clearAndSetSemantics { },
                    color = onHero,
                    trackColor = onHero.copy(alpha = 0.24f)
                )
                Text(
                    text = stringResource(
                        R.string.post_workout_xp_to_level,
                        uiState.xpToNextLevel,
                        uiState.currentLevel + 1
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = onHero.copy(alpha = 0.72f)
                )
            }

            if (uiState.leveledUp) {
                InfoPill(
                    text = stringResource(
                        R.string.post_workout_level_up,
                        uiState.previousLevel,
                        uiState.currentLevel
                    ),
                    accent = onHero
                )
            }
        }
    }
}

@Composable
private fun PersonalRecordsCard(
    records: List<PostWorkoutPrUiState>,
    exerciseMediaOwnerKey: String
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()

    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionHeading(text = stringResource(R.string.post_workout_records_title))
            records.forEach { record ->
                val detail = listOfNotNull(
                    record.weight?.let {
                        stringResource(
                            R.string.post_workout_record_weight,
                            formatPostWorkoutRecordValue(it, locale)
                        )
                    },
                    record.estimatedOneRepMax?.let {
                        stringResource(
                            R.string.post_workout_record_one_rep_max,
                            formatPostWorkoutRecordValue(it, locale)
                        )
                    }
                ).joinToString(" · ")
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics(mergeDescendants = true) { },
                    horizontalArrangement = Arrangement.spacedBy(11.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ExerciseMediaPreview(
                        exerciseId = record.exerciseId,
                        exerciseName = record.exerciseName,
                        ownerKey = exerciseMediaOwnerKey,
                        width = 40.dp,
                        height = 40.dp,
                        editable = false,
                        playBadgeSize = 18.dp
                    )
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Text(
                            text = localizedExerciseName(record.exerciseName),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = detail,
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

@Composable
private fun NewBadgesCard(badges: List<NewBadgeUiState>) {
    val columns = achievementGridColumns(LocalDensity.current.fontScale)

    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionHeading(text = stringResource(R.string.post_workout_badges_title))
            badges.chunked(columns).forEach { rowItems ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    rowItems.forEach { badge ->
                        AchievementRingTile(
                            achievementId = badge.id,
                            title = badge.name,
                            rarity = badge.rarity,
                            unlocked = true,
                            progressFraction = 1f,
                            description = stringResource(
                                R.string.post_workout_badge_a11y,
                                badge.name,
                                achievementRarityLabel(badge.rarity)
                            ),
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
}

@Composable
private fun CompletedMissionsCard(missions: List<CompletedMissionUiState>) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionHeading(text = stringResource(R.string.post_workout_missions_title))
            missions.forEach { mission ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics(mergeDescendants = true) { },
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.CheckCircle,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp)
                    )
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Text(
                            text = mission.title,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = mission.description,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    InfoPill(text = mission.cadence)
                }
            }
        }
    }
}
