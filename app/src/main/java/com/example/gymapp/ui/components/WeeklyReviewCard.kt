package com.example.gymapp.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.WeeklyReview
import com.example.gymapp.data.repository.WeeklyReviewInsight
import com.example.gymapp.ui.util.localizedExerciseName

@Composable
fun WeeklyReviewCard(history: List<ExerciseHistoryEntry>, target: Int, onOpenWorkout: (Long) -> Unit) {
    var offset by rememberSaveable { mutableIntStateOf(0) }
    var evidence by remember { mutableStateOf<WeeklyReviewInsight?>(null) }
    var expanded by rememberSaveable { mutableStateOf(false) }
    val review = WeeklyReview.build(history, offset)
    AppPanel {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.training_weekly_review), style = MaterialTheme.typography.titleLarge)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { offset = (offset - 1).coerceAtLeast(-520) }, enabled = offset > -520) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, stringResource(R.string.training_previous_week))
                }
                Text(
                    "${review.start.format(java.time.format.DateTimeFormatter.ofPattern("EEE, d MMM"))} – ${review.end.format(java.time.format.DateTimeFormatter.ofPattern("EEE, d MMM"))}",
                    modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center
                )
                IconButton(onClick = { offset = (offset + 1).coerceAtMost(0) }, enabled = offset < 0) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, stringResource(R.string.training_next_week))
                }
            }
            if (review.partial) Text(stringResource(R.string.training_partial_week), style = MaterialTheme.typography.labelMedium)
            Text(stringResource(R.string.training_days_goal, review.trainingDays, target), style = MaterialTheme.typography.titleMedium)
            review.insights.forEach { insight ->
                OutlinedButton(onClick = { evidence = insight }, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Text(localizedExerciseName(insight.current.exerciseName))
                        Text(stringResource(R.string.training_rep_comparison, insight.current.weight, insight.previous.reps, insight.current.reps))
                    }
                }
            }
            if (review.insights.isEmpty()) Text(stringResource(if (review.comparableCount == 0) R.string.training_insufficient_history else R.string.training_unchanged_reps))
            TextButton(onClick = { expanded = !expanded }) { Text(stringResource(R.string.training_week_workouts)) }
            if (expanded) review.sessions.forEach { (id, date) ->
                TextButton(onClick = { onOpenWorkout(id) }) { Text(DateTimeUtils.formatDate(date)) }
            }
        }
    }
    evidence?.let { insight ->
        AlertDialog(onDismissRequest = { evidence = null }, title = { Text(stringResource(R.string.training_comparison)) },
            text = { Column { listOf(insight.previous, insight.current).forEach { entry ->
                TextButton(onClick = { evidence = null; onOpenWorkout(entry.sessionId) }) {
                    Text(DateTimeUtils.formatDate(entry.sessionDate) + " · ${entry.weight} kg × ${entry.reps}")
                }
            } } }, confirmButton = { TextButton(onClick = { evidence = null }) { Text(stringResource(R.string.action_close)) } })
    }
}
