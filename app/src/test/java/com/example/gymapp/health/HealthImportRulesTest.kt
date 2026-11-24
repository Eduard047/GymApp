package com.example.gymapp.health

import com.example.gymapp.util.AppLanguage
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

/** Runs shared/health-import-v1.json, the contract the iPhone HealthKit import also follows. */
class HealthImportRulesTest {
    private val contract = loadContract()

    @Test
    fun kotlinConstantsMatchTheContract() {
        assertEquals(1, contract.getInt("schemaVersion"))
        assertEquals(contract.getInt("schemaVersion"), HealthImportRules.SCHEMA_VERSION)
        assertEquals(contract.getInt("windowDays"), HealthImportRules.WINDOW_DAYS)
        assertEquals(contract.getInt("maxSessionsPerRun"), HealthImportRules.MAX_SESSIONS_PER_RUN)
        assertEquals(
            contract.getInt("maxRecordsScannedPerRun"),
            HealthImportRules.MAX_RECORDS_SCANNED_PER_RUN
        )
        assertEquals(contract.getLong("minDurationSeconds"), HealthImportRules.MIN_DURATION_SECONDS)
        assertEquals(contract.getLong("maxDurationSeconds"), HealthImportRules.MAX_DURATION_SECONDS)
        assertEquals(
            contract.getLong("overlapToleranceSeconds"),
            HealthImportRules.OVERLAP_TOLERANCE_SECONDS
        )
        assertEquals(
            contract.getLong("minAutoImportIntervalSeconds"),
            HealthImportRules.MIN_AUTO_IMPORT_INTERVAL_SECONDS
        )
        val heartRate = contract.getJSONObject("heartRate")
        assertEquals(heartRate.getLong("minPlausibleBpm"), HealthImportRules.MIN_PLAUSIBLE_BPM)
        assertEquals(heartRate.getLong("maxPlausibleBpm"), HealthImportRules.MAX_PLAUSIBLE_BPM)
        assertEquals(
            contract.getJSONObject("calories").getDouble("maxKilocalories"),
            HealthImportRules.MAX_KILOCALORIES,
            0.0
        )
        assertEquals(contract.getInt("maxReceiptKeyLength"), HealthImportRules.MAX_RECEIPT_KEY_LENGTH)
        assertEquals(
            contract.getInt("maxHeartRateSamplesPerRun"),
            HealthImportRules.MAX_HEART_RATE_SAMPLES_PER_RUN
        )
        assertEquals(contract.getString("noteSeparator"), HealthImportRules.NOTE_SEPARATOR)
        assertEquals(
            strings(contract.getJSONArray("decisionOrder")),
            HealthImportRules.DECISION_ORDER.map { it.wire }
        )
    }

    @Test
    fun storeConfigurationMatchesTheContract() {
        val stores = contract.getJSONObject("stores")
        for (store in HealthImportStore.entries) {
            val spec = stores.getJSONObject(store.wire)
            assertEquals(spec.getString("receiptKeyPrefix"), store.receiptKeyPrefix)
            assertEquals(spec.getString("notePrefix"), store.notePrefix)
            assertEquals(strings(spec.getJSONArray("ownSourceIds")).toSet(), store.ownSourceIds)
            assertEquals(
                strings(spec.getJSONArray("gymExerciseTypes")),
                store.gymExerciseTypes.toList()
            )
            val labels = spec.getJSONObject("typeLabels")
            assertEquals(store.gymExerciseTypes, labels.keys().asSequence().toSet())
            for ((type, label) in store.typeLabels) {
                val expected = labels.getJSONObject(type)
                assertEquals(expected.getString("en"), label.en)
                assertEquals(expected.getString("uk"), label.uk)
                assertEquals(expected.getString("ru"), label.ru)
            }
        }
    }

    @Test
    fun noteSegmentsMatchTheContractTemplates() {
        val segments = contract.getJSONObject("noteSegments")
        for (language in AppLanguage.entries) {
            val tag = language.tag
            val note = HealthImportRules.note(
                store = HealthImportStore.HEALTH_CONNECT,
                exerciseType = "STRENGTH_TRAINING",
                durationSeconds = 3_725L,
                kilocalories = 321L,
                averageHeartRate = 111,
                maximumHeartRate = 177,
                language = language
            ).split(HealthImportRules.NOTE_SEPARATOR)
            assertEquals(
                segments.getJSONObject("duration").getString(tag)
                    .replace("{duration}", "1:02:05"),
                note[2]
            )
            assertEquals(segments.getJSONObject("calories").getString(tag).replace("{value}", "321"), note[3])
            assertEquals(
                segments.getJSONObject("averageHeartRate").getString(tag).replace("{value}", "111"),
                note[4]
            )
            assertEquals(
                segments.getJSONObject("maximumHeartRate").getString(tag).replace("{value}", "177"),
                note[5]
            )
        }
    }

    @Test
    fun goldenCasesProduceTheExpectedDecisions() {
        val cases = contract.getJSONArray("cases")
        assertTrue("Contract must keep its golden cases", cases.length() >= 50)
        val mismatches = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val store = checkNotNull(HealthImportStore.fromWire(case.getString("store"))) {
                "$id: unknown store"
            }
            val language = checkNotNull(AppLanguage.fromTag(case.getString("language"))) {
                "$id: unknown language"
            }
            val decision = HealthImportRules.evaluate(
                store = store,
                session = session(case.getJSONObject("session")),
                existingWorkouts = existing(case.getJSONArray("existingWorkouts")),
                receipts = strings(case.getJSONArray("receipts")).toSet(),
                nowMillis = case.getLong("nowMillis"),
                language = language
            )
            val expected = case.getJSONObject("expected")
            val outcome = expected.getString("outcome")
            when (decision) {
                is HealthImportDecision.Skip -> {
                    if (outcome != "skipped:${decision.reason.wire}") {
                        mismatches += "$id: expected $outcome but skipped:${decision.reason.wire}"
                    }
                }
                is HealthImportDecision.Import -> {
                    if (outcome != "imported") {
                        mismatches += "$id: expected $outcome but imported"
                        continue
                    }
                    val workout = expected.getJSONObject("workout")
                    val item = decision.item
                    if (expected.getString("receiptKey") != decision.receiptKey) {
                        mismatches += "$id: receiptKey ${decision.receiptKey}"
                    }
                    if (workout.getLong("workoutStartedAt") != item.workoutStartedAt) {
                        mismatches += "$id: workoutStartedAt ${item.workoutStartedAt}"
                    }
                    if (workout.getLong("durationSeconds") != item.durationSeconds) {
                        mismatches += "$id: durationSeconds ${item.durationSeconds}"
                    }
                    if (workout.getDouble("gymCalories") != item.gymCalories) {
                        mismatches += "$id: gymCalories ${item.gymCalories}"
                    }
                    if (optionalInt(workout, "averageHeartRate") != item.averageHeartRate) {
                        mismatches += "$id: averageHeartRate ${item.averageHeartRate}"
                    }
                    if (optionalInt(workout, "maximumHeartRate") != item.maximumHeartRate) {
                        mismatches += "$id: maximumHeartRate ${item.maximumHeartRate}"
                    }
                    if (workout.getString("note") != item.note) {
                        mismatches += "$id: note '${item.note}'"
                    }
                    if (item.garminCalories != null || item.endingHeartRateZone != null) {
                        mismatches += "$id: Garmin-only fields must stay unset"
                    }
                }
            }
        }
        assertEquals("Health import golden mismatches", emptyList<String>(), mismatches)
    }

    @Test
    fun everyImportedItemIsAValidActivityOnlyWorkout() {
        val cases = contract.getJSONArray("cases")
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            if (case.getJSONObject("expected").getString("outcome") != "imported") continue
            val store = checkNotNull(HealthImportStore.fromWire(case.getString("store")))
            val decision = HealthImportRules.evaluate(
                store,
                session(case.getJSONObject("session")),
                emptyList(),
                emptySet(),
                case.getLong("nowMillis"),
                AppLanguage.fromTag(case.getString("language"))!!
            ) as HealthImportDecision.Import
            // ActivityOnlyWorkoutEntity.fromItem runs the same validator the sidecar sync uses.
            assertNotNull(com.example.gymapp.data.entity.ActivityOnlyWorkoutEntity.fromItem(decision.item))
        }
    }

    @Test
    fun noteWritesTheNumberBeforeTheUnitAndHoursFromOneHourOn() {
        fun note(seconds: Long, language: AppLanguage) = HealthImportRules.note(
            store = HealthImportStore.HEALTH_KIT,
            exerciseType = "coreTraining",
            durationSeconds = seconds,
            kilocalories = 356L,
            averageHeartRate = 124,
            maximumHeartRate = 158,
            language = language
        )
        assertEquals(
            "Apple Health · Core training · Duration 47:05 · 356 kcal · Avg HR 124 · Max HR 158",
            note(2_825L, AppLanguage.EN)
        )
        assertEquals(
            "Apple Health · Тренування м’язів кора · Тривалість 1:35:00 · 356 ккал · " +
                "Середній пульс 124 · Макс. пульс 158",
            note(5_700L, AppLanguage.UK)
        )
        assertEquals(
            "Apple Health · Тренировка мышц кора · Длительность 2:05:30 · 356 ккал · " +
                "Средний пульс 124 · Макс. пульс 158",
            note(7_530L, AppLanguage.RU)
        )
        assertEquals("59:59", HealthImportRules.noteDuration(3_599L))
        assertEquals("1:00:00", HealthImportRules.noteDuration(3_600L))
        assertEquals("24:00:00", HealthImportRules.noteDuration(86_400L))
    }

    private fun session(json: JSONObject): HealthImportSession {
        val samples = json.getJSONArray("heartRateSamples")
        return HealthImportSession(
            recordId = json.getString("recordId"),
            startMillis = json.getLong("startMillis"),
            endMillis = json.getLong("endMillis"),
            exerciseType = if (json.isNull("exerciseType")) null else json.getString("exerciseType"),
            sourceId = if (json.isNull("sourceId")) null else json.getString("sourceId"),
            kilocalories = if (json.isNull("kilocalories")) null else json.getDouble("kilocalories"),
            heartRateSamples = List(samples.length()) { i ->
                samples.getJSONObject(i).let { HeartRateSample(it.getLong("timeMillis"), it.getLong("bpm")) }
            }
        )
    }

    private fun existing(rows: JSONArray): List<HealthExistingWorkout> = List(rows.length()) { i ->
        rows.getJSONObject(i).let {
            HealthExistingWorkout(
                it.getLong("startMillis"),
                if (it.isNull("durationSeconds")) null else it.getLong("durationSeconds")
            )
        }
    }

    private fun optionalInt(json: JSONObject, key: String): Int? =
        if (json.isNull(key)) null else json.getInt(key)

    private fun strings(array: JSONArray): List<String> = List(array.length()) { array.getString(it) }

    private fun loadContract(): JSONObject {
        val direct = File("shared/health-import-v1.json")
        val file = if (direct.isFile) direct else File("../shared/health-import-v1.json")
        check(file.isFile) { "Health import contract was not found." }
        return JSONObject(file.readText())
    }

    @Test
    fun watchWorkoutReplacesOnlyUneditedOverlappingHealthImports() {
        val start = 1_750_000_000_000L
        fun replaceable(
            note: String? = "Health Connect · Strength training · Duration 30:00",
            hasExercises: Boolean = false,
            hasReceipt: Boolean = true,
            duration: Long? = 1_800L,
            sidecar: Long? = 1_800L,
            watchStart: Long = start + 60_000L
        ) = HealthImportRules.isReplaceableByWatchWorkout(
            store = HealthImportStore.HEALTH_CONNECT,
            workoutStartMillis = start,
            workoutDurationSeconds = duration,
            workoutNote = note,
            hasExercises = hasExercises,
            hasReceipt = hasReceipt,
            sidecarDurationSeconds = sidecar,
            watchStartMillis = watchStart,
            watchEndMillis = watchStart + 1_800_000L
        )
        assertTrue(replaceable())
        assertTrue(replaceable(sidecar = null))
        // Edge of the 120 s tolerance after the imported end (start + 1800 s).
        assertTrue(replaceable(watchStart = start + 1_800_000L + 120_000L))
        assertFalse(replaceable(watchStart = start + 1_800_000L + 121_000L))
        assertFalse(replaceable(note = "My own note"))
        assertFalse(replaceable(note = null))
        assertFalse(replaceable(hasExercises = true))
        assertFalse(replaceable(hasReceipt = false))
        assertFalse(replaceable(duration = null))
        assertFalse(replaceable(duration = 0L))
        assertFalse(replaceable(sidecar = 1_200L))
    }
}
