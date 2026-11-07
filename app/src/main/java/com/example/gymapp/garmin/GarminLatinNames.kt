package com.example.gymapp.garmin

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import java.text.Normalizer

/** Garmin watches only ever receive English/Latin text; every sync is tagged with this language. */
internal const val GARMIN_WATCH_LANGUAGE_TAG = "en"

/** Pure view of the built-in exercise catalog that the Latin conversion needs. */
internal interface GarminBuiltInNames {
    /** The English catalog name when [raw] is a built-in exercise (catalog identity), else null. */
    fun nameEnFor(raw: String): String?

    /** True when [latin] is a string the catalog recognises (so a custom name must not equal it). */
    fun isReservedLatin(latin: String): Boolean
}

internal object CatalogGarminBuiltInNames : GarminBuiltInNames {
    override fun nameEnFor(raw: String): String? =
        BuiltInExerciseCatalog.definitionForName(raw)?.nameEn

    override fun isReservedLatin(latin: String): Boolean =
        BuiltInExerciseCatalog.inferKey(latin) != null
}

/** Payload builders refuse to send any name the watch could not render: ASCII only. */
internal fun areGarminWatchNamesAscii(
    plan: List<com.example.gymapp.data.repository.NamedWorkoutSetDraft>,
    catalog: List<String>
): Boolean = plan.all { GarminLatinNames.isAscii(it.exerciseName) } &&
    catalog.all { GarminLatinNames.isAscii(it) }

internal data class GarminLatinEntry(val latin: String, val raw: String)

internal data class GarminLatinAssignment(
    /** Trimmed raw name to the Latin name sent to the watch, for every requested name. */
    val latinByRaw: Map<String, String>,
    /** Table rows that must be appended, in assignment order. */
    val newEntries: List<GarminLatinEntry>
) {
    fun latinFor(raw: String): String? = latinByRaw[raw.trim()]
}

/**
 * Raw (possibly Cyrillic) exercise name to the ASCII name shown on the watch, and back.
 * The table below is mirrored by shared/garmin-latin-names-v1.json and tests/garmin-latin-names-contract.test.mjs.
 */
internal object GarminLatinNames {
    const val MAX_LENGTH = 160
    const val FALLBACK_NAME = "Exercise"

    // TABLE-BEGIN
    internal val TABLE: Map<Char, String> = mapOf(
        'а' to "a",
        'б' to "b",
        'в' to "v",
        'г' to "g",
        'ґ' to "g",
        'д' to "d",
        'е' to "e",
        'ё' to "yo",
        'є' to "ye",
        'ж' to "zh",
        'з' to "z",
        'и' to "y",
        'і' to "i",
        'ї' to "yi",
        'й' to "y",
        'к' to "k",
        'л' to "l",
        'м' to "m",
        'н' to "n",
        'о' to "o",
        'п' to "p",
        'р' to "r",
        'с' to "s",
        'т' to "t",
        'у' to "u",
        'ф' to "f",
        'х' to "kh",
        'ц' to "ts",
        'ч' to "ch",
        'ш' to "sh",
        'щ' to "shch",
        'ы' to "y",
        'э' to "e",
        'ю' to "yu",
        'я' to "ya"
    )
    // TABLE-END

    // DROPPED-BEGIN
    internal const val DROPPED = "ъьʼ’'"
    // DROPPED-END

    fun isAscii(value: String): Boolean = value.all { it.code in 0x20..0x7E }

    /** Plain transliteration of a non-built-in name (no collision handling). Never empty. */
    fun transliterate(raw: String): String {
        val normalized = Normalizer.normalize(raw, Normalizer.Form.NFC)
        val builder = StringBuilder()
        for (char in normalized) {
            if (char in DROPPED) continue
            val mapped = TABLE[char.lowercaseChar()]
            if (mapped != null) {
                builder.append(if (char.isUpperCase()) mapped.replaceFirstChar { it.uppercaseChar() } else mapped)
                continue
            }
            if (char.code in 0x20..0x7E) {
                builder.append(char)
                continue
            }
            // Accents: decompose this one character and keep only its ASCII base letters.
            Normalizer.normalize(char.toString(), Normalizer.Form.NFD)
                .filter { it.code in 0x20..0x7E }
                .let(builder::append)
        }
        var result = builder.toString().replace(Regex("\\s+"), " ").trim()
        val allUppercase = normalized.any { it.isUpperCase() } && normalized.none { it.isLowerCase() }
        if (allUppercase) {
            result = result.split(' ').joinToString(" ") { word ->
                word.lowercase().replaceFirstChar { it.uppercaseChar() }
            }
        }
        if (result.length > MAX_LENGTH) result = result.substring(0, MAX_LENGTH).trimEnd()
        return result.ifEmpty { FALLBACK_NAME }
    }

    /** Latin name before collision handling: built-in English name, ASCII unchanged, or translit. */
    fun baseName(raw: String, builtIns: GarminBuiltInNames = CatalogGarminBuiltInNames): String =
        builtIns.nameEnFor(raw) ?: if (isAscii(raw)) raw else transliterate(raw)

    /**
     * Assigns a Latin name to every name in [names]. [existing] is the persisted append-only table:
     * a raw name already in it keeps its Latin name; its Latin names stay reserved even when the raw
     * exercise is gone. Only transliterated names produce [GarminLatinAssignment.newEntries].
     */
    fun assign(
        names: Collection<String>,
        existing: List<GarminLatinEntry>,
        builtIns: GarminBuiltInNames = CatalogGarminBuiltInNames
    ): GarminLatinAssignment {
        val trimmed = names.map(String::trim).filter(String::isNotEmpty).distinct()
        val existingByRaw = existing.associate { it.raw to it.latin }
        val reserved = HashSet<String>()
        existing.forEach { reserved += it.latin.lowercase() }
        trimmed.filter { isAscii(it) }.forEach { reserved += it.lowercase() }

        val result = LinkedHashMap<String, String>()
        val pending = mutableListOf<String>()
        for (raw in trimmed) {
            val builtIn = builtIns.nameEnFor(raw)
            when {
                builtIn != null -> result[raw] = builtIn
                isAscii(raw) -> result[raw] = raw
                existingByRaw.containsKey(raw) -> result[raw] = existingByRaw.getValue(raw)
                else -> pending += raw
            }
        }
        val added = mutableListOf<GarminLatinEntry>()
        for (raw in pending.sortedWith(CODE_POINT_ORDER)) {
            val base = transliterate(raw)
            var candidate = base
            var number = 2
            while (candidate.lowercase() in reserved || builtIns.isReservedLatin(candidate)) {
                val suffix = " $number"
                candidate = base.take(MAX_LENGTH - suffix.length).trimEnd() + suffix
                number += 1
            }
            reserved += candidate.lowercase()
            result[raw] = candidate
            added += GarminLatinEntry(latin = candidate, raw = raw)
        }
        return GarminLatinAssignment(result, added)
    }

    /**
     * The stored exercise name a watch-echoed [latin] name stands for, or null to keep the caller's
     * existing lookup unchanged (that is how old Cyrillic names still match exactly).
     */
    fun invert(
        latin: String,
        table: Collection<GarminLatinEntry>,
        currentNames: Collection<String>,
        builtIns: GarminBuiltInNames = CatalogGarminBuiltInNames
    ): String? {
        table.firstOrNull { it.latin == latin }?.let { return it.raw }
        return currentNames.asSequence()
            .map(String::trim)
            .distinct()
            .filter { !isAscii(it) && builtIns.nameEnFor(it) == null && transliterate(it) == latin }
            .toList()
            .singleOrNull()
    }

    private val CODE_POINT_ORDER = Comparator<String> { a, b ->
        val left = a.codePoints().toArray()
        val right = b.codePoints().toArray()
        var index = 0
        while (index < left.size && index < right.size) {
            if (left[index] != right[index]) return@Comparator left[index].compareTo(right[index])
            index += 1
        }
        left.size.compareTo(right.size)
    }
}
