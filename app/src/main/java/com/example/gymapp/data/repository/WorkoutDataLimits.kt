package com.example.gymapp.data.repository

/**
 * Shared persistence and import limits for workout data.
 *
 * These values intentionally match the iOS backup contract and the Supabase
 * progression validator so a valid GymApp backup has the same meaning on every
 * client.
 */
object WorkoutDataLimits {
    const val MAX_BACKUP_BYTES = 8 * 1_024 * 1_024
    const val MAX_JSON_NESTING_DEPTH = 16
    const val MAX_JSON_STRING_BYTES = 64 * 1_024
    const val MAX_JSON_ARRAY_ENTRIES = 100_000
    const val MAX_JSON_OBJECT_MEMBERS = 64
    const val MAX_JSON_VALUE_COUNT = 350_000
    const val MAX_JSON_NUMBER_CHARS = 128
    const val MAX_EXERCISES = 2_000
    const val MAX_SESSIONS = 5_000
    const val MAX_EXERCISES_PER_SESSION = 100
    const val MAX_SETS_PER_EXERCISE = 100
    const val MAX_TOTAL_SETS = 100_000
    const val MAX_EXERCISE_NAME_LENGTH = 160
    const val MAX_EXERCISE_NAME_BYTES = 640
    const val MAX_NOTE_LENGTH = 4_000
    const val MAX_NOTE_BYTES = 16_000
    const val MAX_ACCOUNT_IDENTIFIER_LENGTH = 256
    const val MAX_EMAIL_LENGTH = 320
    const val MAX_CATALOG_KEY_LENGTH = 128
    const val MAX_WEIGHT = 1_000_000.0
    const val MAX_REPS = 10_000

    // Foundation Date.distantPast...Date.distantFuture. Using the narrower
    // cross-platform range keeps Android backups portable to iOS while
    // preventing extreme dates from reaching UI/calendar code.
    const val MIN_TIMESTAMP_MILLIS = -62_135_769_600_000L
    const val MAX_TIMESTAMP_MILLIS = 64_092_211_200_000L

    fun isValidWeight(weight: Double): Boolean =
        weight.isFinite() && weight >= 0.0 && weight <= MAX_WEIGHT

    fun isValidReps(reps: Int): Boolean = reps in 1..MAX_REPS

    fun canAddSets(existingCount: Int, incomingCount: Int): Boolean =
        existingCount >= 0 && incomingCount >= 0 &&
            existingCount.toLong() + incomingCount.toLong() <= MAX_TOTAL_SETS.toLong()

    fun isValidTimestamp(timestamp: Long): Boolean =
        timestamp in MIN_TIMESTAMP_MILLIS..MAX_TIMESTAMP_MILLIS

    fun isValidExerciseName(name: String): Boolean =
        name.length <= MAX_EXERCISE_NAME_LENGTH * 2 &&
            utf8ByteLengthAtMost(name, MAX_EXERCISE_NAME_BYTES) != null &&
            name.codePointCount(0, name.length) <= MAX_EXERCISE_NAME_LENGTH &&
            name.none(Char::isISOControl) &&
            name.isNotBlank()

    fun isValidNote(note: String?): Boolean =
        note == null || (
            note.length <= MAX_NOTE_LENGTH * 2 &&
                utf8ByteLengthAtMost(note, MAX_NOTE_BYTES) != null &&
                note.codePointCount(0, note.length) <= MAX_NOTE_LENGTH &&
                note.all { character ->
                    !character.isISOControl() || character == '\n' || character == '\r' || character == '\t'
                }
            )

    fun isBackupProjectionWithinLimit(
        exerciseCount: Int,
        sessionCount: Int,
        workoutExerciseCount: Int,
        setCount: Int,
        textUtf8Bytes: Long
    ): Boolean {
        if (exerciseCount !in 0..MAX_EXERCISES ||
            sessionCount !in 0..MAX_SESSIONS ||
            workoutExerciseCount < 0 || workoutExerciseCount > MAX_TOTAL_SETS ||
            setCount !in 0..MAX_TOTAL_SETS ||
            textUtf8Bytes !in 0L..MAX_BACKUP_BYTES.toLong()
        ) {
            return false
        }
        val upperBound = 16_384L +
            exerciseCount.toLong() * 192L +
            sessionCount.toLong() * 192L +
            workoutExerciseCount.toLong() * 256L +
            setCount.toLong() * 64L +
            textUtf8Bytes * 2L
        return upperBound <= MAX_BACKUP_BYTES.toLong()
    }

    fun canRetainBackupText(value: String): Boolean {
        if (value.length > MAX_BACKUP_BYTES) return false
        // UTF-8 cannot exceed four bytes per UTF-16 code unit. Avoid rescanning
        // normal-sized editor updates while still enforcing the byte limit on
        // large clipboard/IME replacements before retaining them in UI state.
        return value.length <= MAX_BACKUP_BYTES / 4 ||
            utf8ByteLengthAtMost(value, MAX_BACKUP_BYTES) != null
    }

    internal fun utf8ByteLengthAtMost(value: String, maximumBytes: Int): Int? {
        var bytes = 0
        var index = 0
        while (index < value.length) {
            val codePoint = Character.codePointAt(value, index)
            bytes += when {
                codePoint <= 0x7f -> 1
                codePoint <= 0x7ff -> 2
                codePoint <= 0xffff -> 3
                else -> 4
            }
            if (bytes > maximumBytes) return null
            index += Character.charCount(codePoint)
        }
        return bytes
    }

    /**
     * Performs bounded checks that must happen before JSONObject parses the
     * attacker-controlled string. Unknown fields are allowed for forward
     * compatibility, but they cannot use the byte or nesting budget without a
     * limit.
     */
    internal fun requireSafeJsonEnvelope(
        rawJson: String,
        maximumBytes: Int = MAX_BACKUP_BYTES
    ) {
        require(maximumBytes in 1..MAX_JSON_PREFLIGHT_BYTES) {
            "JSON preflight byte limit is invalid."
        }
        require(rawJson.isNotBlank()) { "Backup JSON is empty." }
        require(rawJson.length <= maximumBytes) { "Backup exceeds the file size limit." }
        require(utf8ByteLengthAtMost(rawJson, maximumBytes) != null) {
            "Backup exceeds the file size limit."
        }
        BoundedJsonPreflight(rawJson).validate()
    }

    /**
     * Strict allocation-bounded parser used before org.json builds an object graph.
     *
     * Byte/depth checks alone still permit an 8 MiB array containing millions of primitive
     * values. Bounding members, array entries, and the total value count keeps the subsequent
     * JSONObject allocation proportional to the workout contract and rejects duplicate keys
     * before org.json can silently apply last-key-wins semantics.
     */
    private class BoundedJsonPreflight(private val raw: String) {
        private var index = 0
        private var valueCount = 0

        fun validate() {
            skipWhitespace()
            parseValue(depth = 0)
            skipWhitespace()
            require(index == raw.length) { "Backup JSON structure is malformed." }
        }

        private fun parseValue(depth: Int) {
            valueCount += 1
            require(valueCount <= MAX_JSON_VALUE_COUNT) {
                "Backup exceeds the JSON value limit."
            }
            require(index < raw.length) { "Backup JSON structure is malformed." }
            when (raw[index]) {
                '{' -> parseObject(depth + 1)
                '[' -> parseArray(depth + 1)
                '"' -> parseString()
                't' -> consumeLiteral("true")
                'f' -> consumeLiteral("false")
                'n' -> consumeLiteral("null")
                '-', in '0'..'9' -> parseNumber()
                else -> throw IllegalArgumentException("Backup JSON structure is malformed.")
            }
        }

        private fun parseObject(depth: Int) {
            require(depth <= MAX_JSON_NESTING_DEPTH) {
                "Backup exceeds the JSON nesting limit."
            }
            index += 1
            skipWhitespace()
            if (consumeIf('}')) return
            val keys = hashSetOf<String>()
            var memberCount = 0
            while (true) {
                require(index < raw.length && raw[index] == '"') {
                    "Backup JSON structure is malformed."
                }
                val key = parseString()
                memberCount += 1
                require(memberCount <= MAX_JSON_OBJECT_MEMBERS) {
                    "Backup exceeds the JSON object member limit."
                }
                require(keys.add(key)) { "Backup contains a duplicate JSON field." }
                skipWhitespace()
                require(consumeIf(':')) { "Backup JSON structure is malformed." }
                skipWhitespace()
                parseValue(depth)
                skipWhitespace()
                if (consumeIf('}')) return
                require(consumeIf(',')) { "Backup JSON structure is malformed." }
                skipWhitespace()
            }
        }

        private fun parseArray(depth: Int) {
            require(depth <= MAX_JSON_NESTING_DEPTH) {
                "Backup exceeds the JSON nesting limit."
            }
            index += 1
            skipWhitespace()
            if (consumeIf(']')) return
            var entryCount = 0
            while (true) {
                entryCount += 1
                require(entryCount <= MAX_JSON_ARRAY_ENTRIES) {
                    "Backup exceeds the JSON array entry limit."
                }
                parseValue(depth)
                skipWhitespace()
                if (consumeIf(']')) return
                require(consumeIf(',')) { "Backup JSON structure is malformed." }
                skipWhitespace()
            }
        }

        private fun parseString(): String {
            require(consumeIf('"')) { "Backup JSON structure is malformed." }
            val decoded = StringBuilder()
            while (index < raw.length) {
                val character = raw[index++]
                when {
                    character == '"' -> {
                        val value = decoded.toString()
                        require(utf8ByteLengthAtMost(value, MAX_JSON_STRING_BYTES) != null) {
                            "Backup exceeds the JSON string limit."
                        }
                        require(hasValidSurrogates(value)) {
                            "Backup contains malformed Unicode."
                        }
                        return value
                    }
                    character == '\\' -> decoded.append(parseEscape())
                    character.code < 0x20 -> throw IllegalArgumentException(
                        "Backup JSON structure is malformed."
                    )
                    else -> decoded.append(character)
                }
                require(decoded.length <= MAX_JSON_STRING_BYTES) {
                    "Backup exceeds the JSON string limit."
                }
            }
            throw IllegalArgumentException("Backup JSON structure is malformed.")
        }

        private fun parseEscape(): Char {
            require(index < raw.length) { "Backup JSON structure is malformed." }
            return when (val escaped = raw[index++]) {
                '"', '\\', '/' -> escaped
                'b' -> '\b'
                'f' -> '\u000C'
                'n' -> '\n'
                'r' -> '\r'
                't' -> '\t'
                'u' -> {
                    require(index + 4 <= raw.length) { "Backup JSON structure is malformed." }
                    val hex = raw.substring(index, index + 4)
                    require(hex.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) {
                        "Backup JSON structure is malformed."
                    }
                    index += 4
                    hex.toInt(16).toChar()
                }
                else -> throw IllegalArgumentException("Backup JSON structure is malformed.")
            }
        }

        private fun parseNumber() {
            val tokenStart = index
            if (consumeIf('-')) require(index < raw.length) { "Backup JSON structure is malformed." }
            if (consumeIf('0')) {
                require(index >= raw.length || raw[index] !in '0'..'9') {
                    "Backup JSON structure is malformed."
                }
            } else {
                require(index < raw.length && raw[index] in '1'..'9') {
                    "Backup JSON structure is malformed."
                }
                while (index < raw.length && raw[index] in '0'..'9') index += 1
            }
            if (consumeIf('.')) {
                require(index < raw.length && raw[index] in '0'..'9') {
                    "Backup JSON structure is malformed."
                }
                while (index < raw.length && raw[index] in '0'..'9') index += 1
            }
            if (index < raw.length && raw[index].lowercaseChar() == 'e') {
                index += 1
                if (index < raw.length && (raw[index] == '+' || raw[index] == '-')) index += 1
                require(index < raw.length && raw[index] in '0'..'9') {
                    "Backup JSON structure is malformed."
                }
                while (index < raw.length && raw[index] in '0'..'9') index += 1
            }
            require(index - tokenStart <= MAX_JSON_NUMBER_CHARS) {
                "Backup exceeds the JSON number length limit."
            }
        }

        private fun consumeLiteral(value: String) {
            require(raw.regionMatches(index, value, 0, value.length)) {
                "Backup JSON structure is malformed."
            }
            index += value.length
        }

        private fun skipWhitespace() {
            while (
                index < raw.length &&
                (raw[index] == ' ' || raw[index] == '\n' || raw[index] == '\r' || raw[index] == '\t')
            ) {
                index += 1
            }
        }

        private fun consumeIf(expected: Char): Boolean {
            if (index >= raw.length || raw[index] != expected) return false
            index += 1
            return true
        }

        private fun hasValidSurrogates(value: String): Boolean {
            var cursor = 0
            while (cursor < value.length) {
                val character = value[cursor]
                when {
                    character.isHighSurrogate() -> {
                        if (cursor + 1 >= value.length || !value[cursor + 1].isLowSurrogate()) {
                            return false
                        }
                        cursor += 2
                    }
                    character.isLowSurrogate() -> return false
                    else -> cursor += 1
                }
            }
            return true
        }
    }

    private const val MAX_JSON_PREFLIGHT_BYTES = 16 * 1_024 * 1_024
}
