package com.example.gymapp.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.repository.MUSCLE_DEFINITIONS
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.util.localizedMuscleName
import com.example.gymapp.ui.viewmodel.ExerciseMappingUiModel
import com.example.gymapp.ui.viewmodel.MuscleHeatmapUiModel
import com.example.gymapp.ui.viewmodel.MuscleMapPeriod
import com.example.gymapp.ui.viewmodel.MuscleOptionUiModel
import com.example.gymapp.ui.viewmodel.MuscleProgressUiModel
import kotlin.math.min

@Composable
fun MuscleHeatmapCard(
    heatmap: MuscleHeatmapUiModel,
    onPeriodSelected: (MuscleMapPeriod) -> Unit,
    onMuscleSelected: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = stringResource(R.string.muscle_heatmap_title),
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = stringResource(R.string.muscle_heatmap_supporting),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                InfoPill(text = heatmap.periodLabel)
            }

            MusclePeriodSelector(
                heatmap = heatmap,
                onPeriodSelected = onPeriodSelected
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.muscle_heatmap_sets),
                    value = heatmap.totalSets.toString(),
                    modifier = Modifier.weight(1f)
                )
                MetricTile(
                    label = stringResource(R.string.muscle_heatmap_load),
                    value = heatmap.totalLoad.toString(),
                    modifier = Modifier.weight(1f),
                    emphasized = true
                )
            }

            MuscleBodyMap(
                muscles = heatmap.muscles,
                selectedMuscleId = heatmap.selectedMuscleId,
                onMuscleSelected = onMuscleSelected,
                modifier = Modifier.fillMaxWidth()
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                Text(
                    text = stringResource(R.string.muscle_heatmap_front),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = stringResource(R.string.muscle_heatmap_back),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            MuscleLegend()

            if (heatmap.selectedMuscleLabel != null) {
                SelectedMuscleHighlight(heatmap = heatmap)
                SelectedMuscleExercises(heatmap = heatmap)
            }

            if (heatmap.topMuscles.isEmpty()) {
                Text(
                    text = stringResource(R.string.muscle_heatmap_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = stringResource(R.string.muscle_heatmap_top_title),
                        style = MaterialTheme.typography.titleSmall
                    )
                    heatmap.topMuscles.forEach { muscle ->
                        TopMuscleRow(
                            muscle = muscle,
                            selected = muscle.id == heatmap.selectedMuscleId,
                            onClick = { onMuscleSelected(muscle.id) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MusclePeriodSelector(
    heatmap: MuscleHeatmapUiModel,
    onPeriodSelected: (MuscleMapPeriod) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        heatmap.periodOptions.forEach { option ->
            Surface(
                modifier = Modifier
                    .weight(1f)
                    .clickable { onPeriodSelected(option.period) },
                color = if (option.isSelected) {
                    MaterialTheme.colorScheme.primary.copy(alpha = 0.16f)
                } else {
                    MaterialTheme.colorScheme.surface.copy(alpha = 0.72f)
                },
                shape = MaterialTheme.shapes.small,
                border = androidx.compose.foundation.BorderStroke(
                    width = 1.dp,
                    color = if (option.isSelected) {
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.42f)
                    } else {
                        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.62f)
                    }
                )
            ) {
                Text(
                    text = option.label,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp),
                    style = MaterialTheme.typography.labelLarge,
                    color = if (option.isSelected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun MuscleBodyMap(
    muscles: List<MuscleProgressUiModel>,
    selectedMuscleId: String?,
    onMuscleSelected: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    MuscleBodyMapCanvas(
        intensityByMuscle = muscles.associate { muscle -> muscle.id to muscle.intensity },
        selectedMuscleId = selectedMuscleId,
        onMuscleSelected = onMuscleSelected,
        modifier = modifier.height(390.dp)
    )
}

@Composable
fun ExerciseMuscleMap(
    muscleIntensities: Map<String, Float>,
    modifier: Modifier = Modifier
) {
    MuscleBodyMapCanvas(
        intensityByMuscle = muscleIntensities,
        selectedMuscleId = null,
        onMuscleSelected = null,
        modifier = modifier
    )
}

@Composable
fun ExerciseMuscleBreakdownCard(
    exerciseName: String,
    muscleIntensities: Map<String, Float>,
    onEditMapping: (() -> Unit)? = null,
    framed: Boolean = true,
    modifier: Modifier = Modifier
) {
    val languageTag = currentAppLanguageTag()
    val labelById = remember(languageTag) {
        MUSCLE_DEFINITIONS.associate { definition ->
            definition.id to localizedMuscleName(definition.id, languageTag)
        }
    }
    val sortedMuscles = remember(muscleIntensities, labelById) {
        muscleIntensities
            .filterValues { it > 0f }
            .toList()
            .sortedByDescending { it.second }
    }
    val summary = remember(sortedMuscles, labelById) {
        sortedMuscles
            .take(4)
            .joinToString(" - ") { (muscleId, intensity) ->
                "${labelById[muscleId] ?: muscleId} ${(intensity * 100f).toInt()}%"
            }
    }

    @Composable
    fun Content() {
        Column(
            modifier = Modifier.padding(if (framed) 14.dp else 0.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = stringResource(R.string.muscle_heatmap_title),
                        style = MaterialTheme.typography.titleMedium
                    )
                    if (summary.isNotBlank()) {
                        Text(
                            text = summary,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        Text(
                            text = localizedExerciseName(exerciseName),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                if (onEditMapping != null) {
                    OutlinedButton(onClick = onEditMapping) {
                        Text(
                            text = stringResource(R.string.muscle_heatmap_map_action),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }

            ExerciseMuscleMap(
                muscleIntensities = muscleIntensities,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(250.dp)
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                Text(
                    text = stringResource(R.string.muscle_heatmap_front),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = stringResource(R.string.muscle_heatmap_back),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            sortedMuscles.take(6).forEach { (muscleId, intensity) ->
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = labelById[muscleId] ?: muscleId,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    LinearProgressIndicator(
                        progress = { intensity.coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Text(
                        text = "${(intensity * 100f).toInt()}%",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }

    if (framed) {
        AppPanel(
            modifier = modifier.fillMaxWidth(),
            highlighted = true
        ) {
            Content()
        }
    } else {
        Box(modifier = modifier.fillMaxWidth()) {
            Content()
        }
    }
}

@Composable
private fun MuscleBodyMapCanvas(
    intensityByMuscle: Map<String, Float>,
    selectedMuscleId: String?,
    onMuscleSelected: ((String) -> Unit)?,
    modifier: Modifier
) {
    val inactiveColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.52f)
    val outlineColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.62f)
    val lowColor = Color(0xFF3B82F6)
    val mediumColor = Color(0xFF8B5CF6)
    val highColor = Color(0xFFE11D48)
    val peakColor = Color(0xFFF59E0B)
    val selectedOutlineColor = MaterialTheme.colorScheme.primary
    val frontRegions = remember {
        SOURCE_FRONT_MUSCLE_REGIONS.map(::parseSourceRegion)
    }
    val backRegions = remember {
        SOURCE_BACK_MUSCLE_REGIONS.map(::parseSourceRegion)
    }

    val canvasModifier = if (onMuscleSelected != null) {
        modifier.pointerInput(frontRegions, backRegions) {
                detectTapGestures { offset ->
                    findTappedMuscle(
                        offset = offset,
                        canvasWidth = size.width.toFloat(),
                        canvasHeight = size.height.toFloat(),
                        horizontalGap = min(28.dp.toPx(), size.width.toFloat() * 0.12f),
                        frontRegions = frontRegions,
                        backRegions = backRegions
                    )?.let(onMuscleSelected)
                }
            }
    } else {
        modifier
    }

    Canvas(modifier = canvasModifier) {
        val horizontalGap = min(28.dp.toPx(), size.width * 0.12f)
        val availableFigureWidth = ((size.width - horizontalGap) / 2f).coerceAtLeast(24.dp.toPx())
        val availableFigureHeight = size.height - 6.dp.toPx()
        val scale = min(
            availableFigureWidth / SOURCE_BODY_VIEWBOX_WIDTH,
            availableFigureHeight / SOURCE_BODY_VIEWBOX_HEIGHT
        )
        val figureWidth = SOURCE_BODY_VIEWBOX_WIDTH * scale
        val figureHeight = SOURCE_BODY_VIEWBOX_HEIGHT * scale
        val top = (size.height - figureHeight) / 2f
        val frontLeft = size.width * 0.27f - figureWidth / 2f
        val backLeft = size.width * 0.73f - figureWidth / 2f

        drawSourceBody(
            regions = frontRegions,
            viewBoxMinX = SOURCE_FRONT_VIEWBOX_MIN_X,
            left = frontLeft,
            top = top,
            scale = scale,
            intensityByMuscle = intensityByMuscle,
            inactiveColor = inactiveColor,
            outlineColor = outlineColor,
            lowColor = lowColor,
            mediumColor = mediumColor,
            highColor = highColor,
            peakColor = peakColor,
            selectedMuscleId = selectedMuscleId,
            selectedOutlineColor = selectedOutlineColor
        )
        drawSourceBody(
            regions = backRegions,
            viewBoxMinX = SOURCE_BACK_VIEWBOX_MIN_X,
            left = backLeft,
            top = top,
            scale = scale,
            intensityByMuscle = intensityByMuscle,
            inactiveColor = inactiveColor,
            outlineColor = outlineColor,
            lowColor = lowColor,
            mediumColor = mediumColor,
            highColor = highColor,
            peakColor = peakColor,
            selectedMuscleId = selectedMuscleId,
            selectedOutlineColor = selectedOutlineColor
        )
    }
}

@Composable
private fun MuscleLegend() {
    val inactiveColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.56f)
    val lowColor = Color(0xFF3B82F6)
    val mediumColor = Color(0xFF8B5CF6)
    val highColor = Color(0xFFE11D48)
    val peakColor = Color(0xFFF59E0B)

    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = stringResource(R.string.muscle_heatmap_less),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        listOf(0f, 0.25f, 0.5f, 0.75f, 1f).forEach { intensity ->
            Box(
                modifier = Modifier
                    .size(14.dp)
                    .clip(MaterialTheme.shapes.extraSmall)
                    .background(
                        heatColor(
                            intensity = intensity,
                            inactive = inactiveColor,
                            low = lowColor,
                            medium = mediumColor,
                            high = highColor,
                            peak = peakColor
                        )
                    )
            )
        }
        Text(
            text = stringResource(R.string.muscle_heatmap_more),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun SelectedMuscleHighlight(
    heatmap: MuscleHeatmapUiModel
) {
    val muscle = heatmap.muscles.firstOrNull { it.id == heatmap.selectedMuscleId } ?: return
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.42f),
        shape = MaterialTheme.shapes.small,
        border = androidx.compose.foundation.BorderStroke(
            1.dp,
            MaterialTheme.colorScheme.primary.copy(alpha = 0.35f)
        )
    ) {
        Text(
            text = stringResource(
                R.string.muscle_heatmap_highlight_detail,
                muscle.label,
                muscle.load,
                muscle.sets,
                muscle.sessions
            ),
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onPrimaryContainer,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun SelectedMuscleExercises(
    heatmap: MuscleHeatmapUiModel
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = stringResource(
                R.string.muscle_heatmap_selected_title,
                heatmap.selectedMuscleLabel.orEmpty()
            ),
            style = MaterialTheme.typography.titleSmall
        )
        if (heatmap.selectedMuscleExercises.isEmpty()) {
            Text(
                text = stringResource(R.string.muscle_heatmap_selected_empty),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            heatmap.selectedMuscleExercises.forEach { exercise ->
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.78f),
                    shape = MaterialTheme.shapes.small,
                    border = androidx.compose.foundation.BorderStroke(
                        1.dp,
                        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.54f)
                    )
                ) {
                    Row(
                        modifier = Modifier.padding(10.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            Text(
                                text = localizedExerciseName(exercise.exerciseName),
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = stringResource(
                                    R.string.muscle_heatmap_exercise_detail,
                                    exercise.load,
                                    exercise.sets,
                                    exercise.sessions
                                ),
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
private fun UnmappedExercises(
    heatmap: MuscleHeatmapUiModel,
    onEditExerciseMapping: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = stringResource(R.string.muscle_heatmap_unmapped_title),
            style = MaterialTheme.typography.titleSmall
        )
        heatmap.unmappedExercises.forEach { exercise ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = localizedExerciseName(exercise.exerciseName),
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = stringResource(
                            R.string.muscle_heatmap_unmapped_detail,
                            exercise.sets,
                            exercise.sessions
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                FilledTonalButton(onClick = { onEditExerciseMapping(exercise.exerciseName) }) {
                    Text(
                        text = stringResource(R.string.muscle_heatmap_map_action),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

@Composable
private fun ExerciseMappings(
    heatmap: MuscleHeatmapUiModel,
    onEditExerciseMapping: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = stringResource(R.string.muscle_heatmap_mappings_title),
            style = MaterialTheme.typography.titleSmall
        )
        heatmap.exerciseMappings.forEach { exercise ->
            ExerciseMappingRow(
                exercise = exercise,
                onEditExerciseMapping = onEditExerciseMapping
            )
        }
    }
}

@Composable
private fun ExerciseMappingRow(
    exercise: ExerciseMappingUiModel,
    onEditExerciseMapping: (String) -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.72f),
        shape = MaterialTheme.shapes.small,
        border = androidx.compose.foundation.BorderStroke(
            1.dp,
            MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
        )
    ) {
        Row(
            modifier = Modifier.padding(10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = localizedExerciseName(exercise.exerciseName),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = if (exercise.isMapped) {
                        stringResource(
                            R.string.muscle_heatmap_mapping_detail,
                            exercise.muscleLabels,
                            exercise.sets,
                            exercise.sessions
                        )
                    } else {
                        stringResource(
                            R.string.muscle_heatmap_mapping_unmapped_detail,
                            exercise.sets,
                            exercise.sessions
                        )
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            OutlinedButton(onClick = { onEditExerciseMapping(exercise.exerciseName) }) {
                Text(
                    text = stringResource(R.string.muscle_heatmap_map_action),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun ManualMappingEditor(
    exerciseName: String,
    muscles: List<MuscleOptionUiModel>,
    onClose: () -> Unit,
    onSave: (String, List<String>) -> Unit
) {
    var selectedIds by remember(exerciseName, muscles) {
        mutableStateOf(muscles.filter { it.isSelected }.map { it.id }.toSet())
    }

    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f),
        shape = MaterialTheme.shapes.medium,
        border = androidx.compose.foundation.BorderStroke(
            1.dp,
            MaterialTheme.colorScheme.primary.copy(alpha = 0.28f)
        )
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(
                    R.string.muscle_heatmap_manual_title,
                    localizedExerciseName(exerciseName)
                ),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            muscles.chunked(3).forEach { rowMuscles ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    rowMuscles.forEach { muscle ->
                        val selected = muscle.id in selectedIds
                        Surface(
                            modifier = Modifier
                                .weight(1f)
                                .clickable {
                                    selectedIds = if (selected) {
                                        selectedIds - muscle.id
                                    } else {
                                        selectedIds + muscle.id
                                    }
                                },
                            color = if (selected) {
                                MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)
                            } else {
                                MaterialTheme.colorScheme.surface.copy(alpha = 0.7f)
                            },
                            shape = MaterialTheme.shapes.small,
                            border = androidx.compose.foundation.BorderStroke(
                                1.dp,
                                if (selected) {
                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.5f)
                                } else {
                                    MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)
                                }
                            )
                        ) {
                            Text(
                                text = muscle.label,
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 8.dp),
                                style = MaterialTheme.typography.labelMedium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                    repeat(3 - rowMuscles.size) {
                        Box(modifier = Modifier.weight(1f))
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = onClose,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.action_cancel))
                }
                FilledTonalButton(
                    onClick = { onSave(exerciseName, selectedIds.toList()) },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(stringResource(R.string.action_save))
                }
            }
        }
    }
}

@Composable
private fun TopMuscleRow(
    muscle: MuscleProgressUiModel,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val accent = heatColor(
        intensity = muscle.intensity,
        inactive = MaterialTheme.colorScheme.surfaceVariant,
        low = Color(0xFF3B82F6),
        medium = Color(0xFF8B5CF6),
        high = Color(0xFFE11D48),
        peak = Color(0xFFF59E0B)
    )

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.small)
            .background(
                if (selected) {
                    MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
                } else {
                    Color.Transparent
                }
            )
            .clickable(onClick = onClick)
            .padding(8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = muscle.label,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = stringResource(R.string.muscle_heatmap_load_value, muscle.load),
                style = MaterialTheme.typography.labelLarge,
                color = accent,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        LinearProgressIndicator(
            progress = { muscle.intensity },
            modifier = Modifier
                .fillMaxWidth()
                .height(7.dp)
                .clip(MaterialTheme.shapes.small),
            color = accent,
            trackColor = MaterialTheme.colorScheme.surfaceVariant
        )
        Text(
            text = stringResource(
                R.string.muscle_heatmap_muscle_detail,
                muscle.sets,
                muscle.sessions,
                muscle.exercises
            ),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

private fun findTappedMuscle(
    offset: Offset,
    canvasWidth: Float,
    canvasHeight: Float,
    horizontalGap: Float,
    frontRegions: List<RenderedSourceRegion>,
    backRegions: List<RenderedSourceRegion>
): String? {
    val availableFigureWidth = ((canvasWidth - horizontalGap) / 2f).coerceAtLeast(96f)
    val availableFigureHeight = canvasHeight - 6f
    val scale = min(
        availableFigureWidth / SOURCE_BODY_VIEWBOX_WIDTH,
        availableFigureHeight / SOURCE_BODY_VIEWBOX_HEIGHT
    )
    val figureWidth = SOURCE_BODY_VIEWBOX_WIDTH * scale
    val figureHeight = SOURCE_BODY_VIEWBOX_HEIGHT * scale
    val top = (canvasHeight - figureHeight) / 2f
    val frontLeft = canvasWidth * 0.27f - figureWidth / 2f
    val backLeft = canvasWidth * 0.73f - figureWidth / 2f

    return findTappedMuscleInFigure(
        offset = offset,
        regions = frontRegions,
        viewBoxMinX = SOURCE_FRONT_VIEWBOX_MIN_X,
        left = frontLeft,
        top = top,
        figureWidth = figureWidth,
        figureHeight = figureHeight,
        scale = scale
    ) ?: findTappedMuscleInFigure(
        offset = offset,
        regions = backRegions,
        viewBoxMinX = SOURCE_BACK_VIEWBOX_MIN_X,
        left = backLeft,
        top = top,
        figureWidth = figureWidth,
        figureHeight = figureHeight,
        scale = scale
    )
}

private fun findTappedMuscleInFigure(
    offset: Offset,
    regions: List<RenderedSourceRegion>,
    viewBoxMinX: Float,
    left: Float,
    top: Float,
    figureWidth: Float,
    figureHeight: Float,
    scale: Float
): String? {
    if (offset.x < left || offset.x > left + figureWidth || offset.y < top || offset.y > top + figureHeight) {
        return null
    }
    val sourcePoint = Offset(
        x = (offset.x - left) / scale + viewBoxMinX,
        y = (offset.y - top) / scale
    )

    return regions
        .asReversed()
        .firstNotNullOfOrNull { region ->
            val bounds = region.bounds
            val isHit = sourcePoint.x >= bounds.left &&
                sourcePoint.x <= bounds.right &&
                sourcePoint.y >= bounds.top &&
                sourcePoint.y <= bounds.bottom
            if (isHit) muscleIdForSourceRegion(region.source.id) else null
        }
}

private fun DrawScope.drawSourceBody(
    regions: List<RenderedSourceRegion>,
    viewBoxMinX: Float,
    left: Float,
    top: Float,
    scale: Float,
    intensityByMuscle: Map<String, Float>,
    inactiveColor: Color,
    outlineColor: Color,
    lowColor: Color,
    mediumColor: Color,
    highColor: Color,
    peakColor: Color,
    selectedMuscleId: String?,
    selectedOutlineColor: Color
) {
    withTransform({
        translate(left = left - viewBoxMinX * scale, top = top)
        scale(scaleX = scale, scaleY = scale, pivot = Offset.Zero)
    }) {
        regions.forEach { region ->
            val muscleId = muscleIdForSourceRegion(region.source.id)
            val intensity = muscleId?.let { intensityByMuscle[it] } ?: 0f
            val fillColor = if (muscleId == null || intensity <= 0f) {
                inactiveColor
            } else {
                heatColor(
                    intensity = intensity,
                    inactive = inactiveColor,
                    low = lowColor,
                    medium = mediumColor,
                    high = highColor,
                    peak = peakColor
                )
            }
            val selected = muscleId != null && muscleId == selectedMuscleId

            drawPath(
                path = region.path,
                color = if (selected) fillColor.copy(alpha = 0.95f) else fillColor
            )
            drawPath(
                path = region.path,
                color = outlineColor.copy(alpha = 0.5f),
                style = Stroke(width = 0.12f)
            )
            if (selected) {
                drawPath(
                    path = region.path,
                    color = selectedOutlineColor,
                    style = Stroke(width = 0.42f)
                )
            }
        }
    }
}

private fun parseSourceRegion(region: SourceMuscleRegion): RenderedSourceRegion {
    val path = PathParser().parsePathString(region.pathData).toPath()
    return RenderedSourceRegion(
        source = region,
        path = path,
        bounds = path.getBounds()
    )
}

private fun muscleIdForSourceRegion(regionId: String): String? {
    return when {
        regionId.contains("chest") -> "chest"
        regionId.contains("shoulder") || regionId.contains("deltoid") -> "shoulders"
        regionId.contains("biceps") -> "biceps"
        regionId.contains("triceps") -> "triceps"
        regionId.contains("forearm") -> "forearms"
        regionId.contains("obliques") || regionId.contains("serratus") -> "obliques"
        regionId.contains("abs") -> "abs"
        regionId.contains("traps") -> "upperBack"
        regionId.contains("lats") -> "lats"
        regionId == "spine" || regionId.contains("lower-back") -> "lowerBack"
        regionId.contains("gluteus") -> "glutes"
        regionId.contains("quads") -> "quads"
        regionId.contains("adductors") || regionId.contains("hip-flexor") -> "adductors"
        regionId.contains("hamstrings") -> "hamstrings"
        regionId.contains("calves") || regionId.contains("tibialis") -> "calves"
        else -> null
    }
}

private fun heatColor(
    intensity: Float,
    inactive: Color,
    low: Color,
    medium: Color,
    high: Color,
    peak: Color
): Color {
    val value = intensity.coerceIn(0f, 1f)
    return when {
        value <= 0f -> inactive
        value < 0.28f -> lerp(low.copy(alpha = 0.42f), low, value / 0.28f)
        value < 0.58f -> lerp(low, medium, (value - 0.28f) / 0.3f)
        value < 0.86f -> lerp(medium, high, (value - 0.58f) / 0.28f)
        else -> lerp(high, peak, (value - 0.86f) / 0.14f)
    }
}

private data class RenderedSourceRegion(
    val source: SourceMuscleRegion,
    val path: Path,
    val bounds: Rect
)
