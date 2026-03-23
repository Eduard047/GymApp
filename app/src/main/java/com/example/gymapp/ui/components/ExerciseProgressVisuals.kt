package com.example.gymapp.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.viewmodel.ExerciseProgressSpotlightUiModel
import com.example.gymapp.ui.viewmodel.ExerciseTrendChartPointUiModel
import com.example.gymapp.ui.viewmodel.ExerciseTrendChartUiModel

@Composable
fun ExerciseSpotlightCard(
    spotlight: ExerciseProgressSpotlightUiModel,
    modifier: Modifier = Modifier
) {
    HeroPanel(modifier = modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                text = spotlight.title,
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onPrimary
            )
            Text(
                text = spotlight.subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.88f)
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = spotlight.latestWeightCaption,
                    value = spotlight.latestWeightLabel,
                    modifier = Modifier.weight(1f),
                    emphasized = true,
                    onHero = true
                )
                MetricTile(
                    label = spotlight.latestVolumeCaption,
                    value = spotlight.latestVolumeLabel,
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                InfoPill(
                    text = spotlight.weightDeltaLabel,
                    accent = MaterialTheme.colorScheme.onPrimary
                )
                if (
                    spotlight.volumeDeltaLabel.isNotBlank() &&
                    spotlight.volumeDeltaLabel != spotlight.weightDeltaLabel
                ) {
                    InfoPill(
                        text = spotlight.volumeDeltaLabel,
                        accent = MaterialTheme.colorScheme.onPrimary
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.progress_spotlight_all_time_best),
                    value = spotlight.allTimeBestLabel,
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
                MetricTile(
                    label = stringResource(R.string.progress_spotlight_consistency),
                    value = spotlight.consistencyLabel,
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }
        }
    }
}

@Composable
fun ExerciseTrendChartsCard(
    chart: ExerciseTrendChartUiModel,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Text(
                text = stringResource(R.string.progress_visual_trends_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(
                    R.string.progress_visual_trends_subtitle,
                    chart.points.size
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (chart.points.isEmpty()) {
                Text(
                    text = stringResource(R.string.chart_no_data),
                    style = MaterialTheme.typography.bodyMedium
                )
            } else {
                ChartSection(
                    title = stringResource(R.string.progress_chart_max_weight),
                    summary = chart.weightTrendLabel
                ) {
                    WeightTrendChart(points = chart.points)
                }

                ChartSection(
                    title = stringResource(R.string.progress_chart_volume),
                    summary = chart.volumeTrendLabel
                ) {
                    VolumeTrendChart(points = chart.points)
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    MetricTile(
                        label = stringResource(R.string.progress_peak_weight),
                        value = chart.peakWeightLabel,
                        modifier = Modifier.weight(1f)
                    )
                    MetricTile(
                        label = stringResource(R.string.progress_average_volume),
                        value = chart.averageVolumeLabel,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun ChartSection(
    title: String,
    summary: String,
    content: @Composable () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall
        )
        Text(
            text = summary,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        content()
    }
}

@Composable
private fun WeightTrendChart(points: List<ExerciseTrendChartPointUiModel>) {
    val lineColor = MaterialTheme.colorScheme.primary
    val fillColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)
    val guideColor = MaterialTheme.colorScheme.outlineVariant
    val latestPointColor = MaterialTheme.colorScheme.tertiary

    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp)
    ) {
        if (points.isEmpty()) return@Canvas

        val stepX = if (points.size == 1) 0f else size.width / (points.size - 1)
        val chartHeight = size.height - 28.dp.toPx()
        val baseline = chartHeight

        repeat(3) { guide ->
            val y = (chartHeight / 2f) * guide
            drawLine(
                color = guideColor,
                start = Offset(0f, y),
                end = Offset(size.width, y),
                strokeWidth = 1.dp.toPx()
            )
        }

        val path = Path()
        val fillPath = Path()

        points.forEachIndexed { index, point ->
            val x = stepX * index
            val y = baseline - (point.weightRatio * (chartHeight - 12.dp.toPx()))
            if (index == 0) {
                path.moveTo(x, y)
                fillPath.moveTo(x, baseline)
                fillPath.lineTo(x, y)
            } else {
                path.lineTo(x, y)
                fillPath.lineTo(x, y)
            }
        }

        fillPath.lineTo(size.width, baseline)
        fillPath.close()

        drawPath(path = fillPath, color = fillColor)
        drawPath(
            path = path,
            color = lineColor,
            style = Stroke(width = 3.dp.toPx(), cap = StrokeCap.Round)
        )

        points.forEachIndexed { index, point ->
            val x = stepX * index
            val y = baseline - (point.weightRatio * (chartHeight - 12.dp.toPx()))
            drawCircle(
                color = if (point.isLatest) latestPointColor else lineColor,
                radius = if (point.isLatest) 6.dp.toPx() else 4.dp.toPx(),
                center = Offset(x, y)
            )
        }
    }

    ChartLabels(points = points)
}

@Composable
private fun VolumeTrendChart(points: List<ExerciseTrendChartPointUiModel>) {
    val barColor = MaterialTheme.colorScheme.secondary
    val latestBarColor = MaterialTheme.colorScheme.tertiary
    val guideColor = MaterialTheme.colorScheme.outlineVariant

    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp)
    ) {
        if (points.isEmpty()) return@Canvas

        val chartHeight = size.height - 28.dp.toPx()
        val spacing = 10.dp.toPx()
        val barWidth = ((size.width - spacing * (points.size - 1)) / points.size).coerceAtLeast(12.dp.toPx())

        repeat(3) { guide ->
            val y = (chartHeight / 2f) * guide
            drawLine(
                color = guideColor,
                start = Offset(0f, y),
                end = Offset(size.width, y),
                strokeWidth = 1.dp.toPx()
            )
        }

        points.forEachIndexed { index, point ->
            val left = index * (barWidth + spacing)
            val top = chartHeight - (point.volumeRatio * (chartHeight - 8.dp.toPx()))
            drawRoundRect(
                color = if (point.isLatest) latestBarColor else barColor,
                topLeft = Offset(left, top),
                size = Size(barWidth, chartHeight - top),
                cornerRadius = CornerRadius(8.dp.toPx(), 8.dp.toPx())
            )
        }
    }

    ChartLabels(points = points)
}

@Composable
private fun ChartLabels(points: List<ExerciseTrendChartPointUiModel>) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        points.forEach { point ->
            Text(
                text = point.shortLabel,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}
