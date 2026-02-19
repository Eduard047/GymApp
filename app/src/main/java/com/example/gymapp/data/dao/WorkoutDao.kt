package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import kotlinx.coroutines.flow.Flow

@Dao
interface WorkoutDao {
    @Insert
    suspend fun insert(session: WorkoutSessionEntity): Long

    @Update
    suspend fun update(session: WorkoutSessionEntity)

    @Delete
    suspend fun delete(session: WorkoutSessionEntity)

    @Insert
    suspend fun insertWorkoutExercise(workoutExercise: WorkoutExerciseEntity): Long

    @Query("SELECT sessionId FROM workout_exercises WHERE id = :workoutExerciseId LIMIT 1")
    suspend fun getSessionIdByWorkoutExerciseId(workoutExerciseId: Long): Long?

    @Query("SELECT COUNT(*) FROM workout_exercises WHERE sessionId = :sessionId")
    suspend fun getWorkoutExerciseCount(sessionId: Long): Int

    @Update
    suspend fun updateWorkoutExercise(workoutExercise: WorkoutExerciseEntity)

    @Query("DELETE FROM workout_exercises WHERE id = :workoutExerciseId")
    suspend fun deleteWorkoutExerciseById(workoutExerciseId: Long)

    @Delete
    suspend fun deleteWorkoutExercise(workoutExercise: WorkoutExerciseEntity)

    @Query("DELETE FROM workout_sessions WHERE id = :sessionId")
    suspend fun deleteSessionById(sessionId: Long)

    @Query(
        """
        SELECT
            s.id,
            s.date,
            s.note,
            COUNT(DISTINCT CASE WHEN se.id IS NOT NULL THEN we.id END) AS exerciseCount,
            COUNT(se.id) AS setCount,
            COALESCE(SUM(se.weight * se.reps), 0.0) AS totalVolume
        FROM workout_sessions s
        LEFT JOIN workout_exercises we ON we.sessionId = s.id
        LEFT JOIN set_entries se ON se.workoutExerciseId = we.id
        GROUP BY s.id
        HAVING COUNT(se.id) > 0
        ORDER BY s.date DESC
        """
    )
    fun getSessions(): Flow<List<WorkoutSessionSummary>>

    @Query(
        """
        SELECT
            s.id,
            s.date,
            s.note,
            COUNT(DISTINCT CASE WHEN se.id IS NOT NULL THEN we.id END) AS exerciseCount,
            COUNT(se.id) AS setCount,
            COALESCE(SUM(se.weight * se.reps), 0.0) AS totalVolume
        FROM workout_sessions s
        LEFT JOIN workout_exercises we ON we.sessionId = s.id
        LEFT JOIN set_entries se ON se.workoutExerciseId = we.id
        WHERE s.date BETWEEN :startTimestamp AND :endTimestamp
        GROUP BY s.id
        HAVING COUNT(se.id) > 0
        ORDER BY s.date DESC
        """
    )
    fun getSessions(
        startTimestamp: Long,
        endTimestamp: Long
    ): Flow<List<WorkoutSessionSummary>>

    @androidx.room.Transaction
    @Query("SELECT * FROM workout_sessions WHERE id = :sessionId LIMIT 1")
    fun getSessionDetails(sessionId: Long): Flow<WorkoutSessionDetails?>

    @androidx.room.Transaction
    @Query(
        """
        SELECT *
        FROM workout_sessions ws
        WHERE EXISTS (
            SELECT 1
            FROM workout_exercises we
            INNER JOIN set_entries se ON se.workoutExerciseId = we.id
            WHERE we.sessionId = ws.id
        )
        ORDER BY ws.date DESC
        LIMIT 1
        """
    )
    suspend fun getLatestSessionDetails(): WorkoutSessionDetails?

    @Query(
        """
        SELECT
            se.id AS setId,
            ws.id AS sessionId,
            ws.date AS sessionDate,
            e.id AS exerciseId,
            e.name AS exerciseName,
            se.weight AS weight,
            se.reps AS reps,
            se.orderIndex AS setOrderIndex
        FROM set_entries se
        INNER JOIN workout_exercises we ON we.id = se.workoutExerciseId
        INNER JOIN workout_sessions ws ON ws.id = we.sessionId
        INNER JOIN exercises e ON e.id = we.exerciseId
        WHERE we.exerciseId = :exerciseId
        ORDER BY ws.date DESC, se.orderIndex ASC
        """
    )
    fun getExerciseHistory(exerciseId: Long): Flow<List<ExerciseHistoryEntry>>

    @Query(
        """
        SELECT
            se.id AS setId,
            ws.id AS sessionId,
            ws.date AS sessionDate,
            e.id AS exerciseId,
            e.name AS exerciseName,
            se.weight AS weight,
            se.reps AS reps,
            se.orderIndex AS setOrderIndex
        FROM set_entries se
        INNER JOIN workout_exercises we ON we.id = se.workoutExerciseId
        INNER JOIN workout_sessions ws ON ws.id = we.sessionId
        INNER JOIN exercises e ON e.id = we.exerciseId
        WHERE we.exerciseId = :exerciseId
            AND ws.date BETWEEN :startTimestamp AND :endTimestamp
        ORDER BY ws.date DESC, se.orderIndex ASC
        """
    )
    fun getExerciseHistory(
        exerciseId: Long,
        startTimestamp: Long,
        endTimestamp: Long
    ): Flow<List<ExerciseHistoryEntry>>

    @Query(
        """
        SELECT se.weight
        FROM set_entries se
        INNER JOIN workout_exercises we ON we.id = se.workoutExerciseId
        INNER JOIN workout_sessions ws ON ws.id = we.sessionId
        WHERE we.exerciseId = :exerciseId
        ORDER BY ws.date DESC, se.orderIndex DESC
        LIMIT 1
        """
    )
    fun getLastWeight(exerciseId: Long): Flow<Double?>

    @Query(
        """
        SELECT se.weight
        FROM set_entries se
        INNER JOIN workout_exercises we ON we.id = se.workoutExerciseId
        INNER JOIN workout_sessions ws ON ws.id = we.sessionId
        WHERE we.exerciseId = :exerciseId
            AND ws.date < :beforeDate
        ORDER BY ws.date DESC, se.orderIndex DESC
        LIMIT 1
        """
    )
    suspend fun getLastWeightBeforeDate(exerciseId: Long, beforeDate: Long): Double?

    @Query(
        """
        SELECT MAX(se.weight)
        FROM set_entries se
        INNER JOIN workout_exercises we ON we.id = se.workoutExerciseId
        WHERE we.exerciseId = :exerciseId
            AND we.sessionId != :sessionId
        """
    )
    suspend fun getExerciseMaxWeightExcludingSession(exerciseId: Long, sessionId: Long): Double?
}

