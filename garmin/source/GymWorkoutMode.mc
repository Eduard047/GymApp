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

    static function isIdle() {
        return state == MODE_IDLE;
    }

    static function isFree() {
        return state == MODE_FREE;
    }

    static function isPlanned() {
        return state == MODE_PLANNED;
    }

    static function allowsDetailedTracking() {
        return state == MODE_PLANNED;
    }

    static function hasValidPlan() {
        var currentPlan = GymStore.plan;
        if (!GymStore.isValidSetList(currentPlan, GymStore.maxPlanSets, true) ||
            currentPlan.size() == 0) {
            return false;
        }
        for (var i = 0; i < currentPlan.size(); i += 1) {
            var item = currentPlan[i];
            if (!(item instanceof Lang.Dictionary) ||
                GymStore.exerciseIndexForName(item.get("exerciseName")) < 0) {
                return false;
            }
        }
        return true;
    }

    static function canResume() {
        return state == MODE_FREE ||
            (state == MODE_PLANNED && hasValidPlan());
    }

    (:richWorkoutMode)
    static function begin(usePlan) {
        if (!(usePlan instanceof Lang.Boolean) || !isIdle() ||
            GymStore.hasUnfinishedWorkout()) {
            GymStore.status = "MODE FAIL";
            return false;
        }
        if (usePlan && !hasValidPlan()) {
            GymStore.status = "NO PLAN";
            return false;
        }
        state = usePlan ? MODE_PLANNED : MODE_FREE;
        if (isPlanned() && !GymStore.selectNextPlanSlotInGlobalOrder()) {
            state = MODE_IDLE;
            GymStore.status = "NO PLAN";
            return false;
        }
        if (isFree()) {
            // A stale rest from an older detailed activity must not leak into the
            // metrics-only surface. The downloaded plan and historical sets stay
            // untouched so recovery and a later explicit Start Plan remain safe.
            GymStore.restDurationMs = 0;
            GymStore.restStartedAt = null;
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
            GymStore.status = "SAVE FAIL";
            return false;
        }
    }

    // The five 96 KiB products use the same state machine and owner-bound
    // journal with fewer branches and virtual calls. Keeping this as a separate
    // annotated implementation avoids charging larger watches for the compact
    // compatibility path and gives the constrained products loader headroom.
    (:compactWorkoutMode96)
    static function begin(usePlan) {
        if (!(usePlan instanceof Lang.Boolean) || state != MODE_IDLE ||
            GymStore.hasUnfinishedWorkout()) {
            GymStore.status = "MODE FAIL";
            return false;
        }
        if (usePlan && !hasValidPlan()) {
            GymStore.status = "NO PLAN";
            return false;
        }
        state = usePlan ? MODE_PLANNED : MODE_FREE;
        if (usePlan) {
            if (!GymStore.selectNextPlanSlotInGlobalOrder()) {
                state = MODE_IDLE;
                GymStore.status = "NO PLAN";
                return false;
            }
        } else {
            GymStore.restDurationMs = 0;
            GymStore.restStartedAt = null;
        }
        if (!GymStore.hasAccountBinding()) {
            return true;
        }
        // The compact marker is authorized transitively by the validated,
        // owner/device/generation-bound active snapshot required by restore().
        // A crash before that snapshot exists leaves no resumable workout and
        // therefore cannot activate this marker for any account.
        try {
            Storage.setValue("activeWorkoutModeV1", [1, usePlan]);
            return true;
        } catch (e) {
            state = MODE_IDLE;
            GymStore.status = "SAVE FAIL";
            return false;
        }
    }

    (:richWorkoutMode)
    static function restore() {
        state = MODE_IDLE;
        var marker = Storage.getValue("activeWorkoutModeV1");
        var preparedMode = null;
        if (GymStore.hasPreparedWorkout()) {
            preparedMode = GymStore.preparedWorkout.size() == 7 ?
                (GymStore.preparedWorkout[6] ? "free" : "planned") :
                "planned";
        }
        var valid = marker instanceof Lang.Array && marker.size() == 5 &&
            marker[0] instanceof Lang.Number && marker[0] == 1 &&
            marker[4] instanceof Lang.Boolean && GymStore.hasAccountBinding() &&
            GymStore.isValidAccountBinding(marker[1]) &&
            GymStore.isBoundedText(marker[2], GymStore.maxBindingLength) &&
            GymStore.isValidOptionalAccountBinding(marker[3]) &&
            GymStore.accountBinding.toString().equals(marker[1].toString()) &&
            GymStore.deviceBinding.toString().equals(marker[2].toString()) &&
            ((GymStore.pairingGeneration == null && marker[3] == null) ||
                (GymStore.isValidAccountBinding(GymStore.pairingGeneration) &&
                    GymStore.isValidAccountBinding(marker[3]) &&
                    GymStore.pairingGeneration.toString().equals(
                        marker[3].toString()))) &&
            GymStore.hasUnfinishedWorkout() &&
            (!marker[4] || hasValidPlan()) &&
            (preparedMode == null ||
                (marker[4] && preparedMode.equals("planned")) ||
                (!marker[4] && preparedMode.equals("free")));
        if (valid) {
            state = marker[4] ? MODE_PLANNED : MODE_FREE;
            return;
        }
        // Phase 0/1 is a second owner-bound mode journal. If the smaller active
        // marker was lost after preparation, recover the exact transaction mode
        // instead of exposing detailed controls for an empty FREE payload.
        if (preparedMode != null &&
            (preparedMode.equals("free") || hasValidPlan())) {
            state = preparedMode.equals("free") ? MODE_FREE : MODE_PLANNED;
        }
        try {
            Storage.deleteValue("activeWorkoutModeV1");
        } catch (e) {
        }
    }

    (:compactWorkoutMode96)
    static function restore() {
        state = MODE_IDLE;
        // A valid phase marker is already account/device/generation-bound by
        // GymStore. It is the later journal, so it authoritatively restores the
        // exact mode even if the smaller active marker was lost or stale.
        if (GymStore.hasPreparedWorkout()) {
            var preparedFree = GymStore.preparedWorkout.size() == 7 &&
                GymStore.preparedWorkout[6];
            if (preparedFree || hasValidPlan()) {
                state = preparedFree ? MODE_FREE : MODE_PLANNED;
            }
            return;
        }
        var marker = Storage.getValue("activeWorkoutModeV1");
        var markerSize = marker instanceof Lang.Array ? marker.size() : 0;
        var modeIndex = markerSize - 1;
        // Size five is the released 3.1.x marker. Its duplicated bindings need
        // not be re-evaluated here because GymStore has already accepted the
        // exact active snapshot under those same three bindings.
        var valid = (markerSize == 2 || markerSize == 5) &&
            marker[0] instanceof Lang.Number && marker[0] == 1 &&
            marker[modeIndex] instanceof Lang.Boolean &&
            GymStore.hasUnfinishedWorkout() &&
            (!marker[modeIndex] || hasValidPlan());
        if (valid) {
            state = marker[modeIndex] ? MODE_PLANNED : MODE_FREE;
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
