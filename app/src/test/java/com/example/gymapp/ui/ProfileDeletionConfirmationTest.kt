package com.example.gymapp.ui

import com.example.gymapp.ui.screens.localProfileDeletionConfirmationMatches
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProfileDeletionConfirmationTest {
    @Test
    fun typedDeleteIgnoresSurroundingWhitespaceButStaysCaseSensitive() {
        assertTrue(localProfileDeletionConfirmationMatches("DELETE"))
        assertTrue(localProfileDeletionConfirmationMatches(" DELETE"))
        assertTrue(localProfileDeletionConfirmationMatches("DELETE  "))
        assertTrue(localProfileDeletionConfirmationMatches("\tDELETE\n"))
        assertFalse(localProfileDeletionConfirmationMatches("delete"))
        assertFalse(localProfileDeletionConfirmationMatches("Delete"))
        assertFalse(localProfileDeletionConfirmationMatches("DELE TE"))
        assertFalse(localProfileDeletionConfirmationMatches("DELETE!"))
        assertFalse(localProfileDeletionConfirmationMatches(""))
        assertFalse(localProfileDeletionConfirmationMatches("   "))
    }
}
