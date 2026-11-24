package com.example.gymapp.wear.sync

object SyncPaths {
    const val PROTOCOL_VERSION = 1
    const val MAX_MESSAGE_BYTES = 100 * 1024
    const val MAX_WORKOUT_SETS = 100
    const val MAX_DURATION_SECONDS = 86_400L
    const val MIN_HEART_RATE = 25
    const val MAX_HEART_RATE = 240
    const val MAX_PLAN_SETS = 60
    const val MAX_SYNC_SESSIONS = 500
    const val MAX_SYNC_TOTAL_SETS = 5_000
    const val MAX_EXERCISE_CATALOG = 1_000
    const val MAX_EXERCISE_NAME_LENGTH = 120
    const val MAX_NOTE_LENGTH = 2_000
    const val MAX_REPS = 10_000
    const val MAX_WEIGHT = 1_000_000.0
    // Keep protocol counters exactly representable by JSON/JavaScript peers and leave
    // room for future generations instead of allowing a single max-Long lockout.
    const val MAX_PROTOCOL_COUNTER = 9_007_199_254_740_991L

    const val REQUEST_FULL_SYNC = "/gym/sync/request_full"
    const val CREATE_WORKOUT = "/gym/sync/create_workout"
    const val PUSH_WORKOUT_PLAN = "/gym/sync/push_workout_plan"
    const val UPDATE_SET = "/gym/sync/update_set"
    const val DELETE_SET = "/gym/sync/delete_set"
    const val MUTATION_ACK = "/gym/sync/mutation_ack"
    const val FULL_SYNC_PAYLOAD = "/gym/sync/full_payload"
    /** Phone -> watch: the phone signed out ("unbound") or the user unlinked this watch ("unlinked"). */
    const val BINDING_STATE = "/gym/sync/binding_state"
    /** Optional binding-state reason (mirror of the phone's): the owner was deleted there. */
    const val BINDING_REASON_ACCOUNT_DELETED = "account_deleted"
    /**
     * Watch -> phone: the user tapped "Unlink from phone" on this watch. Best effort; a phone
     * build that predates it drops the unknown path (it is not in its inbound path set).
     */
    const val UNLINK = "/gym/sync/unlink"

    /**
     * Capability the phone app declares (its res/values/wear.xml). The manifest filter of
     * WatchSyncListenerService names the same value; a change wakes the watch to send what waits.
     */
    const val PHONE_CAPABILITY = "gymapp_phone_sync"
}
