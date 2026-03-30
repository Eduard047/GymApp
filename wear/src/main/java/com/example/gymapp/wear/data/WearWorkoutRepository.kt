package com.example.gymapp.wear.data

import androidx.room.withTransaction
import com.example.gymapp.wear.data.db.WearDatabase
import com.example.gymapp.wear.data.entity.WearSetEntryEntity
import com.example.gymapp.wear.data.entity.WearWorkoutSessionEntity
import com.example.gymapp.wear.sync.SyncedSessionPayload
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

data class WearWorkoutSetDraft(
    val exerciseName: String,
    val weight: Double,
    val reps: Int
)

data class WearSetUiModel(
    val id: Long,
    val sessionId: Long,
    val exerciseName: String,
    val weight: Double,
    val reps: Int,
    val orderIndex: Int
)

data class WearWorkoutSessionUiModel(
    val id: Long,
    val startedAt: Long,
    val note: String?,
    val sets: List<WearSetUiModel>
) {
    val setCount: Int get() = sets.size
    val totalVolume: Double get() = sets.sumOf { it.weight * it.reps }
}

class WearWorkoutRepository(
    private val database: WearDatabase
) {
    private val workoutDao = database.workoutDao()

    fun observeWorkoutSessions(): Flow<List<WearWorkoutSessionUiModel>> {
        return workoutDao.observeSessionsWithSets().map { sessions ->
            sessions.map { relation ->
                WearWorkoutSessionUiModel(
                    id = relation.session.id,
                    startedAt = relation.session.startedAt,
                    note = relation.session.note,
                    sets = relation.sets.sortedBy { it.orderIndex }.map { set ->
                        WearSetUiModel(
                            id = set.id,
                            sessionId = set.sessionId,
                            exerciseName = set.exerciseName,
                            weight = set.weight,
                            reps = set.reps,
                            orderIndex = set.orderIndex
                        )
                    }
                )
            }
        }
    }

    suspend fun createWorkout(
        startedAt: Long,
        note: String?,
        sets: List<WearWorkoutSetDraft>
    ): Long {
        return database.withTransaction {
            val sessionId = workoutDao.insertSession(
                WearWorkoutSessionEntity(
                    startedAt = startedAt,
                    note = note?.trim().orEmpty().ifBlank { null }
                )
            )

            val entities = sets.mapIndexed { index, draft ->
                WearSetEntryEntity(
                    sessionId = sessionId,
                    exerciseName = draft.exerciseName.trim(),
                    weight = draft.weight,
                    reps = draft.reps,
                    orderIndex = index
                )
            }
            workoutDao.insertSets(entities)
            sessionId
        }
    }

    suspend fun updateSet(set: WearSetUiModel) {
        workoutDao.updateSet(
            WearSetEntryEntity(
                id = set.id,
                sessionId = set.sessionId,
                exerciseName = set.exerciseName.trim(),
                weight = set.weight,
                reps = set.reps,
                orderIndex = set.orderIndex
            )
        )
    }

    suspend fun deleteSet(setId: Long) {
        if (setId <= 0) return

        database.withTransaction {
            val sessionId = workoutDao.getSessionIdBySetId(setId) ?: return@withTransaction
            workoutDao.deleteSetById(setId)
            val remaining = workoutDao.getSetCountForSession(sessionId)
            if (remaining == 0) {
                workoutDao.deleteSessionById(sessionId)
            }
        }
    }

    suspend fun replaceSessionsFromSync(sessions: List<SyncedSessionPayload>) {
        database.withTransaction {
            workoutDao.clearSets()
            workoutDao.clearSessions()

            if (sessions.isEmpty()) {
                return@withTransaction
            }

            workoutDao.insertSessions(
                sessions.map { session ->
                    WearWorkoutSessionEntity(
                        id = session.id,
                        startedAt = session.startedAt,
                        note = session.note
                    )
                }
            )

            workoutDao.insertSets(
                sessions.flatMap { session ->
                    session.sets.map { set ->
                        WearSetEntryEntity(
                            id = set.id,
                            sessionId = session.id,
                            exerciseName = set.exerciseName,
                            weight = set.weight,
                            reps = set.reps,
                            orderIndex = set.orderIndex
                        )
                    }
                }
            )
        }
    }
}
