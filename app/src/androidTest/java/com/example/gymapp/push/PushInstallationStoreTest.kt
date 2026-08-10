package com.example.gymapp.push

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.gymapp.auth.AccountSession
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PushInstallationStoreTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val preferences = context.getSharedPreferences(
        PushInstallationStore.PREFERENCES_NAME,
        Context.MODE_PRIVATE
    )

    @After
    fun cleanUp() {
        preferences.edit().clear().commit()
    }

    @Test
    fun installationIdentityIsStableAndBindingClearsWithoutChangingIt() {
        val store = PushInstallationStore(context)
        val installationId = store.installationId()
        val binding = PushInstallationBinding(
            installationId = installationId,
            userId = "123e4567-e89b-42d3-a456-426614174000",
            sessionGeneration = "223e4567-e89b-42d3-a456-426614174000",
            bindingId = "323e4567-e89b-42d3-a456-426614174000",
            registrationRevision = 2,
            providerTokenDigest = "a".repeat(64),
            registeredAtMillis = 1_754_822_400_000L
        )

        assertTrue(isCanonicalV4Uuid(installationId))
        assertEquals(installationId, store.installationId())
        assertTrue(store.saveBinding(binding))
        assertEquals(binding, store.binding())
        assertTrue(store.clearBinding())
        assertNull(store.binding())
        assertEquals(installationId, store.installationId())
    }

    @Test
    fun malformedRestoredIdentityAndBindingNeverBecomeAuthoritative() {
        preferences.edit()
            .putString("installation_id", "restored-device")
            .putString("user_id", "forged-owner")
            .putString("binding_id", "forged-binding")
            .putInt("registration_revision", 1)
            .commit()

        val store = PushInstallationStore(context)
        assertNull(store.existingInstallationIdOrNull())
        assertNull(store.binding())
        val replacement = store.installationId()

        assertTrue(isCanonicalV4Uuid(replacement))
        assertFalse(preferences.contains("user_id"))
        assertFalse(preferences.contains("binding_id"))
    }

    @Test
    fun pendingRevocationSurvivesBindingClearUntilServerConfirmation() {
        val store = PushInstallationStore(context)
        val installationId = store.installationId()
        val pending = PushPendingRevocation(
            installationId = installationId,
            userId = "123e4567-e89b-42d3-a456-426614174000",
            sessionGeneration = "223e4567-e89b-42d3-a456-426614174000",
            deleteProviderToken = true
        )

        assertTrue(store.savePendingRevocation(pending))
        assertTrue(store.clearBinding())
        assertEquals(pending, store.pendingRevocation())
        assertTrue(store.clearPendingRevocation(installationId))
        assertNull(store.pendingRevocation())
    }

    @Test
    fun atomicAccountRebindClearsOnlyTheExactCapturedOldOwnerMarker() {
        val store = PushInstallationStore(context)
        val installationId = store.installationId()
        val oldPending = PushPendingRevocation(
            installationId = installationId,
            userId = "123e4567-e89b-42d3-a456-426614174000",
            sessionGeneration = "223e4567-e89b-42d3-a456-426614174000",
            deleteProviderToken = false
        )
        val replacement = PushInstallationBinding(
            installationId = installationId,
            userId = "323e4567-e89b-42d3-a456-426614174000",
            sessionGeneration = "423e4567-e89b-42d3-a456-426614174000",
            bindingId = "523e4567-e89b-42d3-a456-426614174000",
            registrationRevision = 7,
            providerTokenDigest = "b".repeat(64),
            registeredAtMillis = 1_754_822_400_000L
        )
        assertTrue(store.savePendingRevocation(oldPending))
        assertTrue(store.saveBinding(replacement))

        val changedMarker = oldPending.copy(deleteProviderToken = true)
        assertTrue(store.savePendingRevocation(changedMarker))
        assertFalse(
            store.clearPendingRevocationSupersededBy(
                replacement,
                expectedPending = oldPending
            )
        )
        assertEquals(changedMarker, store.pendingRevocation())
        assertTrue(
            store.clearPendingRevocationSupersededBy(
                replacement,
                expectedPending = changedMarker
            )
        )
        assertNull(store.pendingRevocation())
    }

    @Test
    fun displayHighWaterRejectsDuplicateAndOutOfOrderRevisions() {
        val store = PushInstallationStore(context)
        val installationId = store.installationId()
        val session = AccountSession.Cloud(
            userId = "123e4567-e89b-42d3-a456-426614174000",
            email = "athlete@example.test",
            displayName = "Athlete",
            accessToken = "access-token",
            refreshToken = "refresh-token",
            sessionGeneration = "223e4567-e89b-42d3-a456-426614174000"
        )
        val bindingId = "323e4567-e89b-42d3-a456-426614174000"
        assertTrue(
            store.saveBinding(
                PushInstallationBinding(
                    installationId = installationId,
                    userId = session.userId,
                    sessionGeneration = session.sessionGeneration,
                    bindingId = bindingId,
                    registrationRevision = 1,
                    providerTokenDigest = "a".repeat(64),
                    registeredAtMillis = 1_754_822_400_000L
                )
            )
        )
        fun payload(revision: Int) = PushPayload.Live(
            bindingId = bindingId,
            kind = LivePushKind.Started,
            roomId = "lr_${"b".repeat(32)}",
            objectRevision = revision
        )

        assertTrue(store.canDisplay(payload(7), session, installationId))
        assertTrue(store.commitDisplayed(payload(7), session, installationId))
        assertFalse(store.canDisplay(payload(7), session, installationId))
        assertFalse(store.canDisplay(payload(6), session, installationId))
        assertTrue(store.canDisplay(payload(8), session, installationId))
        assertTrue(store.commitDisplayed(payload(8), session, installationId))
        assertFalse(store.isCurrentDisplayedPayload(payload(7), session, installationId))
        assertTrue(store.isCurrentDisplayedPayload(payload(8), session, installationId))
        assertTrue(store.clearBinding())
        assertFalse(store.isCurrentDisplayedPayload(payload(8), session, installationId))
    }

    @Test
    fun transientUnbindPreservesReplayFenceOnlyForTheSameReplacementBinding() {
        val store = PushInstallationStore(context)
        val installationId = store.installationId()
        val session = AccountSession.Cloud(
            userId = "123e4567-e89b-42d3-a456-426614174000",
            email = "athlete@example.test",
            displayName = "Athlete",
            accessToken = "access-token",
            refreshToken = "refresh-token",
            sessionGeneration = "223e4567-e89b-42d3-a456-426614174000"
        )
        val binding = PushInstallationBinding(
            installationId = installationId,
            userId = session.userId,
            sessionGeneration = session.sessionGeneration,
            bindingId = "323e4567-e89b-42d3-a456-426614174000",
            registrationRevision = 2,
            providerTokenDigest = "a".repeat(64),
            registeredAtMillis = 1_754_822_400_000L
        )
        val payload = PushPayload.Live(
            bindingId = binding.bindingId,
            kind = LivePushKind.Started,
            roomId = "lr_${"c".repeat(32)}",
            objectRevision = 9
        )
        assertTrue(store.saveBinding(binding))
        assertTrue(store.commitDisplayed(payload, session, installationId))

        assertTrue(store.clearBinding(preserveDeliveryState = true))
        assertTrue(store.saveBinding(binding.copy(registrationRevision = 3)))
        assertFalse(store.canDisplay(payload, session, installationId))

        val rotated = binding.copy(
            bindingId = "423e4567-e89b-42d3-a456-426614174000",
            registrationRevision = 4
        )
        assertTrue(store.clearBinding(preserveDeliveryState = true))
        assertTrue(store.saveBinding(rotated))
        assertFalse(store.isCurrentDisplayedPayload(payload, session, installationId))
    }

    @Test
    fun malformedReplayHistoryRejectsTheCurrentDeliveryAndRepairsClosed() {
        val store = PushInstallationStore(context)
        val installationId = store.installationId()
        val session = AccountSession.Cloud(
            userId = "123e4567-e89b-42d3-a456-426614174000",
            email = "athlete@example.test",
            displayName = "Athlete",
            accessToken = "access-token",
            refreshToken = "refresh-token",
            sessionGeneration = "223e4567-e89b-42d3-a456-426614174000"
        )
        val bindingId = "323e4567-e89b-42d3-a456-426614174000"
        assertTrue(
            store.saveBinding(
                PushInstallationBinding(
                    installationId = installationId,
                    userId = session.userId,
                    sessionGeneration = session.sessionGeneration,
                    bindingId = bindingId,
                    registrationRevision = 2,
                    providerTokenDigest = "c".repeat(64),
                    registeredAtMillis = 1_754_822_400_000L
                )
            )
        )
        preferences.edit()
            .putString("display_user_id", session.userId)
            .putString("display_session_generation", session.sessionGeneration)
            .putString("display_installation_id", installationId)
            .putString("display_binding_id", bindingId)
            .putString("display_high_water", "not-json")
            .commit()
        val payload = PushPayload.Live(
            bindingId = bindingId,
            kind = LivePushKind.Invite,
            roomId = "lr_${"d".repeat(32)}",
            objectRevision = 1
        )

        assertFalse(store.canDisplay(payload, session, installationId))
        assertFalse(preferences.contains("display_high_water"))
    }
}
