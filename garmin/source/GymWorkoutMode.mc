using Toybox.Application.Storage;
using Toybox.Lang;

// Keep the downloaded plan independent from one activity's explicit mode.
// This small separate class also preserves the static-member ceiling on older
// Connect IQ 3.x products whose GymStore implementation is already at the cap.
class GymWorkoutMode {
    static var usesPlan = true;

    static function begin(usePlan) {
        usesPlan = usePlan;
        if (!GymStore.hasAccountBinding()) {
            return true;
        }
        var marker = [
            1,
            GymStore.accountBinding.toString(),
            GymStore.deviceBinding.toString(),
            GymStore.isValidAccountBinding(GymStore.pairingGeneration) ?
                GymStore.pairingGeneration.toString() : null,
            usePlan
        ];
        try {
            Storage.setValue("activeWorkoutModeV1", marker);
            return true;
        } catch (e) {
            usesPlan = true;
            GymStore.status = "SAVE FAIL";
            return false;
        }
    }

    static function restore() {
        usesPlan = true;
        var marker = Storage.getValue("activeWorkoutModeV1");
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
            GymStore.hasUnfinishedWorkout();
        if (valid) {
            usesPlan = marker[4];
            return;
        }
        try {
            Storage.deleteValue("activeWorkoutModeV1");
        } catch (e) {
        }
    }

    static function clear() {
        usesPlan = true;
        try {
            Storage.deleteValue("activeWorkoutModeV1");
        } catch (e) {
            // A stale marker is ignored unless an exact bound unfinished workout
            // also exists, so failed cleanup cannot affect the next activity.
        }
    }
}
