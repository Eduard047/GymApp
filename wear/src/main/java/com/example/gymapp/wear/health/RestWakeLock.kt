package com.example.gymapp.wear.health

import android.content.Context
import android.os.PowerManager

/**
 * Keeps the CPU awake for the length of one rest countdown, so the "rest finished" vibration
 * fires on time with the screen off instead of on the next wrist raise. Always acquired with a
 * timeout (a rest is at most [RestTimerLogic.MAX_REST_SECONDS]), so it can never leak.
 */
class RestWakeLock(context: Context) {
    private val lock: PowerManager.WakeLock? = runCatching {
        context.applicationContext.getSystemService(PowerManager::class.java)
            ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GymWatch:rest")
            ?.apply { setReferenceCounted(false) }
    }.getOrNull()

    fun hold(remainingSeconds: Int) {
        val seconds = remainingSeconds.coerceIn(1, RestTimerLogic.MAX_REST_SECONDS)
        runCatching { lock?.acquire((seconds + GRACE_SECONDS) * 1_000L) }
    }

    fun release() {
        runCatching { if (lock?.isHeld == true) lock.release() }
    }

    private companion object {
        /** Time for the ticker to notice the end and start the vibration. */
        const val GRACE_SECONDS = 3
    }
}
