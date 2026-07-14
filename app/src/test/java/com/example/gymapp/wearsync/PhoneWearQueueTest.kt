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
}
