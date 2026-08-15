package com.example.gymapp.util

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

object DateTimeUtils {
    private val ukrainianGenitiveMonths = listOf(
        "січня",
        "лютого",
        "березня",
        "квітня",
        "травня",
        "червня",
        "липня",
        "серпня",
        "вересня",
        "жовтня",
        "листопада",
        "грудня"
    )

    fun monthBounds(
        monthOffset: Int,
        zoneId: ZoneId = ZoneId.systemDefault()
    ): Pair<Long, Long> {
        val targetMonth = YearMonth.now(zoneId).plusMonths(monthOffset.toLong())
        val start = targetMonth.atDay(1).atStartOfDay(zoneId).toInstant().toEpochMilli()
        val end = targetMonth
            .plusMonths(1)
            .atDay(1)
            .atStartOfDay(zoneId)
            .toInstant()
            .toEpochMilli() - 1
        return start to end
    }

    fun monthLabel(
        monthOffset: Int,
        locale: Locale = Locale.getDefault(),
        zoneId: ZoneId = ZoneId.systemDefault()
    ): String {
        val formatter = DateTimeFormatter.ofPattern("LLLL yyyy", locale)
        return YearMonth.now(zoneId)
            .plusMonths(monthOffset.toLong())
            .atDay(1)
            .format(formatter)
            .replaceFirstChar { if (it.isLowerCase()) it.titlecase(locale) else it.toString() }
    }

    fun formatDate(
        timestamp: Long,
        locale: Locale = Locale.getDefault(),
        zoneId: ZoneId = ZoneId.systemDefault()
    ): String {
        val formatter = DateTimeFormatter.ofPattern("EEE, d MMM yyyy", locale)
        return Instant.ofEpochMilli(timestamp).atZone(zoneId).toLocalDate().format(formatter)
    }

    fun formatLongDate(
        timestamp: Long,
        locale: Locale = Locale.getDefault(),
        zoneId: ZoneId = ZoneId.systemDefault()
    ): String {
        val date = Instant.ofEpochMilli(timestamp).atZone(zoneId).toLocalDate()
        if (locale.language.equals("uk", ignoreCase = true)) {
            val weekday = date.format(DateTimeFormatter.ofPattern("EEEE", locale))
            return "$weekday, ${date.dayOfMonth} " +
                "${ukrainianGenitiveMonths[date.monthValue - 1]} ${date.year}"
        }
        return date.format(DateTimeFormatter.ofPattern("EEEE, d MMMM yyyy", locale))
    }
}
