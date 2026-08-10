package com.example.gymapp.push

/** Orders final notification display checks with account/binding transition cancellation. */
internal class PushNotificationStateGate {
    private val lock = Any()

    fun <T> runExclusive(operation: () -> T): T = synchronized(lock) { operation() }
}
