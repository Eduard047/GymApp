package com.example.gymapp.ui.viewmodel

import com.example.gymapp.util.AppLanguageSignal
import com.example.gymapp.util.localizedText
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class LanguageSwitchLabelsTest {
    private val zone: ZoneId = ZoneId.of("UTC")
    private val points = listOf(
        ExerciseProgressPoint(sessionId = 1, sessionDate = 1_700_000_000_000, maxWeight = 100.0, totalVolume = 1000.0, totalReps = 10),
        ExerciseProgressPoint(sessionId = 2, sessionDate = 1_700_600_000_000, maxWeight = 102.5, totalVolume = 1100.0, totalReps = 12)
    )

    @Test
    fun localizedTextFollowsTheLanguageTag() {
        assertEquals("Month", localizedText("en", "Month", "Місяць"))
        assertEquals("Місяць", localizedText("uk", "Month", "Місяць"))
        assertNotEquals("Month", localizedText("ru", "Month", "Місяць"))
        assertEquals("Month", localizedText("de-DE", "Month", "Місяць"))
    }

    @Test
    fun muscleLabelChangesWithLanguage() {
        val en = muscleLabelForLanguage("chest", "en")
        val uk = muscleLabelForLanguage("chest", "uk")
        val ru = muscleLabelForLanguage("chest", "ru")
        assertNotEquals(en, uk)
        assertNotEquals(uk, ru)
        assertEquals("unknown_muscle", muscleLabelForLanguage("unknown_muscle", "uk"))
    }

    @Test
    fun exerciseSpotlightAndTrendFollowTheLanguage() {
        val en = ExerciseProgressTextBuilder("en", zone)
        val uk = ExerciseProgressTextBuilder("uk", zone)
        val ru = ExerciseProgressTextBuilder("ru", zone)

        val enSpot = en.buildSpotlight(null, points, points)
        val ukSpot = uk.buildSpotlight(null, points, points)
        val ruSpot = ru.buildSpotlight(null, points, points)
        assertEquals("Exercise spotlight", enSpot.title)
        assertEquals("Фокус вправи", ukSpot.title)
        assertNotEquals(enSpot.title, ruSpot.title)
        assertEquals("Latest max", enSpot.latestWeightCaption)
        assertEquals("Останній макс", ukSpot.latestWeightCaption)
        assertEquals("102.5 kg", enSpot.latestWeightLabel)
        assertEquals("102,5 кг", ukSpot.latestWeightLabel)
        assertEquals("102,5 кг", ruSpot.latestWeightLabel)

        val enTrend = en.buildTrendChart(points)
        val ukTrend = uk.buildTrendChart(points)
        assertEquals("+2.5 kg vs first session", enTrend.weightTrendLabel)
        assertEquals("+2,5 кг відносно першої сесії", ukTrend.weightTrendLabel)
        assertEquals("12 reps", enTrend.points.last().repsLabel)
        assertEquals("12 повт", ukTrend.points.last().repsLabel)
    }

    @Test
    fun trendLabelNeedsTwoPointsAndTwoIdenticalPointsHoldSteady() {
        val en = ExerciseProgressTextBuilder("en", zone)
        val uk = ExerciseProgressTextBuilder("uk", zone)
        val ru = ExerciseProgressTextBuilder("ru", zone)

        val single = en.buildTrendChart(points.take(1))
        assertEquals("No trend yet", single.weightTrendLabel)
        assertEquals("No trend yet", single.volumeTrendLabel)
        assertEquals("Тренду ще немає", uk.buildTrendChart(points.take(1)).weightTrendLabel)
        assertEquals("Пока нет тренда", ru.buildTrendChart(points.take(1)).weightTrendLabel)

        val identical = listOf(points[0], points[0].copy(sessionId = 2, sessionDate = 1_700_600_000_000))
        val steady = en.buildTrendChart(identical)
        assertEquals("Holding steady", steady.weightTrendLabel)
        assertEquals("Holding steady", steady.volumeTrendLabel)
    }

    @Test
    fun signalPublishesUpdates() {
        val original = AppLanguageSignal.tag.value
        try {
            AppLanguageSignal.update("uk")
            assertEquals("uk", AppLanguageSignal.tag.value)
            AppLanguageSignal.update("ru")
            assertEquals("ru", AppLanguageSignal.tag.value)
        } finally {
            AppLanguageSignal.update(original)
        }
    }

    @Test
    fun latestVolumeGroupsThousandsLikeNeighbourTiles() {
        val big = listOf(
            ExerciseProgressPoint(sessionId = 3, sessionDate = 1_700_600_000_000, maxWeight = 200.0, totalVolume = 5120.4, totalReps = 20)
        )
        val enSpot = ExerciseProgressTextBuilder("en", zone).buildSpotlight(null, big, big)
        assertEquals("5,120", enSpot.latestVolumeLabel)
        assertEquals("5,120", ExerciseProgressTextBuilder("en", zone).buildTrendChart(big).points.last().volumeLabel)
    }
}
