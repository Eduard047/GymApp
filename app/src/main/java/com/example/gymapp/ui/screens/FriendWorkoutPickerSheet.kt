package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.ScreenHeader
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.util.DateTimeUtils

internal const val MAX_FRIEND_WORKOUT_PICKER_SESSIONS = 100

internal fun friendWorkoutPickerSessions(
    sessions: List<WorkoutSessionSummary>
): List<WorkoutSessionSummary> = sessions.asSequence()
    .filter { it.session.id > 0 && it.exerciseCount > 0 && it.setCount > 0 }
    .sortedWith(
        compareByDescending<WorkoutSessionSummary> { it.session.date }
            .thenByDescending { it.session.id }
    )
    .take(MAX_FRIEND_WORKOUT_PICKER_SESSIONS)
    .toList()

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FriendWorkoutPickerSheet(
    friendName: String,
    sessions: List<WorkoutSessionSummary>,
    inFlightSessionId: Long?,
    onSelect: (WorkoutSessionSummary) -> Unit,
    onDismiss: () -> Unit
) {
    val availableSessions = remember(sessions) { friendWorkoutPickerSessions(sessions) }
    val isBusy = inFlightSessionId != null
    ModalBottomSheet(
        onDismissRequest = { if (!isBusy) onDismiss() },
        containerColor = MaterialTheme.colorScheme.background,
        contentColor = MaterialTheme.colorScheme.onBackground,
        modifier = Modifier.testTag("friend_workout_picker")
    ) {
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding(),
            contentPadding = PaddingValues(
                start = GymSpacing.ScreenHorizontal,
                top = GymSpacing.XSmall,
                end = GymSpacing.ScreenHorizontal,
                bottom = GymSpacing.ScreenBottom
            ),
            verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
        ) {
            item {
                ScreenHeader(
                    title = stringResource(R.string.friend_workout_picker_title, friendName),
                    supporting = stringResource(R.string.friend_workout_picker_supporting)
                )
            }

            if (availableSessions.isEmpty()) {
                item {
                    EmptyStatePanel(
                        title = stringResource(R.string.empty_workouts),
                        supporting = stringResource(R.string.friend_workout_picker_empty_supporting)
                    )
                }
            } else {
                items(
                    items = availableSessions,
                    key = { it.session.id }
                ) { session ->
                    val isSessionBusy = inFlightSessionId == session.session.id
                    AppPanel(
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("friend_workout_picker_session_${session.session.id}")
                    ) {
                        Column(
                            modifier = Modifier.padding(GymSpacing.Large),
                            verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(GymSpacing.Small)
                            ) {
                                Text(
                                    text = DateTimeUtils.formatDate(session.session.date),
                                    style = MaterialTheme.typography.titleMedium,
                                    modifier = Modifier.weight(1f),
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                                InfoPill(
                                    text = stringResource(R.string.stats_sets, session.setCount)
                                )
                            }
                            Text(
                                text = session.session.note
                                    ?.takeIf(String::isNotBlank)
                                    ?.let { stringResource(R.string.details_note, it) }
                                    ?: stringResource(R.string.details_no_note),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = stringResource(
                                    R.string.stats_exercises,
                                    session.exerciseCount
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Button(
                                onClick = { onSelect(session) },
                                enabled = !isBusy,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .heightIn(min = GymSpacing.MinimumTouch)
                                    .testTag(
                                        "friend_workout_picker_select_${session.session.id}"
                                    )
                            ) {
                                if (isSessionBusy) {
                                    CircularProgressIndicator(
                                        modifier = Modifier
                                            .padding(end = GymSpacing.Small)
                                            .size(18.dp),
                                        strokeWidth = 2.dp
                                    )
                                }
                                Text(
                                    text = stringResource(R.string.action_share_workout),
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
