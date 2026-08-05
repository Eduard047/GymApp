package com.example.gymapp.navigation

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.FormatListBulleted
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.ui.graphics.vector.ImageVector
import com.example.gymapp.R

sealed class AppDestination(
    val route: String,
    @StringRes val labelRes: Int,
    val icon: ImageVector
) {
    data object Workouts : AppDestination(
        route = "workouts",
        labelRes = R.string.tab_workouts,
        icon = Icons.Default.FitnessCenter
    )

    data object Missions : AppDestination(
        route = "missions",
        labelRes = R.string.tab_missions,
        icon = Icons.Default.TrackChanges
    )

    data object Exercises : AppDestination(
        route = "exercises",
        labelRes = R.string.tab_exercises,
        icon = Icons.AutoMirrored.Filled.FormatListBulleted
    )

    data object Progress : AppDestination(
        route = "progress",
        labelRes = R.string.tab_progress,
        icon = Icons.AutoMirrored.Filled.ShowChart
    )

    data object Profile : AppDestination(
        route = "leaderboard",
        labelRes = R.string.tab_profile,
        icon = Icons.Default.Person
    )

    data object AddWorkout : AppDestination(
        route = "add_workout",
        labelRes = R.string.title_add_workout,
        icon = Icons.Default.FitnessCenter
    )

    data object ActiveWorkout : AppDestination(
        route = "active_workout",
        labelRes = R.string.active_workout_title,
        icon = Icons.Default.FitnessCenter
    )

    data object Ranks : AppDestination(
        route = "ranks",
        labelRes = R.string.title_ranks,
        icon = Icons.Default.FitnessCenter
    )

    data object WorkoutDetail : AppDestination(
        route = "workout_detail/{sessionId}",
        labelRes = R.string.title_workout_detail,
        icon = Icons.Default.FitnessCenter
    )

    data object PostWorkoutSummary : AppDestination(
        route = "post_workout_summary/{sessionId}",
        labelRes = R.string.title_post_workout_summary,
        icon = Icons.Default.FitnessCenter
    )

    companion object {
        val bottomTabs = listOf(Workouts, Missions, Exercises, Progress, Profile)

        fun workoutDetailRoute(sessionId: Long): String {
            return "workout_detail/$sessionId"
        }

        fun postWorkoutSummaryRoute(sessionId: Long): String {
            return "post_workout_summary/$sessionId"
        }
    }
}
