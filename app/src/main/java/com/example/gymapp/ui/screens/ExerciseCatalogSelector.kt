package com.example.gymapp.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.OutlinedTextField
import androidx.compose.runtime.rememberCoroutineScope
import com.example.gymapp.data.repository.DuplicateExerciseNameException
import com.example.gymapp.data.repository.ExerciseLimitReachedException
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.ui.theme.Button
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.viewmodel.RECENT_EXERCISES_MAX
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
    mode: ExerciseSelectorMode = ExerciseSelectorMode.Add,
    /**
     * Adds a "Create exercise" panel (Add mode only): creates a custom exercise and returns its id,
     * which is then selected and the picker closes, like iOS "Create and add".
     */
    onCreateExercise: (suspend (String) -> Long)? = null,
    /** Exercises already in the plan: shown with a check and not selectable again (Add mode). */
    addedExerciseIds: Set<Long> = emptySet(),
    /** Distinct logged exercises, newest first: the "Recent" section (minus [addedExerciseIds], max 8) while no search or filter is active (Add mode). */
    recentExerciseIds: List<Long> = emptyList()
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

    // Exercises already in the plan are not offered in Recent (they would only be disabled rows), and
    // do not use up one of the slots: the section backfills to the cap.
    val recentExercises = remember(exercises, recentExerciseIds, addedExerciseIds) {
        val byId = exercises.associateBy { it.id }
        recentExerciseIds
            .filter { it !in addedExerciseIds }
            .mapNotNull { byId[it] }
            .take(RECENT_EXERCISES_MAX)
    }
    val showRecent = !isChooseMode && recentExercises.isNotEmpty() && query.isBlank() &&
        !frequentOnly && !favoritesOnly && bodyFilter == ExerciseBodyFilter.All && muscleFilter == null

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
                    verticalArrangement = Arrangement.spacedBy(0.dp)
                ) {
                    if (showRecent) {
                        item(key = "recent-header") {
                            PickerSectionTitle(stringResource(R.string.picker_recent_title))
                        }
                        items(recentExercises, key = { "recent-${it.id}" }) { exercise ->
                            ExercisePickerRow(
                                exercise = exercise,
                                languageTag = languageTag,
                                query = query,
                                muscleIds = exerciseMuscleIds[exercise.name],
                                isChooseMode = false,
                                sessionCount = 0,
                                selected = exercise.id == selectedExerciseId,
                                alreadyAdded = false,
                                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                                isFirstInGroup = exercise.id == recentExercises.first().id,
                                isLastInGroup = exercise.id == recentExercises.last().id,
                                onClick = {
                                    onExerciseSelected(exercise.id)
                                    closePicker()
                                }
                            )
                        }
                    }
                    if (!isChooseMode && onCreateExercise != null) {
                        item(key = "create-exercise") {
                            Box(modifier = Modifier.padding(vertical = 8.dp)) {
                                CreateExercisePanel(
                                    searchQuery = query,
                                    onCreate = onCreateExercise,
                                    onCreated = { exerciseId ->
                                        onExerciseSelected(exerciseId)
                                        closePicker()
                                    }
                                )
                            }
                        }
                    }
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
                        if (showRecent) {
                            item(key = "all-header") {
                                PickerSectionTitle(stringResource(R.string.picker_recent_all_title))
                            }
                        }
                        items(visibleExercises, key = { it.id }) { exercise ->
                            ExercisePickerRow(
                                exercise = exercise,
                                languageTag = languageTag,
                                query = query,
                                muscleIds = exerciseMuscleIds[exercise.name],
                                isChooseMode = isChooseMode,
                                sessionCount = exerciseWorkoutCounts[exercise.id] ?: 0,
                                selected = exercise.id == selectedExerciseId,
                                alreadyAdded = !isChooseMode && exercise.id in addedExerciseIds,
                                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                                isFirstInGroup = exercise.id == visibleExercises.first().id,
                                isLastInGroup = exercise.id == visibleExercises.last().id,
                                onClick = {
                                    onExerciseSelected(exercise.id)
                                    closePicker()
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Plain section label of the picker list: tonal secondary text, no caps, no rule. */
@Composable
private fun PickerSectionTitle(text: String) {
    Text(
        text = text,
        // Start inset 12dp = the grouped rows' content start; 16dp above / 6dp below replaces the old list gap.
        modifier = Modifier.padding(top = 16.dp, bottom = 6.dp, start = 12.dp),
        style = androidx.compose.material3.MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant
    )
}

/** One exercise row of the picker, shared by the "Recent" section and the normal list. */
@Composable
private fun ExercisePickerRow(
    exercise: ExerciseEntity,
    languageTag: String,
    query: String,
    muscleIds: Set<String>?,
    isChooseMode: Boolean,
    sessionCount: Int,
    selected: Boolean,
    alreadyAdded: Boolean,
    exerciseMediaOwnerKey: String,
    isFirstInGroup: Boolean,
    isLastInGroup: Boolean,
    onClick: () -> Unit
) {
    val searchMatchReason = exerciseSearchMatch(exercise.name, query, muscleIds)?.reason
    // Inset-grouped row: consecutive rows share one tonal container (outer corners only on the group's
    // first and last row) and are split by a hairline inset past the thumbnail.
    val groupRadius = 12.dp
    Surface(
        onClick = onClick,
        enabled = !alreadyAdded,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(
            topStart = if (isFirstInGroup) groupRadius else 0.dp,
            topEnd = if (isFirstInGroup) groupRadius else 0.dp,
            bottomStart = if (isLastInGroup) groupRadius else 0.dp,
            bottomEnd = if (isLastInGroup) groupRadius else 0.dp
        ),
        color = androidx.compose.material3.MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
        contentColor = androidx.compose.material3.MaterialTheme.colorScheme.onSurface
    ) {
      Box {
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
                    text = BuiltInExerciseCatalog.displayName(exercise.name, languageTag),
                    style = androidx.compose.material3.MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                if (searchMatchReason != null) {
                    Text(
                        text = localizedExerciseSearchMatchReason(searchMatchReason),
                        style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                        color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                } else if (isChooseMode) {
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
            if (selected || alreadyAdded) {
                Spacer(modifier = Modifier.size(8.dp))
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = null,
                    tint = androidx.compose.material3.MaterialTheme.colorScheme.primary
                )
            }
        }
        if (!isLastInGroup) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 86.dp)
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(
                        androidx.compose.material3.MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                    )
            )
        }
      }
    }
}

/** Inline validation outcome of the picker's "Create exercise" panel (iOS invalid / duplicate name). */
enum class NewExerciseError { Invalid, Duplicate, LimitReached }

/** Maps a failed [com.example.gymapp.data.repository.GymRepository.addExercise] to its inline message. */
internal fun newExerciseErrorFor(error: Throwable): NewExerciseError =
    when (error) {
        is DuplicateExerciseNameException -> NewExerciseError.Duplicate
        is ExerciseLimitReachedException -> NewExerciseError.LimitReached
        else -> NewExerciseError.Invalid
    }

/**
 * Name field + "Create and add" at the top of the picker list, always present in Add mode (iOS puts
 * the same section first). Until the user edits the field it mirrors the search query, so a search
 * with no match is one tap from creating that exercise.
 */
@Composable
private fun CreateExercisePanel(
    searchQuery: String,
    onCreate: suspend (String) -> Long,
    onCreated: (Long) -> Unit
) {
    var edited by rememberSaveable { mutableStateOf(false) }
    var typedName by rememberSaveable { mutableStateOf("") }
    var error by remember { mutableStateOf<NewExerciseError?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val name = if (edited) typedName else searchQuery
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = GymPanelShape,
        color = androidx.compose.material3.MaterialTheme.colorScheme.surface,
        contentColor = androidx.compose.material3.MaterialTheme.colorScheme.onSurface,
        border = BorderStroke(
            1.dp,
            androidx.compose.material3.MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.62f)
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(R.string.exercise_picker_create_title),
                style = androidx.compose.material3.MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            OutlinedTextField(
                value = name,
                onValueChange = {
                    edited = true
                    typedName = it.take(WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH)
                    error = null
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.exercise_picker_create_name)) },
                isError = error != null,
                singleLine = true
            )
            error?.let { current ->
                Text(
                    text = stringResource(
                        when (current) {
                            NewExerciseError.Duplicate -> R.string.exercise_picker_create_error_duplicate
                            NewExerciseError.LimitReached -> R.string.exercise_picker_create_error_limit
                            NewExerciseError.Invalid -> R.string.exercise_picker_create_error_invalid
                        }
                    ),
                    color = androidx.compose.material3.MaterialTheme.colorScheme.error,
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium
                )
            }
            Button(
                onClick = {
                    if (busy) return@Button
                    busy = true
                    scope.launch {
                        try {
                            onCreated(onCreate(name.trim()))
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (failure: Throwable) {
                            error = newExerciseErrorFor(failure)
                        } finally {
                            busy = false
                        }
                    }
                },
                enabled = name.isNotBlank() && !busy,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 52.dp)
            ) {
                Icon(imageVector = Icons.Default.Add, contentDescription = null)
                Text(
                    text = stringResource(R.string.exercise_picker_create_action),
                    modifier = Modifier.padding(start = 8.dp)
                )
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
