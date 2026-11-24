package com.example.gymapp.health

import com.example.gymapp.data.repository.ActivityOnlyWorkoutItem
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.util.AppLanguage

/**
 * Pure decision and mapping rules for the read-only Health Connect / HealthKit import.
 * Mirrors shared/health-import-v1.json, which is the source of truth for both clients; the golden
 * cases in that file run against this object in HealthImportRulesTest. No Android dependencies.
 */
internal data class HealthTypeLabel(val en: String, val uk: String, val ru: String) {
    fun forLanguage(language: AppLanguage): String = when (language) {
        AppLanguage.UK -> uk
        AppLanguage.RU -> ru
        AppLanguage.EN -> en
    }
}

internal enum class HealthImportStore(
    val wire: String,
    val receiptKeyPrefix: String,
    val notePrefix: String,
    val ownSourceIds: Set<String>,
    val typeLabels: Map<String, HealthTypeLabel>
) {
    HEALTH_CONNECT(
        wire = "healthConnect",
        receiptKeyPrefix = "health_connect:",
        notePrefix = "Health Connect",
        ownSourceIds = setOf("com.setforge.gymapp", "com.setforge.gymapp.dev"),
        typeLabels = linkedMapOf(
            "STRENGTH_TRAINING" to HealthTypeLabel(
                "Strength training", "Силове тренування", "Силовая тренировка"
            ),
            "WEIGHTLIFTING" to HealthTypeLabel(
                "Weightlifting", "Важка атлетика", "Тяжёлая атлетика"
            ),
            "CALISTHENICS" to HealthTypeLabel("Calisthenics", "Калістеніка", "Калистеника"),
            "HIGH_INTENSITY_INTERVAL_TRAINING" to HealthTypeLabel("HIIT", "HIIT", "HIIT"),
            "GYMNASTICS" to HealthTypeLabel("Gymnastics", "Гімнастика", "Гимнастика"),
            "BOOT_CAMP" to HealthTypeLabel("Boot camp", "Буткемп", "Буткемп")
        )
    ),
    HEALTH_KIT(
        wire = "healthKit",
        receiptKeyPrefix = "apple_health:",
        notePrefix = "Apple Health",
        ownSourceIds = setOf("com.setforge.gymapp.ios", "com.setforge.gymapp.ios.watchkitapp"),
        typeLabels = linkedMapOf(
            "traditionalStrengthTraining" to HealthTypeLabel(
                "Strength training", "Силове тренування", "Силовая тренировка"
            ),
            "functionalStrengthTraining" to HealthTypeLabel(
                "Functional strength training",
                "Функціональне силове тренування",
                "Функциональная силовая тренировка"
            ),
            "coreTraining" to HealthTypeLabel(
                "Core training", "Тренування м’язів кора", "Тренировка мышц кора"
            ),
            "highIntensityIntervalTraining" to HealthTypeLabel("HIIT", "HIIT", "HIIT"),
            "crossTraining" to HealthTypeLabel("Cross training", "Крос-тренінг", "Кросс-тренинг"),
            "gymnastics" to HealthTypeLabel("Gymnastics", "Гімнастика", "Гимнастика")
        )
    );

    val gymExerciseTypes: Set<String> get() = typeLabels.keys

    fun receiptKey(recordId: String): String = receiptKeyPrefix + recordId

    companion object {
        fun fromWire(wire: String): HealthImportStore? = entries.firstOrNull { it.wire == wire }
    }
}

internal data class HeartRateSample(val timeMillis: Long, val bpm: Long)

/**
 * One exercise record as read from the store. [kilocalories] and [heartRateSamples] are loaded
 * only after the cheap checks pass, so a header-only session has the defaults.
 */
internal data class HealthImportSession(
    val recordId: String,
    val startMillis: Long,
    val endMillis: Long,
    val exerciseType: String?,
    val sourceId: String?,
    val kilocalories: Double? = null,
    val heartRateSamples: List<HeartRateSample> = emptyList()
)

internal data class HealthExistingWorkout(val startMillis: Long, val durationSeconds: Long?)

internal enum class HealthImportSkipReason(val wire: String) {
    INVALID_RECORD("invalid-record"),
    OWN_APP("own-app"),
    NOT_GYM_TYPE("not-gym-type"),
    DURATION("duration"),
    IN_PROGRESS("in-progress"),
    DUPLICATE_RECEIPT("duplicate-receipt"),
    OVERLAP("overlap")
}

/** Result of the transactional write in GymRepository.importHealthActivity. */
internal enum class HealthImportPersistResult {
    IMPORTED,
    DUPLICATE_RECEIPT,
    OVERLAP,
    CAPACITY_REACHED
}

internal sealed interface HealthImportDecision {
    data class Import(val receiptKey: String, val item: ActivityOnlyWorkoutItem) :
        HealthImportDecision

    data class Skip(val reason: HealthImportSkipReason) : HealthImportDecision
}

internal object HealthImportRules {
    const val SCHEMA_VERSION = 1
    const val WINDOW_DAYS = 30
    const val MAX_SESSIONS_PER_RUN = 200
    const val MAX_RECORDS_SCANNED_PER_RUN = 1_000
    const val MIN_DURATION_SECONDS = 60L
    const val MAX_DURATION_SECONDS = 86_400L
    const val OVERLAP_TOLERANCE_SECONDS = 120L
    const val OVERLAP_TOLERANCE_MILLIS = OVERLAP_TOLERANCE_SECONDS * 1_000L
    const val MIN_AUTO_IMPORT_INTERVAL_SECONDS = 3_600L
    const val MIN_PLAUSIBLE_BPM = 25L
    const val MAX_PLAUSIBLE_BPM = 240L
    const val MAX_KILOCALORIES = 100_000.0
    const val MAX_RECEIPT_KEY_LENGTH = 256
    const val MAX_HEART_RATE_SAMPLES_PER_RUN = 50_000
    const val NOTE_SEPARATOR = " · "

    /** Order in which the checks run; the first match wins. */
    val DECISION_ORDER: List<HealthImportSkipReason> = listOf(
        HealthImportSkipReason.INVALID_RECORD,
        HealthImportSkipReason.OWN_APP,
        HealthImportSkipReason.NOT_GYM_TYPE,
        HealthImportSkipReason.DURATION,
        HealthImportSkipReason.IN_PROGRESS,
        HealthImportSkipReason.DUPLICATE_RECEIPT,
        HealthImportSkipReason.OVERLAP
    )

    fun evaluate(
        store: HealthImportStore,
        session: HealthImportSession,
        existingWorkouts: List<HealthExistingWorkout>,
        receipts: Set<String>,
        nowMillis: Long,
        language: AppLanguage
    ): HealthImportDecision {
        screen(store, session, existingWorkouts, receipts, nowMillis)?.let {
            return HealthImportDecision.Skip(it)
        }
        return HealthImportDecision.Import(
            receiptKey = store.receiptKey(session.recordId),
            item = build(store, session, language)
        )
    }

    /** Runs every check that needs only the session header, in [DECISION_ORDER]. */
    fun screen(
        store: HealthImportStore,
        session: HealthImportSession,
        existingWorkouts: List<HealthExistingWorkout>,
        receipts: Set<String>,
        nowMillis: Long
    ): HealthImportSkipReason? {
        screenSource(store, session)?.let { return it }
        val durationSeconds = durationSeconds(session)
            ?: return HealthImportSkipReason.DURATION
        if (durationSeconds !in MIN_DURATION_SECONDS..MAX_DURATION_SECONDS) {
            return HealthImportSkipReason.DURATION
        }
        if (session.endMillis > nowMillis) return HealthImportSkipReason.IN_PROGRESS
        if (store.receiptKey(session.recordId) in receipts) {
            return HealthImportSkipReason.DUPLICATE_RECEIPT
        }
        if (overlapsAny(session, existingWorkouts)) return HealthImportSkipReason.OVERLAP
        return null
    }

    /**
     * Record-id, own-app and gym-type checks: they decide whether a session counts toward the run
     * cap. A record id is invalid when it is empty or when receiptKeyPrefix + recordId is longer
     * than [MAX_RECEIPT_KEY_LENGTH] UTF-16 units or contains an ISO control character.
     */
    fun screenSource(store: HealthImportStore, session: HealthImportSession): HealthImportSkipReason? {
        if (!isValidRecordId(store, session.recordId)) return HealthImportSkipReason.INVALID_RECORD
        if (session.sourceId != null && session.sourceId in store.ownSourceIds) {
            return HealthImportSkipReason.OWN_APP
        }
        if (session.exerciseType == null || session.exerciseType !in store.gymExerciseTypes) {
            return HealthImportSkipReason.NOT_GYM_TYPE
        }
        return null
    }

    fun isValidRecordId(store: HealthImportStore, recordId: String): Boolean =
        recordId.isNotEmpty() &&
            store.receiptKeyPrefix.length + recordId.length <= MAX_RECEIPT_KEY_LENGTH &&
            recordId.none { it.isISOControl() }

    /** Whole seconds between start and end, or null when the interval is invalid. */
    fun durationSeconds(session: HealthImportSession): Long? {
        if (!WorkoutDataLimits.isValidTimestamp(session.startMillis) ||
            !WorkoutDataLimits.isValidTimestamp(session.endMillis) ||
            session.endMillis <= session.startMillis
        ) {
            return null
        }
        return (session.endMillis - session.startMillis) / 1_000L
    }

    fun overlapsAny(session: HealthImportSession, existing: List<HealthExistingWorkout>): Boolean =
        existing.any { overlaps(session.startMillis, session.endMillis, it) }

    fun overlaps(startMillis: Long, endMillis: Long, existing: HealthExistingWorkout): Boolean {
        val existingDurationSeconds = (existing.durationSeconds ?: 0L)
            .coerceIn(0L, WorkoutDataLimits.MAX_WORKOUT_DURATION_SECONDS)
        val existingEnd = existing.startMillis + existingDurationSeconds * 1_000L
        return existing.startMillis - OVERLAP_TOLERANCE_MILLIS <= endMillis &&
            existingEnd + OVERLAP_TOLERANCE_MILLIS >= startMillis
    }

    /** Maps a session that passed [screen] to the activity-only workout that is stored. */
    fun build(
        store: HealthImportStore,
        session: HealthImportSession,
        language: AppLanguage
    ): ActivityOnlyWorkoutItem {
        val durationSeconds = checkNotNull(durationSeconds(session)) {
            "Health import session has an invalid interval."
        }
        val plausible = session.heartRateSamples.filter { sample ->
            sample.timeMillis in session.startMillis..session.endMillis &&
                sample.bpm in MIN_PLAUSIBLE_BPM..MAX_PLAUSIBLE_BPM
        }
        val averageHeartRate = if (plausible.isEmpty()) {
            null
        } else {
            // sum / count rounded half up, in integers so the result is identical on both clients.
            ((plausible.sumOf { it.bpm } * 2L + plausible.size) / (plausible.size * 2L)).toInt()
        }
        val maximumHeartRate = plausible.maxOfOrNull { it.bpm }?.toInt()
        val kilocalories = roundedKilocalories(session.kilocalories)
        return ActivityOnlyWorkoutItem(
            workoutStartedAt = session.startMillis,
            durationSeconds = durationSeconds,
            gymCalories = kilocalories.toDouble(),
            garminCalories = null,
            averageHeartRate = averageHeartRate,
            maximumHeartRate = maximumHeartRate,
            endingHeartRateZone = null,
            note = note(
                store = store,
                exerciseType = checkNotNull(session.exerciseType),
                durationSeconds = durationSeconds,
                kilocalories = kilocalories,
                averageHeartRate = averageHeartRate,
                maximumHeartRate = maximumHeartRate,
                language = language
            )
        )
    }

    private fun roundedKilocalories(value: Double?): Long {
        if (value == null || !value.isFinite() || value < 0.0 || value > MAX_KILOCALORIES) return 0L
        return Math.floor(value + 0.5).toLong()
    }

    fun note(
        store: HealthImportStore,
        exerciseType: String,
        durationSeconds: Long,
        kilocalories: Long,
        averageHeartRate: Int?,
        maximumHeartRate: Int?,
        language: AppLanguage
    ): String {
        val details = mutableListOf(store.notePrefix)
        store.typeLabels[exerciseType]?.let { details += it.forLanguage(language) }
        if (durationSeconds > 0L) {
            val duration = noteDuration(durationSeconds)
            details += when (language) {
                AppLanguage.UK -> "Тривалість $duration"
                AppLanguage.RU -> "Длительность $duration"
                AppLanguage.EN -> "Duration $duration"
            }
        }
        if (kilocalories > 0L) {
            // Number before the unit, like everywhere else in the app ("356 kcal").
            details += when (language) {
                AppLanguage.UK, AppLanguage.RU -> "$kilocalories ккал"
                AppLanguage.EN -> "$kilocalories kcal"
            }
        }
        if (averageHeartRate != null && averageHeartRate > 0) {
            details += when (language) {
                AppLanguage.UK -> "Середній пульс $averageHeartRate"
                AppLanguage.RU -> "Средний пульс $averageHeartRate"
                AppLanguage.EN -> "Avg HR $averageHeartRate"
            }
        }
        if (maximumHeartRate != null && maximumHeartRate > 0) {
            details += when (language) {
                AppLanguage.UK -> "Макс. пульс $maximumHeartRate"
                AppLanguage.RU -> "Макс. пульс $maximumHeartRate"
                AppLanguage.EN -> "Max HR $maximumHeartRate"
            }
        }
        return details.joinToString(NOTE_SEPARATOR)
    }

    /** Note duration: m:ss below one hour, h:mm:ss from one hour on (two-digit minutes and seconds). */
    internal fun noteDuration(durationSeconds: Long): String {
        val hours = durationSeconds / 3_600L
        val minutes = (durationSeconds % 3_600L) / 60L
        val seconds = (durationSeconds % 60L).toString().padStart(2, '0')
        return if (hours > 0L) {
            "$hours:${minutes.toString().padStart(2, '0')}:$seconds"
        } else {
            "$minutes:$seconds"
        }
    }
}
