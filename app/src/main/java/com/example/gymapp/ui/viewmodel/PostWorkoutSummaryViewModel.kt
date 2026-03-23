package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.data.repository.BadgeRarity
import com.example.gymapp.data.repository.GamificationEngine
import com.example.gymapp.data.repository.GamificationSnapshot
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.MissionBoardSnapshot
import com.example.gymapp.data.repository.MissionSnapshot
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import java.time.ZoneId

data class CompletedMissionUiState(
    val title: String,
    val description: String,
    val rewardXp: Int,
    val cadence: String
)

data class NewBadgeUiState(
    val name: String,
    val title: String,
    val rarity: BadgeRarity,
    val rewardXp: Int
)

data class PostWorkoutSummaryUiState(
    val isLoading: Boolean = true,
    val isSessionFound: Boolean = true,
    val sessionId: Long? = null,
    val sessionDate: Long = 0L,
    val workoutCount: Int = 0,
    val exerciseCount: Int = 0,
    val setCount: Int = 0,
    val volume: Double = 0.0,
    val xpGained: Int = 0,
    val currentLevel: Int = 1,
    val previousLevel: Int = 1,
    val totalXp: Int = 0,
    val levelTitle: String = "Rookie",
    val nextTitle: String? = null,
    val xpIntoLevel: Int = 0,
    val xpToNextLevel: Int = 100,
    val levelProgress: Float = 0f,
    val leveledUp: Boolean = false,
    val streakDays: Int = 0,
    val longestStreakDays: Int = 0,
    val streakExtended: Boolean = false,
    val activeToday: Boolean = false,
    val isComeback: Boolean = false,
    val comebackGapDays: Int? = null,
    val comebackMultiplier: Double = 1.0,
    val comebackBonusXp: Int = 0,
    val completedMissions: List<CompletedMissionUiState> = emptyList(),
    val newBadges: List<NewBadgeUiState> = emptyList()
)

class PostWorkoutSummaryViewModel(
    repository: GymRepository,
    private val sessionId: Long
) : ViewModel() {
    private val zoneId = ZoneId.systemDefault()

    val uiState: StateFlow<PostWorkoutSummaryUiState> = combine(
        repository.observeSessionDetails(sessionId),
        repository.observeSessions()
    ) { sessionDetails, sessions ->
        if (sessionDetails == null) {
            PostWorkoutSummaryUiState(
                isLoading = false,
                isSessionFound = false,
                sessionId = sessionId
            )
        } else {
            val allSessions = sessions.sortedBy { it.session.date }
            val previousSessions = allSessions.filterNot { it.session.id == sessionId }
            val anchorTime = sessionDetails.session.date
            val afterSnapshot = GamificationEngine.buildSnapshot(
                sessions = allSessions,
                nowMillis = anchorTime,
                zoneId = zoneId
            )
            val beforeSnapshot = GamificationEngine.buildSnapshot(
                sessions = previousSessions,
                nowMillis = anchorTime,
                zoneId = zoneId
            )

            val completedMissions = completedMissionDiff(
                before = beforeSnapshot.missions,
                after = afterSnapshot.missions
            )
            val newBadges = newBadgeDiff(
                before = beforeSnapshot,
                after = afterSnapshot
            )
            val workoutExerciseCount = sessionDetails.workoutExercises.size
            val setCount = sessionDetails.workoutExercises.sumOf { it.sets.size }
            val volume = sessionDetails.workoutExercises.sumOf { workoutExercise ->
                workoutExercise.sets.sumOf { set -> set.weight * set.reps }
            }

            PostWorkoutSummaryUiState(
                isLoading = false,
                isSessionFound = true,
                sessionId = sessionDetails.session.id,
                sessionDate = sessionDetails.session.date,
                workoutCount = afterSnapshot.summary.workoutCount,
                exerciseCount = workoutExerciseCount,
                setCount = setCount,
                volume = volume,
                xpGained = (afterSnapshot.progression.totalXp - beforeSnapshot.progression.totalXp).coerceAtLeast(0),
                currentLevel = afterSnapshot.progression.level,
                previousLevel = beforeSnapshot.progression.level,
                totalXp = afterSnapshot.progression.totalXp,
                levelTitle = afterSnapshot.progression.title.name,
                nextTitle = afterSnapshot.progression.nextTitle?.name,
                xpIntoLevel = afterSnapshot.progression.xpIntoLevel,
                xpToNextLevel = afterSnapshot.progression.xpToNextLevel,
                levelProgress = afterSnapshot.progression.levelProgress.toFloat(),
                leveledUp = afterSnapshot.progression.level > beforeSnapshot.progression.level,
                streakDays = afterSnapshot.streak.currentDays,
                longestStreakDays = afterSnapshot.streak.longestDays,
                streakExtended = afterSnapshot.streak.currentDays > beforeSnapshot.streak.currentDays,
                activeToday = afterSnapshot.streak.activeToday,
                isComeback = afterSnapshot.comeback.eligible,
                comebackGapDays = afterSnapshot.comeback.gapDays,
                comebackMultiplier = afterSnapshot.comeback.multiplier,
                comebackBonusXp = afterSnapshot.comeback.bonusXp,
                completedMissions = completedMissions,
                newBadges = newBadges
            )
        }
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = PostWorkoutSummaryUiState(sessionId = sessionId)
    )

    private fun completedMissionDiff(
        before: MissionBoardSnapshot,
        after: MissionBoardSnapshot
    ): List<CompletedMissionUiState> {
        val beforeDailyIds = before.daily.filter { it.completed }.map { it.id }.toSet()
        val beforeWeeklyIds = before.weekly.filter { it.completed }.map { it.id }.toSet()

        val newDaily = after.daily
            .filter { it.completed && it.id !in beforeDailyIds }
            .map { it.toCompletedMissionUiState(cadence = "Daily") }
        val newWeekly = after.weekly
            .filter { it.completed && it.id !in beforeWeeklyIds }
            .map { it.toCompletedMissionUiState(cadence = "Weekly") }

        return newDaily + newWeekly
    }

    private fun newBadgeDiff(
        before: GamificationSnapshot,
        after: GamificationSnapshot
    ): List<NewBadgeUiState> {
        val beforeUnlockedIds = before.achievements
            .filter { it.unlocked }
            .map { it.id }
            .toSet()

        return after.achievements
            .filter { it.unlocked && it.id !in beforeUnlockedIds }
            .map { achievement ->
                NewBadgeUiState(
                    name = achievement.badge.name,
                    title = achievement.title,
                    rarity = achievement.badge.rarity,
                    rewardXp = achievement.rewardXp
                )
            }
    }

    private fun MissionSnapshot.toCompletedMissionUiState(cadence: String): CompletedMissionUiState {
        return CompletedMissionUiState(
            title = title,
            description = description,
            rewardXp = rewardXp,
            cadence = cadence
        )
    }

    companion object {
        fun factory(repository: GymRepository, sessionId: Long): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                PostWorkoutSummaryViewModel(
                    repository = repository,
                    sessionId = sessionId
                )
            }
        }
    }
}
