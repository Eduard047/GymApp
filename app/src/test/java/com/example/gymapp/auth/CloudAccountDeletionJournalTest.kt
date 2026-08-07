package com.example.gymapp.auth

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudAccountDeletionJournalTest {
    @Test
    fun pendingOwnersSurviveRestartWithoutTokensAndRemainOwnerBound() {
        val storage = MemoryJournalStorage()
        val firstProcess = CloudAccountDeletionJournal(storage)
        val deletedUser = "00000000-0000-4000-8000-000000000001"
        val secondDeletedUser = "00000000-0000-4000-8000-000000000002"
        val firstSession = cloudSession(deletedUser, "00000000-0000-4000-8000-000000000011")
        val secondSession = cloudSession(
            secondDeletedUser,
            "00000000-0000-4000-8000-000000000012"
        )

        assertTrue(firstProcess.markPending(firstSession))
        assertTrue(firstProcess.markPending(secondSession))
        assertFalse(storage.value.orEmpty().contains("token", ignoreCase = true))

        val restartedProcess = CloudAccountDeletionJournal(storage)
        assertEquals(
            listOf(deletedUser, secondDeletedUser),
            restartedProcess.pending().map(PendingCloudAccountDeletion::userId)
        )
        assertEquals(
            listOf(firstSession.sessionGeneration, secondSession.sessionGeneration),
            restartedProcess.pending().map(PendingCloudAccountDeletion::sessionGeneration)
        )
        assertTrue(shouldSuppressRestoredCloudSession(restartedProcess.snapshot(), deletedUser))
        assertFalse(
            shouldSuppressRestoredCloudSession(
                restartedProcess.snapshot(),
                "00000000-0000-4000-8000-000000000099"
            )
        )

        val firstRecord = checkNotNull(PendingCloudAccountDeletion.fromSession(firstSession))
        assertTrue(restartedProcess.clear(firstRecord))
        assertEquals(
            listOf(secondDeletedUser),
            CloudAccountDeletionJournal(storage).pending()
                .map(PendingCloudAccountDeletion::userId)
        )
    }

    @Test
    fun uppercaseUuidKeepsTheExistingDatabaseNameSpelling() {
        val storage = MemoryJournalStorage()
        val journal = CloudAccountDeletionJournal(storage)
        val uppercaseUserId = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
        val session = cloudSession(
            uppercaseUserId,
            "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEF"
        )

        assertTrue(journal.markPending(session))
        val record = CloudAccountDeletionJournal(storage).pending().single()

        assertEquals(uppercaseUserId, record.userId)
        assertEquals("cloud_$uppercaseUserId", record.databaseName)
        assertTrue(
            shouldSuppressRestoredCloudSession(
                journal.snapshot(),
                uppercaseUserId.lowercase()
            )
        )
    }

    @Test
    fun malformedJournalIsPreservedForRecoveryWithoutBeingOverwritten() {
        val storage = MemoryJournalStorage(value = "not-a-versioned-owner")
        val journal = CloudAccountDeletionJournal(storage)

        assertTrue(journal.pending().isEmpty())
        assertTrue(journal.snapshot().unreadable)
        assertTrue(
            shouldSuppressRestoredCloudSession(
                journal.snapshot(),
                "00000000-0000-4000-8000-000000000099"
            )
        )
        assertFalse(
            journal.markPending(
                cloudSession(
                    "00000000-0000-4000-8000-000000000001",
                    "00000000-0000-4000-8000-000000000011"
                )
            )
        )
        assertEquals("not-a-versioned-owner", storage.value)

        val unknownOwner = checkNotNull(
            PendingCloudAccountDeletion.fromOwner(
                "00000000-0000-4000-8000-000000000002",
                "00000000-0000-4000-8000-000000000012"
            )
        )
        assertFalse(journal.clear(unknownOwner))
        assertEquals("not-a-versioned-owner", storage.value)
    }

    @Test
    fun journalWriteFailurePreventsDispatchAndKeepsTheUnsentSessionActive() = runBlocking {
        val failedStorage = MemoryJournalStorage(writesSucceed = false)
        val journal = CloudAccountDeletionJournal(failedStorage)
        val captured = AccountSession.Cloud(
            userId = "00000000-0000-4000-8000-000000000001",
            email = "deleted@example.test",
            displayName = "Deleted",
            accessToken = "captured-token",
            refreshToken = "captured-refresh",
            sessionGeneration = "00000000-0000-4000-8000-000000000010"
        )

        var dispatched = false
        val failure = runCatching {
            runPreparedAccountDeletionRequest(
                persistIntent = { journal.markPending(captured) },
                request = {
                    dispatched = true
                    "response"
                }
            )
        }.exceptionOrNull()

        assertTrue(failure is AccountDeletionPreparationException)
        assertFalse(dispatched)
        assertEquals(captured, activeCloudSessionFor(captured, captured))
    }

    @Test
    fun unknownOutcomeSignsOutOnlyTheCapturedSession() {
        val captured = AccountSession.Cloud(
            userId = "00000000-0000-4000-8000-000000000001",
            email = "deleted@example.test",
            displayName = "Deleted",
            accessToken = "captured-token",
            refreshToken = "captured-refresh",
            sessionGeneration = "00000000-0000-4000-8000-000000000010"
        )
        val fallback = authStateAfterUnknownAccountDeletionOutcome(captured, captured)
        assertNull(fallback?.session)
        assertTrue(fallback?.messageIsError == true)

        val replacement = captured.copy(
            userId = "00000000-0000-4000-8000-000000000002",
            email = "replacement@example.test",
            sessionGeneration = "00000000-0000-4000-8000-000000000020"
        )
        assertNull(authStateAfterUnknownAccountDeletionOutcome(replacement, captured))
    }

    @Test
    fun simulatedRestartRetriesEveryCleanupAndClearsJournalOnlyAfterFullSuccess() = runBlocking {
        val storage = MemoryJournalStorage()
        val firstProcess = CloudAccountDeletionJournal(storage)
        val userId = "00000000-0000-4000-8000-000000000001"
        val session = cloudSession(userId, "00000000-0000-4000-8000-000000000011")
        assertTrue(firstProcess.markPending(session))

        val restartedProcess = CloudAccountDeletionJournal(storage)
        val record = restartedProcess.pending().single()
        val firstAttemptCalls = mutableListOf<String>()
        val firstFailures = recoverPendingCloudAccountDeletion(
            record = record,
            clearRoom = { firstAttemptCalls += "room" },
            clearBaseline = { firstAttemptCalls += "baseline"; true },
            clearTrainingProfile = { firstAttemptCalls += "profile"; true },
            clearSyncStatus = { firstAttemptCalls += "status"; true },
            clearCustomMedia = { firstAttemptCalls += "media"; false },
            clearBackupShares = { firstAttemptCalls += "shares"; true },
            clearRestTimers = { firstAttemptCalls += "timers"; true },
            clearGarminState = { firstAttemptCalls += "garmin"; true },
            clearJournal = restartedProcess::clear
        )

        assertEquals(1, firstFailures)
        assertEquals(
            listOf(
                "room",
                "baseline",
                "profile",
                "status",
                "media",
                "shares",
                "timers",
                "garmin"
            ),
            firstAttemptCalls
        )
        assertEquals(record, CloudAccountDeletionJournal(storage).pending().single())

        val secondRestart = CloudAccountDeletionJournal(storage)
        val secondFailures = recoverPendingCloudAccountDeletion(
            record = secondRestart.pending().single(),
            clearRoom = {},
            clearBaseline = { true },
            clearTrainingProfile = { true },
            clearSyncStatus = { true },
            clearCustomMedia = { true },
            clearBackupShares = { true },
            clearRestTimers = { true },
            clearGarminState = { true },
            clearJournal = secondRestart::clear
        )

        assertEquals(0, secondFailures)
        assertTrue(CloudAccountDeletionJournal(storage).pending().isEmpty())
        assertNull(storage.value)
    }

    private fun cloudSession(
        userId: String,
        sessionGeneration: String
    ): AccountSession.Cloud = AccountSession.Cloud(
        userId = userId,
        email = "synthetic@example.test",
        displayName = "Synthetic",
        accessToken = "synthetic-token",
        refreshToken = "synthetic-refresh",
        sessionGeneration = sessionGeneration
    )

    private class MemoryJournalStorage(
        var value: String? = null,
        private val writesSucceed: Boolean = true,
        private val clearsSucceed: Boolean = true
    ) : CloudAccountDeletionJournalStorage {
        override fun read(): String? = value

        override fun write(value: String): Boolean {
            if (!writesSucceed) return false
            this.value = value
            return true
        }

        override fun clear(): Boolean {
            if (!clearsSucceed) return false
            value = null
            return true
        }
    }
}
