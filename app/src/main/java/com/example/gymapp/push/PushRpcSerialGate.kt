package com.example.gymapp.push

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Serializes provider-address mutations so logout can always perform the final revocation. */
internal class PushRpcSerialGate {
    private val mutex = Mutex()

    suspend fun <T> runExclusive(operation: suspend () -> T): T =
        mutex.withLock { operation() }
}
