package com.example.gymapp.ui.viewmodel

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * One deletion that is staged for [timeoutMillis] before it touches storage, the way iOS stages a
 * saved-workout deletion behind its undo bar. While an item is [pending] nothing has been written:
 * the screen only hides it, so [undo] simply forgets it and no sync or Garmin side effect ever
 * ran. [onCommit] performs the real deletion exactly once, when the timer fires, when
 * [commitNow] / [commitDetached] is called (leaving the screen), or when another item is staged.
 *
 * The commit runs non-cancellable so a view model that is being cleared cannot abandon a
 * half-finished write. [waitFor] is injectable so tests control the timeout deterministically.
 */
internal class StagedDeletion<T : Any>(
    private val scope: CoroutineScope,
    private val timeoutMillis: Long = DEFAULT_TIMEOUT_MILLIS,
    private val waitFor: suspend (Long) -> Unit = { delay(it) },
    private val detachedScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    private val onCommit: suspend (T) -> Unit
) {
    private val stateLock = Any()
    private val commitLock = Mutex()
    private val mutablePending = MutableStateFlow<T?>(null)
    private var timer: Job? = null
    private var committing: T? = null

    /** The item currently hidden behind the undo bar, or null. */
    val pending: StateFlow<T?> = mutablePending.asStateFlow()

    /** Stages [item]. An earlier staged item is committed first, so only one is ever pending. */
    suspend fun stage(item: T) {
        commitNow()
        synchronized(stateLock) {
            mutablePending.value = item
            timer?.cancel()
            timer = scope.launch {
                waitFor(timeoutMillis)
                commitNow()
            }
        }
    }

    /** Restores the staged item. Returns false when nothing was pending or its commit already started. */
    fun undo(): Boolean = synchronized(stateLock) {
        if (committing != null || mutablePending.value == null) return@synchronized false
        timer?.cancel()
        timer = null
        mutablePending.value = null
        true
    }

    /** Commits the staged item now (a no-op when there is none) and waits for the write. */
    suspend fun commitNow() {
        commitLock.withLock {
            val item = synchronized(stateLock) {
                val staged = mutablePending.value
                timer?.cancel()
                timer = null
                committing = staged
                staged
            } ?: return
            try {
                withContext(NonCancellable) { onCommit(item) }
            } finally {
                synchronized(stateLock) {
                    committing = null
                    if (mutablePending.value === item) mutablePending.value = null
                }
            }
        }
    }

    /** Leaving the screen: commits on a scope that outlives the view model. */
    fun commitDetached() {
        if (mutablePending.value == null) return
        detachedScope.launch { commitNow() }
    }

    companion object {
        const val DEFAULT_TIMEOUT_MILLIS = 5_000L
    }
}
