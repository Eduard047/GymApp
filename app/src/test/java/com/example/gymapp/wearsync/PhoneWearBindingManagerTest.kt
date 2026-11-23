package com.example.gymapp.wearsync

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneWearBindingManagerTest {
    @Test
    fun unlinkForgetsOnlyThePinnedWatchAndAllowsALaterRepin() {
        val prefs = InMemoryPreferences()
        val manager = PhoneWearBindingManager(prefs)
        // A signed-out phone never pins; use a bound (non-signed-out) binding.
        val binding = PhoneWearAccountBinding(ownerId = "a".repeat(64), accountGeneration = 1, signedOut = false)
        prefs.edit().putLong("active_generation", 7L).putLong("full_sync_revision", 3L)
            .putString("receipt_marker", "kept").commit()

        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), binding))
        assertEquals("watch-1", manager.pinnedSourceNodeId())
        assertEquals("watch-1", manager.pinnedSource()?.nodeId)
        // While pinned, another watch is refused.
        assertFalse(manager.authorizeSource("watch-2", setOf("watch-2"), binding))

        assertTrue(manager.clearPinnedSource())
        assertNull(manager.pinnedSourceNodeId())
        assertNull(manager.pinnedSource())
        assertFalse(manager.isPinnedNode("watch-1"))
        // Nothing but the pin is touched: generations, revisions and other stored data stay.
        assertEquals(7L, prefs.getLong("active_generation", 0L))
        assertEquals(3L, prefs.getLong("full_sync_revision", 0L))
        assertEquals("kept", prefs.getString("receipt_marker", null))

        // A later valid request from a single connected watch may pin again (any watch).
        assertTrue(manager.authorizeSource("watch-2", setOf("watch-2"), binding))
        assertEquals("watch-2", manager.pinnedSourceNodeId())
    }

    @Test
    fun unlinkWithoutAPinIsHarmless() {
        val manager = PhoneWearBindingManager(InMemoryPreferences())
        assertTrue(manager.clearPinnedSource())
        assertNull(manager.pinnedSourceNodeId())
    }

    /** Minimal in-memory SharedPreferences for JVM tests. */
    private class InMemoryPreferences : SharedPreferences {
        val values = linkedMapOf<String, Any?>()

        override fun getAll(): MutableMap<String, *> = values.toMutableMap()
        override fun getString(key: String, defValue: String?): String? = values[key] as? String ?: defValue
        override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? =
            @Suppress("UNCHECKED_CAST") (values[key] as? MutableSet<String>) ?: defValues
        override fun getInt(key: String, defValue: Int): Int = values[key] as? Int ?: defValue
        override fun getLong(key: String, defValue: Long): Long = values[key] as? Long ?: defValue
        override fun getFloat(key: String, defValue: Float): Float = values[key] as? Float ?: defValue
        override fun getBoolean(key: String, defValue: Boolean): Boolean = values[key] as? Boolean ?: defValue
        override fun contains(key: String): Boolean = key in values
        override fun edit(): SharedPreferences.Editor = Editor()
        override fun registerOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?
        ) = Unit
        override fun unregisterOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?
        ) = Unit

        private inner class Editor : SharedPreferences.Editor {
            private val puts = linkedMapOf<String, Any?>()
            private val removes = mutableSetOf<String>()
            private var clear = false

            override fun putString(key: String, value: String?) = apply { puts[key] = value }
            override fun putStringSet(key: String, values: MutableSet<String>?) = apply { puts[key] = values }
            override fun putInt(key: String, value: Int) = apply { puts[key] = value }
            override fun putLong(key: String, value: Long) = apply { puts[key] = value }
            override fun putFloat(key: String, value: Float) = apply { puts[key] = value }
            override fun putBoolean(key: String, value: Boolean) = apply { puts[key] = value }
            override fun remove(key: String) = apply { removes += key }
            override fun clear() = apply { clear = true }
            override fun commit(): Boolean {
                if (clear) values.clear()
                removes.forEach(values::remove)
                values.putAll(puts)
                return true
            }
            override fun apply() {
                commit()
            }
        }
    }
}
