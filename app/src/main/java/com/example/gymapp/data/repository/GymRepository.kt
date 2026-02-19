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
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

data class WorkoutSetDraft(
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
    val streakDays: Int
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
            DashboardStats(
                workoutCount = monthSessions.size,
                totalVolume = totalVolume,
                averageIntensity = if (totalSets == 0) 0.0 else totalVolume / totalSets,
                streakDays = calculateStreakDays(allSessions)
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

    suspend fun insertSet(setEntry: SetEntryEntity): Long {
        return setDao.insert(setEntry.copy(id = 0))
    }

    suspend fun updateSet(setEntry: SetEntryEntity) {
        setDao.update(setEntry)
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
}

