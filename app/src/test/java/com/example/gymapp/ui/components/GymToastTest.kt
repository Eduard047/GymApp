package com.example.gymapp.ui.components

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.Velocity
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GymToastTest {
    @Test
    fun durationIsFourSecondsOrSixWithAction() {
        assertEquals(4_000L, gymToastDurationMillis(false, GymToastDuration.Auto))
        assertEquals(6_000L, gymToastDurationMillis(true, GymToastDuration.Auto))
        assertNull(gymToastDurationMillis(true, GymToastDuration.Indefinite))
    }

    @Test
    fun newToastReplacesTheCurrentOneInsteadOfStacking() {
        val slot = GymToastSlot()
        val first = slot.show("one", null, GymToastDuration.Auto)
        assertNull(first.replaced)
        val second = slot.show("two", "Undo", GymToastDuration.Auto)
        assertEquals(first.toast, second.replaced)
        assertEquals("two", slot.current?.message)
        assertNotEquals(first.toast.id, second.toast.id)
        assertNull(slot.dismiss(first.toast.id))
        assertNotNull(slot.current)
    }

    @Test
    fun countdownStartsOnlyWhenShownAndRunsDown() {
        val slot = GymToastSlot()
        val toast = slot.show("x", null, GymToastDuration.Auto).toast
        assertEquals(4_000L, slot.remainingAt(10_000L))
        slot.markShown(toast.id, 10_000L)
        assertEquals(3_000L, slot.remainingAt(11_000L))
        assertEquals(0L, slot.remainingAt(99_000L))
    }

    @Test
    fun pausingHoldsTheCountdownUntilEveryReasonReleases() {
        val slot = GymToastSlot()
        val toast = slot.show("x", "Undo", GymToastDuration.Auto).toast
        slot.markShown(toast.id, 0L)
        assertTrue(slot.setPaused(toast.id, GymToastPauseReason.Touch, true, 1_000L))
        assertFalse(slot.setPaused(toast.id, GymToastPauseReason.Focus, true, 2_000L))
        assertEquals(5_000L, slot.remainingAt(30_000L))
        assertFalse(slot.setPaused(toast.id, GymToastPauseReason.Touch, false, 31_000L))
        assertTrue(slot.isPaused)
        assertEquals(5_000L, slot.remainingAt(40_000L))
        assertTrue(slot.setPaused(toast.id, GymToastPauseReason.Focus, false, 50_000L))
        assertEquals(4_000L, slot.remainingAt(51_000L))
    }

    @Test
    fun indefiniteToastHasNoCountdownAndStaleIdsAreIgnored() {
        val slot = GymToastSlot()
        val toast = slot.show("x", "Close", GymToastDuration.Indefinite).toast
        slot.markShown(toast.id, 0L)
        assertNull(slot.remainingAt(1_000_000L))
        assertFalse(slot.setPaused(toast.id + 1, GymToastPauseReason.Touch, true, 0L))
        assertNull(slot.dismiss(toast.id + 1))
        assertEquals(toast, slot.dismiss(toast.id))
        assertNull(slot.current)
    }

    @Test
    fun replacingClearsAHoldFromThePreviousToast() {
        val slot = GymToastSlot()
        val first = slot.show("a", null, GymToastDuration.Auto).toast
        slot.markShown(first.id, 0L)
        slot.setPaused(first.id, GymToastPauseReason.Touch, true, 100L)
        slot.show("b", null, GymToastDuration.Auto)
        assertFalse(slot.isPaused)
    }

    @Test
    fun topmostSheetHostDrawsTheToastAndRootTakesOverAgain() {
        val stack = GymToastHostStack()
        val sheetA = Any()
        val sheetB = Any()
        assertNull(stack.top)
        stack.register(sheetA)
        stack.register(sheetB)
        assertTrue(stack.top === sheetB)
        stack.unregister(sheetB)
        assertTrue(stack.top === sheetA)
        stack.unregister(sheetA)
        assertNull(stack.top)
    }

    @Test
    fun showReturnsActionOrDismissedAndReplacedCallerIsDismissed() = runBlocking {
        val controller = GymToastController()
        val first = async(start = CoroutineStart.UNDISPATCHED) { controller.show("one", "Undo") }
        val firstId = controller.state.value.toast!!.id
        val second = async(start = CoroutineStart.UNDISPATCHED) { controller.show("two", "Retry") }
        assertEquals(GymToastResult.Dismissed, first.await())
        assertEquals("two", controller.state.value.toast?.message)
        assertNotEquals(firstId, controller.state.value.toast?.id)
        controller.performAction(controller.state.value.toast!!.id)
        assertEquals(GymToastResult.ActionPerformed, second.await())
        assertNull(controller.state.value.toast)
    }

    @Test
    fun cancellingTheCallerDismissesItsToast() = runBlocking {
        val controller = GymToastController()
        val job = async(start = CoroutineStart.UNDISPATCHED) { controller.show("x") }
        assertNotNull(controller.state.value.toast)
        job.cancel()
        job.join()
        assertNull(controller.state.value.toast)
    }

    @Test
    fun postedToastWaitsForAHostBeforeItsCountdownStartsAndClearDropsIt() {
        var now = 0L
        val controller = GymToastController { now }
        controller.post("hello")
        now = 60_000L
        assertEquals(4_000L, controller.remainingMillis())
        controller.markShown(controller.state.value.toast!!.id)
        now = 61_000L
        assertEquals(3_000L, controller.remainingMillis())
        controller.clear()
        assertNull(controller.state.value.toast)
    }

    @Test
    fun sheetHostRegistrationIsPublishedToHosts() {
        val controller = GymToastController()
        val host = Any()
        controller.registerSheetHost(host)
        assertTrue(controller.state.value.sheetHost === host)
        controller.unregisterSheetHost(host)
        assertNull(controller.state.value.sheetHost)
    }

    @Test
    fun swipeDownOrSidewaysDismissesPastThresholdOrOnFlick() {
        val w = 400f
        val h = 100f
        val thr = 1_000f
        assertEquals(GymToastSwipeOutcome.Settle, gymToastSwipeOutcome(Offset(0f, 20f), Velocity.Zero, w, h, thr))
        assertEquals(GymToastSwipeOutcome.DismissDown, gymToastSwipeOutcome(Offset(0f, 45f), Velocity.Zero, w, h, thr))
        assertEquals(GymToastSwipeOutcome.DismissDown, gymToastSwipeOutcome(Offset(0f, 10f), Velocity(0f, 1_500f), w, h, thr))
        assertEquals(GymToastSwipeOutcome.DismissRight, gymToastSwipeOutcome(Offset(170f, 0f), Velocity.Zero, w, h, thr))
        assertEquals(GymToastSwipeOutcome.DismissLeft, gymToastSwipeOutcome(Offset(-30f, 0f), Velocity(-2_000f, 0f), w, h, thr))
        // A flick against the drag direction does not dismiss.
        assertEquals(GymToastSwipeOutcome.Settle, gymToastSwipeOutcome(Offset(30f, 0f), Velocity(-2_000f, 0f), w, h, thr))
    }

    @Test
    fun upwardDragDoesNotMoveTheToast() {
        assertEquals(Offset(12f, 0f), gymToastClampDrag(Offset(12f, -30f)))
        assertEquals(0f, gymToastDragProgress(Offset(0f, -50f), 400f, 100f), 0f)
        assertEquals(1f, gymToastDragProgress(Offset(0f, 80f), 400f, 100f), 0f)
    }
}
