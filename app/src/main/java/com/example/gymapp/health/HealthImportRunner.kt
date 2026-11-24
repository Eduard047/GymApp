package com.example.gymapp.health

import com.example.gymapp.data.repository.ActivityOnlyWorkoutItem
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.util.AppLanguage
import kotlinx.coroutines.CancellationException

/** Where the exercise records come from (Health Connect on Android). */
internal interface HealthSessionSource {
    /** Sessions that start in [fromMillis]..[toMillis], newest first, headers only. */
    suspend fun listSessions(fromMillis: Long, toMillis: Long, maxRecords: Int): HealthSessionListing

    /** Returns [session] with kilocalories and heart-rate samples filled in. */
    suspend fun loadDetails(session: HealthImportSession): HealthImportSession
}

internal data class HealthSessionListing(
    val sessions: List<HealthImportSession>,
    /** True when more records existed than [HealthSessionSource.listSessions] was allowed to read. */
    val truncated: Boolean
)

/** The account-bound local store the importer writes to (GymRepository on the real path). */
internal interface HealthImportPersistence {
    suspend fun existingWorkouts(fromMillis: Long): List<HealthExistingWorkout>
    suspend fun knownReceipts(keys: Collection<String>): Set<String>
    suspend fun persist(item: ActivityOnlyWorkoutItem, receiptKey: String): HealthImportPersistResult
    /** Whether this account opted in to the import (off by default). */
    suspend fun isEnabled(): Boolean
    suspend fun lastImportAt(): Long?
    suspend fun setLastImportAt(millis: Long)
}

internal enum class HealthImportTrigger { MANUAL, AUTOMATIC }

internal enum class HealthImportStatus {
    COMPLETED,
    THROTTLED,
    ABORTED_ACCOUNT_CHANGED,
    NO_PERMISSION,
    /** The active account has not enabled the import; nothing was read. */
    NOT_ENABLED,
    PROVIDER_UPDATE_REQUIRED,
    UNAVAILABLE,
    UNSUPPORTED_OS
}

internal data class HealthImportSummary(
    val status: HealthImportStatus,
    val imported: Int = 0,
    val skipped: Map<HealthImportSkipReason, Int> = emptyMap(),
    /** Gym sessions that were left for a later run because of the per-run cap. */
    val truncated: Boolean = false,
    /** True when the local workout limit stopped the run. */
    val capacityReached: Boolean = false,
    /** Candidates whose details could not be read; left without a receipt for the next run. */
    val readFailures: Int = 0
) {
    fun skippedCount(reason: HealthImportSkipReason): Int = skipped[reason] ?: 0
}

/**
 * Orchestrates one import run: read sessions, apply [HealthImportRules], persist, and remember the
 * completion time. Nothing here touches Android; the source and the store are interfaces so the
 * run is unit-testable. A run aborts without writing anything further once [isAccountActive]
 * reports that the account changed.
 */
internal class HealthImportRunner(
    private val store: HealthImportStore,
    private val source: HealthSessionSource,
    private val persistence: HealthImportPersistence,
    private val language: () -> AppLanguage,
    private val isAccountActive: () -> Boolean,
    private val clock: () -> Long = System::currentTimeMillis
) {
    suspend fun run(trigger: HealthImportTrigger): HealthImportSummary {
        if (!isAccountActive()) return HealthImportSummary(HealthImportStatus.ABORTED_ACCOUNT_CHANGED)
        if (!persistence.isEnabled()) return HealthImportSummary(HealthImportStatus.NOT_ENABLED)
        val now = clock()
        if (trigger == HealthImportTrigger.AUTOMATIC) {
            val last = persistence.lastImportAt()
            if (last != null && now >= last &&
                now - last < HealthImportRules.MIN_AUTO_IMPORT_INTERVAL_SECONDS * 1_000L
            ) {
                return HealthImportSummary(HealthImportStatus.THROTTLED)
            }
        }

        val windowStart = now - HealthImportRules.WINDOW_DAYS * MILLIS_PER_DAY
        val listing = source.listSessions(
            fromMillis = windowStart,
            toMillis = now,
            maxRecords = HealthImportRules.MAX_RECORDS_SCANNED_PER_RUN
        )
        if (!isAccountActive()) return HealthImportSummary(HealthImportStatus.ABORTED_ACCOUNT_CHANGED)

        val skipped = linkedMapOf<HealthImportSkipReason, Int>()
        fun skip(reason: HealthImportSkipReason) {
            skipped[reason] = (skipped[reason] ?: 0) + 1
        }

        // Own-app and non-gym sessions never count toward the cap; the rest is newest first.
        val candidates = ArrayList<HealthImportSession>()
        var truncated = listing.truncated
        for (session in listing.sessions.sortedByDescending { it.startMillis }) {
            val reason = HealthImportRules.screenSource(store, session)
            when {
                reason != null -> skip(reason)
                candidates.size >= HealthImportRules.MAX_SESSIONS_PER_RUN -> truncated = true
                else -> candidates += session
            }
        }

        val receipts = persistence.knownReceipts(candidates.map { store.receiptKey(it.recordId) })
        // Long workouts that began before the window can still overlap its first sessions.
        val existing = persistence.existingWorkouts(
            windowStart - WorkoutDataLimits.MAX_WORKOUT_DURATION_SECONDS * 1_000L
        ).toMutableList()

        var imported = 0
        var capacityReached = false
        var readFailures = 0
        for (candidate in candidates) {
            if (!isAccountActive()) {
                return summary(HealthImportStatus.ABORTED_ACCOUNT_CHANGED, imported, skipped, truncated, capacityReached)
            }
            val reason = HealthImportRules.screen(store, candidate, existing, receipts, now)
            if (reason != null) {
                skip(reason)
                continue
            }
            // One failed read skips only this candidate: no receipt is written, so the next run
            // retries it, and the run still completes (and so throttles the next automatic run).
            val detailed = try {
                source.loadDetails(candidate)
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Exception) {
                readFailures++
                continue
            }
            // Re-check right before the write: loading details can take a while.
            if (!isAccountActive()) {
                return summary(HealthImportStatus.ABORTED_ACCOUNT_CHANGED, imported, skipped, truncated, capacityReached)
            }
            val item = HealthImportRules.build(store, detailed, language())
            when (persistence.persist(item, store.receiptKey(candidate.recordId))) {
                HealthImportPersistResult.IMPORTED -> {
                    imported++
                    existing += HealthExistingWorkout(item.workoutStartedAt, item.durationSeconds)
                }
                HealthImportPersistResult.DUPLICATE_RECEIPT -> skip(HealthImportSkipReason.DUPLICATE_RECEIPT)
                HealthImportPersistResult.OVERLAP -> skip(HealthImportSkipReason.OVERLAP)
                HealthImportPersistResult.CAPACITY_REACHED -> {
                    capacityReached = true
                    break
                }
            }
        }

        persistence.setLastImportAt(now)
        return summary(HealthImportStatus.COMPLETED, imported, skipped, truncated, capacityReached, readFailures)
    }

    private fun summary(
        status: HealthImportStatus,
        imported: Int,
        skipped: Map<HealthImportSkipReason, Int>,
        truncated: Boolean,
        capacityReached: Boolean,
        readFailures: Int = 0
    ) = HealthImportSummary(
        status = status,
        imported = imported,
        skipped = skipped.toMap(),
        truncated = truncated,
        capacityReached = capacityReached,
        readFailures = readFailures
    )

    private companion object {
        const val MILLIS_PER_DAY = 86_400_000L
    }
}
