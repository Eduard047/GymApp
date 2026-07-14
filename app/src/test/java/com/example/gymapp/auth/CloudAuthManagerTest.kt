package com.example.gymapp.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.text.Normalizer

class CloudAuthManagerTest {
    @Test
    fun localDatabaseIdentityIsCanonicalBoundedAndCollisionResistant() {
        val slash = AccountSession.Local("a/b").databaseName()
        val underscore = AccountSession.Local("a_b").databaseName()
        val ivan = AccountSession.Local("Іван").databaseName()
        val oleh = AccountSession.Local("Олег").databaseName()
        val composed = "Élodie"
        val decomposed = Normalizer.normalize(composed, Normalizer.Form.NFD)

        assertTrue(slash.matches(Regex("^local_v2_[0-9a-f]{64}$")))
        assertNotEquals(slash, underscore)
        assertNotEquals(ivan, oleh)
        assertEquals(
            AccountSession.Local(" alice ").databaseName(),
            AccountSession.Local("ALICE").databaseName()
        )
        assertEquals(
            AccountSession.Local(composed).databaseName(),
            AccountSession.Local(decomposed).databaseName()
        )
        assertNull(normalizedLocalDisplayNameOrNull("bad\u0000name"))
        assertNull(normalizedLocalDisplayNameOrNull("x".repeat(1_000)))
    }

    @Test
    fun legacyLocalFilenameAlgorithmRemainsAvailableOnlyForAliasRecovery() {
        assertEquals("local_a_b", legacyLocalDatabaseName(" A/B "))
        assertEquals("local_a_b", legacyLocalDatabaseName("a_b"))
        assertNotEquals(
            checkNotNull(localDatabaseLogicalName("a/b")),
            checkNotNull(localDatabaseLogicalName("a_b"))
        )
    }

    @Test
    fun logoutRequestTargetsOnlyTheCapturedCloudSessionGeneration() {
        val captured = cloudSession(userId = "user-a", generation = "generation-a")
            .copy(accessToken = "captured-access-token")
        val replacement = captured.copy(
            accessToken = "replacement-access-token",
            sessionGeneration = "generation-b"
        )

        val request = checkNotNull(localCloudLogoutRequest(captured))

        assertEquals("POST", request.method)
        assertEquals("/auth/v1/logout?scope=local", request.path)
        assertEquals("captured-access-token", request.accessToken)
        assertEquals("generation-a", request.sessionGeneration)
        assertFalse(request.path.contains("scope=global"))
        assertNull(activeCloudSessionFor(replacement, captured))
        assertNull(localCloudLogoutRequest(AccountSession.Local("Local")))
        assertNull(localCloudLogoutRequest(null))
    }

    @Test
    fun activeSessionRequiresTheSameAccountGeneration() {
        val expected = cloudSession(userId = "user-a", generation = "generation-a")
        val refreshed = expected.copy(accessToken = "new-access-token")

        assertEquals(refreshed, activeCloudSessionFor(refreshed, expected))
        assertNull(activeCloudSessionFor(null, expected))
        assertNull(activeCloudSessionFor(AccountSession.Local("Local"), expected))
        assertNull(
            activeCloudSessionFor(
                cloudSession(userId = "user-b", generation = "generation-a"),
                expected
            )
        )
        assertNull(
            activeCloudSessionFor(
                cloudSession(userId = "user-a", generation = "generation-b"),
                expected
            )
        )
    }

    @Test
    fun remoteStateUpdateUsesTheServerRevisionAsACompareAndSwapFilter() {
        val revision = RemoteStateRevision.Present("2026-07-13T20:45:12.123456+00:00")

        val request = remoteStateWriteRequest("user/a?b", revision)

        assertEquals("PATCH", request.method)
        assertEquals("return=representation", request.prefer)
        assertEquals(
            "/rest/v1/user_states?user_id=eq.user%2Fa%3Fb" +
                "&updated_at=eq.2026-07-13T20%3A45%3A12.123456%2B00%3A00" +
                "&select=updated_at",
            request.path
        )
        assertFalse(request.path.contains("updated_at=eq.2026-07-13T20:45"))
    }

    @Test
    fun remoteStateCreateIsInsertOnlyAndConflictsStayFailedClosed() {
        val request = remoteStateWriteRequest("user-a", RemoteStateRevision.Missing)

        assertEquals("POST", request.method)
        assertEquals(
            "resolution=ignore-duplicates,return=representation,missing=default",
            request.prefer
        )
        assertTrue(request.path.contains("on_conflict=user_id"))
        assertThrows(IllegalStateException::class.java) {
            remoteStateWriteRequest("user-a", RemoteStateRevision.Conflicted)
        }
    }

    @Test
    fun serverRevisionMustBeABoundedTimestamp() {
        assertTrue(isValidRemoteStateRevision("2026-07-13T20:45:12.123456+00:00"))
        assertTrue(isValidRemoteStateRevision("2026-07-13T20:45:12Z"))
        assertFalse(isValidRemoteStateRevision(""))
        assertFalse(isValidRemoteStateRevision("not-a-timestamp"))
        assertFalse(isValidRemoteStateRevision("2".repeat(65)))
    }

    @Test
    fun responseReaderRejectsBytesBeyondTheLimitBeforeJsonParsing() {
        val utf8 = "éé".toByteArray(Charsets.UTF_8)

        assertEquals(
            "éé",
            readUtf8ResponseBody(ByteArrayInputStream(utf8), maxBytes = 4)
        )
        assertThrows(IllegalStateException::class.java) {
            readUtf8ResponseBody(ByteArrayInputStream(utf8), maxBytes = 3)
        }
    }

    @Test
    fun cloudStateResponseIsStructurallyBoundedBeforeOrgJsonAllocation() {
        requireSafeCloudStateResponse("[]")
        requireSafeCloudStateResponse(
            "[{\"state\":{\"sessions\":[]},\"updated_at\":\"2026-07-14T00:00:00Z\"}]"
        )

        val excessivePrimitiveArray = buildString {
            append("[{\"state\":{\"values\":[")
            repeat(com.example.gymapp.data.repository.WorkoutDataLimits.MAX_JSON_ARRAY_ENTRIES + 1) {
                if (it > 0) append(',')
                append('0')
            }
            append("]}}]")
        }
        assertThrows(IllegalArgumentException::class.java) {
            requireSafeCloudStateResponse(excessivePrimitiveArray)
        }
    }

    @Test
    fun recoveryCallbackIsClassifiedWithoutReadingCredentials() {
        assertEquals(
            AuthCallbackKind.PasswordRecovery,
            authCallbackKind("recovery")
        )
        assertEquals(
            AuthCallbackKind.PasswordRecovery,
            authCallbackKind("RECOVERY")
        )
    }

    @Test
    fun signupPurposeIsClassifiedAsEmailConfirmation() {
        assertEquals(
            AuthCallbackKind.EmailConfirmation,
            authCallbackKind("signup")
        )
    }

    @Test
    fun authStateRejectsMismatchReplayExpiryAndDuplicates() {
        val state = "A".repeat(32)
        assertEquals(
            true,
            isExpectedAuthState(listOf(state), state, pendingIsFresh = true)
        )
        assertEquals(
            false,
            isExpectedAuthState(listOf("B".repeat(32)), state, pendingIsFresh = true)
        )
        assertEquals(
            false,
            isExpectedAuthState(listOf(state), expectedState = null, pendingIsFresh = true)
        )
        assertEquals(
            false,
            isExpectedAuthState(listOf(state), state, pendingIsFresh = false)
        )
        assertEquals(
            false,
            isExpectedAuthState(listOf(state, state), state, pendingIsFresh = true)
        )
        assertEquals(
            false,
            isExpectedAuthState(listOf("short"), state, pendingIsFresh = true)
        )
    }

    @Test
    fun signupAndRecoveryRequireStateBoundCodeWithoutBearerMaterial() {
        val state = "S".repeat(32)
        val authCode = "34e770dd-9ff9-416c-87fa-43b31d7ef225"
        val baseKeys = setOf("state", "purpose", "code")
        for (purpose in listOf("signup", "recovery")) {
            assertEquals(
                true,
                isStructurallySafePKCECallback(
                    queryKeys = baseKeys,
                    hasFragment = false,
                    receivedStates = listOf(state),
                    purposes = listOf(purpose),
                    codes = listOf(authCode),
                    errors = emptyList(),
                    descriptions = emptyList()
                )
            )
        }

        assertEquals(
            false,
            isStructurallySafePKCECallback(
                queryKeys = baseKeys + "access_token",
                hasFragment = false,
                receivedStates = listOf(state),
                purposes = listOf("signup"),
                codes = listOf(authCode),
                errors = emptyList(),
                descriptions = emptyList()
            )
        )
        assertEquals(
            false,
            isStructurallySafePKCECallback(
                queryKeys = baseKeys,
                hasFragment = true,
                receivedStates = listOf(state),
                purposes = listOf("signup"),
                codes = listOf(authCode),
                errors = emptyList(),
                descriptions = emptyList()
            )
        )
    }

    @Test
    fun callbackShapeRejectsMissingDuplicateOrAmbiguousFields() {
        val state = "C".repeat(32)
        val authCode = "4be36bc9-5ee4-40f3-a674-5ebf01b53ac8"
        fun isSafe(
            states: List<String> = listOf(state),
            purposes: List<String> = listOf("signup"),
            codes: List<String> = listOf(authCode),
            errors: List<String> = emptyList(),
            descriptions: List<String> = emptyList()
        ): Boolean {
            val keys = buildSet {
                if (states.isNotEmpty()) add("state")
                if (purposes.isNotEmpty()) add("purpose")
                if (codes.isNotEmpty()) add("code")
                if (errors.isNotEmpty()) add("error")
                if (descriptions.isNotEmpty()) add("error_description")
            }
            return isStructurallySafePKCECallback(
                queryKeys = keys,
                hasFragment = false,
                receivedStates = states,
                purposes = purposes,
                codes = codes,
                errors = errors,
                descriptions = descriptions
            )
        }

        assertEquals(false, isSafe(states = emptyList()))
        assertEquals(false, isSafe(states = listOf(state, state)))
        assertEquals(false, isSafe(purposes = emptyList()))
        assertEquals(false, isSafe(purposes = listOf("signup", "recovery")))
        assertEquals(false, isSafe(purposes = listOf("unknown")))
        assertEquals(false, isSafe(codes = emptyList()))
        assertEquals(false, isSafe(codes = listOf(authCode, authCode)))
        assertEquals(false, isSafe(errors = listOf("denied")))
        assertEquals(
            true,
            isSafe(
                codes = emptyList(),
                errors = listOf("access_denied"),
                descriptions = listOf("Cancelled")
            )
        )
        assertEquals(
            false,
            isSafe(codes = emptyList(), descriptions = listOf("orphaned"))
        )
        assertEquals(false, isSafe(codes = listOf("bad\ncode")))
        assertEquals(
            false,
            isSafe(codes = listOf("eyJhbGciOiJIUzI1NiJ9.payload.signature"))
        )
    }

    private fun cloudSession(userId: String, generation: String): AccountSession.Cloud {
        return AccountSession.Cloud(
            userId = userId,
            email = "$userId@example.com",
            displayName = userId,
            accessToken = "access-token",
            refreshToken = "refresh-token",
            sessionGeneration = generation
        )
    }
}
