package com.example.gymapp.util

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class AppLanguage(val tag: String) {
    EN("en"),
    UK("uk"),
    RU("ru");

    companion object {
        fun fromTag(tag: String?): AppLanguage? {
            return entries.firstOrNull { it.tag == tag }
        }
    }
}

class LanguageManager(
    context: Context
) {
    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val _selectedLanguage = MutableStateFlow(resolveCurrentLanguage())
    val selectedLanguage: StateFlow<AppLanguage> = _selectedLanguage.asStateFlow()

    fun applySavedLanguage() {
        val saved = AppLanguage.fromTag(preferences.getString(KEY_LANGUAGE, null))
        if (saved != null) {
            AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(saved.tag))
            _selectedLanguage.value = saved
        } else {
            _selectedLanguage.value = resolveCurrentLanguage()
        }
    }

    fun setLanguage(language: AppLanguage) {
        preferences.edit().putString(KEY_LANGUAGE, language.tag).apply()
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(language.tag))
        _selectedLanguage.value = language
    }

    fun currentLanguage(): AppLanguage {
        return _selectedLanguage.value
    }

    private fun resolveCurrentLanguage(): AppLanguage {
        val appLocales = AppCompatDelegate.getApplicationLocales()
        val appliedTag = if (appLocales.isEmpty) null else appLocales[0]?.language
        val tag = appliedTag ?: appContext.resources.configuration.locales[0]?.language
        return when (tag) {
            "uk" -> AppLanguage.UK
            "ru" -> AppLanguage.RU
            else -> AppLanguage.EN
        }
    }

    private companion object {
        const val PREFS_NAME = "gym_settings"
        const val KEY_LANGUAGE = "language_tag"
    }
}
