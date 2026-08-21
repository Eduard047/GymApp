using Toybox.Test as Test;
using Toybox.Lang as Lang;

(:test)
function handlingMotionDoesNotPromote(logger as Test.Logger) as Lang.Boolean {
    GymStore.sets = [];
    GymSession.paused = false;
    GymSession.autoLogPrompt = false;
    GymSession.activeSetSeen = false;
    GymSession.effortState = "REST";
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

(:test)
function rhythmicMotionPromptsAfterQuietWindow(logger as Test.Logger) as Lang.Boolean {
    GymStore.sets = [];
    GymStore.autoPromptEnabled = true;
    GymStore.sensitivityIndex = 1;
    GymSession.paused = false;
    GymSession.autoLogPrompt = false;
    GymSession.activeSetSeen = false;
    GymSession.effortState = "REST";
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
        GymSession.effortState.equals("SET ACTIVE");
    GymSession.elapsedSeconds = 10;
    GymSession.updateMotionLifecycle();
    logger.debug("promoted=" + promoted.toString() +
        " prompt=" + GymSession.autoLogPrompt.toString());
    return promoted && GymSession.autoLogPrompt &&
        GymSession.effortState.equals("REST");
}
