package com.example.gymapp.sync

import com.example.gymapp.data.repository.canonicalWorkoutPayloadDigest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudStateContractTest {
    private val userId = "123e4567-e89b-12d3-a456-426614174000"

    @Test
    fun `canonical v2 accepts bounded extensions and keeps workout identity core-only`() {
        val core = canonicalState()
        val extensions = JSONObject()
            .put(
                "pwa",
                JSONObject()
                    .put("version", 1)
                    .put("language", "uk")
                    .put("mappings", JSONObject().put("Bench Press", JSONArray().put("chest")))
                    .put(
                        "profile",
                        JSONObject()
                            .put("split", "Full Body")
                            .put("days", 4)
                            .put("goal", "Balanced")
                            .put("calories", "Maintenance")
                    )
            )
            .put(
                "future.client",
                JSONObject()
                    .put("version", 7)
                    .put("nested", JSONObject().put("enabled", true))
            )
        val extended = JSONObject(core.toString()).put("extensions", extensions)
        val prepared = prepareSharedCloudState(extended, userId)

        assertEquals(SharedCloudStateSource.CanonicalV2, prepared.source)
        assertEquals(canonicalWorkoutPayloadDigest(core), prepared.workoutDigest)
        assertEquals(extensions.toString(), prepared.extensions?.toString())
        assertTrue(isCanonicalSharedCloudEnvelope(extended, userId))
    }

    @Test
    fun `released PWA v2 row migrates to pwa extension without changing workout digest`() {
        val legacy = legacyPwaState()
        val prepared = prepareSharedCloudState(legacy, userId)

        assertEquals(SharedCloudStateSource.LegacyPwaV2, prepared.source)
        assertEquals(canonicalWorkoutPayloadDigest(canonicalState()), prepared.workoutDigest)
        val pwa = prepared.extensions?.optJSONObject("pwa")
        assertNotNull(pwa)
        assertEquals(1, pwa?.optInt("version"))
        assertEquals("uk", pwa?.optString("language"))
        assertEquals("Full Body", pwa?.optJSONObject("profile")?.optString("split"))
        assertEquals("chest", pwa?.optJSONObject("mappings")
            ?.optJSONArray("Bench Press")?.optString(0))
    }

    @Test
    fun `representative PWA canonical row remains readable while Android rewrite omits extensions`() {
        val pwaWritten = representativePwaCanonicalState()
        val firstRead = prepareSharedCloudState(pwaWritten, userId)
        val androidCoreRewrite = JSONObject(pwaWritten.toString()).apply {
            remove("extensions")
            put("exportedAt", 1750000002000)
        }
        val androidWritten = attachSharedCloudExtensions(
            canonicalCore = androidCoreRewrite,
            extensions = firstRead.extensions
        )
        val secondRead = prepareSharedCloudState(androidWritten, userId)

        assertEquals(SharedCloudStateSource.CanonicalV2, firstRead.source)
        assertEquals(firstRead.workoutDigest, secondRead.workoutDigest)
        assertNotNull(firstRead.extensions?.optJSONObject("pwa"))
        assertNotNull(firstRead.extensions?.optJSONObject("ios"))
        assertFalse(androidWritten.has("extensions"))
        assertNull(secondRead.extensions)
    }

    @Test
    fun `Android cloud write matches the exact v229 canonical golden shape`() {
        val input = canonicalState().apply {
            put("catalogSeedVersion", 3)
            getJSONArray("exercises").getJSONObject(0).apply {
                put("favorite", true)
                put(
                    "loadProfile",
                    JSONObject()
                        .put("direction", "higherIsHarder")
                        .put("allowedWeightsKg", JSONArray(listOf(60.0, 80.0, 100.0)))
                )
            }
            getJSONArray("sessions").getJSONObject(0)
                .getJSONArray("exercises").getJSONObject(0)
                .put(
                    "loadProfile",
                    JSONObject()
                        .put("direction", "higherIsHarder")
                        .put("allowedWeightsKg", JSONArray(listOf(60.0, 80.0, 100.0)))
                )
        }
        val retainedReadExtensions = JSONObject().put(
            "future.client",
            JSONObject().put("version", 1).put("enabled", true)
        )

        val written = attachSharedCloudExtensions(input, retainedReadExtensions)
        val golden = canonicalState()

        assertEquals(golden.toString(), written.toString())
        assertEquals(
            setOf(
                "schemaVersion",
                "exportedAt",
                "app",
                "diagnostics",
                "owner",
                "exercises",
                "sessions",
                "summary"
            ),
            written.jsonKeys()
        )
        assertEquals(
            setOf("name", "catalogKey"),
            written.getJSONArray("exercises").getJSONObject(0).jsonKeys()
        )
        assertEquals(
            setOf("name", "catalogKey", "sets"),
            written.getJSONArray("sessions").getJSONObject(0)
                .getJSONArray("exercises").getJSONObject(0).jsonKeys()
        )
        assertTrue(isCanonicalSharedCloudEnvelope(written, userId))
    }

    @Test
    fun `foreign and unbound legacy PWA rows fail before becoming authoritative`() {
        val foreign = legacyPwaState().apply {
            getJSONObject("owner")
                .put("userId", "00000000-0000-4000-8000-000000000002")
        }
        val unbound = legacyPwaState().apply {
            getJSONObject("owner").remove("userId")
        }

        assertThrows(IllegalArgumentException::class.java) {
            prepareSharedCloudState(foreign, userId)
        }
        assertThrows(IllegalArgumentException::class.java) {
            prepareSharedCloudState(unbound, userId)
        }
    }

    @Test
    fun `exact ownerless legacy PWA row is bound by the authenticated row and migrated`() {
        val ownerless = legacyPwaState().apply {
            listOf("schemaVersion", "exportedAt", "app", "diagnostics", "owner").forEach(::remove)
            getJSONArray("exercises").getJSONObject(0).remove("catalogKey")
            getJSONArray("sessions").getJSONObject(0)
                .getJSONArray("sets").getJSONObject(0).remove("catalogKey")
        }

        val prepared = prepareSharedCloudState(ownerless, userId)

        assertEquals(SharedCloudStateSource.LegacyPwaV2, prepared.source)
        assertNotNull(prepared.extensions?.optJSONObject("pwa"))
        assertEquals(canonicalWorkoutPayloadDigest(canonicalState()), prepared.workoutDigest)
    }

    @Test
    fun `pwa mapping extension supports the shared exercise ceiling`() {
        val mappings = JSONObject()
        repeat(65) { index ->
            mappings.put("Custom exercise $index", JSONArray().put("muscle-$index"))
        }
        val extensions = JSONObject().put(
            "pwa",
            JSONObject()
                .put("version", 1)
                .put("language", "en")
                .put("mappings", mappings)
                .put(
                    "profile",
                    JSONObject()
                        .put("split", "Upper / Lower")
                        .put("days", 4)
                        .put("goal", "Balanced")
                        .put("calories", "Maintenance")
                )
        )

        assertTrue(
            isCanonicalSharedCloudEnvelope(
                canonicalState().put("extensions", extensions),
                userId
            )
        )
    }

    @Test
    fun `pwa muscle identifiers use the shared unicode character and byte limits`() {
        fun stateWithMuscle(muscle: String): JSONObject {
            val extensions = JSONObject().put(
                "pwa",
                JSONObject()
                    .put("version", 1)
                    .put("language", "en")
                    .put("mappings", JSONObject().put("Custom carry", JSONArray().put(muscle)))
                    .put(
                        "profile",
                        JSONObject()
                            .put("split", "Full Body")
                            .put("days", 4)
                            .put("goal", "Balanced")
                            .put("calories", "Maintenance")
                    )
            )
            return canonicalState().put("extensions", extensions)
        }

        assertTrue(isCanonicalSharedCloudEnvelope(stateWithMuscle("💪".repeat(32)), userId))
        assertThrows(IllegalArgumentException::class.java) {
            prepareSharedCloudState(stateWithMuscle("a".repeat(65)), userId)
        }
        assertThrows(IllegalArgumentException::class.java) {
            prepareSharedCloudState(stateWithMuscle("💪".repeat(33)), userId)
        }
    }

    @Test
    fun `malformed summary unknown root and invalid extension fail closed`() {
        val wrongSummary = canonicalState().apply {
            getJSONObject("summary").put("totalVolume", 1.0)
        }
        val unknownRoot = canonicalState().apply { put("language", "uk") }
        val invalidExtension = canonicalState().apply {
            put("extensions", JSONObject().put("pwa", "not-an-object"))
        }

        listOf(wrongSummary, unknownRoot, invalidExtension).forEach { invalid ->
            assertThrows(IllegalArgumentException::class.java) {
                prepareSharedCloudState(invalid, userId)
            }
        }
    }

    @Test
    fun `canonical cloud history rejects descending dates`() {
        val descending = canonicalState().apply {
            val sessions = getJSONArray("sessions")
            val template = sessions.getJSONObject(0)
            sessions.put(0, JSONObject(template.toString()).put("date", 1750000001000))
            sessions.put(1, JSONObject(template.toString()).put("date", 1750000000000))
            getJSONObject("summary")
                .put("sessionCount", 2)
                .put("setCount", 2)
                .put("totalVolume", 1280.0)
        }

        assertThrows(IllegalArgumentException::class.java) {
            prepareSharedCloudState(descending, userId)
        }
    }

    @Test
    fun `more than 32 extension namespaces fail closed`() {
        val extensions = JSONObject()
        repeat(33) { index ->
            extensions.put("client.$index", JSONObject().put("version", 1))
        }

        assertThrows(IllegalArgumentException::class.java) {
            attachSharedCloudExtensions(canonicalState(), extensions)
        }

        val untrustedCloudState = canonicalState().apply {
            put("extensions", extensions)
        }
        assertThrows(IllegalArgumentException::class.java) {
            prepareSharedCloudState(untrustedCloudState, userId)
        }
    }

    @Test
    fun `canonical reads preserve unknown namespaces but compatible writes omit them`() {
        val core = canonicalState()
        assertFalse(attachSharedCloudExtensions(core, JSONObject()).has("extensions"))

        val unknown = JSONObject()
            .put("watch.vendor", JSONObject().put("values", JSONArray(listOf(1, 2, 3))))
        val first = JSONObject(core.toString()).put("extensions", unknown)
        val retained = prepareSharedCloudState(first, userId).extensions
        val second = attachSharedCloudExtensions(canonicalState(), retained)

        assertEquals(
            unknown.toString(),
            retained?.toString()
        )
        assertFalse(second.has("extensions"))
        assertNull(canonicalState().optJSONObject("extensions"))
    }

    private fun canonicalState(): JSONObject = JSONObject(
        """
        {
          "schemaVersion": 2,
          "exportedAt": 1750000000000,
          "app": "GymApp",
          "diagnostics": false,
          "owner": {
            "accountId": "$userId",
            "userId": "$userId",
            "remote": true
          },
          "exercises": [{"name": "Bench Press", "catalogKey": "bench_press"}],
          "sessions": [{
            "date": 1750000000000,
            "note": "Workout",
            "exercises": [{
              "name": "Bench Press",
              "catalogKey": "bench_press",
              "sets": [{"weight": 80.0, "reps": 8}]
            }]
          }],
          "summary": {
            "exerciseCount": 1,
            "sessionCount": 1,
            "setCount": 1,
            "totalVolume": 640.0
          }
        }
        """.trimIndent()
    )

    private fun legacyPwaState(): JSONObject = JSONObject(
        """
        {
          "schemaVersion": 2,
          "exportedAt": 1750000000000,
          "app": "GymApp",
          "diagnostics": false,
          "owner": {
            "accountId": "remote-$userId",
            "userId": "$userId",
            "remote": "supabase"
          },
          "language": "uk",
          "exercises": [{"id": 1, "name": "Bench Press", "catalogKey": "bench_press"}],
          "sessions": [{
            "id": 2,
            "startedAt": 1750000000000,
            "note": "Workout",
            "exerciseNames": ["Bench Press"],
            "sets": [{
              "id": 3,
              "exerciseName": "Bench Press",
              "catalogKey": "bench_press",
              "weight": 80.0,
              "reps": 8,
              "orderIndex": 0
            }]
          }],
          "mappings": {"Bench Press": ["chest"]},
          "profile": {
            "split": "Full Body",
            "days": 4,
            "goal": "Balanced",
            "calories": "Maintenance"
          }
        }
        """.trimIndent()
    )

    private fun representativePwaCanonicalState(): JSONObject = canonicalState().apply {
        val sessions = getJSONArray("sessions")
        val first = sessions.getJSONObject(0)
        sessions.put(1, JSONObject(first.toString()).put("date", 1750000001000))
        getJSONObject("summary")
            .put("sessionCount", 2)
            .put("setCount", 2)
            .put("totalVolume", 1280.0)
        put(
            "extensions",
            JSONObject()
                .put(
                    "pwa",
                    JSONObject()
                        .put("version", 1)
                        .put("language", "en")
                        .put(
                            "mappings",
                            JSONObject().put("Bench Press", JSONArray().put("chest"))
                        )
                        .put(
                            "profile",
                            JSONObject()
                                .put("split", "Upper / Lower")
                                .put("days", 4)
                                .put("goal", "Strength")
                                .put("calories", "Maintenance")
                        )
                )
                .put(
                    "ios",
                    JSONObject()
                        .put("version", 1)
                        .put("preferences", JSONObject().put("chart", "heartRate"))
                )
        )
    }

    private fun JSONObject.jsonKeys(): Set<String> = buildSet {
        val iterator = keys()
        while (iterator.hasNext()) add(iterator.next())
    }
}
