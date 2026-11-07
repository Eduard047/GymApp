package com.example.gymapp.ui.components

import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.theme.accentMarkColor
import com.example.gymapp.ui.viewmodel.ExerciseProgressSpotlightUiModel
import com.example.gymapp.ui.viewmodel.ExerciseTrendChartPointUiModel
import com.example.gymapp.ui.viewmodel.ExerciseTrendChartUiModel
import com.example.gymapp.util.formattedStringResource
import com.example.gymapp.util.formatVolumeTotal
import com.example.gymapp.util.keepNumberWithUnit
import com.example.gymapp.util.formatWeightDisplay
import com.example.gymapp.util.formattedPluralStringResource

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
                color = HeroTone.title
            )
            Text(
                text = spotlight.subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = HeroTone.supporting
            )

            Row(
                modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
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
                    value = spotlight.latestVolumeLabel
                        .takeIf { label -> label.any(Char::isDigit) }
                        ?.let { label -> keepNumberWithUnit(formattedStringResource(R.string.today_history_volume_kg, label)) }
                        ?: spotlight.latestVolumeLabel,
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                InfoPill(
                    text = spotlight.weightDeltaLabel,
                    onHero = true
                )
                if (
                    spotlight.volumeDeltaLabel.isNotBlank() &&
                    spotlight.volumeDeltaLabel != spotlight.weightDeltaLabel
                ) {
                    InfoPill(
                        text = spotlight.volumeDeltaLabel,
                        onHero = true
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
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
                text = formattedStringResource(
                    R.string.progress_visual_trends_subtitle,
                    formattedPluralStringResource(
                        R.plurals.progress_sessions_count,
                        chart.points.size,
                        chart.points.size
                    )
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
                    WeightTrendChart(
                        points = chart.points,
                        description = trendChartDescription(
                            title = stringResource(R.string.progress_chart_max_weight),
                            trend = chart.weightTrendLabel,
                            range = trendChartRangeSummary(chart.points, ExerciseTrendChartPointUiModel::maxWeight, ::formatWeightDisplay)
                        )
                    )
                }

                ChartSection(
                    title = stringResource(R.string.progress_chart_volume),
                    summary = chart.volumeTrendLabel
                ) {
                    VolumeTrendChart(
                        points = chart.points,
                        description = trendChartDescription(
                            title = stringResource(R.string.progress_chart_volume),
                            trend = chart.volumeTrendLabel,
                            range = trendChartRangeSummary(chart.points, ExerciseTrendChartPointUiModel::totalVolume, ::formatVolumeTotal)
                        )
                    )
                }

                if (chart.oneRepMaxPoints.isNotEmpty()) {
                    ChartSection(
                        title = stringResource(R.string.progress_e1rm_chart_title),
                        summary = chart.oneRepMaxTrendLabel
                    ) {
                        WeightTrendChart(
                            points = chart.oneRepMaxPoints,
                            description = trendChartDescription(
                                title = stringResource(R.string.progress_e1rm_chart_title),
                                trend = chart.oneRepMaxTrendLabel,
                                range = trendChartRangeSummary(
                                    chart.oneRepMaxPoints,
                                    { point -> point.estimatedOneRepMax ?: 0.0 },
                                    ::formatWeightDisplay
                                )
                            ),
                            ratio = ExerciseTrendChartPointUiModel::oneRepMaxRatio
                        )
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    MetricTile(
                        label = stringResource(R.string.progress_peak_weight),
                        value = chart.peakWeightLabel,
                        modifier = Modifier.weight(1f)
                    )
                    MetricTile(
                        label = stringResource(R.string.progress_average_volume),
                        value = chart.averageVolumeLabel
                            .takeIf { label -> label.any(Char::isDigit) }
                            ?.let { label -> keepNumberWithUnit(formattedStringResource(R.string.today_history_volume_kg, label)) }
                            ?: chart.averageVolumeLabel,
                        modifier = Modifier.weight(1f)
                    )
                }
                chart.bestOneRepMaxLabel?.let { bestOneRepMax ->
                    Row(
                        modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        MetricTile(
                            label = stringResource(R.string.progress_e1rm_best),
                            value = bestOneRepMax,
                            modifier = Modifier.weight(1f)
                        )
                        Spacer(modifier = Modifier.weight(1f))
                    }
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
private fun WeightTrendChart(
    points: List<ExerciseTrendChartPointUiModel>,
    description: String,
    ratio: (ExerciseTrendChartPointUiModel) -> Float = ExerciseTrendChartPointUiModel::weightRatio
) {
    val lineColor = accentMarkColor()
    val fillColor = lineColor.copy(alpha = 0.12f)
    val guideColor = MaterialTheme.colorScheme.outlineVariant
    val latestPointColor = MaterialTheme.colorScheme.tertiary

    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp)
            .semantics { contentDescription = description }
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
            val y = baseline - (ratio(point) * (chartHeight - 12.dp.toPx()))
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
            val y = baseline - (ratio(point) * (chartHeight - 12.dp.toPx()))
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
private fun VolumeTrendChart(points: List<ExerciseTrendChartPointUiModel>, description: String) {
    val barColor = MaterialTheme.colorScheme.secondary
    val latestBarColor = MaterialTheme.colorScheme.tertiary
    val guideColor = MaterialTheme.colorScheme.outlineVariant

    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp)
            .semantics { contentDescription = description }
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

/** First, latest and best value of a trend series, or null when there are no points. */
internal data class TrendChartRange(val first: Double, val latest: Double, val best: Double)

internal fun trendChartRange(
    points: List<ExerciseTrendChartPointUiModel>,
    value: (ExerciseTrendChartPointUiModel) -> Double
): TrendChartRange? {
    if (points.isEmpty()) return null
    val values = points.map(value)
    return TrendChartRange(first = values.first(), latest = values.last(), best = values.max())
}

/** "First session 60 kg, latest 70 kg, best 72.5 kg" for TalkBack; null when there is no data. */
@Composable
private fun trendChartRangeSummary(
    points: List<ExerciseTrendChartPointUiModel>,
    value: (ExerciseTrendChartPointUiModel) -> Double,
    format: (Double) -> String
): String? {
    val range = trendChartRange(points, value) ?: return null
    return formattedStringResource(
        R.string.progress_chart_a11y_range,
        formattedStringResource(R.string.today_history_volume_kg, format(range.first)),
        formattedStringResource(R.string.today_history_volume_kg, format(range.latest)),
        formattedStringResource(R.string.today_history_volume_kg, format(range.best))
    )
}

/** Chart title, trend and range joined into one TalkBack sentence list; blank parts are skipped. */
internal fun trendChartDescription(title: String, trend: String, range: String?): String =
    listOf(title, trend, range.orEmpty())
        .map(String::trim)
        .filter(String::isNotEmpty)
        .joinToString(". ")
