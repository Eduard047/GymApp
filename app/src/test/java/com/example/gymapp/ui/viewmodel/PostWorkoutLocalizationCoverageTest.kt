package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.GamificationEngine
import com.example.gymapp.util.RussianText
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PostWorkoutLocalizationCoverageTest {
    @Test
    fun ukrainianMissionCopyCoversEveryMissionEmittedByGamificationEngine() {
        val snapshot = GamificationEngine.buildSnapshot(
            sessions = emptyList(),
            nowMillis = 1_800_000_000_000L,
            zoneId = ZoneId.of("UTC")
        )
        val emittedIds = (snapshot.missions.daily + snapshot.missions.weekly)
            .mapTo(linkedSetOf()) { it.id }

        assertEquals(emptySet<String>(), emittedIds - POST_WORKOUT_MISSION_UK.keys)
        emittedIds.forEach { id ->
            val copy = requireNotNull(POST_WORKOUT_MISSION_UK[id])
            assertTrue("Mission title is blank for '$id'", copy.first.isNotBlank())
            assertTrue("Mission description is blank for '$id'", copy.second.isNotBlank())
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
    fun russianCopyCoversEveryGeneratedPostWorkoutMissionAndAchievementField() {
        val snapshot = GamificationEngine.buildSnapshot(
            sessions = emptyList(),
            nowMillis = 1_800_000_000_000L,
            zoneId = ZoneId.of("UTC")
        )
        (snapshot.missions.daily + snapshot.missions.weekly).forEach { mission ->
            assertNotEquals(mission.title, mission.title, RussianText.translate(mission.title))
            assertNotEquals(
                mission.description,
                mission.description,
                RussianText.translate(mission.description)
            )
        }
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
