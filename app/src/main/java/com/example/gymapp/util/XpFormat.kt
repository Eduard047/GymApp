package com.example.gymapp.util

import java.text.NumberFormat
import java.util.Locale

/** Formats an XP amount with the locale's digit grouping, like the iOS `.formatted(.number)`. */
fun formatXp(xp: Int, locale: Locale): String =
    NumberFormat.getIntegerInstance(locale).format(xp.toLong())
