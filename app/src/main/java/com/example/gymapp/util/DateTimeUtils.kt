package com.example.gymapp.util

import java.time.Instant
import java.time.LocalDate
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

    private val russianGenitiveMonths = listOf(
        "января",
        "февраля",
        "марта",
        "апреля",
        "мая",
        "июня",
        "июля",
        "августа",
        "сентября",
        "октября",
        "ноября",
        "декабря"
    )

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
        return formatLongDate(Instant.ofEpochMilli(timestamp).atZone(zoneId).toLocalDate(), locale)
    }

    /** Full date with the wide weekday and a genitive month, without a trailing period. */
    fun formatLongDate(
        date: LocalDate,
        locale: Locale = Locale.getDefault()
    ): String {
        if (locale.language.equals("uk", ignoreCase = true)) {
            val weekday = date.format(formatter("EEEE", locale))
            return "$weekday, ${date.dayOfMonth} " +
                "${ukrainianGenitiveMonths[date.monthValue - 1]} ${date.year}"
        }
        if (locale.language.equals("ru", ignoreCase = true)) {
            // Android's MMMM yields the nominative month for Russian; dates need the genitive.
            val weekday = date.format(formatter("EEEE", locale))
            return "$weekday, ${date.dayOfMonth} " +
                "${russianGenitiveMonths[date.monthValue - 1]} ${date.year}"
        }
        return date.format(formatter("EEEE, d MMMM yyyy", locale))
    }

    /**
     * "Sat, Sep 26" / "сб, 26 вер." / "Сб, 26 сент." — abbreviated weekday, day and
     * month; the year (with the locale's year suffix) is added only when it differs
     * from the year of [now]. Mirrors the iOS `gymShortDate` output.
     */
    fun formatShortDate(
        timestamp: Long,
        locale: Locale = Locale.getDefault(),
        zoneId: ZoneId = ZoneId.systemDefault(),
        now: Long = System.currentTimeMillis()
    ): String {
        val date = Instant.ofEpochMilli(timestamp).atZone(zoneId).toLocalDate()
        val sameYear = date.year == Instant.ofEpochMilli(now).atZone(zoneId).toLocalDate().year
        val pattern = when (locale.language.lowercase(Locale.ROOT)) {
            "en" -> if (sameYear) "EEE, MMM d" else "EEE, MMM d, yyyy"
            "uk" -> if (sameYear) "EEE, d MMM" else "EEE, d MMM yyyy 'р'."
            "ru" -> if (sameYear) "EEE, d MMM" else "EEE, d MMM yyyy 'г'."
            else -> if (sameYear) "EEE, d MMM" else "EEE, d MMM yyyy"
        }
        val text = date.format(formatter(pattern, locale))
        // Russian capitalizes the standalone weekday; Ukrainian and English do not.
        return if (locale.language.equals("ru", ignoreCase = true)) {
            text.replaceFirstChar { if (it.isLowerCase()) it.titlecase(locale) else it.toString() }
        } else {
            text
        }
    }

    /**
     * Abbreviated hour/minute duration such as "4h 31m", "4 г 31 хв" or "4 ч 31 мин" (at most two
     * units, seconds dropped). Reproduces the iOS `DateComponentsFormatter` output with the
     * abbreviated style, including Ukrainian's narrow no-break space between number and unit.
     * Returns an empty string when [seconds] is not positive.
     */
    fun formatCompactDuration(
        seconds: Long,
        locale: Locale = Locale.getDefault()
    ): String {
        if (seconds <= 0L) return ""
        val hours = seconds / 3600
        val minutes = seconds % 3600 / 60
        val (hourUnit, minuteUnit) = when (locale.language.lowercase(Locale.ROOT)) {
            "uk" -> "\u202F\u0433" to "\u202F\u0445\u0432"
            "ru" -> " \u0447" to " \u043c\u0438\u043d"
            else -> "h" to "m"
        }
        return when {
            hours == 0L -> "$minutes$minuteUnit"
            minutes == 0L -> "$hours$hourUnit"
            else -> "$hours$hourUnit $minutes$minuteUnit"
        }
    }

    /** Short date (see [formatShortDate]) for a calendar day given as days since the epoch. */
    fun formatEpochDayShort(
        epochDay: Long,
        locale: Locale = Locale.getDefault(),
        zoneId: ZoneId = ZoneId.systemDefault(),
        now: Long = System.currentTimeMillis()
    ): String {
        val timestamp = LocalDate.ofEpochDay(epochDay).atStartOfDay(zoneId).toInstant().toEpochMilli()
        return formatShortDate(timestamp, locale, zoneId, now)
    }

    /**
     * Compact date span such as "Sep 21 – 27", "21–27 вер." or "21—27 сент."; the year (with the
     * locale's suffix) is added only when the end year differs from the year of [now]. Reproduces
     * the iOS `DateIntervalFormatter` output, including its thin and narrow spaces.
     */
    fun formatDateRange(
        start: LocalDate,
        end: LocalDate,
        locale: Locale = Locale.getDefault(),
        now: LocalDate = LocalDate.now()
    ): String {
        val sameMonth = start.year == end.year && start.month == end.month
        val crossYear = start.year != end.year
        val includeYear = crossYear || end.year != now.year
        fun month(date: LocalDate) = date.format(formatter("MMM", locale))
        val startDay = start.dayOfMonth
        val endDay = end.dayOfMonth
        return when (locale.language.lowercase(Locale.ROOT)) {
            "uk" -> {
                val suffix = if (crossYear) "\u202Fрр." else "\u202Fр."
                val endYear = if (includeYear) " ${end.year}$suffix" else ""
                when {
                    sameMonth -> "$startDay\u2013$endDay ${month(end)}$endYear"
                    crossYear -> "$startDay ${month(start)} ${start.year} \u2013 $endDay ${month(end)}$endYear"
                    else -> "$startDay ${month(start)} \u2013 $endDay ${month(end)}$endYear"
                }
            }
            "ru" -> {
                val endYear = if (includeYear) " ${end.year}\u202Fг." else ""
                when {
                    sameMonth -> "$startDay\u2014$endDay ${month(end)}$endYear"
                    crossYear -> "$startDay ${month(start)} ${start.year}\u2009\u2014\u2009$endDay ${month(end)}$endYear"
                    else -> "$startDay ${month(start)}\u2009\u2014\u2009$endDay ${month(end)}$endYear"
                }
            }
            else -> {
                val endYear = if (includeYear) ", ${end.year}" else ""
                when {
                    sameMonth -> "${month(start)} $startDay\u2009\u2013\u2009$endDay$endYear"
                    crossYear -> "${month(start)} $startDay, ${start.year}\u2009\u2013\u2009${month(end)} $endDay$endYear"
                    else -> "${month(start)} $startDay\u2009\u2013\u2009${month(end)} $endDay$endYear"
                }
            }
        }
    }
}
