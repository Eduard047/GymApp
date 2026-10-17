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

    /**
     * The one workout-date format used on every screen: abbreviated weekday, day and month, with the
     * year only when it is not the current year. See [formatShortDate].
     */
    fun formatDate(
        timestamp: Long,
        locale: Locale = Locale.getDefault(),
        zoneId: ZoneId = ZoneId.systemDefault(),
        now: Long = System.currentTimeMillis()
    ): String = formatShortDate(timestamp, locale, zoneId, now)

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

    /** The wide weekday and day with a genitive month and no year: "субота, 15 серпня". */
    fun formatLongDateWithoutYear(
        date: LocalDate,
        locale: Locale = Locale.getDefault()
    ): String {
        val months = when (locale.language.lowercase(Locale.ROOT)) {
            "uk" -> ukrainianGenitiveMonths
            "ru" -> russianGenitiveMonths
            else -> return date.format(formatter("EEEE, d MMMM", locale))
        }
        val weekday = date.format(formatter("EEEE", locale))
        return "$weekday, ${date.dayOfMonth} ${months[date.monthValue - 1]}"
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
     * Abbreviated hour/minute duration such as "4 h 31 min", "4 год 31 хв" or "4 ч 31 мин" (at most two
     * units, seconds dropped). Reproduces the iOS `DateComponentsFormatter` output with the
     * abbreviated style.
     * Returns an empty string when [seconds] is not positive.
     */
    fun formatCompactDuration(
        seconds: Long,
        locale: Locale = Locale.getDefault()
    ): String {
        if (seconds <= 0L) return ""
        val hours = seconds / 3600
        // A positive duration shorter than a minute still reads "1 min" (matches iOS and PWA).
        val minutes = if (seconds < 60L) 1L else seconds % 3600 / 60
        val (hourUnit, minuteUnit) = when (locale.language.lowercase(Locale.ROOT)) {
            "uk" -> " \u0433\u043e\u0434" to " \u0445\u0432"
            "ru" -> " \u0447" to " \u043c\u0438\u043d"
            else -> " h" to " min"
        }
        return when {
            hours == 0L -> "$minutes$minuteUnit"
            minutes == 0L -> "$hours$hourUnit"
            else -> "$hours$hourUnit $minutes$minuteUnit"
        }
    }

    /**
     * Trend chart x-axis label: day and abbreviated month with no weekday, "Sep 8" / "8 вер." /
     * "8 сент.". The weekday is omitted because a lone initial reads as a stray letter.
     */
    fun formatChartAxisDate(
        timestamp: Long,
        locale: Locale = Locale.getDefault(),
        zoneId: ZoneId = ZoneId.systemDefault()
    ): String {
        val date = Instant.ofEpochMilli(timestamp).atZone(zoneId).toLocalDate()
        val pattern = if (locale.language.equals("en", ignoreCase = true)) "MMM d" else "d MMM"
        return date.format(formatter(pattern, locale))
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
     * Week/date-range label shared with the PWA (`fmtWeekRange`) and iOS: "12 окт. – 18 окт." (ru),
     * "12 жовт. – 18 жовт." (uk), "Oct 12 – Oct 18" (en). Both ends carry the day and abbreviated
     * month, joined by an en dash with plain spaces. The year (with the locale's suffix) is added to
     * both ends only when either end falls outside the year of [now].
     */
    fun formatDateRange(
        start: LocalDate,
        end: LocalDate,
        locale: Locale = Locale.getDefault(),
        now: LocalDate = LocalDate.now()
    ): String {
        val (from, to) = dateRangeEnds(start, end, locale, now)
        return "$from \u2013 $to"
    }

    /** Spoken form of [formatDateRange] for screen readers ("from 12 окт. to 18 окт."). */
    fun formatDateRangeSpoken(
        start: LocalDate,
        end: LocalDate,
        locale: Locale = Locale.getDefault(),
        now: LocalDate = LocalDate.now()
    ): String {
        val (from, to) = dateRangeEnds(start, end, locale, now)
        return when (locale.language.lowercase(Locale.ROOT)) {
            "uk" -> "з $from по $to"
            "ru" -> "с $from по $to"
            else -> "from $from to $to"
        }
    }

    private fun dateRangeEnds(
        start: LocalDate,
        end: LocalDate,
        locale: Locale,
        now: LocalDate
    ): Pair<String, String> {
        val includeYear = start.year != now.year || end.year != now.year
        fun part(date: LocalDate): String {
            val month = date.format(formatter("MMM", locale))
            return when (locale.language.lowercase(Locale.ROOT)) {
                "uk" -> "${date.dayOfMonth} $month" + if (includeYear) " ${date.year} \u0440." else ""
                "ru" -> "${date.dayOfMonth} $month" + if (includeYear) " ${date.year} \u0433." else ""
                else -> "$month ${date.dayOfMonth}" + if (includeYear) ", ${date.year}" else ""
            }
        }
        return part(start) to part(end)
    }
}
