package com.example.gymapp.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit

internal val TrainingSettingsWorkoutsPerWeek = 2..6

/**
 * The single editor for every training-profile field: goal, calories, split and workouts per
 * week. Other screens show [TrainingSettingsSummaryRow] with an "edit" link that opens this sheet.
 * Every choice is applied immediately through [onProfileChange].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrainingSettingsSheet(
    profile: TrainingProfile,
    onProfileChange: (TrainingProfile) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = GymSpacing.XLarge)
                .padding(bottom = GymSpacing.XXLarge),
            verticalArrangement = Arrangement.spacedBy(GymSpacing.Large)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = stringResource(R.string.training_settings_title),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { heading() }
                )
                TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(stringResource(R.string.training_settings_done))
                }
            }
            TrainingSettingsOptions(
                title = stringResource(R.string.training_profile_goal),
                options = TrainingGoal.entries,
                selected = profile.goal,
                label = { it.trainingSettingsLabel() },
                onSelected = { onProfileChange(profile.copy(goal = it)) }
            )
            TrainingSettingsOptions(
                title = stringResource(R.string.training_profile_calories),
                options = CalorieMode.entries,
                selected = profile.calorieMode,
                label = { it.trainingSettingsLabel() },
                onSelected = { onProfileChange(profile.copy(calorieMode = it)) }
            )
            TrainingSettingsOptions(
                title = stringResource(R.string.training_settings_split),
                options = TrainingSplit.entries,
                selected = profile.split,
                label = { it.trainingSettingsLabel() },
                onSelected = { onProfileChange(profile.copy(split = it)) }
            )
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                TrainingSettingsSectionTitle(stringResource(R.string.training_settings_workouts_per_week))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(GymSpacing.Small)
                ) {
                    TrainingSettingsWorkoutsPerWeek.forEach { option ->
                        val selected = profile.workoutsPerWeek == option
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .heightIn(min = 48.dp)
                                .background(
                                    color = if (selected) {
                                        MaterialTheme.colorScheme.primary
                                    } else {
                                        MaterialTheme.colorScheme.surfaceVariant
                                    },
                                    shape = RoundedCornerShape(999.dp)
                                )
                                .selectable(
                                    selected = selected,
                                    role = Role.RadioButton,
                                    onClick = { onProfileChange(profile.copy(workoutsPerWeek = option)) }
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = option.toString(),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                                color = if (selected) {
                                    MaterialTheme.colorScheme.onPrimary
                                } else {
                                    MaterialTheme.colorScheme.onSurface
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun <T> TrainingSettingsOptions(
    title: String,
    options: List<T>,
    selected: T,
    label: @Composable (T) -> String,
    onSelected: (T) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        TrainingSettingsSectionTitle(title)
        AppPanel(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(horizontal = GymSpacing.Large, vertical = 2.dp)) {
                options.forEachIndexed { index, option ->
                    if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    val isSelected = option == selected
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .selectable(
                                selected = isSelected,
                                role = Role.RadioButton,
                                onClick = { onSelected(option) }
                            ),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = label(option),
                            style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier.weight(1f)
                        )
                        if (isSelected) {
                            Icon(
                                imageVector = Icons.Default.Check,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TrainingSettingsSectionTitle(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = GymSpacing.XSmall)
    )
}

/** Read-only "Goal · Calories · N workouts a week · edit" line; the link opens the editor. */
@Composable
fun TrainingSettingsSummaryRow(
    profile: TrainingProfile,
    onEdit: () -> Unit,
    modifier: Modifier = Modifier,
    textColor: Color = MaterialTheme.colorScheme.onSurfaceVariant,
    linkColor: Color = MaterialTheme.colorScheme.primary
) {
    val summary = listOf(
        profile.goal.trainingSettingsLabel(),
        profile.calorieMode.trainingSettingsLabel(),
        pluralStringResource(
            R.plurals.training_settings_workouts_a_week,
            profile.workoutsPerWeek,
            profile.workoutsPerWeek
        )
    ).joinToString(" · ")
    val editLabel = stringResource(R.string.training_settings_edit)
    val editDescription = stringResource(R.string.training_settings_edit_description)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(onClickLabel = editDescription, role = Role.Button, onClick = onEdit),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = summary,
            style = MaterialTheme.typography.bodyMedium,
            color = textColor,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false)
        )
        Text(
            text = editLabel,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = linkColor
        )
    }
}

@Composable
fun TrainingSplit.trainingSettingsLabel(): String = stringResource(
    when (this) {
        TrainingSplit.UpperLower -> R.string.training_split_upper_lower
        TrainingSplit.FullBody -> R.string.training_split_full_body
        TrainingSplit.PushPullLegs -> R.string.training_split_push_pull_legs
        TrainingSplit.Custom -> R.string.training_split_custom
    }
)

@Composable
fun TrainingGoal.trainingSettingsLabel(): String = stringResource(
    when (this) {
        TrainingGoal.AestheticFatLoss -> R.string.training_goal_aesthetic_fat_loss
        TrainingGoal.MuscleGain -> R.string.training_goal_muscle_gain
        TrainingGoal.Strength -> R.string.training_goal_strength
        TrainingGoal.Balanced -> R.string.training_goal_balanced
    }
)

@Composable
fun CalorieMode.trainingSettingsLabel(): String = stringResource(
    when (this) {
        CalorieMode.Deficit -> R.string.calorie_mode_deficit
        CalorieMode.Maintenance -> R.string.calorie_mode_maintenance
        CalorieMode.Surplus -> R.string.calorie_mode_surplus
    }
)
