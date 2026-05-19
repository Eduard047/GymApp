package com.example.gymapp.data.repository

import androidx.room.withTransaction
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.ExerciseMuscleMappingEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.TrainingProfile
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import org.json.JSONArray
import org.json.JSONObject

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

data class BackupOwner(
    val accountId: String? = null,
    val userId: String? = null,
    val email: String? = null,
    val remote: Boolean = false
)

data class SyncProfileStats(
    val xp: Int,
    val level: Int,
    val workouts: Int
)

class GymRepository(
    private val database: GymDatabase
) {
    private val exerciseDao = database.exerciseDao()
    private val workoutDao = database.workoutDao()
    private val setDao = database.setDao()
    private val muscleMappingDao = database.muscleMappingDao()

    fun observeExercises(): Flow<List<ExerciseEntity>> = exerciseDao.getExercises()
        .catch { emit(emptyList()) }

    suspend fun addExercise(name: String): Long {
        return exerciseDao.insert(ExerciseEntity(name = name.trim()))
    }

    suspend fun updateExercise(exercise: ExerciseEntity) {
        exerciseDao.update(exercise)
    }

    suspend fun renameExercise(exercise: ExerciseEntity, newName: String) {
        val cleanedName = newName.trim()
        require(cleanedName.isNotBlank())

        val existing = exerciseDao.getByName(cleanedName)
        require(existing == null || existing.id == exercise.id)

        val oldKey = exercise.name.toExerciseMappingKey()
        val newKey = cleanedName.toExerciseMappingKey()
        val now = System.currentTimeMillis()

        database.withTransaction {
            val oldMappings = muscleMappingDao.getForExercise(oldKey)
            exerciseDao.update(exercise.copy(name = cleanedName))

            if (oldKey == newKey) {
                muscleMappingDao.updateExerciseName(
                    exerciseNameKey = oldKey,
                    exerciseName = cleanedName,
                    updatedAt = now
                )
            } else if (oldMappings.isNotEmpty()) {
                muscleMappingDao.deleteForExercise(oldKey)
                muscleMappingDao.insertAll(
                    oldMappings.map { mapping ->
                        mapping.copy(
                            exerciseNameKey = newKey,
                            exerciseName = cleanedName,
                            updatedAt = now
                        )
                    }
                )
            }
        }
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

    suspend fun getWorkoutTemplate(sessionId: Long): WorkoutSessionDetails? {
        return workoutDao.getSessionDetailsSnapshot(sessionId)?.let(::sortSessionDetails)
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

    fun observeAllExerciseHistory(): Flow<List<ExerciseHistoryEntry>> {
        return workoutDao.getAllExerciseHistory()
            .catch { emit(emptyList()) }
    }

    fun observeExerciseMuscleMappings(): Flow<List<ExerciseMuscleMappingEntity>> {
        return muscleMappingDao.observeMappings()
            .catch { emit(emptyList()) }
    }

    suspend fun saveExerciseMuscleMapping(
        exerciseName: String,
        muscleIds: List<String>
    ) {
        val cleanedName = exerciseName.trim()
        if (cleanedName.isBlank()) return

        val exerciseNameKey = cleanedName.toExerciseMappingKey()
        val now = System.currentTimeMillis()
        val mappings = muscleIds
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .distinct()
            .map { muscleId ->
                ExerciseMuscleMappingEntity(
                    exerciseNameKey = exerciseNameKey,
                    exerciseName = cleanedName,
                    muscleId = muscleId,
                    weight = 1.0,
                    updatedAt = now
                )
            }

        database.withTransaction {
            muscleMappingDao.deleteForExercise(exerciseNameKey)
            if (mappings.isNotEmpty()) {
                muscleMappingDao.insertAll(mappings)
            }
        }
    }

    suspend fun exportBackupJson(
        includeDiagnostics: Boolean = false,
        owner: BackupOwner? = null
    ): String {
        return buildBackupJson(includeDiagnostics = includeDiagnostics, owner = owner).toString(2)
    }

    suspend fun buildBackupJson(
        includeDiagnostics: Boolean = false,
        owner: BackupOwner? = null
    ): JSONObject {
        val exercises = exerciseDao.getExercisesSnapshot()
        val sessions = workoutDao.getAllSessionDetailsForBackup().map(::sortSessionDetails)
        val root = JSONObject()
            .put("schemaVersion", 2)
            .put("exportedAt", System.currentTimeMillis())
            .put("app", "GymApp")
            .put("diagnostics", includeDiagnostics)
            .put("owner", JSONObject().apply {
                put("accountId", owner?.accountId)
                put("userId", owner?.userId)
                put("email", owner?.email)
                put("remote", owner?.remote ?: false)
            })
            .put("exercises", JSONArray().apply {
                exercises.forEach { exercise ->
                    put(
                        JSONObject()
                            .put("name", exercise.name)
                    )
                }
            })
            .put("sessions", JSONArray().apply {
                sessions.forEach { sessionDetails ->
                    put(
                        JSONObject()
                            .put("date", sessionDetails.session.date)
                            .put("note", sessionDetails.session.note)
                            .put("exercises", JSONArray().apply {
                                sessionDetails.workoutExercises.forEach { workoutExercise ->
                                    put(
                                        JSONObject()
                                            .put("name", workoutExercise.exercise.name)
                                            .put("sets", JSONArray().apply {
                                                workoutExercise.sets.forEach { set ->
                                                    put(
                                                        JSONObject()
                                                            .put("weight", set.weight)
                                                            .put("reps", set.reps)
                                                    )
                                                }
                                            })
                                    )
                                }
                            })
                    )
                }
            })

        val setCount = sessions.sumOf { session ->
            session.workoutExercises.sumOf { exercise -> exercise.sets.size }
        }
        val totalVolume = sessions.sumOf { session ->
            session.workoutExercises.sumOf { exercise ->
                exercise.sets.sumOf { set -> set.weight * set.reps }
            }
        }
        root.put(
            "summary",
            JSONObject()
                .put("exerciseCount", exercises.size)
                .put("sessionCount", sessions.size)
                .put("setCount", setCount)
                .put("totalVolume", totalVolume)
        )

        return root
    }

    suspend fun getSyncProfileStats(): SyncProfileStats {
        val sessions = workoutDao.getAllSessionDetailsForBackup().map(::sortSessionDetails)
        val summaries = sessions.map { details ->
            WorkoutSessionSummary(
                session = details.session,
                exerciseCount = details.workoutExercises.size,
                setCount = details.workoutExercises.sumOf { it.sets.size },
                totalVolume = details.workoutExercises.sumOf { exercise ->
                    exercise.sets.sumOf { set -> set.weight * set.reps }
                }
            )
        }
        val xp = summaries.sumOf { session ->
            90 + session.exerciseCount * 16 + session.setCount * 8 + (session.totalVolume / 80.0).roundToInt()
        }
        val level = calculateSyncLevel(xp)
        return SyncProfileStats(
            xp = xp,
            level = level,
            workouts = summaries.size
        )
    }

    private fun calculateSyncLevel(totalXp: Int): Int {
        var level = 1
        var remainingXp = totalXp
        var xpForNextLevel = syncXpRequirementForLevel(level)
        while (remainingXp >= xpForNextLevel) {
            remainingXp -= xpForNextLevel
            level += 1
            xpForNextLevel = syncXpRequirementForLevel(level)
        }
        return level
    }

    private fun syncXpRequirementForLevel(level: Int): Int {
        val stage = (level - 1).coerceAtLeast(0)
        return 200 + (stage * 85) + ((stage * stage) * 8)
    }

    suspend fun importBackupJson(
        rawJson: String,
        activeAccountId: String? = null,
        activeUserId: String? = null,
        activeRemote: Boolean = false
    ): Int {
        val root = JSONObject(rawJson)
        validateBackupOwner(root, activeAccountId, activeUserId, activeRemote)
        return importBackupJsonObject(root, activeAccountId, activeUserId, activeRemote)
    }

    suspend fun importBackupJsonObject(
        root: JSONObject,
        activeAccountId: String? = null,
        activeUserId: String? = null,
        activeRemote: Boolean = false
    ): Int {
        validateBackupOwner(root, activeAccountId, activeUserId, activeRemote)
        val sessions = root.optJSONArray("sessions") ?: JSONArray()
        val exercises = root.optJSONArray("exercises") ?: JSONArray()
        var importedSessions = 0

        database.withTransaction {
            val existingSignatures = workoutDao.getAllSessionDetailsForBackup()
                .map(::sortSessionDetails)
                .map(::sessionImportSignature)
                .toMutableSet()

            repeat(exercises.length()) { index ->
                val name = exercises.optJSONObject(index)
                    ?.optString("name")
                    ?.trim()
                    .orEmpty()
                if (name.isNotBlank() && exerciseDao.getByName(name) == null) {
                    exerciseDao.insert(ExerciseEntity(name = name))
                }
            }

            repeat(sessions.length()) { sessionIndex ->
                val sessionJson = sessions.optJSONObject(sessionIndex) ?: return@repeat
                val exerciseJsonArray = sessionJson.optJSONArray("exercises")
                val flatSetJsonArray = sessionJson.optJSONArray("sets")
                val drafts = mutableListOf<WorkoutExerciseDraft>()

                if (exerciseJsonArray != null) {
                    repeat(exerciseJsonArray.length()) { exerciseIndex ->
                        val exerciseJson = exerciseJsonArray.optJSONObject(exerciseIndex) ?: return@repeat
                        val exerciseName = exerciseJson.optString("name").trim()
                        if (exerciseName.isBlank()) return@repeat

                        val exerciseId = exerciseDao.getByName(exerciseName)?.id
                            ?: exerciseDao.insert(ExerciseEntity(name = exerciseName))
                        val setJsonArray = exerciseJson.optJSONArray("sets") ?: JSONArray()
                        val sets = mutableListOf<WorkoutSetDraft>()
                        repeat(setJsonArray.length()) { setIndex ->
                            val setJson = setJsonArray.optJSONObject(setIndex) ?: return@repeat
                            val weight = setJson.optDouble("weight", 0.0).coerceAtLeast(0.0)
                            val reps = setJson.optInt("reps", 0).coerceAtLeast(0)
                            if (reps > 0) {
                                sets += WorkoutSetDraft(weight = weight, reps = reps)
                            }
                        }
                        if (sets.isNotEmpty()) {
                            drafts += WorkoutExerciseDraft(
                                exerciseId = exerciseId,
                                sets = sets
                            )
                        }
                    }
                } else if (flatSetJsonArray != null) {
                    val grouped = linkedMapOf<String, MutableList<WorkoutSetDraft>>()
                    repeat(flatSetJsonArray.length()) { setIndex ->
                        val setJson = flatSetJsonArray.optJSONObject(setIndex) ?: return@repeat
                        val exerciseName = setJson.optString("exerciseName").trim()
                            .ifBlank { setJson.optString("name").trim() }
                        val reps = setJson.optInt("reps", 0).coerceAtLeast(0)
                        if (exerciseName.isNotBlank() && reps > 0) {
                            grouped.getOrPut(exerciseName) { mutableListOf() } += WorkoutSetDraft(
                                weight = setJson.optDouble("weight", 0.0).coerceAtLeast(0.0),
                                reps = reps
                            )
                        }
                    }
                    grouped.forEach { (exerciseName, sets) ->
                        val exerciseId = exerciseDao.getByName(exerciseName)?.id
                            ?: exerciseDao.insert(ExerciseEntity(name = exerciseName))
                        drafts += WorkoutExerciseDraft(exerciseId = exerciseId, sets = sets)
                    }
                }

                if (drafts.isNotEmpty()) {
                    val sessionDate = sessionJson.optLong(
                        "date",
                        sessionJson.optLong("startedAt", System.currentTimeMillis())
                    )
                    val sessionNote = sessionJson.optString("note").takeIf { it.isNotBlank() }
                    val signature = sessionImportSignature(sessionDate, sessionNote, drafts)
                    if (existingSignatures.add(signature)) {
                        createWorkoutSession(
                            date = sessionDate,
                            note = sessionNote,
                            workoutExercises = drafts
                        )
                        importedSessions += 1
                    }
                }
            }
        }

        return importedSessions
    }

    private fun validateBackupOwner(
        root: JSONObject,
        activeAccountId: String?,
        activeUserId: String?,
        activeRemote: Boolean
    ) {
        val owner = root.optJSONObject("owner") ?: return
        val backupUserId = owner.optString("userId").takeIf { it.isNotBlank() && it != "null" }
        val backupAccountId = owner.optString("accountId").takeIf { it.isNotBlank() && it != "null" }
        if (activeRemote) {
            require(backupUserId == null || backupUserId == activeUserId) {
                "This backup belongs to another account."
            }
        } else {
            require(backupUserId == null && (backupAccountId == null || backupAccountId == activeAccountId)) {
                "This backup belongs to another account."
            }
        }
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

    fun observeWorkoutRecommendations(
        exerciseIds: List<Long>,
        trainingProfile: TrainingProfile
    ): Flow<Map<Long, WorkoutRecommendation>> {
        val uniqueIds = exerciseIds.distinct()
        if (uniqueIds.isEmpty()) {
            return flowOf(emptyMap())
        }

        val flows = uniqueIds.map { exerciseId ->
            observeExerciseHistory(exerciseId).map { history ->
                exerciseId to WorkoutRecommendationEngine.buildForExercise(
                    exerciseId = exerciseId,
                    history = history,
                    trainingProfile = trainingProfile
                )
            }
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

    private fun sessionImportSignature(details: WorkoutSessionDetails): String {
        return sessionImportSignature(
            date = details.session.date,
            note = details.session.note,
            workoutExercises = details.workoutExercises
                .sortedBy { it.workoutExercise.orderIndex }
                .map { exercise ->
                    WorkoutExerciseDraft(
                        exerciseId = exercise.exercise.id,
                        sets = exercise.sets.sortedBy { it.orderIndex }.map { set ->
                            WorkoutSetDraft(weight = set.weight, reps = set.reps)
                        }
                    )
                }
        )
    }

    private fun sessionImportSignature(
        date: Long,
        note: String?,
        workoutExercises: List<WorkoutExerciseDraft>
    ): String {
        return buildString {
            append(date)
            append('|')
            append(note.orEmpty().trim())
            workoutExercises.forEach { exercise ->
                append('|')
                append(exercise.exerciseId)
                exercise.sets.forEach { set ->
                    append(':')
                    append(set.weight)
                    append('x')
                    append(set.reps)
                }
            }
        }
    }
}

private fun String.toExerciseMappingKey(): String {
    return lowercase(Locale.ROOT)
        .replace('ʼ', '\'')
        .replace('’', '\'')
        .replace(Regex("\\s+"), " ")
        .trim()
}

