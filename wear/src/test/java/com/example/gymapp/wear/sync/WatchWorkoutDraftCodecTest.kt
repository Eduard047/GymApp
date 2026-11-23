package com.example.gymapp.wear.sync

import com.example.gymapp.wear.data.WearWorkoutSetDraft
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WatchWorkoutDraftCodecTest {
    private val running = WatchWorkoutDraft(
        draftId = "draft-1",
        startedAt = 1_700_000_000_000L,
        pausedTotalMs = 42_000L,
        pausedAtMs = 1_700_000_300_000L,
        usingPlan = true,
        selectedExercise = "Жим лежачи",
        sets = listOf(
            WearWorkoutSetDraft("Жим лежачи", 82.5, 8),
            WearWorkoutSetDraft("Squat", 0.0, 12)
        ),
        finished = null
    )

    @Test
    fun aRunningWorkoutSurvivesARoundTripUnchanged() {
        assertEquals(running, WatchWorkoutDraftCodec.decode(WatchWorkoutDraftCodec.encode(running)))
    }

    @Test
    fun aStartedWorkoutWithoutSetsIsKept() {
        val started = running.copy(sets = emptyList(), selectedExercise = null, pausedAtMs = null)
        assertEquals(started, WatchWorkoutDraftCodec.decode(WatchWorkoutDraftCodec.encode(started)))
    }

    @Test
    fun theFrozenResultOfSaveSurvivesARoundTripIncludingAbsentValues() {
        val withHeartRate = running.copy(
            pausedAtMs = null,
            finished = FinishedWorkoutSnapshot(durationSeconds = 3_125L, averageHeartRate = 118, maxHeartRate = 164)
        )
        assertEquals(withHeartRate, WatchWorkoutDraftCodec.decode(WatchWorkoutDraftCodec.encode(withHeartRate)))

        val withoutHeartRate = withHeartRate.copy(
            finished = FinishedWorkoutSnapshot(durationSeconds = 0L, averageHeartRate = null, maxHeartRate = null)
        )
        assertEquals(withoutHeartRate, WatchWorkoutDraftCodec.decode(WatchWorkoutDraftCodec.encode(withoutHeartRate)))
    }

    @Test
    fun outOfRangeResultValuesAreDroppedWithoutLosingTheSets() {
        val json = JSONObject(
            WatchWorkoutDraftCodec.encode(
                running.copy(finished = FinishedWorkoutSnapshot(60L, 120, 150))
            )
        )
        json.getJSONObject("finished")
            .put("durationSeconds", SyncPaths.MAX_DURATION_SECONDS + 1)
            .put("avgHeartRate", 300)
        val decoded = requireNotNull(WatchWorkoutDraftCodec.decode(json.toString()))
        assertEquals(running.sets, decoded.sets)
        assertEquals(FinishedWorkoutSnapshot(null, null, 150), decoded.finished)

        // An average above the maximum is not trustworthy either way: send neither.
        json.getJSONObject("finished").put("avgHeartRate", 160)
        assertEquals(
            FinishedWorkoutSnapshot(null, null, null),
            requireNotNull(WatchWorkoutDraftCodec.decode(json.toString())).finished
        )
    }

    @Test
    fun corruptOrOutOfBoundsDraftsAreRejected() {
        fun mutated(change: (JSONObject) -> Unit): String =
            JSONObject(WatchWorkoutDraftCodec.encode(running)).also(change).toString()

        assertNull(WatchWorkoutDraftCodec.decode("not json"))
        assertNull(WatchWorkoutDraftCodec.decode(mutated { it.put("draftId", "") }))
        assertNull(WatchWorkoutDraftCodec.decode(mutated { it.put("startedAt", 0) }))
        assertNull(WatchWorkoutDraftCodec.decode(mutated { it.put("pausedTotalMs", -1) }))
        assertNull(WatchWorkoutDraftCodec.decode(mutated { it.put("pausedAtMs", 5) }))
        assertNull(WatchWorkoutDraftCodec.decode(mutated { it.getJSONArray("sets").getJSONObject(0).put("reps", 0) }))
        assertNull(
            WatchWorkoutDraftCodec.decode(
                mutated { it.getJSONArray("sets").getJSONObject(0).put("weight", SyncPaths.MAX_WEIGHT * 2) }
            )
        )
        assertNull(
            WatchWorkoutDraftCodec.decode(
                mutated { it.getJSONArray("sets").getJSONObject(1).put("exerciseName", "x".repeat(121)) }
            )
        )
        // A "finished" workout with nothing in it cannot be sent and must not block the watch.
        assertNull(
            WatchWorkoutDraftCodec.decode(
                WatchWorkoutDraftCodec.encode(
                    running.copy(sets = emptyList(), finished = FinishedWorkoutSnapshot(1L, null, null))
                )
            )
        )
    }

    @Test
    fun moreSetsThanTheProtocolAllowsAreRejected() {
        val tooMany = running.copy(sets = List(SyncPaths.MAX_WORKOUT_SETS + 1) { WearWorkoutSetDraft("Row", 40.0, 10) })
        assertNull(WatchWorkoutDraftCodec.decode(WatchWorkoutDraftCodec.encode(tooMany)))
    }
}
