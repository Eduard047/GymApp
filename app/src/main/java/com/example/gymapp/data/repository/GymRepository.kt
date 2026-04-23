package com.example.gymapp.data.repository

import androidx.room.withTransaction
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.util.DateTimeUtils
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

data class WorkoutSetDraft(
    val weight: Double,
    val reps: Int
)

data class NamedWorkoutSetDraft(
    val exerciseName: String,
    val weight: Double,
    val reps: Int
)

data class WorkoutExerciseDraft(
    val exerciseId: Long,
    val sets: List<WorkoutSetDraft>
)

data class DashboardStats(
    val workoutCount: Int,
    val totalVolume: Double,
    val averageIntensity: Double,
    val streakDays: Int,
    val weeklyStreakWeeks: Int = 0
)

class GymRepository(
    private val database: GymDatabase
) {
    private val exerciseDao = database.exerciseDao()
    private val workoutDao = database.workoutDao()
    private val setDao = database.setDao()

    fun observeExercises(): Flow<List<ExerciseEntity>> = exerciseDao.getExercises()
        .catch { emit(emptyList()) }

    suspend fun addExercise(name: String): Long {
        return exerciseDao.insert(ExerciseEntity(name = name.trim()))
    }

    suspend fun updateExercise(exercise: ExerciseEntity) {
        exerciseDao.update(exercise)
    }

    suspend fun deleteExercise(exercise: ExerciseEntity) {
        exerciseDao.delete(exercise)
    }

    fun observeSessions(): Flow<List<WorkoutSessionSummary>> = workoutDao.getSessions()
        .catch { emit(emptyList()) }

    fun observeGamificationSnapshot(): Flow<GamificationSnapshot> {
        return observeSessions()
            .map { sessions ->
                GamificationEngine.buildSnapshot(
                    sessions = sessions,
                    nowMillis = System.currentTimeMillis(),
                    zoneId = ZoneId.systemDefault()
                )
            }
            .catch {
                emit(
                    GamificationEngine.buildSnapshot(
                        sessions = emptyList(),
                        nowMillis = System.currentTimeMillis(),
                        zoneId = ZoneId.systemDefault()
                    )
                )
            }
    }

    fun observeSessions(
        startTimestamp: Long,
        endTimestamp: Long
    ): Flow<List<WorkoutSessionSummary>> = workoutDao.getSessions(startTimestamp, endTimestamp)
        .catch { emit(emptyList()) }

    fun observeSessionsForMonth(monthOffset: Int): Flow<List<WorkoutSessionSummary>> {
        val (start, end) = DateTimeUtils.monthBounds(monthOffset)
        return observeSessions(start, end)
    }

    fun observeDashboardStatsForMonth(monthOffset: Int): Flow<DashboardStats> {
        val (start, end) = DateTimeUtils.monthBounds(monthOffset)
        return combine(
            observeSessions(start, end),
            observeSessions()
        ) { monthSessions, allSessions ->
            val totalVolume = monthSessions.sumOf { it.totalVolume }
            val totalSets = monthSessions.sumOf { it.setCount }
            val streakDays = calculateStreakDays(allSessions)
            val weeklyStreakWeeks = calculateWeeklyStreakWeeks(allSessions)
            DashboardStats(
                workoutCount = monthSessions.size,
                totalVolume = totalVolume,
                averageIntensity = if (totalSets == 0) 0.0 else totalVolume / totalSets,
                streakDays = streakDays,
                weeklyStreakWeeks = weeklyStreakWeeks
            )
        }
    }

    fun observeSessionDetails(sessionId: Long): Flow<WorkoutSessionDetails?> {
        return workoutDao.getSessionDetails(sessionId).map { details ->
            details?.let(::sortSessionDetails)
        }.catch { emit(null) }
    }

    suspend fun getLatestWorkoutTemplate(): WorkoutSessionDetails? {
        return workoutDao.getLatestSessionDetails()?.let(::sortSessionDetails)
    }

    fun observeExerciseHistory(exerciseId: Long): Flow<List<ExerciseHistoryEntry>> {
        return workoutDao.getExerciseHistory(exerciseId)
            .catch { emit(emptyList()) }
    }

    fun observeExerciseHistory(
        exerciseId: Long,
        startTimestamp: Long,
        endTimestamp: Long
    ): Flow<List<ExerciseHistoryEntry>> {
        return workoutDao.getExerciseHistory(exerciseId, startTimestamp, endTimestamp)
            .catch { emit(emptyList()) }
    }

    fun observeExerciseHistoryForMonth(
        exerciseId: Long,
        monthOffset: Int
    ): Flow<List<ExerciseHistoryEntry>> {
        val (start, end) = DateTimeUtils.monthBounds(monthOffset)
        return observeExerciseHistory(exerciseId, start, end)
    }

    fun observeLastWeight(exerciseId: Long): Flow<Double?> = workoutDao.getLastWeight(exerciseId)
        .catch { emit(null) }

    suspend fun getLastWeightBeforeDate(exerciseId: Long, beforeDate: Long): Double? {
        return workoutDao.getLastWeightBeforeDate(exerciseId, beforeDate)
    }

    suspend fun getExerciseMaxWeightExcludingSession(exerciseId: Long, sessionId: Long): Double? {
        return workoutDao.getExerciseMaxWeightExcludingSession(exerciseId, sessionId)
    }

    fun observeLastWeights(exerciseIds: List<Long>): Flow<Map<Long, Double?>> {
        val uniqueIds = exerciseIds.distinct()
        if (uniqueIds.isEmpty()) {
            return flowOf(emptyMap())
        }

        val flows = uniqueIds.map { exerciseId ->
            observeLastWeight(exerciseId).map { weight -> exerciseId to weight }
        }

        return combine(flows) { entries -> entries.toMap() }
    }

    suspend fun createWorkoutSession(
        date: Long,
        note: String?,
        workoutExercises: List<WorkoutExerciseDraft>
    ): Long {
        return database.withTransaction {
            val sessionId = workoutDao.insert(
                WorkoutSessionEntity(
                    date = date,
                    note = note?.trim().orEmpty().ifBlank { null }
                )
            )

            workoutExercises.forEachIndexed { exerciseIndex, workoutExerciseDraft ->
                val workoutExerciseId = workoutDao.insertWorkoutExercise(
                    WorkoutExerciseEntity(
                        sessionId = sessionId,
                        exerciseId = workoutExerciseDraft.exerciseId,
                        orderIndex = exerciseIndex
                    )
                )

                workoutExerciseDraft.sets.forEachIndexed { setIndex, setDraft ->
                    setDao.insert(
                        SetEntryEntity(
                            workoutExerciseId = workoutExerciseId,
                            weight = setDraft.weight,
                            reps = setDraft.reps,
                            orderIndex = setIndex
                        )
                    )
                }
            }

            sessionId
        }
    }

    suspend fun createWorkoutSessionFromNamedSets(
        date: Long,
        note: String?,
        sets: List<NamedWorkoutSetDraft>
    ): Long? {
        if (sets.isEmpty()) {
            return null
        }

        val exerciseIdByName = linkedMapOf<String, Long>()
        val groupedDrafts = linkedMapOf<Long, MutableList<WorkoutSetDraft>>()

        for (set in sets) {
            val name = set.exerciseName.trim()
            if (name.isBlank()) continue

            val key = name.lowercase()
            val exerciseId = exerciseIdByName.getOrPut(key) {
                runCatching { exerciseDao.getByName(name) }.getOrNull()?.id
                    ?: exerciseDao.insert(ExerciseEntity(name = name))
            }

            groupedDrafts.getOrPut(exerciseId) { mutableListOf() }
                .add(WorkoutSetDraft(weight = set.weight, reps = set.reps))
        }

        if (groupedDrafts.isEmpty()) {
            return null
        }

        return createWorkoutSession(
            date = date,
            note = note,
            workoutExercises = groupedDrafts.map { (exerciseId, drafts) ->
                WorkoutExerciseDraft(exerciseId = exerciseId, sets = drafts)
            }
        )
    }

    suspend fun updateWorkoutSession(session: WorkoutSessionEntity) {
        workoutDao.update(session)
    }

    suspend fun deleteWorkoutSession(session: WorkoutSessionEntity) {
        workoutDao.delete(session)
    }

    suspend fun addSet(
        workoutExerciseId: Long,
        weight: Double,
        reps: Int
    ): Long {
        val nextIndex = (setDao.getMaxOrderIndex(workoutExerciseId) ?: -1) + 1
        return setDao.insert(
            SetEntryEntity(
                workoutExerciseId = workoutExerciseId,
                weight = weight,
                reps = reps,
                orderIndex = nextIndex
            )
        )
    }

    suspend fun addExerciseToSession(
        sessionId: Long,
        exerciseId: Long,
        initialWeight: Double,
        initialReps: Int
    ): Long {
        return database.withTransaction {
            val nextOrderIndex = (workoutDao.getMaxWorkoutExerciseOrderIndex(sessionId) ?: -1) + 1
            val workoutExerciseId = workoutDao.insertWorkoutExercise(
                WorkoutExerciseEntity(
                    sessionId = sessionId,
                    exerciseId = exerciseId,
                    orderIndex = nextOrderIndex
                )
            )
            setDao.insert(
                SetEntryEntity(
                    workoutExerciseId = workoutExerciseId,
                    weight = initialWeight,
                    reps = initialReps,
                    orderIndex = 0
                )
            )
            workoutExerciseId
        }
    }

    suspend fun insertSet(setEntry: SetEntryEntity): Long {
        return setDao.insert(setEntry.copy(id = 0))
    }

    suspend fun updateSet(setEntry: SetEntryEntity) {
        setDao.update(setEntry)
    }

    suspend fun updateSetById(setId: Long, weight: Double, reps: Int) {
        val existing = setDao.getById(setId) ?: return
        setDao.update(
            existing.copy(
                weight = weight,
                reps = reps
            )
        )
    }

    suspend fun deleteSet(setEntry: SetEntryEntity) {
        deleteSetById(setEntry.id)
    }

    suspend fun deleteSetById(setId: Long) {
        if (setId <= 0) return

        database.withTransaction {
            val workoutExerciseId = setDao.getWorkoutExerciseIdBySetId(setId) ?: return@withTransaction
            setDao.deleteById(setId)
            cleanupAfterSetDeletion(workoutExerciseId)
        }
    }

    private suspend fun cleanupAfterSetDeletion(workoutExerciseId: Long) {
        val remainingSets = setDao.getSetCountForWorkoutExercise(workoutExerciseId)
        if (remainingSets > 0) {
            return
        }

        val sessionId = workoutDao.getSessionIdByWorkoutExerciseId(workoutExerciseId) ?: return
        workoutDao.deleteWorkoutExerciseById(workoutExerciseId)

        val remainingExercises = workoutDao.getWorkoutExerciseCount(sessionId)
        if (remainingExercises == 0) {
            workoutDao.deleteSessionById(sessionId)
        }
    }

    private fun sortSessionDetails(details: WorkoutSessionDetails): WorkoutSessionDetails {
        return details.copy(
            workoutExercises = details.workoutExercises
                .sortedBy { it.workoutExercise.orderIndex }
                .map { exercise ->
                    exercise.copy(sets = exercise.sets.sortedBy { it.orderIndex })
                }
        )
    }

    suspend fun getSessionDetailsForSync(limit: Int = 120): List<WorkoutSessionDetails> {
        return workoutDao.getSessionDetailsForSync(limit).map(::sortSessionDetails)
    }

    suspend fun getExerciseNamesForSync(limit: Int = 400): List<String> {
        return exerciseDao.getExerciseNamesForSync()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .distinctBy { it.lowercase() }
            .take(limit)
    }

    private fun calculateStreakDays(allSessions: List<WorkoutSessionSummary>): Int {
        if (allSessions.isEmpty()) {
            return 0
        }

        val zoneId = ZoneId.systemDefault()
        val workoutDays = allSessions.map { session ->
            Instant.ofEpochMilli(session.session.date).atZone(zoneId).toLocalDate().toEpochDay()
        }.toSet()

        var cursorDay = LocalDate.now(zoneId).toEpochDay()
        if (!workoutDays.contains(cursorDay)) {
            cursorDay -= 1
        }

        var streak = 0
        while (workoutDays.contains(cursorDay)) {
            streak += 1
            cursorDay -= 1
        }
        return streak
    }

    private fun calculateWeeklyStreakWeeks(allSessions: List<WorkoutSessionSummary>): Int {
        if (allSessions.isEmpty()) {
            return 0
        }

        val zoneId = ZoneId.systemDefault()
        val weekStarts = allSessions.groupingBy { session ->
            Instant.ofEpochMilli(session.session.date)
                .atZone(zoneId)
                .toLocalDate()
                .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        }.eachCount()

        var cursorWeekStart = LocalDate.now(zoneId).with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        if ((weekStarts[cursorWeekStart] ?: 0) < 3) {
            cursorWeekStart = cursorWeekStart.minusWeeks(1)
        }

        var streak = 0
        while ((weekStarts[cursorWeekStart] ?: 0) >= 3) {
            streak += 1
            cursorWeekStart = cursorWeekStart.minusWeeks(1)
        }
        return streak
    }
}

