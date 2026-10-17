package com.example.gymapp.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Verified
import com.example.gymapp.ui.theme.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
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
import com.example.gymapp.ui.components.HeroTone
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.achievementGridColumns
import com.example.gymapp.ui.components.achievementRarityLabel
import com.example.gymapp.ui.components.tabularDigits
import com.example.gymapp.ui.theme.GymCapsuleShape
import com.example.gymapp.ui.components.brandFillColor
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.util.localizedMuscleName
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
                    TrainingMetricsCard(uiState = uiState)
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

/** "Sat, Sep 26 · 4 h 31 min": short date, then the duration when it is known. */
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

/** Exercise count and the most loaded muscle of the finished workout, like the iPhone summary. */
@Composable
private fun TrainingMetricsCard(uiState: PostWorkoutSummaryUiState) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val languageTag = currentAppLanguageTag()
    val topMuscle = uiState.topMuscleId?.let { localizedMuscleName(it, languageTag) } ?: "—"

    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SectionHeading(text = stringResource(R.string.post_workout_metrics_title))
                if (!uiState.note.isNullOrBlank()) {
                    Text(
                        text = uiState.note,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.post_workout_metric_exercises),
                    value = NumberFormat.getIntegerInstance(locale).format(uiState.exerciseCount),
                    modifier = Modifier.weight(1f)
                )
                MetricTile(
                    label = stringResource(R.string.post_workout_metric_top_muscle),
                    value = topMuscle,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

/** Layout constants of [WorkoutFeedbackCard]; the stacking decision and the real layout share them. */
internal object FeedbackChipsLayout {
    const val CardPaddingDp = 14f
    const val ChipGapDp = 8f
    const val ChipLabelPaddingDp = 8f
    const val ChipBorderDp = 1f
    const val ChipCount = 3

    /** Width available to the label text of one chip when the chips share a row. */
    fun labelWidthDp(cardWidthDp: Float): Float {
        val row = cardWidthDp - 2 * CardPaddingDp
        val chip = (row - (ChipCount - 1) * ChipGapDp) / ChipCount
        return chip - 2 * ChipLabelPaddingDp - 2 * ChipBorderDp
    }

    /** Narrowest width in which a label (its words with their widths) fits in at most two lines. */
    fun minTwoLineWidthDp(wordWidthsDp: List<Float>, spaceDp: Float): Float {
        if (wordWidthsDp.size <= 1) return wordWidthsDp.firstOrNull() ?: 0f
        fun line(words: List<Float>) = words.sum() + spaceDp * (words.size - 1)
        return (1 until wordWidthsDp.size).minOf { split ->
            maxOf(line(wordWidthsDp.subList(0, split)), line(wordWidthsDp.subList(split, wordWidthsDp.size)))
        }
    }

    /**
     * The chips stay in one row while every label fits its chip in at most two lines (wrapping by
     * words, like the web app): a label is never shrunk, cut off or broken mid-word. Otherwise they stack.
     */
    fun stacks(cardWidthDp: Float, labelWordWidthsDp: List<List<Float>>, spaceDp: Float): Boolean {
        val available = labelWidthDp(cardWidthDp)
        return labelWordWidthsDp.any { minTwoLineWidthDp(it, spaceDp) > available }
    }
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
    val density = LocalDensity.current
    val measurer = androidx.compose.ui.text.rememberTextMeasurer()
    val labelStyle = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold)

    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = selected != null) {
        androidx.compose.foundation.layout.BoxWithConstraints {
            val cardWidthDp = with(density) { constraints.maxWidth.toDp().value }
            val stacked = remember(options, labelStyle, cardWidthDp, density.density, density.fontScale) {
                fun widthDp(text: String) = with(density) {
                    measurer.measure(text, labelStyle, maxLines = 1, softWrap = false).size.width.toDp().value
                }
                val words = options.map { (_, label) ->
                    label.split(' ', '\u00A0').filter { it.isNotEmpty() }.map(::widthDp)
                }
                FeedbackChipsLayout.stacks(cardWidthDp, words, spaceDp = widthDp(" "))
            }
            Column(
                modifier = Modifier.padding(FeedbackChipsLayout.CardPaddingDp.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                SectionHeading(text = stringResource(R.string.workout_feedback_title))
                if (stacked) {
                    Column(verticalArrangement = Arrangement.spacedBy(FeedbackChipsLayout.ChipGapDp.dp)) {
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
                    // Equal-width chips of equal height: a label that needs two lines makes the whole row taller.
                    Row(
                        modifier = Modifier.height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(FeedbackChipsLayout.ChipGapDp.dp)
                    ) {
                        options.forEach { (feedback, label) ->
                            FeedbackChip(
                                label = label,
                                selected = selected == feedback,
                                onClick = { onSelected(feedback) },
                                modifier = Modifier.weight(1f).fillMaxHeight()
                            )
                        }
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
        shape = GymCapsuleShape,
        // Selected = accent fill with white text on every screen (the pale dark-theme primary is too weak).
        color = if (selected) brandFillColor() else MaterialTheme.colorScheme.surfaceVariant,
        contentColor = if (selected) Color.White else MaterialTheme.colorScheme.onSurface,
        border = BorderStroke(
            FeedbackChipsLayout.ChipBorderDp.dp,
            if (selected) brandFillColor() else MaterialTheme.colorScheme.outlineVariant
        )
    ) {
        Box(
            modifier = Modifier.padding(horizontal = FeedbackChipsLayout.ChipLabelPaddingDp.dp, vertical = 10.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                maxLines = 2
            )
        }
    }
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
                        color = HeroTone.supporting
                    )
                }
            }

            // Sets, volume and duration of the workout that was just finished. At large font scales the
            // three stats stack on their own lines so values and labels are never ellipsized.
            val stackStats = LocalDensity.current.fontScale >= 1.3f
            val statsContent: @Composable (Modifier) -> Unit = { statModifier ->
                HeroStat(
                    value = NumberFormat.getIntegerInstance(locale).format(uiState.setCount),
                    label = stringResource(R.string.post_workout_metric_sets),
                    color = onHero,
                    modifier = statModifier
                )
                HeroStat(
                    value = stringResource(
                        R.string.today_history_volume_kg,
                        NumberFormat.getIntegerInstance(locale).format(uiState.volume)
                    ),
                    label = stringResource(R.string.post_workout_metric_volume),
                    color = onHero,
                    modifier = statModifier
                )
                HeroStat(
                    value = uiState.durationSeconds
                        ?.takeIf { it > 0L }
                        ?.let { DateTimeUtils.formatCompactDuration(it, locale) }
                        ?: "--",
                    label = stringResource(R.string.post_workout_metric_duration),
                    color = onHero,
                    modifier = statModifier
                )
            }
            if (stackStats) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    statsContent(Modifier.fillMaxWidth())
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    statsContent(Modifier.weight(1f))
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = stringResource(R.string.post_workout_xp_gain, uiState.xpGained),
                    style = MaterialTheme.typography.headlineLarge.tabularDigits(),
                    fontSize = 34.sp,
                    fontFamily = FontFamily.SansSerif,
                    fontWeight = FontWeight.SemiBold,
                    color = HeroTone.accentText
                )
                Text(
                    text = stringResource(R.string.post_workout_session_xp),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = HeroTone.supporting
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
                    color = HeroTone.accent,
                    trackColor = HeroTone.track
                )
                Text(
                    text = stringResource(
                        R.string.post_workout_xp_to_level,
                        uiState.xpToNextLevel,
                        uiState.currentLevel + 1
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = HeroTone.supporting
                )
            }

            if (uiState.leveledUp) {
                InfoPill(
                    text = stringResource(
                        R.string.post_workout_level_up,
                        uiState.previousLevel,
                        uiState.currentLevel
                    ),
                    onHero = true
                )
            }
        }
    }
}

@Composable
private fun HeroStat(
    value: String,
    label: String,
    color: Color,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.semantics(mergeDescendants = true) { },
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleMedium.tabularDigits(),
            fontWeight = FontWeight.SemiBold,
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = HeroTone.supporting,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
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
