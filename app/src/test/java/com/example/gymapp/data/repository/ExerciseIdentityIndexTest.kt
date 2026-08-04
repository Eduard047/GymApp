package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ExerciseIdentityIndexTest {
    @Test
    fun `exact legacy name wins while ambiguous portable-only lookup is rejected`() {
        val index = ExerciseIdentityIndex(
            listOf(
                ExerciseEntity(id = 11, name = "Legacy Custom"),
                ExerciseEntity(id = 12, name = "Legacy\u00a0Custom")
            )
        )

        assertEquals(11L, index.resolve("Legacy Custom", catalogKey = null))
        assertEquals(12L, index.resolve("Legacy\u00a0Custom", catalogKey = null))
        assertThrows(IllegalArgumentException::class.java) {
            index.resolve("Legacy\u2007Custom", catalogKey = null)
        }
    }

    @Test
    fun `ambiguous built-in aliases fail closed unless the raw name is exact`() {
        val index = ExerciseIdentityIndex(
            listOf(
                ExerciseEntity(id = 21, name = "Bench Press"),
                ExerciseEntity(id = 22, name = "Жим лежачи")
            )
        )

        assertEquals(21L, index.resolve("Bench Press", catalogKey = "bench_press"))
        assertEquals(22L, index.resolve("Жим лежачи", catalogKey = "bench_press"))
        assertThrows(IllegalArgumentException::class.java) {
            index.resolve("BENCH PRESS", catalogKey = "bench_press")
        }
    }
}
