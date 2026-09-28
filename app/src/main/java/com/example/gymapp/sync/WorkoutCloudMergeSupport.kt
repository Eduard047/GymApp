package com.example.gymapp.sync

import android.content.Context
import android.util.AtomicFile
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.repository.BackupImportValidator
import com.example.gymapp.data.repository.ValidatedBackup
import com.example.gymapp.data.repository.ValidatedBackupBlock
import com.example.gymapp.data.repository.ValidatedBackupExercise
import com.example.gymapp.data.repository.ValidatedBackupSession
import com.example.gymapp.data.repository.ValidatedBackupSet
import java.io.File
import java.security.MessageDigest
import java.time.OffsetDateTime
import kotlinx.coroutines.sync.Mutex
import org.json.JSONObject

/** Cross-device catalog identity, the same one the shared cloud validator uses. */
internal fun workoutMergeExerciseIdentity(exercise: WorkoutMergeExercise): String =
    ValidatedBackupExercise(name = exercise.name, catalogKey = exercise.catalogKey).identityKey

/**
 * The canonical v2.2.9 projection of a validated backup, the same projection its sync digest
 * covers: portable catalog keys, no device-local preferences, no activity-only sessions.
 */
internal fun workoutMergeCore(backup: ValidatedBackup): WorkoutMergeCore = WorkoutMergeCore(
    exercises = backup.exercises.map { exercise ->
        WorkoutMergeExercise(exercise.name, portableCatalogKey(exercise))
    },
    sessions = backup.sessions
        .filter { it.blocks.isNotEmpty() }
        .sortedBy { it.date }
        .map { session ->
            WorkoutMergeSession(
                date = session.date,
                note = session.note,
                blocks = session.blocks.map { block ->
                    WorkoutMergeBlock(
                        name = block.exercise.name,
                        catalogKey = portableCatalogKey(block.exercise),
                        sets = block.sets.map { set ->
                            WorkoutMergeSet(
                                weight = WorkoutCloudSyncState.canonicalWeight(set.weight),
                                reps = set.reps
                            )
                        }
                    )
                }
            )
        }
)

internal fun workoutMergeCoreFromCloudState(root: JSONObject): WorkoutMergeCore =
    workoutMergeCore(BackupImportValidator.validate(root))

internal fun WorkoutMergeCore.toValidatedBackup(): ValidatedBackup = ValidatedBackup(
    exercises = exercises.map { ValidatedBackupExercise(name = it.name, catalogKey = it.catalogKey) },
    sessions = sessions.map { session ->
        ValidatedBackupSession(
            date = session.date,
            note = session.note,
            blocks = session.blocks.map { block ->
                ValidatedBackupBlock(
                    exercise = ValidatedBackupExercise(name = block.name, catalogKey = block.catalogKey),
                    sets = block.sets.map { ValidatedBackupSet(weight = it.weight, reps = it.reps) }
                )
            }
        )
    }
)

private fun portableCatalogKey(exercise: ValidatedBackupExercise): String? =
    BuiltInExerciseCatalog.inferKey(exercise.name) ?: exercise.catalogKey

/**
 * Remembers the local workout core last seen for one signed-in account, so each local edit can be
 * stamped in the change journal. Changes applied from the cloud hold [mutex] and move [lastSeen]
 * to their result, so they are never recorded as local edits.
 */
internal class WorkoutLocalChangeTracker {
    val mutex = Mutex()
    var lastSeen: WorkoutMergeCore? = null
}

/** `updated_at` of a cloud row in epoch milliseconds, or null when it cannot be read. */
internal fun remoteStateRevisionMillis(updatedAt: String): Long? =
    runCatching { OffsetDateTime.parse(updatedAt).toInstant().toEpochMilli() }.getOrNull()

/**
 * Keeps [WorkoutCloudSyncState] per account on this installation only. The file lives in the
 * no-backup directory because it describes this device's synchronization history, like
 * [CloudSyncBaselineStore]. A missing or unreadable file simply disables per-workout merging until
 * the next confirmed sync, so the whole-history choice remains the fallback.
 */
internal class WorkoutCloudSyncStateStore(context: Context) {
    private val directory = File(context.applicationContext.noBackupFilesDir, DIRECTORY_NAME)

    fun read(userId: String): WorkoutCloudSyncState? = synchronized(lock) {
        val file = AtomicFile(file(userId))
        if (!file.baseFile.exists()) return null
        runCatching {
            val state = WorkoutCloudSyncState.fromJson(JSONObject(String(file.readFully(), Charsets.UTF_8)))
            state.takeIf { it.ownerUserId == userId }
        }.getOrNull()
    }

    fun write(state: WorkoutCloudSyncState): Boolean = synchronized(lock) {
        runCatching {
            directory.mkdirs()
            val file = AtomicFile(file(state.ownerUserId))
            val output = file.startWrite()
            try {
                output.write(state.toJson().toString().toByteArray(Charsets.UTF_8))
                file.finishWrite(output)
            } catch (error: Throwable) {
                file.failWrite(output)
                throw error
            }
        }.isSuccess
    }

    fun clear(userId: String): Boolean = synchronized(lock) {
        val file = AtomicFile(file(userId))
        file.delete()
        !file.baseFile.exists()
    }

    private fun file(userId: String): File {
        require(userId.isNotBlank() && userId.length <= 256)
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(userId.toByteArray(Charsets.UTF_8))
            .joinToString(separator = "") { byte -> (byte.toInt() and 0xff).toString(16).padStart(2, '0') }
        return File(directory, "user_$digest.json")
    }

    private companion object {
        const val DIRECTORY_NAME = "workout_cloud_sync"
        val lock = Any()
    }
}
