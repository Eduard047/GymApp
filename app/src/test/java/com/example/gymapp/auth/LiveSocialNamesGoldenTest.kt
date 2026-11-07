package com.example.gymapp.auth

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Runs shared/live-social-names-v1.json through the live and social name validators, like the iOS suite. */
class LiveSocialNamesGoldenTest {
    private class Vector(val id: String, val kinds: Set<String>, val valid: Boolean, val text: String)

    @Test
    fun sharedVectorsGiveTheSameVerdictInLiveAndSocial() {
        val vectors = loadVectors()
        assertTrue(vectors.size >= 40)
        var exerciseChecked = 0
        var displayChecked = 0
        for (vector in vectors) {
            if ("exerciseName" in vector.kinds) {
                exerciseChecked++
                assertVerdict("live exercise name ${vector.id}", vector.valid) {
                    parseLiveWorkoutInbox(liveInbox(exerciseName = vector.text))
                }
                assertVerdict("social exercise name ${vector.id}", vector.valid) {
                    parseSocialWorkoutInvitePlan(socialInvitePlan(vector.text))
                }
            }
            if ("displayName" in vector.kinds) {
                displayChecked++
                assertVerdict("live display name ${vector.id}", vector.valid) {
                    parseLiveWorkoutInbox(liveInbox(displayName = vector.text))
                }
                assertVerdict("social display name ${vector.id}", vector.valid) {
                    parseSocialDashboard(socialDashboard(vector.text))
                }
            }
        }
        assertTrue(exerciseChecked >= 30 && displayChecked >= 25)
    }

    private fun assertVerdict(label: String, valid: Boolean, parse: () -> Unit) {
        val accepted = try {
            parse()
            true
        } catch (_: IllegalArgumentException) {
            false
        }
        assertEquals(label, valid, accepted)
    }

    private fun liveInbox(exerciseName: String = "Bench press", displayName: String = "Owner"): String =
        JSONObject()
            .put("version", 1)
            .put(
                "invitations",
                JSONArray().put(
                    JSONObject()
                        .put("roomId", "lr_0123456789abcdef0123456789abcdef")
                        .put("status", "waiting")
                        .put("roomRevision", 1)
                        .put("createdAt", "2026-08-10T09:00:00Z")
                        .put("inviteExpiresAt", "2026-08-10T11:00:00Z")
                        .put(
                            "summary",
                            JSONObject()
                                .put("exerciseCount", 1)
                                .put("setCount", 1)
                                .put("exerciseNames", JSONArray().put(exerciseName))
                        )
                        .put(
                            "owner",
                            JSONObject()
                                .put("profileId", "p_${"1".repeat(32)}")
                                .put("displayName", displayName)
                        )
                )
            )
            .put("rooms", JSONArray())
            .toString()

    private fun socialInvitePlan(exerciseName: String): String = JSONObject()
        .put("version", 1)
        .put("inviteId", "wi_${"1".repeat(32)}")
        .put("inviteRevision", 1)
        .put(
            "workout",
            JSONObject()
                .put("version", 1)
                .put(
                    "exercises",
                    JSONArray().put(
                        JSONObject()
                            .put("name", exerciseName)
                            .put(
                                "sets",
                                JSONArray().put(JSONObject().put("weight", 60.0).put("reps", 5))
                            )
                    )
                )
        )
        .toString()

    private fun socialDashboard(displayName: String): String = JSONObject()
        .put("version", 1)
        .put(
            "self",
            JSONObject()
                .put("profileId", "p_${"0".repeat(32)}")
                .put("friendCode", "p_${"0".repeat(32)}")
                .put("displayName", displayName)
                .put("xp", 800)
                .put("level", 4)
                .put("workouts", 12)
                .put("statsAvailable", true)
                .put("progressUpdatedAt", "2026-08-09T10:00:00Z")
                .put(
                    "privacy",
                    JSONObject()
                        .put("allowRequests", true)
                        .put("shareProgress", true)
                        .put("shareRecentWorkouts", true)
                        .put("shareRecords", true)
                )
                .put("settingsRevision", 3)
        )
        .put("friends", JSONArray())
        .put("incoming", JSONArray())
        .put("outgoing", JSONArray())
        .put("blocked", JSONArray())
        .put("pendingWorkoutInviteCount", 0)
        .toString()

    private fun loadVectors(): List<Vector> {
        val direct = File("shared/live-social-names-v1.json")
        val file = if (direct.isFile) direct else File("../shared/live-social-names-v1.json")
        val array = JSONObject(file.readText()).getJSONArray("vectors")
        return List(array.length()) { index ->
            val item = array.getJSONObject(index)
            val repeat = item.optJSONObject("repeat")
            val text = if (repeat != null) {
                repeat.optString("prefix", "") +
                    repeat.getString("unit").repeat(repeat.getInt("count")) +
                    repeat.optString("suffix", "")
            } else {
                item.getString("text")
            }
            val kinds = item.getJSONArray("kinds")
            Vector(
                id = item.getString("id"),
                kinds = List(kinds.length()) { kinds.getString(it) }.toSet(),
                valid = item.getBoolean("valid"),
                text = text
            )
        }
    }
}
