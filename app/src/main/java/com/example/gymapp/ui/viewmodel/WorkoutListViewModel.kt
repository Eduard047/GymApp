package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.lifecycle.viewModelScope
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.data.repository.DashboardStats
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.util.DateTimeUtils
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn

data class WorkoutListUiState(
    val monthOffset: Int = 0,
    val monthLabel: String = DateTimeUtils.monthLabel(0),
    val sessions: List<WorkoutSessionSummary> = emptyList(),
    val dashboardStats: DashboardStats = DashboardStats(
        workoutCount = 0,
        totalVolume = 0.0,
        averageIntensity = 0.0,
        streakDays = 0
    )
)

@OptIn(ExperimentalCoroutinesApi::class)
class WorkoutListViewModel(
    private val repository: GymRepository
) : ViewModel() {
    private val monthOffset = MutableStateFlow(0)

    private val sessionsFlow = monthOffset.flatMapLatest { offset ->
        repository.observeSessionsForMonth(offset)
    }

    private val dashboardFlow = monthOffset.flatMapLatest { offset ->
        repository.observeDashboardStatsForMonth(offset)
    }

    val uiState: StateFlow<WorkoutListUiState> = combine(
        monthOffset,
        sessionsFlow,
        dashboardFlow
    ) { offset, sessions, dashboardStats ->
        WorkoutListUiState(
            monthOffset = offset,
            monthLabel = DateTimeUtils.monthLabel(offset),
            sessions = sessions,
            dashboardStats = dashboardStats
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WorkoutListUiState()
    )

    fun previousMonth() {
        monthOffset.value -= 1
    }

    fun nextMonth() {
        monthOffset.value += 1
    }

    fun currentMonth() {
        monthOffset.value = 0
    }

    companion object {
        fun factory(repository: GymRepository): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                WorkoutListViewModel(repository)
            }
        }
    }
}

