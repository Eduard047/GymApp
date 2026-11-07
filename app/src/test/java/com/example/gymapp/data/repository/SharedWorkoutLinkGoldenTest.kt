package com.example.gymapp.data.repository

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.Base64

/** Runs shared/shared-workout-link-v1.json, the same cases the iOS suite runs. */
class SharedWorkoutLinkGoldenTest {
    private val customScheme = "com.setforge.gymapp"

    @Test
    fun sharedGoldenCasesDecodeAndRejectLikeIos() {
        val cases = contract().getJSONArray("cases")
        assertTrue(cases.length() >= 10)
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val id = case.getString("id")
            val link = case.getString("link")
            val result = SharedWorkoutLink.parseIncomingUrl(link, customScheme)
            if (!case.getBoolean("valid")) {
                assertEquals("$id must be rejected", IncomingSharedWorkoutUrl.InvalidSharedWorkout, result)
                continue
            }
            val expected = expectedExercises(case.getJSONObject("expected"))
            assertEquals(
                "$id must decode to the expected plan",
                IncomingSharedWorkoutUrl.Valid(SharedWorkoutPlan(expected)),
                result
            )
        }
    }

    @Test
    fun sharedGoldenValidCasesReEncodeToTheSamePayload() {
        val cases = contract().getJSONArray("cases")
        var checked = 0
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            if (!case.getBoolean("valid") || !case.getBoolean("encodeRoundTrip")) continue
            val expected = expectedExercises(case.getJSONObject("expected"))
            val id = case.getString("id")
            val encoded = SharedWorkoutLink.buildUrl(expected)
            // Key order is not compared: the PWA writes v,e while this encoder writes e,v.
            val actual = payloadJson(encoded)
            val golden = payloadJson(case.getString("link"))
            assertEquals("$id version", golden.getInt("v"), actual.getInt("v"))
            assertEquals("$id exercises", golden.getJSONArray("e").toString(), actual.getJSONArray("e").toString())
            assertEquals(
                "$id must round-trip",
                IncomingSharedWorkoutUrl.Valid(SharedWorkoutPlan(expected)),
                SharedWorkoutLink.parseIncomingUrl(encoded, customScheme)
            )
            checked += 1
        }
        assertTrue(checked >= 5)
    }

    private fun payloadJson(url: String): JSONObject =
        JSONObject(
            Base64.getUrlDecoder().decode(url.substringAfter("#workout=")).toString(Charsets.UTF_8)
        )

    private fun expectedExercises(expected: JSONObject): List<SharedWorkoutExercise> {
        val exercises = expected.getJSONArray("exercises")
        return List(exercises.length()) { exerciseIndex ->
            val exercise = exercises.getJSONObject(exerciseIndex)
            val sets: JSONArray = exercise.getJSONArray("sets")
            SharedWorkoutExercise(
                catalogKey = if (exercise.isNull("catalogKey")) null else exercise.getString("catalogKey"),
                name = exercise.getString("name"),
                sets = List(sets.length()) { setIndex ->
                    val pair = sets.getJSONArray(setIndex)
                    SharedWorkoutSet(weight = pair.getDouble(0), reps = pair.getInt(1))
                }
            )
        }
    }

    private fun contract(): JSONObject {
        val direct = File("shared/shared-workout-link-v1.json")
        val file = if (direct.isFile) direct else File("../shared/shared-workout-link-v1.json")
        check(file.isFile) { "Shared workout link contract was not found." }
        return JSONObject(file.readText(Charsets.UTF_8))
    }
}
