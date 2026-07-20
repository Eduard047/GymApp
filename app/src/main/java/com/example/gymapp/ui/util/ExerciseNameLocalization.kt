package com.example.gymapp.ui.util

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.repository.MUSCLE_DEFINITIONS
import com.example.gymapp.util.RussianText

@Composable
fun currentAppLanguageTag(): String {
    return LocalConfiguration.current.locales[0]?.language ?: "en"
}

@Composable
fun localizedExerciseName(rawName: String): String {
    return BuiltInExerciseCatalog.displayName(rawName, currentAppLanguageTag())
}

fun localizedMuscleName(muscleId: String, languageTag: String): String {
    val definition = MUSCLE_DEFINITIONS.firstOrNull { it.id == muscleId } ?: return muscleId
    return when {
        languageTag.equals("uk", ignoreCase = true) -> definition.titleUk
        languageTag.equals("ru", ignoreCase = true) -> RussianText.translate(definition.titleEn)
        else -> definition.titleEn
    }
}
