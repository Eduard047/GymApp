package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.util.RussianText
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AdaptiveMissionBoardSourceTest {
    private val zoneId = ZoneId.of("UTC")
    private val anchorDate = LocalDate.of(2027, 1, 15)

    @Test
    fun `workout list and summary builds keep exactly the same mission ids and targets`() {
        val before = AdaptiveMissionBoardSource.build(
            sessions = emptyList(),
            anchorDate = anchorDate,
            zoneId = zoneId
        )
        val after = AdaptiveMissionBoardSource.build(
            sessions = listOf(summary(id = 1, date = anchorDate, exercises = 20, sets = 80, volume = 50_000.0)),
            anchorDate = anchorDate,
            zoneId = zoneId
        )

        assertEquals(3, before.daily.size)
        assertEquals(3, before.weekly.size)
        assertEquals(2, before.monthly.size)
        assertEquals(listOf("workouts", "sets", "exercises"), before.daily.map { it.family })
        assertEquals(listOf("workouts", "active-days", "sets"), before.weekly.map { it.family })
        assertEquals(listOf("workouts", "sets"), before.monthly.map { it.family })
        assertEquals(before.signature(), after.signature())

        val legacyIds = setOf(
            "daily_workout",
            "daily_sets",
            "daily_exercises",
            "daily_volume",
            "weekly_days",
            "weekly_workouts",
            "weekly_sets",
            "weekly_volume"
        )
        assertTrue(before.allMissions().none { it.id in legacyIds })
        assertTrue(after.allMissions().none { it.id in legacyIds })
    }

    @Test
    fun `post workout diff can emit a monthly mission from the shared board`() {
        val sourceBoard = AdaptiveMissionBoardSource.build(
            sessions = emptyList(),
            anchorDate = anchorDate,
            zoneId = zoneId
        )
        val monthlyMission = sourceBoard.monthly.first()
        val before = sourceBoard.copy(
            monthly = sourceBoard.monthly.map { mission ->
                if (mission.id == monthlyMission.id) {
                    mission.copy(progress = (mission.goal - 1).coerceAtLeast(0))
                } else {
                    mission
                }
            }
        )
        val after = before.copy(
            monthly = before.monthly.map { mission ->
                if (mission.id == monthlyMission.id) {
                    mission.copy(progress = mission.goal)
                } else {
                    mission
                }
            }
        )

        val completed = AdaptiveMissionBoardSource.newlyCompleted(before, after)

        assertEquals(listOf(monthlyMission.id), completed.map { it.id })
        assertEquals(listOf(monthlyMission.goal), completed.map { it.goal })
        assertEquals(listOf(MissionCadence.Monthly), completed.map { it.cadence })
    }

    @Test
    fun `corrupt extreme counts are bounded before mission aggregation`() {
        val sessions = (1..WorkoutDataLimits.MAX_SESSIONS + 1).map { id ->
            summary(
                id = id.toLong(),
                date = anchorDate,
                exercises = Int.MAX_VALUE,
                sets = Int.MAX_VALUE,
                volume = Double.MAX_VALUE
            )
        }

        val board = AdaptiveMissionBoardSource.build(
            sessions = sessions,
            anchorDate = anchorDate,
            zoneId = zoneId
        )

        val missions = board.allMissions()
        assertTrue(missions.all { it.progress >= 0 })
        assertEquals(
            setOf(WorkoutDataLimits.MAX_SESSIONS),
            missions.filter { it.family == "workouts" }.mapTo(linkedSetOf()) { it.progress }
        )
    }

    @Test
    fun `mission copy uses target aware forms for one three and eight`() {
        val catalog = AdaptiveMissionBoardSource.allCatalogMissions().associateBy { it.id }

        val oneSession = requireNotNull(catalog["weekly-sessions-8-sets-1"])
        assertEquals("Finish 1 session with eight or more sets this week.", oneSession.summaryEn)
        assertEquals("Заверши 1 сесію з вісьмома або більше підходами цього тижня.", oneSession.summaryUk)
        assertEquals("session", oneSession.unitEn)
        assertEquals("сесія", oneSession.unitUk)
        assertEquals("сессия", oneSession.unitRu)

        val threeWorkouts = requireNotNull(catalog["weekly-workouts-3"])
        assertEquals("Ритм тижня", threeWorkouts.titleUk)
        assertEquals(
            "Підтримай цього тижня сталий ритм недавніх тренувань.",
            threeWorkouts.summaryUk
        )
        assertEquals("тренування", threeWorkouts.unitUk)

        val threeExercises = requireNotNull(catalog["daily-exercises-3"])
        assertEquals("Збалансована сесія", threeExercises.titleUk)
        assertEquals("Виконай реалістичну кількість вправ сьогодні.", threeExercises.summaryUk)
        assertEquals("вправи", threeExercises.unitUk)
        assertEquals("упражнения", threeExercises.unitRu)
        assertEquals("Сбалансированная сессия", RussianText.translate(threeExercises.titleEn))
        assertEquals(
            "Выполни реалистичное количество упражнений сегодня.",
            RussianText.translate(threeExercises.summaryEn)
        )

        val eightSets = requireNotNull(catalog["daily-sets-8"])
        assertEquals("Якісні підходи", eightSets.titleUk)
        assertEquals(
            "Виконай реалістичну кількість робочих підходів сьогодні.",
            eightSets.summaryUk
        )
        assertEquals("підходів", eightSets.unitUk)
        assertEquals("подходов", eightSets.unitRu)
        assertEquals("Качественные подходы", RussianText.translate(eightSets.titleEn))
        assertEquals(
            "Выполни реалистичное количество рабочих подходов сегодня.",
            RussianText.translate(eightSets.summaryEn)
        )

        val oneDay = requireNotNull(catalog["weekly-days-10-sets-1"])
        assertEquals("Hit 10 sets on 1 day this week.", oneDay.summaryEn)
        assertEquals("Зроби 10 підходів у 1 день цього тижня.", oneDay.summaryUk)
        assertEquals("day", oneDay.unitEn)
        assertEquals("день", oneDay.unitUk)
    }

    private fun summary(
        id: Long,
        date: LocalDate,
        exercises: Int,
        sets: Int,
        volume: Double
    ): WorkoutSessionSummary = WorkoutSessionSummary(
        session = WorkoutSessionEntity(
            id = id,
            date = date.atTime(12, 0).atZone(zoneId).toInstant().toEpochMilli(),
            note = null
        ),
        exerciseCount = exercises,
        setCount = sets,
        totalVolume = volume
    )

    private fun AdaptiveMissionBoard.allMissions(): List<AdaptiveMission> =
        daily + weekly + monthly

    private fun AdaptiveMissionBoard.signature(): List<Pair<String, Int>> =
        allMissions().map { mission -> mission.id to mission.goal }
}
