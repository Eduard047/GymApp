package com.example.gymapp.wearsync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PhoneWearQueueTest {
    @Test
    fun mutationFloodCannotCreateAnUnboundedBacklog() {
        val channel = boundedPhoneWearChannel<Int>(PHONE_WEAR_MUTATION_QUEUE_CAPACITY)
        val accepted = (0 until 10_000).count { channel.trySend(it).isSuccess }

        assertEquals(PHONE_WEAR_MUTATION_QUEUE_CAPACITY, accepted)
        channel.close()
    }

    @Test
    fun ordinaryFailureDoesNotTerminateTheNextConsumerItem() = runBlocking {
        var processed = 0
        runPhoneWearConsumerItem { throw IllegalStateException("offline") }
        runPhoneWearConsumerItem { processed += 1 }

        assertEquals(1, processed)
    }

    @Test
    fun cancellationStillStopsTheConsumer() {
        assertThrows(CancellationException::class.java) {
            runBlocking {
                runPhoneWearConsumerItem { throw CancellationException("stop") }
            }
        }
    }

    @Test
    fun unlinkedWatchIsToldSoWhateverItSendsAndOnlyItsLinkRequestPasses() {
        fun gate(requestFull: Boolean, link: Boolean, unlinked: Boolean, pinned: Boolean) =
            phoneWearInboundGate(requestFull, link, unlinked, pinned)
        // A queued workout or a plain sync request of the unlinked watch: told "unlinked".
        assertEquals(PhoneWearInboundGate.ReplyUnlinked, gate(false, false, true, false))
        assertEquals(PhoneWearInboundGate.ReplyUnlinked, gate(true, false, true, false))
        // Only its explicit link request goes on to authorization.
        assertEquals(PhoneWearInboundGate.Authorize, gate(true, true, true, false))
        // A mutation never establishes the pin, with or without a claimed link flag.
        assertEquals(PhoneWearInboundGate.Drop, gate(false, false, false, false))
        assertEquals(PhoneWearInboundGate.Drop, gate(false, true, false, false))
        assertEquals(PhoneWearInboundGate.ReplyUnlinked, gate(false, true, true, false))
        // The pinned watch and a first sync request are authorized as before.
        assertEquals(PhoneWearInboundGate.Authorize, gate(false, false, false, true))
        assertEquals(PhoneWearInboundGate.Authorize, gate(true, false, false, false))
    }

    @Test
    fun capabilityEventTargetsOnlyThePinnedReachableWatch() {
        val capability = PhoneWearPaths.WATCH_CAPABILITY
        assertEquals("watch-1", phoneWearReconnectTarget(capability, setOf("watch-1", "watch-2"), "watch-1"))
        assertEquals(null, phoneWearReconnectTarget(capability, setOf("watch-2"), "watch-1"))
        assertEquals(null, phoneWearReconnectTarget(capability, emptySet(), "watch-1"))
        assertEquals(null, phoneWearReconnectTarget(capability, setOf("watch-1"), null))
        assertEquals(null, phoneWearReconnectTarget("another_capability", setOf("watch-1"), "watch-1"))
    }
}
