package com.example.gymapp.data.repository

import androidx.room.withTransaction
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.dao.ExerciseDeletionCascadeRow
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.entity.AppMetadataEntity
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseLoadProfileEntity
import com.example.gymapp.data.entity.ExerciseWeightOptionEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.ExerciseMuscleMappingEntity
import com.example.gymapp.data.entity.GarminWorkoutReceiptEntity
import com.example.gymapp.data.entity.GarminWorkoutProvenanceEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.TrainingProfile
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
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

enum class GarminWorkoutApplyResult {
    Applied,
    AlreadyApplied,
    RateLimited,
    PairingLimitReached,
    Rejected
}

internal const val MAX_GARMIN_WORKOUTS_PER_PAIRING_GENERATION = 256
internal const val MAX_GARMIN_WORKOUTS_PER_ROLLING_DAY = 6
internal const val MAX_LEGACY_GARMIN_RECEIPTS_WITHIN_HORIZON =
    MAX_GARMIN_WORKOUTS_PER_ROLLING_DAY * 90
internal const val MAX_GARMIN_DURABLE_RECEIPTS =
    GymDatabase.LEGACY_GARMIN_RECEIPT_LIMIT + MAX_LEGACY_GARMIN_RECEIPTS_WITHIN_HORIZON +
        MAX_GARMIN_WORKOUTS_PER_PAIRING_GENERATION
internal const val GARMIN_WORKOUT_RATE_WINDOW_MS = 24L * 60L * 60L * 1_000L
internal const val LEGACY_GARMIN_RECEIPT_HORIZON_MS = 90L * GARMIN_WORKOUT_RATE_WINDOW_MS
private const val MIGRATED_LEGACY_GARMIN_GENERATION =
    "0000000000000000000000000000000000000000000000000000000000000000"
private const val LEGACY_GARMIN_FALLBACK_GENERATION =
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

/**
 * Collision-resistant identity for import de-duplication.
 *
 * Every variable-length value has an explicit presence/length marker and every numeric value is
 * encoded at a fixed width. Notes and signed zero are normalized exactly as persistence treats
 * them. This prevents an imported note from imitating the delimiters that separate exercise and
 * set fields without breaking idempotence after a save/re-import round trip.
 */
internal fun workoutImportSignature(
    date: Long,
    note: String?,
    workoutExercises: List<WorkoutExerciseDraft>
): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val numberBuffer = ByteBuffer.allocate(Long.SIZE_BYTES)

    fun updateLong(value: Long) {
        numberBuffer.clear()
        numberBuffer.putLong(value)
        digest.update(numberBuffer.array())
    }

    fun updateInt(value: Int) {
        updateLong(value.toLong())
    }

    fun updateNullableString(value: String?) {
        if (value == null) {
            digest.update(0.toByte())
            return
        }
        val utf8 = value.toByteArray(Charsets.UTF_8)
        digest.update(1.toByte())
        updateInt(utf8.size)
        digest.update(utf8)
    }

    digest.update("GymAppWorkoutImportSignatureV1".toByteArray(Charsets.UTF_8))
    updateLong(date)
    updateNullableString(note?.trim()?.takeIf { it.isNotEmpty() })
    updateInt(workoutExercises.size)
    workoutExercises.forEach { exercise ->
        updateLong(exercise.exerciseId)
        updateInt(exercise.sets.size)
        exercise.sets.forEach { set ->
            val canonicalWeight = if (set.weight == 0.0) 0.0 else set.weight
            updateLong(java.lang.Double.doubleToLongBits(canonicalWeight))
            updateInt(set.reps)
        }
    }
    return digest.digest().joinToString(separator = "") { byte -> "%02x".format(byte) }
}

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

/** Exact exercise identity and cascade impact shown to the user before deletion. */
data class ExerciseDeletionSnapshot(
    val exerciseId: Long,
    val exerciseName: String,
    val isFavorite: Boolean,
    val workoutCount: Int,
    val exerciseBlockCount: Int,
    val setCount: Int,
    val cascadeFingerprint: String,
    val deletionStoreToken: String
)

/** Highest-level row that cleanup removes after deleting the selected set. */
enum class SetDeletionImpact {
    SetOnly,
    ExerciseBlock,
    WorkoutSession
}

/** Exact set identity, display context, and cleanup impact shown before deletion. */
data class SetDeletionSnapshot(
    val setId: Long,
    val workoutExerciseId: Long,
    val workoutSessionId: Long,
    val exerciseId: Long,
    val exerciseName: String,
    val sessionDate: Long,
    val weight: Double,
    val reps: Int,
    val orderIndex: Int,
    val displayOrdinal: Int,
    val setsInExerciseBlock: Int,
    val exerciseBlocksInWorkout: Int,
    val impact: SetDeletionImpact,
    val removedWorkoutExercise: WorkoutExerciseEntity?,
    val removedWorkoutSession: WorkoutSessionEntity?,
    val removedGarminProvenance: GarminWorkoutProvenanceEntity?,
    val deletionStoreToken: String
)

data class CloudWorkoutProjectionState internal constructor(
    val digest: String,
    val catalogSeedVersion: Int,
    val exerciseCount: Int,
    val customExerciseCount: Int,
    val sessionCount: Int,
    val workoutExerciseCount: Int,
    val setCount: Int
) {
    val isEmpty: Boolean
        get() = customExerciseCount == 0 &&
            sessionCount == 0 &&
            workoutExerciseCount == 0 &&
            setCount == 0
}

class GymRepository(
    private val database: GymDatabase,
    private val currentTimeMillis: () -> Long = System::currentTimeMillis
) {
    private val exerciseDao = database.exerciseDao()
    private val exerciseLoadProfileDao = database.exerciseLoadProfileDao()
    private val appMetadataDao = database.appMetadataDao()
    private val workoutDao = database.workoutDao()
    private val setDao = database.setDao()
    private val muscleMappingDao = database.muscleMappingDao()
    private val garminWorkoutReceiptDao = database.garminWorkoutReceiptDao()
    private val deletionStoreToken = UUID.randomUUID().toString()

    fun observeExercises(): Flow<List<ExerciseEntity>> = exerciseDao.getExercises()
        .catch { emit(emptyList()) }

    fun observeExerciseLoadProfiles(): Flow<Map<Long, ExerciseLoadProfile>> = combine(
        exerciseLoadProfileDao.observeProfiles(),
        exerciseLoadProfileDao.observeWeightOptions()
    ) { profiles, options ->
        loadProfileMap(profiles, options, rejectInvalid = false)
    }.catch { emit(emptyMap()) }

    suspend fun saveExerciseLoadProfile(
        exerciseId: Long,
        profile: ExerciseLoadProfile?
    ) = database.withTransaction {
        require(exerciseId > 0L && exerciseDao.getById(exerciseId) != null) {
            "Exercise no longer exists."
        }
        replaceExerciseLoadProfile(exerciseId, profile)
    }

    /** Clears every Room table only after the matching remote account deletion succeeded. */
    suspend fun clearAllAccountData() = withContext(Dispatchers.IO) {
        database.clearAllTables()
    }

    /**
     * Makes the versioned app catalog available in every account database without replacing
     * custom rows or workout history. Recognized legacy aliases satisfy the same catalog key.
     */
    suspend fun seedBuiltInExercises(): Int = database.withTransaction {
        val currentSeedVersion = (appMetadataDao.getCatalogSeedVersion() ?: 0).coerceAtLeast(0)
        if (currentSeedVersion >= BuiltInExerciseCatalog.SEED_VERSION) {
            return@withTransaction 0
        }
        val pendingDefinitions = BuiltInExerciseCatalog.definitions.filter {
            it.introducedInSeedVersion > currentSeedVersion
        }
        val existing = exerciseDao.getExercisesSnapshot()
        val existingCatalogKeys = existing.mapNotNull { exercise ->
            BuiltInExerciseCatalog.inferKey(exercise.name)
        }.toMutableSet()
        var currentCount = existing.size
        var inserted = 0

        pendingDefinitions.forEach { definition ->
            if (definition.key in existingCatalogKeys) return@forEach
            // A full legacy account must remain usable. Leave the marker unset so a later
            // deletion can make room for the remaining catalog items on a future retry.
            if (currentCount >= WorkoutDataLimits.MAX_EXERCISES) return@forEach
            exerciseDao.insert(ExerciseEntity(name = definition.nameEn))
            existingCatalogKeys += definition.key
            currentCount += 1
            inserted += 1
        }
        if (pendingDefinitions.all { it.key in existingCatalogKeys }) {
            appMetadataDao.upsert(
                AppMetadataEntity(catalogSeedVersion = BuiltInExerciseCatalog.SEED_VERSION)
            )
        }
        inserted
    }

    suspend fun addExercise(name: String): Long {
        require(name.length <= WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2) {
            "Exercise name is outside the supported length."
        }
        val cleanedName = name.trim()
        require(WorkoutDataLimits.isValidExerciseName(cleanedName)) {
            "Exercise name is outside the supported length."
        }
        return database.withTransaction {
            val existingExercises = exerciseDao.getExercisesSnapshot()
            require(existingExercises.size < WorkoutDataLimits.MAX_EXERCISES) {
                "This account has reached the exercise limit."
            }
            require(
                existingExercises.none { existing ->
                    exerciseNamesConflict(existing.name, cleanedName)
                }
            )
            exerciseDao.insert(ExerciseEntity(name = cleanedName))
        }
    }

    suspend fun updateExercise(exercise: ExerciseEntity) {
        require(exercise.name.length <= WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2) {
            "Exercise name is outside the supported length."
        }
        require(WorkoutDataLimits.isValidExerciseName(exercise.name.trim())) {
            "Exercise name is outside the supported length."
        }
        exerciseDao.update(exercise)
    }

    suspend fun renameExercise(exercise: ExerciseEntity, newName: String) {
        require(BuiltInExerciseCatalog.inferKey(exercise.name) == null) {
            "Built-in exercises cannot be renamed."
        }
        require(newName.length <= WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2) {
            "Exercise name is outside the supported length."
        }
        val cleanedName = newName.trim()
        require(WorkoutDataLimits.isValidExerciseName(cleanedName)) {
            "Exercise name is outside the supported length."
        }

        require(
            exerciseDao.getExercisesSnapshot().none { existing ->
                existing.id != exercise.id && exerciseNamesConflict(existing.name, cleanedName)
            }
        )

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

    suspend fun setExerciseFavorite(exerciseId: Long, isFavorite: Boolean) {
        require(exerciseId > 0) { "Exercise identifier is invalid." }
        check(exerciseDao.setFavorite(exerciseId, isFavorite) == 1) {
            "Exercise no longer exists."
        }
    }

    suspend fun toggleExerciseFavorite(exerciseId: Long) {
        require(exerciseId > 0) { "Exercise identifier is invalid." }
        check(exerciseDao.toggleFavorite(exerciseId) == 1) {
            "Exercise no longer exists."
        }
    }

    suspend fun deleteExercise(exercise: ExerciseEntity) {
        exerciseDao.delete(exercise)
    }

    suspend fun getExerciseDeletionSnapshot(exerciseId: Long): ExerciseDeletionSnapshot? {
        if (exerciseId <= 0) return null
        return database.withTransaction {
            exerciseDeletionSnapshot(exerciseId)
        }
    }

    suspend fun deleteExerciseIfUnchanged(expected: ExerciseDeletionSnapshot): Boolean {
        if (expected.exerciseId <= 0 || expected.deletionStoreToken != deletionStoreToken) {
            return false
        }
        return database.withTransaction {
            if (exerciseDeletionSnapshot(expected.exerciseId) != expected) {
                return@withTransaction false
            }
            val deletedRows = exerciseDao.deleteIfUnchanged(
                exerciseId = expected.exerciseId,
                expectedName = expected.exerciseName,
                expectedFavorite = expected.isFavorite
            )
            deletedRows == 1 && exerciseDao.getById(expected.exerciseId) == null
        }
    }

    private suspend fun exerciseDeletionSnapshot(exerciseId: Long): ExerciseDeletionSnapshot? {
        val exercise = exerciseDao.getById(exerciseId) ?: return null
        val cascadeRows = workoutDao.getExerciseDeletionCascadeRows(exercise.id)
        return ExerciseDeletionSnapshot(
            exerciseId = exercise.id,
            exerciseName = exercise.name,
            isFavorite = exercise.isFavorite,
            workoutCount = cascadeRows.mapTo(linkedSetOf()) { it.workoutSessionId }.size,
            exerciseBlockCount = cascadeRows.mapTo(linkedSetOf()) { it.workoutExerciseId }.size,
            setCount = cascadeRows.count { it.setId != null },
            cascadeFingerprint = exerciseDeletionCascadeFingerprint(cascadeRows),
            deletionStoreToken = deletionStoreToken
        )
    }

    private fun exerciseDeletionCascadeFingerprint(
        rows: List<ExerciseDeletionCascadeRow>
    ): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteBuffer.allocate(Long.SIZE_BYTES)

        fun updateLong(value: Long) {
            buffer.clear()
            buffer.putLong(value)
            digest.update(buffer.array())
        }

        fun updateInt(value: Int) = updateLong(value.toLong())

        fun updateNullableLong(value: Long?) {
            if (value == null) {
                digest.update(0.toByte())
            } else {
                digest.update(1.toByte())
                updateLong(value)
            }
        }

        fun updateNullableInt(value: Int?) {
            if (value == null) {
                digest.update(0.toByte())
            } else {
                digest.update(1.toByte())
                updateInt(value)
            }
        }

        fun updateNullableDouble(value: Double?) {
            if (value == null) {
                digest.update(0.toByte())
            } else {
                digest.update(1.toByte())
                updateLong(java.lang.Double.doubleToRawLongBits(value))
            }
        }

        digest.update("GymAppExerciseDeletionCascadeV2".toByteArray(Charsets.UTF_8))
        updateInt(rows.size)
        rows.forEach { row ->
            updateLong(row.workoutExerciseId)
            updateLong(row.workoutSessionId)
            updateLong(row.workoutExerciseExerciseId)
            updateInt(row.workoutExerciseOrderIndex)
            updateNullableLong(row.setId)
            updateNullableLong(row.setWorkoutExerciseId)
            updateNullableDouble(row.setWeight)
            updateNullableInt(row.setReps)
            updateNullableInt(row.setOrderIndex)
        }
        return digest.digest().joinToString(separator = "") { byte -> "%02x".format(byte) }
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
            val sessionTimestamps = allSessions.map { it.session.date }
            val weeklyStreakWeeks = if (monthOffset == 0) {
                WeeklyStreakCalculator.current(
                    sessionTimestamps = sessionTimestamps,
                    nowMillis = System.currentTimeMillis(),
                    zoneId = ZoneId.systemDefault()
                )
            } else {
                WeeklyStreakCalculator.bestDuringPeriod(
                    sessionTimestamps = sessionTimestamps,
                    periodStartMillis = start,
                    periodEndMillis = end,
                    zoneId = ZoneId.systemDefault()
                )
            }
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

    suspend fun seedDefaultExerciseMuscleMappings() {
        val now = System.currentTimeMillis()
        database.withTransaction {
            val existingKeys = muscleMappingDao.getMappingsSnapshot()
                .map { it.exerciseNameKey }
                .toSet()
            val seedMappings = exerciseDao.getExercisesSnapshot()
                .filter { exercise -> exercise.name.toExerciseMappingKey() !in existingKeys }
                .flatMap { exercise ->
                    val key = exercise.name.toExerciseMappingKey()
                    defaultContributionsForExercise(exercise.name).map { contribution ->
                        ExerciseMuscleMappingEntity(
                            exerciseNameKey = key,
                            exerciseName = exercise.name,
                            muscleId = contribution.muscleId,
                            weight = contribution.weight,
                            updatedAt = now
                        )
                    }
                }
            if (seedMappings.isNotEmpty()) {
                muscleMappingDao.insertAll(seedMappings)
            }
        }
    }

    suspend fun saveExerciseMuscleMapping(
        exerciseName: String,
        muscleIds: List<String>
    ) {
        require(exerciseName.length <= WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2) {
            "Exercise name is outside the supported length."
        }
        val cleanedName = exerciseName.trim()
        if (cleanedName.isBlank()) return
        require(WorkoutDataLimits.isValidExerciseName(cleanedName)) {
            "Exercise name is outside the supported length."
        }
        require(muscleIds.size <= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
            "Exercise mapping exceeds the muscle limit."
        }
        require(muscleIds.all { it.length <= WorkoutDataLimits.MAX_CATALOG_KEY_LENGTH }) {
            "Muscle identifier exceeds the length limit."
        }

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
    ): String = withContext(Dispatchers.Default) {
        val serialized = buildBackupJson(
            includeDiagnostics = includeDiagnostics,
            owner = owner
        ).toString(2)
        // Validate the exact representation retained by the UI and shared with other apps.
        // Pretty-print whitespace can be material at the account-wide row limits.
        WorkoutDataLimits.requireSafeJsonEnvelope(serialized)
        serialized
    }

    /**
     * Produces a deliberately content-free support snapshot.
     *
     * Account identifiers, exercise names, notes, dates, set values, and raw database rows are
     * excluded. A user can share this aggregate safely without accidentally sharing a backup.
     */
    suspend fun exportDiagnosticsJson(): String = withContext(Dispatchers.Default) {
        val summary = database.withTransaction {
            JSONObject()
                .put("exerciseCount", exerciseDao.getExerciseCount())
                .put("sessionCount", workoutDao.getSessionCount())
                .put("setCount", setDao.getTotalSetCount())
        }
        val root = JSONObject()
            .put("schemaVersion", 1)
            .put("exportedAt", System.currentTimeMillis())
            .put("app", "GymApp")
            .put("diagnostics", true)
            .put("summary", summary)
        val serialized = root.toString(2)
        WorkoutDataLimits.requireSafeJsonEnvelope(serialized)
        serialized
    }

    suspend fun buildBackupJson(
        includeDiagnostics: Boolean = false,
        owner: BackupOwner? = null
    ): JSONObject = withContext(Dispatchers.Default) {
        val (catalogSeedVersion, exerciseRows, sessions) = database.withTransaction {
            val exerciseCount = exerciseDao.getExerciseCount()
            val sessionCount = workoutDao.getSessionCount()
            val workoutExerciseCount = workoutDao.getTotalWorkoutExerciseCount()
            val setCount = setDao.getTotalSetCount()
            require(exerciseCount <= WorkoutDataLimits.MAX_EXERCISES) {
                "Stored exercise data exceeds the safe export limit."
            }
            require(sessionCount <= WorkoutDataLimits.MAX_SESSIONS) {
                "Stored workout data exceeds the safe export limit."
            }
            require(setCount <= WorkoutDataLimits.MAX_TOTAL_SETS) {
                "Stored set data exceeds the safe export limit."
            }
            require(
                WorkoutDataLimits.isBackupProjectionWithinLimit(
                    exerciseCount = exerciseCount,
                    sessionCount = sessionCount,
                    workoutExerciseCount = workoutExerciseCount,
                    setCount = setCount,
                    textUtf8Bytes = workoutDao.getBackupTextUtf8Bytes()
                )
            ) { "Stored workout data exceeds the safe backup byte budget." }
            val loadProfiles = currentExerciseLoadProfiles(rejectInvalid = true)
            Triple(
                appMetadataDao.getCatalogSeedVersion() ?: 0,
                exerciseDao.getExercisesSnapshot().map { exercise ->
                    exercise to loadProfiles[exercise.id]
                },
                workoutDao.getAllSessionDetailsForBackup().map(::sortSessionDetails)
            )
        }
        val root = JSONObject()
            .put("schemaVersion", 2)
            .put("exportedAt", System.currentTimeMillis())
            .put("app", "GymApp")
            .put("diagnostics", includeDiagnostics)
            .put("catalogSeedVersion", catalogSeedVersion)
            .put("owner", JSONObject().apply {
                put("accountId", owner?.accountId)
                put("userId", owner?.userId)
                put("email", owner?.email)
                put("remote", owner?.remote ?: false)
            })
            .put("exercises", JSONArray().apply {
                exerciseRows.forEach { (exercise, loadProfile) ->
                    put(
                        exerciseBackupJson(exercise.name, loadProfile)
                            .put("favorite", exercise.isFavorite)
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
                                        exerciseBackupJson(workoutExercise.exercise.name)
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
                .put("exerciseCount", exerciseRows.size)
                .put("sessionCount", sessions.size)
                .put("setCount", setCount)
                .put("totalVolume", totalVolume)
        )

        // Enforce the same byte/depth envelope for generated cloud and manual
        // backups. Account-wide row counts were checked before materializing
        // relations above, so legacy over-limit databases fail early.
        WorkoutDataLimits.requireSafeJsonEnvelope(root.toString())

        root
    }

    /**
     * Builds the public cloud envelope understood by already-released clients.
     *
     * The catalog seed marker is local migration metadata and remains in manual backups, but
     * older Android releases require the canonical cloud root to keep its legacy eight keys.
     */
    suspend fun buildCloudBackupJson(owner: BackupOwner): JSONObject =
        buildBackupJson(owner = owner).apply {
            remove("catalogSeedVersion")
            optJSONArray("exercises")?.let { cloudExercises ->
                repeat(cloudExercises.length()) { index ->
                    cloudExercises.optJSONObject(index)?.remove("favorite")
                }
            }
        }

    suspend fun getSyncProfileStats(): SyncProfileStats {
        return withContext(Dispatchers.Default) {
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
            val xp = summaries.fold(0) { total, summary ->
                (total.toLong() + GamificationEngine.xpForSession(summary).toLong())
                    .coerceAtMost(Int.MAX_VALUE.toLong())
                    .toInt()
            }
            val level = GamificationEngine.levelForXp(xp)
            SyncProfileStats(
                xp = xp,
                level = level,
                workouts = summaries.size
            )
        }
    }

    suspend fun getCloudWorkoutProjectionState(): CloudWorkoutProjectionState =
        database.withTransaction { currentCloudWorkoutProjectionState() }

    suspend fun importBackupJson(
        rawJson: String,
        activeAccountId: String? = null,
        activeUserId: String? = null,
        activeRemote: Boolean = false
    ): Int = withContext(Dispatchers.Default) {
        WorkoutDataLimits.requireSafeJsonEnvelope(rawJson)
        val root = JSONObject(rawJson)
        importBackupJsonObject(root, activeAccountId, activeUserId, activeRemote)
    }

    suspend fun importBackupJsonObject(
        root: JSONObject,
        activeAccountId: String? = null,
        activeUserId: String? = null,
        activeRemote: Boolean = false
    ): Int = importBackupJsonObjectInternal(
        root = root,
        activeAccountId = activeAccountId,
        activeUserId = activeUserId,
        activeRemote = activeRemote,
        replaceExisting = false
    )

    /**
     * Replaces the account workout projection with an already-fetched authoritative snapshot.
     * Validation and owner binding happen before the transaction can delete any local rows.
     */
    suspend fun replaceWithBackupJsonObject(
        root: JSONObject,
        expectedLocalState: CloudWorkoutProjectionState,
        activeAccountId: String? = null,
        activeUserId: String? = null,
        activeRemote: Boolean = false
    ): Int = importBackupJsonObjectInternal(
        root = root,
        activeAccountId = activeAccountId,
        activeUserId = activeUserId,
        activeRemote = activeRemote,
        replaceExisting = true,
        expectedLocalState = expectedLocalState
    )

    private suspend fun importBackupJsonObjectInternal(
        root: JSONObject,
        activeAccountId: String?,
        activeUserId: String?,
        activeRemote: Boolean,
        replaceExisting: Boolean,
        expectedLocalState: CloudWorkoutProjectionState? = null
    ): Int = withContext(Dispatchers.Default) {
        val backup = BackupImportValidator.validate(root)
        validateBackupOwnerContext(root, activeAccountId, activeUserId, activeRemote)
        val expectedReplacementDigest = if (replaceExisting) {
            canonicalWorkoutPayloadDigest(backup)
        } else {
            null
        }
        var importedSessions = 0

        database.withTransaction {
            val retainedGarminProvenance = mutableMapOf<String, Int>()
            if (replaceExisting) {
                require(expectedLocalState != null)
                require(currentCloudWorkoutProjectionState() == expectedLocalState) {
                    "Local workout data changed while cloud state was loading. Automatic replacement is paused."
                }
                val provenanceSessionIds = database.garminWorkoutReceiptDao()
                    .getProvenanceSessionIds()
                    .toSet()
                workoutDao.getAllSessionDetailsForBackup()
                    .asSequence()
                    .filter { details -> details.session.id in provenanceSessionIds }
                    .map(::sortSessionDetails)
                    .map(::garminProvenanceSignature)
                    .forEach { signature ->
                        retainedGarminProvenance[signature] =
                            retainedGarminProvenance.getOrDefault(signature, 0) + 1
                    }
                // Foreign-key cascades remove workout_exercises and set_entries. Garmin replay
                // receipts deliberately remain intact so cloud replacement cannot reopen an old
                // request ID. Trusted provenance is reassociated below only when the authoritative
                // session is exactly equivalent under the canonical workout projection.
                workoutDao.deleteAllSessions()
                exerciseDao.deleteAllExercises()
            }
            val currentSeedVersion = appMetadataDao.getCatalogSeedVersion() ?: 0
            val restoredSeedVersion = if (replaceExisting) {
                if (root.has("catalogSeedVersion")) {
                    backup.catalogSeedVersion
                } else {
                    // The public cloud envelope predates the local seed marker. Preserve a
                    // completed local migration so later pulls do not resurrect a built-in
                    // exercise the user intentionally deleted.
                    expectedLocalState?.catalogSeedVersion ?: currentSeedVersion
                }
            } else {
                maxOf(currentSeedVersion, backup.catalogSeedVersion)
            }
            appMetadataDao.upsert(AppMetadataEntity(catalogSeedVersion = restoredSeedVersion))
            val existingExerciseCount = exerciseDao.getExerciseCount()
            var sessionCount = workoutDao.getSessionCount()
            var accountSetCount = setDao.getTotalSetCount()
            require(existingExerciseCount <= WorkoutDataLimits.MAX_EXERCISES) {
                "Stored exercise data exceeds the safe import limit."
            }
            require(sessionCount <= WorkoutDataLimits.MAX_SESSIONS) {
                "Stored workout data exceeds the safe import limit."
            }
            require(accountSetCount <= WorkoutDataLimits.MAX_TOTAL_SETS) {
                "Stored set data exceeds the safe import limit."
            }
            val existingExercises = exerciseDao.getExercisesSnapshot()
            val exerciseIdByNameKey = existingExercises
                .associate { exercise -> exercise.name.normalizedExerciseName() to exercise.id }
                .toMutableMap()
            val exerciseIdByCatalogKey = linkedMapOf<String, Long>().apply {
                existingExercises.forEach { exercise ->
                    BuiltInExerciseCatalog.inferKey(exercise.name)?.let { catalogKey ->
                        putIfAbsent(catalogKey, exercise.id)
                    }
                }
            }

            val prospectiveNameKeys = exerciseIdByNameKey.keys.toMutableSet()
            val prospectiveCatalogKeys = exerciseIdByCatalogKey.keys.toMutableSet()
            var prospectiveExerciseCount = existingExercises.size

            fun accountForImportedExercise(exercise: ValidatedBackupExercise) {
                val nameKey = exercise.name.normalizedExerciseName()
                if (nameKey in prospectiveNameKeys) return
                val catalogKey = BuiltInExerciseCatalog.resolvedKey(
                    catalogKey = exercise.catalogKey,
                    rawName = exercise.name
                )
                if (catalogKey != null && catalogKey in prospectiveCatalogKeys) return

                prospectiveExerciseCount += 1
                require(prospectiveExerciseCount <= WorkoutDataLimits.MAX_EXERCISES) {
                    "Backup exceeds the exercise limit for this account."
                }
                prospectiveNameKeys += nameKey
                if (catalogKey != null) prospectiveCatalogKeys += catalogKey
            }

            backup.exercises.forEach(::accountForImportedExercise)
            backup.sessions.forEach { session ->
                session.blocks.forEach { block -> accountForImportedExercise(block.exercise) }
            }

            suspend fun resolveImportedExercise(exercise: ValidatedBackupExercise): Long {
                val rawName = exercise.name
                val nameKey = rawName.normalizedExerciseName()
                exerciseIdByNameKey[nameKey]?.let { existingId ->
                    exercise.isFavorite?.let { favorite ->
                        check(exerciseDao.setFavorite(existingId, favorite) == 1)
                    }
                    exercise.loadProfile?.let { profile ->
                        replaceExerciseLoadProfile(existingId, profile)
                    }
                    return existingId
                }

                val catalogKey = BuiltInExerciseCatalog.resolvedKey(
                    catalogKey = exercise.catalogKey,
                    rawName = rawName
                )
                if (catalogKey != null) {
                    exerciseIdByCatalogKey[catalogKey]?.let { existingId ->
                        exercise.isFavorite?.let { favorite ->
                            check(exerciseDao.setFavorite(existingId, favorite) == 1)
                        }
                        exercise.loadProfile?.let { profile ->
                            replaceExerciseLoadProfile(existingId, profile)
                        }
                        return existingId
                    }
                }

                val exerciseId = exerciseDao.insert(
                    ExerciseEntity(
                        name = rawName,
                        isFavorite = exercise.isFavorite == true
                    )
                )
                exerciseIdByNameKey[nameKey] = exerciseId
                if (catalogKey != null) {
                    exerciseIdByCatalogKey.putIfAbsent(catalogKey, exerciseId)
                }
                exercise.loadProfile?.let { profile ->
                    replaceExerciseLoadProfile(exerciseId, profile)
                }
                return exerciseId
            }

            val existingSessions = workoutDao.getAllSessionDetailsForBackup()
            val existingSignatures = existingSessions
                .map(::sortSessionDetails)
                .map(::sessionImportSignature)
                .toMutableSet()

            backup.exercises.forEach { exercise -> resolveImportedExercise(exercise) }

            backup.sessions.forEach { session ->
                val drafts = if (replaceExisting) {
                    // Authoritative native snapshots must round-trip exactly. Room permits the
                    // same exercise in multiple ordered blocks and two semantically identical
                    // sessions; neither is a duplicate when restoring the server projection.
                    session.blocks.map { block ->
                        WorkoutExerciseDraft(
                            exerciseId = resolveImportedExercise(block.exercise),
                            sets = block.sets.map { set ->
                                WorkoutSetDraft(weight = set.weight, reps = set.reps)
                            }
                        )
                    }
                } else {
                    val setsByExerciseId = linkedMapOf<Long, MutableList<WorkoutSetDraft>>()
                    session.blocks.forEach { block ->
                        val exerciseId = resolveImportedExercise(block.exercise)
                        if (block.sets.isNotEmpty()) {
                            setsByExerciseId.getOrPut(exerciseId) { mutableListOf() }.addAll(
                                block.sets.map { set ->
                                    WorkoutSetDraft(weight = set.weight, reps = set.reps)
                                }
                            )
                        }
                    }

                    setsByExerciseId.map { (exerciseId, sets) ->
                        WorkoutExerciseDraft(exerciseId = exerciseId, sets = sets)
                    }
                }

                if (drafts.isNotEmpty()) {
                    val signature = workoutImportSignature(session.date, session.note, drafts)
                    if (replaceExisting || existingSignatures.add(signature)) {
                        require(sessionCount < WorkoutDataLimits.MAX_SESSIONS) {
                            "Backup exceeds the workout limit for this account."
                        }
                        requireValidWorkout(
                            date = session.date,
                            note = session.note,
                            workoutExercises = drafts
                        )
                        val incomingSetCount = drafts.sumOf { it.sets.size }
                        require(WorkoutDataLimits.canAddSets(accountSetCount, incomingSetCount)) {
                            "Backup exceeds the total set limit for this account."
                        }
                        val insertedSessionId = insertValidatedWorkoutSession(
                            date = session.date,
                            note = session.note,
                            workoutExercises = drafts
                        )
                        if (replaceExisting) {
                            val provenanceSignature = garminProvenanceSignature(session)
                            val remainingMatches =
                                retainedGarminProvenance[provenanceSignature] ?: 0
                            if (remainingMatches > 0) {
                                database.garminWorkoutReceiptDao().insertProvenance(
                                    GarminWorkoutProvenanceEntity(
                                        workoutSessionId = insertedSessionId
                                    )
                                )
                                if (remainingMatches == 1) {
                                    retainedGarminProvenance.remove(provenanceSignature)
                                } else {
                                    retainedGarminProvenance[provenanceSignature] =
                                        remainingMatches - 1
                                }
                            }
                        }
                        accountSetCount += incomingSetCount
                        sessionCount += 1
                        importedSessions += 1
                    }
                }
            }

            if (replaceExisting) {
                require(currentCloudWorkoutProjectionState().digest == expectedReplacementDigest) {
                    "Cloud state cannot be represented without loss. Local data was preserved."
                }
            }
        }

        importedSessions
    }

    /** Must be called from [database]'s transaction to make replacement compare-and-swap safe. */
    private suspend fun currentCloudWorkoutProjectionState(): CloudWorkoutProjectionState {
        val exerciseCount = exerciseDao.getExerciseCount()
        val sessionCount = workoutDao.getSessionCount()
        val workoutExerciseCount = workoutDao.getTotalWorkoutExerciseCount()
        val setCount = setDao.getTotalSetCount()
        require(exerciseCount in 0..WorkoutDataLimits.MAX_EXERCISES)
        require(sessionCount in 0..WorkoutDataLimits.MAX_SESSIONS)
        require(workoutExerciseCount in 0..WorkoutDataLimits.MAX_TOTAL_SETS)
        require(setCount in 0..WorkoutDataLimits.MAX_TOTAL_SETS)

        val exercises = exerciseDao.getExercisesSnapshot()
        val loadProfiles = currentExerciseLoadProfiles(rejectInvalid = true)
        val sessions = workoutDao.getAllSessionDetailsForBackup().map(::sortSessionDetails)
        val projection = ValidatedBackup(
            catalogSeedVersion = appMetadataDao.getCatalogSeedVersion() ?: 0,
            exercises = exercises.map { exercise ->
                ValidatedBackupExercise(
                    name = exercise.name,
                    catalogKey = BuiltInExerciseCatalog.inferKey(exercise.name),
                    loadProfile = loadProfiles[exercise.id]
                )
            },
            sessions = sessions.map { details ->
                ValidatedBackupSession(
                    date = details.session.date,
                    note = details.session.note,
                    blocks = details.workoutExercises.map { workoutExercise ->
                        ValidatedBackupBlock(
                            exercise = ValidatedBackupExercise(
                                name = workoutExercise.exercise.name,
                                catalogKey = BuiltInExerciseCatalog.inferKey(
                                    workoutExercise.exercise.name
                                )
                            ),
                            sets = workoutExercise.sets.map { set ->
                                ValidatedBackupSet(weight = set.weight, reps = set.reps)
                            }
                        )
                    }
                )
            }
        )
        return CloudWorkoutProjectionState(
            digest = canonicalWorkoutPayloadDigest(projection),
            catalogSeedVersion = projection.catalogSeedVersion,
            exerciseCount = exerciseCount,
            customExerciseCount = exercises.count { exercise ->
                BuiltInExerciseCatalog.inferKey(exercise.name) == null
            },
            sessionCount = sessionCount,
            workoutExerciseCount = workoutExerciseCount,
            setCount = setCount
        )
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
        trainingProfile: TrainingProfile,
        effort: SmartWorkoutEffort = SmartWorkoutEffort.Standard,
        hardExerciseIds: Set<Long> = emptySet()
    ): Flow<Map<Long, WorkoutRecommendation>> {
        val uniqueIds = exerciseIds.distinct()
        if (uniqueIds.isEmpty()) {
            return flowOf(emptyMap())
        }

        val flows = uniqueIds.map { exerciseId ->
            combine(
                observeExerciseHistory(exerciseId),
                observeExerciseLoadProfiles()
            ) { history, loadProfiles ->
                val exerciseName = exerciseDao.getById(exerciseId)?.name
                exerciseId to WorkoutRecommendationEngine.buildForExercise(
                    exerciseId = exerciseId,
                    history = history,
                    trainingProfile = trainingProfile,
                    exerciseName = exerciseName,
                    loadProfile = loadProfiles[exerciseId],
                    effort = effort,
                    hardSetEligible = exerciseId in hardExerciseIds
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
        requireValidWorkout(date = date, note = note, workoutExercises = workoutExercises)
        return database.withTransaction {
            require(workoutDao.getSessionCount() < WorkoutDataLimits.MAX_SESSIONS) {
                "This account has reached the workout limit."
            }
            val incomingSetCount = workoutExercises.sumOf { it.sets.size }
            require(WorkoutDataLimits.canAddSets(setDao.getTotalSetCount(), incomingSetCount)) {
                "This account has reached the total set limit."
            }
            insertValidatedWorkoutSession(date, note, workoutExercises)
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
        require(WorkoutDataLimits.isValidTimestamp(date)) {
            "Workout timestamp is outside the supported range."
        }
        require(WorkoutDataLimits.isValidNote(note)) { "Workout note exceeds the length limit." }
        require(sets.size <= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION * WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
            "Workout exceeds the set limit."
        }

        val normalizedSets = sets.map { set ->
            require(set.exerciseName.length <= WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2) {
                "Exercise name is outside the supported length."
            }
            val name = set.exerciseName.trim()
            require(WorkoutDataLimits.isValidExerciseName(name)) {
                "Exercise name is outside the supported length."
            }
            requireValidSet(weight = set.weight, reps = set.reps)
            set.copy(exerciseName = name)
        }
        val countsByExercise = normalizedSets.groupingBy { it.exerciseName.normalizedExerciseName() }.eachCount()
        require(countsByExercise.size <= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
            "Workout exceeds the exercise limit."
        }
        require(countsByExercise.values.all { it <= WorkoutDataLimits.MAX_SETS_PER_EXERCISE }) {
            "Workout exercise exceeds the set limit."
        }

        return database.withTransaction {
            require(workoutDao.getSessionCount() < WorkoutDataLimits.MAX_SESSIONS) {
                "This account has reached the workout limit."
            }
            require(WorkoutDataLimits.canAddSets(setDao.getTotalSetCount(), normalizedSets.size)) {
                "This account has reached the total set limit."
            }
            val existingExercises = exerciseDao.getExercisesSnapshot()
            val exerciseIdByName = existingExercises
                .associate { it.name.normalizedExerciseName() to it.id }
                .toMutableMap()
            val exerciseIdByCatalogKey = linkedMapOf<String, Long>().apply {
                existingExercises.forEach { exercise ->
                    BuiltInExerciseCatalog.inferKey(exercise.name)?.let { catalogKey ->
                        putIfAbsent(catalogKey, exercise.id)
                    }
                }
            }
            val prospectiveNameKeys = exerciseIdByName.keys.toMutableSet()
            val prospectiveCatalogKeys = exerciseIdByCatalogKey.keys.toMutableSet()
            var prospectiveExerciseCount = existingExercises.size
            normalizedSets.forEach { set ->
                val nameKey = set.exerciseName.normalizedExerciseName()
                if (nameKey in prospectiveNameKeys) return@forEach
                val catalogKey = BuiltInExerciseCatalog.inferKey(set.exerciseName)
                if (catalogKey != null && catalogKey in prospectiveCatalogKeys) return@forEach
                prospectiveExerciseCount += 1
                prospectiveNameKeys += nameKey
                if (catalogKey != null) prospectiveCatalogKeys += catalogKey
            }
            require(prospectiveExerciseCount <= WorkoutDataLimits.MAX_EXERCISES) {
                "This account has reached the exercise limit."
            }
            val groupedDrafts = linkedMapOf<Long, MutableList<WorkoutSetDraft>>()

            normalizedSets.forEach { set ->
                val name = set.exerciseName
                val key = name.normalizedExerciseName()
                val catalogKey = BuiltInExerciseCatalog.inferKey(name)
                val exerciseId = exerciseIdByName[key]
                    ?: catalogKey?.let(exerciseIdByCatalogKey::get)
                    ?: exerciseDao.insert(ExerciseEntity(name = name)).also { insertedId ->
                        exerciseIdByName[key] = insertedId
                        if (catalogKey != null) {
                            exerciseIdByCatalogKey.putIfAbsent(catalogKey, insertedId)
                        }
                    }
                exerciseIdByName.putIfAbsent(key, exerciseId)
                if (catalogKey != null) {
                    exerciseIdByCatalogKey.putIfAbsent(catalogKey, exerciseId)
                }

                groupedDrafts.getOrPut(exerciseId) { mutableListOf() }
                    .add(WorkoutSetDraft(weight = set.weight, reps = set.reps))
            }

            val workoutExercises = groupedDrafts.map { (exerciseId, drafts) ->
                WorkoutExerciseDraft(exerciseId = exerciseId, sets = drafts)
            }
            requireValidWorkout(
                date = date,
                note = note,
                workoutExercises = workoutExercises
            )
            insertValidatedWorkoutSession(date, note, workoutExercises)
        }
    }

    suspend fun updateWorkoutSession(session: WorkoutSessionEntity) {
        require(WorkoutDataLimits.isValidTimestamp(session.date)) {
            "Workout timestamp is outside the supported range."
        }
        require(WorkoutDataLimits.isValidNote(session.note)) { "Workout note exceeds the length limit." }
        workoutDao.update(session)
    }

    suspend fun deleteWorkoutSession(session: WorkoutSessionEntity) {
        workoutDao.delete(session)
    }

    suspend fun deleteWorkoutSessionById(sessionId: Long) {
        if (sessionId <= 0) return
        workoutDao.deleteSessionById(sessionId)
    }

    suspend fun addSet(
        workoutExerciseId: Long,
        weight: Double,
        reps: Int
    ): Long {
        require(workoutExerciseId > 0) { "Workout exercise identifier is invalid." }
        requireValidSet(weight = weight, reps = reps)
        return database.withTransaction {
            require(WorkoutDataLimits.canAddSets(setDao.getTotalSetCount(), 1)) {
                "This account has reached the total set limit."
            }
            val nextIndex = (setDao.getMaxOrderIndex(workoutExerciseId) ?: -1) + 1
            require(nextIndex < WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
                "Workout exercise exceeds the set limit."
            }
            setDao.insert(
                SetEntryEntity(
                    workoutExerciseId = workoutExerciseId,
                    weight = weight,
                    reps = reps,
                    orderIndex = nextIndex
                )
            )
        }
    }

    suspend fun addExerciseToSession(
        sessionId: Long,
        exerciseId: Long,
        initialWeight: Double,
        initialReps: Int
    ): Long {
        require(sessionId > 0 && exerciseId > 0) { "Workout identifiers are invalid." }
        requireValidSet(weight = initialWeight, reps = initialReps)
        return database.withTransaction {
            require(WorkoutDataLimits.canAddSets(setDao.getTotalSetCount(), 1)) {
                "This account has reached the total set limit."
            }
            val nextOrderIndex = (workoutDao.getMaxWorkoutExerciseOrderIndex(sessionId) ?: -1) + 1
            require(nextOrderIndex < WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
                "Workout exceeds the exercise limit."
            }
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
        require(setEntry.workoutExerciseId > 0) { "Workout exercise identifier is invalid." }
        requireValidSet(weight = setEntry.weight, reps = setEntry.reps)
        require(setEntry.orderIndex in 0 until WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
            "Set order is outside the supported range."
        }
        return database.withTransaction {
            require(WorkoutDataLimits.canAddSets(setDao.getTotalSetCount(), 1)) {
                "This account has reached the total set limit."
            }
            setDao.insert(setEntry.copy(id = 0))
        }
    }

    suspend fun updateSet(setEntry: SetEntryEntity) {
        require(setEntry.id > 0 && setEntry.workoutExerciseId > 0) { "Set identifier is invalid." }
        requireValidSet(weight = setEntry.weight, reps = setEntry.reps)
        require(setEntry.orderIndex in 0 until WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
            "Set order is outside the supported range."
        }
        setDao.update(setEntry)
    }

    suspend fun updateSetById(setId: Long, weight: Double, reps: Int) {
        require(setId > 0) { "Set identifier is invalid." }
        requireValidSet(weight = weight, reps = reps)
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

    suspend fun getSetDeletionSnapshot(setId: Long): SetDeletionSnapshot? {
        if (setId <= 0) return null
        return database.withTransaction {
            setDeletionSnapshot(setId)
        }
    }

    suspend fun deleteSetIfUnchanged(expected: SetDeletionSnapshot): Boolean {
        if (expected.setId <= 0 || expected.deletionStoreToken != deletionStoreToken) {
            return false
        }
        return database.withTransaction {
            if (setDeletionSnapshot(expected.setId) != expected) {
                return@withTransaction false
            }
            val deletedRows = setDao.deleteIfUnchanged(
                setId = expected.setId,
                expectedWorkoutExerciseId = expected.workoutExerciseId,
                expectedWeight = expected.weight,
                expectedReps = expected.reps,
                expectedOrderIndex = expected.orderIndex
            )
            if (deletedRows != 1 || setDao.getById(expected.setId) != null) {
                return@withTransaction false
            }
            cleanupAfterSetDeletion(expected.workoutExerciseId)
            true
        }
    }

    private suspend fun setDeletionSnapshot(setId: Long): SetDeletionSnapshot? {
        val set = setDao.getById(setId) ?: return null
        val sessionId = workoutDao.getSessionIdByWorkoutExerciseId(set.workoutExerciseId)
            ?: return null
        val details = workoutDao.getSessionDetailsSnapshot(sessionId) ?: return null
        val exerciseBlock = details.workoutExercises
            .singleOrNull { it.workoutExercise.id == set.workoutExerciseId }
            ?: return null
        val currentSet = exerciseBlock.sets.singleOrNull { it.id == set.id } ?: return null
        if (currentSet != set) return null

        val displayOrdinal = exerciseBlock.sets
            .sortedBy { it.orderIndex }
            .indexOfFirst { it.id == set.id }
            .takeIf { it >= 0 }
            ?.plus(1)
            ?: return null

        val setsInExerciseBlock = exerciseBlock.sets.size
        val exerciseBlocksInWorkout = details.workoutExercises.size
        if (setsInExerciseBlock <= 0 || exerciseBlocksInWorkout <= 0) return null
        val impact = when {
            setsInExerciseBlock > 1 -> SetDeletionImpact.SetOnly
            exerciseBlocksInWorkout > 1 -> SetDeletionImpact.ExerciseBlock
            else -> SetDeletionImpact.WorkoutSession
        }
        val removedWorkoutExercise = exerciseBlock.workoutExercise.takeIf {
            impact != SetDeletionImpact.SetOnly
        }
        val removedWorkoutSession = details.session.takeIf {
            impact == SetDeletionImpact.WorkoutSession
        }
        val removedGarminProvenance = if (impact == SetDeletionImpact.WorkoutSession) {
            garminWorkoutReceiptDao.getProvenance(details.session.id)
        } else {
            null
        }
        return SetDeletionSnapshot(
            setId = set.id,
            workoutExerciseId = set.workoutExerciseId,
            workoutSessionId = details.session.id,
            exerciseId = exerciseBlock.exercise.id,
            exerciseName = exerciseBlock.exercise.name,
            sessionDate = details.session.date,
            weight = set.weight,
            reps = set.reps,
            orderIndex = set.orderIndex,
            displayOrdinal = displayOrdinal,
            setsInExerciseBlock = setsInExerciseBlock,
            exerciseBlocksInWorkout = exerciseBlocksInWorkout,
            impact = impact,
            removedWorkoutExercise = removedWorkoutExercise,
            removedWorkoutSession = removedWorkoutSession,
            removedGarminProvenance = removedGarminProvenance,
            deletionStoreToken = deletionStoreToken
        )
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

    suspend fun getExerciseNamesForSync(limit: Int = 400): List<String> {
        require(limit in 1..WorkoutDataLimits.MAX_EXERCISES)
        return exerciseDao.getExerciseNamesForSync(limit)
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .distinctBy { it.lowercase() }
    }

    /**
     * Atomically persists a bound Garmin workout and its durable idempotency receipt.
     *
     * The pairing generation is issued by the phone and persisted by the watch before it can send
     * a workout. Duplicate IDs are checked before the admission budgets so delivery retries remain
     * idempotent even when the current generation has reached a limit. Generationless released
     * watches use a bounded 90-day receipt horizon so they do not become permanently unusable;
     * replay protection for those legacy messages intentionally ends when that horizon expires.
     */
    suspend fun applyGarminCreateWorkout(
        ownerBinding: String,
        deviceBinding: String,
        pairingGeneration: String,
        requestId: String,
        payloadDigest: String,
        date: Long,
        note: String?,
        sets: List<NamedWorkoutSetDraft>
    ): GarminWorkoutApplyResult {
        require(ownerBinding.matches(GARMIN_OWNER_BINDING_PATTERN))
        require(
            deviceBinding.matches(GARMIN_DEVICE_BINDING_PATTERN) &&
                deviceBinding.toLongOrNull() != null
        )
        require(pairingGeneration.matches(GARMIN_OWNER_BINDING_PATTERN))
        require(requestId.matches(GARMIN_REQUEST_ID_PATTERN))
        require(payloadDigest.matches(SHA256_HEX_PATTERN))

        return database.withTransaction {
            val receiptDao = database.garminWorkoutReceiptDao()
            val now = currentTimeMillis()
            if (now !in 1L..WorkoutDataLimits.MAX_TIMESTAMP_MILLIS) {
                return@withTransaction GarminWorkoutApplyResult.Rejected
            }
            val legacyExpiresBefore =
                (now - LEGACY_GARMIN_RECEIPT_HORIZON_MS).coerceAtLeast(0L)
            receiptDao.deleteExpiredLegacyReceipts(
                migratedLegacyGeneration = MIGRATED_LEGACY_GARMIN_GENERATION,
                generationlessFallbackGeneration = LEGACY_GARMIN_FALLBACK_GENERATION,
                expiresBefore = legacyExpiresBefore
            )
            val existing = receiptDao.getAcrossGenerations(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                requestId = requestId
            )
            if (existing != null) {
                return@withTransaction if (existing.payloadDigest == payloadDigest) {
                    GarminWorkoutApplyResult.AlreadyApplied
                } else {
                    GarminWorkoutApplyResult.Rejected
                }
            }

            if (receiptDao.count() >= MAX_GARMIN_DURABLE_RECEIPTS) {
                return@withTransaction GarminWorkoutApplyResult.PairingLimitReached
            }
            val generationLimit = if (pairingGeneration == LEGACY_GARMIN_FALLBACK_GENERATION) {
                MAX_LEGACY_GARMIN_RECEIPTS_WITHIN_HORIZON
            } else {
                MAX_GARMIN_WORKOUTS_PER_PAIRING_GENERATION
            }
            if (
                receiptDao.countForPairingGeneration(
                    ownerBinding,
                    deviceBinding,
                    pairingGeneration
                ) >= generationLimit
            ) {
                return@withTransaction GarminWorkoutApplyResult.PairingLimitReached
            }
            val notBefore = (now - GARMIN_WORKOUT_RATE_WINDOW_MS).coerceAtLeast(0L)
            if (
                receiptDao.countForPairingGenerationSince(
                    ownerBinding,
                    deviceBinding,
                    pairingGeneration,
                    notBefore
                ) >= MAX_GARMIN_WORKOUTS_PER_ROLLING_DAY
            ) {
                return@withTransaction GarminWorkoutApplyResult.RateLimited
            }

            val sessionId = createWorkoutSessionFromNamedSets(
                date = date,
                note = note,
                sets = sets
            ) ?: return@withTransaction GarminWorkoutApplyResult.Rejected
            receiptDao.insert(
                GarminWorkoutReceiptEntity(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = pairingGeneration,
                    requestId = requestId,
                    payloadDigest = payloadDigest,
                    createdAt = now
                )
            )
            receiptDao.insertProvenance(
                GarminWorkoutProvenanceEntity(workoutSessionId = sessionId)
            )
            GarminWorkoutApplyResult.Applied
        }
    }

    /**
     * Retires replay state only after the watch acknowledged a destructive generation reset.
     * Old-generation messages are rejected by the protocol before reaching this database.
     */
    suspend fun activateGarminPairingGeneration(
        ownerBinding: String,
        deviceBinding: String,
        pairingGeneration: String
    ) {
        require(ownerBinding.matches(GARMIN_OWNER_BINDING_PATTERN))
        require(
            deviceBinding.matches(GARMIN_DEVICE_BINDING_PATTERN) &&
                deviceBinding.toLongOrNull() != null
        )
        require(pairingGeneration.matches(GARMIN_OWNER_BINDING_PATTERN))
        database.withTransaction {
            database.garminWorkoutReceiptDao().deleteOtherPairingGenerations(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                activePairingGeneration = pairingGeneration
            )
        }
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

    private fun sessionImportSignature(details: WorkoutSessionDetails): String {
        return workoutImportSignature(
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

    private fun garminProvenanceSignature(details: WorkoutSessionDetails): String {
        return garminProvenanceSignature(
            ValidatedBackupSession(
                date = details.session.date,
                note = details.session.note,
                blocks = details.workoutExercises.map { workoutExercise ->
                    ValidatedBackupBlock(
                        exercise = ValidatedBackupExercise(
                            name = workoutExercise.exercise.name,
                            catalogKey = BuiltInExerciseCatalog.inferKey(
                                workoutExercise.exercise.name
                            )
                        ),
                        sets = workoutExercise.sets.map { set ->
                            ValidatedBackupSet(weight = set.weight, reps = set.reps)
                        }
                    )
                }
            )
        )
    }

    private fun garminProvenanceSignature(session: ValidatedBackupSession): String {
        return canonicalWorkoutPayloadDigest(
            ValidatedBackup(
                exercises = emptyList(),
                sessions = listOf(session)
            )
        )
    }

    private fun requireValidWorkout(
        date: Long,
        note: String?,
        workoutExercises: List<WorkoutExerciseDraft>
    ) {
        require(WorkoutDataLimits.isValidTimestamp(date)) {
            "Workout timestamp is outside the supported range."
        }
        require(WorkoutDataLimits.isValidNote(note)) { "Workout note exceeds the length limit." }
        require(workoutExercises.isNotEmpty()) { "Workout must contain at least one exercise." }
        require(workoutExercises.size <= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
            "Workout exceeds the exercise limit."
        }
        require(workoutExercises.all { it.exerciseId > 0 }) { "Exercise identifier is invalid." }
        var totalSets = 0
        val setsPerExercise = mutableMapOf<Long, Int>()
        workoutExercises.forEach { exercise ->
            require(exercise.sets.isNotEmpty()) { "Workout exercise must contain at least one set." }
            require(exercise.sets.size <= WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
                "Workout exercise exceeds the set limit."
            }
            val exerciseSetCount = setsPerExercise.getOrDefault(exercise.exerciseId, 0) + exercise.sets.size
            require(exerciseSetCount <= WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
                "Workout exercise exceeds the set limit."
            }
            setsPerExercise[exercise.exerciseId] = exerciseSetCount
            exercise.sets.forEach { set ->
                requireValidSet(weight = set.weight, reps = set.reps)
                totalSets += 1
            }
        }
        require(totalSets <= WorkoutDataLimits.MAX_TOTAL_SETS) { "Workout exceeds the total set limit." }
    }

    /** Must only be called inside [database]'s transaction after validation and capacity checks. */
    private suspend fun insertValidatedWorkoutSession(
        date: Long,
        note: String?,
        workoutExercises: List<WorkoutExerciseDraft>
    ): Long {
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

        return sessionId
    }

    private fun requireValidSet(weight: Double, reps: Int) {
        require(WorkoutDataLimits.isValidWeight(weight)) {
            "Set weight is outside the supported range."
        }
        require(WorkoutDataLimits.isValidReps(reps)) {
            "Set repetitions are outside the supported range."
        }
    }

    private suspend fun currentExerciseLoadProfiles(
        rejectInvalid: Boolean
    ): Map<Long, ExerciseLoadProfile> = loadProfileMap(
        profiles = exerciseLoadProfileDao.getProfilesSnapshot(),
        options = exerciseLoadProfileDao.getWeightOptionsSnapshot(),
        rejectInvalid = rejectInvalid
    )

    private fun loadProfileMap(
        profiles: List<ExerciseLoadProfileEntity>,
        options: List<ExerciseWeightOptionEntity>,
        rejectInvalid: Boolean
    ): Map<Long, ExerciseLoadProfile> {
        val optionsByExercise = options.groupBy { it.exerciseId }
        if (rejectInvalid) {
            require(optionsByExercise.keys.all { optionExerciseId ->
                profiles.any { it.exerciseId == optionExerciseId }
            }) { "Stored exercise load profile is invalid." }
        }
        return buildMap {
            profiles.forEach { entity ->
                val direction = ExerciseLoadDirection.fromWireValue(entity.direction)
                val orderedOptions = optionsByExercise[entity.exerciseId]
                    .orEmpty()
                    .sortedBy { it.ordinal }
                val ordinalsAreCanonical = orderedOptions.withIndex().all { (index, option) ->
                    option.ordinal == index
                }
                val weights = orderedOptions.map { it.weight }
                val isValid = ordinalsAreCanonical &&
                    ExerciseLoadProfile.isValid(direction, weights)
                if (rejectInvalid) {
                    require(isValid) { "Stored exercise load profile is invalid." }
                }
                if (isValid && direction != null) {
                    put(entity.exerciseId, ExerciseLoadProfile(direction, weights))
                }
            }
        }
    }

    /** Must only be called inside [database]'s transaction. */
    private suspend fun replaceExerciseLoadProfile(
        exerciseId: Long,
        profile: ExerciseLoadProfile?
    ) {
        exerciseLoadProfileDao.deleteWeightOptions(exerciseId)
        if (profile == null) {
            exerciseLoadProfileDao.deleteProfile(exerciseId)
            return
        }
        exerciseLoadProfileDao.upsertProfile(
            ExerciseLoadProfileEntity(
                exerciseId = exerciseId,
                direction = profile.direction.wireValue,
                updatedAt = currentTimeMillis()
            )
        )
        exerciseLoadProfileDao.insertWeightOptions(
            profile.allowedWeightsKg.mapIndexed { index, weight ->
                ExerciseWeightOptionEntity(
                    exerciseId = exerciseId,
                    ordinal = index,
                    weight = weight
                )
            }
        )
    }

    private companion object {
        val GARMIN_OWNER_BINDING_PATTERN = Regex("^[0-9a-f]{64}$")
        val GARMIN_DEVICE_BINDING_PATTERN = Regex("^-?[0-9]{1,19}$")
        val GARMIN_REQUEST_ID_PATTERN = Regex("^[A-Za-z0-9_.:-]{16,128}$")
        val SHA256_HEX_PATTERN = Regex("^[0-9a-f]{64}$")
    }
}

internal fun validateBackupOwnerContext(
    root: JSONObject,
    activeAccountId: String?,
    activeUserId: String?,
    activeRemote: Boolean
) {
    val owner = root.optJSONObject("owner")
    if (activeRemote) {
        val currentUserId = activeUserId?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("An active cloud account is required for this backup.")
        if (owner == null) return // Legacy cloud rows are account-bound by authenticated RLS.

        val backupUserId = (owner.opt("userId") as? String)?.takeIf { it.isNotBlank() }
        val backupAccountId = (owner.opt("accountId") as? String)?.takeIf { it.isNotBlank() }
        require(backupUserId == null || backupUserId == currentUserId) {
            "This backup belongs to another account."
        }

        val remoteMarker = owner.opt("remote")
        val isRemoteOwner = remoteMarker == true || remoteMarker == "supabase"
        val isExactCrossClientAlias = backupUserId == currentUserId &&
            isRecognizedCloudAccountId(backupAccountId, currentUserId) &&
            isRemoteOwner
        require(backupAccountId == null || backupAccountId == currentUserId || isExactCrossClientAlias) {
            "This backup belongs to another account."
        }
        return
    }

    if (owner == null) return
    val backupUserId = (owner.opt("userId") as? String)?.takeIf { it.isNotBlank() }
    val backupAccountId = (owner.opt("accountId") as? String)?.takeIf { it.isNotBlank() }
    require(backupUserId == null && (backupAccountId == null || backupAccountId == activeAccountId)) {
        "This backup belongs to another account."
    }
}

/**
 * Cloud clients use different account-storage keys for the same authenticated Supabase user.
 * Accept only exact, user-bound aliases; arbitrary prefixes or another user's suffix remain
 * rejected even when the row was returned through authenticated RLS.
 */
internal fun isRecognizedCloudAccountId(accountId: String?, activeUserId: String): Boolean =
    accountId == activeUserId ||
        accountId == "remote-$activeUserId" ||
        accountId == "cloud_$activeUserId"

private fun String.toExerciseMappingKey(): String {
    return normalizedExerciseName()
}

private fun exerciseNamesConflict(existingName: String, candidateName: String): Boolean {
    if (existingName.normalizedExerciseName() == candidateName.normalizedExerciseName()) {
        return true
    }
    val candidateCatalogKey = BuiltInExerciseCatalog.inferKey(candidateName) ?: return false
    return BuiltInExerciseCatalog.inferKey(existingName) == candidateCatalogKey
}

private fun exerciseBackupJson(
    rawName: String,
    loadProfile: ExerciseLoadProfile? = null
): JSONObject {
    return JSONObject()
        .put("name", rawName)
        .apply {
            BuiltInExerciseCatalog.inferKey(rawName)?.let { key ->
                put("catalogKey", key)
            }
            loadProfile?.let { profile ->
                put(
                    "loadProfile",
                    JSONObject()
                        .put("direction", profile.direction.wireValue)
                        .put("allowedWeightsKg", JSONArray(profile.allowedWeightsKg))
                )
            }
        }
}
