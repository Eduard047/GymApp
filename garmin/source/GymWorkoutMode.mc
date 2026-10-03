using Toybox.Application.Storage;
using Toybox.Lang;

// Keep the downloaded plan independent from one activity's explicit mode.
// This small separate class also preserves the static-member ceiling on older
// Connect IQ 3.x products whose GymStore implementation is already at the cap.
//
// Mode transitions are deliberately one-way for the lifetime of an activity:
// IDLE -> FREE or IDLE -> PLANNED -> IDLE. A downloaded plan does not select
// PLANNED by itself, and an active workout can never switch modes after start.
class GymWorkoutMode {
    static const MODE_IDLE = 0;
    static const MODE_FREE = 1;
    static const MODE_PLANNED = 2;
    static var state = MODE_IDLE;
    // Profile sentinel selects memory-specialized code paths; product limits
    // for new workouts are shared and live in GymStore.maxNewWorkoutSets.
    (:fr55Memory)
    static const recordingSetLimit = 30;
    (:notFr55Memory)
    static const recordingSetLimit = 60;
    // A new workout may start while fewer than this many wait in the queue.
    // The full profile keeps the whole queue capacity; 128 KiB watches keep
    // the strict one-session-beside-no-queued-data gate. Lite never reads it.
    (:richWorkoutMode, :noMem128)
    static const startQueueLimit = GymStore.maxPendingWorkouts;
    (:mem128)
    static const startQueueLimit = 1;

    (:richWorkoutMode, :inline)
    static function isIdle() {
        return state == MODE_IDLE;
    }

    (:inline)
    static function isFree() {
        return state == MODE_FREE;
    }

    (:inline)
    static function isPlanned() {
        return state == MODE_PLANNED;
    }

    (:richWorkoutMode, :inline)
    static function allowsDetailedTracking() {
        return state == MODE_PLANNED;
    }

    // The 96 KiB profile keeps manual set entry in Plan mode while Free remains
    // duration-only, matching the existing save wire contract.
    (:compactWorkoutMode96, :inline)
    static function allowsDetailedTracking() {
        return false;
    }

    // Keep optional per-set interval rows on richer profiles; the 96 KiB
    // products can omit the slices while retaining aggregate timeline metrics.
    (:richWorkoutMode, :inline)
    static function permitsOmittedSetIntervals() { return false; }

    (:compactWorkoutMode96, :inline)
    static function permitsOmittedSetIntervals() { return true; }

    (:richWorkoutMode)
    static function hasValidPlan() {
        var currentPlan = GymStore.plan;
        if (!GymStore.isValidLiveSetList(currentPlan, GymStore.maxPlanSets, true) ||
            currentPlan.size() == 0) {
            return false;
        }
        for (var i = 0; i < currentPlan.size(); i += 1) {
            var exerciseName = GymPlanAccess.nameAt(currentPlan, i);
            if (exerciseName == null ||
                GymStore.exerciseIndexForName(exerciseName) < 0) {
                return false;
            }
        }
        return true;
    }

    (:richWorkoutMode)
    static function hasStartablePlan() {
        return GymStore.plan.size() <= GymStore.maxNewWorkoutSets && hasValidPlan();
    }

    // The 96 KiB lite profile has no plan; every workout is FREE.
    (:compactWorkoutMode96, :inline)
    static function hasValidPlan() { return false; }

    static function canResume() {
        return state == MODE_FREE ||
            (state == MODE_PLANNED && hasValidPlan());
    }

    (:richWorkoutMode)
    static function begin(usePlan) {
        if (GymLocalWorkout.readFailed) {
            GymStore.status = GymStatus.RECOVERY_FAIL;
            return false;
        }
        if (!(usePlan instanceof Lang.Boolean) || !isIdle() ||
            GymStore.hasUnfinishedWorkout()) {
            GymStore.status = GymStatus.MODE_FAIL;
            return false;
        }
        // Reserve a queue slot before any new workout or picker state is written.
        // Resume bypasses begin(), so an existing recording remains recoverable.
        if (!GymPendingJournal.readable || GymStore.pendingCount() >= startQueueLimit) {
            GymStore.status = GymStatus.QUEUE_FULL;
            return false;
        }
        if (usePlan && !hasStartablePlan()) {
            GymStore.status = GymStatus.NO_PLAN;
            return false;
        }
        state = usePlan ? MODE_PLANNED : MODE_FREE;
        if (isPlanned() && !GymStore.selectNextPlanSlotInGlobalOrder()) {
            state = MODE_IDLE;
            GymStore.status = GymStatus.NO_PLAN;
            return false;
        }
        if (isFree()) {
            // A stale rest from an older detailed activity must not leak into the
            // metrics-only surface. The downloaded plan and historical sets stay
            // untouched so recovery and a later explicit Start Plan remain safe.
            GymStore.restDurationMs = 0;
            GymStore.restStartedAt = null;
        }
        // Persist the first target before a zero-set activity can be resumed.
        if (usePlan && !GymStore.saveCurrentEntry()) {
            state = MODE_IDLE;
            return false;
        }
        if (!GymStore.hasAccountBinding()) {
            return true;
        }
        var marker = [
            1,
            GymStore.accountBinding.toString(),
            GymStore.deviceBinding.toString(),
            GymStore.isValidAccountBinding(GymStore.pairingGeneration) ?
                GymStore.pairingGeneration.toString() : null,
            isPlanned()
        ];
        try {
            Storage.setValue("activeWorkoutModeV1", marker);
            return true;
        } catch (e) {
            state = MODE_IDLE;
            GymStore.status = GymStatus.SAVE_FAIL;
            return false;
        }
    }

    // The five 96 KiB products use the same state machine and owner-bound
    // journal with fewer branches and virtual calls. Keeping this as a separate
    // annotated implementation avoids charging larger watches for the compact
    // compatibility path and gives the constrained products loader headroom.
    (:compactWorkoutMode96)
    static function begin(usePlan) {
        if (GymLocalWorkout.readFailed) {
            GymStore.status = GymStatus.RECOVERY_FAIL;
            return false;
        }
        if (usePlan || state != MODE_IDLE || GymStore.hasUnfinishedWorkout()) {
            GymStore.status = GymStatus.MODE_FAIL;
            return false;
        }
        // Reserve a queue slot before any new workout state is written.
        // Resume bypasses begin(), so an existing recording remains recoverable.
        if (!GymPendingJournal.readable || GymStore.pendingCount() > 0) {
            GymStore.status = GymStatus.QUEUE_FULL;
            return false;
        }
        state = MODE_FREE;
        GymStore.restDurationMs = 0;
        GymStore.restStartedAt = null;
        if (!GymStore.hasAccountBinding()) {
            return true;
        }
        // The marker is authorized transitively by the validated active
        // snapshot required by restore().
        try {
            Storage.setValue("activeWorkoutModeV1", [1, false]);
            return true;
        } catch (e) {
            state = MODE_IDLE;
            GymStore.status = GymStatus.SAVE_FAIL;
            return false;
        }
    }

    (:richWorkoutMode)
    static function restore() {
        state = MODE_IDLE;
        var marker = Storage.getValue("activeWorkoutModeV1");
        var prepared = GymStore.hasPreparedWorkout();
        var preparedFree = prepared && GymStore.preparedWorkout.size() == 7 &&
            GymStore.preparedWorkout[6];
        var valid = marker instanceof Lang.Array && marker.size() == 5 &&
            marker[0] instanceof Lang.Number && marker[0] == 1 &&
            marker[4] instanceof Lang.Boolean &&
            GymStore.isValidOptionalAccountBinding(GymStore.pairingGeneration) &&
            GymStore.activeWorkoutSnapshotMatchesBindings(marker) &&
            GymStore.hasUnfinishedWorkout() &&
            (!marker[4] || hasValidPlan()) &&
            (!prepared || marker[4] != preparedFree);
        if (valid) {
            state = marker[4] ? MODE_PLANNED : MODE_FREE;
            return;
        }
        // Phase 0/1 is a second owner-bound mode journal. If the smaller active
        // marker was lost after preparation, recover the exact transaction mode
        // instead of exposing detailed controls for an empty FREE payload.
        if (prepared && (preparedFree || hasValidPlan())) {
            state = preparedFree ? MODE_FREE : MODE_PLANNED;
        }
        try {
            Storage.deleteValue("activeWorkoutModeV1");
        } catch (e) {
        }
    }

    // A workout that an older build recorded in plan mode resumes as FREE; its
    // stored rows are kept and uploaded unchanged.
    (:compactWorkoutMode96)
    static function restore() {
        state = MODE_IDLE;
        if (GymStore.hasPreparedWorkout()) {
            state = MODE_FREE;
            return;
        }
        var marker = Storage.getValue("activeWorkoutModeV1");
        if (marker instanceof Lang.Array && marker.size() > 0 &&
            GymStore.hasUnfinishedWorkout()) {
            state = MODE_FREE;
            return;
        }
        clear();
    }

    static function clear() {
        state = MODE_IDLE;
        try {
            Storage.deleteValue("activeWorkoutModeV1");
        } catch (e) {
            // A stale marker is ignored unless an exact bound unfinished workout
            // also exists, so failed cleanup cannot affect the next activity.
        }
    }
}
