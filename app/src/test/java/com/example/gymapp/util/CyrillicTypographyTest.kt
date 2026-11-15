package com.example.gymapp.util

import org.junit.Assert.assertEquals
import org.junit.Test

class CyrillicTypographyTest {
    private val nb = "\u00A0"

    @Test
    fun bindsShortPrepositionsAfterWhichTheNameMayWrap() {
        assertEquals("Жим штанги лежа на${nb}скамье", keepShortWordsWithNext("Жим штанги лежа на скамье"))
        assertEquals(
            "Отжимания на${nb}брусьях в${nb}гравитроне",
            keepShortWordsWithNext("Отжимания на брусьях в гравитроне")
        )
    }

    @Test
    fun matchesWholeWordsAndCaseOnly() {
        // "на" inside "Отжимания" and "в" inside "Приседания" are not standalone words.
        assertEquals("Приседания со${nb}штангой", keepShortWordsWithNext("Приседания со штангой"))
        assertEquals("На${nb}турнике", keepShortWordsWithNext("На турнике"))
        assertEquals("Тяга в${nb}наклоне", keepShortWordsWithNext("Тяга в наклоне"))
        assertEquals("Bench Press", keepShortWordsWithNext("Bench Press"))
        assertEquals("Подтягивания", keepShortWordsWithNext("Подтягивания"))
    }

    @Test
    fun ukrainianWordsAndTrailingPrepositionStayIntact() {
        assertEquals("Присідання з${nb}гантелями", keepShortWordsWithNext("Присідання з гантелями"))
        assertEquals("Жим на ", keepShortWordsWithNext("Жим на "))
        assertEquals("", keepShortWordsWithNext(""))
    }

    @Test
    fun neverTouchesOtherSpaces() {
        assertEquals("Жим  штанги", keepShortWordsWithNext("Жим  штанги"))
    }
}
