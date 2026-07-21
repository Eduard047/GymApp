package com.example.gymapp.data.repository

import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BackupFavoriteCompatibilityTest {
    @Test
    fun legacyBackupWithoutFavoriteRemainsValid() {
        val backup = backupWithExercise("{\"name\":\"Bench Press\"}")

        val validated = BackupImportValidator.validate(backup)

        assertNull(validated.exercises.single().isFavorite)
    }

    @Test
    fun favoriteRequiresAnActualBoolean() {
        val valid = BackupImportValidator.validate(
            backupWithExercise("{\"name\":\"Bench Press\",\"favorite\":true}")
        )
        assertTrue(valid.exercises.single().isFavorite == true)

        assertThrows(IllegalArgumentException::class.java) {
            BackupImportValidator.validate(
                backupWithExercise("{\"name\":\"Bench Press\",\"favorite\":\"true\"}")
            )
        }
    }

    @Test
    fun favoritePreferenceDoesNotChangeCanonicalCloudWorkoutIdentity() {
        val withoutFavorite = backupWithExercise("{\"name\":\"Bench Press\"}")
        val withFavorite = backupWithExercise(
            "{\"name\":\"Bench Press\",\"favorite\":true}"
        )

        assertTrue(canonicalWorkoutPayloadMatches(withoutFavorite, withFavorite))
        assertTrue(
            canonicalWorkoutPayloadDigest(withoutFavorite) ==
                canonicalWorkoutPayloadDigest(withFavorite)
        )
        assertFalse(withFavorite.getJSONArray("sessions").length() > 0)
    }

    private fun backupWithExercise(exerciseJson: String): JSONObject = JSONObject(
        """
        {
          "schemaVersion": 2,
          "exercises": [$exerciseJson],
          "sessions": []
        }
        """.trimIndent()
    )
}
