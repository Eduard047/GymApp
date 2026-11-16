package com.example.gymapp.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AccessibilityNew
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.hairlineThickness
import com.example.gymapp.ui.components.groupedSeparatorColor
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.MUSCLE_DEFINITIONS
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.theme.TintedButton
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.util.localizedMuscleName
import com.example.gymapp.util.formattedStringResource
import com.example.gymapp.util.keepShortWordsWithNext

/**
 * One row of the exercise library (grouped list, no per-row controls): 44dp thumbnail, name on up to two
 * lines (a small heart after it when favourite), «muscle · equipment», chevron. Tap opens the detail screen;
 * long press opens the context menu with favourite and the actions that used to sit behind a row «more» button.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun ExerciseLibraryRow(
    exercise: ExerciseEntity,
    isBuiltIn: Boolean,
    muscleIds: Collection<String>?,
    searchMatchReason: ExerciseSearchMatchReason?,
    exerciseMediaOwnerKey: String,
    isFirst: Boolean,
    isLast: Boolean,
    onOpen: () -> Unit,
    onToggleFavorite: () -> Unit,
    onEditMuscles: () -> Unit,
    onEditWeightSteps: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit
) {
    var menuExpanded by remember(exercise.id) { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val displayName = localizedExerciseName(exercise.name)
    val subtitle = exerciseSubtitle(exercise.name, muscleIds)
    val radius = 12.dp
    val shape = RoundedCornerShape(
        topStart = if (isFirst) radius else 0.dp,
        topEnd = if (isFirst) radius else 0.dp,
        bottomStart = if (isLast) radius else 0.dp,
        bottomEnd = if (isLast) radius else 0.dp
    )
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MaterialTheme.colorScheme.surface)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 60.dp)
                .combinedClickable(
                    onClickLabel = displayName,
                    onClick = onOpen,
                    onLongClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        menuExpanded = true
                    }
                )
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ExerciseMediaPreview(
                exerciseId = exercise.id,
                exerciseName = exercise.name,
                ownerKey = exerciseMediaOwnerKey,
                width = 44.dp,
                height = 44.dp,
                playBadgeSize = 16.dp,
                cornerRadius = 10.dp,
                editable = false,
                interactive = false
            )
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        text = keepShortWordsWithNext(displayName),
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    if (exercise.isFavorite) {
                        Icon(
                            imageVector = Icons.Default.Favorite,
                            contentDescription = stringResource(R.string.exercise_filter_favorites),
                            modifier = Modifier.size(12.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                if (subtitle != null) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                if (searchMatchReason != null) {
                    Text(
                        text = localizedExerciseSearchMatchReason(searchMatchReason),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
            )
        }
        if (!isLast) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 72.dp)
                    .fillMaxWidth()
                    .height(hairlineThickness())
                    .background(groupedSeparatorColor())
            )
        }
        Box(modifier = Modifier.align(Alignment.TopStart).padding(start = 72.dp)) {
            DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                DropdownMenuItem(
                    text = {
                        Text(
                            stringResource(
                                if (exercise.isFavorite) R.string.exercise_detail_favorite_remove
                                else R.string.exercise_detail_favorite_add
                            )
                        )
                    },
                    onClick = { menuExpanded = false; onToggleFavorite() },
                    leadingIcon = {
                        Icon(
                            if (exercise.isFavorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                            contentDescription = null
                        )
                    }
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.exercise_card_history)) },
                    onClick = { menuExpanded = false; onOpen() },
                    leadingIcon = { Icon(Icons.Default.History, contentDescription = null) }
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.exercise_card_muscle_groups)) },
                    onClick = { menuExpanded = false; onEditMuscles() },
                    leadingIcon = { Icon(Icons.Default.AccessibilityNew, contentDescription = null) }
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.exercise_load_profile_action)) },
                    onClick = { menuExpanded = false; onEditWeightSteps() },
                    leadingIcon = { Icon(Icons.Default.FormatListNumbered, contentDescription = null) }
                )
                if (!isBuiltIn) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.exercise_detail_edit)) },
                        onClick = { menuExpanded = false; onRename() },
                        leadingIcon = { Icon(Icons.Default.Edit, contentDescription = null) }
                    )
                }
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.action_delete), color = MaterialTheme.colorScheme.error) },
                    onClick = { menuExpanded = false; onDelete() },
                    leadingIcon = {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = formattedStringResource(R.string.cd_delete_exercise_named, displayName),
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                )
            }
        }
    }
}

/**
 * Library search: one 36dp search field with a single filter button beside it. The button opens a menu
 * with «Favorites», the body categories, the muscles and the sort order. Favorites, a category and a
 * muscle combine; the active filters show as one removable token under the field.
 */
@Composable
internal fun ExerciseLibrarySearchAndFilter(
    query: String,
    onQueryChange: (String) -> Unit,
    bodyFilter: ExerciseBodyFilter,
    muscleFilter: String?,
    favoritesOnly: Boolean,
    onFilterChange: (favoritesOnly: Boolean, body: ExerciseBodyFilter, muscle: String?) -> Unit,
    sortMode: ExerciseSortMode,
    onSortModeChange: (ExerciseSortMode) -> Unit
) {
    val languageTag = currentAppLanguageTag()
    var menuOpen by remember { mutableStateOf(false) }
    val favoritesLabel = stringResource(R.string.exercise_filter_favorites)
    val bodyLabel = if (bodyFilter != ExerciseBodyFilter.All) stringResource(bodyFilterLabel(bodyFilter)) else null
    val muscleLabel = muscleFilter?.let { localizedMuscleName(it, languageTag) }
    val tokenLabel: String? = listOfNotNull(
        favoritesLabel.takeIf { favoritesOnly },
        bodyLabel,
        muscleLabel
    ).takeIf { it.isNotEmpty() }?.joinToString(" · ")
    val hasCustomSort = sortMode != ExerciseSortMode.Name
    val clearFilter = { onFilterChange(false, ExerciseBodyFilter.All, null) }

    Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            ExerciseLibrarySearchField(
                value = query,
                onValueChange = onQueryChange,
                placeholder = stringResource(R.string.exercise_search_label),
                clearDescription = stringResource(R.string.exercise_search_clear),
                modifier = Modifier.weight(1f)
            )
            Box {
                IconButton(
                    onClick = { menuOpen = true },
                    modifier = Modifier
                        .size(48.dp)
                        .semantics { selected = tokenLabel != null || hasCustomSort }
                ) {
                    Icon(
                        imageVector = Icons.Default.FilterList,
                        contentDescription = stringResource(R.string.exercise_filter_button),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
                if (hasCustomSort) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(top = 10.dp, end = 10.dp)
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.primary)
                            .clearAndSetSemantics { }
                    )
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.exercise_filter_favorites)) },
                        onClick = {
                            onFilterChange(!favoritesOnly, bodyFilter, muscleFilter)
                            menuOpen = false
                        },
                        leadingIcon = {
                            Icon(
                                if (favoritesOnly) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                                contentDescription = null
                            )
                        },
                        trailingIcon = if (favoritesOnly) {
                            { Icon(Icons.Default.Check, contentDescription = null) }
                        } else {
                            null
                        },
                        modifier = Modifier.semantics { selected = favoritesOnly }
                    )
                    HorizontalDivider()
                    LibraryFilterMenuHeader(stringResource(R.string.exercise_filter_category))
                    ExerciseBodyFilter.entries.filter { it != ExerciseBodyFilter.All }.forEach { filter ->
                        LibraryFilterMenuChoice(
                            label = stringResource(bodyFilterLabel(filter)),
                            selected = bodyFilter == filter,
                            onClick = {
                                onFilterChange(favoritesOnly, if (bodyFilter == filter) ExerciseBodyFilter.All else filter, muscleFilter)
                                menuOpen = false
                            }
                        )
                    }
                    HorizontalDivider()
                    LibraryFilterMenuHeader(stringResource(R.string.exercise_detail_muscles_header))
                    MUSCLE_DEFINITIONS.forEach { muscle ->
                        LibraryFilterMenuChoice(
                            label = localizedMuscleName(muscle.id, languageTag),
                            selected = muscleFilter == muscle.id,
                            onClick = {
                                onFilterChange(favoritesOnly, bodyFilter, if (muscleFilter == muscle.id) null else muscle.id)
                                menuOpen = false
                            }
                        )
                    }
                    HorizontalDivider()
                    LibraryFilterMenuHeader(stringResource(R.string.exercise_filter_sort))
                    ExerciseSortMode.entries.forEach { mode ->
                        val label = when (mode) {
                            ExerciseSortMode.Name -> R.string.exercise_sort_name
                            ExerciseSortMode.MostFrequent -> R.string.exercise_sort_most_frequent
                            ExerciseSortMode.LeastFrequent -> R.string.exercise_sort_least_frequent
                        }
                        LibraryFilterMenuChoice(
                            label = stringResource(label),
                            selected = sortMode == mode,
                            onClick = {
                                onSortModeChange(mode)
                                menuOpen = false
                            }
                        )
                    }
                }
            }
        }
        if (tokenLabel != null) {
            TintedButton(
                onClick = clearFilter,
                modifier = Modifier.heightIn(min = 32.dp).height(32.dp),
                contentPadding = PaddingValues(start = 14.dp, end = 10.dp)
            ) {
                Text(
                    text = tokenLabel,
                    style = MaterialTheme.typography.labelLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = formattedStringResource(R.string.exercise_filter_remove_named, tokenLabel),
                    modifier = Modifier.padding(start = 6.dp).size(14.dp)
                )
            }
        }
    }
}

private fun bodyFilterLabel(filter: ExerciseBodyFilter): Int = when (filter) {
    ExerciseBodyFilter.All -> R.string.exercise_filter_all
    ExerciseBodyFilter.Upper -> R.string.exercise_filter_upper
    ExerciseBodyFilter.Lower -> R.string.exercise_filter_lower
    ExerciseBodyFilter.Core -> R.string.exercise_filter_core
}

@Composable
private fun LibraryFilterMenuHeader(text: String) {
    Text(
        text = text,
        modifier = Modifier
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .semantics { heading() },
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun LibraryFilterMenuChoice(label: String, selected: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(label) },
        onClick = onClick,
        trailingIcon = if (selected) {
            { Icon(Icons.Default.Check, contentDescription = null) }
        } else {
            null
        },
        modifier = Modifier.semantics { this.selected = selected }
    )
}

/** Compact search field: 36dp, radius 10, tonal fill, leading magnifier, trailing clear button while not empty. */
@Composable
private fun ExerciseLibrarySearchField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    clearDescription: String,
    modifier: Modifier = Modifier
) {
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier
            .height(36.dp)
            .semantics { contentDescription = placeholder },
        singleLine = true,
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        decorationBox = { inner ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(36.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Search,
                    contentDescription = null,
                    modifier = Modifier.padding(start = 8.dp, end = 6.dp).size(18.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                    if (value.isEmpty()) {
                        Text(
                            text = placeholder,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    inner()
                }
                if (value.isNotEmpty()) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clickable { onValueChange("") },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = clearDescription,
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    )
}
