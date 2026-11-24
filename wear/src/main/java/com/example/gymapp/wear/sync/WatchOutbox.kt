package com.example.gymapp.wear.sync

import android.content.Context
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Application-scope sender of the finished workout that waits on the watch. It runs without any
 * screen: after an accepted full sync from the bound owner, when the phone reconnects and when
 * the app starts. One mutex is shared with the ViewModel's own send, so a workout is never sent
 * twice in parallel, and a draft delivered here is never sent again under a new operation id.
 */
class WatchOutbox(
    context: Context,
    private val syncClient: WearSyncClient
) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private val deliveredDraftIds = ConcurrentHashMap.newKeySet<String>()
    private val deliveredEvents = MutableSharedFlow<String>(extraBufferCapacity = 8)

    /** Draft ids delivered by a background flush; the ViewModel closes its copy on these. */
    val delivered: SharedFlow<String> = deliveredEvents

    fun wasDelivered(draftId: String): Boolean = draftId in deliveredDraftIds

    /** The ViewModel's own send was acknowledged; a flush must not send this draft again. */
    fun markDelivered(draftId: String) {
        deliveredDraftIds += draftId
    }

    fun flushAsync() {
        scope.launch { runCatching { flush() } }
    }

    /** Runs [block] under the send mutex (the ViewModel's foreground send). */
    suspend fun <T> exclusive(block: suspend () -> T): T = mutex.withLock { block() }

    /** Sends the waiting workout when it belongs to the bound owner. True when it was delivered. */
    suspend fun flush(): Boolean = mutex.withLock {
        val binding = WatchSyncBindingStorage.load(appContext) ?: return@withLock false
        val ownerId = binding.ownerId ?: return@withLock false
        // load() returns a stored operation only for the same owner; another owner's stays held.
        val pending = WatchPendingWorkoutStorage.load(appContext, binding)
        val stored = WatchWorkoutDraftStorage.load(appContext)
        // Already acknowledged in this process; its owner (the ViewModel) is clearing the storage.
        val candidateDraftId = pending?.draftId ?: stored?.draft?.draftId
        if (candidateDraftId != null && candidateDraftId in deliveredDraftIds) return@withLock false
        val sent = when {
            pending != null -> syncClient.createWorkout(
                binding = binding,
                draftId = pending.draftId,
                startedAt = pending.startedAt,
                note = pending.note,
                sets = pending.sets,
                sourcePlanRaw = pending.sourcePlanRaw,
                durationSeconds = pending.durationSeconds,
                averageHeartRate = pending.averageHeartRate,
                maxHeartRate = pending.maxHeartRate
            )

            stored != null &&
                WatchBindingRules.heldWorkState(ownerId, stored.ownerId, true) == HeldWorkState.Ready &&
                stored.draft.finished != null &&
                stored.draft.sets.isNotEmpty() -> syncClient.createWorkout(
                binding = binding,
                draftId = stored.draft.draftId,
                startedAt = stored.draft.startedAt,
                note = null,
                sets = stored.draft.sets,
                // The plan the workout was started from, not a newer one stored since (E-11).
                sourcePlanRaw = WatchWorkoutDraftStorage.sourcePlanFor(
                    appContext, stored.draft, WatchPlanStorage.load(appContext)
                ),
                durationSeconds = stored.draft.finished.durationSeconds,
                averageHeartRate = stored.draft.finished.averageHeartRate,
                maxHeartRate = stored.draft.finished.maxHeartRate
            )

            else -> return@withLock false
        }
        // The phone accepted it. Draft first, operation id last (a crash in between resends the
        // same id, which the phone recognises).
        deliveredDraftIds += sent.draftId
        if (WorkoutSourcePlan.shouldClearStoredPlan(WatchPlanStorage.load(appContext), sent.sourcePlanRaw)) {
            runCatching { WatchPlanStorage.clear(appContext) }
        }
        val draftGone = runCatching {
            WatchWorkoutDraftStorage.load(appContext)?.draft?.draftId != sent.draftId ||
                WatchWorkoutDraftStorage.clear(appContext)
        }.getOrDefault(false)
        // A finished draft that could not be removed keeps its operation id: after a process
        // death it is resent under the same id (the phone recognises it), never under a new one.
        if (draftGone) WatchPendingWorkoutStorage.clearIfMatches(appContext, sent)
        deliveredEvents.tryEmit(sent.draftId)
        true
    }
}
