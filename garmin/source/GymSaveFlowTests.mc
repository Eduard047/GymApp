using Toybox.Test;
using Toybox.Lang;

(:test)
class RefusingPauseSession {
    var stopCalls = 0;
    var saveCalls = 0;
    function isRecording() { return true; }
    function stop() { stopCalls += 1; return false; }
    function save() { saveCalls += 1; return true; }
}

(:test)
function failedFitPauseCannotPrepareOrCompleteSave(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    var previousSession = GymSession.session;
    var previousPrepared = GymStore.preparedWorkout;
    var previousSets = GymStore.sets;
    var session = new RefusingPauseSession();
    GymSession.session = session;
    GymSession.recording = true;
    GymSession.paused = false;
    GymSession.autoLogPrompt = false;
    GymSession.activeSetSeen = false;
    var view = new WorkoutView();
    view.saveAndExit();
    var valid = session.stopCalls == 1 && session.saveCalls == 0 &&
        view.saveStage == 0 && (GymStore.status == GymStatus.PAUSE_FAIL) &&
        GymStore.preparedWorkout == previousPrepared && GymStore.sets == previousSets;
    GymSession.session = previousSession;
    LocalWorkoutFixture.reset();
    return valid;
}

(:test)
class SaveFlowTestView extends WorkoutView {
    var finishes = 0;
    var queueResult = true;

    function initialize() {
        WorkoutView.initialize();
    }

    function buildFinishWorkoutMessage() { return {}; }

    function finishWorkoutMessage(message) {
        finishes += 1;
        return queueResult;
    }
}

(:test)
function saveCompletionWaitsForCallbackAndIgnoresRepeatedPress(logger as Test.Logger) as Lang.Boolean {
    var view = new SaveFlowTestView();
    view.saveStage = 1;
    view.saveAndExit();
    if (view.finishes != 0 || view.saveStage != 1) { return false; }
    view.continueSaving();
    if (view.finishes != 0 || view.saveStage != 5 || view.saveMessage == null) { return false; }
    view.continueSaving();
    // Cleanup must wait for a later callback, not run recursively in this one.
    return view.finishes == 1 && view.saveStage == 2;
}

(:test)
function failedQueueCompletionReenablesExplicitRetry(logger as Test.Logger) as Lang.Boolean {
    var previousSets = GymStore.sets;
    var previousPrepared = GymStore.preparedWorkout;
    var view = new SaveFlowTestView();
    view.queueResult = false;
    view.saveStage = 1;
    view.continueSaving();
    view.continueSaving();
    return view.finishes == 1 && view.saveStage == 0 &&
        view.saveMessage == null &&
        GymStore.sets == previousSets && GymStore.preparedWorkout == previousPrepared;
}

(:test)
function stagedSaveCannotCompleteAfterAccountBindingIsLost(logger as Test.Logger) as Lang.Boolean {
    var previousAccount = GymStore.accountBinding;
    var previousSets = GymStore.sets;
    var previousPending = GymStore.pending;
    var previousPrepared = GymStore.preparedWorkout;
    GymStore.accountBinding = null;
    var view = new WorkoutView();
    view.saveStage = 5;
    view.saveMessage = {"requestId" => "old-owner-request"};
    view.continueSaving();
    GymStore.accountBinding = previousAccount;
    return view.saveStage == 0 && view.saveMessage == null &&
        GymStore.sets == previousSets && GymStore.pending == previousPending &&
        GymStore.preparedWorkout == previousPrepared;
}

(:test, :compactLegacyState)
function failedFirstCheckpointCannotStartFitRecording(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "checkpoint-start-test";
    GymStore.exercises = ["Bench Press"];
    GymStore.exerciseCatalogNeedsWrite = true;
    GymWorkoutMode.state = GymWorkoutMode.MODE_FREE;
    // An unreadable queue denies selecting a durable bank. The first checkpoint
    // must fail before allocating or starting a FIT recording.
    GymPendingJournal.readable = false;
    var started = GymSession.start();
    var ok = !started && !GymSession.recording && GymSession.session == null &&
        GymSession.startedAt == 0 && (GymStore.status == GymStatus.RECOVERY_FAIL);
    GymStore.clearAccountScopedState();
    LocalWorkoutFixture.reset();
    return ok;
}

(:test, :compactLegacyState)
function boundFreeWorkoutCheckpointsMetricsAndThrottlesWrites(logger as Test.Logger) as Lang.Boolean {
    LocalWorkoutFixture.reset();
    GymStore.clearAccountScopedState();
    GymStore.accountBinding = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    GymStore.stateOwnerBinding = GymStore.accountBinding;
    GymStore.deviceBinding = "periodic-checkpoint-test";
    GymStore.exercises = ["Bench Press"];
    GymStore.exerciseCatalogNeedsWrite = true;
    GymWorkoutMode.state = GymWorkoutMode.MODE_FREE;
    GymSession.startedAt = 1700000000;
    GymSession.paused = false;
    GymSession.elapsedSeconds = 30;
    GymSession.gymCalories = 4.5;
    GymSession.garminCalories = null;
    GymSession.hrSamples = 2;
    GymSession.avgHr = 130;
    GymSession.maxHr = 145;
    GymSession.hr = 140;
    GymSession.zone = 2;
    GymStore.lastRuntimeCheckpointTimerMs = null;
    if (!GymStore.checkpointLiveWorkout(false)) { return false; }
    var first = Toybox.Application.Storage.getValue("activeWorkoutV1");
    GymSession.elapsedSeconds = 31;
    if (!GymStore.checkpointLiveWorkout(false)) { return false; }
    var throttled = Toybox.Application.Storage.getValue("activeWorkoutV1");
    GymStore.lastRuntimeCheckpointTimerMs = Toybox.System.getTimer() - 15001;
    if (!GymStore.checkpointLiveWorkout(false)) { return false; }
    var next = Toybox.Application.Storage.getValue("activeWorkoutV1");
    var ok = first[5] == 0 && first[9][0] == 30 && first[9][1] == 4.5 &&
        first[9][3] == 260 && first[9][4] == 2 && first[9][5] == 145 &&
        throttled[8] == first[8] && next[8] == first[8] + 1 && next[9][0] == 31;
    GymStore.clearAccountScopedState();
    LocalWorkoutFixture.reset();
    return ok;
}
