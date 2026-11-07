package com.example.gymapp.util

import android.content.Context
import android.content.res.Configuration
import android.os.Build
import androidx.appcompat.app.AppCompatDelegate
import java.util.Locale

/**
 * The locale the in-app language setting asks for, or null to leave the context alone.
 *
 * Below API 33 AppCompat localizes Activity contexts only, so a service, receiver or notifier
 * working from an application context sees the system locale. A process started by one of those
 * has not run `applySavedLanguage` yet either, so the saved choice is the fallback. From API 33
 * the system applies the per-app locale to every context itself.
 */
internal fun resolveAppLocale(appCompatLocale: Locale?, savedTag: String?, sdkInt: Int): Locale? {
    if (appCompatLocale != null) return appCompatLocale
    if (sdkInt >= Build.VERSION_CODES.TIRAMISU) return null
    return AppLanguage.fromTag(savedTag)?.let { Locale.forLanguageTag(it.tag) }
}

/** Whether [target] already matches the first locale in [current], so no new context is needed. */
internal fun isSameLanguage(current: Locale?, target: Locale): Boolean =
    current != null && current.language == target.language

/** A context whose resources follow the in-app language; the same context when nothing applies. */
internal fun Context.withAppLanguage(): Context {
    val appContext = applicationContext ?: this
    val locale = try {
        val appCompatLocales = AppCompatDelegate.getApplicationLocales()
        val saved = appContext
            .getSharedPreferences(LanguageManager.PREFS_NAME, Context.MODE_PRIVATE)
            .getString(LanguageManager.KEY_LANGUAGE, null)
        resolveAppLocale(
            appCompatLocale = if (appCompatLocales.isEmpty) null else appCompatLocales[0],
            savedTag = saved,
            sdkInt = Build.VERSION.SDK_INT
        )
    } catch (_: Exception) {
        null
    } ?: return this
    val configuration = Configuration(resources.configuration)
    if (isSameLanguage(configuration.locales.takeUnless { it.isEmpty }?.get(0), locale)) return this
    return try {
        configuration.setLocale(locale)
        createConfigurationContext(configuration)
    } catch (_: Exception) {
        this
    }
}
