package com.example.gymapp.wear.sync

import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred

object WatchSyncAckRegistry {
    private val pending = ConcurrentHashMap<String, CompletableDeferred<Boolean>>()

    fun register(operationId: String): CompletableDeferred<Boolean> {
        val acknowledgement = CompletableDeferred<Boolean>()
        check(pending.putIfAbsent(operationId, acknowledgement) == null) {
            "Duplicate operation id"
        }
        return acknowledgement
    }

    fun complete(operationId: String, accepted: Boolean) {
        pending.remove(operationId)?.complete(accepted)
    }

    fun cancel(operationId: String) {
        pending.remove(operationId)?.cancel()
    }
}
