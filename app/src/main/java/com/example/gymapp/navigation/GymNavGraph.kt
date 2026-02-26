package com.example.gymapp.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Language
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.example.gymapp.R
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.ui.screens.AddWorkoutScreen
import com.example.gymapp.ui.screens.ExerciseListScreen
import com.example.gymapp.ui.screens.ExerciseProgressScreen
import com.example.gymapp.ui.screens.GymBackground
import com.example.gymapp.ui.screens.WorkoutDetailScreen
import com.example.gymapp.ui.screens.WorkoutListScreen
import com.example.gymapp.ui.viewmodel.AddWorkoutViewModel
import com.example.gymapp.ui.viewmodel.ExerciseListViewModel
import com.example.gymapp.ui.viewmodel.ExerciseProgressViewModel
import com.example.gymapp.ui.viewmodel.WorkoutDetailViewModel
import com.example.gymapp.ui.viewmodel.WorkoutListViewModel
import com.example.gymapp.util.AppLanguage
import com.example.gymapp.util.LanguageManager
import com.example.gymapp.util.RestTimerController

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GymAppRoot(
    repository: GymRepository,
    languageManager: LanguageManager,
    restTimerController: RestTimerController
) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val selectedLanguage by languageManager.selectedLanguage.collectAsState()

    val isBottomTabRoute = AppDestination.bottomTabs.any { it.route == currentRoute }
    val titleRes = when (currentRoute) {
        AppDestination.Workouts.route -> R.string.title_workouts
        AppDestination.Exercises.route -> R.string.title_exercises
        AppDestination.Progress.route -> R.string.title_progress
        AppDestination.AddWorkout.route -> R.string.title_add_workout
        AppDestination.WorkoutDetail.route -> R.string.title_workout_detail
        else -> R.string.app_name
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        containerColor = androidx.compose.ui.graphics.Color.Transparent,
        contentColor = androidx.compose.material3.MaterialTheme.colorScheme.onBackground,
        topBar = {
            TopAppBar(
                title = { Text(text = stringResource(titleRes)) },
                navigationIcon = {
                    if (!isBottomTabRoute) {
                        IconButton(onClick = { navController.navigateUp() }) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = stringResource(R.string.cd_back)
                            )
                        }
                    }
                },
                actions = {
                    LanguageSelector(
                        selectedLanguage = selectedLanguage,
                        onLanguageSelected = { languageManager.setLanguage(it) }
                    )
                }
            )
        },
        bottomBar = {
            if (isBottomTabRoute) {
                NavigationBar {
                    AppDestination.bottomTabs.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = {
                                navController.navigate(tab.route) {
                                    popUpTo(navController.graph.startDestinationId) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = {
                                Icon(
                                    imageVector = tab.icon,
                                    contentDescription = stringResource(tab.labelRes)
                                )
                            },
                            label = { Text(text = stringResource(tab.labelRes)) }
                        )
                    }
                }
            }
        },
        floatingActionButton = {
            if (currentRoute == AppDestination.Workouts.route) {
                FloatingActionButton(
                    onClick = { navController.navigate(AppDestination.AddWorkout.route) }
                ) {
                    Icon(
                        imageVector = Icons.Default.Add,
                        contentDescription = stringResource(R.string.cd_add_workout)
                    )
                }
            }
        }
    ) { innerPadding ->
        GymBackground(modifier = Modifier.padding(innerPadding)) {
            NavHost(
                navController = navController,
                startDestination = AppDestination.Workouts.route,
                modifier = Modifier.fillMaxSize()
            ) {
                composable(route = AppDestination.Workouts.route) {
                    val viewModel: WorkoutListViewModel = viewModel(
                        factory = WorkoutListViewModel.factory(repository)
                    )
                    val uiState by viewModel.uiState.collectAsState()

                    WorkoutListScreen(
                        uiState = uiState,
                        onSessionClick = { sessionId ->
                            navController.navigate(AppDestination.workoutDetailRoute(sessionId))
                        },
                        onPreviousMonth = viewModel::previousMonth,
                        onCurrentMonth = viewModel::currentMonth,
                        onNextMonth = viewModel::nextMonth,
                        modifier = Modifier.fillMaxSize()
                    )
                }

                composable(route = AppDestination.AddWorkout.route) {
                    val viewModel: AddWorkoutViewModel = viewModel(
                        factory = AddWorkoutViewModel.factory(repository)
                    )
                    val uiState by viewModel.uiState.collectAsState()

                    LaunchedEffect(uiState.createdSessionId) {
                        val createdSessionId = uiState.createdSessionId
                        if (createdSessionId != null) {
                            navController.navigate(AppDestination.workoutDetailRoute(createdSessionId)) {
                                popUpTo(AppDestination.AddWorkout.route) {
                                    inclusive = true
                                }
                            }
                            viewModel.consumeCreatedSession()
                        }
                    }

                    AddWorkoutScreen(
                        uiState = uiState,
                        onNoteChange = viewModel::updateNote,
                        onAddExerciseDraft = viewModel::addExerciseDraft,
                        onRemoveExerciseDraft = viewModel::removeExerciseDraft,
                        onExerciseSelected = viewModel::updateExerciseSelection,
                        onAddSet = viewModel::addSet,
                        onRemoveSet = viewModel::removeSet,
                        onSetWeightChanged = viewModel::updateSetWeight,
                        onSetRepsChanged = viewModel::updateSetReps,
                        onApplyLastWeight = viewModel::applyLastWeight,
                        onRepeatLastWorkout = viewModel::repeatLastWorkout,
                        onSaveWorkout = viewModel::saveWorkout,
                        modifier = Modifier.fillMaxSize()
                    )
                }

                composable(
                    route = AppDestination.WorkoutDetail.route,
                    arguments = listOf(
                        navArgument("sessionId") { type = NavType.LongType }
                    )
                ) { backStackEntry ->
                    val sessionId = backStackEntry.arguments?.getLong("sessionId") ?: return@composable
                    val viewModel: WorkoutDetailViewModel = viewModel(
                        key = "workout_detail_$sessionId",
                        factory = WorkoutDetailViewModel.factory(
                            repository = repository,
                            sessionId = sessionId,
                            restTimerController = restTimerController
                        )
                    )
                    val uiState by viewModel.uiState.collectAsState()

                    WorkoutDetailScreen(
                        uiState = uiState,
                        events = viewModel.events,
                        onAddExerciseToWorkout = viewModel::addExerciseToWorkout,
                        onAddSet = viewModel::addSet,
                        onDeleteSet = viewModel::deleteSet,
                        onUpdateSet = viewModel::updateSet,
                        onUndoDelete = viewModel::undoDeleteSet,
                        modifier = Modifier.fillMaxSize()
                    )
                }

                composable(route = AppDestination.Exercises.route) {
                    val viewModel: ExerciseListViewModel = viewModel(
                        factory = ExerciseListViewModel.factory(repository)
                    )
                    val uiState by viewModel.uiState.collectAsState()

                    ExerciseListScreen(
                        uiState = uiState,
                        onNameChange = viewModel::updateNewExerciseName,
                        onAddExercise = viewModel::addExercise,
                        onExerciseClick = viewModel::openExerciseHistory,
                        onDeleteExercise = viewModel::deleteExercise,
                        onDismissHistory = viewModel::closeExerciseHistory,
                        modifier = Modifier.fillMaxSize()
                    )
                }

                composable(route = AppDestination.Progress.route) {
                    val viewModel: ExerciseProgressViewModel = viewModel(
                        factory = ExerciseProgressViewModel.factory(repository)
                    )
                    val uiState by viewModel.uiState.collectAsState()

                    ExerciseProgressScreen(
                        uiState = uiState,
                        onSelectExercise = viewModel::selectExercise,
                        onDeleteHistoryEntry = viewModel::deleteHistoryEntry,
                        onPreviousMonth = viewModel::previousMonth,
                        onCurrentMonth = viewModel::currentMonth,
                        onNextMonth = viewModel::nextMonth,
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }
        }
    }
}

@Composable
private fun LanguageSelector(
    selectedLanguage: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Box(modifier = Modifier.padding(end = 8.dp)) {
        IconButton(onClick = { expanded = true }) {
            Icon(
                imageVector = Icons.Default.Language,
                contentDescription = stringResource(R.string.cd_language)
            )
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            DropdownMenuItem(
                text = {
                    Text(
                        text = stringResource(R.string.language_english),
                        color = if (selectedLanguage == AppLanguage.EN) {
                            androidx.compose.material3.MaterialTheme.colorScheme.primary
                        } else {
                            androidx.compose.material3.MaterialTheme.colorScheme.onSurface
                        }
                    )
                },
                onClick = {
                    onLanguageSelected(AppLanguage.EN)
                    expanded = false
                }
            )
            DropdownMenuItem(
                text = {
                    Text(
                        text = stringResource(R.string.language_ukrainian),
                        color = if (selectedLanguage == AppLanguage.UK) {
                            androidx.compose.material3.MaterialTheme.colorScheme.primary
                        } else {
                            androidx.compose.material3.MaterialTheme.colorScheme.onSurface
                        }
                    )
                },
                onClick = {
                    onLanguageSelected(AppLanguage.UK)
                    expanded = false
                }
            )
        }
    }
}
