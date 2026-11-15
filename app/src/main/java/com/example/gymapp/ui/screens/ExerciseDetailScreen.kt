package com.example.gymapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.catalog.ExerciseSearchVocabulary
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.GymOneRepMax
import com.example.gymapp.ui.components.AppleBackButton
import com.example.gymapp.ui.components.AppleNavigationBar
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.GroupedSection
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.util.localizedMuscleName
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.formatWeightDisplay
import com.example.gymapp.util.formattedStringResource
import com.example.gymapp.util.keepNumberWithUnit
import com.example.gymapp.util.keepShortWordsWithNext
import com.example.gymapp.util.safeGetString
import java.util.Locale

/** Sessions listed on the detail screen before «All history» takes over. */
private const val DETAIL_HISTORY_PREVIEW_SESSIONS = 5

/** Equipment shown in a list subtitle when a built-in exercise has several: the first of this order wins. */
private val EQUIPMENT_PRIORITY = listOf("barbell", "dumbbell", "cable", "machine", "plate", "band", "bodyweight")

/** Equipment id of a built-in exercise (see the search vocabulary), or null for a custom one. */
internal fun exerciseEquipmentId(exerciseName: String): String? {
    val key = BuiltInExerciseCatalog.definitionForName(exerciseName)?.key ?: return null
    val ids = ExerciseSearchVocabulary.equipmentIdsByKey[key].orEmpty()
    return EQUIPMENT_PRIORITY.firstOrNull { it in ids }
}

@Composable
internal fun exerciseEquipmentLabel(equipmentId: String?): String? {
    val res = when (equipmentId) {
        "barbell" -> R.string.exercise_equipment_barbell
        "dumbbell" -> R.string.exercise_equipment_dumbbell
        "cable" -> R.string.exercise_equipment_cable
        "machine" -> R.string.exercise_equipment_machine
        "plate" -> R.string.exercise_equipment_plate
        "band" -> R.string.exercise_equipment_band
        "bodyweight" -> R.string.exercise_equipment_bodyweight
        else -> return null
    }
    return stringResource(res)
}

/** «Chest · Dumbbells»: primary muscle, then equipment when known; null when neither is known. */
@Composable
internal fun exerciseSubtitle(exerciseName: String, muscleIds: Collection<String>?): String? {
    val languageTag = currentAppLanguageTag()
    val muscle = muscleIds?.firstOrNull()?.let { localizedMuscleName(it, languageTag) }
    val equipment = exerciseEquipmentLabel(exerciseEquipmentId(exerciseName))
    return listOfNotNull(muscle, equipment).takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

private data class DetailSession(val date: Long, val sets: List<ExerciseHistoryEntry>)

/** The set with the highest estimated one-rep max (heavier weight on a tie); most reps when every set is 0 kg. */
private fun bestSetOf(sets: List<ExerciseHistoryEntry>): ExerciseHistoryEntry? {
    val completed = sets.filter { it.reps > 0 && it.weight >= 0.0 }
    if (completed.isEmpty()) return null
    val weighted = completed.filter { it.weight > 0.0 }
    if (weighted.isEmpty()) return completed.maxByOrNull { it.reps }
    return weighted.maxWithOrNull(
        compareBy<ExerciseHistoryEntry> { GymOneRepMax.estimate(it.weight, it.reps) }.thenBy { it.weight }
    )
}

/**
 * Pushed exercise detail (opened by tapping a library row): video preview, name and muscles/equipment,
 * best result, recent history, muscles, then the actions that used to hide behind the row's overflow menu.
 */
@Composable
internal fun ExerciseDetailScreen(
    exercise: ExerciseEntity,
    history: List<ExerciseHistoryEntry>,
    muscleIds: List<String>,
    exerciseMediaOwnerKey: String,
    bottomContentInset: Dp,
    onBack: () -> Unit,
    onToggleFavorite: () -> Unit,
    onShowAllHistory: () -> Unit,
    onEditMuscles: () -> Unit,
    onEditWeightSteps: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier
) {
    val horizontalPadding = adaptiveScreenHorizontalPadding()
    val context = LocalContext.current
    val languageTag = currentAppLanguageTag()
    val locale = remember(languageTag) { Locale.forLanguageTag(languageTag) }
    val isBuiltIn = remember(exercise.name) { BuiltInExerciseCatalog.definitionForName(exercise.name) != null }
    val displayName = localizedExerciseName(exercise.name)
    val subtitle = exerciseSubtitle(exercise.name, muscleIds)
    val sessions = remember(history) {
        history.groupBy { it.sessionId }.values
            .map { sets -> DetailSession(sets.first().sessionDate, sets.sortedBy { it.setOrderIndex }) }
            .sortedByDescending { it.date }
    }
    val bestSet = remember(history) { bestSetOf(history) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            // Swallow touches so the list underneath never reacts through the pushed screen.
            .pointerInput(Unit) {}
    ) {
        AppleNavigationBar(
            title = stringResource(R.string.exercise_detail_title),
            leading = {
                AppleBackButton(onClick = onBack, contentDescription = stringResource(R.string.cd_back))
            }
        )
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = horizontalPadding,
                top = GymSpacing.Small,
                end = horizontalPadding,
                bottom = GymSpacing.ScreenBottom + bottomContentInset
            ),
            verticalArrangement = Arrangement.spacedBy(28.dp)
        ) {
            item(key = "header") {
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    BoxWithConstraints(Modifier.fillMaxWidth()) {
                        val previewWidth = if (maxWidth > 420.dp) 420.dp else maxWidth
                        ExerciseMediaPreview(
                            exerciseId = exercise.id,
                            exerciseName = exercise.name,
                            ownerKey = exerciseMediaOwnerKey,
                            width = previewWidth,
                            height = previewWidth * 0.56f,
                            playBadgeSize = 36.dp,
                            cornerRadius = 12.dp
                        )
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            text = keepShortWordsWithNext(displayName),
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onBackground,
                            modifier = Modifier.semantics { heading() }
                        )
                        if (subtitle != null) {
                            Text(
                                text = subtitle,
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }

            if (bestSet != null) {
                item(key = "best") {
                    val formatKg = { weight: Double ->
                        keepNumberWithUnit(
                            context.safeGetString(R.string.today_history_volume_kg, formatWeightDisplay(weight, locale))
                        )
                    }
                    val setValue = if (bestSet.weight > 0.0) {
                        keepNumberWithUnit("${formatKg(bestSet.weight)} × ${bestSet.reps}")
                    } else {
                        context.safeGetString(R.string.exercise_detail_best_reps, bestSet.reps)
                    }
                    val oneRepMax = if (bestSet.weight > 0.0) {
                        formatKg(GymOneRepMax.estimate(bestSet.weight, bestSet.reps))
                    } else {
                        null
                    }
                    val bestSetTitle = stringResource(R.string.exercise_detail_best_set)
                    val oneRepMaxTitle = stringResource(R.string.exercise_detail_one_rm)
                    val lastTitle = stringResource(R.string.exercise_detail_last_performed)
                    val timesTitle = stringResource(R.string.exercise_history_sessions)
                    val lastDate = DateTimeUtils.formatShortDate(sessions.first().date, locale)
                    GroupedSection(header = stringResource(R.string.exercise_detail_best_header)) {
                        row(bestSetTitle, value = setValue)
                        if (oneRepMax != null) row(oneRepMaxTitle, value = oneRepMax)
                        row(lastTitle, value = lastDate)
                        row(timesTitle, value = sessions.size.toString())
                    }
                }
            }

            item(key = "history") {
                val historyRows = sessions.take(DETAIL_HISTORY_PREVIEW_SESSIONS).map { session ->
                    val sessionBest = bestSetOf(session.sets)
                    Triple(
                        DateTimeUtils.formatShortDate(session.date, locale),
                        context.safeGetString(R.string.exercise_history_sets_inline, session.sets.size),
                        sessionBest?.let { set ->
                            keepNumberWithUnit(
                                context.safeGetString(
                                    R.string.today_history_volume_kg,
                                    formatWeightDisplay(set.weight, locale)
                                ) + " × ${set.reps}"
                            )
                        }
                    )
                }
                val emptyTitle = stringResource(R.string.exercise_history_empty)
                val allTitle = stringResource(R.string.exercise_detail_history_all)
                val secondary = MaterialTheme.colorScheme.onSurfaceVariant
                val accent = MaterialTheme.colorScheme.primary
                GroupedSection(header = stringResource(R.string.exercise_card_history)) {
                    if (sessions.isEmpty()) {
                        row(emptyTitle, titleColor = secondary)
                    } else {
                        historyRows.forEach { (date, sets, best) ->
                            row(date, subtitle = sets, value = best)
                        }
                        if (sessions.size > DETAIL_HISTORY_PREVIEW_SESSIONS) {
                            row(allTitle, titleColor = accent, chevron = true, onClick = onShowAllHistory)
                        }
                    }
                }
            }

            item(key = "muscles") {
                val names = muscleIds.map { localizedMuscleName(it, languageTag) }
                val header = stringResource(R.string.exercise_detail_muscles_header)
                val primaryTitle = stringResource(R.string.exercise_detail_muscles_primary)
                val secondaryTitle = stringResource(R.string.exercise_detail_muscles_secondary)
                val editTitle = stringResource(R.string.exercise_detail_muscles_edit)
                val accent = MaterialTheme.colorScheme.primary
                GroupedSection(header = header) {
                    if (names.isNotEmpty()) {
                        if (isBuiltIn && names.size > 1) {
                            row(primaryTitle, value = names.first())
                            row(secondaryTitle, subtitle = names.drop(1).joinToString(", "))
                        } else {
                            row(header, value = names.joinToString(", "))
                        }
                    }
                    row(editTitle, titleColor = accent, chevron = true, onClick = onEditMuscles)
                }
            }

            item(key = "actions") {
                val favoriteTitle = stringResource(
                    if (exercise.isFavorite) R.string.exercise_detail_favorite_remove
                    else R.string.exercise_detail_favorite_add
                )
                val stepsTitle = stringResource(R.string.exercise_load_profile_action)
                val editTitle = stringResource(R.string.exercise_detail_edit)
                val accent = MaterialTheme.colorScheme.primary
                GroupedSection {
                    row(favoriteTitle, titleColor = accent, onClick = onToggleFavorite)
                    row(stepsTitle, chevron = true, onClick = onEditWeightSteps)
                    if (!isBuiltIn) row(editTitle, chevron = true, onClick = onEdit)
                }
            }

            item(key = "delete") {
                val deleteTitle = stringResource(R.string.action_delete)
                val danger = MaterialTheme.colorScheme.error
                GroupedSection {
                    row(deleteTitle, titleColor = danger, onClick = onDelete)
                }
            }
        }
    }
}
