package com.example.gymapp.data.repository

import java.text.Normalizer
import java.util.UUID

data class VoiceWorkoutSet(
    val id: String,
    val weight: Double? = null,
    val reps: Int? = null
) {
    val isValid: Boolean
        get() = weight != null && reps != null &&
            VoiceWorkoutDraftParser.isValidWeight(weight) && VoiceWorkoutDraftParser.isValidReps(reps)
}

enum class VoiceWorkoutMatch { Resolved, Unresolved, Ambiguous }

data class VoiceWorkoutCandidate(
    val id: String,
    val name: String,
    val catalogKey: String?
)

enum class VoiceWorkoutBlockIssue { ChooseExercise, FixSets }

data class VoiceWorkoutBlock(
    val id: String,
    val spokenName: String,
    val exerciseId: String?,
    val catalogKey: String?,
    val match: VoiceWorkoutMatch,
    val candidates: List<VoiceWorkoutCandidate>,
    val sets: List<VoiceWorkoutSet>
) {
    /** Live readiness shared by every client: an explicit exercise and 1..100 valid sets. */
    val isValid: Boolean
        get() = exerciseId != null && sets.isNotEmpty() &&
            sets.size <= VoiceWorkoutDraftParser.MAX_SETS_PER_BLOCK && sets.all { it.isValid }

    val issue: VoiceWorkoutBlockIssue?
        get() = when {
            exerciseId == null -> VoiceWorkoutBlockIssue.ChooseExercise
            !isValid -> VoiceWorkoutBlockIssue.FixSets
            else -> null
        }
}

enum class VoiceWorkoutDiagnosticKind(val wireName: String) {
    Empty("empty"),
    TranscriptTooLong("transcriptTooLong"),
    MissingExercise("missingExercise"),
    MissingSets("missingSets"),
    InvalidNumber("invalidNumber"),
    UnknownExercise("unknownExercise"),
    AmbiguousExercise("ambiguousExercise"),
    LimitsExceeded("limitsExceeded")
}

data class VoiceWorkoutDiagnostic(
    val kind: VoiceWorkoutDiagnosticKind,
    val blockId: String? = null
)

data class VoiceWorkoutDraft(
    val blocks: List<VoiceWorkoutBlock> = emptyList(),
    val diagnostics: List<VoiceWorkoutDiagnostic> = emptyList()
)

/** One exercise the parser may resolve to, with every localized label and search alias. */
data class VoiceWorkoutExerciseInput(
    val id: String,
    val name: String,
    val catalogKey: String?,
    val aliases: List<String> = emptyList()
)

/**
 * Implements shared/voice-workout-v1.json. iOS (VoiceWorkoutDraft.swift) and the PWA
 * (pwa/voice-workout.js) use the same tables and algorithm; the shared golden cases
 * run on every client.
 */
object VoiceWorkoutDraftParser {
    const val SCHEMA_VERSION = 1
    const val MAX_TRANSCRIPT_BYTES = 8 * 1024
    const val MAX_BLOCKS = 100
    const val MAX_SETS_PER_BLOCK = 100
    const val MAX_WEIGHT = 1_000_000.0
    const val MAX_REPS = 10_000
    const val CONTAINS_MATCH_MINIMUM_LENGTH = 8
    const val AUTO_STOP_SECONDS = 60
    val LOCALES: Map<String, String> = mapOf("en" to "en-US", "uk" to "uk-UA", "ru" to "ru-RU")

    val SEPARATOR_PHRASES: List<String> = listOf(
        "и потом", "а потом", "после этого", "потом", "затем", "далее", "дальше",
        "після цього", "потім", "далі",
        "and then", "after that", "then", "next"
    )
    val SET_WORDS: List<String> = listOf(
        "подход", "подхода", "подходов", "подходы",
        "підхід", "підходи", "підходів", "підхода",
        "set", "sets"
    )
    val REP_WORDS: List<String> = listOf(
        "повтор", "повтора", "повторов", "повторы", "повторение", "повторения", "повторений", "раз", "раза",
        "повтори", "повторів", "повторення", "повторень", "рази", "разів",
        "rep", "reps", "repetition", "repetitions", "times"
    )
    val WEIGHT_WORDS: List<String> = listOf(
        "кг", "кило", "килограмм", "килограмма", "килограммов", "килограм",
        "кілограм", "кілограми", "кілограмів", "кілограма", "кіло",
        "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "kilogramme", "kilogrammes"
    )
    val WEIGHT_PREFIX_WORDS: List<String> = listOf("вес", "весом", "веса", "вага", "вагою", "ваги", "weight", "weighing")
    val CONNECTOR_WORDS: List<String> = listOf(
        "по", "на", "x", "х", "×", "с", "со", "з", "зі", "із", "и", "і", "й", "та", "а", "без", "каждый", "кожен",
        "for", "of", "by", "with", "at", "and", "each", "bodyweight"
    )
    val NUMBER_UNITS: Map<String, Int> = mapOf(
        "ноль" to 0, "один" to 1, "одна" to 1, "одно" to 1, "два" to 2, "две" to 2, "три" to 3, "четыре" to 4, "пять" to 5,
        "шесть" to 6, "семь" to 7, "восемь" to 8, "девять" to 9,
        "нуль" to 0, "одне" to 1, "дві" to 2, "чотири" to 4, "п'ять" to 5, "шість" to 6, "сім" to 7, "вісім" to 8, "дев'ять" to 9,
        "zero" to 0, "one" to 1, "two" to 2, "three" to 3, "four" to 4, "five" to 5, "six" to 6, "seven" to 7, "eight" to 8, "nine" to 9
    )
    val NUMBER_TEENS: Map<String, Int> = mapOf(
        "десять" to 10, "одиннадцать" to 11, "двенадцать" to 12, "тринадцать" to 13, "четырнадцать" to 14,
        "пятнадцать" to 15, "шестнадцать" to 16, "семнадцать" to 17, "восемнадцать" to 18, "девятнадцать" to 19,
        "одинадцять" to 11, "дванадцять" to 12, "тринадцять" to 13, "чотирнадцять" to 14, "п'ятнадцять" to 15,
        "шістнадцять" to 16, "сімнадцять" to 17, "вісімнадцять" to 18, "дев'ятнадцять" to 19,
        "ten" to 10, "eleven" to 11, "twelve" to 12, "thirteen" to 13, "fourteen" to 14, "fifteen" to 15,
        "sixteen" to 16, "seventeen" to 17, "eighteen" to 18, "nineteen" to 19
    )
    val NUMBER_TENS: Map<String, Int> = mapOf(
        "двадцать" to 20, "тридцать" to 30, "сорок" to 40, "пятьдесят" to 50, "шестьдесят" to 60,
        "семьдесят" to 70, "восемьдесят" to 80, "девяносто" to 90,
        "двадцять" to 20, "тридцять" to 30, "п'ятдесят" to 50, "шістдесят" to 60, "сімдесят" to 70,
        "вісімдесят" to 80, "дев'яносто" to 90,
        "twenty" to 20, "thirty" to 30, "forty" to 40, "fifty" to 50, "sixty" to 60, "seventy" to 70, "eighty" to 80, "ninety" to 90
    )
    val NUMBER_HUNDREDS: Map<String, Int> = mapOf(
        "сто" to 100, "двести" to 200, "триста" to 300, "четыреста" to 400, "пятьсот" to 500,
        "двісті" to 200, "чотириста" to 400, "п'ятсот" to 500
    )
    val HUNDRED_MULTIPLIERS: List<String> = listOf("hundred")
    val VOICE_ALIASES: Map<String, List<String>> = mapOf(
        "bench_press" to listOf("жим лежа", "жим лежачи", "жим штанги лежа", "жим штанги лежачи", "bench"),
        "squat" to listOf("присед", "присед со штангой", "приседания", "приседания со штангой", "присідання", "присідання зі штангою", "присід", "barbell squat", "back squat", "squats"),
        "pull_up" to listOf("подтягивания", "подтягивание", "підтягування", "pull ups", "pullups", "chin ups"),
        "push_up" to listOf("отжимания", "отжимания от пола", "віджимання", "віджимання від підлоги", "push ups", "pushups"),
        "dips" to listOf("брусья", "отжимания на брусьях", "бруси", "віджимання на брусах"),
        "deadlift" to listOf("становая", "становая тяга", "станова", "станова тяга"),
        "romanian_deadlift" to listOf("румынская тяга", "румунська тяга", "rdl"),
        "leg_press" to listOf("жим ногами", "жим ногами в тренажере", "жим ногами у тренажері"),
        "lat_pulldown" to listOf("тяга верхнего блока", "тяга верхнього блока", "вертикальная тяга"),
        "barbell_row" to listOf("тяга штанги в наклоне", "тяга штанги в нахилі"),
        "shoulder_press" to listOf("жим над головой", "армейский жим", "жим над головою", "армійський жим", "overhead press"),
        "biceps_curl" to listOf("подъем на бицепс", "бицепс", "біцепс", "curls"),
        "lunge" to listOf("выпады", "випади", "lunges"),
        "plank" to listOf("планка"),
        "calf_raise" to listOf("подъем на носки", "підйом на носки", "calf raises"),
        "lateral_raise" to listOf("махи в стороны", "махи гантелями в стороны", "розведення в сторони", "lateral raises")
    )

    private val setWordSet = SET_WORDS.toSet()
    private val repWordSet = REP_WORDS.toSet()
    private val weightWordSet = WEIGHT_WORDS.toSet()
    private val weightPrefixSet = WEIGHT_PREFIX_WORDS.toSet()
    private val connectorSet = CONNECTOR_WORDS.toSet()
    private val separatorTokens: List<List<String>> = SEPARATOR_PHRASES
        .map { it.split(" ") }
        .withIndex()
        .sortedWith(compareByDescending<IndexedValue<List<String>>> { it.value.size }.thenBy { it.index })
        .map { it.value }

    fun isValidWeight(value: Double): Boolean = value.isFinite() && value >= 0.0 && value <= MAX_WEIGHT

    fun isValidReps(value: Int): Boolean = value in 1..MAX_REPS

    fun utf8Length(value: String): Int = value.toByteArray(Charsets.UTF_8).size

    /** Cuts on code-point boundaries so the result never exceeds the byte budget. */
    fun truncateUtf8(value: String, maxBytes: Int = MAX_TRANSCRIPT_BYTES): String {
        val result = StringBuilder()
        var bytes = 0
        var index = 0
        while (index < value.length) {
            val codePoint = value.codePointAt(index)
            val size = when {
                codePoint < 0x80 -> 1
                codePoint < 0x800 -> 2
                codePoint < 0x10000 -> 3
                else -> 4
            }
            if (bytes + size > maxBytes) break
            bytes += size
            result.appendCodePoint(codePoint)
            index += Character.charCount(codePoint)
        }
        return result.toString()
    }

    fun formatWeight(value: Double?): String {
        if (value == null || !value.isFinite()) return ""
        val rounded = Math.round(value * 1000.0) / 1000.0
        return if (rounded == Math.rint(rounded) && kotlin.math.abs(rounded) < 1e15) {
            rounded.toLong().toString()
        } else {
            rounded.toString()
        }
    }

    /** null = empty field; NaN = text that is not a number. */
    fun parseWeightInput(text: String): Double? {
        val trimmed = text.trim().replace(",", ".")
        if (trimmed.isEmpty()) return null
        if (!Regex("^-?[0-9]+(\\.[0-9]+)?$").matches(trimmed)) return Double.NaN
        return trimmed.toDoubleOrNull() ?: Double.NaN
    }

    fun parse(
        transcript: String,
        exercises: List<VoiceWorkoutExerciseInput>,
        makeId: () -> String = { UUID.randomUUID().toString() }
    ): VoiceWorkoutDraft {
        if (transcript.isBlank()) {
            return VoiceWorkoutDraft(diagnostics = listOf(VoiceWorkoutDiagnostic(VoiceWorkoutDiagnosticKind.Empty)))
        }
        if (utf8Length(transcript) > MAX_TRANSCRIPT_BYTES) {
            return VoiceWorkoutDraft(diagnostics = listOf(VoiceWorkoutDiagnostic(VoiceWorkoutDiagnosticKind.TranscriptTooLong)))
        }
        val candidates = exercises.map { Candidate(it, candidateAliases(it)) }

        val entries = mutableListOf<ParsedEntry>()
        for (tokens in segment(tokenize(transcript))) {
            val name = spokenName(tokens)
            val match = matchExercise(name, candidates)
            val values = parseValues(tokens)
            val resolved = if (match.first == VoiceWorkoutMatch.Resolved) match.second.first() else null
            val existingIndex = resolved?.let { candidate ->
                entries.indexOfFirst { it.block.exerciseId == candidate.input.id }.takeIf { it >= 0 }
            }
            if (existingIndex != null) {
                val existing = entries[existingIndex]
                entries[existingIndex] = existing.copy(
                    invalid = existing.invalid || values.invalid,
                    block = existing.block.copy(
                        sets = existing.block.sets + values.sets.map { VoiceWorkoutSet(makeId(), it.weight, it.reps) }
                    )
                )
                continue
            }
            val blockId = makeId()
            entries += ParsedEntry(
                hasName = name.isNotEmpty(),
                invalid = values.invalid,
                block = VoiceWorkoutBlock(
                    id = blockId,
                    spokenName = name,
                    exerciseId = resolved?.input?.id,
                    catalogKey = resolved?.input?.catalogKey,
                    match = match.first,
                    candidates = if (match.first == VoiceWorkoutMatch.Ambiguous) {
                        match.second.map { VoiceWorkoutCandidate(it.input.id, it.input.name, it.input.catalogKey) }
                    } else {
                        emptyList()
                    },
                    sets = values.sets.map { VoiceWorkoutSet(makeId(), it.weight, it.reps) }
                )
            )
        }

        val diagnostics = mutableListOf<VoiceWorkoutDiagnostic>()
        val tooManyBlocks = entries.size > MAX_BLOCKS
        val kept = if (tooManyBlocks) entries.take(MAX_BLOCKS) else entries
        val blocks = kept.map { entry ->
            val blockId = entry.block.id
            when {
                !entry.hasName -> diagnostics += VoiceWorkoutDiagnostic(VoiceWorkoutDiagnosticKind.MissingExercise, blockId)
                entry.block.match == VoiceWorkoutMatch.Ambiguous ->
                    diagnostics += VoiceWorkoutDiagnostic(VoiceWorkoutDiagnosticKind.AmbiguousExercise, blockId)
                entry.block.match != VoiceWorkoutMatch.Resolved ->
                    diagnostics += VoiceWorkoutDiagnostic(VoiceWorkoutDiagnosticKind.UnknownExercise, blockId)
            }
            val truncated = entry.block.sets.size > MAX_SETS_PER_BLOCK
            val sets = if (truncated) entry.block.sets.take(MAX_SETS_PER_BLOCK) else entry.block.sets
            val hasInvalid = entry.invalid || sets.any { set ->
                (set.weight != null && !isValidWeight(set.weight)) || (set.reps != null && !isValidReps(set.reps))
            }
            if (hasInvalid) {
                diagnostics += VoiceWorkoutDiagnostic(VoiceWorkoutDiagnosticKind.InvalidNumber, blockId)
            } else if (sets.any { it.weight == null || it.reps == null }) {
                diagnostics += VoiceWorkoutDiagnostic(VoiceWorkoutDiagnosticKind.MissingSets, blockId)
            }
            if (truncated) diagnostics += VoiceWorkoutDiagnostic(VoiceWorkoutDiagnosticKind.LimitsExceeded, blockId)
            entry.block.copy(sets = sets)
        }
        if (tooManyBlocks) diagnostics += VoiceWorkoutDiagnostic(VoiceWorkoutDiagnosticKind.LimitsExceeded)
        return VoiceWorkoutDraft(blocks, diagnostics)
    }

    // Normalization

    internal fun normalizeWord(value: String): String = value.lowercase()
        .replace("ё", "е")
        .replace("’", "'")
        .replace("ʼ", "'")
        .replace("`", "'")

    internal fun normalizeName(value: String): String {
        val result = StringBuilder()
        var pendingSpace = false
        for (character in normalizeWord(Normalizer.normalize(value, Normalizer.Form.NFC))) {
            if (character.isLetter() || isDigit(character) || character == '\'') {
                if (pendingSpace && result.isNotEmpty()) result.append(' ')
                pendingSpace = false
                result.append(character)
            } else {
                pendingSpace = true
            }
        }
        return result.toString()
    }

    private fun isDigit(character: Char): Boolean = character in '0'..'9'

    private fun isApostrophe(character: Char): Boolean =
        character == '\'' || character == '’' || character == 'ʼ' || character == '`'

    // Tokens

    // internal (not private): reused as-is by VoiceWorkoutCommandParser so in-workout
    // voice commands share this tokenizer instead of duplicating vocabulary/parsing.
    internal sealed interface Token {
        data class Word(val raw: String, val norm: String) : Token
        data class Number(val value: Double) : Token
        data object Separator : Token
    }

    internal val Token.norm: String? get() = (this as? Token.Word)?.norm

    internal fun tokenize(transcript: String): List<Token> {
        val characters = Normalizer.normalize(transcript, Normalizer.Form.NFC)
        val tokens = mutableListOf<Token>()
        var index = 0
        fun at(position: Int): Char? = characters.getOrNull(position)
        while (index < characters.length) {
            val character = characters[index]
            val previous = at(index - 1)
            val next = at(index + 1)
            if (isDigit(character) || (character == '-' && next?.let(::isDigit) == true && previous?.let(::isDigit) != true)) {
                val text = StringBuilder().append(character)
                index += 1
                while (at(index)?.let(::isDigit) == true) text.append(characters[index++])
                val separator = at(index)
                if ((separator == '.' || separator == ',') && at(index + 1)?.let(::isDigit) == true) {
                    text.append('.')
                    index += 1
                    while (at(index)?.let(::isDigit) == true) text.append(characters[index++])
                }
                tokens += Token.Number(text.toString().toDoubleOrNull() ?: Double.NaN)
                continue
            }
            if (character == '×') {
                tokens += Token.Word("×", "×")
                index += 1
                continue
            }
            if (character.isLetter()) {
                val raw = StringBuilder().append(character)
                index += 1
                while (at(index)?.let { it.isLetter() || isApostrophe(it) } == true) raw.append(characters[index++])
                val trimmed = raw.toString().trimEnd { isApostrophe(it) }
                tokens += Token.Word(trimmed, normalizeWord(trimmed))
                continue
            }
            if (character == ';' || character == '\n' || character == '\r' || character == '.' ||
                character == '!' || character == '?'
            ) {
                tokens += Token.Separator
            }
            index += 1
        }
        return combineNumberWords(tokens)
    }

    private enum class NumberClass { Hundreds, Tens, Teens, Units, Multiplier }

    private fun numberWordClass(norm: String): Pair<NumberClass, Int>? {
        NUMBER_HUNDREDS[norm]?.let { return NumberClass.Hundreds to it }
        NUMBER_TENS[norm]?.let { return NumberClass.Tens to it }
        NUMBER_TEENS[norm]?.let { return NumberClass.Teens to it }
        NUMBER_UNITS[norm]?.let { return NumberClass.Units to it }
        if (norm in HUNDRED_MULTIPLIERS) return NumberClass.Multiplier to 100
        return null
    }

    private fun nextAllowed(kind: NumberClass, total: Int): Set<NumberClass> = when (kind) {
        NumberClass.Hundreds, NumberClass.Multiplier -> setOf(NumberClass.Tens, NumberClass.Teens, NumberClass.Units)
        NumberClass.Tens -> setOf(NumberClass.Units)
        NumberClass.Units -> if (total < 10) setOf(NumberClass.Multiplier) else emptySet()
        NumberClass.Teens -> emptySet()
    }

    private fun combineNumberWords(tokens: List<Token>): List<Token> {
        val result = mutableListOf<Token>()
        var total: Int? = null
        var allowed: Set<NumberClass> = emptySet()
        fun flush() {
            total?.let { result += Token.Number(it.toDouble()) }
            total = null
            allowed = emptySet()
        }
        for (token in tokens) {
            val info = token.norm?.let(::numberWordClass)
            if (info == null) {
                flush()
                result += token
                continue
            }
            val (kind, value) = info
            val current = total
            if (current != null && kind in allowed) {
                val updated = if (kind == NumberClass.Multiplier) current * 100 else current + value
                total = updated
                allowed = nextAllowed(kind, updated)
                continue
            }
            flush()
            if (kind == NumberClass.Multiplier) {
                result += token
                continue
            }
            total = value
            allowed = nextAllowed(kind, value)
        }
        flush()
        return result
    }

    private fun isMetadataWord(norm: String): Boolean =
        norm in connectorSet || norm in setWordSet || norm in repWordSet || norm in weightWordSet || norm in weightPrefixSet

    private fun separatorLength(tokens: List<Token>, index: Int): Int {
        for (phrase in separatorTokens) {
            val matches = phrase.indices.all { offset ->
                tokens.getOrNull(index + offset)?.norm == phrase[offset]
            }
            if (matches) return phrase.size
        }
        return 0
    }

    private fun segment(tokens: List<Token>): List<List<Token>> {
        val segments = mutableListOf<List<Token>>()
        var current = mutableListOf<Token>()
        var seenNumber = false
        fun close() {
            if (current.any { it is Token.Number || (it.norm?.let { norm -> !isMetadataWord(norm) } == true) }) {
                segments += current
            }
            current = mutableListOf()
            seenNumber = false
        }
        var index = 0
        while (index < tokens.size) {
            val token = tokens[index]
            if (token is Token.Separator) {
                close()
                index += 1
                continue
            }
            val separator = separatorLength(tokens, index)
            if (separator > 0) {
                close()
                index += separator
                continue
            }
            val norm = token.norm
            if (norm != null && seenNumber && !isMetadataWord(norm)) close()
            if (token is Token.Number) seenNumber = true
            current += token
            index += 1
        }
        close()
        return segments
    }

    private fun spokenName(tokens: List<Token>): String {
        var words = tokens.takeWhile { it !is Token.Number }.filterIsInstance<Token.Word>()
        while (words.isNotEmpty() && isMetadataWord(words.first().norm)) words = words.drop(1)
        while (words.isNotEmpty() && isMetadataWord(words.last().norm)) words = words.dropLast(1)
        return words.joinToString(" ") { it.raw }
    }

    // Matching

    private data class Candidate(val input: VoiceWorkoutExerciseInput, val aliases: Set<String>)

    private fun candidateAliases(exercise: VoiceWorkoutExerciseInput): Set<String> {
        val aliases = listOf(exercise.name) + exercise.aliases +
            (exercise.catalogKey?.let { VOICE_ALIASES[it] } ?: emptyList())
        return aliases.map(::normalizeName).filter { it.isNotEmpty() }.toSet()
    }

    private fun matchExercise(name: String, candidates: List<Candidate>): Pair<VoiceWorkoutMatch, List<Candidate>> {
        val normalized = normalizeName(name)
        if (normalized.isEmpty()) return VoiceWorkoutMatch.Unresolved to emptyList()
        val padded = " $normalized "
        val exact = mutableListOf<Candidate>()
        val contained = mutableListOf<Pair<Candidate, Int>>()
        var bestScore = 0
        for (candidate in candidates) {
            if (normalized in candidate.aliases) {
                exact += candidate
                continue
            }
            val score = candidate.aliases
                .filter { it.length >= CONTAINS_MATCH_MINIMUM_LENGTH && padded.contains(" $it ") }
                .maxOfOrNull { it.length } ?: 0
            if (score > 0) {
                contained += candidate to score
                bestScore = maxOf(bestScore, score)
            }
        }
        val chosen = if (exact.isNotEmpty()) exact else contained.filter { it.second == bestScore }.map { it.first }
        val unique = chosen.distinctBy { it.input.id }
        return when (unique.size) {
            1 -> VoiceWorkoutMatch.Resolved to unique
            0 -> VoiceWorkoutMatch.Unresolved to emptyList()
            else -> VoiceWorkoutMatch.Ambiguous to unique
        }
    }

    // Values

    private data class ParsedEntry(val hasName: Boolean, val invalid: Boolean, val block: VoiceWorkoutBlock)

    private data class RawSet(val weight: Double? = null, val reps: Int? = null)

    private data class Values(val sets: List<RawSet>, val invalid: Boolean)

    private enum class ValueTag { Set, Rep, Weight }

    private class InvalidFlag(var value: Boolean = false)

    private fun repsValue(raw: Double?, flag: InvalidFlag): Int? {
        if (raw == null) return null
        if (!raw.isFinite() || raw != Math.rint(raw) || kotlin.math.abs(raw) > Int.MAX_VALUE) {
            flag.value = true
            return null
        }
        return raw.toInt()
    }

    private fun parseValues(tokens: List<Token>): Values {
        val flag = InvalidFlag()
        val numbers = mutableListOf<Pair<Double, ValueTag?>>()
        tokens.forEachIndexed { index, token ->
            if (token !is Token.Number) return@forEachIndexed
            val next = tokens.getOrNull(index + 1)?.norm
            var tag: ValueTag? = when {
                next == null -> null
                next in setWordSet -> ValueTag.Set
                next in repWordSet -> ValueTag.Rep
                next in weightWordSet -> ValueTag.Weight
                else -> null
            }
            if (tag == null && tokens.getOrNull(index - 1)?.norm?.let { it in weightPrefixSet } == true) {
                tag = ValueTag.Weight
            }
            numbers += token.value to tag
        }
        if (numbers.isEmpty()) return Values(listOf(RawSet()), false)

        val setEntry = numbers.firstOrNull { it.second == ValueTag.Set }
        if (setEntry != null) {
            var reps = numbers.firstOrNull { it.second == ValueTag.Rep }?.first
            var weight = numbers.firstOrNull { it.second == ValueTag.Weight }?.first
            for ((value, tag) in numbers) {
                if (tag != null) continue
                if (reps == null) reps = value else if (weight == null) weight = value
            }
            val repsInteger = repsValue(reps, flag)
            if (reps == null && weight == null) return Values(listOf(RawSet()), flag.value)
            if (weight == null && repsInteger != null) weight = 0.0
            val count = setEntry.first
            if (!count.isFinite() || count != Math.rint(count) || count < 1.0) {
                flag.value = true
                return Values(listOf(RawSet(weight, repsInteger)), flag.value)
            }
            val bounded = minOf(count, (MAX_SETS_PER_BLOCK + 1).toDouble()).toInt()
            return Values(List(bounded) { RawSet(weight, repsInteger) }, flag.value)
        }

        val sets = mutableListOf<RawSet>()
        var weight: Double? = null
        var reps: Int? = null
        var hasReps = false
        fun push() {
            if (weight != null || hasReps) sets += RawSet(weight, reps)
            weight = null
            reps = null
            hasReps = false
        }
        for ((value, tag) in numbers) {
            when (tag) {
                ValueTag.Rep -> {
                    if (hasReps) push()
                    reps = repsValue(value, flag)
                    hasReps = true
                }
                ValueTag.Weight -> {
                    if (weight != null) push()
                    weight = value
                }
                else -> when {
                    weight == null && !hasReps -> weight = value
                    weight != null && !hasReps -> {
                        reps = repsValue(value, flag)
                        hasReps = true
                    }
                    weight == null -> weight = value
                    else -> {
                        push()
                        weight = value
                    }
                }
            }
            if (weight != null && hasReps) push()
        }
        push()
        return Values(sets, flag.value)
    }
}

/** Production adapter: every localized display name plus the shared search aliases. */
fun voiceWorkoutExerciseInputs(
    exercises: List<com.example.gymapp.data.entity.ExerciseEntity>
): List<VoiceWorkoutExerciseInput> = exercises.map { exercise ->
    val catalogKey = com.example.gymapp.data.catalog.BuiltInExerciseCatalog.resolvedKey(null, exercise.name)
    val displayNames = listOf("en", "uk", "ru").map {
        com.example.gymapp.data.catalog.BuiltInExerciseCatalog.displayName(exercise.name, it)
    }
    VoiceWorkoutExerciseInput(
        id = exercise.id.toString(),
        name = exercise.name,
        catalogKey = catalogKey,
        aliases = displayNames +
            (catalogKey?.let { com.example.gymapp.data.catalog.ExerciseSearchVocabulary.aliasesByKey[it] } ?: emptyList())
    )
}
