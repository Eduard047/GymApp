package com.example.gymapp.ui.screens

import java.io.OutputStream

/** Suggested file name for the local-side backup saved from the cloud sync conflict dialog. */
internal const val CLOUD_SYNC_CONFLICT_BACKUP_FILE_NAME = "GymApp-phone-backup.json"

/**
 * Writes the manual-backup [json] to the stream returned by [openStream] (a SAF document).
 * Returns false when no stream could be opened or writing failed; never throws.
 */
internal fun writeCloudSyncConflictBackup(
    json: String,
    openStream: () -> OutputStream?
): Boolean = runCatching {
    val stream = openStream() ?: return@runCatching false
    stream.use {
        it.write(json.toByteArray(Charsets.UTF_8))
        it.flush()
    }
    true
}.getOrDefault(false)
