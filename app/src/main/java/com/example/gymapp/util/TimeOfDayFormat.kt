package com.example.gymapp.util

import android.content.Context
import java.text.DateFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Date
import java.util.Locale

/**
 * The one time-of-day format. The 12/24-hour cycle follows the phone's system setting
 * ([is24Hour] comes from [systemUses24Hour]); AM/PM markers and month names follow the
 * in-app [locale]. Matches iPhone `gymFormattedTimeOfDay`.
 */
object TimeOfDayFormat {
    fun systemUses24Hour(context: Context): Boolean =
        android.text.format.DateFormat.is24HourFormat(context)

    fun formatTime(
        timestamp: Long,
        locale: Locale,
        is24Hour: Boolean,
        zoneId: ZoneId = ZoneId.systemDefault(),
        withSeconds: Boolean = false
    ): String {
        val pattern = when {
            is24Hour && withSeconds -> "HH:mm:ss"
            is24Hour -> "HH:mm"
            withSeconds -> "h:mm:ss a"
            else -> "h:mm a"
        }
        return DateTimeFormatter.ofPattern(pattern, locale)
            .withZone(zoneId)
            .format(Instant.ofEpochMilli(timestamp))
    }

    /** "Oct 5, 2026, 14:05": medium date in the app locale, then [formatTime]. */
    fun formatDateTime(
        timestamp: Long,
        locale: Locale,
        is24Hour: Boolean,
        zoneId: ZoneId = ZoneId.systemDefault()
    ): String {
        val dateFormat = DateFormat.getDateInstance(DateFormat.MEDIUM, locale)
        dateFormat.timeZone = java.util.TimeZone.getTimeZone(zoneId)
        return dateFormat.format(Date(timestamp)) + ", " +
            formatTime(timestamp, locale, is24Hour, zoneId)
    }
}
