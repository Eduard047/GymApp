package com.example.gymapp.navigation

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Language
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.style.TextAlign
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
import com.example.gymapp.ui.screens.AppIntroSplash
import com.example.gymapp.ui.screens.ExerciseListScreen
import com.example.gymapp.ui.screens.ExerciseProgressScreen
import com.example.gymapp.ui.screens.GymBackground
import com.example.gymapp.ui.screens.PostWorkoutSummaryScreen
import com.example.gymapp.ui.screens.WorkoutDetailScreen
import com.example.gymapp.ui.screens.WorkoutListScreen
import com.example.gymapp.ui.viewmodel.AddWorkoutViewModel
import com.example.gymapp.ui.viewmodel.ExerciseListViewModel
import com.example.gymapp.ui.viewmodel.ExerciseProgressViewModel
import com.example.gymapp.ui.viewmodel.PostWorkoutSummaryViewModel
import com.example.gymapp.ui.viewmodel.WorkoutDetailViewModel
import com.example.gymapp.ui.viewmodel.WorkoutListViewModel
import com.example.gymapp.util.AppLanguage
import com.example.gymapp.util.LanguageManager
import com.example.gymapp.util.RestTimerController
import kotlinx.coroutines.delay

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
    var showIntro by rememberSaveable { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        delay(1400)
        showIntro = false
    }

    val isBottomTabRoute = AppDestination.bottomTabs.any { it.route == currentRoute }
    val titleRes = when {
        currentRoute == AppDestination.Workouts.route -> R.string.title_workouts
        currentRoute == AppDestination.Exercises.route -> R.string.title_exercises
        currentRoute == AppDestination.Progress.route -> R.string.title_progress
        currentRoute == AppDestination.AddWorkout.route -> R.string.title_add_workout
        currentRoute?.startsWith("workout_detail/") == true -> R.string.title_workout_detail
        currentRoute?.startsWith("post_workout_summary/") == true -> R.string.title_workout_detail
        else -> R.string.app_name
    }

    GymBackground {
        Box(modifier = Modifier.fillMaxSize()) {
            Scaffold(
                modifier = Modifier.fillMaxSize(),
                containerColor = Color.Transparent,
                contentColor = MaterialTheme.colorScheme.onBackground,
                topBar = {
                    AppTopBar(
                        titleRes = titleRes,
                        isRootDestination = isBottomTabRoute,
                        selectedLanguage = selectedLanguage,
                        onBack = { navController.navigateUp() },
                        onLanguageSelected = { languageManager.setLanguage(it) }
                    )
                },
                bottomBar = {
                    if (isBottomTabRoute) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            contentAlignment = Alignment.BottomCenter
                        ) {
                            Surface(
                                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f),
                                shape = MaterialTheme.shapes.extraLarge,
                                tonalElevation = 4.dp,
                                shadowElevation = 12.dp,
                                border = androidx.compose.foundation.BorderStroke(
                                    1.dp,
                                    MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.8f)
                                )
                            ) {
                                NavigationBar(
                                    modifier = Modifier.height(74.dp),
                                    containerColor = Color.Transparent,
                                    tonalElevation = 0.dp
                                ) {
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
                                            colors = NavigationBarItemDefaults.colors(
                                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                                selectedTextColor = MaterialTheme.colorScheme.primary,
                                                indicatorColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                                                unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                                unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant
                                            ),
                                            icon = {
                                                Box(
                                                    modifier = Modifier.size(24.dp),
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    Icon(
                                                        imageVector = tab.icon,
                                                        contentDescription = stringResource(tab.labelRes),
                                                        modifier = Modifier.size(20.dp)
                                                    )
                                                }
                                            },
                                            label = {
                                                Text(
                                                    text = stringResource(tab.labelRes),
                                                    style = MaterialTheme.typography.labelSmall,
                                                    modifier = Modifier.fillMaxWidth(),
                                                    textAlign = TextAlign.Center,
                                                    maxLines = 1
                                                )
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                },
                floatingActionButton = {
                    if (currentRoute == AppDestination.Workouts.route) {
                        ExtendedFloatingActionButton(
                            onClick = { navController.navigate(AppDestination.AddWorkout.route) },
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                            expanded = true,
                            text = { Text(text = stringResource(R.string.action_add_workout)) },
                            icon = {
                                Icon(
                                    imageVector = Icons.Default.Add,
                                    contentDescription = stringResource(R.string.cd_add_workout)
                                )
                            }
                        )
                    }
                }
            ) { innerPadding ->
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                ) {
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
                                    navController.navigate(AppDestination.postWorkoutSummaryRoute(createdSessionId)) {
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
                            route = AppDestination.PostWorkoutSummary.route,
                            arguments = listOf(
                                navArgument("sessionId") { type = NavType.LongType }
                            )
                        ) { backStackEntry ->
                            val sessionId = backStackEntry.arguments?.getLong("sessionId") ?: return@composable
                            val viewModel: PostWorkoutSummaryViewModel = viewModel(
                                key = "post_workout_summary_$sessionId",
                                factory = PostWorkoutSummaryViewModel.factory(
                                    repository = repository,
                                    sessionId = sessionId
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            PostWorkoutSummaryScreen(
                                uiState = uiState,
                                onViewWorkout = {
                                    navController.navigate(AppDestination.workoutDetailRoute(sessionId)) {
                                        popUpTo(AppDestination.PostWorkoutSummary.route) {
                                            inclusive = true
                                        }
                                    }
                                },
                                onDone = {
                                    navController.navigate(AppDestination.Workouts.route) {
                                        popUpTo(navController.graph.startDestinationId) {
                                            saveState = true
                                        }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                },
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

            AnimatedVisibility(
                visible = showIntro,
                enter = fadeIn() + slideInVertically(initialOffsetY = { it / 8 }),
                exit = fadeOut() + scaleOut(targetScale = 1.03f)
            ) {
                AppIntroSplash()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppTopBar(
    titleRes: Int,
    isRootDestination: Boolean,
    selectedLanguage: AppLanguage,
    onBack: () -> Unit,
    onLanguageSelected: (AppLanguage) -> Unit
) {
    CenterAlignedTopAppBar(
        colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
            containerColor = Color.Transparent,
            titleContentColor = MaterialTheme.colorScheme.onBackground
        ),
        title = {
            Text(
                text = stringResource(titleRes),
                style = MaterialTheme.typography.titleLarge
            )
        },
        navigationIcon = {
            if (!isRootDestination) {
                Surface(
                    modifier = Modifier.padding(start = 12.dp),
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.84f),
                    shape = MaterialTheme.shapes.small,
                    border = androidx.compose.foundation.BorderStroke(
                        1.dp,
                        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.8f)
                    )
                ) {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back)
                        )
                    }
                }
            }
        },
        actions = {
            LanguageSelector(
                selectedLanguage = selectedLanguage,
                onLanguageSelected = onLanguageSelected
            )
        }
    )
}

@Composable
private fun LanguageSelector(
    selectedLanguage: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Box(modifier = Modifier.padding(end = 12.dp)) {
        Surface(
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.84f),
            shape = MaterialTheme.shapes.small,
            border = androidx.compose.foundation.BorderStroke(
                1.dp,
                MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.8f)
            )
        ) {
            IconButton(onClick = { expanded = true }) {
                Icon(
                    imageVector = Icons.Default.Language,
                    contentDescription = stringResource(R.string.cd_language)
                )
            }
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
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
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
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
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
