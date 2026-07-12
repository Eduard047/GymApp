package com.example.gymapp.auth

import org.junit.Assert.assertEquals
import org.junit.Test

class CloudAuthManagerTest {
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
}
