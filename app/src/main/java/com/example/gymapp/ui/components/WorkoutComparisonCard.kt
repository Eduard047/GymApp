package com.example.gymapp.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.garmin.ScalarMetricComparison
import com.example.gymapp.garmin.WorkoutComparison
import com.example.gymapp.util.DateTimeUtils
import java.util.Locale
import kotlin.math.abs

private data class ComparisonMetric(
    val label: String,
    val currentValue: String,
    val previousAndDelta: String
)

@Composable
fun WorkoutComparisonCard(
    comparison: WorkoutComparison,
    modifier: Modifier = Modifier
) {
    val wholeNumber: (Double) -> String = { value ->
        String.format(Locale.getDefault(), "%.0f", value)
    }
    val volume: (Double) -> String = { value ->
        String.format(Locale.getDefault(), "%.0f", value)
    }
    val duration: (Double) -> String = { value -> formatDuration(value.toLong()) }
    val bpmUnit = androidx.compose.ui.res.stringResource(R.string.garmin_metric_bpm_unit)
    val heartRate: (Double) -> String = { value ->
        String.format(
            Locale.getDefault(),
            "%d %s",
            value.toInt(),
            bpmUnit
        )
    }

    val metrics = listOfNotNull(
        comparisonMetric(
            label = androidx.compose.ui.res.stringResource(R.string.post_workout_metric_sets),
            comparison = comparison.setCount,
            formatter = wholeNumber
        ),
        comparisonMetric(
            label = androidx.compose.ui.res.stringResource(R.string.label_reps),
            comparison = comparison.totalReps,
            formatter = wholeNumber
        ),
        comparisonMetric(
            label = androidx.compose.ui.res.stringResource(R.string.post_workout_metric_volume),
            comparison = comparison.totalVolume,
            formatter = volume
        ),
        comparison.durationSeconds?.let { metric ->
            comparisonMetric(
                label = androidx.compose.ui.res.stringResource(R.string.garmin_metric_duration),
                comparison = metric,
                formatter = duration
            )
        },
        comparison.garminCalories?.let { metric ->
            comparisonMetric(
                label = androidx.compose.ui.res.stringResource(R.string.garmin_metric_garmin_kcal),
                comparison = metric,
                formatter = wholeNumber
            )
        },
        comparison.gymCalories?.let { metric ->
            comparisonMetric(
                label = androidx.compose.ui.res.stringResource(R.string.garmin_metric_gym_kcal),
                comparison = metric,
                formatter = wholeNumber
            )
        },
        comparison.averageHeartRate?.let { metric ->
            comparisonMetric(
                label = androidx.compose.ui.res.stringResource(R.string.garmin_metric_avg_hr),
                comparison = metric,
                formatter = heartRate
            )
        },
        comparison.maximumHeartRate?.let { metric ->
            comparisonMetric(
                label = androidx.compose.ui.res.stringResource(R.string.garmin_metric_max_hr),
                comparison = metric,
                formatter = heartRate
            )
        }
    )

    AppPanel(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = androidx.compose.ui.res.stringResource(R.string.workout_comparison_eyebrow),
                title = androidx.compose.ui.res.stringResource(R.string.workout_comparison_title),
                supporting = androidx.compose.ui.res.stringResource(
                    R.string.workout_comparison_supporting,
                    comparison.matchedExerciseCount,
                    DateTimeUtils.formatDate(comparison.previousSessionDate)
                )
            )
            metrics.chunked(2).forEach { rowMetrics ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    rowMetrics.forEach { metric ->
                        ComparisonMetricCell(metric = metric, modifier = Modifier.weight(1f))
                    }
                    if (rowMetrics.size == 1) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun comparisonMetric(
    label: String,
    comparison: ScalarMetricComparison,
    formatter: (Double) -> String
): ComparisonMetric {
    val current = formatter(comparison.currentValue)
    val previous = formatter(comparison.previousValue)
    val delta = if (abs(comparison.delta) < 0.000_001) {
        androidx.compose.ui.res.stringResource(R.string.workout_comparison_no_change)
    } else {
        val sign = if (comparison.delta > 0.0) "+" else "−"
        sign + formatter(abs(comparison.delta))
    }
    return ComparisonMetric(
        label = label,
        currentValue = current,
        previousAndDelta = androidx.compose.ui.res.stringResource(
            R.string.workout_comparison_previous_delta,
            previous,
            delta
        )
    )
}

@Composable
private fun ComparisonMetricCell(
    metric: ComparisonMetric,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier = modifier
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.48f), shape)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f), shape)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            text = metric.label.uppercase(Locale.getDefault()),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = metric.currentValue,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = metric.previousAndDelta,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

private fun formatDuration(totalSeconds: Long): String {
    val safeSeconds = totalSeconds.coerceAtLeast(0L)
    val hours = safeSeconds / 3_600L
    val minutes = (safeSeconds % 3_600L) / 60L
    val seconds = safeSeconds % 60L
    return if (hours > 0L) {
        String.format(Locale.ROOT, "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.ROOT, "%d:%02d", minutes, seconds)
    }
}
