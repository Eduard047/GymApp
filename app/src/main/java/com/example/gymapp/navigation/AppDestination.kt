package com.example.gymapp.navigation

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.FitnessCenter
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

    data object Exercises : AppDestination(
        route = "exercises",
        labelRes = R.string.tab_exercises,
        icon = Icons.AutoMirrored.Filled.List
    )

    data object Progress : AppDestination(
        route = "progress",
        labelRes = R.string.tab_progress,
        icon = Icons.AutoMirrored.Filled.ShowChart
    )

    data object AddWorkout : AppDestination(
        route = "add_workout",
        labelRes = R.string.title_add_workout,
        icon = Icons.Default.FitnessCenter
    )

    data object WorkoutDetail : AppDestination(
        route = "workout_detail/{sessionId}",
        labelRes = R.string.title_workout_detail,
        icon = Icons.Default.FitnessCenter
    )

    companion object {
        val bottomTabs = listOf(Workouts, Exercises, Progress)

        fun workoutDetailRoute(sessionId: Long): String {
            return "workout_detail/$sessionId"
        }
    }
}

