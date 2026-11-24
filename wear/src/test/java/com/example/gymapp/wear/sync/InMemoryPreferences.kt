package com.example.gymapp.wear.sync

import android.content.SharedPreferences

/** Minimal in-memory SharedPreferences for JVM tests. */
internal class InMemoryPreferences : SharedPreferences {
    val values = linkedMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()
    override fun getString(key: String, defValue: String?): String? = values[key] as? String ?: defValue
    override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? = defValues
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
        private val removes = linkedSetOf<String>()
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
            puts.forEach { (key, value) -> if (value == null) values.remove(key) else values[key] = value }
            return true
        }
        override fun apply() {
            commit()
        }
    }
}
