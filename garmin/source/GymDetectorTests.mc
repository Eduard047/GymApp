using Toybox.Test as Test;
using Toybox.Lang as Lang;

(:test, :richWorkoutMode)
function handlingMotionDoesNotPromote(logger as Test.Logger) as Lang.Boolean {
    GymStore.sets = [];
    GymSession.paused = false;
    GymSession.autoLogPrompt = false;
    GymSession.activeSetSeen = false;
    GymSession.effortState = GymSession.EFFORT_REST;
    GymSession.elapsedSeconds = 0;
    GymSession.lastLoggedSetSeconds = -10;
    GymSession.motionBurstSignals = 0;
    GymSession.motionRhythmSignals = 0;
    GymSession.motionReversalCount = 0;
    GymSession.motionBurstStartedSeconds = 0;
    GymSession.clearSetCandidate();
    GymSession.beginSetCandidate(null);
    for (var second = 0; second < 4; second += 1) {
        GymSession.elapsedSeconds = second;
        GymSession.updateMotionBurst(true, true, false, 0);
        GymSession.updateMotionLifecycle();
    }
    logger.debug("handling active=" + GymSession.activeSetSeen.toString());
    return !GymSession.activeSetSeen && !GymSession.autoLogPrompt;
}

(:test, :richWorkoutMode)
function rhythmicMotionPromptsAfterQuietWindow(logger as Test.Logger) as Lang.Boolean {
    GymStore.sets = [];
    GymStore.autoPromptEnabled = true;
    GymStore.sensitivityIndex = 1;
    GymSession.paused = false;
    GymSession.autoLogPrompt = false;
    GymSession.activeSetSeen = false;
    GymSession.effortState = GymSession.EFFORT_REST;
    GymSession.elapsedSeconds = 0;
    GymSession.lastLoggedSetSeconds = -10;
    GymSession.motionBurstSignals = 0;
    GymSession.motionRhythmSignals = 0;
    GymSession.motionReversalCount = 0;
    GymSession.motionBurstStartedSeconds = 0;
    GymSession.clearSetCandidate();
    GymSession.beginSetCandidate(null);
    for (var second = 0; second < 7; second += 1) {
        GymSession.elapsedSeconds = second;
        GymSession.lastCredibleMotionSeconds = second;
        GymSession.updateMotionBurst(true, true, true, 2);
        GymSession.updateMotionLifecycle();
    }
    var promoted = GymSession.activeSetSeen &&
        GymSession.effortState == GymSession.EFFORT_ACTIVE;
    GymSession.elapsedSeconds = 10;
    GymSession.updateMotionLifecycle();
    logger.debug("promoted=" + promoted.toString() +
        " prompt=" + GymSession.autoLogPrompt.toString());
    return promoted && GymSession.autoLogPrompt &&
        GymSession.effortState == GymSession.EFFORT_REST;
}

(:test, :richWorkoutMode)
function candidateZoneOwnershipTransferPreservesCommittedTotals(logger as Test.Logger) as Lang.Boolean {
    GymSession.resetCurrentSetInterval();
    GymSession.clearSetCandidate();
    GymSession.paused = false;
    GymSession.activeSetSeen = false;
    GymSession.elapsedSeconds = 100;
    GymSession.beginSetCandidate(null);
    var firstCandidate = GymSession.candidateZoneSeconds;
    if (!(firstCandidate instanceof Lang.Array) || firstCandidate.size() != 6) {
        return false;
    }
    GymSession.elapsedSeconds = 101;
    GymSession.trackCandidateSetInterval(100, 2);
    GymSession.elapsedSeconds = 102;
    GymSession.trackCandidateSetInterval(101, 4);
    GymSession.activeStartSeconds = GymSession.candidateStartSeconds;
    GymSession.beginSetInterval();
    var committed = GymSession.currentSetZoneSeconds;
    var transferred = GymSession.candidateZoneSeconds == null &&
        committed[2] == 1 && committed[4] == 1;
    if (transferred) {
        firstCandidate[2] = 2;
        transferred = committed[2] == 2;
        firstCandidate[2] = 1;
    }

    GymSession.activeSetSeen = false;
    GymSession.elapsedSeconds = 103;
    GymSession.beginSetCandidate(null);
    var nextCandidate = GymSession.candidateZoneSeconds;
    GymSession.elapsedSeconds = 104;
    GymSession.trackCandidateSetInterval(103, 5);
    var isolated = nextCandidate instanceof Lang.Array &&
        nextCandidate[5] == 1 &&
        GymSession.currentSetZoneSeconds[2] == 1 &&
        committed[2] == 1 && committed[4] == 1 && committed[5] == 0;
    logger.debug("candidate transferred=" + transferred.toString() +
        " next candidate isolated=" + isolated.toString());

    GymSession.resetCurrentSetInterval();
    GymSession.clearSetCandidate();
    GymSession.activeStartSeconds = 0;
    GymSession.activeSetSeen = false;
    GymSession.elapsedSeconds = 0;
    return transferred && isolated;
}

(:test, :compactWorkoutMode96)
function manualSetCapturePreservesHeartRateAndNonnegativeInterval(logger as Test.Logger) as Lang.Boolean {
    GymSession.resetWorkoutMetrics();
    GymSession.elapsedSeconds = 420;
    GymSession.hr = 137;
    GymSession.gymCalories = 18.75;
    GymSession.garminCalories = 22;

    var statistics = GymSession.captureSetStatistics();
    var interval = GymSession.setStatistic(statistics, 7);
    var valid = GymSession.isCapturedStatistics(statistics) &&
        GymSession.setStatistic(statistics, 1) == 420 &&
        GymSession.setStatistic(statistics, 2) == 420 &&
        GymSession.setStatistic(statistics, 3) == 137 &&
        GymSession.setStatistic(statistics, 4) == 137 &&
        interval instanceof Lang.Array && interval.size() == 10 &&
        interval[0] >= 0 && interval[1] >= interval[0] && interval[2] >= 0 &&
        interval[3] == 0;
    logger.debug("manual capture HR=" + GymSession.setStatistic(statistics, 4).toString() +
        " interval=" + interval[0].toString() + ".." + interval[1].toString());
    GymSession.resetWorkoutMetrics();
    return valid;
}
