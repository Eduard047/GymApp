package com.example.gymapp.util

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource

/** Keeps user-facing state language-neutral until it is rendered. */
data class LocalizedText(
    @param:StringRes @get:StringRes val resourceId: Int,
    val formatArguments: List<Any>
) {
    constructor(@StringRes resourceId: Int) : this(resourceId, emptyList())

    constructor(
        @StringRes resourceId: Int,
        firstFormatArgument: Any,
        vararg remainingFormatArguments: Any
    ) : this(resourceId, listOf(firstFormatArgument) + remainingFormatArguments)
}

@Composable
fun LocalizedText.asString(): String = stringResource(
    resourceId,
    *formatArguments.toTypedArray()
)

fun Context.getString(text: LocalizedText): String = getString(
    text.resourceId,
    *text.formatArguments.toTypedArray()
)
