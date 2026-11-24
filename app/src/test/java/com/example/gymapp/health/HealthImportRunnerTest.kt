package com.example.gymapp.health

import com.example.gymapp.data.repository.ActivityOnlyWorkoutItem
import com.example.gymapp.util.AppLanguage
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthImportRunnerTest {
    private val now = 1_750_000_000_000L
    private val minute = 60_000L

    private fun gym(id: String, startMinutesAgo: Long, minutes: Long = 30, type: String = "STRENGTH_TRAINING",
        source: String = "watch") = HealthImportSession(
        recordId = id,
        startMillis = now - startMinutesAgo * minute,
        endMillis = now - startMinutesAgo * minute + minutes * minute,
        exerciseType = type,
        sourceId = source
    )

    private class FakeSource(
        val sessions: List<HealthImportSession>,
        val truncated: Boolean = false,
        val onDetails: () -> Unit = {}
    ) : HealthSessionSource {
        var listCalls = 0
        var detailLoads = 0
        var listedFrom = 0L
        override suspend fun listSessions(fromMillis: Long, toMillis: Long, maxRecords: Int): HealthSessionListing {
            listCalls++
            listedFrom = fromMillis
            return HealthSessionListing(sessions, truncated)
        }

        override suspend fun loadDetails(session: HealthImportSession): HealthImportSession {
            detailLoads++
            onDetails()
            return session.copy(
                kilocalories = 100.0,
                heartRateSamples = listOf(HeartRateSample(session.startMillis + 1_000L, 120))
            )
        }
    }

    private class FakePersistence(
        var existing: List<HealthExistingWorkout> = emptyList(),
        var receipts: Set<String> = emptySet(),
        var last: Long? = null,
        var enabled: Boolean = true,
        var result: HealthImportPersistResult = HealthImportPersistResult.IMPORTED
    ) : HealthImportPersistence {
        val persisted = mutableListOf<Pair<ActivityOnlyWorkoutItem, String>>()
        override suspend fun existingWorkouts(fromMillis: Long) = existing
        override suspend fun knownReceipts(keys: Collection<String>) = keys.filter { it in receipts }.toSet()
        override suspend fun persist(item: ActivityOnlyWorkoutItem, receiptKey: String): HealthImportPersistResult {
            if (result == HealthImportPersistResult.IMPORTED) persisted += item to receiptKey
            return result
        }
        override suspend fun isEnabled() = enabled
        override suspend fun lastImportAt() = last
        override suspend fun setLastImportAt(millis: Long) { last = millis }
    }

    private fun runner(
        source: HealthSessionSource,
        persistence: HealthImportPersistence,
        active: () -> Boolean = { true }
    ) = HealthImportRunner(
        store = HealthImportStore.HEALTH_CONNECT,
        source = source,
        persistence = persistence,
        language = { AppLanguage.EN },
        isAccountActive = active,
        clock = { now }
    )

    @Test
    fun importsGymSessionsAndCountsSkipsByReason() = runBlocking {
        val source = FakeSource(
            listOf(
                gym("a", 600),
                gym("b", 500, type = "RUNNING"),
                gym("c", 400, source = "com.setforge.gymapp"),
                gym("d", 300, minutes = 0),
                gym("e", 200),
                gym("f", 100)
            )
        )
        val persistence = FakePersistence(
            receipts = setOf("health_connect:e"),
            existing = listOf(HealthExistingWorkout(now - 100 * minute, 1_800))
        )

        val summary = runner(source, persistence).run(HealthImportTrigger.MANUAL)

        assertEquals(HealthImportStatus.COMPLETED, summary.status)
        assertEquals(1, summary.imported)
        assertEquals(1, summary.skippedCount(HealthImportSkipReason.NOT_GYM_TYPE))
        assertEquals(1, summary.skippedCount(HealthImportSkipReason.OWN_APP))
        assertEquals(1, summary.skippedCount(HealthImportSkipReason.DURATION))
        assertEquals(1, summary.skippedCount(HealthImportSkipReason.DUPLICATE_RECEIPT))
        assertEquals(1, summary.skippedCount(HealthImportSkipReason.OVERLAP))
        assertEquals(listOf("health_connect:a"), persistence.persisted.map { it.second })
        assertEquals(1, source.detailLoads)
        assertEquals(now, persistence.last)
        assertEquals(now - 30L * 86_400_000L, source.listedFrom)
    }

    @Test
    fun twoOverlappingSessionsFromDifferentAppsImportOnlyOnce() = runBlocking {
        val source = FakeSource(listOf(gym("watch", 100), gym("phone", 99, source = "other")))
        val persistence = FakePersistence()

        val summary = runner(source, persistence).run(HealthImportTrigger.MANUAL)

        assertEquals(1, summary.imported)
        assertEquals(1, summary.skippedCount(HealthImportSkipReason.OVERLAP))
        assertEquals(listOf("health_connect:phone"), persistence.persisted.map { it.second })
    }

    @Test
    fun automaticRunsAreThrottledButManualRunsAreNot() = runBlocking {
        val source = FakeSource(listOf(gym("a", 100)))
        val persistence = FakePersistence(last = now - 3_599_000L)

        val throttled = runner(source, persistence).run(HealthImportTrigger.AUTOMATIC)
        assertEquals(HealthImportStatus.THROTTLED, throttled.status)
        assertEquals(0, source.detailLoads)
        assertEquals(now - 3_599_000L, persistence.last)

        val manual = runner(source, persistence).run(HealthImportTrigger.MANUAL)
        assertEquals(1, manual.imported)

        persistence.last = now - 3_600_000L
        val later = runner(FakeSource(listOf(gym("z", 700))), persistence).run(HealthImportTrigger.AUTOMATIC)
        assertEquals(HealthImportStatus.COMPLETED, later.status)
    }

    @Test
    fun capLimitsEvaluatedGymSessionsNewestFirstAndIgnoresOtherSessions() = runBlocking {
        val gymSessions = (1..205).map { gym("g$it", it.toLong() * 40, minutes = 20) }
        val noise = (1..50).map { gym("w$it", 10_000L + it, type = "WALKING") }
        val source = FakeSource(gymSessions + noise)
        val persistence = FakePersistence()

        val summary = runner(source, persistence).run(HealthImportTrigger.MANUAL)

        assertEquals(200, summary.imported)
        assertTrue(summary.truncated)
        assertEquals(50, summary.skippedCount(HealthImportSkipReason.NOT_GYM_TYPE))
        // Newest first: the five oldest gym sessions were left for a later run.
        val keys = persistence.persisted.map { it.second }.toSet()
        assertTrue("health_connect:g1" in keys)
        assertFalse("health_connect:g205" in keys)
    }

    @Test
    fun sourceTruncationIsReported() = runBlocking {
        val summary = runner(FakeSource(listOf(gym("a", 100)), truncated = true), FakePersistence())
            .run(HealthImportTrigger.MANUAL)
        assertTrue(summary.truncated)
    }

    @Test
    fun accountSwitchBeforeTheWriteAbortsWithoutWritingOrRecordingCompletion() = runBlocking {
        var active = true
        val source = FakeSource(listOf(gym("a", 100), gym("b", 300))) { active = false }
        val persistence = FakePersistence()

        val summary = runner(source, persistence) { active }.run(HealthImportTrigger.MANUAL)

        assertEquals(HealthImportStatus.ABORTED_ACCOUNT_CHANGED, summary.status)
        assertEquals(0, summary.imported)
        assertTrue(persistence.persisted.isEmpty())
        assertNull(persistence.last)
    }

    @Test
    fun inactiveAccountAtStartDoesNothing() = runBlocking {
        val source = FakeSource(listOf(gym("a", 100)))
        val persistence = FakePersistence()

        val summary = runner(source, persistence) { false }.run(HealthImportTrigger.MANUAL)

        assertEquals(HealthImportStatus.ABORTED_ACCOUNT_CHANGED, summary.status)
        assertEquals(0, source.detailLoads)
    }

    @Test
    fun repeatedRunIsIdempotentThroughReceipts() = runBlocking {
        val source = FakeSource(listOf(gym("a", 100)))
        val persistence = FakePersistence()
        runner(source, persistence).run(HealthImportTrigger.MANUAL)

        persistence.receipts = persistence.persisted.map { it.second }.toSet()
        val second = runner(source, persistence).run(HealthImportTrigger.MANUAL)

        assertEquals(0, second.imported)
        assertEquals(1, second.skippedCount(HealthImportSkipReason.DUPLICATE_RECEIPT))
        assertEquals(1, persistence.persisted.size)
    }

    @Test
    fun raceLosersFromTheTransactionAreCountedAsSkips() = runBlocking {
        val persistence = FakePersistence(result = HealthImportPersistResult.OVERLAP)
        val summary = runner(FakeSource(listOf(gym("a", 100))), persistence).run(HealthImportTrigger.MANUAL)
        assertEquals(0, summary.imported)
        assertEquals(1, summary.skippedCount(HealthImportSkipReason.OVERLAP))
    }

    @Test
    fun capacityReachedStopsTheRun() = runBlocking {
        val persistence = FakePersistence(result = HealthImportPersistResult.CAPACITY_REACHED)
        val source = FakeSource(listOf(gym("a", 100), gym("b", 300)))
        val summary = runner(source, persistence).run(HealthImportTrigger.MANUAL)
        assertTrue(summary.capacityReached)
        assertEquals(1, source.detailLoads)
    }

    @Test
    fun accountThatHasNotOptedInReadsNothingForAnyTrigger() = runBlocking {
        val source = FakeSource(listOf(gym("a", 100)))
        val persistence = FakePersistence(enabled = false)

        for (trigger in HealthImportTrigger.entries) {
            val summary = runner(source, persistence).run(trigger)
            assertEquals(HealthImportStatus.NOT_ENABLED, summary.status)
            assertEquals(0, summary.imported)
        }
        assertEquals(0, source.listCalls)
        assertEquals(0, source.detailLoads)
        assertTrue(persistence.persisted.isEmpty())
        assertNull(persistence.last)

        persistence.enabled = true
        assertEquals(1, runner(source, persistence).run(HealthImportTrigger.MANUAL).imported)
    }

    @Test
    fun sessionsStillRunningAreSkippedAndPickedUpLater() = runBlocking {
        val running = gym("running", 10, minutes = 30) // ends 20 minutes after now
        val source = FakeSource(listOf(running, gym("done", 100)))
        val persistence = FakePersistence()

        val summary = runner(source, persistence).run(HealthImportTrigger.MANUAL)

        assertEquals(1, summary.imported)
        assertEquals(1, summary.skippedCount(HealthImportSkipReason.IN_PROGRESS))
        assertEquals(listOf("health_connect:done"), persistence.persisted.map { it.second })
    }

    @Test
    fun malformedRecordIdsAreSkippedInsteadOfBlockingTheRun() = runBlocking {
        val source = FakeSource(
            listOf(gym("x".repeat(242), 300), gym("bad\u0007id", 200), gym("ok", 100))
        )
        val persistence = FakePersistence()

        val summary = runner(source, persistence).run(HealthImportTrigger.MANUAL)

        assertEquals(HealthImportStatus.COMPLETED, summary.status)
        assertEquals(2, summary.skippedCount(HealthImportSkipReason.INVALID_RECORD))
        assertEquals(listOf("health_connect:ok"), persistence.persisted.map { it.second })
        assertEquals(1, source.detailLoads)
    }

    @Test
    fun failedDetailReadSkipsOnlyThatCandidateWithoutReceipt() = runBlocking {
        val failing = object : HealthSessionSource {
            override suspend fun listSessions(fromMillis: Long, toMillis: Long, maxRecords: Int) =
                HealthSessionListing(listOf(gym("a", 600), gym("b", 300)), false)

            override suspend fun loadDetails(session: HealthImportSession): HealthImportSession {
                if (session.recordId == "b") throw IllegalStateException("read failed")
                return session
            }
        }
        val persistence = FakePersistence()

        val summary = runner(failing, persistence).run(HealthImportTrigger.MANUAL)

        assertEquals(HealthImportStatus.COMPLETED, summary.status)
        assertEquals(1, summary.imported)
        assertEquals(1, summary.readFailures)
        assertEquals(listOf("health_connect:a"), persistence.persisted.map { it.second })
        assertEquals(now, persistence.last)
    }

    @Test
    fun truncatedHeartRateSeriesStoresNoHeartRate() {
        val session = gym("a", 600).let {
            it.copy(
                kilocalories = 200.0,
                heartRateSamples = listOf(HeartRateSample(it.startMillis + 1_000L, 150)),
                heartRateComplete = false
            )
        }
        val item = HealthImportRules.build(HealthImportStore.HEALTH_CONNECT, session, AppLanguage.EN)
        assertNull(item.averageHeartRate)
        assertNull(item.maximumHeartRate)
        assertEquals(200.0, item.gymCalories, 0.0)
        assertFalse(item.note.orEmpty().contains("HR"))
        val complete = HealthImportRules.build(
            HealthImportStore.HEALTH_CONNECT,
            session.copy(heartRateComplete = true),
            AppLanguage.EN
        )
        assertEquals(150, complete.averageHeartRate)
    }
}
