package com.example.gymapp.data.repository

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import com.example.gymapp.auth.AccountSession
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveWorkoutSidecarClearIfRoomTest {
    private val userId = "11111111-1111-4111-8111-111111111111"
    private val generation = "22222222-2222-4222-8222-222222222222"
    private val session = AccountSession.Cloud(
        userId = userId,
        email = "synthetic@example.test",
        displayName = "Synthetic",
        accessToken = "synthetic-access-token",
        refreshToken = null,
        sessionGeneration = generation
    )

    @Test
    fun clearsOnlyWhenBoundToTheGivenRoom() {
        val store = LiveWorkoutSidecarStore(FakeContext())
        assertTrue(store.save(session, binding(ROOM_A)))

        assertFalse(store.clearIfRoom(session, ROOM_B))
        assertNotNull(store.load(session))

        assertTrue(store.clearIfRoom(session, ROOM_A))
        assertNull(store.load(session))
        assertFalse(store.clearIfRoom(session, ROOM_A))
    }

    private fun binding(roomId: String) = LiveWorkoutBinding(
        userId = userId,
        sessionGeneration = generation,
        roomId = roomId,
        role = "owner",
        peerProfileId = "p_0123456789abcdef0123456789abcdef",
        peerDisplayName = "Peer",
        roomRevision = 1,
        membershipRevision = 1,
        progressRevision = 1,
        workoutStartedAt = 1_786_352_400_000L,
        serverToLocalSetIds = mapOf("s_01_01" to "62345678-1234-4123-8123-123456789abc")
    )

    private companion object {
        const val ROOM_A = "lr_0123456789abcdef0123456789abcdef"
        const val ROOM_B = "lr_fedcba9876543210fedcba9876543210"
    }

    private class FakeContext : ContextWrapper(null) {
        private val prefs = MemoryPrefs()
        override fun getApplicationContext(): Context = this
        override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences = prefs
    }

    private class MemoryPrefs : SharedPreferences {
        val map = mutableMapOf<String, Any?>()
        override fun getAll(): MutableMap<String, *> = map
        override fun getString(key: String?, defValue: String?): String? = map[key] as String? ?: defValue
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? = defValues
        override fun getInt(key: String?, defValue: Int) = defValue
        override fun getLong(key: String?, defValue: Long) = defValue
        override fun getFloat(key: String?, defValue: Float) = defValue
        override fun getBoolean(key: String?, defValue: Boolean) = defValue
        override fun contains(key: String?) = map.containsKey(key)
        override fun registerOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
        override fun unregisterOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
        override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
            val pending = mutableMapOf<String, Any?>()
            val removed = mutableSetOf<String>()
            override fun putString(key: String, value: String?) = apply { pending[key] = value }
            override fun putStringSet(key: String, values: MutableSet<String>?) = this
            override fun putInt(key: String, value: Int) = this
            override fun putLong(key: String, value: Long) = this
            override fun putFloat(key: String, value: Float) = this
            override fun putBoolean(key: String, value: Boolean) = this
            override fun remove(key: String) = apply { removed += key }
            override fun clear() = apply { removed += map.keys }
            override fun commit(): Boolean {
                removed.forEach { map.remove(it) }
                map.putAll(pending)
                return true
            }
            override fun apply() { commit() }
        }
    }
}
