package com.example.gymapp.util

import org.junit.Assert.assertEquals
import org.junit.Test

class RussianTextTest {
    @Test
    fun translatesRepresentativeMissionCopy() {
        assertEquals("Завершить тренировку", RussianText.translate("Complete a workout"))
        assertEquals(
            "Выполни тридцать подходов за эту неделю.",
            RussianText.translate("Accumulate thirty sets this week.")
        )
        assertEquals(
            "Подходов сегодня: 12.",
            RussianText.translate("Reach 12 total sets today.")
        )
    }

    @Test
    fun translatesRepresentativeAchievementCopy() {
        assertEquals("Первая тренировка", RussianText.translate("First Workout"))
        assertEquals("Возвращение", RussianText.translate("Comeback"))
        assertEquals("Первое повторение", RussianText.translate("First Rep"))
        assertEquals("Стабильный прогресс", RussianText.translate("Consistency Builder"))
        assertEquals("Объём 10 000", RussianText.translate("Ten Thousand Volume"))
        assertEquals("Объём 50 000", RussianText.translate("Fifty Thousand Volume"))
        assertEquals("Темп", RussianText.translate("Momentum"))
        assertEquals(
            "Набери общий объём 50 000.",
            RussianText.translate("Accumulate fifty thousand total volume.")
        )
    }

    @Test
    fun usesTheCorrectPluralMuscleName() {
        assertEquals("Предплечья", RussianText.translate("Forearms"))
    }

    @Test
    fun translatesRepresentativeRankTitles() {
        assertEquals("Новичок", RussianText.translate("Rookie"))
        assertEquals("Стабильный", RussianText.translate("Steady"))
        assertEquals("Космический воевода", RussianText.translate("Cosmic Warlord"))
    }
}
