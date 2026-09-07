package com.example.gymapp.data.repository

import com.example.gymapp.util.TrainingProgramPersistence
import com.example.gymapp.util.TrainingProgramStore
import org.junit.Assert.*
import org.junit.Test

class TrainingProgramPersistenceTest {
    private class Disk : TrainingProgramPersistence {
        var raw: String? = null
        var reject = false
        override fun read() = raw
        override fun write(value: String?): Boolean {
            raw = value // SharedPreferences can publish in memory before reporting a disk failure.
            return !reject
        }
    }

    @Test fun failedWritePreservesProgramAndRequiresReload() {
        val disk = Disk()
        val store = TrainingProgramStore("first", disk)
        assertTrue(store.create(3, "Strength"))
        val before = store.load()
        val bytes = disk.raw
        disk.reject = true
        assertFalse(store.updateStatus("completed"))
        assertTrue(store.hasError)
        assertEquals(before, store.load())
        assertEquals(bytes, disk.raw)
        assertEquals(before, TrainingProgramStore("first", disk).load())
        disk.reject = false
        assertTrue(store.reload())
        assertTrue(store.updateStatus("completed"))
    }

    @Test fun staleWriterCannotOverwriteAnotherStoresProgress() {
        val disk = Disk()
        val first = TrainingProgramStore("first", disk)
        assertTrue(first.create(3, "Strength"))
        val stale = TrainingProgramStore("first", disk)
        assertTrue(first.updateStatus("paused"))
        assertFalse(stale.updateStatus("completed"))
        assertTrue(stale.hasError)
        assertEquals("paused", TrainingProgramStore("first", disk).load()?.status)
    }

    @Test fun newCycleRequiresCompletedProgramAndMatchingIdentity() {
        val disk = Disk()
        val store = TrainingProgramStore("first", disk)
        assertTrue(store.create(3, "Strength"))
        val id = store.load()!!.id
        assertFalse(store.create(4, "Strength", replacingId = id))
        assertTrue(store.updateStatus("completed"))
        assertTrue(store.reopen())
        assertEquals(id, store.load()!!.id)
        assertTrue(store.updateStatus("completed"))
        assertFalse(store.create(4, "Strength", replacingId = id + 100))
        assertTrue(store.create(4, "Strength", replacingId = id))
        assertNotEquals(id, store.load()!!.id)
        assertEquals(16, store.load()!!.slots.size)
    }

    @Test fun corruptOrWrongOwnerDataCannotBeOverwrittenByCreate() {
        val disk = Disk()
        assertTrue(TrainingProgramStore("first", disk).create(3, "Strength"))
        val original = disk.raw
        val other = TrainingProgramStore("second", disk)
        assertTrue(other.hasError)
        assertFalse(other.create(3, "Strength"))
        assertEquals(original, disk.raw)
        disk.raw = "invalid"
        val corrupt = TrainingProgramStore("first", disk)
        assertTrue(corrupt.hasError)
        assertFalse(corrupt.create(3, "Strength"))
        assertEquals("invalid", disk.raw)
    }
}
