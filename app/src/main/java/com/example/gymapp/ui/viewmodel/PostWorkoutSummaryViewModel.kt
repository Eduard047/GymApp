package com.example.gymapp.ui.viewmodel

import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.ExerciseMuscleMappingEntity
import com.example.gymapp.data.repository.BadgeRarity
import com.example.gymapp.data.repository.GamificationEngine
import com.example.gymapp.data.repository.GamificationSnapshot
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.MUSCLE_DEFINITIONS
import com.example.gymapp.data.repository.RANK_DEFINITIONS
import com.example.gymapp.data.repository.estimatedLoad
import com.example.gymapp.data.repository.muscleContributionsForExercise
import com.example.gymapp.data.repository.toManualContributionMap
import com.example.gymapp.garmin.WorkoutComparison
import com.example.gymapp.garmin.buildWorkoutComparisonForSession
import com.example.gymapp.garmin.isWorkoutEarlier
import com.example.gymapp.garmin.toExerciseHistoryEntries
import com.example.gymapp.util.RussianText
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.math.pow
import kotlin.math.roundToInt

data class CompletedMissionUiState(
    val id: String,
    val title: String,
    val description: String,
    val target: Int,
    val cadence: String
)

data class NewBadgeUiState(
    val name: String,
    val title: String,
    val rarity: BadgeRarity,
    val rewardXp: Int
)

data class PostWorkoutMuscleUiState(
    val id: String,
    val label: String,
    val load: Int,
    val sets: Int,
    val intensity: Float
)

data class PostWorkoutPrUiState(
    val exerciseId: Long,
    val exerciseName: String,
    val weight: Double,
    val previousBest: Double?
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
    val levelTitle: String = "--",
    val nextTitle: String? = null,
    val xpIntoLevel: Int = 0,
    val xpToNextLevel: Int = 200,
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
    val topMuscleLabel: String? = null,
    val muscles: List<PostWorkoutMuscleUiState> = emptyList(),
    val personalRecords: List<PostWorkoutPrUiState> = emptyList(),
    val workoutComparison: WorkoutComparison? = null,
    val completedMissions: List<CompletedMissionUiState> = emptyList(),
    val newBadges: List<NewBadgeUiState> = emptyList()
)

private data class MutableSessionMuscleStats(
    var load: Double = 0.0,
    val setIds: MutableSet<Long> = linkedSetOf()
)

internal data class PostWorkoutAchievementTranslation(
    val title: String,
    val description: String,
    val badgeName: String
)

internal val POST_WORKOUT_ACHIEVEMENT_UK = mapOf(
    "first_workout" to PostWorkoutAchievementTranslation(
        "Перше тренування", "Заверши своє перше тренування.", "Перший підхід"
    ),
    "workout_5" to PostWorkoutAchievementTranslation(
        "Початок звички", "Заверши п’ять тренувань.", "Початок звички"
    ),
    "workout_10" to PostWorkoutAchievementTranslation(
        "Будівник стабільності", "Заверши десять тренувань.", "Стабільність"
    ),
    "workout_25" to PostWorkoutAchievementTranslation(
        "Працьовитий", "Заверши двадцять п’ять тренувань.", "Працьовитий"
    ),
    "workout_50" to PostWorkoutAchievementTranslation(
        "Ветеран", "Заверши п’ятдесят тренувань.", "Ветеран"
    ),
    "workout_100" to PostWorkoutAchievementTranslation(
        "Центуріон", "Заверши сто тренувань.", "Центуріон"
    ),
    "streak_7" to PostWorkoutAchievementTranslation(
        "Серія на сім днів", "Підтримуй серію протягом семи днів.", "Імпульс"
    ),
    "streak_14" to PostWorkoutAchievementTranslation(
        "Серія на чотирнадцять днів", "Підтримуй серію протягом чотирнадцяти днів.", "Стан потоку"
    ),
    "streak_30" to PostWorkoutAchievementTranslation(
        "Серія на тридцять днів", "Підтримуй серію протягом тридцяти днів.", "Незламний"
    ),
    "volume_10k" to PostWorkoutAchievementTranslation(
        "Десять тисяч обсягу", "Накопич загальний обсяг 10 000.", "Творець обсягу"
    ),
    "volume_50k" to PostWorkoutAchievementTranslation(
        "П’ятдесят тисяч обсягу", "Накопич загальний обсяг 50 000.", "Підкорювач гір"
    ),
    "comeback" to PostWorkoutAchievementTranslation(
        "Повернення", "Повернися після семиденної перерви.", "Повернення"
    )
)

class PostWorkoutSummaryViewModel(
    repository: GymRepository,
    private val sessionId: Long
) : ViewModel() {
    private val zoneId = ZoneId.systemDefault()

    val uiState: StateFlow<PostWorkoutSummaryUiState> = combine(
        repository.observeSessionDetails(sessionId),
        repository.observeSessions(),
        repository.observeAllExerciseHistory(),
        repository.observeExerciseMuscleMappings()
    ) { sessionDetails, sessions, exerciseHistory, muscleMappings ->
        if (sessionDetails == null) {
            PostWorkoutSummaryUiState(
                isLoading = false,
                isSessionFound = false,
                sessionId = sessionId
            )
        } else {
            val anchorTime = sessionDetails.session.date
            val sessionsThroughCurrent = sessions
                .filter { summary ->
                    summary.session.id == sessionId || isWorkoutEarlier(
                        candidateDate = summary.session.date,
                        candidateId = summary.session.id,
                        currentDate = anchorTime,
                        currentId = sessionId
                    )
                }
                .sortedWith(compareBy({ it.session.date }, { it.session.id }))
            val previousSessions = sessionsThroughCurrent.filter { summary ->
                isWorkoutEarlier(
                    candidateDate = summary.session.date,
                    candidateId = summary.session.id,
                    currentDate = anchorTime,
                    currentId = sessionId
                )
            }
            val afterSnapshot = GamificationEngine.buildSnapshot(
                sessions = sessionsThroughCurrent,
                nowMillis = anchorTime,
                zoneId = zoneId
            )
            val beforeSnapshot = GamificationEngine.buildSnapshot(
                sessions = previousSessions,
                nowMillis = anchorTime,
                zoneId = zoneId
            )
            val anchorDate = Instant.ofEpochMilli(anchorTime).atZone(zoneId).toLocalDate()
            val afterMissionBoard = AdaptiveMissionBoardSource.build(
                sessions = sessionsThroughCurrent,
                anchorDate = anchorDate,
                zoneId = zoneId
            )
            val beforeMissionBoard = AdaptiveMissionBoardSource.build(
                sessions = previousSessions,
                anchorDate = anchorDate,
                zoneId = zoneId
            )

            val completedMissions = completedMissionDiff(
                before = beforeMissionBoard,
                after = afterMissionBoard
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
            val sessionHistoryEntries = sessionDetails.toExerciseHistoryEntries()
            val muscles = buildSessionMuscles(
                sessionHistoryEntries = sessionHistoryEntries,
                muscleMappings = muscleMappings
            )
            val personalRecords = buildPersonalRecords(
                sessionEntries = sessionHistoryEntries,
                allHistory = exerciseHistory,
                currentSessionDate = sessionDetails.session.date
            )
            val workoutComparison = buildWorkoutComparisonForSession(
                currentSessionId = sessionDetails.session.id,
                currentSessionDate = sessionDetails.session.date,
                currentNote = sessionDetails.session.note,
                currentHasGarminReceipt = sessions
                    .firstOrNull { summary -> summary.session.id == sessionId }
                    ?.hasGarminReceipt == true,
                currentEntries = sessionHistoryEntries,
                allSessions = sessions,
                allHistory = exerciseHistory
            )

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
                levelTitle = localizedRankTitle(afterSnapshot.progression.title.name),
                nextTitle = afterSnapshot.progression.nextTitle?.name?.let(::localizedRankTitle),
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
                topMuscleLabel = muscles.firstOrNull()?.label,
                muscles = muscles,
                personalRecords = personalRecords,
                workoutComparison = workoutComparison,
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
        before: AdaptiveMissionBoard,
        after: AdaptiveMissionBoard
    ): List<CompletedMissionUiState> {
        return AdaptiveMissionBoardSource.newlyCompleted(before, after)
            .map { mission -> mission.toCompletedMissionUiState() }
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
                val translation = POST_WORKOUT_ACHIEVEMENT_UK[achievement.id]
                NewBadgeUiState(
                    name = localizedText(
                        en = achievement.badge.name,
                        uk = translation?.badgeName ?: achievement.badge.name
                    ),
                    title = localizedText(
                        en = achievement.title,
                        uk = translation?.title ?: achievement.title
                    ),
                    rarity = achievement.badge.rarity,
                    rewardXp = achievement.rewardXp
                )
            }
    }

    private fun buildSessionMuscles(
        sessionHistoryEntries: List<ExerciseHistoryEntry>,
        muscleMappings: List<ExerciseMuscleMappingEntity>
    ): List<PostWorkoutMuscleUiState> {
        val manualMap = muscleMappings.toManualContributionMap()
        val statsByMuscle = MUSCLE_DEFINITIONS.associate { it.id to MutableSessionMuscleStats() }.toMutableMap()

        sessionHistoryEntries.forEach { entry ->
            val load = entry.estimatedLoad()
            muscleContributionsForExercise(entry.exerciseName, manualMap).forEach { contribution ->
                val stats = statsByMuscle.getOrPut(contribution.muscleId) { MutableSessionMuscleStats() }
                stats.load += load * contribution.weight
                stats.setIds += entry.setId
            }
        }

        val maxLoad = statsByMuscle.values.maxOfOrNull { it.load } ?: 0.0
        return MUSCLE_DEFINITIONS.mapNotNull { definition ->
            val stats = statsByMuscle[definition.id] ?: return@mapNotNull null
            if (stats.load <= 0.0) return@mapNotNull null
            val ratio = if (maxLoad <= 0.0) 0.0 else (stats.load / maxLoad).coerceIn(0.0, 1.0)
            PostWorkoutMuscleUiState(
                id = definition.id,
                label = localizedText(definition.titleEn, definition.titleUk),
                load = stats.load.roundToInt(),
                sets = stats.setIds.size,
                intensity = ratio.pow(0.72).toFloat().coerceIn(0f, 1f)
            )
        }.sortedByDescending { it.load }
    }

    private fun buildPersonalRecords(
        sessionEntries: List<ExerciseHistoryEntry>,
        allHistory: List<ExerciseHistoryEntry>,
        currentSessionDate: Long
    ): List<PostWorkoutPrUiState> {
        val previousBestByExercise = allHistory
            .filter { entry ->
                isWorkoutEarlier(
                    candidateDate = entry.sessionDate,
                    candidateId = entry.sessionId,
                    currentDate = currentSessionDate,
                    currentId = sessionId
                )
            }
            .groupBy { it.exerciseId }
            .mapValues { (_, entries) -> entries.maxOfOrNull { it.weight } ?: 0.0 }

        return sessionEntries
            .groupBy { it.exerciseId }
            .mapNotNull { (exerciseId, entries) ->
                val bestCurrentSet = entries.maxByOrNull { it.weight } ?: return@mapNotNull null
                val previousBest = previousBestByExercise[exerciseId]
                if (bestCurrentSet.weight <= 0.0) {
                    return@mapNotNull null
                }
                if (previousBest != null && bestCurrentSet.weight <= previousBest) {
                    return@mapNotNull null
                }
                PostWorkoutPrUiState(
                    exerciseId = exerciseId,
                    exerciseName = BuiltInExerciseCatalog.displayName(
                        bestCurrentSet.exerciseName,
                        currentLocale().language
                    ),
                    weight = bestCurrentSet.weight,
                    previousBest = previousBest
                )
            }
            .sortedByDescending { it.weight }
    }

    private fun AdaptiveMission.toCompletedMissionUiState(): CompletedMissionUiState {
        val cadenceLabel = when (cadence) {
            MissionCadence.Daily -> localizedText(en = "Daily", uk = "Щоденна")
            MissionCadence.Weekly -> localizedText(en = "Weekly", uk = "Щотижнева")
            MissionCadence.Monthly -> localizedText(en = "Monthly", uk = "Щомісячна")
        }
        return CompletedMissionUiState(
            id = id,
            title = localizedText(en = titleEn, uk = titleUk),
            description = localizedText(en = summaryEn, uk = summaryUk),
            target = goal,
            cadence = cadenceLabel
        )
    }

    private fun localizedRankTitle(english: String): String {
        val ukrainian = RANK_DEFINITIONS
            .firstOrNull { it.titleEn == english }
            ?.titleUk
            ?: english
        return localizedText(en = english, uk = ukrainian)
    }

    private fun localizedText(en: String, uk: String): String = when (
        currentLocale().language.lowercase(Locale.ROOT)
    ) {
        "uk" -> uk
        "ru" -> RussianText.translate(en)
        else -> en
    }

    private fun currentLocale(): Locale {
        val appLocales = AppCompatDelegate.getApplicationLocales()
        return if (appLocales.isEmpty) {
            Locale.getDefault()
        } else {
            appLocales[0] ?: Locale.getDefault()
        }
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
