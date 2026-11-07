package com.example.gymapp.garmin

import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/garmin-sync-v1.json through the real Android builders; iOS runs the same cases. */
class GarminSyncGoldenTest {
    @Test
    fun sharedGoldenCasesMatchTheAndroidSyncBuilders() {
        val root = contract()
        val bindingJson = root.getJSONObject("binding")
        val binding = GarminBinding(
            account = bindingJson.getString("account"),
            device = bindingJson.getString("device"),
            pairingGeneration = bindingJson.getString("pairingGeneration")
        )
        val syncId = root.getString("syncId")
        val cases = root.getJSONArray("cases")
        assertTrue(cases.length() >= 5)

        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val input = case.getJSONObject("input")
            val revision = input.getLong("syncRevision")
            val language = input.getString("language")
            val plan = input.getJSONArray("plan").objects().map {
                NamedWorkoutSetDraft(it.getString("exerciseName"), it.getDouble("weight"), it.getInt("reps"))
            }

            val actual: Map<String, Any> = if (input.getBoolean("bindingOnly")) {
                checkNotNull(
                    boundGarminSyncPayload(
                        garminBindingOnlySyncPayload(
                            language = language,
                            syncId = syncId,
                            resetWorkout = input.getBoolean("resetWorkout"),
                            repairPairing = input.getBoolean("repairPairing")
                        ),
                        binding,
                        revision
                    )
                ) { "$id bound payload" }
            } else {
                // The ordinary plan sync: Android builds it through the plan-submission path.
                check(!input.getBoolean("resetWorkout") && !input.getBoolean("repairPairing")) { "$id" }
                val key = GarminPlanSubmissionKey(
                    accountBinding = binding.account,
                    authTransitionKey = "c".repeat(64),
                    deviceBinding = binding.device,
                    pairingGeneration = binding.pairingGeneration,
                    includePairingGeneration = true,
                    languageTag = language,
                    orderedPlan = plan,
                    exerciseCatalog = input.getJSONArray("exerciseCandidates").strings()
                )
                val prepared = checkNotNull(
                    prepareGarminPlanSubmission(
                        key = key,
                        encodedExisting = null,
                        lastGlobalRevision = null,
                        nowMillis = revision,
                        newRequestId = { syncId }
                    )
                ) { "$id prepared" }
                checkNotNull(materializeGarminPlanSubmissionPayload(key, prepared.envelope)) { "$id payload" }
            }

            val expected = normalize(case.getJSONObject("expected")).toMutableMap()
            expected.putAll(normalize(case.getJSONObject("platformExtras").getJSONObject("android")))
            assertEquals("$id", expected, normalize(actual))
            assertTrue("$id syncRevision stays a Long", actual["syncRevision"] is Long)
            assertTrue("$id fits the watch key cap", actual.size <= root.getInt("watchMaximumKeys"))
        }
    }

    // Numbers compare as doubles (JSON has one number type); everything else compares as is.
    private fun normalize(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { normalize(value.get(it)) }
        is JSONArray -> List(value.length()) { normalize(value.get(it)) }
        is Map<*, *> -> value.entries.associate { (k, v) -> k as String to normalize(v) }
        is List<*> -> value.map(::normalize)
        is Number -> value.toDouble()
        else -> value
    }

    @Suppress("UNCHECKED_CAST")
    private fun normalize(map: Map<String, Any>): Map<String, Any?> = normalize(map as Any?) as Map<String, Any?>

    private fun normalize(json: JSONObject): Map<String, Any?> =
        json.keys().asSequence().associateWith { normalize(json.get(it)) }

    private fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }

    private fun JSONArray.strings(): List<String> = List(length()) { getString(it) }

    private fun contract(): JSONObject {
        val direct = File("shared/garmin-sync-v1.json")
        val file = if (direct.isFile) direct else File("../shared/garmin-sync-v1.json")
        check(file.isFile) { "Garmin sync contract was not found." }
        return JSONObject(file.readText(Charsets.UTF_8))
    }
}
