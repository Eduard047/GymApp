package com.example.gymapp.push

import com.example.gymapp.auth.AccountSession
import java.util.Collections
import java.util.concurrent.CountDownLatch
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class PushContractTest {
    private val bindingId = "123e4567-e89b-42d3-a456-426614174000"
    private val installationId = "223e4567-e89b-42d3-a456-426614174000"
    private val userId = "323e4567-e89b-42d3-a456-426614174000"
    private val generation = "423e4567-e89b-42d3-a456-426614174000"
    private val providerToken = "token:${"a".repeat(40)}"

    @Test
    fun `data-only social payload is exact and routes only to social profile`() {
        val payload = parsePushPayload(
            data = mapOf(
                "version" to "1",
                "bindingId" to bindingId,
                "type" to "friend_request_received",
                "objectId" to "f_${"a".repeat(32)}",
                "objectRevision" to "0"
            ),
            hasNotificationPayload = false
        )

        assertTrue(payload is PushPayload.Social)
        assertEquals(
            PushNavigationTarget.Social(
                SocialPushType.FriendRequestReceived,
                "f_${"a".repeat(32)}",
                0
            ),
            payload?.navigationTarget()
        )
    }

    @Test
    fun `live payload accepts only allowlisted room route and canonical revision`() {
        val payload = parsePushPayload(
            data = livePayload(),
            hasNotificationPayload = false
        )

        assertEquals(
            PushNavigationTarget.Live(
                LivePushKind.Invite,
                "lr_${"b".repeat(32)}",
                7
            ),
            payload?.navigationTarget()
        )
        assertNull(parsePushPayload(livePayload("roomRevision" to "01"), false))
        assertNull(parsePushPayload(livePayload("roomRevision" to "2147483648"), false))
        assertNull(parsePushPayload(livePayload("roomId" to "https://example.test"), false))
    }

    @Test
    fun `notification payload extra fields and malformed binding fail closed`() {
        val valid = livePayload()

        assertNull(parsePushPayload(valid, hasNotificationPayload = true))
        assertNull(parsePushPayload(valid + ("title" to "Forged"), false))
        assertNull(
            parsePushPayload(
                livePayload("bindingId" to bindingId.uppercase()),
                false
            )
        )
        assertNull(parsePushPayload(livePayload("kind" to "open_url"), false))
        assertNull(parsePushPayload(emptyMap(), false))
    }

    @Test
    fun `friend and workout event types require their own object IDs`() {
        val friend = socialPayload(
            type = "friend_request_accepted",
            objectId = "f_${"c".repeat(32)}"
        )
        val workout = socialPayload(
            type = "workout_invite_received",
            objectId = "wi_${"d".repeat(32)}"
        )

        assertTrue(parsePushPayload(friend, false) is PushPayload.Social)
        assertTrue(parsePushPayload(workout, false) is PushPayload.Social)
        assertNull(
            parsePushPayload(
                socialPayload("friend_request_accepted", "wi_${"d".repeat(32)}"),
                false
            )
        )
        assertNull(
            parsePushPayload(
                socialPayload("workout_invite_received", "f_${"c".repeat(32)}"),
                false
            )
        )
    }

    @Test
    fun `registration marker commits only to the same account generation token and epoch`() {
        val attempt = PushRegistrationAttempt(
            installationId = installationId,
            userId = userId,
            sessionGeneration = generation,
            providerToken = providerToken,
            epoch = 9
        )
        val session = cloudSession(userId, generation)

        assertTrue(
            canCommitPushRegistration(
                attempt,
                session,
                installationId,
                providerToken,
                currentEpoch = 9,
                enabled = true
            )
        )
        assertFalse(
            canCommitPushRegistration(
                attempt,
                cloudSession("523e4567-e89b-42d3-a456-426614174000", generation),
                installationId,
                providerToken,
                9,
                true
            )
        )
        assertFalse(
            canCommitPushRegistration(
                attempt,
                cloudSession(userId, "623e4567-e89b-42d3-a456-426614174000"),
                installationId,
                providerToken,
                9,
                true
            )
        )
        assertFalse(
            canCommitPushRegistration(
                attempt,
                session,
                "723e4567-e89b-42d3-a456-426614174000",
                providerToken,
                9,
                true
            )
        )
        assertFalse(
            canCommitPushRegistration(
                attempt,
                session,
                installationId,
                "replacement:${"z".repeat(40)}",
                9,
                true
            )
        )
        assertFalse(
            canCommitPushRegistration(
                attempt,
                session,
                installationId,
                providerToken,
                10,
                true
            )
        )
        assertFalse(
            canCommitPushRegistration(
                attempt,
                session,
                installationId,
                providerToken,
                9,
                false
            )
        )
    }

    @Test
    fun `atomic rebind clears only the exact captured pending owner marker`() {
        val oldPending = PushPendingRevocation(
            installationId = installationId,
            userId = userId,
            sessionGeneration = generation,
            deleteProviderToken = false
        )
        val replacement = PushInstallationBinding(
            installationId = installationId,
            userId = "523e4567-e89b-42d3-a456-426614174000",
            sessionGeneration = "623e4567-e89b-42d3-a456-426614174000",
            bindingId = bindingId,
            registrationRevision = 4,
            providerTokenDigest = providerTokenDigest(providerToken),
            registeredAtMillis = 1
        )

        assertTrue(
            canClearSupersededPendingRevocation(
                persistedReplacement = replacement,
                expectedReplacement = replacement,
                currentPending = oldPending,
                expectedPending = oldPending
            )
        )
        assertFalse(
            canClearSupersededPendingRevocation(
                persistedReplacement = replacement,
                expectedReplacement = replacement,
                currentPending = oldPending.copy(deleteProviderToken = true),
                expectedPending = oldPending
            )
        )
        assertFalse(
            canClearSupersededPendingRevocation(
                persistedReplacement = replacement.copy(bindingId = installationId),
                expectedReplacement = replacement,
                currentPending = oldPending,
                expectedPending = oldPending
            )
        )
    }

    @Test
    fun `logout revocation waits for an in-flight registration and runs last`() = runBlocking {
        val gate = PushRpcSerialGate()
        val registrationEntered = CompletableDeferred<Unit>()
        val releaseRegistration = CompletableDeferred<Unit>()
        val revokeQueued = CompletableDeferred<Unit>()
        val operations = Collections.synchronizedList(mutableListOf<String>())

        val registration = async(Dispatchers.Default) {
            gate.runExclusive {
                operations += "register-start"
                registrationEntered.complete(Unit)
                releaseRegistration.await()
                operations += "register-finish"
            }
        }
        registrationEntered.await()
        val revocation = async(Dispatchers.Default) {
            revokeQueued.complete(Unit)
            gate.runExclusive { operations += "revoke" }
        }
        revokeQueued.await()
        releaseRegistration.complete(Unit)
        awaitAll(registration, revocation)

        assertEquals(listOf("register-start", "register-finish", "revoke"), operations)
    }

    @Test
    fun `notification cancellation is ordered after an in-flight display`() {
        val gate = PushNotificationStateGate()
        val displayEntered = CountDownLatch(1)
        val releaseDisplay = CountDownLatch(1)
        val operations = Collections.synchronizedList(mutableListOf<String>())
        val display = Thread {
            gate.runExclusive {
                operations += "display-check"
                displayEntered.countDown()
                releaseDisplay.await()
                operations += "notify"
            }
        }
        val cancellation = Thread {
            displayEntered.await()
            gate.runExclusive { operations += "cancel" }
        }

        display.start()
        cancellation.start()
        displayEntered.await()
        releaseDisplay.countDown()
        display.join()
        cancellation.join()

        assertEquals(listOf("display-check", "notify", "cancel"), operations)
    }

    @Test
    fun `queued navigation is rejected by a replacement account generation`() {
        val navigation = AccountBoundPushNavigation(
            payload = PushPayload.Live(
                bindingId = bindingId,
                kind = LivePushKind.Invite,
                roomId = "lr_${"a".repeat(32)}",
                objectRevision = 2
            ),
            userId = userId,
            sessionGeneration = generation,
            installationId = installationId
        )

        assertTrue(navigation.matchesSession(cloudSession(userId, generation)))
        assertFalse(
            navigation.matchesSession(
                cloudSession("523e4567-e89b-42d3-a456-426614174000", generation)
            )
        )
        assertFalse(
            navigation.matchesSession(
                cloudSession(userId, "623e4567-e89b-42d3-a456-426614174000")
            )
        )
    }

    @Test
    fun `stored binding requires account generation installation and server binding`() {
        val session = cloudSession(userId, generation)
        val binding = PushInstallationBinding(
            installationId = installationId,
            userId = userId,
            sessionGeneration = generation,
            bindingId = bindingId,
            registrationRevision = 3,
            providerTokenDigest = providerTokenDigest(providerToken),
            registeredAtMillis = 1
        )

        assertTrue(binding.matches(session, installationId, bindingId))
        assertFalse(binding.matches(session, installationId, installationId))
        assertFalse(
            binding.matches(
                cloudSession(userId, "723e4567-e89b-42d3-a456-426614174000"),
                installationId,
                bindingId
            )
        )
        assertNotEquals(providerToken, binding.providerTokenDigest)
        assertEquals(64, binding.providerTokenDigest.length)
    }

    @Test
    fun `cold process restores delivery only for an exact durable active binding`() {
        val session = cloudSession(userId, generation)
        val binding = PushInstallationBinding(
            installationId = installationId,
            userId = userId,
            sessionGeneration = generation,
            bindingId = bindingId,
            registrationRevision = 3,
            providerTokenDigest = providerTokenDigest(providerToken),
            registeredAtMillis = 1
        )
        fun canRestore(
            activeSession: AccountSession? = session,
            pending: PushPendingRevocation? = null
        ) = canRestorePushDeliveryArm(
            session = activeSession,
            binding = binding,
            installationId = installationId,
            pendingRevocation = pending,
            configured = true,
            enabled = true,
            permissionGranted = true,
            channelEnabled = true
        )

        assertTrue(canRestore())
        assertFalse(
            canRestore(
                activeSession = cloudSession(
                    "523e4567-e89b-42d3-a456-426614174000",
                    generation
                )
            )
        )
        assertFalse(
            canRestore(
                pending = PushPendingRevocation(
                    installationId = installationId,
                    userId = userId,
                    sessionGeneration = generation,
                    deleteProviderToken = false
                )
            )
        )
    }

    @Test
    fun `durable revoke keeps the persisted binding owner across process and account changes`() {
        val binding = PushInstallationBinding(
            installationId = installationId,
            userId = userId,
            sessionGeneration = generation,
            bindingId = bindingId,
            registrationRevision = 3,
            providerTokenDigest = providerTokenDigest(providerToken),
            registeredAtMillis = 1
        )
        val replacementSession = cloudSession(
            "523e4567-e89b-42d3-a456-426614174000",
            "623e4567-e89b-42d3-a456-426614174000"
        )
        val fromBinding = resolvePushPendingRevocation(
            installationId = installationId,
            existing = null,
            persistedBinding = binding,
            session = replacementSession,
            deleteProviderToken = true
        )

        assertEquals(userId, fromBinding?.userId)
        assertEquals(generation, fromBinding?.sessionGeneration)
        assertTrue(fromBinding?.deleteProviderToken == true)
        assertEquals(
            fromBinding,
            resolvePushPendingRevocation(
                installationId = installationId,
                existing = fromBinding,
                persistedBinding = null,
                session = replacementSession,
                deleteProviderToken = false
            )
        )
        assertNull(
            resolvePushPendingRevocation(
                installationId = installationId,
                existing = null,
                persistedBinding = null,
                session = null,
                deleteProviderToken = true
            )
        )
    }

    @Test
    fun `revocation binding clear policy requires a durable marker`() {
        val marker = PushPendingRevocation(
            installationId = installationId,
            userId = userId,
            sessionGeneration = generation,
            deleteProviderToken = true
        )

        assertFalse(
            canClearPushBindingAfterRevocationPreparation(
                marker = marker,
                markerSaved = false
            )
        )
        assertTrue(
            canClearPushBindingAfterRevocationPreparation(
                marker = marker,
                markerSaved = true
            )
        )
        assertTrue(
            canClearPushBindingAfterRevocationPreparation(
                marker = null,
                markerSaved = false
            )
        )
    }

    @Test
    fun `revocation marker save failure keeps binding as the next launch retry source`() {
        val binding = PushInstallationBinding(
            installationId = installationId,
            userId = userId,
            sessionGeneration = generation,
            bindingId = bindingId,
            registrationRevision = 3,
            providerTokenDigest = providerTokenDigest(providerToken),
            registeredAtMillis = 1
        )
        val marker = PushPendingRevocation(
            installationId = installationId,
            userId = userId,
            sessionGeneration = generation,
            deleteProviderToken = true
        )

        assertFalse(
            canClearPushBindingAfterRevocationPreparation(
                marker = marker,
                markerSaved = false
            )
        )
        assertEquals(
            marker,
            resolvePushPendingRevocation(
                installationId = installationId,
                existing = null,
                persistedBinding = binding,
                session = null,
                deleteProviderToken = true
            )
        )
    }

    @Test
    fun `cross-account registration requires durable cleanup for the previous owner`() {
        val previousBinding = PushInstallationBinding(
            installationId = installationId,
            userId = userId,
            sessionGeneration = generation,
            bindingId = bindingId,
            registrationRevision = 3,
            providerTokenDigest = providerTokenDigest(providerToken),
            registeredAtMillis = 1
        )
        val replacementSession = cloudSession(
            "523e4567-e89b-42d3-a456-426614174000",
            "623e4567-e89b-42d3-a456-426614174000"
        )
        val previousOwnerCleanup = PushPendingRevocation(
            installationId = installationId,
            userId = userId,
            sessionGeneration = generation,
            deleteProviderToken = false
        )

        assertFalse(
            canBeginPushRegistration(
                session = replacementSession,
                binding = previousBinding,
                pendingRevocation = null,
                pendingMarkerSaved = false
            )
        )
        assertFalse(
            canBeginPushRegistration(
                session = replacementSession,
                binding = previousBinding,
                pendingRevocation = previousOwnerCleanup,
                pendingMarkerSaved = false
            )
        )
        assertTrue(
            canBeginPushRegistration(
                session = replacementSession,
                binding = previousBinding,
                pendingRevocation = previousOwnerCleanup,
                pendingMarkerSaved = true
            )
        )

        val mismatchedCleanup = previousOwnerCleanup.copy(
            userId = "723e4567-e89b-42d3-a456-426614174000"
        )
        assertFalse(
            canBeginPushRegistration(
                session = replacementSession,
                binding = previousBinding,
                pendingRevocation = mismatchedCleanup,
                pendingMarkerSaved = true
            )
        )
    }

    @Test
    fun `same-owner registration is not blocked by cleanup admission gate`() {
        val currentSession = cloudSession(userId, generation)
        val currentBinding = PushInstallationBinding(
            installationId = installationId,
            userId = userId,
            sessionGeneration = generation,
            bindingId = bindingId,
            registrationRevision = 3,
            providerTokenDigest = providerTokenDigest(providerToken),
            registeredAtMillis = 1
        )

        assertTrue(
            canBeginPushRegistration(
                session = currentSession,
                binding = currentBinding,
                pendingRevocation = null,
                pendingMarkerSaved = false
            )
        )
    }

    @Test
    fun `newer object revisions replace the same visible notification`() {
        val first = PushPayload.Live(
            bindingId = bindingId,
            kind = LivePushKind.Invite,
            roomId = "lr_${"a".repeat(32)}",
            objectRevision = 3
        )
        val newer = first.copy(kind = LivePushKind.Started, objectRevision = 4)
        val anotherRoom = first.copy(roomId = "lr_${"b".repeat(32)}")

        assertEquals(pushNotificationTag(first), pushNotificationTag(newer))
        assertNotEquals(pushNotificationTag(first), pushNotificationTag(anotherRoom))
    }

    @Test
    fun `registration request and responses match exact RPC contract`() {
        val request = JSONObject(
            pushRegistrationRequestJson(
                installationId,
                providerToken,
                "uk-UA",
                "2026.08.10"
            )
        )
        assertEquals(
            setOf(
                "p_installation_id",
                "p_platform",
                "p_provider",
                "p_environment",
                "p_provider_token",
                "p_web_push_p256dh",
                "p_web_push_auth",
                "p_locale",
                "p_app_version"
            ),
            request.keys().asSequence().toSet()
        )
        assertEquals("android", request.getString("p_platform"))
        assertEquals("fcm", request.getString("p_provider"))
        assertEquals("production", request.getString("p_environment"))
        assertTrue(request.isNull("p_web_push_p256dh"))
        assertTrue(request.isNull("p_web_push_auth"))

        val registration = parsePushRegistrationResponse(
            """{
              "version":1,
              "installationId":"$installationId",
              "provider":"fcm",
              "environment":"production",
              "bindingId":"$bindingId",
              "registrationRevision":4,
              "registeredAt":"2026-08-10T12:00:00Z"
            }""".trimIndent(),
            installationId
        )
        assertEquals(bindingId, registration.bindingId)
        assertEquals(4, registration.registrationRevision)

        val revocation = parsePushRevocationResponse(
            """{"version":1,"installationId":"$installationId","revoked":true}""",
            installationId
        )
        assertTrue(revocation.revoked)
        assertTrue(pushRevocationReachedDesiredState(revocation))
        assertTrue(
            pushRevocationReachedDesiredState(
                parsePushRevocationResponse(
                    """{"version":1,"installationId":"$installationId","revoked":false}""",
                    installationId
                )
            )
        )
        assertFalse(pushRevocationReachedDesiredState(null))
        assertThrows(IllegalArgumentException::class.java) {
            parsePushRegistrationResponse(
                """{
                  "version":1,
                  "installationId":"$installationId",
                  "provider":"fcm",
                  "environment":"production",
                  "bindingId":"$bindingId",
                  "registrationRevision":4,
                  "registeredAt":"2026-08-10T12:00:00Z",
                  "extra":true
                }""".trimIndent(),
                installationId
            )
        }
    }

    @Test
    fun `locale and provider token validation are bounded`() {
        assertEquals("uk-UA", normalizedPushLocale("UK", "ua"))
        assertEquals("ru", normalizedPushLocale("ru", ""))
        assertNull(normalizedPushLocale("english", "US"))
        assertTrue(isValidFcmProviderToken(providerToken))
        assertFalse(isValidFcmProviderToken("short"))
        assertFalse(isValidFcmProviderToken("x".repeat(31) + " "))
    }

    private fun livePayload(vararg replacements: Pair<String, String>): Map<String, String> =
        mutableMapOf(
            "version" to "1",
            "bindingId" to bindingId,
            "kind" to "invite",
            "roomId" to "lr_${"b".repeat(32)}",
            "roomRevision" to "7"
        ).apply { replacements.forEach { (key, value) -> put(key, value) } }

    private fun socialPayload(type: String, objectId: String): Map<String, String> = mapOf(
        "version" to "1",
        "bindingId" to bindingId,
        "type" to type,
        "objectId" to objectId,
        "objectRevision" to "1"
    )

    private fun cloudSession(userId: String, generation: String) = AccountSession.Cloud(
        userId = userId,
        email = "athlete@example.test",
        displayName = "Athlete",
        accessToken = "access-token",
        refreshToken = "refresh-token",
        sessionGeneration = generation
    )
}
