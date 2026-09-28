package com.example.gymapp.data.repository

/**
 * In-workout voice commands: shared/voice-workout-command-v1.json. A separate entry
 * point from plan dictation (VoiceWorkoutDraftParser.parse) with its own result shape:
 * one utterance maps to one typed intent, not a list of exercise blocks.
 */
sealed class VoiceWorkoutCommand {
    data class LogSet(val weightKg: Double? = null, val reps: Int? = null) : VoiceWorkoutCommand()
    data object RepeatPrevious : VoiceWorkoutCommand()
    data object SkipRest : VoiceWorkoutCommand()
    data class Unknown(val transcript: String, val code: String? = null) : VoiceWorkoutCommand()
}

/**
 * Reserved for the caller's state (e.g. the set currently being edited) for future
 * tie-breaking. The parser itself is locale-agnostic and never reads these values,
 * mirroring pwa/voice-workout.js `parseVoiceWorkoutCommand`; per the contract's
 * clientContract, filling a missing weight/reps from the current set is the UI's job,
 * not the parser's.
 */
data class VoiceWorkoutCommandContext(
    val currentWeightKg: Double? = null,
    val currentReps: Int? = null
)

/**
 * Implements shared/voice-workout-command-v1.json. iOS and the PWA
 * (pwa/voice-workout.js parseVoiceWorkoutCommand/finalizeLogSetCommand) use the same
 * tables and algorithm; the shared golden cases run on every client. Reuses
 * VoiceWorkoutDraftParser's tokenizer and its REP_WORDS/WEIGHT_WORDS/CONNECTOR_WORDS/
 * NUMBER_WORDS tables verbatim instead of redefining command vocabulary.
 */
object VoiceWorkoutCommandParser {
    const val MIN_WEIGHT_KG = 0.0
    const val MAX_WEIGHT_KG = 1000.0
    const val WEIGHT_STEP_KG = 0.25
    const val MIN_REPS = 1
    const val MAX_REPS = 200
    val MAX_TRANSCRIPT_BYTES: Int get() = VoiceWorkoutDraftParser.MAX_TRANSCRIPT_BYTES

    val COMMAND_FILLER_WORDS: List<String> = listOf(
        "ну", "эм", "окей", "ага",
        "емм", "гаразд",
        "um", "uh", "okay", "ok"
    )
    val COMMAND_BODYWEIGHT_PHRASES: List<String> = listOf(
        "с собственным весом", "собственным весом", "своим весом",
        "власною вагою", "власним вагою", "з власною вагою",
        "bodyweight", "body weight", "own bodyweight"
    )
    val COMMAND_REPEAT_PHRASES: List<String> = listOf(
        "повтори", "ещё раз так же", "то же самое", "повтор",
        "ще раз",
        "repeat", "same again"
    )
    val COMMAND_SKIP_PHRASES: List<String> = listOf(
        "дальше", "пропусти отдых", "готов", "поехали",
        "далі", "пропусти відпочинок", "готовий",
        "next", "skip rest", "ready"
    )
    val COMMAND_DIAGNOSTIC_CODES: List<String> = listOf(
        "empty", "transcriptTooLong",
        "ambiguousNumbers", "weightOutOfRange", "repsOutOfRange", "invalidWeightStep",
        "noMatch"
    )

    private val commandFillerSet = COMMAND_FILLER_WORDS.toSet()
    private val weightWordSet = VoiceWorkoutDraftParser.WEIGHT_WORDS.toSet()
    private val repWordSet = VoiceWorkoutDraftParser.REP_WORDS.toSet()
    private val connectorSet = VoiceWorkoutDraftParser.CONNECTOR_WORDS.toSet()

    private fun toPhraseWords(phrase: String): List<String> =
        phrase.split(" ").map { VoiceWorkoutDraftParser.normalizeWord(it) }

    // Longest phrase first so a longer bodyweight phrase wins over a shorter one it
    // contains (e.g. "з власною вагою" over "власною вагою").
    private val commandBodyweightPhraseWords: List<List<String>> =
        COMMAND_BODYWEIGHT_PHRASES.map(::toPhraseWords).sortedByDescending { it.size }
    private val commandRepeatPhraseWords: List<List<String>> = COMMAND_REPEAT_PHRASES.map(::toPhraseWords)
    private val commandSkipPhraseWords: List<List<String>> = COMMAND_SKIP_PHRASES.map(::toPhraseWords)

    /** Never throws: any unexpected failure resolves to Unknown(transcript, "noMatch"). */
    fun parse(
        transcript: String?,
        locale: String = "ru",
        context: VoiceWorkoutCommandContext? = null
    ): VoiceWorkoutCommand {
        val raw = transcript ?: ""
        return try {
            parseInternal(raw)
        } catch (error: Throwable) {
            if (error is InterruptedException) throw error
            VoiceWorkoutCommand.Unknown(raw, "noMatch")
        }
    }

    private fun parseInternal(raw: String): VoiceWorkoutCommand {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return VoiceWorkoutCommand.Unknown(raw, "empty")
        if (VoiceWorkoutDraftParser.utf8Length(raw) > MAX_TRANSCRIPT_BYTES) {
            return VoiceWorkoutCommand.Unknown(VoiceWorkoutDraftParser.truncateUtf8(raw, MAX_TRANSCRIPT_BYTES), "transcriptTooLong")
        }

        var tokens: List<VoiceWorkoutDraftParser.Token> = VoiceWorkoutDraftParser.tokenize(raw)
            .filterNot { it is VoiceWorkoutDraftParser.Token.Separator }
        tokens = tokens.filterNot { token ->
            token is VoiceWorkoutDraftParser.Token.Word && token.norm in commandFillerSet
        }

        val hasNumber = tokens.any { it is VoiceWorkoutDraftParser.Token.Number }
        if (!hasNumber) {
            if (wordSequenceMatchesAny(tokens, commandRepeatPhraseWords)) return VoiceWorkoutCommand.RepeatPrevious
            if (wordSequenceMatchesAny(tokens, commandSkipPhraseWords)) return VoiceWorkoutCommand.SkipRest
            return VoiceWorkoutCommand.Unknown(raw, "noMatch")
        }

        var isBodyweight = false
        val bodyweightRun = findPhraseRun(tokens, commandBodyweightPhraseWords)
        if (bodyweightRun != null) {
            val (start, length) = bodyweightRun
            tokens = tokens.subList(0, start) + tokens.subList(start + length, tokens.size)
            isBodyweight = true
        }

        data class NumberEntry(val value: Double, val tag: String?, val index: Int)

        val numberEntries = mutableListOf<NumberEntry>()
        tokens.forEachIndexed { index, token ->
            if (token !is VoiceWorkoutDraftParser.Token.Number) return@forEachIndexed
            val next = tokens.getOrNull(index + 1)
            val tag = if (next is VoiceWorkoutDraftParser.Token.Word) {
                when {
                    next.norm in weightWordSet -> "weight"
                    next.norm in repWordSet -> "rep"
                    else -> null
                }
            } else {
                null
            }
            numberEntries += NumberEntry(token.value, tag, index)
        }

        if (isBodyweight) {
            if (numberEntries.size != 1) return VoiceWorkoutCommand.Unknown(raw, "ambiguousNumbers")
            return finalizeLogSetCommand(raw, 0.0, numberEntries[0].value)
        }

        if (numberEntries.isEmpty()) return VoiceWorkoutCommand.Unknown(raw, "noMatch")

        if (numberEntries.size == 1) {
            val only = numberEntries[0]
            return when (only.tag) {
                "weight" -> finalizeLogSetCommand(raw, only.value, null)
                "rep" -> finalizeLogSetCommand(raw, null, only.value)
                else -> VoiceWorkoutCommand.Unknown(raw, "ambiguousNumbers")
            }
        }

        if (numberEntries.size == 2) {
            val first = numberEntries[0]
            val second = numberEntries[1]
            val taggedWeight = numberEntries.filter { it.tag == "weight" }
            val taggedRep = numberEntries.filter { it.tag == "rep" }
            val untagged = numberEntries.filter { it.tag == null }
            if (taggedWeight.size == 1 && taggedRep.size == 1) {
                return finalizeLogSetCommand(raw, taggedWeight[0].value, taggedRep[0].value)
            }
            if (taggedWeight.size == 1 && untagged.size == 1) {
                return finalizeLogSetCommand(raw, taggedWeight[0].value, untagged[0].value)
            }
            if (taggedRep.size == 1 && untagged.size == 1) {
                return finalizeLogSetCommand(raw, untagged[0].value, taggedRep[0].value)
            }
            if (untagged.size == 2) {
                val between = tokens.subList(first.index + 1, second.index)
                val hasConnector = between.any { token ->
                    token is VoiceWorkoutDraftParser.Token.Word && token.norm in connectorSet
                }
                if (hasConnector) return finalizeLogSetCommand(raw, first.value, second.value)
            }
            return VoiceWorkoutCommand.Unknown(raw, "ambiguousNumbers")
        }

        return VoiceWorkoutCommand.Unknown(raw, "ambiguousNumbers")
    }

    private fun wordSequenceMatches(tokens: List<VoiceWorkoutDraftParser.Token>, phraseWords: List<String>): Boolean {
        if (tokens.size != phraseWords.size) return false
        return tokens.indices.all { index ->
            val token = tokens[index]
            token is VoiceWorkoutDraftParser.Token.Word && token.norm == phraseWords[index]
        }
    }

    private fun wordSequenceMatchesAny(
        tokens: List<VoiceWorkoutDraftParser.Token>,
        phraseWordsList: List<List<String>>
    ): Boolean = phraseWordsList.any { wordSequenceMatches(tokens, it) }

    // First contiguous run of word tokens equal to one of phraseWordsList (longest
    // phrase first, see commandBodyweightPhraseWords). Returns (start, length).
    private fun findPhraseRun(
        tokens: List<VoiceWorkoutDraftParser.Token>,
        phraseWordsList: List<List<String>>
    ): Pair<Int, Int>? {
        for (phraseWords in phraseWordsList) {
            var start = 0
            while (start + phraseWords.size <= tokens.size) {
                var matches = true
                for (offset in phraseWords.indices) {
                    val token = tokens.getOrNull(start + offset)
                    if (token !is VoiceWorkoutDraftParser.Token.Word || token.norm != phraseWords[offset]) {
                        matches = false
                        break
                    }
                }
                if (matches) return start to phraseWords.size
                start += 1
            }
        }
        return null
    }

    private fun finalizeLogSetCommand(raw: String, weightKg: Double?, repsRaw: Double?): VoiceWorkoutCommand {
        if (weightKg != null) {
            if (!weightKg.isFinite() || weightKg < MIN_WEIGHT_KG || weightKg > MAX_WEIGHT_KG) {
                return VoiceWorkoutCommand.Unknown(raw, "weightOutOfRange")
            }
            val scaled = weightKg / WEIGHT_STEP_KG
            if (kotlin.math.abs(scaled - Math.rint(scaled)) > 1e-6) {
                return VoiceWorkoutCommand.Unknown(raw, "invalidWeightStep")
            }
        }
        var reps: Int? = null
        if (repsRaw != null) {
            val isInteger = repsRaw.isFinite() && repsRaw == Math.rint(repsRaw) && kotlin.math.abs(repsRaw) <= Int.MAX_VALUE
            val repsInt = if (isInteger) repsRaw.toInt() else null
            if (repsInt == null || repsInt < MIN_REPS || repsInt > MAX_REPS) {
                return VoiceWorkoutCommand.Unknown(raw, "repsOutOfRange")
            }
            reps = repsInt
        }
        return VoiceWorkoutCommand.LogSet(weightKg, reps)
    }
}
