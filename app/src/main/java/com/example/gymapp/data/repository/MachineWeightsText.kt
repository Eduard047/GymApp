package com.example.gymapp.data.repository

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * Text form of a machine's allowed-weights list, shared with iPhone (shared/machine-weights-v1.json).
 *
 * Tokens are separated by ASCII whitespace, newlines, ';', or a comma followed by whitespace or the
 * end of the text. A comma between digits is always a decimal separator ("12,5" is 12.5), so
 * "10,20,30" is invalid. A token is ASCII digits with one optional '.' or ',' and 1 to 2 decimals.
 */
object MachineWeightsText {
    const val MAX_TEXT_BYTES = 2_048

    private val separatorChars = setOf(' ', '\t', '\n', '\r', '\u000B', '\u000C')
    private val tokenPattern = Regex("[0-9]+(?:[.,][0-9]{1,2})?")

    /** Sorted, distinct weights, or null when the text is not a valid list. */
    fun parse(raw: String): List<Double>? {
        if (raw.toByteArray(Charsets.UTF_8).size > MAX_TEXT_BYTES) return null
        val tokens = tokens(raw)
        if (tokens.isEmpty() || tokens.size > ExerciseLoadProfile.MAX_WEIGHT_OPTIONS) return null
        val parsed = tokens.map { token ->
            if (!tokenPattern.matches(token)) return null
            token.replace(',', '.').toDoubleOrNull()?.takeIf(WorkoutDataLimits::isValidWeight)
                ?: return null
        }
        return parsed.distinct().sorted()
    }

    /** Editor text for one weight: at most 2 decimals, '.' separator, no grouping or exponent. */
    fun format(weight: Double): String =
        BigDecimal(weight).setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()

    private fun tokens(raw: String): List<String> {
        val result = mutableListOf<String>()
        val current = StringBuilder()
        fun flush() {
            if (current.isNotEmpty()) {
                result += current.toString()
                current.clear()
            }
        }
        for ((index, char) in raw.withIndex()) {
            val endsToken = char == ';' || char in separatorChars ||
                (char == ',' && (index + 1 == raw.length || raw[index + 1] in separatorChars))
            if (endsToken) flush() else current.append(char)
        }
        flush()
        return result
    }
}
