package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingProgramStore

@Composable
internal fun TrainingProgramCard(owner: String, sessions: List<WorkoutSessionSummary>, profile: TrainingProfile, onPrepare: () -> Unit) {
    val context = LocalContext.current
    val store = remember(owner, context) { TrainingProgramStore(context, owner) }
    var generation by remember(owner) { mutableIntStateOf(0) }
    var operationFailed by remember(owner) { mutableStateOf(false) }
    var confirmation by remember(owner) { mutableStateOf<Pair<String, Long>?>(null) }
    val program = remember(owner, generation) { store.load() }
    val failed = store.hasError || operationFailed
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    LaunchedEffect(program?.id, program?.status, failed) { listState.scrollToItem(0) }
    fun refresh(ok: Boolean) { operationFailed = !ok; generation++ }

    confirmation?.let { intent ->
        val replace = intent.first == "replace"
        AlertDialog(
            onDismissRequest = { confirmation = null },
            title = { Text(stringResource(if (replace) R.string.training_program_new_title else R.string.training_program_finish_title)) },
            text = { Text(stringResource(if (replace) R.string.training_program_new_message else R.string.training_program_finish_message)) },
            confirmButton = { TextButton(onClick = {
                confirmation = null
                refresh(if (store.load()?.id != intent.second) false else if (replace)
                    store.create(profile.workoutsPerWeek, profile.goal.name, replacingId = intent.second)
                else store.updateStatus("completed"))
            }) { Text(stringResource(if (replace) R.string.training_program_create else R.string.training_program_finish)) } },
            dismissButton = { TextButton(onClick = { confirmation = null }) { Text(stringResource(R.string.action_cancel)) } }
        )
    }

    LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)) {
        if (failed) item {
            AppPanel(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.training_program_save_error), color = MaterialTheme.colorScheme.error)
                    OutlinedButton(onClick = { refresh(store.reload()) }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                        Text(stringResource(R.string.training_program_reload))
                    }
                }
            }
        }
        item {
            AppPanel(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(R.string.training_four_week_program), style = MaterialTheme.typography.titleLarge)
                    if (program == null) {
                        Text(stringResource(R.string.training_program_intro))
                        Button(onClick = { refresh(store.create(profile.workoutsPerWeek, profile.goal.name)) },
                            Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = !failed) {
                            Text(stringResource(R.string.training_program_create))
                        }
                    } else {
                        val goal = when (program.goal) {
                            "AestheticFatLoss" -> R.string.training_goal_aesthetic_fat_loss
                            "MuscleGain" -> R.string.training_goal_muscle_gain
                            "Strength" -> R.string.training_goal_strength
                            else -> R.string.training_goal_balanced
                        }
                        val linked = program.slots.count { it.sessionId != null }
                        val next = store.next(program)
                        Text(stringResource(goal), style = MaterialTheme.typography.bodyLarge)
                        Text(stringResource(R.string.training_program_count, linked, program.slots.size))
                        LinearProgressIndicator(progress = { linked.toFloat() / program.slots.size }, modifier = Modifier.fillMaxWidth())
                        Text(when (program.status) {
                            "paused" -> stringResource(R.string.training_program_paused)
                            "completed" -> stringResource(R.string.training_program_finished)
                            else -> next?.let { stringResource(R.string.training_program_next, DateTimeUtils.formatDate(it.date)) }
                                ?: stringResource(R.string.training_program_all_linked)
                        })
                        when (program.status) {
                            "active" -> if (next != null) {
                                Button(onClick = onPrepare, Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = !failed) {
                                    Text(stringResource(R.string.training_program_prepare))
                                }
                                store.matchingSession(program, next, sessions)?.let { session ->
                                    OutlinedButton(onClick = { refresh(store.link(session.session.id, sessions)) },
                                        Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = !failed) {
                                        Text(stringResource(R.string.training_program_link) + ": " + DateTimeUtils.formatDate(session.session.date))
                                    }
                                }
                            }
                            "paused" -> Button(onClick = { refresh(store.updateStatus("active")) },
                                Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = !failed) {
                                Text(stringResource(R.string.training_program_resume))
                            }
                            "completed" -> {
                                Button(onClick = { confirmation = "replace" to program.id }, Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = !failed) {
                                    Text(stringResource(R.string.training_program_new))
                                }
                                if (next != null) OutlinedButton(onClick = { refresh(store.reopen()) },
                                    Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = !failed) {
                                    Text(stringResource(R.string.training_program_reopen))
                                }
                            }
                        }
                        if (program.status != "completed") {
                            var expanded by rememberSaveable(program.id) { mutableStateOf(false) }
                            TextButton(onClick = { expanded = !expanded }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                                Text(stringResource(if (expanded) R.string.training_program_options_hide else R.string.training_program_options))
                            }
                            if (expanded) {
                                if (program.status == "active") {
                                    OutlinedButton(onClick = { refresh(store.rescheduleNext()) }, Modifier.fillMaxWidth(), enabled = !failed) {
                                        Text(stringResource(R.string.training_program_move))
                                    }
                                    TextButton(onClick = { refresh(store.updateStatus("paused")) }, Modifier.fillMaxWidth(), enabled = !failed) {
                                        Text(stringResource(R.string.training_program_pause))
                                    }
                                }
                                TextButton(onClick = { confirmation = "finish" to program.id }, Modifier.fillMaxWidth(), enabled = !failed) {
                                    Text(stringResource(R.string.training_program_finish))
                                }
                            }
                        }
                    }
                }
            }
        }
        if (program != null) items(4) { week ->
            var expanded by rememberSaveable(program.id, week) { mutableStateOf(false) }
            val slots = program.slots.drop(week * program.days).take(program.days)
            AppPanel(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { expanded = !expanded }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                        Text(stringResource(R.string.training_program_week, week + 1, slots.count { it.sessionId != null }, slots.size))
                    }
                    if (expanded) slots.forEach { slot ->
                        Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp)) {
                            Text(DateTimeUtils.formatDate(slot.date), style = MaterialTheme.typography.bodyLarge)
                            Text(stringResource(if (slot.sessionId != null) R.string.training_program_done else R.string.training_program_planned),
                                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}
