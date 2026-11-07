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
import java.util.Base64
import org.json.JSONObject

class CloudAuthManagerTest {
    @Test
    fun shortFriendCodeFallsBackOnlyWhenTheRpcFunctionIsUnavailable() {
        assertTrue(isUnavailableSocialMyFriendCodeRpc(404, "PGRST202"))
        assertTrue(isUnavailableSocialMyFriendCodeRpc(404, "42883"))
        assertFalse(isUnavailableSocialMyFriendCodeRpc(404, null))
        assertFalse(isUnavailableSocialMyFriendCodeRpc(404, "PGRST301"))
        assertFalse(isUnavailableSocialMyFriendCodeRpc(401, "PGRST202"))
        assertFalse(isUnavailableSocialMyFriendCodeRpc(500, "PGRST202"))
    }

    @Test
    fun boundedWorkoutInboxFallsBackOnlyWhenThatRpcFunctionIsUnavailable() {
        assertTrue(isUnavailableSocialWorkoutInboxPageRpc(404, "PGRST202"))
        assertTrue(isUnavailableSocialWorkoutInboxPageRpc(404, "42883"))
        assertFalse(isUnavailableSocialWorkoutInboxPageRpc(404, "P0002"))
        assertFalse(isUnavailableSocialWorkoutInboxPageRpc(400, "42883"))
        assertFalse(isUnavailableSocialWorkoutInboxPageRpc(500, "PGRST202"))
    }

    @Test
    fun boundedWorkoutInboxRequestAlwaysUsesTheFourArgumentDefaultTenContract() {
        val initial = socialWorkoutInboxPageRequestBody(cursor = null)
        assertEquals(
            setOf(
                "p_cursor_created_at",
                "p_cursor_invite_id",
                "p_cursor_pending",
                "p_limit"
            ),
            initial.keys().asSequence().toSet()
        )
        assertTrue(initial.isNull("p_cursor_created_at"))
        assertTrue(initial.isNull("p_cursor_invite_id"))
        assertTrue(initial.isNull("p_cursor_pending"))
        assertEquals(10, initial.getInt("p_limit"))

        val cursor = SocialWorkoutInboxCursor(
            createdAt = "2026-08-13T10:00:00Z",
            inviteId = "wi_${"a".repeat(32)}",
            pending = true
        )
        val next = socialWorkoutInboxPageRequestBody(cursor, limit = 7)
        assertEquals(cursor.createdAt, next.getString("p_cursor_created_at"))
        assertEquals(cursor.inviteId, next.getString("p_cursor_invite_id"))
        assertTrue(next.getBoolean("p_cursor_pending"))
        assertEquals(7, next.getInt("p_limit"))
        assertThrows(IllegalArgumentException::class.java) {
            socialWorkoutInboxPageRequestBody(cursor, limit = 11)
        }
    }

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
    fun newLocalProfileNamesMatchTheMobileVisibleContractWithoutWeakeningLegacyRestore() {
        assertEquals("Local", validatedNewLocalDisplayNameOrNull(" Local "))
        assertEquals("Іван_2", validatedNewLocalDisplayNameOrNull("Іван_2"))
        assertNull(validatedNewLocalDisplayNameOrNull("A"))
        assertNull(validatedNewLocalDisplayNameOrNull("A".repeat(33)))
        assertNull(validatedNewLocalDisplayNameOrNull("Local/Profile"))
        assertNull(validatedNewLocalDisplayNameOrNull("Coach🔥"))

        val grandfathered = "Legacy/" + "x".repeat(64)
        assertEquals(grandfathered, normalizedLocalDisplayNameOrNull(grandfathered))
        assertNull(validatedNewLocalDisplayNameOrNull(grandfathered))
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
    fun localLogoutAlwaysDropsTheInMemorySessionWhenDiskClearFails() {
        val failedPersistenceState = signedOutAuthStateAfterLocalLogout(
            preferencesCleared = false
        )

        assertNull(failedPersistenceState.session)
        assertFalse(failedPersistenceState.isLoading)
        assertTrue(failedPersistenceState.messageIsError)
        assertEquals(
            com.example.gymapp.R.string.auth_message_logout_failed,
            failedPersistenceState.message?.resourceId
        )

        val successfulState = signedOutAuthStateAfterLocalLogout(preferencesCleared = true)
        assertNull(successfulState.session)
        assertNull(successfulState.message)
        assertFalse(successfulState.messageIsError)
    }

    @Test
    fun accountDeletionRequestAndResponseUseTheExactEdgeFunctionContract() {
        val preparation = cloudAccountDeletionPreparationRequest()
        val preparationBody = JSONObject(preparation.body)
        assertEquals("POST", preparation.method)
        assertEquals("/functions/v1/delete-account", preparation.path)
        assertTrue(preparation.headers.isEmpty())
        assertEquals(setOf("action"), preparationBody.keys().asSequence().toSet())
        assertEquals("prepare", preparationBody.getString("action"))

        val grant = "10000000-0000-4000-8000-000000000001"
        val request = cloudAccountDeletionRequest(grant)
        val body = JSONObject(request.body)

        assertEquals("POST", request.method)
        assertEquals("/functions/v1/delete-account", request.path)
        assertEquals(mapOf("X-GymApp-Delete" to "confirmed"), request.headers)
        assertEquals(setOf("action", "confirmation", "grant"), body.keys().asSequence().toSet())
        assertEquals("delete", body.getString("action"))
        assertEquals("DELETE", body.getString("confirmation"))
        assertEquals(grant, body.getString("grant"))
        assertEquals(
            grant,
            accountDeletionGrantFromResponse(
                "{\"grant\":\"$grant\",\"expiresAt\":\"2026-08-23T16:00:00Z\"}"
            )
        )
        assertNull(accountDeletionGrantFromResponse("{\"grant\":\"$grant\"}"))
        assertTrue(isSuccessfulCloudAccountDeletionResponse("{\"deleted\":true}"))
        assertFalse(isSuccessfulCloudAccountDeletionResponse("{\"deleted\":false}"))
        assertFalse(
            isSuccessfulCloudAccountDeletionResponse(
                "{\"deleted\":true,\"unexpected\":true}"
            )
        )
        assertFalse(isSuccessfulCloudAccountDeletionResponse("[]"))
    }

    @Test
    fun recoveryAndSignedInPasswordUpdatesHaveDifferentRequestShapes() {
        val recovery = JSONObject(passwordUpdateBody(newPassword = "NewSecurePass9!"))
        val signedIn = JSONObject(
            passwordUpdateBody(
                newPassword = "NewSecurePass9!",
                currentPassword = "CurrentSecurePass8!"
            )
        )

        assertEquals(setOf("password"), recovery.keys().asSequence().toSet())
        assertEquals("NewSecurePass9!", recovery.getString("password"))
        assertEquals(setOf("password", "current_password"), signedIn.keys().asSequence().toSet())
        assertEquals("CurrentSecurePass8!", signedIn.getString("current_password"))

        val reauthenticated = JSONObject(
            passwordUpdateBody(
                newPassword = "NewSecurePass9!",
                currentPassword = "CurrentSecurePass8!",
                nonce = "123456"
            )
        )
        assertEquals(
            setOf("password", "current_password", "nonce"),
            reauthenticated.keys().asSequence().toSet()
        )
        assertEquals("123456", reauthenticated.getString("nonce"))
    }

    @Test
    fun passwordReauthenticationUsesOnlyBoundedNumericNoncesAndExactProviderErrors() {
        assertTrue(isValidPasswordReauthenticationNonce("123456"))
        assertTrue(isValidPasswordReauthenticationNonce("12345678"))
        assertFalse(isValidPasswordReauthenticationNonce("12345"))
        assertFalse(isValidPasswordReauthenticationNonce("123456789"))
        assertFalse(isValidPasswordReauthenticationNonce("12345a"))
        assertFalse(isValidPasswordReauthenticationNonce("١٢٣٤٥٦"))
        assertTrue(isPasswordReauthenticationRequired("reauthentication_needed", null))
        assertTrue(isPasswordReauthenticationRequired(null, "Reauthentication needed"))
        assertFalse(isPasswordReauthenticationRequired("reauthentication_not_valid", null))
        assertFalse(isPasswordReauthenticationRequired(null, "nonce was invalid"))
    }

    @Test
    fun onlyTerminalRefreshFailuresRequireAFreshLogin() {
        assertTrue(isTerminalRefreshFailure(401, null, null))
        assertTrue(isTerminalRefreshFailure(400, "refresh_token_not_found", null))
        assertTrue(isTerminalRefreshFailure(400, null, "Invalid Refresh Token"))
        assertFalse(isTerminalRefreshFailure(429, "over_request_rate_limit", "try later"))
        assertFalse(isTerminalRefreshFailure(503, null, "temporarily unavailable"))
    }

    @Test
    fun resendReusesOnlyTheFreshSignupTransactionForTheSameEmail() {
        val now = 1_750_000_000_000L
        val existing = PendingAuthTransaction(
            state = "S".repeat(32),
            codeVerifier = "V".repeat(64),
            email = "athlete@example.com",
            createdAtMillis = now - 60_000L
        )

        assertEquals(
            existing,
            reusablePendingSignupTransaction(existing, "athlete@example.com", now)
        )
        assertNull(reusablePendingSignupTransaction(existing, "other@example.com", now))
        assertNull(
            reusablePendingSignupTransaction(
                existing.copy(createdAtMillis = now - 24 * 60 * 60 * 1_000L - 1),
                "athlete@example.com",
                now
            )
        )
    }

    @Test
    fun ambiguousAuthInitiationOutcomesKeepThePendingPkceTransaction() {
        assertTrue(isDeterministicAuthInitiationHttpFailure(400))
        assertTrue(isDeterministicAuthInitiationHttpFailure(422))
        assertTrue(isDeterministicAuthInitiationHttpFailure(429))
        assertFalse(isDeterministicAuthInitiationHttpFailure(null))
        assertFalse(isDeterministicAuthInitiationHttpFailure(408))
        assertFalse(isDeterministicAuthInitiationHttpFailure(425))
        assertFalse(isDeterministicAuthInitiationHttpFailure(500))
        assertFalse(isDeterministicAuthInitiationHttpFailure(503))
    }

    @Test
    fun storedCloudSessionMustBeBoundToAValidJwtSubject() {
        val userId = "123e4567-e89b-42d3-a456-426614174000"
        val raw = storedCloudSessionJson(userId, accessToken(userId))

        val parsed = parseStoredCloudSession(raw)

        assertEquals(userId, parsed?.userId)
        assertEquals("user@example.test", parsed?.email)
        assertNull(parseStoredCloudSession("{}"))
        assertNull(
            parseStoredCloudSession(
                storedCloudSessionJson(
                    userId,
                    accessToken("223e4567-e89b-42d3-a456-426614174000")
                )
            )
        )
        assertNull(parseStoredCloudSession(storedCloudSessionJson(userId, "not-a-jwt")))
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
    fun confirmedDeletionCompletionIsIdempotentAndGenerationBound() {
        val deleted = cloudSession(userId = "user-a", generation = "generation-a")

        assertEquals(
            CloudAccountDeletionSessionDisposition.ClearCapturedSession,
            cloudAccountDeletionSessionDisposition(deleted, deleted)
        )
        assertEquals(
            CloudAccountDeletionSessionDisposition.AlreadySignedOut,
            cloudAccountDeletionSessionDisposition(null, deleted)
        )
        assertEquals(
            CloudAccountDeletionSessionDisposition.PreserveDifferentSession,
            cloudAccountDeletionSessionDisposition(
                deleted.copy(sessionGeneration = "generation-b"),
                deleted
            )
        )
        assertEquals(
            CloudAccountDeletionSessionDisposition.PreserveDifferentSession,
            cloudAccountDeletionSessionDisposition(AccountSession.Local("Local"), deleted)
        )
    }

    @Test
    fun deletionJournalRetiresOnlyAfterDurableAuthCleanup() {
        val completed = CloudAccountDeletionCompletion(
            disposition = CloudAccountDeletionSessionDisposition.ClearCapturedSession,
            durableAuthCleanupCompleted = true
        )
        val failedPreferenceCommit = completed.copy(durableAuthCleanupCompleted = false)
        val replacementAccount = failedPreferenceCommit.copy(
            disposition = CloudAccountDeletionSessionDisposition.PreserveDifferentSession
        )

        assertTrue(shouldRetireCloudAccountDeletionJournal(completed, localCleanupFailures = 0))
        assertFalse(
            shouldRetireCloudAccountDeletionJournal(completed, localCleanupFailures = 1)
        )
        assertFalse(
            shouldRetireCloudAccountDeletionJournal(
                failedPreferenceCommit,
                localCleanupFailures = 0
            )
        )
        assertFalse(
            shouldRetireCloudAccountDeletionJournal(replacementAccount, localCleanupFailures = 0)
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
            descriptions: List<String> = emptyList(),
            errorCodes: List<String> = emptyList()
        ): Boolean {
            val keys = buildSet {
                if (states.isNotEmpty()) add("state")
                if (purposes.isNotEmpty()) add("purpose")
                if (codes.isNotEmpty()) add("code")
                if (errors.isNotEmpty()) add("error")
                if (descriptions.isNotEmpty()) add("error_description")
                if (errorCodes.isNotEmpty()) add("error_code")
            }
            return isStructurallySafePKCECallback(
                queryKeys = keys,
                hasFragment = false,
                receivedStates = states,
                purposes = purposes,
                codes = codes,
                errors = errors,
                descriptions = descriptions,
                errorCodes = errorCodes
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
                descriptions = listOf("Cancelled"),
                errorCodes = listOf("otp_expired")
            )
        )
        assertEquals(
            false,
            isSafe(codes = emptyList(), errorCodes = listOf("otp_expired"))
        )
        assertEquals(
            false,
            isSafe(
                codes = emptyList(),
                errors = listOf("access_denied"),
                errorCodes = listOf("one", "two")
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

    private fun storedCloudSessionJson(userId: String, accessToken: String): String =
        JSONObject()
            .put("userId", userId)
            .put("email", "User@Example.Test")
            .put("displayName", "User")
            .put("accessToken", accessToken)
            .put("refreshToken", "refresh-token")
            .put("sessionGeneration", "323e4567-e89b-42d3-a456-426614174000")
            .toString()

    private fun accessToken(userId: String): String {
        fun encode(value: String): String = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(value.toByteArray(Charsets.UTF_8))
        return listOf(
            encode("{\"alg\":\"HS256\"}"),
            encode(JSONObject().put("sub", userId).put("exp", 4_102_444_800L).toString()),
            encode("signature")
        ).joinToString(".")
    }
}
