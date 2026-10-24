package com.example.gymapp.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.Surface
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import com.example.gymapp.ui.theme.GymPanelShape
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import com.example.gymapp.ui.components.GymModalBottomSheet
import com.example.gymapp.ui.components.GymSheetTitleRow
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.util.formattedPluralStringResource

/** Which flow the catalog sheet serves: adding an exercise to a workout, or choosing one to view. */
internal enum class ExerciseSelectorMode { Add, Choose }

/**
 * Shared catalog picker for both new-workout planning and editing saved workouts.
 *
 * The caller supplies an account-bound media owner key. Catalog rows are only selected here;
 * this component never renames, deletes, or rewrites legacy/custom exercise history.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ExerciseCatalogSelector(
    selectedExerciseId: Long?,
    exercises: List<ExerciseEntity>,
    frequentExerciseIds: List<Long>,
    exerciseWorkoutCounts: Map<Long, Int>,
    exerciseMuscleIds: Map<String, Set<String>>,
    exerciseMediaOwnerKey: String,
    onExerciseSelected: (Long) -> Unit,
    modifier: Modifier = Modifier,
    trigger: (@Composable (openPicker: () -> Unit) -> Unit)? = null,
    /** Lets a caller with several "add" buttons open the picker itself; [onExternalDismiss] resets its flag. */
    externalOpen: Boolean = false,
    onExternalDismiss: () -> Unit = {},
    /** [ExerciseSelectorMode.Choose] is the Progress picker: own title, no add-flow chips, session counts. */
    mode: ExerciseSelectorMode = ExerciseSelectorMode.Add
) {
    val isChooseMode = mode == ExerciseSelectorMode.Choose
    var internalExpanded by rememberSaveable { mutableStateOf(false) }
    val expanded = internalExpanded || externalOpen
    val closePicker = {
        internalExpanded = false
        onExternalDismiss()
    }
    var query by rememberSaveable { mutableStateOf("") }
    var frequentOnly by rememberSaveable { mutableStateOf(false) }
    var bodyFilter by rememberSaveable { mutableStateOf(ExerciseBodyFilter.All) }
    var muscleFilter by rememberSaveable { mutableStateOf<String?>(null) }
    var sortMode by rememberSaveable { mutableStateOf(ExerciseSortMode.Name) }
    var favoritesOnly by rememberSaveable { mutableStateOf(false) }
    val languageTag = currentAppLanguageTag()
    val selectedLabel = exercises
        .firstOrNull { it.id == selectedExerciseId }
        ?.let { BuiltInExerciseCatalog.displayName(it.name, languageTag) }
        ?: stringResource(R.string.label_select_exercise)
    val visibleExercises = remember(
        exercises,
        frequentExerciseIds,
        exerciseWorkoutCounts,
        exerciseMuscleIds,
        query,
        frequentOnly,
        bodyFilter,
        muscleFilter,
        sortMode,
        favoritesOnly,
        languageTag
    ) {
        filterAndSortExercises(
            exercises = exercises,
            exerciseWorkoutCounts = exerciseWorkoutCounts,
            muscleIdsByExerciseName = exerciseMuscleIds,
            query = query,
            bodyFilter = bodyFilter,
            muscleFilter = muscleFilter,
            sortMode = sortMode,
            favoritesOnly = favoritesOnly,
            languageTag = languageTag
        ).filter { exercise -> !frequentOnly || exercise.id in frequentExerciseIds }
    }

    if (trigger != null) {
        trigger { internalExpanded = true }
    } else {
        OutlinedButton(
            onClick = { internalExpanded = true },
            modifier = modifier.fillMaxWidth()
        ) {
            Icon(imageVector = Icons.Default.Search, contentDescription = null)
            Text(
                text = selectedLabel,
                modifier = Modifier.padding(start = 8.dp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }

    if (expanded) {
        GymModalBottomSheet(
            skipPartiallyExpanded = true,
            onDismissRequest = closePicker
        ) {
            Column(
                // Fixed height: the sheet never resizes or settles while the list is flung.
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.9f)
                    .imePadding()
                    .padding(start = 16.dp, end = 16.dp, bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                GymSheetTitleRow(
                    title = stringResource(
                        if (isChooseMode) R.string.progress_choose_exercise else R.string.action_add_exercise
                    ),
                    onClose = closePicker,
                    style = androidx.compose.material3.MaterialTheme.typography.titleLarge.copy(
                        fontWeight = FontWeight.Bold
                    )
                )
                if (!isChooseMode) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ExerciseMuscleChip(
                        selected = !frequentOnly,
                        onClick = { frequentOnly = false },
                        label = stringResource(R.string.exercise_picker_all)
                    )
                    ExerciseMuscleChip(
                        selected = frequentOnly,
                        onClick = {
                            frequentOnly = true
                            sortMode = ExerciseSortMode.MostFrequent
                        },
                        label = stringResource(R.string.exercise_picker_frequent),
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Default.Star,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    )
                }
                ExerciseSearchAndFilters(
                    query = query,
                    onQueryChange = { query = it.take(EXERCISE_SEARCH_QUERY_MAX_CHARS) },
                    bodyFilter = bodyFilter,
                    onBodyFilterChange = { bodyFilter = it },
                    muscleFilter = muscleFilter,
                    onMuscleFilterChange = { muscleFilter = it },
                    sortMode = sortMode,
                    onSortModeChange = { sortMode = it },
                    favoritesOnly = favoritesOnly,
                    onFavoritesOnlyChange = { favoritesOnly = it },
                    resultCount = visibleExercises.size
                )
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .nestedScroll(remember { ConsumeListOverscrollConnection }),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    if (visibleExercises.isEmpty()) {
                        item {
                            Text(
                                text = if (frequentOnly && frequentExerciseIds.isEmpty()) {
                                    stringResource(R.string.exercise_picker_frequent_empty)
                                } else {
                                    stringResource(R.string.exercise_search_no_results)
                                },
                                modifier = Modifier.padding(vertical = 20.dp),
                                style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                                color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        items(visibleExercises, key = { it.id }) { exercise ->
                            val searchMatchReason = exerciseSearchMatch(exercise.name, query)?.reason
                            // Same solid hairline row as the Exercises list: primary text, no blue capsule.
                            Surface(
                                onClick = {
                                    onExerciseSelected(exercise.id)
                                    closePicker()
                                },
                                modifier = Modifier.fillMaxWidth(),
                                shape = GymPanelShape,
                                color = androidx.compose.material3.MaterialTheme.colorScheme.surface,
                                contentColor = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
                                border = BorderStroke(
                                    1.dp,
                                    androidx.compose.material3.MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.62f)
                                )
                            ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .heightIn(min = 56.dp)
                                    .padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                ExerciseMediaPreview(
                                    exerciseId = exercise.id,
                                    exerciseName = exercise.name,
                                    ownerKey = exerciseMediaOwnerKey,
                                    width = 64.dp,
                                    height = 52.dp,
                                    editable = false
                                )
                                Column(
                                    modifier = Modifier
                                        .weight(1f)
                                        .padding(start = 10.dp),
                                    verticalArrangement = Arrangement.spacedBy(2.dp)
                                ) {
                                    Text(
                                        text = BuiltInExerciseCatalog.displayName(
                                            exercise.name,
                                            languageTag
                                        ),
                                        style = androidx.compose.material3.MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    if (searchMatchReason != null) {
                                        Text(
                                            text = localizedExerciseSearchMatchReason(
                                                searchMatchReason
                                            ),
                                            style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                                            color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 2,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                    } else if (isChooseMode) {
                                        val sessionCount = exerciseWorkoutCounts[exercise.id] ?: 0
                                        Text(
                                            text = formattedPluralStringResource(
                                                R.plurals.progress_sessions_count,
                                                sessionCount,
                                                sessionCount
                                            ),
                                            style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                                            color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                    }
                                }
                                if (exercise.id == selectedExerciseId) {
                                    Spacer(modifier = Modifier.size(8.dp))
                                    Icon(
                                        imageVector = Icons.Default.CheckCircle,
                                        contentDescription = null,
                                        tint = androidx.compose.material3.MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Keeps the exercise list's leftover scroll/fling out of the parent bottom sheet. Without it the
 * sheet's nested-scroll connection swallows the fling remainder at a list edge and starts a
 * settle animation that eats the next drag. The sheet still dismisses via its drag handle.
 */
private object ConsumeListOverscrollConnection : NestedScrollConnection {
    override fun onPostScroll(
        consumed: Offset,
        available: Offset,
        source: NestedScrollSource
    ): Offset = Offset(0f, available.y)

    override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity =
        Velocity(0f, available.y)
}
