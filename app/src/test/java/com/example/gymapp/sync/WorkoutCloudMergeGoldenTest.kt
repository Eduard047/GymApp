package com.example.gymapp.sync

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Runs the shared per-workout merge scenarios against the Android merge engine. */
class WorkoutCloudMergeGoldenTest {
    private val contract = JSONObject(sharedFixture().readText())
    private val sessions = contract.getJSONObject("sessions")
    private val exercises = contract.getJSONObject("exercises")
    private val times = contract.getJSONObject("times")

    @Test
    fun everySharedMergeScenarioMatches() {
        val scenarios = contract.getJSONArray("mergeScenarios")
        assertTrue(scenarios.length() >= 20)
        repeat(scenarios.length()) { index ->
            val scenario = scenarios.getJSONObject(index)
            val name = scenario.getString("name")
            val result = merge(scenario)
            val expected = core(scenario.getJSONObject("result"))
            assertEquals(name, expected.sessions.sortedBy { it.date }, result.merged.sessions)
            assertEquals(
                name,
                expected.exercises.sortedBy(::contractIdentity),
                result.merged.exercises
            )
        }
    }

    @Test
    fun duplicateStartTimesFailClosed() {
        val scenarios = contract.getJSONArray("failClosedScenarios")
        repeat(scenarios.length()) { index ->
            val scenario = scenarios.getJSONObject(index)
            try {
                merge(scenario)
                fail("Expected a fail-closed merge: ${scenario.getString("name")}")
            } catch (_: WorkoutMergeException) {
                // Expected.
            }
        }
    }

    @Test
    fun divergentWinnersAreReported() {
        val start = sessions.getJSONObject("a").getLong("date")
        val localNewer = scenarioNamed("divergent edits: newer local edit wins")
        val remoteNewer = scenarioNamed("divergent edits: newer remote row wins")

        val localResult = merge(localNewer)
        assertEquals(setOf(start), localResult.localWins)
        assertEquals(emptySet<Long>(), localResult.remoteWins)

        val remoteResult = merge(remoteNewer)
        assertEquals(emptySet<Long>(), remoteResult.localWins)
        assertEquals(setOf(start), remoteResult.remoteWins)
    }

    @Test
    fun changedSessionStartsFindsAddedRemovedAndEditedWorkouts() {
        val before = core(JSONObject().put("sessions", JSONArray().put("a").put("b")))
        val after = core(JSONObject().put("sessions", JSONArray().put("aLocalEdit").put("c")))
        val a = sessions.getJSONObject("a").getLong("date")
        val b = sessions.getJSONObject("b").getLong("date")
        val c = sessions.getJSONObject("c").getLong("date")

        assertEquals(setOf(a, b, c), WorkoutCloudMerge.changedSessionStarts(before, after))
        assertEquals(emptySet<Long>(), WorkoutCloudMerge.changedSessionStarts(before, before))
    }

    @Test
    fun syncStateRoundTripsThroughJson() {
        val baseline = core(JSONObject()
            .put("sessions", JSONArray().put("aLocalEdit").put("d"))
            .put("exercises", JSONArray().put("kickback")))
        val state = WorkoutCloudSyncState(
            ownerUserId = "00000000-0000-4000-8000-0000000001a1",
            baselineDigest = "a".repeat(64),
            baseline = baseline,
            localChangedAt = mapOf(1_789_000_000_000L to 1_790_000_100_000L)
        )

        val decoded = WorkoutCloudSyncState.fromJson(JSONObject(state.toJson().toString()))

        assertEquals(state, decoded)
        val stamped = decoded.withChanges(setOf(1L, 2L), changedAt = 5L)
        assertEquals(5L, stamped.localChangedAt[1L])
        assertEquals(3, stamped.localChangedAt.size)
    }

    private fun merge(scenario: JSONObject): WorkoutMergeResult {
        val journal = mutableMapOf<Long, Long>()
        scenario.optJSONObject("localChangedAt")?.let { changes ->
            changes.keys().forEach { fixture ->
                val start = sessions.getJSONObject(fixture).getLong("date")
                journal[start] = times.getLong(changes.getString(fixture))
            }
        }
        return WorkoutCloudMerge.merge(
            base = core(scenario.getJSONObject("base")),
            local = core(scenario.getJSONObject("local")),
            remote = core(scenario.getJSONObject("remote")),
            localChangedAt = journal,
            remoteRowUpdatedAt = times.getLong("remoteRowUpdatedAt"),
            exerciseIdentity = ::contractIdentity,
            requiresCatalogEntry = { block -> block.catalogKey == null }
        )
    }

    private fun core(side: JSONObject): WorkoutMergeCore {
        val sessionNames = side.optJSONArray("sessions") ?: JSONArray()
        val exerciseNames = side.optJSONArray("exercises") ?: JSONArray()
        val coreJson = JSONObject()
            .put("sessions", JSONArray().apply {
                repeat(sessionNames.length()) { put(sessions.getJSONObject(sessionNames.getString(it))) }
            })
            .put("exercises", JSONArray().apply {
                repeat(exerciseNames.length()) { put(exercises.getJSONObject(exerciseNames.getString(it))) }
            })
        return WorkoutCloudSyncState.decodeCore(JSONObject(coreJson.toString()))
    }

    private fun scenarioNamed(name: String): JSONObject {
        val scenarios = contract.getJSONArray("mergeScenarios")
        repeat(scenarios.length()) { index ->
            val scenario = scenarios.getJSONObject(index)
            if (scenario.getString("name") == name) return scenario
        }
        error("Missing scenario $name")
    }

    /** The contract's reference identity: normalized name plus catalog key. */
    private fun contractIdentity(exercise: WorkoutMergeExercise): String {
        val name = exercise.name.trim().replace(Regex("\\s+"), " ").lowercase()
        return "$name|${exercise.catalogKey.orEmpty()}"
    }

    private fun sharedFixture(): File {
        val direct = File("shared/workout-sync-merge-v1.json")
        if (direct.isFile) return direct
        return File("../shared/workout-sync-merge-v1.json").also {
            check(it.isFile) { "Shared workout merge contract was not found." }
        }
    }
}
