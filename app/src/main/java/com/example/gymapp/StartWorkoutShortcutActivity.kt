package com.example.gymapp

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.example.gymapp.service.ACTION_START_WORKOUT_SHORTCUT

/**
 * Flags for the intent the trampoline forwards to [MainActivity]. SINGLE_TOP|CLEAR_TOP delivers
 * `onNewIntent` to a live instance (keeping its in-memory workout plan); NEW_TASK is required to
 * start from a different task affinity and only brings the existing app task to the front.
 */
internal const val START_WORKOUT_SHORTCUT_FORWARD_FLAGS: Int =
    Intent.FLAG_ACTIVITY_NEW_TASK or
        Intent.FLAG_ACTIVITY_SINGLE_TOP or
        Intent.FLAG_ACTIVITY_CLEAR_TOP

/** Flags the launcher uses that must never be forwarded (CLEAR_TASK would destroy MainActivity). */
internal fun forwardedStartWorkoutShortcutFlags(): Int = START_WORKOUT_SHORTCUT_FORWARD_FLAGS

/**
 * Invisible launcher-shortcut target. Static shortcuts are started with NEW_TASK|CLEAR_TASK, so
 * pointing them straight at [MainActivity] would wipe a running app. This activity lives in its
 * own (empty-affinity) task, hands the shortcut over to [MainActivity] and finishes at once.
 */
class StartWorkoutShortcutActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(
            Intent(this, MainActivity::class.java)
                .setAction(ACTION_START_WORKOUT_SHORTCUT)
                .addFlags(forwardedStartWorkoutShortcutFlags())
        )
        finish()
    }
}
