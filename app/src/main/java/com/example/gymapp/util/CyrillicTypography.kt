package com.example.gymapp.util

private const val NO_BREAK_SPACE = '\u00A0'

/**
 * One-letter and short Russian / Ukrainian prepositions and conjunctions that must not end a line
 * ("на брусьях", "в гравитроне"). Matched as whole words, case-insensitively.
 */
private val shortWordGap = Regex(
    "(?<![\\p{L}\\p{N}])" +
        "(в|во|на|с|со|к|ко|и|а|о|об|у|по|за|из|от|до|для|не|з|із|зі|і|й|та|від)" +
        " (?=\\S)",
    RegexOption.IGNORE_CASE
)

/**
 * Display-only typography for Cyrillic text: replaces the plain space after a short preposition or
 * conjunction with a no-break space so such a word never dangles at the end of a line. Never apply
 * it to stored values; the returned text is meant to be rendered only.
 */
fun keepShortWordsWithNext(text: String): String =
    if (' ' !in text) text else shortWordGap.replace(text) { it.groupValues[1] + NO_BREAK_SPACE }
