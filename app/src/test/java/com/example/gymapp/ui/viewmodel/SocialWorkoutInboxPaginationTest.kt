package com.example.gymapp.ui.viewmodel

import com.example.gymapp.auth.SocialIncomingWorkoutInvite
import com.example.gymapp.auth.SocialOutgoingWorkoutInvite
import com.example.gymapp.auth.SocialWorkoutInbox
import com.example.gymapp.auth.SocialWorkoutInboxCursor
import com.example.gymapp.auth.SocialWorkoutInviteSummary
import com.example.gymapp.auth.hasAnotherBoundedPage
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SocialWorkoutInboxPaginationTest {
    @Test
    fun metadataPagesAppendInStableOrderAndContinueWhileTheCursorMakesProgress() {
        val first = SocialWorkoutInbox(
            pendingIncomingCount = 2,
            incoming = listOf(invite(2)),
            outgoing = emptyList(),
            nextCursor = cursor(2)
        )
        val next = SocialWorkoutInbox(
            pendingIncomingCount = 2,
            incoming = listOf(invite(1)),
            outgoing = emptyList(),
            nextCursor = cursor(1)
        )

        assertTrue(first.hasAnotherBoundedPage())
        val merged = mergeSocialWorkoutInboxPage(first, next)

        assertEquals(listOf(inviteId(2), inviteId(1)), merged.incoming.map { it.inviteId })
        assertEquals(2, merged.pendingIncomingCount)
        assertEquals(2, merged.loadedPageCount)
        assertEquals(cursor(1), merged.nextCursor)
        assertTrue(merged.hasAnotherBoundedPage())
    }

    @Test
    fun twoTenItemPagesNeverExposeMoreThanTwentyItems() {
        val first = SocialWorkoutInbox(
            pendingIncomingCount = 20,
            incoming = (20 downTo 11).map(::invite),
            outgoing = emptyList(),
            nextCursor = cursor(11)
        )
        val next = SocialWorkoutInbox(
            pendingIncomingCount = 20,
            incoming = (10 downTo 1).map(::invite),
            outgoing = emptyList(),
            nextCursor = cursor(1)
        )

        val merged = mergeSocialWorkoutInboxPage(first, next)

        assertEquals(20, merged.incoming.size)
        assertEquals((20 downTo 1).map(::inviteId), merged.incoming.map { it.inviteId })
        assertEquals(null, merged.nextCursor)
        assertFalse(merged.hasAnotherBoundedPage())
    }

    @Test
    fun shortBudgetedPagesCanContinuePastPageTwoButStillStopAtTwentyItems() {
        val outgoing = listOf(outgoing(100))
        val first = SocialWorkoutInbox(
            pendingIncomingCount = 20,
            incoming = (20 downTo 15).map(::invite),
            outgoing = outgoing,
            nextCursor = cursor(15)
        )
        val second = SocialWorkoutInbox(
            pendingIncomingCount = 20,
            incoming = (14 downTo 8).map(::invite),
            outgoing = outgoing,
            nextCursor = cursor(8)
        )
        val third = SocialWorkoutInbox(
            pendingIncomingCount = 20,
            incoming = (7 downTo 1).map(::invite),
            outgoing = outgoing,
            nextCursor = cursor(1)
        )

        val afterSecond = mergeSocialWorkoutInboxPage(first, second)
        assertEquals(13, afterSecond.incoming.size)
        assertEquals(2, afterSecond.loadedPageCount)
        assertEquals(cursor(8), afterSecond.nextCursor)
        assertTrue(afterSecond.hasAnotherBoundedPage())

        val bounded = mergeSocialWorkoutInboxPage(afterSecond, third)
        assertEquals(20, bounded.incoming.size)
        assertEquals(3, bounded.loadedPageCount)
        assertEquals(outgoing, bounded.outgoing)
        assertNull(bounded.nextCursor)
        assertFalse(bounded.hasAnotherBoundedPage())
    }

    @Test
    fun oneLoadMoreActionLoopsAcrossShortPagesButAddsAtMostTenRows() = runBlocking {
        val outgoing = listOf(outgoing(100))
        val first = SocialWorkoutInbox(
            pendingIncomingCount = 20,
            incoming = (20 downTo 15).map(::invite),
            outgoing = outgoing,
            nextCursor = cursor(15)
        )
        val second = SocialWorkoutInbox(
            pendingIncomingCount = 20,
            incoming = (14 downTo 8).map(::invite),
            outgoing = outgoing,
            nextCursor = cursor(8)
        )
        val third = SocialWorkoutInbox(
            pendingIncomingCount = 20,
            incoming = (7 downTo 5).map(::invite),
            outgoing = outgoing,
            nextCursor = cursor(5)
        )
        val calls = mutableListOf<Pair<SocialWorkoutInboxCursor?, Int>>()

        val loaded = loadNextSocialWorkoutInboxPage(
            current = first,
            isRequestCurrent = { true },
            loadPage = { requestedCursor, requestedLimit ->
                calls += requestedCursor to requestedLimit
                if (requestedCursor == cursor(15)) second else third
            }
        )

        assertEquals(listOf(cursor(15) to 10, cursor(8) to 3), calls)
        val inbox = checkNotNull(loaded).inbox
        assertEquals(16, inbox.incoming.size)
        assertEquals(3, inbox.loadedPageCount)
        assertEquals(cursor(5), inbox.nextCursor)
        assertEquals(outgoing, inbox.outgoing)
        assertTrue(inbox.hasAnotherBoundedPage())
    }

    @Test
    fun overlappingOrOutOfOrderCursorPagesFailClosed() {
        val first = SocialWorkoutInbox(
            pendingIncomingCount = 2,
            incoming = listOf(invite(2)),
            outgoing = emptyList(),
            nextCursor = cursor(2)
        )

        assertThrows(IllegalArgumentException::class.java) {
            mergeSocialWorkoutInboxPage(
                first,
                first.copy(nextCursor = null)
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            mergeSocialWorkoutInboxPage(
                first,
                SocialWorkoutInbox(
                    pendingIncomingCount = 2,
                    incoming = listOf(invite(3)),
                    outgoing = emptyList()
                )
            )
        }
    }

    @Test
    fun countOutgoingAndCrossListDriftFailClosed() {
        val outgoing = listOf(outgoing(1))
        val first = SocialWorkoutInbox(
            pendingIncomingCount = 2,
            incoming = listOf(invite(3)),
            outgoing = outgoing,
            nextCursor = cursor(3)
        )
        val validNext = SocialWorkoutInbox(
            pendingIncomingCount = 2,
            incoming = listOf(invite(2)),
            outgoing = outgoing
        )

        assertThrows(IllegalArgumentException::class.java) {
            mergeSocialWorkoutInboxPage(first, validNext.copy(pendingIncomingCount = 3))
        }
        assertThrows(IllegalArgumentException::class.java) {
            mergeSocialWorkoutInboxPage(first, validNext.copy(outgoing = emptyList()))
        }
        assertThrows(IllegalArgumentException::class.java) {
            mergeSocialWorkoutInboxPage(first, validNext.copy(incoming = listOf(invite(1))))
        }
    }

    @Test
    fun changedPendingSnapshotReloadsOneFullFirstPageWithoutMixingRows() = runBlocking {
        val first = SocialWorkoutInbox(
            pendingIncomingCount = 2,
            incoming = listOf(invite(3)),
            outgoing = emptyList(),
            nextCursor = cursor(3)
        )
        val changedCursorPage = SocialWorkoutInbox(
            pendingIncomingCount = 3,
            incoming = listOf(invite(2)),
            outgoing = emptyList()
        )
        val refreshedFirstPage = SocialWorkoutInbox(
            pendingIncomingCount = 3,
            incoming = listOf(invite(4), invite(3)),
            outgoing = emptyList(),
            nextCursor = cursor(3)
        )
        val calls = mutableListOf<Pair<SocialWorkoutInboxCursor?, Int>>()

        val loaded = loadNextSocialWorkoutInboxPage(
            current = first,
            isRequestCurrent = { true },
            loadPage = { requestedCursor, requestedLimit ->
                calls += requestedCursor to requestedLimit
                if (requestedCursor == null) refreshedFirstPage else changedCursorPage
            }
        )

        assertEquals(listOf(cursor(3) to 10, null to 10), calls)
        assertTrue(checkNotNull(loaded).replacedChangedSnapshot)
        assertEquals(refreshedFirstPage, loaded.inbox)
        assertFalse(loaded.inbox.incoming.any { it.inviteId == inviteId(2) })
        assertEquals(1, loaded.inbox.loadedPageCount)
    }

    @Test
    fun changedOutgoingSnapshotAlsoReloadsFirstPageAndHonorsLateFence() = runBlocking {
        val initialOutgoing = listOf(outgoing(1))
        val changedOutgoing = listOf(outgoing(2))
        val first = SocialWorkoutInbox(
            pendingIncomingCount = 2,
            incoming = listOf(invite(4)),
            outgoing = initialOutgoing,
            nextCursor = cursor(4)
        )
        val changedCursorPage = SocialWorkoutInbox(
            pendingIncomingCount = 2,
            incoming = listOf(invite(3)),
            outgoing = changedOutgoing
        )
        val refreshedFirstPage = SocialWorkoutInbox(
            pendingIncomingCount = 2,
            incoming = listOf(invite(5)),
            outgoing = changedOutgoing,
            nextCursor = cursor(5)
        )
        var fenceChecks = 0
        val calls = mutableListOf<SocialWorkoutInboxCursor?>()

        val loaded = loadNextSocialWorkoutInboxPage(
            current = first,
            isRequestCurrent = {
                fenceChecks += 1
                fenceChecks < 3
            },
            loadPage = { requestedCursor, _ ->
                calls += requestedCursor
                if (requestedCursor == null) refreshedFirstPage else changedCursorPage
            }
        )

        assertEquals(listOf(cursor(4), null), calls)
        assertNull(loaded)
    }

    private fun invite(index: Int) = SocialIncomingWorkoutInvite(
        inviteId = inviteId(index),
        profileId = profileId(index),
        displayName = "Peer $index",
        status = "pending",
        inviteRevision = 1,
        createdAt = "2026-08-13T10:00:00Z",
        expiresAt = "2026-08-20T10:00:00Z",
        respondedAt = null,
        summary = summary
    )

    private fun outgoing(index: Int) = SocialOutgoingWorkoutInvite(
        inviteId = inviteId(index),
        profileId = profileId(index),
        displayName = "Peer $index",
        status = "pending",
        inviteRevision = 1,
        createdAt = "2026-08-13T10:00:00Z",
        expiresAt = "2026-08-20T10:00:00Z",
        respondedAt = null,
        summary = summary
    )

    private fun cursor(index: Int) = SocialWorkoutInboxCursor(
        createdAt = "2026-08-13T10:00:00Z",
        inviteId = inviteId(index),
        pending = true
    )

    private fun inviteId(index: Int) = "wi_${index.toString(16).padStart(32, '0')}"
    private fun profileId(index: Int) = "p_${index.toString(16).padStart(32, '0')}"

    private companion object {
        val summary = SocialWorkoutInviteSummary(1, 1, listOf("Bench Press"))
    }
}
