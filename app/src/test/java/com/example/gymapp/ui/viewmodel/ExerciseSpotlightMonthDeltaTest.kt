package com.example.gymapp.ui.viewmodel

import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Test

/** The spotlight compares this month with the previous month, like iOS ProgressView. */
class ExerciseSpotlightMonthDeltaTest {
    private val zone: ZoneId = ZoneId.of("UTC")

    private fun point(id: Long, date: String, weight: Double, volume: Double) = ExerciseProgressPoint(
        sessionId = id,
        sessionDate = LocalDate.parse(date).atStartOfDay(zone).toInstant().toEpochMilli(),
        maxWeight = weight,
        totalVolume = volume,
        totalReps = 10
    )

    // Audit scenario: Nov 3 80 kg, Nov 20 75 kg; October best 70 kg.
    private val november = listOf(
        point(2, "2026-11-03", 80.0, 800.0),
        point(3, "2026-11-20", 75.0, 750.0)
    )
    private val october = listOf(point(1, "2026-10-10", 70.0, 700.0))

    @Test
    fun monthBestAndVolumeAreComparedWithThePreviousMonth() {
        val spot = ExerciseProgressTextBuilder("en", zone)
            .buildSpotlight(null, november, october + november, october)
        assertEquals("+10 kg vs prior month", spot.weightDeltaLabel)
        assertEquals("+850 volume vs prior month", spot.volumeDeltaLabel)
        assertEquals("80 kg", spot.allTimeBestWeightLabel)

        val uk = ExerciseProgressTextBuilder("uk", zone)
            .buildSpotlight(null, november, october + november, october)
        assertEquals("+10 кг до попереднього місяця", uk.weightDeltaLabel)
        val ru = ExerciseProgressTextBuilder("ru", zone)
            .buildSpotlight(null, november, october + november, october)
        assertEquals("+10 кг к прошлому месяцу", ru.weightDeltaLabel)
        assertEquals("+850 объёма к прошлому месяцу", ru.volumeDeltaLabel)
    }

    @Test
    fun lowerMonthBestShowsMinusAndEqualShowsNoChange() {
        val en = ExerciseProgressTextBuilder("en", zone)
        val heavierOctober = listOf(point(1, "2026-10-10", 85.0, 1550.0))
        val lower = en.buildSpotlight(null, november, heavierOctober + november, heavierOctober)
        assertEquals("−5.0 kg vs prior month", lower.weightDeltaLabel)
        assertEquals("No change vs prior month", lower.volumeDeltaLabel)
    }

    @Test
    fun emptyPreviousMonthIsTheFirstMonth() {
        val en = ExerciseProgressTextBuilder("en", zone)
            .buildSpotlight(null, november, november, emptyList())
        assertEquals("First month for best weight", en.weightDeltaLabel)
        assertEquals("First month for volume", en.volumeDeltaLabel)

        val uk = ExerciseProgressTextBuilder("uk", zone)
            .buildSpotlight(null, november, november, emptyList())
        assertEquals("Перший місяць для «найкраща вага»", uk.weightDeltaLabel)
        assertEquals("Перший місяць для «обсяг»", uk.volumeDeltaLabel)
        val ru = ExerciseProgressTextBuilder("ru", zone)
            .buildSpotlight(null, november, november, emptyList())
        assertEquals("Первый месяц для «лучший вес»", ru.weightDeltaLabel)
        assertEquals("Первый месяц для «объём»", ru.volumeDeltaLabel)
    }

    @Test
    fun singleSessionMonthStillComparesWithThePreviousMonth() {
        val single = november.take(1)
        val spot = ExerciseProgressTextBuilder("en", zone)
            .buildSpotlight(null, single, october + single, october)
        assertEquals("+10 kg vs prior month", spot.weightDeltaLabel)
        assertEquals("+100 volume vs prior month", spot.volumeDeltaLabel)

        val firstEver = ExerciseProgressTextBuilder("en", zone)
            .buildSpotlight(null, single, single, emptyList())
        assertEquals("First month for best weight", firstEver.weightDeltaLabel)
        assertEquals("80 kg", firstEver.allTimeBestWeightLabel)
    }

    @Test
    fun bestTileShowsTheAllTimeWeightOrADashWithoutAPrPrefix() {
        val en = ExerciseProgressTextBuilder("en", zone)
        assertEquals("80 kg", en.buildSpotlight(null, emptyList(), october + november, october).allTimeBestWeightLabel)
        assertEquals("\u2014", en.buildSpotlight(null, emptyList(), emptyList(), emptyList()).allTimeBestWeightLabel)
    }

    @Test
    fun tilesShowTheMonthBestAndTheMonthVolume() {
        val spot = ExerciseProgressTextBuilder("en", zone)
            .buildSpotlight(null, november, october + november, october)
        assertEquals("Month best", spot.latestWeightCaption)
        assertEquals("80 kg", spot.latestWeightLabel)
        assertEquals("Month volume", spot.latestVolumeCaption)
        assertEquals("1,550", spot.latestVolumeLabel)
    }

    @Test
    fun emptySelectedMonthSaysThereIsNoDataThisMonth() {
        val en = ExerciseProgressTextBuilder("en", zone).buildSpotlight(null, emptyList(), october, october)
        assertEquals("No best weight in this month", en.weightDeltaLabel)
        assertEquals("No volume in this month", en.volumeDeltaLabel)
        assertEquals("\u2014", en.latestWeightLabel)
        assertEquals("0", en.latestVolumeLabel)
        assertEquals("70 kg", en.allTimeBestWeightLabel)
        assertEquals("0 this month", en.consistencyLabel)

        val uk = ExerciseProgressTextBuilder("uk", zone).buildSpotlight(null, emptyList(), october, october)
        assertEquals("Немає показника «найкраща вага» цього місяця", uk.weightDeltaLabel)
        val ru = ExerciseProgressTextBuilder("ru", zone).buildSpotlight(null, emptyList(), october, october)
        assertEquals("Нет показателя «объём» в этом месяце", ru.volumeDeltaLabel)
    }
}
