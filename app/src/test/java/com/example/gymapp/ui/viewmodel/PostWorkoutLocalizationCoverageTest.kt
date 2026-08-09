package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.GamificationEngine
import com.example.gymapp.util.RussianText
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PostWorkoutLocalizationCoverageTest {
    @Test
    fun sharedMissionBoardCarriesUkrainianCopyForEveryCadence() {
        val board = AdaptiveMissionBoardSource.build(
            sessions = emptyList(),
            anchorDate = LocalDate.of(2027, 1, 15),
            zoneId = ZoneId.of("UTC")
        )
        val missions = board.daily + board.weekly + board.monthly

        assertEquals(3, board.daily.size)
        assertEquals(3, board.weekly.size)
        assertEquals(2, board.monthly.size)
        missions.forEach { mission ->
            assertTrue("English mission title is blank for '${mission.id}'", mission.titleEn.isNotBlank())
            assertTrue("Ukrainian mission title is blank for '${mission.id}'", mission.titleUk.isNotBlank())
            assertTrue("English mission summary is blank for '${mission.id}'", mission.summaryEn.isNotBlank())
            assertTrue("Ukrainian mission summary is blank for '${mission.id}'", mission.summaryUk.isNotBlank())
        }
    }

    @Test
    fun ukrainianAchievementCopyCoversEveryAchievementEmittedByGamificationEngine() {
        val snapshot = GamificationEngine.buildSnapshot(
            sessions = emptyList(),
            nowMillis = 1_800_000_000_000L,
            zoneId = ZoneId.of("UTC")
        )
        val emittedIds = snapshot.achievements.mapTo(linkedSetOf()) { it.id }

        assertEquals(emptySet<String>(), emittedIds - POST_WORKOUT_ACHIEVEMENT_UK.keys)
        emittedIds.forEach { id ->
            val copy = requireNotNull(POST_WORKOUT_ACHIEVEMENT_UK[id])
            assertTrue("Achievement title is blank for '$id'", copy.title.isNotBlank())
            assertTrue("Achievement description is blank for '$id'", copy.description.isNotBlank())
            assertTrue("Achievement badge is blank for '$id'", copy.badgeName.isNotBlank())
        }
    }

    @Test
    fun russianCopyCoversEveryMissionCatalogAndAchievementField() {
        AdaptiveMissionBoardSource.allCatalogMissions().forEach { mission ->
            assertNotEquals(
                mission.titleEn,
                mission.titleEn,
                RussianText.translate(mission.titleEn)
            )
            assertNotEquals(
                mission.summaryEn,
                mission.summaryEn,
                RussianText.translate(mission.summaryEn)
            )
            assertNotEquals(
                mission.unitEn,
                mission.unitEn,
                RussianText.translate(mission.unitEn)
            )
            assertTrue("Russian mission unit is blank for '${mission.id}'", mission.unitRu.isNotBlank())
        }
        listOf("Daily", "Weekly", "Monthly", "Today", "This week", "This month").forEach { label ->
            assertNotEquals(label, label, RussianText.translate(label))
        }
        val snapshot = GamificationEngine.buildSnapshot(
            sessions = emptyList(),
            nowMillis = 1_800_000_000_000L,
            zoneId = ZoneId.of("UTC")
        )
        snapshot.achievements.forEach { achievement ->
            assertNotEquals(
                achievement.title,
                achievement.title,
                RussianText.translate(achievement.title)
            )
            assertNotEquals(
                achievement.description,
                achievement.description,
                RussianText.translate(achievement.description)
            )
            assertNotEquals(
                achievement.badge.name,
                achievement.badge.name,
                RussianText.translate(achievement.badge.name)
            )
        }
    }
}
