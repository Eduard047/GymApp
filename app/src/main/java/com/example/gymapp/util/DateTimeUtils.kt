package com.example.gymapp.util

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

object DateTimeUtils {
    // DateTimeFormatter is immutable. Locale stays in the key; the current zone
    // is still applied to each timestamp before formatting.
    private val formatters = LinkedHashMap<Pair<String, Locale>, DateTimeFormatter>()

    private fun formatter(pattern: String, locale: Locale): DateTimeFormatter = synchronized(formatters) {
        val key = pattern to locale
        formatters[key] ?: DateTimeFormatter.ofPattern(pattern, locale).also {
            if (formatters.size >= 16) formatters.remove(formatters.keys.first())
            formatters[key] = it
        }
    }

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
        val formatter = formatter("LLLL yyyy", locale)
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
        val formatter = formatter("EEE, d MMM yyyy", locale)
        return Instant.ofEpochMilli(timestamp).atZone(zoneId).toLocalDate().format(formatter)
    }

    fun formatLongDate(
        timestamp: Long,
        locale: Locale = Locale.getDefault(),
        zoneId: ZoneId = ZoneId.systemDefault()
    ): String {
        val date = Instant.ofEpochMilli(timestamp).atZone(zoneId).toLocalDate()
        if (locale.language.equals("uk", ignoreCase = true)) {
            val weekday = date.format(formatter("EEEE", locale))
            return "$weekday, ${date.dayOfMonth} " +
                "${ukrainianGenitiveMonths[date.monthValue - 1]} ${date.year}"
        }
        return date.format(formatter("EEEE, d MMMM yyyy", locale))
    }
}
