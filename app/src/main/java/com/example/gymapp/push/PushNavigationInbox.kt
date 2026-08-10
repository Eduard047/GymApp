package com.example.gymapp.push

import com.example.gymapp.auth.AccountSession
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class PendingPushNavigation(
    val id: Long,
    val navigation: AccountBoundPushNavigation
)

internal data class AccountBoundPushNavigation(
    val payload: PushPayload,
    val userId: String,
    val sessionGeneration: String,
    val installationId: String
) {
    val target: PushNavigationTarget
        get() = payload.navigationTarget()
    val bindingId: String
        get() = payload.bindingId
}

internal fun AccountBoundPushNavigation.matchesSession(session: AccountSession?): Boolean {
    val cloud = session as? AccountSession.Cloud ?: return false
    return userId == cloud.userId && sessionGeneration == cloud.sessionGeneration
}

internal class PushNavigationInbox {
    private val nextId = AtomicLong(0L)
    private val _pending = MutableStateFlow<PendingPushNavigation?>(null)
    val pending: StateFlow<PendingPushNavigation?> = _pending.asStateFlow()

    fun offer(navigation: AccountBoundPushNavigation) {
        _pending.value = PendingPushNavigation(nextId.incrementAndGet(), navigation)
    }

    fun consume(id: Long) {
        if (_pending.value?.id == id) _pending.value = null
    }

    fun clear() {
        _pending.value = null
    }
}
