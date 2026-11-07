package com.example.gymapp.ui.screens

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BackupPdfReportTest {
    // Cyrillic capitals are wider than Latin lowercase in a real font; model that.
    private val measure: (String) -> Float = { text ->
        text.sumOf { ch ->
            when {
                ch == ' ' -> 3
                ch.isUpperCase() -> 8
                ch.code > 0x400 -> 6
                else -> 5
            }
        }.toFloat()
    }

    @Test
    fun twoHundredSessionsKeepNewestSixtyNewestFirst() {
        val dates = List(200) { 1_000L + it }
        val picked = selectPdfSessionIndices(dates, 60)
        assertEquals(60, picked.size)
        assertEquals(199, picked.first())
        assertEquals(140, picked.last())
        assertEquals(200 - picked.size, 140)
        assertEquals(picked.sortedDescending(), picked)
    }

    @Test
    fun selectionSortsByDateEvenWhenBackupOrderIsShuffled() {
        val picked = selectPdfSessionIndices(listOf(30L, 10L, 50L, 20L, 50L), 3)
        assertEquals(listOf(4, 2, 0), picked)
        assertEquals(listOf(1, 0), selectPdfSessionIndices(listOf(1L, 2L), 60))
    }

    @Test
    fun wrappedLinesNeverExceedWidth() {
        val text = "Тренування " + "ПРИСІДАННЯ СО ШТАНГОЮ НА ПЛЕЧАХ ".repeat(8) + "А".repeat(120)
        val width = 120f
        val lines = wrapPdfText(text, width, measure)
        assertTrue(lines.size > 1)
        lines.forEach { assertTrue("'$it' too wide", measure(it) <= width) }
    }

    @Test
    fun shortAndEmptyTextStayOnOneLine() {
        assertEquals(listOf("abc"), wrapPdfText("abc", 100f, measure))
        assertEquals(listOf(""), wrapPdfText("", 100f, measure))
    }

    @Test
    fun wrappingKeepsAllWordsInOrder() {
        val text = "one two three four five six seven eight nine ten"
        val lines = wrapPdfText(text, 60f, measure)
        assertEquals(text, lines.joinToString(" "))
    }

    @Test
    fun weightTextUsesLocaleSeparator() {
        assertEquals("82,5", pdfWeightText(82.5, Locale.forLanguageTag("uk")))
        assertEquals("82,5", pdfWeightText(82.5, Locale.forLanguageTag("ru")))
        assertEquals("82.5", pdfWeightText(82.5, Locale.forLanguageTag("en")))
        assertEquals("60", pdfWeightText(60.0, Locale.forLanguageTag("uk")))
        assertEquals("0", pdfWeightText(Double.NaN, Locale.forLanguageTag("uk")))
    }

    @Test
    fun aGlyphWiderThanTheLineStillTerminates() {
        val lines = wrapPdfText("ab W", maxWidth = 5f) { text -> if (text.contains('W')) 100f else text.length.toFloat() }
        assertEquals(listOf("ab", "W"), lines)
    }
}
