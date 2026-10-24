package com.example.gymapp.util

import android.content.Context
import android.content.res.Configuration
import androidx.annotation.PluralsRes
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import java.util.IllegalFormatException
import java.util.Locale

/*
 * Crash-proof formatted resources.
 *
 * Store-injected machine translations can break a format template (for example `%1$s` turned into
 * `%1$d`), and the platform then throws IllegalFormatException while rendering. Every resource that
 * takes format arguments goes through these helpers instead of stringResource/getString with
 * arguments: a broken localized template falls back to the default (English) template, and if that
 * also fails the unformatted localized text is shown. Arguments are never logged; they can hold
 * user data.
 */

/** Same resource lookup as Compose's stringResource, but never throws on a broken format template. */
@Composable
@ReadOnlyComposable
fun formattedStringResource(@StringRes id: Int, vararg formatArgs: Any): String {
    // Read the configuration first so a locale change recomposes callers, as stringResource does.
    LocalConfiguration.current
    return LocalContext.current.safeGetString(id, *formatArgs)
}

/** Same resource lookup as Compose's pluralStringResource, but never throws on a broken template. */
@Composable
@ReadOnlyComposable
fun formattedPluralStringResource(
    @PluralsRes id: Int,
    count: Int,
    vararg formatArgs: Any
): String {
    LocalConfiguration.current
    return LocalContext.current.safeGetQuantityString(id, count, *formatArgs)
}

fun Context.safeGetString(@StringRes id: Int, vararg formatArgs: Any): String =
    formatWithFallback(
        localizedTemplate = resources.getString(id),
        locale = resources.configuration.primaryLocale(),
        formatArgs = formatArgs,
        defaultTemplate = { defaultResourcesContext().resources.getString(id) }
    )

fun Context.safeGetQuantityString(
    @PluralsRes id: Int,
    quantity: Int,
    vararg formatArgs: Any
): String =
    formatWithFallback(
        localizedTemplate = resources.getQuantityString(id, quantity),
        locale = resources.configuration.primaryLocale(),
        formatArgs = formatArgs,
        defaultTemplate = { defaultResourcesContext().resources.getQuantityString(id, quantity) }
    )

/**
 * Formats [localizedTemplate]; when it is malformed, formats the lazily loaded default template
 * with the same arguments, and when that fails too returns [localizedTemplate] unformatted.
 */
internal fun formatWithFallback(
    localizedTemplate: String,
    locale: Locale,
    formatArgs: Array<out Any>,
    defaultTemplate: () -> String?
): String {
    try {
        return String.format(locale, localizedTemplate, *formatArgs)
    } catch (_: IllegalFormatException) {
        // Fall through to the default template below.
    }
    val fallback = try {
        defaultTemplate()
    } catch (_: Exception) {
        null
    } ?: return localizedTemplate
    return try {
        String.format(locale, fallback, *formatArgs)
    } catch (_: IllegalFormatException) {
        localizedTemplate
    }
}

/** A context whose resources resolve from the default `values/` folder (English), keeping the rest. */
private fun Context.defaultResourcesContext(): Context =
    createConfigurationContext(
        Configuration(resources.configuration).apply { setLocale(Locale.ROOT) }
    )

private fun Configuration.primaryLocale(): Locale =
    locales.takeUnless { it.isEmpty }?.get(0) ?: Locale.getDefault()
