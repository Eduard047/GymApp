package com.example.gymapp.util

import androidx.appcompat.app.AppCompatDelegate
import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * App-wide "current language" signal. ViewModels survive the Activity recreation that follows an
 * in-app language switch, so any text they bake into UI state must be rebuilt when this changes.
 * The value is a BCP-47 tag: the in-app locale when one is set, otherwise the device default.
 */
object AppLanguageSignal {
    private val mutableTag = MutableStateFlow(readCurrentTag())
    val tag: StateFlow<String> = mutableTag.asStateFlow()

    fun update(tag: String) {
        mutableTag.value = tag
    }

    /** Re-reads the in-app or device locale, e.g. after a system locale change recreated the Activity. */
    fun refresh() {
        mutableTag.value = readCurrentTag()
    }

    private fun readCurrentTag(): String {
        val appLocale = try {
            AppCompatDelegate.getApplicationLocales().let { if (it.isEmpty) null else it[0] }
        } catch (_: Throwable) {
            null
        }
        return (appLocale ?: Locale.getDefault()).toLanguageTag()
    }
}

/** Picks the Ukrainian text, the Russian translation of [en], or [en] for the language of [languageTag]. */
internal fun localizedText(languageTag: String, en: String, uk: String): String =
    when (Locale.forLanguageTag(languageTag).language.lowercase(Locale.ROOT)) {
        "uk" -> uk
        "ru" -> RussianText.translate(en)
        else -> en
    }
