package com.example.gymapp.ui.screens

import android.content.Intent
import android.content.Context
import android.content.ClipData
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import androidx.compose.foundation.clickable
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.data.repository.MUSCLE_DEFINITIONS
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.ExerciseMuscleBreakdownCard
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.util.localizedMuscleName
import com.example.gymapp.ui.util.SensitiveClipboard
import com.example.gymapp.ui.viewmodel.ExerciseListUiState
import com.example.gymapp.ui.viewmodel.ExerciseMuscleOptionUiModel
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.asString
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.text.DateFormat
import java.util.Date
import java.util.Locale
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

private const val BACKUP_PREVIEW_CHARS = 4_000
private const val MAX_PDF_PAGES = 24
private const val MAX_PDF_REPORT_LINES = 480
private const val MAX_PDF_EXERCISES = 120
private const val MAX_PDF_SESSIONS = 60
private const val MAX_PDF_EXERCISES_PER_SESSION = 24
private const val MAX_PDF_SETS_PER_EXERCISE = 20
private const val MAX_PDF_TEXT_CHARS = 320
private const val PRIVATE_SHARE_RETENTION_MILLIS = 24 * 60 * 60 * 1_000L
private const val MAX_RETAINED_PRIVATE_SHARE_FILES = 32
private val PRIVATE_SHARE_FILE_LOCK = Any()

private enum class ExerciseBodyFilter(val muscleIds: Set<String>) {
    All(emptySet()),
    Upper(setOf("chest", "shoulders", "biceps", "triceps", "forearms", "lats", "upperBack")),
    Lower(setOf("lowerBack", "glutes", "quads", "hamstrings", "adductors", "calves")),
    Core(setOf("abs", "obliques"))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AccountBackupSheets(
    uiState: ExerciseListUiState,
    onClearBackup: () -> Unit,
    onCloseImport: () -> Unit,
    onImportJsonChange: (String) -> Unit,
    onImportBackup: () -> Unit
) {
    val backupJson = uiState.backupJson
    if (backupJson != null) {
        ModalBottomSheet(
            onDismissRequest = onClearBackup,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            BackupJsonBottomSheetContent(
                json = backupJson,
                diagnosticsOnly = uiState.backupIsDiagnostics,
                onDismiss = onClearBackup
            )
        }
    }

    if (uiState.isImportOpen) {
        ModalBottomSheet(
            onDismissRequest = onCloseImport,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            ImportBackupBottomSheetContent(
                importJson = uiState.importJson,
                importMessage = uiState.importMessage,
                onImportJsonChange = onImportJsonChange,
                onImportBackup = onImportBackup,
                onDismiss = onCloseImport
            )
        }
    }
}

private enum class ExerciseSortMode {
    Name,
    MostFrequent,
    LeastFrequent
}

private data class ExerciseHistorySessionGroup(
    val sessionId: Long,
    val sessionDate: Long,
    val sets: List<ExerciseHistoryEntry>
)

internal fun exerciseNameMatchesLocalizedQuery(exerciseName: String, query: String): Boolean {
    val normalizedQuery = query.trim().lowercase(Locale.ROOT)
    if (normalizedQuery.isEmpty()) return true
    val definition = BuiltInExerciseCatalog.definitionForName(exerciseName)
    val searchableNames = buildList {
        add(exerciseName)
        definition?.let {
            add(it.nameEn)
            add(it.nameUk)
            add(BuiltInExerciseCatalog.displayName(exerciseName, "ru"))
            addAll(it.legacyAliases)
        }
    }
    return searchableNames.any { name ->
        name.lowercase(Locale.ROOT).contains(normalizedQuery)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExerciseListScreen(
    uiState: ExerciseListUiState,
    onNameChange: (String) -> Unit,
    onAddExercise: () -> Unit,
    onExerciseClick: (Long) -> Unit,
    onStartRenameExercise: (ExerciseEntity) -> Unit,
    onRenameExerciseNameChange: (String) -> Unit,
    onSaveRenameExercise: () -> Unit,
    onDismissRenameExercise: () -> Unit,
    onDeleteExercise: (ExerciseEntity) -> Unit,
    onEditExerciseMapping: (String) -> Unit,
    onToggleExerciseMappingMuscle: (String) -> Unit,
    onSaveExerciseMapping: () -> Unit,
    onDismissExerciseMapping: () -> Unit,
    onDismissHistory: () -> Unit,
    onToggleFavorite: (ExerciseEntity) -> Unit,
    modifier: Modifier = Modifier
) {
    var isAddExerciseOpen by rememberSaveable { mutableStateOf(false) }
    var pendingAddedName by rememberSaveable { mutableStateOf<String?>(null) }
    var searchQuery by rememberSaveable { mutableStateOf("") }
    var bodyFilter by rememberSaveable { mutableStateOf(ExerciseBodyFilter.All) }
    var muscleFilter by rememberSaveable { mutableStateOf<String?>(null) }
    var sortMode by rememberSaveable { mutableStateOf(ExerciseSortMode.Name) }
    var favoritesOnly by rememberSaveable { mutableStateOf(false) }
    val languageTag = currentAppLanguageTag()
    val musclesByExercise = remember(uiState.muscleMappings) {
        uiState.muscleMappings.associate { mapping -> mapping.exerciseName to mapping.muscleIds.toSet() }
    }
    val filteredExercises = remember(
        uiState.exercises,
        uiState.exerciseWorkoutCounts,
        musclesByExercise,
        searchQuery,
        bodyFilter,
        muscleFilter,
        sortMode,
        favoritesOnly,
        languageTag
    ) {
        val filtered = uiState.exercises.filter { exercise ->
            val muscleIds = musclesByExercise[exercise.name].orEmpty()
            val matchesQuery = exerciseNameMatchesLocalizedQuery(exercise.name, searchQuery)
            val matchesBody = bodyFilter == ExerciseBodyFilter.All ||
                muscleIds.any(bodyFilter.muscleIds::contains)
            val matchesMuscle = muscleFilter == null || muscleFilter in muscleIds
            val matchesFavorite = !favoritesOnly || exercise.isFavorite
            matchesQuery && matchesBody && matchesMuscle && matchesFavorite
        }
        val byName = compareBy<ExerciseEntity> {
            BuiltInExerciseCatalog.displayName(it.name, languageTag).lowercase(Locale.ROOT)
        }.thenBy { it.id }
        when (sortMode) {
            ExerciseSortMode.Name -> filtered.sortedWith(byName)
            ExerciseSortMode.MostFrequent -> filtered.sortedWith(
                compareByDescending<ExerciseEntity> { uiState.exerciseWorkoutCounts[it.id] ?: 0 }
                    .then(byName)
            )
            ExerciseSortMode.LeastFrequent -> filtered.sortedWith(
                compareBy<ExerciseEntity> { uiState.exerciseWorkoutCounts[it.id] ?: 0 }
                    .then(byName)
            )
        }
    }
    LaunchedEffect(uiState.newExerciseName, uiState.hasInputError, pendingAddedName) {
        if (
            pendingAddedName != null &&
            uiState.newExerciseName.isBlank() &&
            !uiState.hasInputError
        ) {
            isAddExerciseOpen = false
            pendingAddedName = null
        } else if (uiState.hasInputError) {
            pendingAddedName = null
        }
    }

    LazyColumn(
        modifier = modifier
            .fillMaxSize(),
        contentPadding = PaddingValues(
            start = 14.dp,
            top = 10.dp,
            end = 14.dp,
            bottom = 28.dp
        ),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = stringResource(R.string.title_exercises),
                    style = MaterialTheme.typography.headlineLarge,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Text(
                    text = stringResource(R.string.exercises_screen_subtitle),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        item {
            Button(
                onClick = { isAddExerciseOpen = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 52.dp),
                shape = MaterialTheme.shapes.small
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = null
                )
                Text(
                    text = stringResource(R.string.action_add_exercise),
                    modifier = Modifier.padding(start = 8.dp),
                    maxLines = 1
                )
            }
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    SectionTitle(
                        eyebrow = stringResource(R.string.exercise_library_eyebrow),
                        title = stringResource(R.string.exercise_library_title),
                        supporting = stringResource(R.string.exercise_library_supporting)
                    )
                }
            }
        }

        item {
            ExerciseSearchAndFilters(
                query = searchQuery,
                onQueryChange = { searchQuery = it },
                bodyFilter = bodyFilter,
                onBodyFilterChange = { bodyFilter = it },
                muscleFilter = muscleFilter,
                onMuscleFilterChange = { muscleFilter = it },
                sortMode = sortMode,
                onSortModeChange = { sortMode = it },
                favoritesOnly = favoritesOnly,
                onFavoritesOnlyChange = { favoritesOnly = it },
                resultCount = filteredExercises.size
            )
        }

        if (filteredExercises.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = if (uiState.exercises.isEmpty()) {
                        stringResource(R.string.empty_exercises)
                    } else {
                        stringResource(R.string.exercise_search_no_results)
                    },
                    supporting = if (uiState.exercises.isEmpty()) {
                        stringResource(R.string.exercise_library_empty_supporting)
                    } else {
                        stringResource(R.string.exercise_search_no_results_supporting)
                    }
                )
            }
        } else {
            items(
                items = filteredExercises,
                key = { it.id }
            ) { exercise ->
                val mappingCount = musclesByExercise[exercise.name].orEmpty().size
                val workoutCount = uiState.exerciseWorkoutCounts[exercise.id] ?: 0
                val isBuiltIn = BuiltInExerciseCatalog.definitionForName(exercise.name) != null
                AppPanel(
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(13.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text(
                                text = localizedExerciseName(exercise.name),
                                modifier = Modifier.weight(1f),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                            if (isBuiltIn) {
                                InfoPill(text = stringResource(R.string.exercise_card_built_in))
                            } else {
                                IconButton(onClick = { onStartRenameExercise(exercise) }) {
                                    Icon(
                                        imageVector = Icons.Default.Edit,
                                        contentDescription = stringResource(R.string.cd_edit)
                                    )
                                }
                            }
                            IconButton(onClick = { onToggleFavorite(exercise) }) {
                                Icon(
                                    imageVector = if (exercise.isFavorite) {
                                        Icons.Default.Favorite
                                    } else {
                                        Icons.Default.FavoriteBorder
                                    },
                                    contentDescription = stringResource(
                                        if (exercise.isFavorite) {
                                            R.string.exercise_favorite_remove
                                        } else {
                                            R.string.exercise_favorite_add
                                        }
                                    ),
                                    tint = if (exercise.isFavorite) {
                                        MaterialTheme.colorScheme.primary
                                    } else {
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                    }
                                )
                            }
                            IconButton(onClick = { onDeleteExercise(exercise) }) {
                                Icon(
                                    imageVector = Icons.Default.Delete,
                                    contentDescription = stringResource(R.string.cd_delete),
                                    tint = MaterialTheme.colorScheme.onSurface
                                )
                            }
                        }

                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ExerciseMetricPill(
                                icon = Icons.Default.FormatListNumbered,
                                text = stringResource(R.string.exercise_workout_count_compact, workoutCount)
                            )
                            ExerciseMetricPill(
                                icon = Icons.Default.FitnessCenter,
                                text = if (mappingCount == 0) {
                                    stringResource(R.string.exercise_card_auto_mapping)
                                } else {
                                    stringResource(R.string.exercise_card_mapped_count, mappingCount)
                                }
                            )
                        }

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            OutlinedButton(
                                onClick = { onExerciseClick(exercise.id) },
                                modifier = Modifier
                                    .weight(1f)
                                    .heightIn(min = 58.dp)
                            ) {
                                Icon(imageVector = Icons.Default.History, contentDescription = null)
                                Text(
                                    text = stringResource(R.string.exercise_card_history),
                                    modifier = Modifier.padding(start = 8.dp),
                                    maxLines = 2
                                )
                            }
                            OutlinedButton(
                                onClick = { onEditExerciseMapping(exercise.name) },
                                modifier = Modifier
                                    .weight(1f)
                                    .heightIn(min = 58.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.FitnessCenter,
                                    contentDescription = null
                                )
                                Text(
                                    text = stringResource(R.string.exercise_card_muscle_groups),
                                    modifier = Modifier.padding(start = 8.dp),
                                    maxLines = 2
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (isAddExerciseOpen) {
        ModalBottomSheet(
            onDismissRequest = {
                isAddExerciseOpen = false
                pendingAddedName = null
            },
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            AddExerciseBottomSheetContent(
                exerciseName = uiState.newExerciseName,
                hasInputError = uiState.hasInputError,
                onExerciseNameChange = onNameChange,
                onAdd = {
                    pendingAddedName = uiState.newExerciseName.trim().takeIf { it.isNotEmpty() }
                    onAddExercise()
                }
            )
        }
    }

    val editingExercise = uiState.editingExercise
    if (editingExercise != null) {
        ModalBottomSheet(
            onDismissRequest = onDismissRenameExercise,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            RenameExerciseBottomSheetContent(
                exerciseName = uiState.editingExerciseName,
                rawExerciseName = editingExercise.name,
                hasInputError = uiState.hasInputError,
                onExerciseNameChange = onRenameExerciseNameChange,
                onSave = onSaveRenameExercise,
                onDismiss = onDismissRenameExercise
            )
        }
    }

    val selectedExerciseId = uiState.selectedExerciseId
    val selectedExerciseName = uiState.selectedExerciseName
    if (selectedExerciseId != null && selectedExerciseName != null) {
        ModalBottomSheet(
            onDismissRequest = onDismissHistory,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            ExerciseHistoryBottomSheetContent(
                exerciseName = selectedExerciseName,
                history = uiState.selectedExerciseHistory,
                onEditExerciseMapping = {
                    onDismissHistory()
                    onEditExerciseMapping(selectedExerciseName)
                }
            )
        }
    }

    val mappingExerciseName = uiState.mappingEditorExerciseName
    if (mappingExerciseName != null) {
        ModalBottomSheet(
            onDismissRequest = onDismissExerciseMapping,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            ExerciseMappingBottomSheetContent(
                exerciseName = mappingExerciseName,
                muscles = uiState.mappingEditorMuscles,
                onToggleMuscle = onToggleExerciseMappingMuscle,
                onSave = onSaveExerciseMapping,
                onDismiss = onDismissExerciseMapping
            )
        }
    }

}

@Composable
private fun ExerciseMetricPill(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String
) {
    val accent = MaterialTheme.colorScheme.primary
    Surface(
        color = accent.copy(alpha = 0.10f),
        contentColor = accent,
        shape = CircleShape,
        border = BorderStroke(1.dp, accent.copy(alpha = 0.22f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 11.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Icon(imageVector = icon, contentDescription = null, modifier = Modifier.size(17.dp))
            Text(
                text = text,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1
            )
        }
    }
}

@Composable
private fun ExerciseSearchAndFilters(
    query: String,
    onQueryChange: (String) -> Unit,
    bodyFilter: ExerciseBodyFilter,
    onBodyFilterChange: (ExerciseBodyFilter) -> Unit,
    muscleFilter: String?,
    onMuscleFilterChange: (String?) -> Unit,
    sortMode: ExerciseSortMode,
    onSortModeChange: (ExerciseSortMode) -> Unit,
    favoritesOnly: Boolean,
    onFavoritesOnlyChange: (Boolean) -> Unit,
    resultCount: Int
) {
    val languageTag = currentAppLanguageTag()
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            OutlinedTextField(
                value = query,
                onValueChange = onQueryChange,
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                leadingIcon = {
                    Icon(Icons.Default.Search, contentDescription = null)
                },
                trailingIcon = if (query.isNotEmpty()) {
                    {
                        IconButton(onClick = { onQueryChange("") }) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = stringResource(R.string.exercise_search_clear)
                            )
                        }
                    }
                } else {
                    null
                },
                label = { Text(stringResource(R.string.exercise_search_label)) },
                placeholder = { Text(stringResource(R.string.exercise_search_placeholder)) }
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilterChip(
                    selected = favoritesOnly,
                    onClick = { onFavoritesOnlyChange(!favoritesOnly) },
                    leadingIcon = {
                        Icon(
                            imageVector = if (favoritesOnly) {
                                Icons.Default.Favorite
                            } else {
                                Icons.Default.FavoriteBorder
                            },
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                    },
                    label = { Text(stringResource(R.string.exercise_filter_favorites)) }
                )
                ExerciseBodyFilter.entries.forEach { filter ->
                    val label = when (filter) {
                        ExerciseBodyFilter.All -> R.string.exercise_filter_all
                        ExerciseBodyFilter.Upper -> R.string.exercise_filter_upper
                        ExerciseBodyFilter.Lower -> R.string.exercise_filter_lower
                        ExerciseBodyFilter.Core -> R.string.exercise_filter_core
                    }
                    FilterChip(
                        selected = bodyFilter == filter,
                        onClick = { onBodyFilterChange(filter) },
                        label = { Text(stringResource(label)) }
                    )
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ExerciseSortMode.entries.forEach { mode ->
                    val label = when (mode) {
                        ExerciseSortMode.Name -> R.string.exercise_sort_name
                        ExerciseSortMode.MostFrequent -> R.string.exercise_sort_most_frequent
                        ExerciseSortMode.LeastFrequent -> R.string.exercise_sort_least_frequent
                    }
                    FilterChip(
                        selected = sortMode == mode,
                        onClick = { onSortModeChange(mode) },
                        label = { Text(stringResource(label)) }
                    )
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilterChip(
                    selected = muscleFilter == null,
                    onClick = { onMuscleFilterChange(null) },
                    label = { Text(stringResource(R.string.exercise_filter_all_muscles)) }
                )
                MUSCLE_DEFINITIONS.forEach { muscle ->
                    FilterChip(
                        selected = muscleFilter == muscle.id,
                        onClick = {
                            onMuscleFilterChange(if (muscleFilter == muscle.id) null else muscle.id)
                        },
                        label = { Text(localizedMuscleName(muscle.id, languageTag)) }
                    )
                }
            }

            Text(
                text = stringResource(R.string.exercise_search_result_count, resultCount),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun AddExerciseBottomSheetContent(
    exerciseName: String,
    hasInputError: Boolean,
    onExerciseNameChange: (String) -> Unit,
    onAdd: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        SectionTitle(
            eyebrow = stringResource(R.string.exercise_library_eyebrow),
            title = stringResource(R.string.action_add_exercise),
            supporting = stringResource(R.string.exercise_library_supporting)
        )
        OutlinedTextField(
            value = exerciseName,
            onValueChange = onExerciseNameChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text(stringResource(R.string.label_exercise_name)) },
            placeholder = { Text(stringResource(R.string.hint_exercise_name)) },
            singleLine = true
        )
        if (hasInputError) {
            Text(
                text = stringResource(R.string.message_exercise_error),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        Button(
            onClick = onAdd,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 52.dp),
            shape = MaterialTheme.shapes.small
        ) {
            Icon(
                imageVector = Icons.Default.Add,
                contentDescription = null
            )
            Text(
                text = stringResource(R.string.action_add_exercise),
                modifier = Modifier.padding(start = 8.dp)
            )
        }
    }
}

@Composable
private fun ExerciseMappingBottomSheetContent(
    exerciseName: String,
    muscles: List<ExerciseMuscleOptionUiModel>,
    onToggleMuscle: (String) -> Unit,
    onSave: () -> Unit,
    onDismiss: () -> Unit
) {
    val languageTag = currentAppLanguageTag()
    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text(
                text = stringResource(
                    R.string.exercise_mappings_editor_title,
                    localizedExerciseName(exerciseName)
                ),
                style = MaterialTheme.typography.headlineSmall
            )
        }
        items(
            items = muscles,
            key = { it.id }
        ) { muscle ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onToggleMuscle(muscle.id) }
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Checkbox(
                    checked = muscle.isSelected,
                    onCheckedChange = { onToggleMuscle(muscle.id) }
                )
                Text(
                    text = localizedMuscleName(muscle.id, languageTag),
                    style = MaterialTheme.typography.bodyLarge
                )
            }
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = onDismiss,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.action_cancel))
                }
                Button(
                    onClick = onSave,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.action_save))
                }
            }
        }
    }
}

@Composable
internal fun AccountStatusCard(
    label: String,
    supporting: String,
    isCloudAccount: Boolean,
    canLogout: Boolean,
    logoutEnabled: Boolean,
    onLogout: () -> Unit,
    onOpenGarminApp: () -> Unit,
    onResetGarminPairing: () -> Unit
) {
    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = supporting,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                InfoPill(
                    text = stringResource(
                        if (isCloudAccount) {
                            R.string.account_mode_cloud
                        } else {
                            R.string.account_mode_local
                        }
                    )
                )
            }
            if (canLogout) {
                OutlinedButton(
                    onClick = onLogout,
                    enabled = logoutEnabled,
                    modifier = Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.small
                ) {
                    Text(stringResource(R.string.auth_switch_account))
                }
            }
            OutlinedButton(
                onClick = onOpenGarminApp,
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.small
            ) {
                Text(stringResource(R.string.garmin_open_app))
            }
            OutlinedButton(
                onClick = onResetGarminPairing,
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.small
            ) {
                Text(stringResource(R.string.garmin_reset_pairing_action))
            }
        }
    }
}

@Composable
private fun RenameExerciseBottomSheetContent(
    exerciseName: String,
    rawExerciseName: String,
    hasInputError: Boolean,
    onExerciseNameChange: (String) -> Unit,
    onSave: () -> Unit,
    onDismiss: () -> Unit
) {
    val displayedExerciseName = if (exerciseName == rawExerciseName) {
        localizedExerciseName(rawExerciseName)
    } else {
        exerciseName
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            text = stringResource(R.string.exercise_rename_title),
            style = MaterialTheme.typography.headlineSmall
        )
        OutlinedTextField(
            value = displayedExerciseName,
            onValueChange = onExerciseNameChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text(stringResource(R.string.label_exercise_name)) },
            singleLine = true
        )
        if (hasInputError) {
            Text(
                text = stringResource(R.string.message_exercise_error),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier.weight(1f)
            ) {
                Text(stringResource(R.string.action_cancel))
            }
            Button(
                onClick = onSave,
                modifier = Modifier.weight(1f)
            ) {
                Text(stringResource(R.string.action_save))
            }
        }
    }
}

@Composable
internal fun BackupToolsCard(
    message: LocalizedText?,
    onExportBackup: () -> Unit,
    onExportDiagnostics: () -> Unit,
    onOpenImport: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.backup_tools_eyebrow),
                title = stringResource(R.string.backup_tools_title),
                supporting = stringResource(R.string.backup_tools_supporting)
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = onExportBackup,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        text = stringResource(R.string.backup_export_json),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                OutlinedButton(
                    onClick = onOpenImport,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        text = stringResource(R.string.backup_import_json),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            OutlinedButton(
                onClick = onExportDiagnostics,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.backup_export_diagnostics))
            }
            if (message != null) {
                Text(
                    text = message.asString(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
internal fun BackupJsonBottomSheetContent(
    json: String,
    diagnosticsOnly: Boolean,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showClipboardWarning by rememberSaveable { mutableStateOf(false) }
    var shareError by remember { mutableStateOf<LocalizedText?>(null) }
    val previewTruncatedMessage = stringResource(R.string.backup_preview_truncated)
    val preview = remember(json, previewTruncatedMessage) {
        if (json.length <= BACKUP_PREVIEW_CHARS) json else {
            json.take(BACKUP_PREVIEW_CHARS) +
                "\n… $previewTruncatedMessage"
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text(
                text = stringResource(
                    if (diagnosticsOnly) {
                        R.string.backup_diagnostics_ready
                    } else {
                        R.string.backup_export_ready
                    }
                ),
                style = MaterialTheme.typography.headlineSmall
            )
        }
        item {
            // A read-only text field remains selectable and would expose an unguarded Copy menu.
            // Plain Text outside SelectionContainer keeps the warned action as the only copy path.
            Text(
                text = preview,
                modifier = Modifier.fillMaxWidth(),
                style = MaterialTheme.typography.bodySmall,
                maxLines = 12,
                overflow = TextOverflow.Ellipsis
            )
        }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = { showClipboardWarning = true },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.backup_copy_json))
                }
                OutlinedButton(
                    onClick = {
                        shareError = null
                        scope.launch {
                            runCatching {
                                val file = withContext(Dispatchers.IO) {
                                    createBackupJsonFile(context, json)
                                }
                                sharePrivateBackupFile(
                                    context = context,
                                    file = file,
                                    mimeType = "application/json",
                                    chooserTitle = context.getString(R.string.backup_share_json)
                                )
                            }.onFailure { error ->
                                if (error is CancellationException) throw error
                                shareError = LocalizedText(R.string.backup_share_json_failed)
                            }
                        }
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.backup_share_json))
                }
            }
        }
        item {
            OutlinedButton(
                onClick = {
                    shareError = null
                    scope.launch {
                        runCatching {
                            val file = withContext(Dispatchers.IO) {
                                createBackupPdfFile(context, json)
                            }
                            sharePrivateBackupFile(
                                context = context,
                                file = file,
                                mimeType = "application/pdf",
                                chooserTitle = context.getString(R.string.backup_share_pdf)
                            )
                        }.onFailure { error ->
                            if (error is CancellationException) throw error
                            shareError = LocalizedText(R.string.backup_share_pdf_failed)
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.backup_share_pdf))
            }
        }
        if (shareError != null) {
            item {
                Text(
                    text = checkNotNull(shareError).asString(),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
        item {
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.action_close))
            }
        }
    }

    if (showClipboardWarning) {
        AlertDialog(
            onDismissRequest = { showClipboardWarning = false },
            title = { Text(stringResource(R.string.backup_copy_warning_title)) },
            text = { Text(stringResource(R.string.backup_copy_warning_message)) },
            confirmButton = {
                Button(
                    onClick = {
                        if (!SensitiveClipboard.copyBackup(context, json)) {
                            shareError = LocalizedText(R.string.backup_clipboard_too_large)
                        }
                        showClipboardWarning = false
                    }
                ) {
                    Text(stringResource(R.string.backup_copy_confirm))
                }
            },
            dismissButton = {
                OutlinedButton(onClick = { showClipboardWarning = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

@Composable
internal fun ImportBackupBottomSheetContent(
    importJson: String,
    importMessage: LocalizedText?,
    onImportJsonChange: (String) -> Unit,
    onImportBackup: () -> Unit,
    onDismiss: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            text = stringResource(R.string.backup_import_title),
            style = MaterialTheme.typography.headlineSmall
        )
        OutlinedTextField(
            value = importJson,
            onValueChange = onImportJsonChange,
            modifier = Modifier.fillMaxWidth(),
            minLines = 6,
            maxLines = 12,
            placeholder = { Text(stringResource(R.string.backup_import_placeholder)) }
        )
        if (importMessage != null) {
            Text(
                text = importMessage.asString(),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier.weight(1f)
            ) {
                Text(stringResource(R.string.action_cancel))
            }
            Button(
                onClick = onImportBackup,
                modifier = Modifier.weight(1f)
            ) {
                Text(stringResource(R.string.backup_import_action))
            }
        }
    }
}

private fun sharePrivateBackupFile(
    context: Context,
    file: File,
    mimeType: String,
    chooserTitle: String
) {
    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file
    )
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = mimeType
        putExtra(Intent.EXTRA_STREAM, uri)
        clipData = ClipData.newRawUri(file.name, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(
        Intent.createChooser(
            sendIntent,
            chooserTitle
        )
    )
}

private fun createBackupJsonFile(context: Context, json: String): File {
    val bytes = json.toByteArray(Charsets.UTF_8)
    check(bytes.size <= WorkoutDataLimits.MAX_BACKUP_BYTES) {
        "Backup exceeds the private share size limit."
    }
    val outputFile = createPrivateBackupShareFile(context, "gymapp-backup-", ".json")
    try {
        outputFile.outputStream().buffered().use { output ->
            output.write(bytes)
        }
        return outputFile
    } catch (error: Throwable) {
        outputFile.delete()
        throw error
    }
}

private fun createBackupPdfFile(context: Context, json: String): File {
    // Parse and bound attacker-controlled backup content before allocating a native PDF.
    val reportLines = backupReportLines(context, json)
    val document = PdfDocument()
    return try {
        val pageWidth = 595
        val pageHeight = 842
        val left = 42f
        val top = 48f
        val bottom = 800f
        val lineHeight = 16f
        var pageNumber = 1
        var y = top
        var page = document.startPage(
            PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageNumber).create()
        )

        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.rgb(20, 32, 44)
            textSize = 18f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val headingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.rgb(20, 32, 44)
            textSize = 12f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.rgb(45, 56, 70)
            textSize = 10f
        }

        var pageLimitReached = false

        fun newPage(): Boolean {
            if (pageNumber >= MAX_PDF_PAGES) {
                pageLimitReached = true
                return false
            }
            document.finishPage(page)
            pageNumber += 1
            page = document.startPage(
                PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageNumber).create()
            )
            y = top
            return true
        }

        fun drawWrapped(text: String, paint: Paint = bodyPaint, maxChars: Int = 92) {
            if (pageLimitReached) return
            wrapPdfLine(text, maxChars).forEach { line ->
                if (y > bottom && !newPage()) {
                    return
                }
                page.canvas.drawText(line, left, y, paint)
                y += lineHeight
            }
        }

        reportLines.forEachIndexed { index, line ->
            when {
                index == 0 -> {
                    drawWrapped(line, titlePaint, maxChars = 58)
                    y += 8f
                }
                line.startsWith("## ") -> {
                    y += 6f
                    drawWrapped(line.removePrefix("## "), headingPaint, maxChars = 76)
                    y += 2f
                }
                else -> drawWrapped(line)
            }
        }

        document.finishPage(page)
        val outputFile = createPrivateBackupShareFile(context, "gymapp-report-", ".pdf")
        try {
            outputFile.outputStream().use(document::writeTo)
            outputFile
        } catch (error: Throwable) {
            outputFile.delete()
            throw error
        }
    } finally {
        document.close()
    }
}

private fun createPrivateBackupShareFile(
    context: Context,
    prefix: String,
    suffix: String
): File = synchronized(PRIVATE_SHARE_FILE_LOCK) {
    require(prefix in setOf("gymapp-backup-", "gymapp-report-"))
    require(suffix in setOf(".json", ".pdf"))
    val nowMillis = System.currentTimeMillis()
    val shareDirectory = File(context.cacheDir, "backup-share").apply {
        check(isDirectory || mkdirs()) { "Could not prepare the private share directory" }
    }
    val artifacts = shareDirectory.listFiles()
        .orEmpty()
        .filter(::isPrivateBackupShareArtifact)

    // A chooser may retain the granted URI after returning to GymApp. Delete
    // only expired artifacts; never invalidate a fresh grant to make room.
    artifacts.filter { file ->
        val age = nowMillis - file.lastModified()
        age >= PRIVATE_SHARE_RETENTION_MILLIS
    }.forEach(File::delete)
    val retainedCount = shareDirectory.listFiles()
        .orEmpty()
        .count(::isPrivateBackupShareArtifact)
    check(retainedCount < MAX_RETAINED_PRIVATE_SHARE_FILES) {
        "Too many recent private share files. Try again after older shares expire."
    }
    File.createTempFile(prefix, suffix, shareDirectory)
}

private fun isPrivateBackupShareArtifact(file: File): Boolean =
    file.isFile &&
        (file.name.startsWith("gymapp-backup-") || file.name.startsWith("gymapp-report-")) &&
        file.extension in setOf("pdf", "json")

private fun backupReportLines(context: Context, json: String): List<String> {
    val root = JSONObject(json)
    val diagnosticsOnly = root.optBoolean("diagnostics", false)
    val locale = context.resources.configuration.locales[0]
    val exportedAt = DateFormat.getDateTimeInstance(
        DateFormat.MEDIUM,
        DateFormat.SHORT,
        locale
    )
        .format(Date(root.optLong("exportedAt", System.currentTimeMillis())))
    val exercises = root.optJSONArray("exercises")
    val sessions = root.optJSONArray("sessions")
    val summary = root.optJSONObject("summary")
    val lines = mutableListOf<String>()

    lines += if (diagnosticsOnly) {
        context.getString(R.string.backup_report_diagnostics_title)
    } else {
        context.getString(R.string.backup_report_private_title)
    }
    lines += context.getString(R.string.backup_report_exported, exportedAt)
    lines += context.getString(
        R.string.backup_report_schema,
        root.optInt("schemaVersion", 1)
    )
    if (!diagnosticsOnly) {
        lines += context.getString(R.string.backup_report_private_notice)
    }
    lines += ""
    lines += "## ${context.getString(R.string.backup_report_summary_heading)}"
    lines += context.getString(
        R.string.backup_report_exercises_count,
        summary?.optInt("exerciseCount") ?: (exercises?.length() ?: 0)
    )
    lines += context.getString(
        R.string.backup_report_workouts_count,
        summary?.optInt("sessionCount") ?: (sessions?.length() ?: 0)
    )
    summary?.let {
        lines += context.getString(R.string.backup_report_sets_count, it.optInt("setCount"))
    }

    if (diagnosticsOnly) {
        lines += ""
        lines += context.getString(R.string.backup_report_diagnostics_notice)
        lines += context.getString(R.string.backup_report_diagnostics_exclusions)
        return lines.take(MAX_PDF_REPORT_LINES)
    }

    lines += ""
    lines += "## ${context.getString(R.string.backup_report_exercises_heading)}"
    if (exercises == null || exercises.length() == 0) {
        lines += context.getString(R.string.backup_report_no_exercises)
    } else {
        val exerciseLimit = exercises.length().coerceAtMost(MAX_PDF_EXERCISES)
        for (index in 0 until exerciseLimit) {
            val name = boundedPdfText(
                exercises.optJSONObject(index)?.optString("name").orEmpty()
            )
            if (name.isNotBlank()) {
                lines += "- $name"
            }
        }
        if (exercises.length() > exerciseLimit) {
            lines += context.getString(
                R.string.backup_report_more_exercises,
                exercises.length() - exerciseLimit
            )
        }
    }

    lines += ""
    lines += "## ${context.getString(R.string.backup_report_workouts_heading)}"
    if (sessions == null || sessions.length() == 0) {
        lines += context.getString(R.string.backup_report_no_workouts)
    } else {
        val sessionLimit = sessions.length().coerceAtMost(MAX_PDF_SESSIONS)
        for (sessionIndex in 0 until sessionLimit) {
            if (lines.size >= MAX_PDF_REPORT_LINES) break
            val session = sessions.optJSONObject(sessionIndex) ?: continue
            val date = DateFormat.getDateTimeInstance(
                DateFormat.MEDIUM,
                DateFormat.SHORT,
                locale
            )
                .format(Date(session.optLong("date", 0L)))
            val note = boundedPdfText(session.optString("note")).takeIf { it.isNotBlank() }
            lines += "$date${note?.let { " - $it" }.orEmpty()}"
            val sessionExercises = session.optJSONArray("exercises")
            val sessionExerciseCount = sessionExercises?.length() ?: 0
            val sessionExerciseLimit = sessionExerciseCount.coerceAtMost(
                MAX_PDF_EXERCISES_PER_SESSION
            )
            for (exerciseIndex in 0 until sessionExerciseLimit) {
                if (lines.size >= MAX_PDF_REPORT_LINES) break
                val exercise = sessionExercises?.optJSONObject(exerciseIndex) ?: continue
                val sets = exercise.optJSONArray("sets")
                val setCount = sets?.length() ?: 0
                val setLimit = setCount.coerceAtMost(MAX_PDF_SETS_PER_EXERCISE)
                val setParts = buildList {
                    for (setIndex in 0 until setLimit) {
                        val set = sets?.optJSONObject(setIndex) ?: continue
                        val weight = set.optDouble("weight", 0.0)
                            .toString()
                            .trimEnd('0')
                            .trimEnd('.')
                        add(
                            context.getString(
                                R.string.backup_report_set_value,
                                weight,
                                set.optInt("reps", 0)
                            )
                        )
                    }
                }
                val moreSets = if (setCount > setLimit) {
                    ", … ${context.getString(
                        R.string.backup_report_more_sets,
                        setCount - setLimit
                    )}"
                } else {
                    ""
                }
                lines += "  - ${boundedPdfText(exercise.optString("name"))}: " +
                    setParts.joinToString(", ") + moreSets
            }
            if (sessionExerciseCount > sessionExerciseLimit) {
                lines += "  … ${context.getString(
                    R.string.backup_report_more_exercises,
                    sessionExerciseCount - sessionExerciseLimit
                )}"
            }
            lines += ""
        }
        if (sessions.length() > sessionLimit) {
            lines += context.getString(
                R.string.backup_report_more_workouts,
                sessions.length() - sessionLimit
            )
        }
    }

    if (lines.size >= MAX_PDF_REPORT_LINES) {
        lines[MAX_PDF_REPORT_LINES - 1] =
            context.getString(R.string.backup_report_truncated)
    }
    return lines.take(MAX_PDF_REPORT_LINES)
}

private fun boundedPdfText(value: String): String = buildString {
    for (character in value) {
        if (length >= MAX_PDF_TEXT_CHARS) break
        append(
            if (character.isISOControl() || character == '\n' || character == '\r') ' '
            else character
        )
    }
}.trim()

private fun wrapPdfLine(text: String, maxChars: Int): List<String> {
    require(maxChars > 0)
    val bounded = text.take(MAX_PDF_TEXT_CHARS)
    if (bounded.length <= maxChars) return listOf(bounded)
    val words = bounded.split(" ")
    val lines = mutableListOf<String>()
    var current = ""
    words.forEach { word ->
        val chunks = if (word.length <= maxChars) listOf(word) else word.chunked(maxChars)
        chunks.forEach { chunk ->
            if (current.isBlank()) {
                current = chunk
            } else if (current.length + chunk.length + 1 <= maxChars) {
                current += " $chunk"
            } else {
                lines += current
                current = chunk
            }
        }
    }
    if (current.isNotBlank()) lines += current
    return lines
}

@Composable
private fun ExerciseHistoryBottomSheetContent(
    exerciseName: String,
    history: List<ExerciseHistoryEntry>,
    onEditExerciseMapping: () -> Unit
) {
    val locale = Locale.getDefault()
    val zoneId = ZoneId.systemDefault()
    val monthFormatter = remember(locale) { DateTimeFormatter.ofPattern("LLLL yyyy", locale) }
    val dayFormatter = remember(locale) { DateTimeFormatter.ofPattern("EEEE, d MMMM", locale) }
    val timeFormatter = remember(locale) { DateTimeFormatter.ofPattern("HH:mm", locale) }

    val sessionGroups = remember(history) {
        history
            .groupBy { it.sessionId }
            .values
            .map { entries ->
                ExerciseHistorySessionGroup(
                    sessionId = entries.first().sessionId,
                    sessionDate = entries.first().sessionDate,
                    sets = entries.sortedBy { it.setOrderIndex }
                )
            }
            .sortedByDescending { it.sessionDate }
    }

    val sessionsByMonth = remember(sessionGroups, zoneId) {
        sessionGroups.groupBy { group ->
            YearMonth.from(Instant.ofEpochMilli(group.sessionDate).atZone(zoneId).toLocalDate())
        }.toSortedMap(compareByDescending { it })
    }

    val totalVolume = remember(history) { history.sumOf { it.weight * it.reps } }
    val muscleIntensities = remember(exerciseName) {
        defaultContributionsForExercise(exerciseName)
            .associate { contribution -> contribution.muscleId to contribution.weight.toFloat() }
    }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text(
                text = localizedExerciseName(exerciseName),
                style = MaterialTheme.typography.headlineSmall
            )
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    HistoryStat(
                        label = stringResource(R.string.exercise_history_sessions),
                        value = sessionGroups.size.toString(),
                        modifier = Modifier.weight(1f)
                    )
                    HistoryStat(
                        label = stringResource(R.string.exercise_history_sets),
                        value = history.size.toString(),
                        modifier = Modifier.weight(1f)
                    )
                    HistoryStat(
                        label = stringResource(R.string.exercise_history_volume),
                        value = String.format(locale, "%.0f", totalVolume),
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }

        if (muscleIntensities.isNotEmpty()) {
            item {
                ExerciseMuscleBreakdownCard(
                    exerciseName = exerciseName,
                    muscleIntensities = muscleIntensities,
                    onEditMapping = onEditExerciseMapping
                )
            }
        }

        if (history.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.exercise_history_empty),
                    supporting = stringResource(R.string.exercise_library_empty_supporting)
                )
            }
            return@LazyColumn
        }

        sessionsByMonth.forEach { (month, monthSessions) ->
            item(key = "month_$month") {
                Text(
                    text = month.format(monthFormatter).replaceFirstChar {
                        if (it.isLowerCase()) it.titlecase(locale) else it.toString()
                    },
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            val sessionsByDay = monthSessions.groupBy { group ->
                Instant.ofEpochMilli(group.sessionDate).atZone(zoneId).toLocalDate()
            }.toSortedMap(compareByDescending { it })

            sessionsByDay.forEach { (day, daySessions) ->
                item(key = "day_${month}_$day") {
                    Text(
                        text = day.format(dayFormatter).replaceFirstChar {
                            if (it.isLowerCase()) it.titlecase(locale) else it.toString()
                        },
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                items(
                    items = daySessions,
                    key = { group -> group.sessionId }
                ) { sessionGroup ->
                    val timeText = Instant.ofEpochMilli(sessionGroup.sessionDate)
                        .atZone(zoneId)
                        .toLocalTime()
                        .format(timeFormatter)
                    ExerciseHistorySessionCard(
                        sessionGroup = sessionGroup,
                        timeText = timeText
                    )
                }
            }
        }
    }
}

@Composable
private fun HistoryStat(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = value,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun ExerciseHistorySessionCard(
    sessionGroup: ExerciseHistorySessionGroup,
    timeText: String
) {
    val locale = Locale.getDefault()
    val totalVolume = sessionGroup.sets.sumOf { it.weight * it.reps }
    val maxWeight = sessionGroup.sets.maxOfOrNull { it.weight } ?: 0.0

    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.session_item_title, timeText),
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = stringResource(R.string.progress_weight_value, maxWeight),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.exercise_history_sets_inline, sessionGroup.sets.size),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = stringResource(R.string.exercise_history_volume_inline, String.format(locale, "%.0f", totalVolume)),
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            HorizontalDivider()

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.label_set_short),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelLarge
                )
                Text(
                    text = stringResource(R.string.label_weight_kg),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelLarge
                )
                Text(
                    text = stringResource(R.string.label_reps),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelLarge
                )
            }

            sessionGroup.sets.forEachIndexed { index, set ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = stringResource(R.string.label_set, index + 1),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = formatWeightShort(set.weight),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = set.reps.toString(),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        }
    }
}

private fun formatWeightShort(weight: Double): String {
    return if (weight % 1.0 == 0.0) {
        weight.toInt().toString()
    } else {
        String.format(Locale.getDefault(), "%.1f", weight)
    }
}
