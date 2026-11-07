package com.example.gymapp.util

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** The local calendar day together with the zone it was read in; a zone change alone is a new value. */
data class CurrentDay(val date: LocalDate, val zoneId: ZoneId)

/**
 * Holds "today" for UI state that would otherwise keep yesterday after the app stays open across
 * midnight or the device timezone changes. [refresh] re-reads the clock and emits only when the
 * day or the zone actually changed.
 */
class CurrentDayTracker(
    private val zoneProvider: () -> ZoneId = { ZoneId.systemDefault() },
    private val dateProvider: (ZoneId) -> LocalDate = { zone -> LocalDate.now(zone) }
) {
    private val mutableState = MutableStateFlow(read())
    val state: StateFlow<CurrentDay> = mutableState.asStateFlow()

    fun refresh() {
        mutableState.value = read()
    }

    private fun read(): CurrentDay {
        val zone = zoneProvider()
        return CurrentDay(dateProvider(zone), zone)
    }
}

/**
 * App-wide current-day signal, refreshed on resume and on the system date/time/timezone
 * broadcasts. The broadcasts are registered at runtime only while an Activity is started, so no
 * manifest entry or permission is needed.
 */
object CurrentDaySignal {
    private val tracker = CurrentDayTracker()
    val state: StateFlow<CurrentDay> = tracker.state

    fun refresh() = tracker.refresh()

    /** Registers the date/timezone receiver; call [unregister] with the same context. */
    fun register(context: Context): BroadcastReceiver {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                refresh()
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_DATE_CHANGED)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }
        ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        refresh()
        return receiver
    }

    fun unregister(context: Context, receiver: BroadcastReceiver) {
        runCatching { context.unregisterReceiver(receiver) }
    }
}
