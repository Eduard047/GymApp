using Toybox.Test;
using Toybox.Lang;

(:test)
class NavigationTestView extends WorkoutView {
    var actions = 4;
    var undoVisible = false;
    function initialize() { WorkoutView.initialize(); }
    function readyActionCount() { return actions; }
    function isUndoOverlayActive() { return undoVisible; }

    (:richWorkoutMode)
    function detectorPromptEnabled() { return GymSession.autoLogPrompt; }

    (:compactWorkoutMode96)
    function detectorPromptEnabled() { return false; }

    (:richWorkoutMode)
    function supportsDetectorPrompt() { return true; }

    (:compactWorkoutMode96)
    function supportsDetectorPrompt() { return false; }

    (:richWorkoutMode)
    function setDetectorPromptEnabled(value) { GymSession.autoLogPrompt = value; }

    (:compactWorkoutMode96)
    function setDetectorPromptEnabled(value) { }
}

(:test)
function pageKeysPreserveCyclicMenusAndModalGuards(logger as Test.Logger) as Lang.Boolean {
    var previousMode = GymWorkoutMode.state;
    var previousPrepared = GymStore.preparedWorkout;
    var view = new NavigationTestView();
    var previousPrompt = view.detectorPromptEnabled();
    GymWorkoutMode.state = GymWorkoutMode.MODE_PLANNED;
    view.setDetectorPromptEnabled(false);
    GymStore.preparedWorkout = null;
    var input = new WorkoutDelegate(view);
    // page, initial selection, direction, expected page, expected selection
    var rows = [[7, 0, -1, 7, 3], [7, 3, 1, 7, 0],
        [1, 0, -1, 1, 3], [1, 3, 1, 1, 0],
        [2, 0, -1, 2, 2], [2, 2, 1, 2, 0],
        [5, 0, -1, 5, 6], [5, 6, 1, 5, 0],
        [0, 0, 1, 1, 0], [0, 0, -1, 5, 0],
        [4, 0, 1, 5, 0], [4, 0, -1, 1, 0],
        [3, 0, 1, 0, 0], [3, 0, -1, 2, 0]];
    var ok = true;
    for (var i = 0; i < rows.size(); i += 1) {
        var row = rows[i];
        view.page = row[0];
        view.selected = row[1];
        view.pauseSelected = row[1];
        view.settingsSelected = row[1];
        if (row[2] > 0) { input.onNextPage(); } else { input.onPreviousPage(); }
        var selected = row[0] == 2 ? view.pauseSelected :
            (row[0] == 5 ? view.settingsSelected : view.selected);
        if (view.page != row[3] || selected != row[4]) {
            logger.debug("Unexpected navigation row " + i.toString());
            ok = false;
        }
    }
    view.actions = 3;
    view.page = 7;
    view.selected = 0;
    input.onPreviousPage();
    ok = ok && view.selected == 2;
    input.onNextPage();
    ok = ok && view.selected == 0;
    view.saveStage = 1;
    input.onNextPage();
    input.onPreviousPage();
    ok = ok && view.page == 7 && view.selected == 0;
    view.saveStage = 0;
    view.page = 1;
    view.undoVisible = true;
    input.onNextPage();
    ok = ok && view.page == 1 && view.selected == 0;
    view.undoVisible = false;
    if (view.supportsDetectorPrompt()) {
        view.setDetectorPromptEnabled(true);
        input.onPreviousPage();
        ok = ok && view.page == 1 && view.selected == 0;
        view.setDetectorPromptEnabled(false);
    }
    GymWorkoutMode.state = GymWorkoutMode.MODE_FREE;
    view.page = 0;
    input.onNextPage();
    input.onPreviousPage();
    ok = ok && view.page == 0;
    GymWorkoutMode.state = previousMode;
    view.setDetectorPromptEnabled(previousPrompt);
    GymStore.preparedWorkout = previousPrepared;
    return ok;
}

(:test)
function hardwareArrowsCannotActivateHiddenSave(logger as Test.Logger) as Lang.Boolean {
    var oldMode = GymWorkoutMode.state;
    var view = new NavigationTestView();
    var oldPrompt = view.detectorPromptEnabled();
    GymWorkoutMode.state = GymWorkoutMode.MODE_PLANNED;
    view.setDetectorPromptEnabled(false);
    var input = new WorkoutDelegate(view);
    view.page = 7;
    view.selected = 0;
    input.dispatchHardwareKey(Toybox.WatchUi.KEY_LEFT);
    var ok = view.selected == 3;
    input.dispatchHardwareKey(Toybox.WatchUi.KEY_RIGHT);
    ok = ok && view.selected == 0;
    view.page = 1;
    view.selected = 3;
    view.undoVisible = true;
    var originalSets = GymStore.sets;
    var originalWeight = GymStore.weight;
    var keys = [Toybox.WatchUi.KEY_RIGHT, Toybox.WatchUi.KEY_LEFT,
        Toybox.WatchUi.KEY_UP, Toybox.WatchUi.KEY_DOWN, Toybox.WatchUi.KEY_MENU];
    for (var i = 0; i < keys.size(); i += 1) {
        ok = input.dispatchHardwareKey(keys[i]) && ok;
    }
    ok = ok && view.page == 1 && view.selected == 3 &&
        GymStore.sets == originalSets && GymStore.weight == originalWeight;
    view.undoVisible = false;
    view.setDetectorPromptEnabled(true);
    if (view.detectorPromptEnabled()) {
        input.dispatchHardwareKey(Toybox.WatchUi.KEY_RIGHT);
        ok = ok && GymStore.sets == originalSets && view.page == 1;
    }
    view.saveStage = 1;
    input.dispatchHardwareKey(Toybox.WatchUi.KEY_START);
    input.dispatchHardwareKey(Toybox.WatchUi.KEY_ESC);
    ok = ok && view.saveStage == 1 && GymStore.sets == originalSets;
    GymWorkoutMode.state = oldMode;
    view.setDetectorPromptEnabled(oldPrompt);
    return ok;
}

(:test)
function backLeavesDiscardAndSummaryWithoutErasingWorkout(logger as Test.Logger) as Lang.Boolean {
    var oldRecording = GymSession.recording;
    var oldPrepared = GymStore.preparedWorkout;
    var view = new NavigationTestView();
    var oldPrompt = view.detectorPromptEnabled();
    GymSession.recording = false;
    view.setDetectorPromptEnabled(false);
    GymStore.preparedWorkout = null;
    var input = new WorkoutDelegate(view);
    var originalSets = GymStore.sets;
    view.page = 6;
    view.discardSelected = 1;
    input.onBack();
    var ok = view.page == 2 && view.discardSelected == 0 && GymStore.sets == originalSets;
    view.page = 3;
    input.onBack();
    ok = ok && view.page == 2 && view.pauseSelected == 1 && GymStore.sets == originalSets;
    input.onBack();
    ok = ok && view.page == 0 && view.pauseSelected == 0;
    view.page = 5;
    input.onBack();
    ok = ok && view.page == 7;
    GymSession.recording = true;
    view.page = 5;
    input.onBack();
    ok = ok && view.page == 0;
    view.saveStage = 1;
    view.page = 3;
    input.onBack();
    ok = ok && view.page == 3 && GymStore.sets == originalSets;
    GymSession.recording = oldRecording;
    view.setDetectorPromptEnabled(oldPrompt);
    GymStore.preparedWorkout = oldPrepared;
    return ok;
}

(:test)
class ModeChoiceTestView extends WorkoutView {
    function initialize() { WorkoutView.initialize(); }
    // Exercise the real menu and durable mode transition without starting FIT.
    function startOrResumeWorkout(usePlan) { return GymWorkoutMode.begin(usePlan); }
}

(:test)
function freeChoiceAndRestartNeverImportDownloadedPlan(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    GymStore.resetActiveWorkoutSnapshotState();
    GymStore.runtimeWorkoutStartedAtSeconds = null;
    GymStore.activeWorkoutStartedAtSeconds = null;
    GymStore.preparedWorkout = null;
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "free-choice-test";
    GymStore.exercises = ["Bench Press"];
    GymStore.exerciseCatalogNeedsWrite = true;
    GymStore.plan = [{"exerciseName" => "Bench Press", "weight" => 50.0, "reps" => 8}];
    var downloadedPlan = GymStore.plan;
    var view = new ModeChoiceTestView();
    view.selected = 1;
    var input = new WorkoutDelegate(view);
    input.onSelect();
    var ok = GymWorkoutMode.isFree() && !GymWorkoutMode.allowsDetailedTracking() &&
        GymStore.plan == downloadedPlan && GymStore.sets.size() == 0 && !GymStore.addSet();
    var origin = Toybox.Time.now().value() - 30;
    ok = GymStore.persistActiveWorkoutSnapshot([], origin,
        [30, 1.0, null, 0, 0, 0, null, 0]) && ok;
    var snapshot = Toybox.Application.Storage.getValue("activeWorkoutV1");
    if (GymStore.isValidActiveWorkoutSnapshot(snapshot)) {
        GymStore.restoreActiveWorkoutSnapshot(snapshot);
        GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
        GymWorkoutMode.restore();
        ok = GymWorkoutMode.isFree() && !GymStore.addSet() &&
            GymStore.sets.size() == 0 && GymStore.plan == downloadedPlan && ok;
    } else { ok = false; }
    LocalWorkoutFixture.reset();
    GymStore.resetActiveWorkoutSnapshotState();
    GymStore.runtimeWorkoutStartedAtSeconds = null;
    GymStore.activeWorkoutStartedAtSeconds = null;
    Toybox.Application.Storage.deleteValue("activeWorkoutV1");
    Toybox.Application.Storage.deleteValue("activeWorkoutModeV1");
    return ok;
}
