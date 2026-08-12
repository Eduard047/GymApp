package com.example.gymapp

import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.data.repository.GamificationEngine
import com.example.gymapp.data.repository.RANK_DEFINITIONS
import com.example.gymapp.data.repository.nextRankDefinitionAfter
import com.example.gymapp.data.repository.rankDefinitionForLevel
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class GamificationParityTest {
    @Test
    fun canonicalRankLadderUsesTheSameThresholdsAsTheProductUi() {
        assertEquals("Rookie", rankDefinitionForLevel(1).titleEn)
        assertEquals("Starter", rankDefinitionForLevel(4).titleEn)
        assertEquals("Steady", rankDefinitionForLevel(5).titleEn)
        assertEquals("Steady", nextRankDefinitionAfter(4)?.titleEn)
        assertEquals(null, nextRankDefinitionAfter(RANK_DEFINITIONS.last().levelRequirement))
    }

    @Test
    fun canonicalProgressionMatchesCrossPlatformGoldenFixture() {
        val rows = requireNotNull(javaClass.getResourceAsStream("/progression-v1.tsv")) {
            "Missing progression-v1.tsv"
        }.bufferedReader().useLines { lines ->
            lines
                .filterNot { it.isBlank() || it.startsWith("#") || it.startsWith("case_id") }
                .map(::parseRow)
                .toList()
        }

        rows.forEach { row ->
            val sessions = row.sessions.mapIndexed { index, input ->
                WorkoutSessionSummary(
                    session = WorkoutSessionEntity(
                        id = (index + 1).toLong(),
                        date = 1_700_000_000_000L + index * 86_400_000L,
                        note = null
                    ),
                    exerciseCount = input.exerciseCount,
                    setCount = input.setCount,
                    totalVolume = input.volume
                )
            }
            val snapshot = GamificationEngine.buildSnapshot(
                sessions = sessions,
                nowMillis = 1_800_000_000_000L,
                zoneId = ZoneId.of("UTC")
            )

            assertEquals(row.id, row.expectedTotalXP, sessions.sumOf(GamificationEngine::xpForSession))
            assertEquals(row.id, row.expectedTotalXP, snapshot.progression.totalXp)
            assertEquals(row.id, row.expectedTotalXP, snapshot.progression.baseXp)
            assertEquals(row.id, 0, snapshot.progression.bonusXp)
            assertEquals(row.id, row.expectedLevel, snapshot.progression.level)
            assertEquals(row.id, row.expectedLevelStartXP, GamificationEngine.xpForLevelStart(row.expectedLevel))
            assertEquals(row.id, row.expectedNextLevelXP, GamificationEngine.xpForLevelStart(row.expectedLevel + 1))
        }
    }

    @Test(timeout = 1_000)
    fun maximumIntegerXpUsesBoundedSaturatingProgressionMath() {
        val level = GamificationEngine.levelForXp(Int.MAX_VALUE)

        assertTrue(level > 1)
        assertTrue(GamificationEngine.xpForLevelStart(level) <= Int.MAX_VALUE)
        assertEquals(Int.MAX_VALUE, GamificationEngine.xpForLevelStart(level + 1))
        assertEquals(1, GamificationEngine.levelForXp(Int.MIN_VALUE))
    }

    @Test
    fun nonFiniteStoredVolumeCannotPoisonXp() {
        val session = WorkoutSessionSummary(
            session = WorkoutSessionEntity(date = 1_700_000_000_000L, note = null),
            exerciseCount = 1,
            setCount = 1,
            totalVolume = Double.POSITIVE_INFINITY
        )

        assertEquals(114, GamificationEngine.xpForSession(session))
    }

    @Test
    fun emptySessionsEarnNoXpAndSingleSessionXpIsCapped() {
        val empty = WorkoutSessionSummary(
            session = WorkoutSessionEntity(date = 1_700_000_000_000L, note = null),
            exerciseCount = 100,
            setCount = 0,
            totalVolume = 1_000_000.0
        )
        val extreme = WorkoutSessionSummary(
            session = WorkoutSessionEntity(date = 1_700_000_000_000L, note = null),
            exerciseCount = Int.MAX_VALUE,
            setCount = Int.MAX_VALUE,
            totalVolume = Double.MAX_VALUE
        )

        assertEquals(0, GamificationEngine.xpForSession(empty))
        assertEquals(GamificationEngine.MAX_SESSION_XP, GamificationEngine.xpForSession(extreme))
        assertEquals(5_000, GamificationEngine.MAX_SESSION_XP)
    }

    @Test
    fun visibleStreakAchievementsUseProfileTargetAndStableLegacyIdsAtTwoFourEightWeeks() {
        val zone = ZoneId.of("Europe/Kyiv")
        val firstMonday = LocalDate.of(2026, 1, 5)
        val sessions = (0L until 8L).flatMap { week ->
            listOf(
                session((week * 10 + 1).toLong(), firstMonday.plusWeeks(week)),
                session((week * 10 + 2).toLong(), firstMonday.plusWeeks(week).plusDays(2))
            )
        }
        val now = firstMonday.plusWeeks(9).atStartOfDay(zone).toInstant().toEpochMilli()

        val twoDayTarget = GamificationEngine.buildSnapshot(
            sessions = sessions,
            nowMillis = now,
            zoneId = zone,
            targetWorkoutsPerWeek = 2
        ).achievements.filter { it.id.startsWith("streak_") }

        assertEquals(listOf("streak_7", "streak_14", "streak_30"), twoDayTarget.map { it.id })
        assertEquals(listOf(2.0, 4.0, 8.0), twoDayTarget.map { it.target })
        assertEquals(listOf("Two-Week Rhythm", "Four-Week Rhythm", "Eight-Week Rhythm"), twoDayTarget.map { it.title })
        assertTrue(twoDayTarget.all { it.progress == 8.0 && it.unlocked })

        val threeDayTarget = GamificationEngine.buildSnapshot(
            sessions = sessions + sessions.take(8),
            nowMillis = now,
            zoneId = zone,
            targetWorkoutsPerWeek = 3
        ).achievements.filter { it.id.startsWith("streak_") }
        assertTrue(threeDayTarget.all { it.progress == 0.0 })
        assertTrue(threeDayTarget.none { it.unlocked })
    }

    @Test
    fun weeklyAchievementProgressSurvivesRestDaysButConsecutiveWeeksStillMatter() {
        val zone = ZoneId.of("UTC")
        val firstMonday = LocalDate.of(2026, 3, 2)
        val sessions = (0L until 5L)
            .filter { it != 2L }
            .flatMap { week ->
                listOf(
                    session((week * 10 + 1).toLong(), firstMonday.plusWeeks(week)),
                    session((week * 10 + 2).toLong(), firstMonday.plusWeeks(week).plusDays(4))
                )
            }
        val now = firstMonday.plusWeeks(6).atStartOfDay(zone).toInstant().toEpochMilli()
        val streaks = GamificationEngine.buildSnapshot(
            sessions = sessions,
            nowMillis = now,
            zoneId = zone,
            targetWorkoutsPerWeek = 2
        ).achievements.filter { it.id.startsWith("streak_") }

        assertEquals(2.0, streaks.first().progress, 0.0)
        assertTrue(streaks.first().unlocked)
        assertFalse(streaks[1].unlocked)
        assertThrows(IllegalArgumentException::class.java) {
            GamificationEngine.buildSnapshot(emptyList(), now, zone, targetWorkoutsPerWeek = 1)
        }
    }

    @Test
    fun futureWeeksCannotProgressWeeklyStreakAchievements() {
        val zone = ZoneId.of("UTC")
        val today = LocalDate.of(2026, 3, 2)
        val futureSessions = (1L..8L).flatMap { week ->
            listOf(
                session(week * 10 + 1, today.plusWeeks(week)),
                session(week * 10 + 2, today.plusWeeks(week).plusDays(2))
            )
        }

        val streaks = GamificationEngine.buildSnapshot(
            sessions = futureSessions,
            nowMillis = today.atStartOfDay(zone).toInstant().toEpochMilli(),
            zoneId = zone,
            targetWorkoutsPerWeek = 2
        ).achievements.filter { it.id.startsWith("streak_") }

        assertTrue(streaks.all { it.progress == 0.0 && !it.unlocked })
    }

    @Test
    fun laterTodaySessionCannotCompleteWeeklyStreakAchievementEarly() {
        val zone = ZoneId.of("UTC")
        val monday = LocalDate.of(2026, 3, 2)
        val now = monday.plusDays(1).atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
        val laterToday = WorkoutSessionSummary(
            session = WorkoutSessionEntity(
                id = 2L,
                date = monday.plusDays(1).atTime(18, 0).atZone(zone).toInstant().toEpochMilli(),
                note = null
            ),
            exerciseCount = 1,
            setCount = 3,
            totalVolume = 100.0
        )
        val streaks = GamificationEngine.buildSnapshot(
            sessions = listOf(session(1L, monday), laterToday),
            nowMillis = now,
            zoneId = zone,
            targetWorkoutsPerWeek = 2
        ).achievements.filter { it.id.startsWith("streak_") }

        assertTrue(streaks.all { it.progress == 0.0 && !it.unlocked })
    }

    private fun session(id: Long, date: LocalDate): WorkoutSessionSummary = WorkoutSessionSummary(
        session = WorkoutSessionEntity(
            id = id,
            date = date.atTime(12, 0).atZone(ZoneId.of("UTC")).toInstant().toEpochMilli(),
            note = null
        ),
        exerciseCount = 1,
        setCount = 3,
        totalVolume = 100.0
    )

    private fun parseRow(line: String): GoldenRow {
        val columns = line.split('\t')
        require(columns.size == 6) { "Invalid progression fixture row: $line" }
        return GoldenRow(
            id = columns[0],
            sessions = columns[1].split(';').map { encoded ->
                val values = encoded.split(',')
                require(values.size == 3) { "Invalid session tuple: $encoded" }
                SessionInput(values[0].toInt(), values[1].toInt(), values[2].toDouble())
            },
            expectedTotalXP = columns[2].toInt(),
            expectedLevel = columns[3].toInt(),
            expectedLevelStartXP = columns[4].toInt(),
            expectedNextLevelXP = columns[5].toInt()
        )
    }

    private data class SessionInput(
        val exerciseCount: Int,
        val setCount: Int,
        val volume: Double
    )

    private data class GoldenRow(
        val id: String,
        val sessions: List<SessionInput>,
        val expectedTotalXP: Int,
        val expectedLevel: Int,
        val expectedLevelStartXP: Int,
        val expectedNextLevelXP: Int
    )
}
