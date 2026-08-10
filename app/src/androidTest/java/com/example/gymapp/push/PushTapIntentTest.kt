package com.example.gymapp.push

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PushTapIntentTest {
    private val payload = PushPayload.Live(
        bindingId = "123e4567-e89b-42d3-a456-426614174000",
        kind = LivePushKind.Invite,
        roomId = "lr_${"a".repeat(32)}",
        objectRevision = 4
    )

    @Test
    fun explicitTapAcceptsOnlyTheDerivedActionAndExactPayload() {
        val valid = Intent().apply {
            action = pushTapAction(payload)
            putPushPayloadExtras(this, payload)
        }

        assertEquals(payload, parseNotificationTapIntent(valid))
        valid.putExtra("untrusted_route", "https://example.test")
        assertNull(parseNotificationTapIntent(valid))
    }

    @Test
    fun forgedActionOrNonStringExtraFailsClosed() {
        val forgedAction = Intent().apply {
            action = "com.setforge.gymapp.action.PUSH_TAP.profile"
            putPushPayloadExtras(this, payload)
        }
        val wrongType = Intent().apply {
            action = pushTapAction(payload)
            putPushPayloadExtras(this, payload)
            putExtra("com.setforge.gymapp.push.roomRevision", 4)
        }

        assertNull(parseNotificationTapIntent(forgedAction))
        assertTrue(runCatching { parseNotificationTapIntent(wrongType) }.getOrNull() == null)
    }
}
