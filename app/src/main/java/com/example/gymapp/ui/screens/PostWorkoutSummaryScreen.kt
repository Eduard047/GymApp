package com.example.gymapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gymapp.R
import com.example.gymapp.data.repository.WorkoutFeedback
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.GroupedListDefaults
import com.example.gymapp.ui.components.GroupedSection
import com.example.gymapp.ui.components.GymProgressBar
import com.example.gymapp.ui.components.GymSegmentItem
import com.example.gymapp.ui.components.GymSegmentedControl
import com.example.gymapp.ui.components.achievementRarityLabel
import com.example.gymapp.ui.components.tabularDigits
import com.example.gymapp.ui.theme.Button
import com.example.gymapp.ui.theme.GymCapsuleShape
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.util.localizedMuscleName
import com.example.gymapp.ui.viewmodel.BiggestWorkoutBadge
import com.example.gymapp.ui.viewmodel.ExerciseSummaryUiState
import com.example.gymapp.ui.viewmodel.ExerciseVsLastUiState
import com.example.gymapp.ui.viewmodel.PostWorkoutPrUiState
import com.example.gymapp.ui.viewmodel.PostWorkoutSummaryUiState
import com.example.gymapp.ui.viewmodel.TrainedMuscleLoad
import com.example.gymapp.ui.viewmodel.VsLastBasis
import com.example.gymapp.ui.viewmodel.VsLastSet
import com.example.gymapp.ui.viewmodel.VsLastStatus
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.formatVolumeTotal
import com.example.gymapp.util.formatWeightDisplay
import com.example.gymapp.util.formattedPluralStringResource
import com.example.gymapp.util.formattedStringResource
import com.example.gymapp.util.keepNumberWithUnit
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.roundToInt

/** Space under the list so the last row clears the pinned "Done" bar (16 + 52 + 16 plus a little air). */
private val DoneBarClearance = 104.dp
private val SectionGap = 28.dp
private val ScreenMargin = 16.dp

/**
 * Post-workout summary: the workout result (volume, sets, duration) is the one focal point, "Done" is
 * pinned to the bottom, and everything else is an inset-grouped section. XP, missions and badges are
 * footnote-weight, never hero material.
 */
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
            Box(modifier = modifier.fillMaxSize()) {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(
                        start = ScreenMargin,
                        top = 8.dp,
                        end = ScreenMargin,
                        bottom = DoneBarClearance
                    ),
                    verticalArrangement = Arrangement.spacedBy(SectionGap)
                ) {
                    item { WorkoutResultHero(uiState = uiState) }

                    item {
                        WorkoutFeedbackSection(
                            selected = uiState.feedback,
                            onSelected = onFeedbackSelected
                        )
                    }

                    if (uiState.exerciseSummaries.isNotEmpty()) {
                        item {
                            ExerciseSummarySection(
                                summaries = uiState.exerciseSummaries,
                                comparisons = uiState.exerciseComparisons
                            )
                        }
                    }

                    if (uiState.trainedMuscles.isNotEmpty()) {
                        item { TrainedMusclesSection(muscles = uiState.trainedMuscles) }
                    }

                    if (uiState.personalRecords.isNotEmpty()) {
                        item {
                            PersonalRecordsSection(
                                records = uiState.personalRecords,
                                exerciseMediaOwnerKey = exerciseMediaOwnerKey
                            )
                        }
                    }

                    if (uiState.completedMissions.isNotEmpty()) {
                        item {
                            GroupedSection(header = stringResource(R.string.post_workout_missions_title)) {
                                uiState.completedMissions.forEach { mission ->
                                    row(title = mission.title, value = mission.cadence)
                                }
                            }
                        }
                    }

                    if (uiState.newBadges.isNotEmpty()) {
                        item {
                            val badgeRows = uiState.newBadges.map { badge ->
                                badge.name to achievementRarityLabel(badge.rarity)
                            }
                            GroupedSection(header = stringResource(R.string.post_workout_badges_title)) {
                                badgeRows.forEach { (name, rarity) -> row(title = name, value = rarity) }
                            }
                        }
                    }

                    item {
                        val detailsTitle = stringResource(R.string.post_workout_details)
                        GroupedSection {
                            row(
                                title = detailsTitle,
                                chevron = true,
                                onClick = onViewWorkout
                            )
                        }
                    }

                    item { ProgressFootnote(uiState = uiState) }
                }

                DoneBar(
                    onDone = onDone,
                    modifier = Modifier.align(Alignment.BottomCenter)
                )
            }
        }
    }
}

/** "Done" stays reachable at any scroll position: a pinned capsule on the screen ground. */
@Composable
private fun DoneBar(onDone: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background)
            .navigationBarsPadding()
            .padding(horizontal = ScreenMargin, vertical = 12.dp)
    ) {
        Button(
            onClick = onDone,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 52.dp),
            shape = GymCapsuleShape,
            elevation = null
        ) {
            Text(
                text = stringResource(R.string.post_workout_done),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1
            )
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


/** One footnote line: "+120 XP · Level 3" (or the level-up pair). XP is a footnote, not a hero. */
@Composable
private fun ProgressFootnote(uiState: PostWorkoutSummaryUiState) {
    val levelText = if (uiState.leveledUp) {
        formattedStringResource(R.string.post_workout_level_up, uiState.previousLevel, uiState.currentLevel)
    } else {
        formattedStringResource(R.string.post_workout_level, uiState.currentLevel)
    }
    Text(
        text = formattedStringResource(R.string.post_workout_xp_gain, uiState.xpGained) + " · " + levelText,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = GroupedListDefaults.TextInset),
        style = MaterialTheme.typography.bodySmall.tabularDigits(),
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

/** Result first: title and date, then volume, sets and duration as three numerals on the screen ground. */
@Composable
private fun WorkoutResultHero(uiState: PostWorkoutSummaryUiState) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    // The duration is a hero numeral, so the date line carries the date only.
    val dateLine = postWorkoutSubtitle(uiState.sessionDate, null, locale)
    val integerFormat = NumberFormat.getIntegerInstance(locale)
    val stats = listOf(
        formattedStringResource(R.string.today_history_volume_kg, integerFormat.format(uiState.volume)) to
            stringResource(R.string.post_workout_metric_volume),
        integerFormat.format(uiState.setCount) to stringResource(R.string.post_workout_metric_sets),
        (
            uiState.durationSeconds
                ?.takeIf { it > 0L }
                ?.let { DateTimeUtils.formatCompactDuration(it, locale) }
                ?: "—"
            ) to stringResource(R.string.post_workout_metric_duration)
    )
    // At large font scales the three stats stack so values and labels are never ellipsized.
    val stackStats = LocalDensity.current.fontScale >= 1.3f

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = GroupedListDefaults.TextInset, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = stringResource(R.string.post_workout_complete_title),
                modifier = Modifier.semantics { heading() },
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = dateLine,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (stackStats) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                stats.forEach { (value, label) -> HeroStat(value, label, Modifier.fillMaxWidth()) }
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                stats.forEach { (value, label) -> HeroStat(value, label, Modifier.weight(1f)) }
            }
        }
        uiState.biggestWorkout?.let { badge ->
            Text(
                text = stringResource(
                    when (badge) {
                        BiggestWorkoutBadge.Ever -> R.string.biggest_workout_ever
                        BiggestWorkoutBadge.Month -> R.string.biggest_workout_month
                    }
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun HeroStat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.semantics(mergeDescendants = true) { },
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.headlineMedium.tabularDigits(),
            fontSize = 30.sp,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/** Effort feedback as a native segmented control; the stored values are unchanged. */
@Composable
private fun WorkoutFeedbackSection(
    selected: WorkoutFeedback?,
    onSelected: (WorkoutFeedback) -> Unit
) {
    val items = listOf(
        GymSegmentItem<WorkoutFeedback?>(WorkoutFeedback.Easy, stringResource(R.string.workout_feedback_easy)),
        GymSegmentItem<WorkoutFeedback?>(WorkoutFeedback.Normal, stringResource(R.string.workout_feedback_normal)),
        GymSegmentItem<WorkoutFeedback?>(WorkoutFeedback.Hard, stringResource(R.string.workout_feedback_hard))
    )
    GroupedSection(header = stringResource(R.string.workout_feedback_title)) {
        row {
            Box(modifier = Modifier.padding(GroupedListDefaults.RowPaddingVertical)) {
                GymSegmentedControl<WorkoutFeedback?>(
                    items = items,
                    selected = selected,
                    onSelected = { value -> value?.let(onSelected) }
                )
            }
        }
    }
}

/** Free-form row with the metrics of [GroupedRow]: min 52dp, 16 x 12 padding. */
@Composable
private fun GroupedRowFrame(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = GroupedListDefaults.RowMinHeight)
            .padding(
                horizontal = GroupedListDefaults.TextInset,
                vertical = GroupedListDefaults.RowPaddingVertical
            ),
        contentAlignment = Alignment.CenterStart
    ) {
        content()
    }
}

/** Exercise name, "3 sets · 60 × 8" and, when the workout is comparable with the last one, the change. */
@Composable
private fun ExerciseSummarySection(
    summaries: List<ExerciseSummaryUiState>,
    comparisons: List<ExerciseVsLastUiState>
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val comparisonById = comparisons.associateBy { it.exerciseId }

    GroupedSection(header = stringResource(R.string.post_workout_exercises_title)) {
        summaries.forEach { summary ->
            row {
                val comparison = comparisonById[summary.exerciseId]
                val setsText = formattedPluralStringResource(
                    R.plurals.saved_workout_set_count,
                    summary.setCount,
                    summary.setCount
                )
                val bestText = comparison?.let { vsLastBestText(it, locale) }
                    ?: vsLastSetText(summary.best, locale)
                val deltaText = comparison?.let { vsLastDeltaText(it, locale) }
                val deltaColor = if (comparison?.status == VsLastStatus.Up) {
                    MaterialTheme.colorScheme.secondary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
                GroupedRowFrame(modifier = Modifier.semantics(mergeDescendants = true) { }) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            Text(
                                text = localizedExerciseName(summary.exerciseName),
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurface,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = "$setsText · $bestText",
                                style = MaterialTheme.typography.bodySmall.tabularDigits(),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                        if (deltaText != null) {
                            Text(
                                text = deltaText,
                                style = MaterialTheme.typography.bodyLarge.tabularDigits(),
                                color = deltaColor,
                                maxLines = 1
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Muscles loaded in the finished workout with bars scaled to the most loaded one. */
@Composable
private fun TrainedMusclesSection(muscles: List<TrainedMuscleLoad>) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val languageTag = currentAppLanguageTag()
    val numberFormat = NumberFormat.getIntegerInstance(locale)
    val maxLoad = maxOf(1.0, muscles.first().load)

    GroupedSection(header = stringResource(R.string.post_workout_muscles_title)) {
        muscles.forEach { item ->
            row {
                val name = localizedMuscleName(item.muscleId, languageTag)
                val load = numberFormat.format(item.load)
                val percent = numberFormat.format((item.load / maxLoad * 100.0).roundToInt())
                val description = formattedStringResource(R.string.post_workout_muscle_a11y, name, load, percent)
                GroupedRowFrame(modifier = Modifier.clearAndSetSemantics { contentDescription = description }) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = name,
                                modifier = Modifier.weight(1f),
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            Text(
                                text = load,
                                style = MaterialTheme.typography.bodyLarge.tabularDigits(),
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        GymProgressBar(
                            progress = { (item.load / maxLoad).toFloat() },
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PersonalRecordsSection(
    records: List<PostWorkoutPrUiState>,
    exerciseMediaOwnerKey: String
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()

    GroupedSection(header = stringResource(R.string.post_workout_records_title)) {
        records.forEach { record ->
            row {
                val detail = listOfNotNull(
                    record.weight?.let {
                        formattedStringResource(
                            R.string.post_workout_record_weight,
                            formatPostWorkoutRecordValue(it, locale)
                        )
                    },
                    record.estimatedOneRepMax?.let {
                        formattedStringResource(
                            R.string.post_workout_record_one_rep_max,
                            formatPostWorkoutRecordValue(it, locale)
                        )
                    }
                ).joinToString(" · ")
                GroupedRowFrame(modifier = Modifier.semantics(mergeDescendants = true) { }) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
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
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurface,
                                maxLines = 2,
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
}

/** Layout constants of [MetricTile] rows; the side-by-side decision and the real layout share them. */
internal object MetricTilesLayout {
    const val TileGapDp = 10f
    const val TilePaddingDp = 12f
    const val TileCount = 2

    /** Width available to the text of one tile when the tiles share a row of [rowWidthDp]. */
    fun contentWidthDp(rowWidthDp: Float): Float {
        val tile = (rowWidthDp - (TileCount - 1) * TileGapDp) / TileCount
        return tile - 2 * TilePaddingDp
    }

    /** True while the widest text of every tile ([tileTextWidthsDp]) fits the tile without shrinking or cutting. */
    fun sideBySide(rowWidthDp: Float, tileTextWidthsDp: List<Float>): Boolean =
        tileTextWidthsDp.all { it <= contentWidthDp(rowWidthDp) }
}

/** "+20 kg" / "−3 reps" (true minus, NBSP before the unit); null for "new" and "same". */
@Composable
private fun vsLastDeltaText(row: ExerciseVsLastUiState, locale: Locale): String? {
    val delta = row.delta ?: return null
    if (row.status != VsLastStatus.Up && row.status != VsLastStatus.Down) return null
    val sign = if (delta > 0.0) "+" else "\u2212"
    val magnitude = kotlin.math.abs(delta)
    val text = when (row.basis) {
        VsLastBasis.Reps -> formattedStringResource(
            R.string.vs_last_reps,
            NumberFormat.getIntegerInstance(locale).format(magnitude.roundToInt())
        )
        else -> formattedStringResource(R.string.vs_last_volume_kg, formatVolumeTotal(magnitude, locale))
    }
    return sign + keepNumberWithUnit(text)
}

@Composable
private fun vsLastSetText(set: VsLastSet, locale: Locale): String =
    if (set.weight > 0.0) {
        formattedStringResource(R.string.vs_last_best_set, formatWeightDisplay(set.weight, locale), set.reps.toString())
    } else {
        keepNumberWithUnit(formattedStringResource(R.string.vs_last_reps, set.reps.toString()))
    }

/** Best set line: "60 × 8 → 62,5 × 8", or just the current best for a new exercise or an unchanged best set. */
@Composable
private fun vsLastBestText(row: ExerciseVsLastUiState, locale: Locale): String {
    val current = vsLastSetText(row.best, locale)
    val previous = row.previousBest?.takeIf { it != row.best } ?: return current
    return formattedStringResource(R.string.vs_last_best_set_change, vsLastSetText(previous, locale), current)
}
