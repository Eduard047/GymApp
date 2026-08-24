package com.example.gymapp.sync

import com.example.gymapp.auth.parseWorkoutDurationSyncAcknowledgement
import com.example.gymapp.auth.isUnavailableActivityOnlyWorkoutRpc
import com.example.gymapp.auth.isRetryableActivityOnlyWorkoutSqlState
import com.example.gymapp.auth.retryActivityOnlyWorkoutOutcomeUnknown
import com.example.gymapp.data.repository.ActivityOnlyWorkoutItem
import com.example.gymapp.data.repository.ActivityOnlyWorkoutLocalSnapshot
import com.example.gymapp.data.repository.ActivityOnlyWorkoutSyncJournalRecord
import com.example.gymapp.data.repository.activityOnlyWorkoutDigest
import com.example.gymapp.data.repository.threeWayMergeActivityOnlyWorkoutItems
import java.io.IOException
import java.util.ArrayDeque
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivityOnlyWorkoutSidecarContractTest {
    private val owner = "123e4567-e89b-12d3-a456-426614174000"
    private val firstRequest = "123e4567-e89b-12d3-a456-426614174001"
    private val secondRequest = "123e4567-e89b-12d3-a456-426614174002"

    @Test
    fun `read and write shapes are strict bounded and canonical`() {
        val item = activity(startedAt = 1_750_000_000_000L)
        val response = JSONObject()
            .put("version", 1)
            .put("revision", 7)
            .put("items", activityOnlyWorkoutItemsJson(listOf(item)))
            .toString()

        val parsed = parseActivityOnlyWorkoutReadResponse(response)
        assertEquals(7L, parsed.revision)
        assertEquals(listOf(item), parsed.items)

        val request = activityOnlyWorkoutSyncRequestJson(7, firstRequest, listOf(item))
        assertEquals(
            setOf("p_expected_revision", "p_request_id", "p_items"),
            request.keys().asSequence().toSet()
        )
        assertEquals(7L, request.getLong("p_expected_revision"))
        assertEquals(firstRequest, request.getString("p_request_id"))
        assertEquals(
            setOf(
                "workoutStartedAt",
                "durationSeconds",
                "gymCalories",
                "garminCalories",
                "averageHeartRate",
                "maximumHeartRate",
                "endingHeartRateZone",
                "note"
            ),
            request.getJSONArray("p_items").getJSONObject(0).keys().asSequence().toSet()
        )

        assertThrows(IllegalArgumentException::class.java) {
            parseActivityOnlyWorkoutReadResponse(
                JSONObject(response).put("unknown", true).toString()
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseActivityOnlyWorkoutReadResponse(
                JSONObject(response)
                    .put(
                        "items",
                        JSONArray()
                            .put(activityOnlyWorkoutItemsJson(listOf(item)).getJSONObject(0))
                            .put(
                                activityOnlyWorkoutItemsJson(
                                    listOf(activity(startedAt = item.workoutStartedAt - 1L))
                                ).getJSONObject(0)
                            )
                    )
                    .toString()
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            activityOnlyWorkoutSyncRequestJson(
                expectedRevision = 0,
                requestId = firstRequest,
                items = listOf(item.copy(durationSeconds = 0))
            )
        }
    }

    @Test
    fun `three-way merge mirrors all shared activity-only golden scenarios`() {
        val a = ActivityOnlyWorkoutItem(
            workoutStartedAt = 1_785_790_000_000L,
            durationSeconds = 600,
            gymCalories = 30.0
        )
        val aLocalEdit = a.copy(
            durationSeconds = 660,
            gymCalories = 31.5,
            note = "local edit"
        )
        val aRemoteEdit = a.copy(
            durationSeconds = 720,
            gymCalories = 32.0,
            note = "remote edit"
        )
        val b = ActivityOnlyWorkoutItem(
            workoutStartedAt = 1_785_791_000_000L,
            durationSeconds = 754,
            gymCalories = 40.0
        )
        val cExact = ActivityOnlyWorkoutItem(
            workoutStartedAt = 1_785_792_000_000L,
            durationSeconds = 900,
            gymCalories = 45.125,
            note = "owner private"
        )
        val cZero = cExact.copy(
            garminCalories = 0,
            averageHeartRate = 0,
            maximumHeartRate = 0,
            endingHeartRateZone = 0
        )
        val items = mapOf(
            "a" to a,
            "aLocalEdit" to aLocalEdit,
            "aRemoteEdit" to aRemoteEdit,
            "b" to b,
            "cExact" to cExact,
            "cZero" to cZero
        )
        val scenarios = listOf(
            MergeScenario("unchanged", listOf("a"), listOf("a"), listOf("a"), listOf("a")),
            MergeScenario(
                "local edit wins against unchanged remote",
                listOf("a"),
                listOf("aLocalEdit"),
                listOf("a"),
                listOf("aLocalEdit")
            ),
            MergeScenario(
                "remote edit wins against unchanged local",
                listOf("a"),
                listOf("a"),
                listOf("aRemoteEdit"),
                listOf("aRemoteEdit")
            ),
            MergeScenario(
                "same edit on both sides",
                listOf("a"),
                listOf("aLocalEdit"),
                listOf("aLocalEdit"),
                listOf("aLocalEdit")
            ),
            MergeScenario(
                "independent additions merge",
                emptyList(),
                listOf("b"),
                listOf("cExact"),
                listOf("b", "cExact")
            ),
            MergeScenario("local deletion propagates", listOf("a"), emptyList(), listOf("a"), emptyList()),
            MergeScenario("remote deletion propagates", listOf("a"), listOf("a"), emptyList(), emptyList()),
            MergeScenario(
                "deletion and unrelated addition both survive",
                listOf("a"),
                listOf("b"),
                emptyList(),
                listOf("b")
            ),
            MergeScenario(
                "remote deletion and independent local addition",
                listOf("a"),
                listOf("a", "b"),
                emptyList(),
                listOf("b")
            ),
            MergeScenario(
                "local deletion and independent exact remote addition",
                listOf("a"),
                emptyList(),
                listOf("a", "cExact"),
                listOf("cExact")
            ),
            MergeScenario(
                "equal concurrent same-identity addition",
                emptyList(),
                listOf("b"),
                listOf("b"),
                listOf("b")
            ),
            MergeScenario(
                "local delete versus remote edit conflicts",
                listOf("a"),
                emptyList(),
                listOf("aRemoteEdit"),
                conflict = true
            ),
            MergeScenario(
                "remote delete versus local edit conflicts",
                listOf("a"),
                listOf("aLocalEdit"),
                emptyList(),
                conflict = true
            ),
            MergeScenario(
                "divergent edits conflict",
                listOf("a"),
                listOf("aLocalEdit"),
                listOf("aRemoteEdit"),
                conflict = true
            ),
            MergeScenario(
                "divergent concurrent same-identity additions conflict",
                emptyList(),
                listOf("cExact"),
                listOf("cZero"),
                conflict = true
            )
        )

        scenarios.forEach { scenario ->
            fun resolve(names: List<String>): List<ActivityOnlyWorkoutItem> =
                names.map { name -> checkNotNull(items[name]) }
                    .sortedBy(ActivityOnlyWorkoutItem::workoutStartedAt)
            val result = runCatching {
                threeWayMergeActivityOnlyWorkoutItems(
                    base = resolve(scenario.base),
                    local = resolve(scenario.local),
                    remote = resolve(scenario.remote)
                )
            }
            if (scenario.conflict) {
                assertTrue(scenario.name, result.exceptionOrNull() is IllegalArgumentException)
            } else {
                assertEquals(scenario.name, resolve(scenario.result), result.getOrThrow())
            }
        }
    }

    @Test
    fun `three-way merge preserves empty note versus null and enforces result bound`() {
        val base = activity().copy(note = null)
        assertEquals(
            listOf(base.copy(note = "")),
            threeWayMergeActivityOnlyWorkoutItems(
                base = listOf(base),
                local = listOf(base.copy(note = "")),
                remote = listOf(base)
            )
        )

        val local = List(2_501) { index ->
            ActivityOnlyWorkoutItem(
                workoutStartedAt = 1_750_000_000_000L + index,
                durationSeconds = 1,
                gymCalories = 0.0
            )
        }
        val remote = List(2_500) { index ->
            ActivityOnlyWorkoutItem(
                workoutStartedAt = 1_750_100_000_000L + index,
                durationSeconds = 1,
                gymCalories = 0.0
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            threeWayMergeActivityOnlyWorkoutItems(emptyList(), local, remote)
        }
    }

    @Test
    fun `durable baseline record round-trips exact optional fields and rejects tampering`() {
        val exact = activity().copy(
            garminCalories = null,
            averageHeartRate = 0,
            maximumHeartRate = null,
            endingHeartRateZone = 0,
            note = ""
        )
        val baseline = ActivityOnlyWorkoutCloudBaseline(
            ownerUserId = owner,
            revision = 7,
            items = listOf(exact)
        )
        val record = baseline.toRecord()

        assertEquals(baseline, ActivityOnlyWorkoutCloudBaseline.fromRecord(record))
        assertEquals(listOf(exact), parseActivityOnlyWorkoutItemsJson(record.itemsJson))
        assertThrows(IllegalArgumentException::class.java) {
            ActivityOnlyWorkoutCloudBaseline.fromRecord(record.copy(itemsJson = "[]"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            ActivityOnlyWorkoutCloudBaseline.fromRecord(
                record.copy(ownerUserId = "not-an-owner")
            )
        }
    }

    @Test
    fun `outcome unknown replays exact durable request before newer local data`() = runBlocking {
        val firstItem = activity(startedAt = 1_750_000_000_000L)
        val secondItem = activity(startedAt = 1_750_000_100_000L, gymCalories = 0.0)
        var local = ActivityOnlyWorkoutLocalSnapshot(listOf(firstItem))
        var journal: ActivityOnlyWorkoutSyncJournalRecord? = null
        val requestIds = ArrayDeque(listOf(firstRequest, secondRequest))
        val writes = mutableListOf<Write>()
        var failFirstDispatch = true

        suspend fun runSync(): ActivityOnlyWorkoutCloudBaseline =
            syncActivityOnlyWorkoutSidecar(
                ownerUserId = owner,
                baseline = ActivityOnlyWorkoutCloudBaseline(
                    ownerUserId = owner,
                    revision = 0,
                    items = emptyList()
                ),
                readLocal = { local },
                reconcileLocal = { canonical ->
                    local = ActivityOnlyWorkoutLocalSnapshot(canonical)
                    local
                },
                readRemote = { error("Conflict read was not expected.") },
                writeRemote = { revision, requestId, items ->
                    writes += Write(revision, requestId, items)
                    if (failFirstDispatch) {
                        failFirstDispatch = false
                        throw IOException("response lost after dispatch")
                    }
                    ActivityOnlyWorkoutSyncResponse.Synced(
                        revision = if (requestId == firstRequest) 1 else 2,
                        syncedCount = items.size,
                        changedCount = items.size,
                        replayed = requestId == firstRequest
                    )
                },
                readJournal = { journal },
                persistJournal = { pending ->
                    require(journal == null || journal == pending)
                    journal = pending
                },
                clearJournal = { pending ->
                    if (journal == pending) {
                        journal = null
                        true
                    } else {
                        false
                    }
                },
                persistBaseline = { },
                requestIdFactory = { requestIds.removeFirst() }
            )

        assertTrue(runCatching { runSync() }.exceptionOrNull() is IOException)
        val durableAfterUnknown = checkNotNull(journal)
        val firstDurableBody = activityOnlyWorkoutSyncRequestJson(
            expectedRevision = durableAfterUnknown.expectedRevision,
            requestId = durableAfterUnknown.requestId,
            items = listOf(firstItem)
        ).toString()
        val restartReplayBody = activityOnlyWorkoutSyncRequestJson(
            expectedRevision = durableAfterUnknown.expectedRevision,
            requestId = durableAfterUnknown.requestId,
            items = parseActivityOnlyWorkoutItemsJson(durableAfterUnknown.itemsJson)
        ).toString()
        assertEquals(firstDurableBody, restartReplayBody)
        local = ActivityOnlyWorkoutLocalSnapshot(listOf(firstItem, secondItem))

        val completed = runSync()

        assertEquals(writes[0], writes[1])
        assertEquals(durableAfterUnknown.requestId, writes[1].requestId)
        assertEquals(durableAfterUnknown.expectedRevision, writes[1].expectedRevision)
        assertEquals(listOf(firstItem), writes[1].items)
        assertEquals(secondRequest, writes[2].requestId)
        assertEquals(1L, writes[2].expectedRevision)
        assertEquals(listOf(firstItem, secondItem), writes[2].items)
        assertEquals(2L, completed.revision)
        assertEquals(local.digest, completed.digest)
        assertEquals(null, journal)
    }

    @Test
    fun `explicit CAS conflict atomically merges then uses a new UUID`() = runBlocking {
        val localItem = activity(startedAt = 1_750_000_000_000L)
        val remoteItem = activity(startedAt = 1_750_000_100_000L, gymCalories = 0.0)
        var local = ActivityOnlyWorkoutLocalSnapshot(listOf(localItem))
        var journal: ActivityOnlyWorkoutSyncJournalRecord? = null
        val requestIds = ArrayDeque(listOf(firstRequest, secondRequest))
        val writes = mutableListOf<Write>()

        val completed = syncActivityOnlyWorkoutSidecar(
            ownerUserId = owner,
            baseline = ActivityOnlyWorkoutCloudBaseline(
                ownerUserId = owner,
                revision = 4,
                items = emptyList()
            ),
            readLocal = { local },
            reconcileLocal = { canonical ->
                local = ActivityOnlyWorkoutLocalSnapshot(canonical)
                local
            },
            readRemote = {
                ActivityOnlyWorkoutRemoteSnapshot(5, listOf(remoteItem))
            },
            writeRemote = { revision, requestId, items ->
                writes += Write(revision, requestId, items)
                if (writes.size == 1) {
                    ActivityOnlyWorkoutSyncResponse.Conflict(5)
                } else {
                    ActivityOnlyWorkoutSyncResponse.Synced(
                        revision = 6,
                        syncedCount = items.size,
                        changedCount = items.size,
                        replayed = false
                    )
                }
            },
            readJournal = { journal },
            persistJournal = { pending ->
                require(journal == null)
                journal = pending
            },
            clearJournal = { pending ->
                if (journal == pending) {
                    journal = null
                    true
                } else {
                    false
                }
            },
            persistBaseline = { },
            requestIdFactory = { requestIds.removeFirst() }
        )

        assertEquals(2, writes.size)
        assertEquals(4L, writes[0].expectedRevision)
        assertEquals(5L, writes[1].expectedRevision)
        assertNotEquals(writes[0].requestId, writes[1].requestId)
        assertEquals(listOf(localItem, remoteItem).sortedBy { it.workoutStartedAt }, writes[1].items)
        assertEquals(6L, completed.revision)
        assertEquals(null, journal)
    }

    @Test
    fun `restart replays deletion journal before stale remote can materialize`() = runBlocking {
        val deleted = activity(startedAt = 1_750_000_000_000L)
        var local = ActivityOnlyWorkoutLocalSnapshot(emptyList())
        var journal: ActivityOnlyWorkoutSyncJournalRecord? = null
        var durableBaseline = ActivityOnlyWorkoutCloudBaseline(
            ownerUserId = owner,
            revision = 4,
            items = listOf(deleted)
        )
        val events = mutableListOf<String>()
        var loseFirstResponse = true

        suspend fun runSync(forceRemoteRead: Boolean): ActivityOnlyWorkoutCloudBaseline =
            syncActivityOnlyWorkoutSidecar(
                ownerUserId = owner,
                baseline = durableBaseline,
                readLocal = { local },
                reconcileLocal = { canonical ->
                    events += "reconcile"
                    local = ActivityOnlyWorkoutLocalSnapshot(canonical)
                    local
                },
                readRemote = {
                    events += "readRemote"
                    ActivityOnlyWorkoutRemoteSnapshot(revision = 5, items = emptyList())
                },
                writeRemote = { revision, requestId, items ->
                    events += "write:$revision:$requestId:${items.size}"
                    if (loseFirstResponse) {
                        loseFirstResponse = false
                        throw IOException("response lost after deletion committed")
                    }
                    ActivityOnlyWorkoutSyncResponse.Synced(
                        revision = 5,
                        syncedCount = items.size,
                        changedCount = 1,
                        replayed = true
                    )
                },
                readJournal = { journal },
                persistJournal = { pending ->
                    require(journal == null || journal == pending)
                    journal = pending
                },
                clearJournal = { pending ->
                    (journal == pending).also { exact -> if (exact) journal = null }
                },
                persistBaseline = { confirmed -> durableBaseline = confirmed },
                forceRemoteRead = forceRemoteRead,
                requestIdFactory = { firstRequest }
            )

        assertTrue(runCatching { runSync(forceRemoteRead = false) }.exceptionOrNull() is IOException)
        val exactPending = checkNotNull(journal)
        assertEquals(emptyList<ActivityOnlyWorkoutItem>(), parseActivityOnlyWorkoutItemsJson(exactPending.itemsJson))
        val eventsBeforeRestart = events.size

        val completed = runSync(forceRemoteRead = true)

        val restartEvents = events.drop(eventsBeforeRestart)
        assertTrue(restartEvents.first().startsWith("write:4:$firstRequest:0"))
        assertTrue(restartEvents.indexOfFirst { it.startsWith("write:") } <
            restartEvents.indexOf("readRemote"))
        assertEquals(emptyList<ActivityOnlyWorkoutItem>(), completed.items)
        assertEquals(emptyList<ActivityOnlyWorkoutItem>(), local.items)
        assertEquals(null, journal)
    }

    @Test
    fun `owner switch and baseline revision mismatch fail closed without consuming journal`() =
        runBlocking {
            val pending = ActivityOnlyWorkoutSyncJournalRecord(
                ownerUserId = owner,
                expectedRevision = 4,
                requestId = firstRequest,
                itemsJson = "[]",
                itemsDigest = activityOnlyWorkoutDigest(emptyList())
            )
            var journal: ActivityOnlyWorkoutSyncJournalRecord? = pending
            var remoteRead = false

            assertThrows(IllegalArgumentException::class.java) {
                runBlocking {
                    syncActivityOnlyWorkoutSidecar(
                        ownerUserId = "123e4567-e89b-12d3-a456-426614174099",
                        baseline = ActivityOnlyWorkoutCloudBaseline(
                            ownerUserId = owner,
                            revision = 4,
                            items = emptyList()
                        ),
                        readLocal = { ActivityOnlyWorkoutLocalSnapshot(emptyList()) },
                        reconcileLocal = { ActivityOnlyWorkoutLocalSnapshot(it) },
                        readRemote = { error("must not read") },
                        writeRemote = { _, _, _ -> error("must not write") },
                        readJournal = { journal },
                        persistJournal = { error("must not persist") },
                        clearJournal = { false },
                        persistBaseline = { error("must not persist") }
                    )
                }
            }
            assertEquals(pending, journal)

            val failure = runCatching {
                syncActivityOnlyWorkoutSidecar(
                    ownerUserId = owner,
                    baseline = ActivityOnlyWorkoutCloudBaseline(
                        ownerUserId = owner,
                        revision = 3,
                        items = emptyList()
                    ),
                    readLocal = { ActivityOnlyWorkoutLocalSnapshot(emptyList()) },
                    reconcileLocal = { ActivityOnlyWorkoutLocalSnapshot(it) },
                    readRemote = {
                        remoteRead = true
                        ActivityOnlyWorkoutRemoteSnapshot(5, emptyList())
                    },
                    writeRemote = { _, _, _ -> ActivityOnlyWorkoutSyncResponse.Conflict(5) },
                    readJournal = { journal },
                    persistJournal = { error("must not persist") },
                    clearJournal = { cleared ->
                        if (journal == cleared) {
                            journal = null
                            true
                        } else {
                            false
                        }
                    },
                    persistBaseline = { error("must not persist") }
                )
            }.exceptionOrNull()

            assertTrue(failure is IllegalArgumentException)
            assertTrue(!remoteRead)
            assertEquals(pending, journal)
        }

    @Test
    fun `duration sidecar accepts production v2 and rejects stale or oversized retry`() {
        assertEquals(
            2,
            parseWorkoutDurationSyncAcknowledgement(
                rawResponse = """{"version":2,"syncedCount":2,"changedCount":3}""",
                expectedCount = 2
            ).syncedCount
        )
        assertThrows(IllegalArgumentException::class.java) {
            parseWorkoutDurationSyncAcknowledgement(
                rawResponse = """{"version":1,"syncedCount":2}""",
                expectedCount = 2
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            parseWorkoutDurationSyncAcknowledgement(
                rawResponse = """{"version":2,"error":"rate_limited","retryAfter":601}""",
                expectedCount = 2
            )
        }
    }

    @Test
    fun `rollout fallback accepts only exact missing RPC errors`() {
        assertTrue(isUnavailableActivityOnlyWorkoutRpc(404, "PGRST202"))
        assertTrue(isUnavailableActivityOnlyWorkoutRpc(404, "PGRST203"))
        assertTrue(!isUnavailableActivityOnlyWorkoutRpc(404, "42501"))
        assertTrue(!isUnavailableActivityOnlyWorkoutRpc(500, "PGRST202"))
        assertTrue(!isUnavailableActivityOnlyWorkoutRpc(404, null))
    }

    @Test
    fun `transport retries exact body only for network unknown and exact SQL states`() =
        runBlocking {
            val exactBody = """{"p_expected_revision":4,"p_request_id":"$firstRequest","p_items":[]}"""
            val dispatchedBodies = mutableListOf<String>()
            val result = retryActivityOnlyWorkoutOutcomeUnknown(
                isRetryableSqlFailure = { false },
                retryDelay = { }
            ) {
                dispatchedBodies += exactBody
                if (dispatchedBodies.size < 3) throw IOException("outcome unknown")
                "synced"
            }

            assertEquals("synced", result)
            assertEquals(listOf(exactBody, exactBody, exactBody), dispatchedBodies)
            assertTrue(isRetryableActivityOnlyWorkoutSqlState("55P03"))
            assertTrue(isRetryableActivityOnlyWorkoutSqlState("57014"))
            assertTrue(!isRetryableActivityOnlyWorkoutSqlState("40001"))
            assertTrue(!isRetryableActivityOnlyWorkoutSqlState(null))
        }

    private fun activity(
        startedAt: Long = 1_750_000_000_000L,
        gymCalories: Double = 87.125
    ): ActivityOnlyWorkoutItem = ActivityOnlyWorkoutItem(
        workoutStartedAt = startedAt,
        durationSeconds = 1_234,
        gymCalories = gymCalories,
        garminCalories = 92,
        averageHeartRate = 131,
        maximumHeartRate = 168,
        endingHeartRateZone = 3,
        note = "Garmin · Free workout"
    )

    private data class Write(
        val expectedRevision: Long,
        val requestId: String,
        val items: List<ActivityOnlyWorkoutItem>
    )

    private data class MergeScenario(
        val name: String,
        val base: List<String>,
        val local: List<String>,
        val remote: List<String>,
        val result: List<String> = emptyList(),
        val conflict: Boolean = false
    )
}
