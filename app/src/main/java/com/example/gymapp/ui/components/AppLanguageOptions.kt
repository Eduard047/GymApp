package com.example.gymapp.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.example.gymapp.R
import com.example.gymapp.util.AppLanguage

/** Native full name of [language], the same in every locale ("English", "Українська", "Русский"). */
@Composable
fun AppLanguage.nativeName(): String = stringResource(
    when (this) {
        AppLanguage.EN -> R.string.language_name_english
        AppLanguage.UK -> R.string.language_name_ukrainian
        AppLanguage.RU -> R.string.language_name_russian
    }
)

/** Every selectable language paired with its native name, in menu order. */
@Composable
fun appLanguageOptions(): List<Pair<AppLanguage, String>> =
    AppLanguage.entries.map { it to it.nativeName() }
