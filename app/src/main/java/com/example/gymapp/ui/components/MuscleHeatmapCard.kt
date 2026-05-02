package com.example.gymapp.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.viewmodel.MuscleHeatmapUiModel
import com.example.gymapp.ui.viewmodel.MuscleProgressUiModel
import kotlin.math.min

@Composable
fun MuscleHeatmapCard(
    heatmap: MuscleHeatmapUiModel,
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
                MetricTile(
                    label = stringResource(R.string.muscle_heatmap_mapped),
                    value = stringResource(
                        R.string.muscle_heatmap_mapped_value,
                        heatmap.mappedExerciseCount,
                        heatmap.totalExerciseCount
                    ),
                    modifier = Modifier.weight(1f)
                )
            }

            MuscleBodyMap(
                muscles = heatmap.muscles,
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
                        TopMuscleRow(muscle = muscle)
                    }
                }
            }
        }
    }
}

@Composable
private fun MuscleBodyMap(
    muscles: List<MuscleProgressUiModel>,
    modifier: Modifier = Modifier
) {
    val inactiveColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.52f)
    val outlineColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.62f)
    val lowColor = Color(0xFF3B82F6)
    val mediumColor = Color(0xFF8B5CF6)
    val highColor = Color(0xFFE11D48)
    val peakColor = Color(0xFFF59E0B)
    val intensityByMuscle = muscles.associate { muscle -> muscle.id to muscle.intensity }
    val frontRegions = remember {
        SOURCE_FRONT_MUSCLE_REGIONS.map(::parseSourceRegion)
    }
    val backRegions = remember {
        SOURCE_BACK_MUSCLE_REGIONS.map(::parseSourceRegion)
    }

    Canvas(
        modifier = modifier.height(390.dp)
    ) {
        val horizontalGap = 28.dp.toPx()
        val availableFigureWidth = ((size.width - horizontalGap) / 2f).coerceAtLeast(96.dp.toPx())
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
            peakColor = peakColor
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
            peakColor = peakColor
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
private fun TopMuscleRow(
    muscle: MuscleProgressUiModel,
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
        modifier = modifier.fillMaxWidth(),
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
    peakColor: Color
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

            drawPath(path = region.path, color = fillColor)
            drawPath(
                path = region.path,
                color = outlineColor.copy(alpha = 0.5f),
                style = Stroke(width = 0.12f)
            )
        }
    }
}

private fun parseSourceRegion(region: SourceMuscleRegion): RenderedSourceRegion {
    return RenderedSourceRegion(
        source = region,
        path = PathParser().parsePathString(region.pathData).toPath()
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
    val path: Path
)
