using Toybox.Attention as Attention;
using Toybox.Graphics as Gfx;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.WatchUi as Ui;

class WorkoutView extends Ui.View {
    var selected = 0;
    // Page 7 is the compact, non-recording launch surface. Opening GymApp must
    // never be interpreted as consent to start a FIT activity or contact a
    // phone/cloud endpoint.
    var page = 7;
    var pauseSelected = 0;
    var discardSelected = 0;
    var settingsSelected = 0;
    var settingsCount = 7;
    var ticker;
    var restWasActive = false;
    var autoPromptWasActive = false;
    var savedSetFlashStartedAt = null;
    var savedSetNumber = 0;
    var lastSyncRequestAt = null;
    var syncRequestInFlight = false;
    var syncRequestTimedOut = false;
    var pendingRetryStartedAt = null;
    var pendingRetryDelayMs = 5000;
    var pendingSendInFlight = false;
    var tutorialActive = false;
    var tutorialStep = 0;
    var screenWidth = 260;
    var screenHeight = 260;

    function initialize() {
        View.initialize();
        ticker = new Timer.Timer();
    }

    (:enhancedRecoveryCheckpoint)
    function onShow() {
        ticker.start(method(:tick), 1000, true);
        if (GymStore.hasPreparedWorkout()) {
            page = 3;
        } else if (GymSession.recording) {
            page = GymSession.paused ? 2 : 0;
            if (!GymSession.paused) {
                GymSession.startSensors();
            }
        } else {
            page = 7;
        }
        selected = 0;
        pauseSelected = 0;
        discardSelected = 0;
        // Mailbox polling is intentionally retained while idle so a bound phone
        // can deliver a plan. The launch path itself sends nothing and starts no
        // recording or sensor; a durable pending workout retries only after the
        // bounded timer in tick().
        getApp().pollMailbox();
        if (page == 7 && GymStore.shouldStartTutorial()) {
            startTutorial();
        }
    }

    (:compactRecovery96)
    function onShow() {
        ticker.start(method(:tick), 1000, true);
        if (GymStore.hasPreparedWorkout()) {
            page = 3;
        } else if (GymSession.recording) {
            page = GymSession.paused ? 2 : 0;
            if (!GymSession.paused) {
                GymSession.startSensors();
            }
        } else {
            page = 7;
        }
        selected = 0;
        getApp().pollMailbox();
        if (page == 7 && GymStore.shouldStartTutorial()) {
            startTutorial();
        }
    }

    function onHide() {
        ticker.stop();
        if (GymSession.recording) {
            if (!GymStore.checkpointLiveWorkout(true)) {
                GymStore.status = "RECOVERY FAIL";
            }
            GymSession.stopSensors();
        }
        GymStore.save();
    }

    function tick() {
        getApp().pollMailbox();
        maybeRetryPending();
        if (syncRequestInFlight && lastSyncRequestAt != null &&
            GymStore.timerElapsedMs(lastSyncRequestAt) > 60000l) {
            // Connect IQ offers no safe cancellation for an outstanding
            // listener. Lock sync until the app is reopened so a missing or
            // late callback can never create overlapping listeners.
            syncRequestInFlight = false;
            syncRequestTimedOut = true;
            GymStore.status = "REOPEN";
        }
        if (page == 7 || !GymSession.recording) {
            Ui.requestUpdate();
            return;
        }
        GymSession.tick();
        var rest = GymStore.restSeconds();
        if (GymStore.restStartedAt != null &&
            GymSession.effortState.equals("SET ACTIVE")) {
            // Freeze rather than destroy the prior rest. A short false detection or
            // explicit BACK rejection can restore it. Store a bounded remaining
            // duration instead of a signed timer deadline so timer rollover is safe.
            var remainingRest = GymStore.restDurationMs.toLong() -
                GymStore.timerElapsedMs(GymStore.restStartedAt);
            GymStore.restDurationMs = remainingRest > 0l ? remainingRest.toNumber() : 0;
            GymStore.restStartedAt = null;
        }
        if (GymStore.restDurationMs > 0 && GymStore.restStartedAt == null) {
            rest = 0;
            restWasActive = false;
            dismissSetSavedFlash();
            GymStore.status = "SET ACTIVE";
        }
        if (GymStore.restDurationMs > 0 && GymStore.restStartedAt == null &&
            !GymSession.activeSetSeen &&
            !GymSession.autoLogPrompt) {
            restoreSuspendedRest();
            rest = GymStore.restSeconds();
        }
        var active = rest > 0;
        if (restWasActive && !active) {
            Attention.vibrate([new Attention.VibeProfile(100, 500), new Attention.VibeProfile(100, 500)]);
            GymStore.status = "REST DONE";
        }
        restWasActive = active;
        if (!autoPromptWasActive && GymSession.autoLogPrompt) {
            page = 0;
            notifyAutoPrompt();
        }
        autoPromptWasActive = GymSession.autoLogPrompt;
        if (!syncRequestInFlight && !syncRequestTimedOut &&
            (lastSyncRequestAt == null ||
            GymStore.timerElapsedMs(lastSyncRequestAt) > 20000l)) {
            requestSyncNow();
        }
        GymStore.checkpointLiveWorkout(false);
        Ui.requestUpdate();
    }

    (:fullLegacyState)
    function notifyAutoPrompt() {
        // A distinct cue asks for confirmation; it never saves a set on the
        // athlete's behalf.
        Attention.vibrate([
            new Attention.VibeProfile(45, 90),
            new Attention.VibeProfile(35, 70),
            new Attention.VibeProfile(45, 90)
        ]);
        GymStore.status = "CONFIRM SET";
    }

    (:compactLegacyState)
    function notifyAutoPrompt() {
        Attention.vibrate([new Attention.VibeProfile(45, 120)]);
        GymStore.status = "CONFIRM SET";
    }

    function requestSyncNow() {
        if (syncRequestInFlight || syncRequestTimedOut) {
            return;
        }
        syncRequestInFlight = true;
        lastSyncRequestAt = System.getTimer();
        GymComm.requestSync(method(:onSyncSent));
    }

    function restoreSuspendedRest() {
        if (GymStore.restDurationMs > 0 && GymStore.restStartedAt == null) {
            GymStore.restStartedAt = System.getTimer();
            restWasActive = true;
            GymStore.status = "REST RESUMED";
        }
    }

    function onSyncSent(ok) {
        if (syncRequestTimedOut) {
            return;
        }
        syncRequestInFlight = false;
        GymStore.status = ok ? "SYNC REQ" : "NO PHONE";
        Ui.requestUpdate();
    }

    (:fullLegacyState)
    function requestCloudSyncNow() {
        GymStore.status = "CLOUD...";
        GymComm.requestCloudPlan(method(:onCloudPlanFetched));
        Ui.requestUpdate();
    }

    (:fullLegacyState)
    function onCloudPlanFetched(ok, status, message) {
        if (ok && message == null) {
            GymStore.status = status;
        } else if (ok && message != null) {
            try {
                var applied = GymStore.applyCloudSync(message);
                if (!applied) {
                    GymStore.status = "CLOUD FAIL";
                } else if (!GymStore.status.equals("PLAN WAIT")) {
                    GymStore.status = status;
                }
                if (applied) {
                    GymComm.acknowledgeCloudPlan(message, method(:onCloudPlanAcknowledged));
                }
            } catch (e) {
                GymStore.status = "CLOUD FAIL";
            }
        } else {
            GymStore.status = status;
        }
        Ui.requestUpdate();
    }

    (:fullLegacyState)
    function onCloudPlanAcknowledged(ok) {
        if (!ok) {
            GymStore.status = "CLOUD RETRY";
        }
        Ui.requestUpdate();
    }

    (:compactLegacyState)
    function requestCloudSyncNow() {
        // Compact 96 KiB watches use the paired phone as the cloud gateway.
        // This keeps the same plan outcome without a second on-watch HTTP stack.
        requestSyncNow();
        GymStore.status = "SYNC REQ";
        Ui.requestUpdate();
    }

    function onWorkoutSent(ok) {
        pendingSendInFlight = false;
        pendingRetryStartedAt = System.getTimer();
        pendingRetryDelayMs = ok ? 20000 : nextRetryDelay();
        if (ok) {
            GymStore.status = "WAITING ACK";
        } else {
            GymStore.status = "QUEUED";
        }
        Ui.requestUpdate();
    }

    function flushPending() {
        if (!GymStore.hasAccountBinding() || GymStore.pending.size() == 0 ||
            pendingSendInFlight) {
            return;
        }
        if (!GymStore.recoverQueuedWorkout()) {
            GymStore.status = "DATA KEPT";
            return;
        }
        pendingSendInFlight = true;
        GymComm.send(GymStore.pending[0], method(:onPendingSent));
    }

    function onPendingSent(ok) {
        // Transport completion is not a database acknowledgement. Keep the
        // item queued until the Android app replies with an explicit ack.
        GymStore.status = ok ? "WAITING ACK" : "OFFLINE";
        pendingSendInFlight = false;
        pendingRetryStartedAt = System.getTimer();
        pendingRetryDelayMs = ok ? 20000 : nextRetryDelay();
        Ui.requestUpdate();
    }

    function nextRetryDelay() {
        var next = pendingRetryDelayMs * 2;
        if (next < 5000) {
            next = 5000;
        } else if (next > 300000) {
            next = 300000;
        }
        return next;
    }

    function maybeRetryPending() {
        if (!GymStore.hasAccountBinding() || GymStore.pending.size() == 0) {
            pendingSendInFlight = false;
            pendingRetryStartedAt = null;
            pendingRetryDelayMs = 5000;
            return;
        }
        if (pendingSendInFlight) {
            return;
        }
        if (pendingRetryStartedAt == null) {
            pendingRetryStartedAt = System.getTimer();
            return;
        }
        if (GymStore.timerElapsedMs(pendingRetryStartedAt) >=
            pendingRetryDelayMs.toLong()) {
            flushPending();
        }
    }

    function hasWorkoutToResume() {
        return GymSession.recording || GymStore.hasUnfinishedWorkout();
    }

    (:enhancedRecoveryCheckpoint)
    function startOrResumeWorkout(usePlan) {
        if (page != 7 || GymSession.fitSaved || GymStore.hasPreparedWorkout()) {
            GymStore.status = "START FAIL";
            Ui.requestUpdate();
            return false;
        }

        var resuming = hasWorkoutToResume();
        var started = false;
        if (GymSession.recording) {
            if (GymSession.paused) {
                started = GymSession.resume();
            } else {
                // A still-running native session may survive a brief app hide. Do
                // not create a second FIT session; re-enable sensors only after the
                // athlete explicitly chooses Resume.
                GymSession.startSensors();
                started = true;
            }
        } else {
            if (!GymWorkoutMode.begin(usePlan)) {
                Ui.requestUpdate();
                return false;
            }
            started = GymSession.start();
        }
        if (!started) {
            if (!resuming) {
                GymWorkoutMode.clear();
            }
            Ui.requestUpdate();
            return false;
        }

        if (resuming) {
            GymStore.markWorkoutResumed();
            GymStore.status = "RESUMED";
        } else {
            GymStore.status = "READY";
        }
        // Commit the zero-set origin immediately. A termination before the first
        // set can then return to an explicit Resume instead of looking fresh.
        if (!GymStore.checkpointLiveWorkout(true)) {
            GymStore.status = "RECOVERY FAIL";
        }
        page = 0;
        autoPromptWasActive = GymSession.autoLogPrompt;
        Ui.requestUpdate();
        return true;
    }

    (:compactRecovery96)
    function startOrResumeWorkout(usePlan) {
        if (page != 7 || GymSession.fitSaved || GymStore.hasPreparedWorkout()) {
            GymStore.status = "START FAIL";
            Ui.requestUpdate();
            return false;
        }
        var resuming = hasWorkoutToResume();
        var started = false;
        if (GymSession.recording) {
            if (GymSession.paused) {
                started = GymSession.resume();
            } else {
                GymSession.startSensors();
                started = true;
            }
        } else {
            if (!GymWorkoutMode.begin(usePlan)) {
                Ui.requestUpdate();
                return false;
            }
            started = GymSession.start();
        }
        if (!started) {
            if (!resuming) {
                GymWorkoutMode.clear();
            }
            Ui.requestUpdate();
            return false;
        }
        if (resuming) {
            GymStore.markWorkoutResumed();
            GymStore.status = "RESUMED";
        } else {
            GymStore.status = "READY";
        }
        // A restored workout is already durable; do not rebuild its entire set
        // history at the memory-sensitive Resume boundary.
        if (!resuming && !GymStore.checkpointLiveWorkout(true)) {
            GymStore.status = "RECOVERY FAIL";
        }
        page = 0;
        autoPromptWasActive = GymSession.autoLogPrompt;
        Ui.requestUpdate();
        return true;
    }

    function syncFromReady() {
        requestSyncNow();
        flushPending();
        if (GymComm.hasCloudDeviceToken()) {
            requestCloudSyncNow();
        }
        Ui.requestUpdate();
    }

    (:richRecovery)
    function finishWorkoutMessage(message) {
        if (GymStore.sets.size() == 0 || !GymStore.hasAccountBinding()) {
            // FIT recording is a watch-local feature. Manual set logging and an
            // authenticated phone binding are required only for GymApp sync.
            return true;
        }
        if (message == null) {
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return false;
        }
        if (!GymStore.queueWorkout(message)) {
            if (!GymStore.status.equals("SYNC FULL") &&
                !GymStore.status.equals("QUEUE FULL")) {
                GymStore.status = "SAVE FAIL";
            }
            Ui.requestUpdate();
            return false;
        }
        // queueWorkout appends durably. Always send the oldest entry so a newly
        // finished P2 cannot overtake an offline P1 already awaiting its ACK.
        GymComm.send(GymStore.pending[0], method(:onWorkoutSent));
        return true;
    }

    (:richRecovery)
    function finishWorkout() {
        return finishWorkoutMessage(GymStore.preparedWorkoutMessage());
    }

    (:compactRecovery96)
    function finishWorkout() {
        if (GymStore.sets.size() == 0 || !GymStore.hasAccountBinding()) {
            return true;
        }
        var message = GymStore.preparedWorkoutFitSaved() ?
            GymStore.preparedWorkoutMessage() :
            GymStore.preparedWorkoutSetsOnlyMessage();
        if (message == null) {
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return false;
        }
        if (!GymStore.queueWorkout(message)) {
            if (!GymStore.status.equals("SYNC FULL") &&
                !GymStore.status.equals("QUEUE FULL")) {
                GymStore.status = "SAVE FAIL";
            }
            Ui.requestUpdate();
            return false;
        }
        GymComm.send(GymStore.pending[0], method(:onWorkoutSent));
        return true;
    }

    (:richRecovery)
    function finishFitRecovery(activityFound) {
        var message = null;
        if (activityFound) {
            if (!GymStore.markPreparedWorkoutFitSaved()) {
                Ui.requestUpdate();
                return false;
            }
            message = GymStore.preparedWorkoutMessage();
        } else {
            message = GymStore.preparedWorkoutSetsOnlyMessage();
        }
        if (!finishWorkoutMessage(message)) {
            Ui.requestUpdate();
            return false;
        }
        if (!GymStore.clearActiveWorkout()) {
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return false;
        }
        Attention.vibrate([new Attention.VibeProfile(80, 250)]);
        System.exit();
    }

    (:richRecovery)
    function fitRecoveryPending() {
        return GymStore.preparedWorkoutNeedsFitDecision() &&
            GymSession.fitOutcomeUnknownAfterRestart();
    }

    (:richRecovery)
    function handleFitRecoveryAction() {
        if (!fitRecoveryPending()) {
            return false;
        }
        if (pauseSelected == 0) {
            System.exit();
        }
        if (discardSelected == 0) {
            // A second explicit ENTER is required for either irreversible
            // interpretation. BACK cancels this confirmation without changing
            // the phase-0 marker, sets, request id, or any FIT state.
            discardSelected = 1;
            GymStore.status = "CONFIRM";
            Ui.requestUpdate();
            return false;
        }
        return finishFitRecovery(pauseSelected == 1);
    }

    (:richRecovery)
    function saveAndExit() {
        if (GymSession.autoLogPrompt || GymSession.activeSetSeen) {
            page = 0;
            Ui.requestUpdate();
            return;
        }
        var needsPhoneSync = GymStore.sets.size() > 0 &&
            GymStore.hasAccountBinding();
        if (needsPhoneSync && !GymStore.prepareWorkoutCommit()) {
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return;
        }
        if (needsPhoneSync && GymStore.preparedWorkoutNeedsFitDecision() &&
            GymSession.fitOutcomeUnknownAfterRestart()) {
            handleFitRecoveryAction();
            return;
        }
        var fitAlreadySaved = GymSession.fitSaved ||
            GymStore.preparedWorkoutFitSaved();
        if (!fitAlreadySaved && !GymSession.stopAndSave()) {
            GymStore.status = "FIT FAIL";
            Ui.requestUpdate();
            return;
        }
        if (needsPhoneSync) {
            if (!GymStore.markPreparedWorkoutFitSaved()) {
                Ui.requestUpdate();
                return;
            }
            if (!finishWorkout()) {
                Ui.requestUpdate();
                return;
            }
        }
        if (!GymStore.clearActiveWorkout()) {
            // Keep the already saved FIT session closed and retry only the local
            // cleanup. Never silently resurrect these sets as a new activity.
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return;
        }
        Attention.vibrate([new Attention.VibeProfile(80, 250)]);
        System.exit();
    }

    // The 96 KiB tier keeps the proven phase-0 behavior and omits the richer
    // post-crash FIT decision UI. This preserves loader headroom on products
    // whose process ceiling is lower than their nominal PRG limit.
    (:compactRecovery96)
    function saveAndExit() {
        if (GymSession.autoLogPrompt || GymSession.activeSetSeen) {
            page = 0;
            Ui.requestUpdate();
            return;
        }
        var needsPhoneSync = GymStore.sets.size() > 0 &&
            GymStore.hasAccountBinding();
        if (needsPhoneSync && !GymStore.prepareWorkoutCommit()) {
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return;
        }
        var fitUnknown = needsPhoneSync &&
            !GymStore.preparedWorkoutFitSaved() &&
            GymSession.fitOutcomeUnknownAfterRestart();
        var fitAlreadySaved = GymSession.fitSaved ||
            GymStore.preparedWorkoutFitSaved();
        if (!fitUnknown && !fitAlreadySaved && !GymSession.stopAndSave()) {
            GymStore.status = "FIT FAIL";
            Ui.requestUpdate();
            return;
        }
        if (needsPhoneSync && !fitUnknown &&
            !GymStore.preparedWorkoutFitSaved() &&
            !GymStore.markPreparedWorkoutFitSaved()) {
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return;
        }
        if (needsPhoneSync && !finishWorkout()) {
            Ui.requestUpdate();
            return;
        }
        if (!GymStore.clearActiveWorkout()) {
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return;
        }
        Attention.vibrate([new Attention.VibeProfile(80, 250)]);
        System.exit();
    }

    (:fullLegacyState)
    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        screenWidth = w;
        screenHeight = h;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        if (page == 7) {
            drawReady(dc, w, h);
        } else if (page == 0) {
            drawDashboard(dc, w, h);
        } else if (page == 1) {
            drawEntry(dc, w, h);
        } else if (page == 2) {
            drawPauseMenu(dc, w, h);
        } else if (page == 3) {
            drawSummary(dc, w, h);
        } else if (page == 4) {
            drawDebug(dc, w, h);
        } else if (page == 5) {
            drawSettings(dc, w, h);
        } else if (page == 6) {
            drawDiscardConfirmation(dc, w, h);
        } else {
            drawDashboard(dc, w, h);
        }
        drawPageDots(dc, w, h);

        if (isUndoOverlayActive()) {
            drawSetSavedOverlay(dc, w, h);
        }
        if (tutorialActive && page == 7) {
            drawTutorialOverlay(dc, w, h);
        }
    }

    // The compact hardware tier includes 156-176 px low-memory products and the
    // 208 px Forerunner/ForeAthlete 55. One button-first layout avoids loading
    // the unused 240/260 px dashboard renderers on either constrained profile.
    (:compactRichRecovery)
    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        screenWidth = w;
        screenHeight = h;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        if (page == 7) {
            drawReady(dc, w, h);
        } else if (page == 0) {
            var rest = GymStore.restSeconds();
            var active = GymSession.effortState.equals("SET ACTIVE");
            var maybe = GymSession.effortState.equals("SET MAYBE");
            drawTinyDashboard(dc, w, h,
                GymSession.hr == null ? "--" : GymSession.hr.toString(),
                rest, active, maybe, dashboardStatusText(rest, active, maybe));
        } else if (page == 1) {
            drawEntry(dc, w, h);
        } else if (page == 2) {
            drawPauseMenu(dc, w, h);
        } else if (page == 3) {
            drawSummary(dc, w, h);
        } else if (page == 4) {
            drawDebug(dc, w, h);
        } else if (page == 5) {
            drawSettings(dc, w, h);
        } else if (page == 6) {
            drawDiscardConfirmation(dc, w, h);
        }
        drawPageDots(dc, w, h);
        if (isUndoOverlayActive()) {
            drawSetSavedOverlay(dc, w, h);
        }
        if (tutorialActive && page == 7) {
            drawTutorialOverlay(dc, w, h);
        }
    }

    (:compactRecovery96)
    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        screenWidth = w;
        screenHeight = h;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        if (page == 7) {
            drawReady(dc, w, h);
        } else if (page == 0) {
            var rest = GymStore.restSeconds();
            var active = GymSession.effortState.equals("SET ACTIVE");
            var maybe = GymSession.effortState.equals("SET MAYBE");
            drawTinyDashboard(dc, w, h,
                GymSession.hr == null ? "--" : GymSession.hr.toString(),
                rest, active, maybe, dashboardStatusText(rest, active, maybe));
        } else if (page == 1) {
            drawEntry(dc, w, h);
        } else if (page == 2) {
            drawPauseMenu(dc, w, h);
        } else if (page == 3) {
            drawSummary(dc, w, h);
        } else if (page == 5) {
            drawSettings(dc, w, h);
        } else if (page == 6) {
            drawDiscardConfirmation(dc, w, h);
        }
        drawPageDots(dc, w, h);
        if (isUndoOverlayActive()) {
            drawSetSavedOverlay(dc, w, h);
        }
        if (tutorialActive && page == 7) {
            drawTutorialOverlay(dc, w, h);
        }
    }

    (:fullLegacyState)
    function readyPlanText() {
        if (GymStore.plan.size() == 0) {
            return GymStore.tr("FREE MODE", "ВІЛЬНИЙ РЕЖИМ", "СВОБ. РЕЖИМ");
        }
        return GymStore.tr("PLAN ", "ПЛАН ", "ПЛАН ") +
            GymStore.plan.size().toString();
    }

    (:fullLegacyState)
    function readyBindingText() {
        return readyStatusText();
    }

    (:fullLegacyState)
    function readyStatusText() {
        var waiting = GymStore.pending.size();
        var current = GymStore.status == null ? "" : GymStore.status.toString();
        if (current.equals("FIT FAIL")) {
            return GymStore.tr("FIT NOT SAVED", "FIT НЕ ЗБЕР.", "FIT НЕ СОХР.");
        } else if (current.equals("START FAIL") || current.equals("REC FAIL") ||
            current.equals("FIT RETRY")) {
            return GymStore.tr("CAN'T START · RETRY", "НЕ СТАРТУЄ · ПОВТОР", "НЕ СТАРТУЕТ · ПОВТОР");
        } else if (current.equals("FIT CHECK")) {
            return GymStore.tr("CHECK FIT · DATA KEPT", "ПЕРЕВІР FIT · ДАНІ Є", "ПРОВЕРЬ FIT · ДАННЫЕ ЕСТЬ");
        } else if (current.equals("SAVE FAIL")) {
            return GymStore.tr("DATA KEPT · RETRY", "ДАНІ Є · ПОВТОР", "ДАННЫЕ ЕСТЬ · ПОВТОР");
        } else if (current.equals("SYNC FULL")) {
            return waiting.toString() + GymStore.tr(" WAITING · FIT SAVED", " ЧЕКАЄ · FIT Є", " ЖДУТ · FIT ЕСТЬ");
        } else if (current.equals("REOPEN")) {
            return GymStore.tr("REOPEN APP", "ПЕРЕЗАПУСК", "ПЕРЕЗАПУСК");
        } else if (current.equals("OFFLINE") || current.equals("NO PHONE")) {
            return GymStore.tr("OFFLINE", "ОФЛАЙН", "ОФЛАЙН") +
                (waiting > 0 ? " · " + waiting.toString() : "");
        }
        if (!GymStore.hasAccountBinding()) {
            return GymStore.tr("NOT PAIRED", "НЕ ПРИВ'ЯЗАНО", "НЕ СОПРЯЖЕНО");
        }
        if (waiting > 0) {
            return waiting.toString() + GymStore.tr(" WAITING · LAST ", " ЧЕКАЄ · ОСТ. ", " ЖДУТ · ПОСЛ. ") +
                GymStore.lastWorkoutSyncText();
        }
        return GymStore.tr("SYNC ", "СИНХ ", "СИНХ ") +
            GymStore.lastWorkoutSyncText();
    }

    (:compactLegacyState)
    function readyStatusText() {
        var current = GymStore.status == null ? "" : GymStore.status.toString();
        if (current.equals("FIT FAIL") || current.equals("FIT CHECK") ||
            current.equals("SAVE FAIL") || current.equals("START FAIL") ||
            current.equals("REC FAIL") || current.equals("FIT RETRY")) {
            return GymStore.tr("DATA KEPT", "ДАНІ Є", "ДАННЫЕ ЕСТЬ");
        } else if (current.equals("REOPEN")) {
            return GymStore.tr("REOPEN APP", "ПЕРЕЗАПУСК", "ПЕРЕЗАПУСК");
        }
        if (!GymStore.hasAccountBinding()) {
            return GymStore.tr("NOT PAIRED", "НЕ ПРИВ'ЯЗ.", "НЕ СОПРЯЖ.");
        }
        if (GymStore.pending.size() > 0) {
            return GymStore.tr("WAITING ", "ЧЕКАЄ ", "ЖДУТ ") +
                GymStore.pending.size().toString();
        }
        return GymStore.tr("SYNC ", "СИНХ ", "СИНХ ") +
            GymStore.lastWorkoutSyncText();
    }

    function readyPrimaryText() {
        if (hasWorkoutToResume()) {
            return GymStore.tr("RESUME WORKOUT", "ПРОДОВЖИТИ", "ПРОДОЛЖИТЬ");
        }
        return GymStore.plan.size() == 0 ?
            GymStore.tr("FREE WORKOUT", "ВІЛЬНЕ ТРЕН.", "СВОБ. ТРЕН.") :
            GymStore.tr("START WORKOUT", "ПОЧАТИ ТРЕН.", "НАЧАТЬ ТРЕН.");
    }

    function readyActionCount() {
        return !hasWorkoutToResume() && GymStore.plan.size() > 0 ? 4 : 3;
    }

    function readyActionText(index) {
        if (hasWorkoutToResume()) {
            if (index == 0) {
                return GymStore.tr("RESUME WORKOUT", "ПРОДОВЖИТИ", "ПРОДОЛЖИТЬ");
            }
        } else if (GymStore.plan.size() > 0) {
            if (index == 0) {
                return GymStore.tr("START PLAN", "ПОЧАТИ ПЛАН", "НАЧАТЬ ПЛАН");
            } else if (index == 1) {
                return GymStore.tr("FREE WORKOUT", "ВІЛЬНЕ ТРЕН.", "СВОБ. ТРЕН.");
            }
            index -= 1;
        } else if (index == 0) {
            return GymStore.tr("FREE WORKOUT", "ВІЛЬНЕ ТРЕН.", "СВОБ. ТРЕН.");
        }
        return index == 1 ?
            GymStore.tr("SYNC PLAN", "СИНХ. ПЛАН", "СИНХ. ПЛАН") :
            GymStore.tr("SETTINGS", "НАЛАШТ.", "НАСТРОЙКИ");
    }

    (:fullLegacyState)
    function drawReady(dc, w, h) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 24), Gfx.FONT_TINY,
            "GYMAPP", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 57), Gfx.FONT_XTINY,
            fitTextWidth(dc, readyPlanText(), Gfx.FONT_XTINY, sr(w, h, 174)),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(GymStore.hasAccountBinding() ? Gfx.COLOR_GREEN :
            Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 79), Gfx.FONT_XTINY,
            fitTextWidth(dc, readyBindingText(), Gfx.FONT_XTINY, sr(w, h, 174)),
            Gfx.TEXT_JUSTIFY_CENTER);

        if (readyActionCount() == 4) {
            for (var i = 0; i < 4; i += 1) {
                drawReadyRow(dc, w, h, i, 91 + (i * 38), readyActionText(i));
            }
        } else {
            for (var j = 0; j < 3; j += 1) {
                drawReadyRow(dc, w, h, j, 106 + (j * 45), readyActionText(j));
            }
        }
    }

    (:compactRichRecovery)
    function drawReady(dc, w, h) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var action = readyActionText(selected);
        var compactFont = w >= 200 ? Gfx.FONT_SMALL : Gfx.FONT_XTINY;
        dc.drawText(w / 2, h / 3, compactFont,
            GymStore.tr("GYMAPP READY", "GYMAPP ГОТОВ", "GYMAPP ГОТОВО"),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2, compactFont,
            action, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, (h * 2) / 3, compactFont,
            fitText(readyStatusText(), 18), Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:compactRecovery96)
    function drawReady(dc, w, h) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();
        var action = readyActionText(selected);
        dc.drawText(w / 2, h / 3, Gfx.FONT_XTINY,
            GymStore.tr("GYMAPP READY", "GYMAPP ГОТОВ", "GYMAPP ГОТОВО"),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2, Gfx.FONT_XTINY,
            action, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, (h * 2) / 3, Gfx.FONT_XTINY,
            fitText(readyStatusText(), 18), Gfx.TEXT_JUSTIFY_CENTER);
    }

    function startTutorial() {
        if (page != 7 || GymStore.hasUnfinishedWorkout() ||
            GymStore.hasPreparedWorkout()) {
            return false;
        }
        tutorialActive = true;
        tutorialStep = 0;
        selected = 0;
        Ui.requestUpdate();
        return true;
    }

    function tutorialNext() {
        if (!tutorialActive) {
            return;
        }
        if (tutorialStep < 2) {
            tutorialStep += 1;
            selected = readyActionCount() == 4 && tutorialStep > 0 ?
                tutorialStep + 1 : tutorialStep;
            return;
        }
        if (GymStore.markTutorialHandled()) {
            tutorialActive = false;
            selected = 0;
            GymStore.status = "READY";
        } else {
            GymStore.status = "SAVE FAIL";
        }
    }

    function tutorialBackOrSkip() {
        if (!tutorialActive) {
            return;
        }
        if (tutorialStep > 0) {
            tutorialStep -= 1;
            selected = readyActionCount() == 4 && tutorialStep > 0 ?
                tutorialStep + 1 : tutorialStep;
            return;
        }
        if (GymStore.markTutorialHandled()) {
            tutorialActive = false;
            selected = 0;
        } else {
            GymStore.status = "SAVE FAIL";
        }
    }

    (:fullLegacyState)
    function drawTutorialOverlay(dc, w, h) {
        var targetY = readyActionCount() == 4 ?
            (tutorialStep == 0 ? 91 : (tutorialStep == 1 ? 167 : 205)) :
            (tutorialStep == 0 ? 106 : (tutorialStep == 1 ? 151 : 196));
        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(sx(w, 42), sy(h, targetY - 5),
            sr(w, h, 176), sr(w, h, 44), sr(w, h, 11));
        dc.drawRoundedRectangle(sx(w, 39), sy(h, targetY - 8),
            sr(w, h, 182), sr(w, h, 50), sr(w, h, 13));
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.fillRoundedRectangle(sx(w, 34), sy(h, 38),
            sr(w, h, 192), sr(w, h, 55), sr(w, h, 10));
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var title = tutorialStep == 0 ?
            GymStore.tr("START OR RESUME", "СТАРТ АБО ДАЛІ", "СТАРТ ИЛИ ДАЛЬШЕ") :
            (tutorialStep == 1 ?
                GymStore.tr("SYNC STATUS", "СТАН СИНХ.", "СТАТУС СИНХ.") :
                GymStore.tr("SETTINGS & HELP", "НАЛАШТ. І ДОПОМОГА", "НАСТРОЙКИ И ПОМОЩЬ"));
        var detail = tutorialStep == 1 && GymStore.pending.size() > 0 ?
            GymStore.pending.size().toString() + GymStore.tr(" WAITING", " ЧЕКАЄ", " ЖДУТ") :
            GymStore.tr("SELECT: NEXT · BACK: SKIP", "ВИБІР: ДАЛІ · НАЗАД: ПРОПУСТИТИ", "ВЫБОР: ДАЛЕЕ · НАЗАД: ПРОПУСТИТЬ");
        dc.drawText(w / 2, sy(h, 48), Gfx.FONT_XTINY,
            fitTextWidth(dc, (tutorialStep + 1).toString() + "/3 " + title,
                Gfx.FONT_XTINY, sr(w, h, 174)),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 70), Gfx.FONT_XTINY,
            fitTextWidth(dc, detail, Gfx.FONT_XTINY, sr(w, h, 174)),
            Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:compactLegacyState)
    function drawTutorialOverlay(dc, w, h) {
        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        dc.drawRectangle(2, (h / 2) - 12, w - 4, 24);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var label = tutorialStep == 0 ?
            GymStore.tr("START", "СТАРТ", "СТАРТ") :
            (tutorialStep == 1 ? GymStore.tr("SYNC", "СИНХ", "СИНХ") :
                GymStore.tr("SETTINGS", "НАЛАШТ", "НАСТР"));
        dc.drawText(w / 2, 2, Gfx.FONT_XTINY,
            (tutorialStep + 1).toString() + "/3 " + label,
            Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullLegacyState)
    function drawReadyRow(dc, w, h, index, baseY, label) {
        var selectedRow = index == selected;
        var actionColor = index == 0 ? Gfx.COLOR_GREEN : Gfx.COLOR_WHITE;
        var left = sx(w, 47);
        var top = sy(h, baseY);
        var width = sr(w, h, 166);
        var height = sr(w, h, 34);
        var radius = sr(w, h, 9);
        if (selectedRow) {
            dc.setColor(actionColor, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(left, top, width, height, radius);
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(actionColor, Gfx.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(left, top, width, height, radius);
        }
        dc.drawText(w / 2, sy(h, baseY + 7), Gfx.FONT_XTINY,
            fitTextWidth(dc, label, Gfx.FONT_XTINY, sr(w, h, 146)),
            Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullLegacyState)
    function drawDashboard(dc, w, h) {
        var hrText = GymSession.hr == null ? "--" : GymSession.hr.toString();
        var rest = GymStore.restSeconds();
        var setActive = GymSession.effortState.equals("SET ACTIVE");
        var setMaybe = GymSession.effortState.equals("SET MAYBE");
        var status = dashboardStatusText(rest, setActive, setMaybe);

        if (isCompactDashboard(w, h)) {
            drawCompactDashboard(dc, w, h, hrText, rest, setActive, setMaybe, status);
            if (GymSession.paused) {
                drawPausedOverlay(dc, w, h);
            }
            return;
        }

        drawHeartIcon(dc, w, h, 130, 14);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 31), Gfx.FONT_TINY, hrText, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 64), Gfx.FONT_SYSTEM_XTINY, "BPM", Gfx.TEXT_JUSTIFY_CENTER);
        drawHeartRateZones(dc, w, h, 92);

        drawDashboardDivider(dc, w, h, 110);
        drawDashboardMetric(dc, w, h, 78, 113,
            GymStore.tr("ELAPSED", "ЧАС", "ВРЕМЯ"), GymSession.elapsedText());
        drawDashboardMetric(dc, w, h, 182, 113,
            GymStore.tr("CALORIES", "ККАЛ", "ККАЛ"), GymStore.totalGymCalories().format("%.1f"));
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(w / 2, sy(h, 113), w / 2, sy(h, 148));
        drawDashboardDivider(dc, w, h, 153);

        drawDashboardSetRow(dc, w, h);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 184), Gfx.FONT_SYSTEM_XTINY, setSummaryText(), Gfx.TEXT_JUSTIFY_CENTER);

        var statusColor = GymSession.autoLogPrompt ? Gfx.COLOR_GREEN :
            (setActive ? Gfx.COLOR_GREEN :
                (setMaybe ? Gfx.COLOR_YELLOW :
                    (rest > 0 ? Gfx.COLOR_GREEN : stateColor(GymSession.effortState))));
        drawDashboardStatusPill(dc, w, h, status, statusColor);

        if (GymSession.paused) {
            drawPausedOverlay(dc, w, h);
        }
    }

    (:fullLegacyState)
    function isCompactDashboard(w, h) {
        return w < 240 || h < 240;
    }

    (:fullLegacyState)
    function isTinyDashboard(w, h) {
        return w < 200 || h < 200;
    }

    (:fullLegacyState)
    function drawCompactDashboard(dc, w, h, hrText, rest, setActive, setMaybe, status) {
        if (isTinyDashboard(w, h)) {
            drawTinyDashboard(dc, w, h, hrText, rest, setActive, setMaybe, status);
            return;
        }

        var centerX = w / 2;
        drawCompactHeartIcon(dc, centerX, 17);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(centerX, 22, Gfx.FONT_TINY, hrText, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(centerX, 49, Gfx.FONT_SYSTEM_XTINY, "BPM", Gfx.TEXT_JUSTIFY_CENTER);
        drawCompactHeartRateZones(dc, w, 67);

        drawCompactDivider(dc, w, 83);
        drawCompactMetric(dc, centerX - 39, 87,
            GymStore.tr("TIME", "ЧАС", "ВРЕМЯ"), GymSession.elapsedText());
        drawCompactMetric(dc, centerX + 39, 87,
            GymStore.tr("KCAL", "ККАЛ", "ККАЛ"), GymStore.totalGymCalories().format("%.1f"));
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(centerX, 87, centerX, 116);
        drawCompactDivider(dc, w, 120);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var setExercise = dashboardSetProgressText() + " | " + GymStore.currentExerciseLabel();
        dc.drawText(centerX, 123, Gfx.FONT_SYSTEM_XTINY,
            fitTextWidth(dc, setExercise, Gfx.FONT_SYSTEM_XTINY, w - 38),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(centerX, 141, Gfx.FONT_SYSTEM_XTINY, setSummaryText(), Gfx.TEXT_JUSTIFY_CENTER);

        var statusColor = GymSession.autoLogPrompt ? Gfx.COLOR_GREEN :
            (setActive ? Gfx.COLOR_GREEN :
                (setMaybe ? Gfx.COLOR_YELLOW :
                    (rest > 0 ? Gfx.COLOR_GREEN : stateColor(GymSession.effortState))));
        var fitted = fitTextWidth(dc, status, Gfx.FONT_SYSTEM_XTINY, w - 82);
        dc.setColor(statusColor, Gfx.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(41, 161, w - 82, 24, 9);
        dc.drawText(centerX, 162, Gfx.FONT_SYSTEM_XTINY, fitted, Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullLegacyState)
    function drawTinyDashboard(dc, w, h, hrText, rest, setActive, setMaybe, status) {
        var centerX = w / 2;
        drawCompactHeartIcon(dc, centerX, 10);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(centerX, 14, Gfx.FONT_XTINY, hrText, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(centerX, 35, Gfx.FONT_SYSTEM_XTINY, "BPM", Gfx.TEXT_JUSTIFY_CENTER);
        drawCompactHeartRateZones(dc, w, 51);

        drawTinyDivider(dc, w, 64);
        drawCompactMetric(dc, centerX - 31, 68,
            GymStore.tr("TIME", "ЧАС", "ВРЕМЯ"), GymSession.elapsedText());
        drawCompactMetric(dc, centerX + 31, 68,
            GymStore.tr("KCAL", "ККАЛ", "ККАЛ"), GymStore.totalGymCalories().format("%.1f"));
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(centerX, 68, centerX, 95);
        drawTinyDivider(dc, w, 99);

        var setExercise = dashboardSetProgressText() + " | " + GymStore.currentExerciseLabel();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(centerX, 103, Gfx.FONT_SYSTEM_XTINY,
            fitTextWidth(dc, setExercise, Gfx.FONT_SYSTEM_XTINY, w - 28),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(centerX, 119, Gfx.FONT_SYSTEM_XTINY, setSummaryText(), Gfx.TEXT_JUSTIFY_CENTER);

        var statusColor = GymSession.autoLogPrompt ? Gfx.COLOR_GREEN :
            (setActive ? Gfx.COLOR_GREEN :
                (setMaybe ? Gfx.COLOR_YELLOW :
                    (rest > 0 ? Gfx.COLOR_GREEN : stateColor(GymSession.effortState))));
        var fitted = fitTextWidth(dc, status, Gfx.FONT_SYSTEM_XTINY, w - 76);
        dc.setColor(statusColor, Gfx.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(38, 137, w - 76, 21, 8);
        dc.drawText(centerX, 137, Gfx.FONT_SYSTEM_XTINY, fitted, Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:compactLegacyState)
    function drawTinyDashboard(dc, w, h, hrText, rest, setActive, setMaybe, status) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 16, Gfx.FONT_XTINY,
            "HR " + hrText + "  Z" + GymSession.zone.toString(),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 48, Gfx.FONT_TINY,
            GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 76, Gfx.FONT_XTINY,
            fitText(GymStore.currentExerciseLabel(), 18),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 100, Gfx.FONT_XTINY,
            GymStore.tr("SETS ", "ПІДХ ", "ПОДХ ") +
                GymStore.sets.size().toString() + "  " + setSummaryText(),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(GymSession.autoLogPrompt || setActive || rest > 0 ?
            Gfx.COLOR_GREEN : (setMaybe ? Gfx.COLOR_YELLOW : Gfx.COLOR_WHITE),
            Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 128, Gfx.FONT_XTINY,
            fitText(status, 18), Gfx.TEXT_JUSTIFY_CENTER);
        if (GymSession.paused) {
            dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
            dc.drawCircle(w / 2, h / 2, (w / 2) - 5);
        }
    }

    (:fullLegacyState)
    function drawCompactHeartIcon(dc, x, y) {
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - 3, y, 3);
        dc.fillCircle(x + 3, y, 3);
        dc.fillPolygon([[x - 6, y], [x + 6, y], [x, y + 9]]);
    }

    (:fullLegacyState)
    function drawCompactHeartRateZones(dc, w, y) {
        var segmentWidth = w < 200 ? 12 : 16;
        var gap = w < 200 ? 2 : 3;
        var totalWidth = (segmentWidth * 5) + (gap * 4);
        var left = (w - totalWidth) / 2;
        for (var i = 1; i <= 5; i += 1) {
            var x = left + ((i - 1) * (segmentWidth + gap));
            dc.setColor(zoneColor(i), Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, segmentWidth, 7, 3);
        }

        var markerZone = GymSession.zone;
        if (markerZone < 1) {
            markerZone = 1;
        } else if (markerZone > 5) {
            markerZone = 5;
        }
        var markerX = left + ((markerZone - 1) * (segmentWidth + gap)) + (segmentWidth / 2);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon([[markerX, y - 5], [markerX - 4, y - 1], [markerX + 4, y - 1]]);
    }

    (:fullLegacyState)
    function drawCompactDivider(dc, w, y) {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(35, y, w - 35, y);
    }

    (:fullLegacyState)
    function drawTinyDivider(dc, w, y) {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(28, y, w - 28, y);
    }

    (:fullLegacyState)
    function drawCompactMetric(dc, x, y, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, Gfx.FONT_SYSTEM_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y + 15, Gfx.FONT_SYSTEM_XTINY, value, Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullLegacyState)
    function drawHeartIcon(dc, w, h, baseX, baseY) {
        var x = sx(w, baseX);
        var y = sy(h, baseY);
        var radius = sr(w, h, 4);
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - radius, y, radius);
        dc.fillCircle(x + radius, y, radius);
        dc.fillPolygon([
            [x - (radius * 2), y],
            [x + (radius * 2), y],
            [x, y + (radius * 3)]
        ]);
    }

    (:fullLegacyState)
    function drawDashboardDivider(dc, w, h, baseY) {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(sx(w, 58), sy(h, baseY), sx(w, 202), sy(h, baseY));
    }

    (:fullLegacyState)
    function drawDashboardMetric(dc, w, h, baseX, baseY, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, baseX), sy(h, baseY), Gfx.FONT_SYSTEM_XTINY,
            label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, baseX), sy(h, baseY + 16), Gfx.FONT_SYSTEM_XTINY,
            value, Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullLegacyState)
    function dashboardSetProgressText() {
        var current = GymStore.sets.size() + 1;
        if (current > GymStore.maxWorkoutSets) {
            current = GymStore.maxWorkoutSets;
        }
        var label = GymStore.tr("SET ", "ПІДХІД ", "ПОДХОД ") + current.toString();
        return label;
    }

    (:fullLegacyState)
    function dashboardSetBadgeText() {
        var current = GymStore.sets.size() + 1;
        if (current > GymStore.maxWorkoutSets) {
            current = GymStore.maxWorkoutSets;
        }
        if (GymStore.plan.size() > 0) {
            return GymStore.completedPlannedSetCount().toString() + "/" +
                GymStore.plan.size().toString();
        }
        return "SET " + current.toString();
    }

    (:fullLegacyState)
    function drawDashboardSetRow(dc, w, h) {
        var badgeLeft = sx(w, 55);
        var badgeTop = sy(h, 159);
        var badgeWidth = sr(w, h, 50);
        var badgeHeight = sr(w, h, 25);
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(badgeLeft, badgeTop, badgeWidth, badgeHeight, sr(w, h, 9));
        dc.drawText(badgeLeft + (badgeWidth / 2), sy(h, 160), Gfx.FONT_SYSTEM_XTINY,
            dashboardSetBadgeText(), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, 112), sy(h, 160), Gfx.FONT_SYSTEM_XTINY,
            fitTextWidth(dc, GymStore.currentExerciseLabel(), Gfx.FONT_SYSTEM_XTINY, sr(w, h, 104)),
            Gfx.TEXT_JUSTIFY_LEFT);
    }

    function countdownText(seconds) {
        var minutes = (seconds / 60).toNumber();
        var remaining = seconds % 60;
        var suffix = remaining < 10 ? "0" + remaining.toString() : remaining.toString();
        return minutes.toString() + ":" + suffix;
    }

    (:fullLegacyState)
    function drawDashboardStatusPill(dc, w, h, label, color) {
        var fitted = fitTextWidth(dc, label, Gfx.FONT_SYSTEM_XTINY, sr(w, h, 122));
        var left = sx(w, 63);
        var top = sy(h, 210);
        var width = sr(w, h, 134);
        var height = sr(w, h, 25);
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(left, top, width, height, sr(w, h, 10));
        dc.drawText(w / 2, sy(h, 210), Gfx.FONT_SYSTEM_XTINY, fitted, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function showSetSavedFlash(number) {
        savedSetNumber = number;
        savedSetFlashStartedAt = System.getTimer();
    }

    function isUndoOverlayActive() {
        return page != 7 && savedSetFlashStartedAt != null &&
            GymStore.timerElapsedMs(savedSetFlashStartedAt) <= GymStore.undoWindowMs &&
            GymStore.canUndoLastSet();
    }

    function dismissSetSavedFlash() {
        savedSetFlashStartedAt = null;
    }

    (:fullLegacyState)
    function drawSetSavedOverlay(dc, w, h) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(w / 2, h / 2, sr(w, h, 124));
        dc.drawText(w / 2, sy(h, 48), Gfx.FONT_SMALL, GymStore.tr("SET", "ПІДХІД", "ПОДХОД"), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, 76), Gfx.FONT_NUMBER_MEDIUM, savedSetNumber.toString(), Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 142), Gfx.FONT_XTINY,
            fitTextWidth(dc,
                GymStore.tr("NEXT: ", "ДАЛІ: ", "ДАЛЬШЕ: ") + GymStore.currentExerciseLabel(),
                Gfx.FONT_XTINY, sr(w, h, 184)),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, 164), Gfx.FONT_XTINY,
            fitTextWidth(dc, setSummaryText(), Gfx.FONT_XTINY, sr(w, h, 184)),
            Gfx.TEXT_JUSTIFY_CENTER);
        var rest = GymStore.restSeconds();
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 188), Gfx.FONT_XTINY,
            GymStore.tr("REST ", "ВІДП ", "ОТДЫХ ") + countdownText(rest),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 216), Gfx.FONT_XTINY, GymStore.tr("TAP / BACK: UNDO", "ТАП / НАЗАД: СКАС", "ТАП / НАЗАД: ОТМЕНА"), Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:compactLegacyState)
    function drawSetSavedOverlay(dc, w, h) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 3, Gfx.FONT_XTINY,
            GymStore.tr("SET SAVED", "ПІДХІД Є", "ПОДХОД ЕСТЬ"),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2, Gfx.FONT_XTINY,
            GymStore.tr("BACK: UNDO", "НАЗАД: СКАС", "НАЗАД: ОТМЕНА"),
            Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullLegacyState)
    function drawPausedOverlay(dc, w, h) {
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(w / 2, h / 2, sr(w, h, 124));
    }

    (:fullLegacyState)
    function drawHeartRateZones(dc, w, h, baseY) {
        var left = sx(w, 62);
        var y = sy(h, baseY);
        var segmentWidth = sr(w, h, 24);
        var gap = sr(w, h, 4);
        for (var i = 1; i <= 5; i += 1) {
            var x = left + ((i - 1) * (segmentWidth + gap));
            dc.setColor(zoneColor(i), Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, segmentWidth, sr(w, h, 9), sr(w, h, 4));
        }

        var markerZone = GymSession.zone;
        if (markerZone < 1) {
            markerZone = 1;
        } else if (markerZone > 5) {
            markerZone = 5;
        }
        var markerX = left + ((markerZone - 1) * (segmentWidth + gap)) + (segmentWidth / 2);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon([[markerX, y - sr(w, h, 6)], [markerX - sr(w, h, 5), y - sr(w, h, 1)], [markerX + sr(w, h, 5), y - sr(w, h, 1)]]);
    }

    (:fullLegacyState)
    function zoneColor(zone) {
        if (zone == 1) {
            return Gfx.COLOR_BLUE;
        } else if (zone == 2) {
            return Gfx.COLOR_GREEN;
        } else if (zone == 3) {
            return Gfx.COLOR_YELLOW;
        } else if (zone == 4) {
            return Gfx.COLOR_ORANGE;
        } else if (zone >= 5) {
            return Gfx.COLOR_RED;
        }
        return Gfx.COLOR_WHITE;
    }

    function stateColor(state) {
        if (state.equals("SET ACTIVE")) {
            return Gfx.COLOR_GREEN;
        } else if (state.equals("SET MAYBE")) {
            return Gfx.COLOR_YELLOW;
        } else if (state.equals("REST")) {
            return Gfx.COLOR_BLUE;
        } else if (state.equals("READY")) {
            return Gfx.COLOR_YELLOW;
        }
        return Gfx.COLOR_LT_GRAY;
    }

    function effortLabel(state) {
        if (!GymStore.isUk() && !GymStore.isRu()) {
            return state;
        }
        if (state.equals("SET ACTIVE")) {
            return GymStore.isRu() ? "ПОДХОД" : "ПІДХІД";
        } else if (state.equals("SET MAYBE")) {
            return GymStore.tr("SET?", "ПІДХ?", "ПОДХ?");
        } else if (state.equals("REST")) {
            return GymStore.isRu() ? "ОТДЫХ" : "ВІДП";
        } else if (state.equals("READY")) {
            return GymStore.isRu() ? "ГОТОВО" : "ГОТОВ";
        } else if (state.equals("WARMUP")) {
            return GymStore.isRu() ? "РАЗМИН" : "РОЗМИН";
        } else if (state.equals("PAUSED")) {
            return "ПАУЗА";
        }
        return state;
    }

    function confidenceLabel() {
        if (GymSession.confidenceLevel.equals("HIGH")) {
            return GymStore.tr("HIGH", "ВИС", "ВЫС");
        } else if (GymSession.confidenceLevel.equals("MED")) {
            return GymStore.tr("MED", "СЕР", "СРЕД");
        }
        return GymStore.tr("LOW", "НИЗ", "НИЗ");
    }

    (:fullLegacyState)
    function dashboardStatusText(rest, setActive, setMaybe) {
        var fault = workoutErrorText();
        if (fault != null) {
            return fault;
        }
        if (GymSession.autoLogPrompt) {
            return GymStore.tr("SAVE/BACK ", "ЗБЕР/НІ ", "СОХР/НЕТ ") +
                GymSession.activeSetText();
        }
        if (setActive) {
            return effortLabel(GymSession.effortState) + " " +
                GymSession.activeSetText() + " " + confidenceLabel();
        }
        if (setMaybe) {
            return effortLabel(GymSession.effortState) + " " + confidenceLabel();
        }
        if (rest > 0) {
            var text = GymStore.tr("REST ", "ВІДП ", "ОТДЫХ ") + countdownText(rest);
            var recovery = GymSession.recoveryHeartRateDrop();
            if (recovery != null) {
                text += " HR-" + recovery.toString();
            }
            return text;
        }
        return effortLabel(GymSession.effortState);
    }

    (:compactLegacyState)
    function dashboardStatusText(rest, setActive, setMaybe) {
        var fault = workoutErrorText();
        if (fault != null) {
            return fault;
        }
        if (GymSession.autoLogPrompt) {
            return GymStore.tr("SAVE/BACK", "ТАК/НІ", "ДА/НЕТ");
        } else if (setActive) {
            return effortLabel(GymSession.effortState) + " " + confidenceLabel();
        } else if (setMaybe) {
            return effortLabel(GymSession.effortState);
        } else if (rest > 0) {
            return GymStore.tr("REST ", "ВІДП ", "ОТДЫХ ") + countdownText(rest);
        }
        return effortLabel(GymSession.effortState);
    }

    function workoutErrorText() {
        var current = GymStore.status == null ? "" : GymStore.status.toString();
        if (current.equals("PAUSE FAIL")) {
            return GymStore.tr("PAUSE FAILED · RETRY", "ПАУЗА НЕ ВДАЛАСЬ", "ПАУЗА НЕ УДАЛАСЬ");
        }
        if (current.equals("RESUME FAIL")) {
            return GymStore.tr("RESUME FAILED · RETRY", "НЕ ВІДНОВЛЕНО", "НЕ ВОЗОБНОВЛЕНО");
        }
        return null;
    }

    (:fullDebugState)
    function motionDebugText() {
        if (!GymSession.motionAvailable) {
            return "--";
        }
        var source = GymSession.gyroAvailable ? "AG " : "A ";
        var text = source + GymSession.motionScore.format("%.0f");
        if (GymSession.gyroAvailable) {
            text += "/" + GymSession.gyroScore.format("%.0f");
        }
        return fitText(text, 10);
    }

    (:fullLegacyState)
    function drawEntry(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 24), Gfx.FONT_XTINY, GymStore.tr("SET ENTRY", "ПІДХІД", "ПОДХОД"), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 50), Gfx.FONT_XTINY, fitTextWidth(dc, GymStore.currentExerciseLabel(), Gfx.FONT_XTINY, sr(w, h, 184)), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, 72), Gfx.FONT_XTINY, setSummaryText(), Gfx.TEXT_JUSTIFY_CENTER);

        drawAdjustRow(dc, w, h, 0, 104, GymStore.tr("EXERCISE", "ВПРАВА", "УПРАЖН"), GymStore.tr("choose", "вибір", "выбор"));
        drawAdjustRow(dc, w, h, 1, 142, GymStore.tr("KG", "КГ", "КГ"), localizedDecimal(GymStore.weight));
        drawAdjustRow(dc, w, h, 2, 180, GymStore.tr("REPS", "ПОВТ", "ПОВТ"), GymStore.reps.toString());
        if (GymStore.canUndoLastSet()) {
            drawAdjustRow(dc, w, h, 3, 218, GymStore.tr("UNDO / SAVE", "СКАС / ЗБЕР", "ОТМ / СОХР"), GymStore.sets.size().toString());
        } else {
            drawRow(dc, w, h, 3, 218, GymStore.tr("SAVE SET", "ЗБЕР ПІДХ", "СОХР ПОДХ"), GymStore.sets.size().toString());
        }
    }

    (:compactLegacyState)
    function drawEntry(dc, w, h) {
        drawHeader(dc, w, h, GymStore.tr("SET ENTRY", "ПІДХІД", "ПОДХОД"));
        var label;
        var value;
        if (selected == 0) {
            label = GymStore.tr("EXERCISE", "ВПРАВА", "УПРАЖН");
            value = GymStore.currentExerciseLabel();
        } else if (selected == 1) {
            label = "KG";
            value = localizedDecimal(GymStore.weight);
        } else if (selected == 2) {
            label = GymStore.tr("REPS", "ПОВТ", "ПОВТ");
            value = GymStore.reps.toString();
        } else {
            label = GymStore.canUndoLastSet() ?
                GymStore.tr("UNDO / SAVE", "СКАС / ЗБЕР", "ОТМ / СОХР") :
                GymStore.tr("SAVE SET", "ЗБЕР ПІДХ", "СОХР ПОДХ");
            value = GymStore.sets.size().toString();
        }
        drawAdjustRow(dc, w, h, selected, 126, label, value);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 192), Gfx.FONT_XTINY, setSummaryText(), Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawPauseMenu(dc, w, h) {
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        drawHeader(dc, w, h, GymStore.tr("PAUSED", "ПАУЗА", "ПАУЗА"));

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 52), Gfx.FONT_SMALL, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);

        drawMenuRow(dc, w, h, 0, 82, GymStore.tr("RESUME", "ДАЛІ", "ПРОДОЛЖ"));
        drawMenuRow(dc, w, h, 1, 126, GymStore.tr("SAVE", "ЗБЕРЕГТИ", "СОХРАНИТЬ"));
        drawMenuRow(dc, w, h, 2, 170, GymStore.tr("DISCARD", "СКАСУВ", "СБРОСИТЬ"));
    }

    (:fullLegacyState)
    function drawDiscardConfirmation(dc, w, h) {
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 34), Gfx.FONT_XTINY, GymStore.tr("DISCARD WORKOUT?", "СКАСУВАТИ?", "СБРОСИТЬ?"), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 64), Gfx.FONT_XTINY, GymStore.tr("SETS + ACTIVITY", "ПІДХОДИ + ЗАПИС", "ПОДХОДЫ + ЗАПИСЬ"), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, 86), Gfx.FONT_XTINY, GymStore.tr("WILL BE LOST", "БУДЕ ВТРАЧЕНО", "БУДУТ УДАЛЕНЫ"), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, 108), Gfx.FONT_XTINY, GymStore.tr("CANNOT BE UNDONE", "НЕ МОЖНА СКАСУВАТИ", "НЕЛЬЗЯ ОТМЕНИТЬ"), Gfx.TEXT_JUSTIFY_CENTER);

        drawDiscardRow(dc, w, h, 0, 144, GymStore.tr("KEEP WORKOUT", "ЗАЛИШИТИ", "ОСТАВИТЬ"), false);
        drawDiscardRow(dc, w, h, 1, 192, GymStore.tr("YES, DISCARD", "ТАК, СКАСУВАТИ", "ДА, СБРОСИТЬ"), true);
    }

    (:compactLegacyState)
    function drawDiscardConfirmation(dc, w, h) {
        drawHeader(dc, w, h, GymStore.tr("DISCARD?", "СКАСУВАТИ?", "СБРОСИТЬ?"));
        drawDiscardRow(dc, w, h, 0, 112, GymStore.tr("KEEP", "ЗАЛИШИТИ", "ОСТАВИТЬ"), false);
        drawDiscardRow(dc, w, h, 1, 166, GymStore.tr("DISCARD", "СКАСУВАТИ", "СБРОСИТЬ"), true);
    }

    (:fullLegacyState)
    function drawSummary(dc, w, h) {
        if (fitRecoveryPending()) {
            drawFitRecoverySummary(dc, w, h);
            return;
        }
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 30), Gfx.FONT_XTINY, GymStore.tr("SUMMARY", "ПІДСУМ", "ИТОГ"), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 54), Gfx.FONT_XTINY, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);
        drawSummaryValue(dc, w, h, 78, 86, "GYM", GymStore.totalGymCalories().format("%.0f"));
        var totalGarminCalories = GymStore.totalGarminCalories();
        var garminKcal = totalGarminCalories == null ? "--" : totalGarminCalories.toString();
        drawSummaryValue(dc, w, h, 182, 86, "GAR", garminKcal);
        drawSummaryValue(dc, w, h, 78, 132, GymStore.tr("AVG", "СЕР", "СРЕД"), GymSession.avgHr.toString());
        drawSummaryValue(dc, w, h, 182, 132, "MAX", GymSession.maxHr.toString());
        drawSummaryValue(dc, w, h, 130, 174, GymStore.tr("SETS", "ПІДХ", "ПОДХ"), GymStore.sets.size().toString());
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 70), Gfx.FONT_XTINY,
            fitTextWidth(dc, readyStatusText(), Gfx.FONT_XTINY, sr(w, h, 184)),
            Gfx.TEXT_JUSTIFY_CENTER);
        drawMenuRow(dc, w, h, 0, 210, GymStore.tr("SAVE & EXIT", "ЗБЕРЕГТИ", "СОХРАНИТЬ"));
    }

    (:compactRichRecovery)
    function drawSummary(dc, w, h) {
        if (fitRecoveryPending()) {
            drawFitRecoverySummary(dc, w, h);
            return;
        }
        drawHeader(dc, w, h, GymStore.tr("SUMMARY", "ПІДСУМ", "ИТОГ"));
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 62), Gfx.FONT_TINY, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, 112), Gfx.FONT_XTINY,
            GymStore.tr("SETS ", "ПІДХ ", "ПОДХ ") + GymStore.sets.size().toString(),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 146), Gfx.FONT_XTINY,
            fitText(readyStatusText(), 18), Gfx.TEXT_JUSTIFY_CENTER);
        // The compact menu helper intentionally centers row zero for the pause
        // screen. Draw the single summary action at its real lower position so
        // it cannot overlap elapsed time on 208 px Forerunner/ForeAthlete 55.
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 190), Gfx.FONT_XTINY,
            "> " + fitText(GymStore.tr("SAVE & EXIT", "ЗБЕРЕГТИ", "СОХРАНИТЬ"), 13),
            Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:compactRecovery96)
    function drawSummary(dc, w, h) {
        drawHeader(dc, w, h, GymStore.tr("SUMMARY", "ПІДСУМ", "ИТОГ"));
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 62), Gfx.FONT_TINY, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, 112), Gfx.FONT_XTINY,
            GymStore.tr("SETS ", "ПІДХ ", "ПОДХ ") + GymStore.sets.size().toString(),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 146), Gfx.FONT_XTINY,
            fitText(readyStatusText(), 18), Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 190), Gfx.FONT_XTINY,
            "> " + fitText(GymStore.tr("SAVE & EXIT", "ЗБЕРЕГТИ", "СОХРАНИТЬ"), 13),
            Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:richRecovery)
    function fitRecoveryActionText() {
        if (discardSelected == 1) {
            return GymStore.tr("ENTER TO CONFIRM", "ENTER: ПІДТВЕРДИТИ", "ENTER: ПОДТВЕРДИТЬ");
        }
        if (pauseSelected == 0) {
            return GymStore.tr("LATER", "ПІЗНІШЕ", "ПОЗЖЕ");
        }
        if (pauseSelected == 1) {
            return GymStore.tr("ACTIVITY FOUND", "ЗАПИС ЗНАЙДЕНО", "ЗАПИСЬ НАЙДЕНА");
        }
        return GymStore.tr("SETS ONLY", "ЛИШЕ ПІДХОДИ", "ТОЛЬКО ПОДХОДЫ");
    }

    (:richRecovery)
    function drawFitRecoverySummary(dc, w, h) {
        drawHeader(dc, w, h, GymStore.tr("FIT CHECK", "ПЕРЕВІРКА FIT", "ПРОВЕРКА FIT"));
        var font = w >= 200 ? Gfx.FONT_SMALL : Gfx.FONT_XTINY;
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 70), Gfx.FONT_XTINY,
            discardSelected == 1 ?
                (pauseSelected == 1 ?
                    GymStore.tr("ACTIVITY EXISTS?", "ЗАПИС ІСНУЄ?", "ЗАПИСЬ ЕСТЬ?") :
                    GymStore.tr("SYNC WITHOUT FIT?", "СИНХ БЕЗ FIT?", "СИНХ БЕЗ FIT?")) :
                GymStore.tr("CHECK GARMIN HISTORY", "ПЕРЕВІРТЕ ІСТОРІЮ", "ПРОВЕРЬТЕ ИСТОРИЮ"),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(pauseSelected == 0 ? Gfx.COLOR_WHITE : Gfx.COLOR_GREEN,
            Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 118), font,
            "> " + fitText(fitRecoveryActionText(), w >= 200 ? 18 : 13),
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 157), Gfx.FONT_XTINY,
            (pauseSelected + 1).toString() + "/3  UP/DOWN",
            Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, 190), Gfx.FONT_XTINY,
            fitText(readyStatusText(), 18), Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullLegacyState)
    function drawSummaryValue(dc, w, h, baseX, baseY, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, baseX), sy(h, baseY), Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, baseX), sy(h, baseY + 16), Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullDebugState)
    function drawDebug(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        drawHeader(dc, w, h, GymStore.tr("DEBUG", "ДЕБАГ", "ОТЛАДКА"));

        // Garmin's XTINY font height differs between product families. Derive the
        // rows from the real font metrics so the header cannot overlap the HR row.
        var lineHeight = dc.getFontHeight(Gfx.FONT_XTINY);
        var lineY = sy(h, 34) + lineHeight + sr(w, h, 4);
        var lineStep = lineHeight + sr(w, h, 1);
        drawDebugLine(dc, w, lineY, "HR", (GymSession.hr == null ? "--" : GymSession.hr.toString()) + " " + GymSession.hrSource);
        lineY += lineStep;
        drawDebugLine(dc, w, lineY, "ACT", GymSession.activityHr == null ? "--" : GymSession.activityHr.toString());
        lineY += lineStep;
        drawDebugLine(dc, w, lineY, "SNS", GymSession.sensorHr == null ? "--" : GymSession.sensorHr.toString());
        lineY += lineStep;
        drawDebugLine(dc, w, lineY, "MOV", motionDebugText());
        lineY += lineStep;
        drawDebugLine(dc, w, lineY, "CONF", GymSession.setConfidence.toString() + "% " + GymSession.confidenceLevel);
        lineY += lineStep;
        drawDebugLine(dc, w, lineY, "ST", fitText(effortLabel(GymSession.effortState), 7));
        lineY += lineStep;
        drawDebugLine(dc, w, lineY, "K/M", GymSession.lastKcalPerMinute.format("%.1f"));
        lineY += lineStep;
        drawDebugLine(dc, w, lineY, GymStore.tr("SYNC", "СИНХ", "СИНХ"), statusLabel(GymStore.status));
    }

    (:compactRichRecovery)
    function drawDebug(dc, w, h) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2, Gfx.FONT_XTINY,
            fitText(GymStore.status, 10), Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:tightFullDebugState)
    function drawDebug(dc, w, h) {
        drawHeader(dc, w, h, GymStore.tr("STATUS", "СТАН", "СТАТУС"));
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2, Gfx.FONT_XTINY,
            fitText(GymStore.status, 12), Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullDebugState)
    function drawDebugLine(dc, w, y, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, 72), y, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, 188), y, Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_RIGHT);
    }

    (:fullLegacyState)
    function drawSettings(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 18), Gfx.FONT_XTINY, GymStore.tr("SETTINGS", "НАЛАШТ", "НАСТРОЙКИ"), Gfx.TEXT_JUSTIFY_CENTER);

        drawSettingsRow(dc, w, h, 0, 43, GymStore.tr("AUTO SET", "АВТО ПІДХ", "АВТО ПОДХ"), GymStore.onOff(GymStore.autoPromptEnabled));
        drawSettingsRow(dc, w, h, 1, 71, GymStore.tr("SENSITIVITY", "ЧУТЛИВІСТЬ", "ЧУВСТВИТ."), GymStore.sensitivityLabel());
        drawSettingsRow(dc, w, h, 2, 99, GymStore.tr("WEIGHT STEP", "КРОК ВАГИ", "ШАГ ВЕСА"), localizedDecimal(GymStore.weightStep));
        drawSettingsRow(dc, w, h, 3, 127, GymStore.tr("REST", "ВІДПОЧИНОК", "ОТДЫХ"), GymStore.restSecondsDefault.toString() + GymStore.tr("s", "с", "с"));
        drawSettingsRow(dc, w, h, 4, 155, GymStore.tr("DEFAULT REPS", "ПОВТ. БАЗА", "ПОВТ. БАЗА"), GymStore.reps.toString());
        drawSettingsRow(dc, w, h, 5, 183, GymStore.tr("CLOUD PLAN", "ПЛАН З ХМАРИ", "ПЛАН ИЗ ОБЛ."), GymStore.tr("SYNC", "СИНХ", "СИНХ"));
        drawSettingsRow(dc, w, h, 6, 211, GymStore.tr("TUTORIAL", "НАВЧАННЯ", "ОБУЧЕНИЕ"), GymStore.tr("OPEN", "ВІДКР", "ОТКР"));
    }

    (:compactLegacyState)
    function drawSettings(dc, w, h) {
        drawHeader(dc, w, h, GymStore.tr("SETTINGS", "НАЛАШТ", "НАСТРОЙКИ"));
        var label;
        var value;
        if (settingsSelected == 0) {
            label = "AUTO";
            value = GymStore.onOff(GymStore.autoPromptEnabled);
        } else if (settingsSelected == 1) {
            label = GymStore.tr("DETECT", "ЧУТЛ", "ЧУВСТ");
            value = GymStore.sensitivityLabel();
        } else if (settingsSelected == 2) {
            label = "KG STEP";
            value = localizedDecimal(GymStore.weightStep);
        } else if (settingsSelected == 3) {
            label = GymStore.tr("REST", "ВІДП", "ОТДЫХ");
            value = GymStore.restSecondsDefault.toString();
        } else if (settingsSelected == 4) {
            label = GymStore.tr("REPS", "ПОВТ", "ПОВТ");
            value = GymStore.reps.toString();
        } else if (settingsSelected == 5) {
            label = GymStore.tr("CLOUD", "ХМАРА", "ОБЛАКО");
            value = GymStore.tr("SYNC", "СИНХ", "СИНХ");
        } else {
            label = GymStore.tr("TUTORIAL", "НАВЧАННЯ", "ОБУЧЕНИЕ");
            value = GymStore.tr("OPEN", "ВІДКР", "ОТКР");
        }
        drawSettingsRow(dc, w, h, settingsSelected, 116, label, value);
    }

    function localizedDecimal(value) {
        var text = value.format("%.1f");
        if ((!GymStore.isUk() && !GymStore.isRu()) || text.length() < 3) {
            return text;
        }
        var length = text.length();
        return text.substring(0, length - 2) + "," + text.substring(length - 1, length);
    }

    function setSummaryText() {
        return localizedDecimal(GymStore.weight) +
            GymStore.tr("kg x ", " кг × ", " кг × ") + GymStore.reps.toString();
    }

    (:fullDebugState)
    function statusLabel(value) {
        var text = value == null ? "" : value.toString();
        if (!GymStore.isUk() && !GymStore.isRu()) {
            return fitText(text, 7);
        }
        if (text.equals("READY")) {
            return GymStore.tr(text, "ГОТОВ", "ГОТОВО");
        } else if (text.equals("RESUMED")) {
            return GymStore.tr(text, "ВІДНОВ", "ВОЗОБН");
        } else if (text.equals("REST DONE")) {
            return GymStore.tr(text, "ВІДП ГОТ", "ОТД ГОТ");
        } else if (text.equals("SET SAVED")) {
            return GymStore.tr(text, "ЗБЕР", "СОХР");
        } else if (text.equals("SET UNDONE")) {
            return GymStore.tr(text, "СКАС", "ОТМЕНА");
        } else if (text.equals("SET ACTIVE")) {
            return GymStore.tr(text, "ПІДХІД", "ПОДХОД");
        } else if (text.equals("CONFIRM SET")) {
            return GymStore.tr("CONFIRM", "ПІДТВ", "ПОДТВ");
        } else if (text.equals("UNDO EXPIRED")) {
            return GymStore.tr(text, "ПІЗНО", "ПОЗДНО");
        } else if (text.equals("SENT")) {
            return GymStore.tr(text, "НАДІСЛ", "ОТПРАВ");
        } else if (text.equals("QUEUED") || text.equals("QUEUED SAFE")) {
            return GymStore.tr(text, "ЧЕРГА", "ОЧЕРЕДЬ");
        } else if (text.equals("WAITING ACK")) {
            return GymStore.tr(text, "ЧЕКАЄ", "ЖДЕМ");
        } else if (text.equals("OFFLINE")) {
            return "ОФЛАЙН";
        } else if (text.equals("NO PHONE")) {
            return GymStore.tr(text, "НЕМА ТЛ", "НЕТ ТЕЛ");
        } else if (text.equals("SYNC REQ") || text.equals("SYNC RX")) {
            return GymStore.tr(text, "СИНХ...", "СИНХ...");
        } else if (text.equals("CLOUD...")) {
            return GymStore.tr(text, "ХМАРА", "ОБЛАКО");
        } else if (text.equals("CLOUD FAIL") || text.equals("CLOUD RETRY")) {
            return GymStore.tr(text, "ПОХМАР", "ОШ ОБЛ");
        }
        return fitText(text, 7);
    }

    (:fullLegacyState)
    function drawSettingsRow(dc, w, h, index, baseY, label, value) {
        var selectedRow = index == settingsSelected;
        var y = sy(h, baseY);
        if (selectedRow) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(sx(w, 36), y - sr(w, h, 2), sr(w, h, 188), sr(w, h, 30), sr(w, h, 8));
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(sx(w, 48), sy(h, baseY + 7), Gfx.FONT_XTINY, fitTextWidth(dc, label, Gfx.FONT_XTINY, sr(w, h, 78)), Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(sx(w, 212), sy(h, baseY + 7), Gfx.FONT_XTINY, fitTextWidth(dc, value, Gfx.FONT_XTINY, sr(w, h, 78)), Gfx.TEXT_JUSTIFY_RIGHT);
    }

    (:compactLegacyState)
    function drawSettingsRow(dc, w, h, index, baseY, label, value) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, (h / 2) - 16, Gfx.FONT_XTINY,
            fitText(label, 16), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, (h / 2) + 12, Gfx.FONT_XTINY,
            fitText(value, 16), Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullLegacyState)
    function drawMenuRow(dc, w, h, index, baseY, label) {
        var y = sy(h, baseY);
        if (index == pauseSelected) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(sx(w, 54), y - sr(w, h, 2), sr(w, h, 152), sr(w, h, 36), sr(w, h, 9));
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(w / 2, sy(h, baseY + 9), Gfx.FONT_XTINY, fitTextWidth(dc, label, Gfx.FONT_XTINY, sr(w, h, 132)), Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:compactLegacyState)
    function drawMenuRow(dc, w, h, index, baseY, label) {
        dc.setColor(index == pauseSelected ? Gfx.COLOR_GREEN : Gfx.COLOR_WHITE,
            Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, (h / 3) + (index * 24), Gfx.FONT_XTINY,
            (index == pauseSelected ? "> " : "  ") + fitText(label, 13),
            Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullLegacyState)
    function drawDiscardRow(dc, w, h, index, baseY, label, destructive) {
        var selectedRow = index == discardSelected;
        var actionColor = destructive ? Gfx.COLOR_RED : Gfx.COLOR_WHITE;
        var y = sy(h, baseY);
        if (selectedRow) {
            dc.setColor(actionColor, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(sx(w, 42), y - sr(w, h, 2), sr(w, h, 176), sr(w, h, 38), sr(w, h, 9));
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(actionColor, Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(w / 2, sy(h, baseY + 9), Gfx.FONT_XTINY, fitTextWidth(dc, label, Gfx.FONT_XTINY, sr(w, h, 152)), Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:compactLegacyState)
    function drawDiscardRow(dc, w, h, index, baseY, label, destructive) {
        dc.setColor(index == discardSelected ?
            (destructive ? Gfx.COLOR_RED : Gfx.COLOR_GREEN) : Gfx.COLOR_WHITE,
            Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, (h / 2) + (index * 28), Gfx.FONT_XTINY,
            (index == discardSelected ? "> " : "  ") + fitText(label, 13),
            Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:fullLegacyState)
    function drawRow(dc, w, h, index, baseY, label, value) {
        var selectedRow = index == selected;
        var y = sy(h, baseY);
        if (selectedRow) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(sx(w, 32), y - sr(w, h, 2), sr(w, h, 196), sr(w, h, 38), sr(w, h, 9));
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(sx(w, 50), sy(h, baseY + 8), Gfx.FONT_XTINY, fitTextWidth(dc, label, Gfx.FONT_XTINY, sr(w, h, 112)), Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(sx(w, 210), sy(h, baseY + 8), Gfx.FONT_XTINY, fitTextWidth(dc, value, Gfx.FONT_XTINY, sr(w, h, 42)), Gfx.TEXT_JUSTIFY_RIGHT);
    }

    (:fullLegacyState)
    function drawAdjustRow(dc, w, h, index, baseY, label, value) {
        var selectedRow = index == selected;
        var y = sy(h, baseY);
        if (selectedRow) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(sx(w, 32), y - sr(w, h, 2), sr(w, h, 196), sr(w, h, 38), sr(w, h, 9));
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(sx(w, 58), sy(h, baseY + 9), Gfx.FONT_XTINY, "-", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, baseY + 9), Gfx.FONT_XTINY, fitTextWidth(dc, label + " " + value, Gfx.FONT_XTINY, sr(w, h, 124)), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(sx(w, 202), sy(h, baseY + 9), Gfx.FONT_XTINY, "+", Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:compactLegacyState)
    function drawAdjustRow(dc, w, h, index, baseY, label, value) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, (h / 2) - 14, Gfx.FONT_XTINY,
            fitText(label, 16), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, (h / 2) + 14, Gfx.FONT_XTINY,
            fitText(value.toString(), 16), Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawHeader(dc, w, h, label) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 34), Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
    }

    (:pageDots)
    function drawPageDots(dc, w, h) {
        if (page == 2 || page == 3) {
            return;
        }
        var dotPage = 0;
        if (page == 0) {
            dotPage = 0;
        } else if (page == 1) {
            dotPage = 1;
        } else if (page == 4) {
            dotPage = 2;
        } else if (page == 5) {
            dotPage = 3;
        } else {
            return;
        }
        var totalWidth = sr(w, h, 50);
        var startX = (w / 2) - (totalWidth / 2);
        var y = page == 0 ?
            (isCompactDashboard(w, h) ?
                (isTinyDashboard(w, h) ? h - 10 : h - 14) :
                sy(h, 244)) : sy(h, 12);
        for (var i = 0; i < 4; i += 1) {
            var x = startX + (i * sr(w, h, 16));
            dc.setColor(i == dotPage ? Gfx.COLOR_WHITE : Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            if (i == dotPage) {
                dc.fillCircle(x, y, sr(w, h, 4));
            } else {
                dc.drawCircle(x, y, sr(w, h, 3));
            }
        }
    }

    (:noPageDots)
    function drawPageDots(dc, w, h) {
        // Compact products keep the same hardware-key navigation without the
        // decorative page indicator. Omitting it preserves the product memory
        // budget for the explicit Ready/Start state and workout safeguards.
    }

    function scale(w, h) {
        var size = w < h ? w : h;
        // Leave a consistent optical safe area around round displays and avoid
        // making the whole interface oversized on high-resolution devices.
        return size.toFloat() / 286.0;
    }

    function sx(w, baseX) {
        return ((w / 2) + ((baseX - 130) * scale(w, screenHeight))).toNumber();
    }

    function sy(h, baseY) {
        return ((h / 2) + ((baseY - 130) * scale(screenWidth, h))).toNumber();
    }

    function sr(w, h, value) {
        var scaled = value * scale(w, h);
        if (scaled < 1) {
            return 1;
        }
        return scaled.toNumber();
    }

    function fitText(text, maxLen) {
        if (text == null) {
            return "";
        }
        if (text.length() <= maxLen) {
            return text;
        }
        return text.substring(0, maxLen - 3) + "...";
    }

    function fitTextWidth(dc, text, font, maxWidth) {
        if (text == null) {
            return "";
        }
        var value = text.toString();
        if (dc.getTextWidthInPixels(value, font) <= maxWidth) {
            return value;
        }
        while (value.length() > 3) {
            value = value.substring(0, value.length() - 1);
            var candidate = value + "...";
            if (dc.getTextWidthInPixels(candidate, font) <= maxWidth) {
                return candidate;
            }
        }
        return "...";
    }
}

class WorkoutDelegate extends Ui.BehaviorDelegate {
    var view;

    function initialize(workoutView) {
        BehaviorDelegate.initialize();
        view = workoutView;
    }

    function hasPendingSetPrompt() {
        return view.page != 7 && GymSession.autoLogPrompt;
    }

    function exitReady() {
        System.exit();
    }

    function onSelect() {
        if (view.tutorialActive) {
            view.tutorialNext();
        } else if (view.page == 7) {
            handleReadySelection();
        } else if (view.isUndoOverlayActive()) {
            view.dismissSetSavedFlash();
        } else if (hasPendingSetPrompt()) {
            recordSet();
        } else if (view.page == 3) {
            view.saveAndExit();
        } else if (view.page == 2) {
            handlePauseMenu();
        } else if (view.page == 6) {
            handleDiscardConfirmation();
        } else if (view.page == 5) {
            handleSettings(1);
        } else if (view.page == 4) {
            view.page = 0;
        } else if (view.page == 0) {
            view.page = 1;
        } else {
            handleSelect();
        }
        Ui.requestUpdate();
        return true;
    }

    (:richRecoveryNavigation)
    function onNextPage() {
        if (view.tutorialActive) {
            view.tutorialNext();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 7) {
            view.selected = (view.selected + 1) % view.readyActionCount();
            Ui.requestUpdate();
            return true;
        }
        if (view.isUndoOverlayActive()) {
            return true;
        }
        if (hasPendingSetPrompt()) {
            return true;
        }
        if (view.page == 3 && view.fitRecoveryPending()) {
            moveFitRecovery(1);
        } else if (view.page == 2) {
            view.pauseSelected = (view.pauseSelected + 1) % 3;
        } else if (view.page == 6) {
            moveDiscardSelection(1);
        } else if (view.page == 1) {
            view.selected = (view.selected + 1) % 4;
        } else if (view.page == 5) {
            view.settingsSelected = (view.settingsSelected + 1) % view.settingsCount;
        } else if (view.page == 0) {
            view.page = 1;
        } else if (view.page == 4) {
            view.page = 5;
        } else {
            view.page = 0;
        }
        Ui.requestUpdate();
        return true;
    }

    (:compactRecovery96)
    function onNextPage() {
        if (view.tutorialActive) {
            view.tutorialNext();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 7) {
            view.selected = (view.selected + 1) % view.readyActionCount();
            Ui.requestUpdate();
            return true;
        }
        if (view.isUndoOverlayActive() || hasPendingSetPrompt()) {
            return true;
        }
        if (view.page == 2) {
            view.pauseSelected = (view.pauseSelected + 1) % 3;
        } else if (view.page == 6) {
            moveDiscardSelection(1);
        } else if (view.page == 1) {
            view.selected = (view.selected + 1) % 4;
        } else if (view.page == 5) {
            view.settingsSelected = (view.settingsSelected + 1) % view.settingsCount;
        } else if (view.page == 0) {
            view.page = 1;
        } else if (view.page == 4) {
            view.page = 5;
        } else {
            view.page = 0;
        }
        Ui.requestUpdate();
        return true;
    }

    (:richRecoveryNavigation)
    function onPreviousPage() {
        if (view.tutorialActive) {
            view.tutorialBackOrSkip();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 7) {
            view.selected = (view.selected + view.readyActionCount() - 1) %
                view.readyActionCount();
            Ui.requestUpdate();
            return true;
        }
        if (view.isUndoOverlayActive()) {
            return true;
        }
        if (hasPendingSetPrompt()) {
            return true;
        }
        if (view.page == 3 && view.fitRecoveryPending()) {
            moveFitRecovery(-1);
        } else if (view.page == 3) {
            if (GymStore.preparedWorkoutFitSaved()) {
                GymStore.status = "FIT SAVED";
                Ui.requestUpdate();
                return true;
            }
            view.page = 2;
        } else if (view.page == 2) {
            view.pauseSelected = (view.pauseSelected + 2) % 3;
        } else if (view.page == 6) {
            moveDiscardSelection(-1);
        } else if (view.page == 1) {
            view.selected = (view.selected + 3) % 4;
        } else if (view.page == 4) {
            view.page = 1;
        } else if (view.page == 5) {
            view.settingsSelected = (view.settingsSelected + view.settingsCount - 1) % view.settingsCount;
        } else {
            view.page = 5;
        }
        Ui.requestUpdate();
        return true;
    }

    (:compactRecovery96)
    function onPreviousPage() {
        if (view.tutorialActive) {
            view.tutorialBackOrSkip();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 7) {
            view.selected = (view.selected + view.readyActionCount() - 1) %
                view.readyActionCount();
            Ui.requestUpdate();
            return true;
        }
        if (view.isUndoOverlayActive() || hasPendingSetPrompt()) {
            return true;
        }
        if (view.page == 3) {
            if (GymStore.preparedWorkoutFitSaved()) {
                GymStore.status = "FIT SAVED";
                Ui.requestUpdate();
                return true;
            }
            view.page = 2;
        } else if (view.page == 2) {
            view.pauseSelected = (view.pauseSelected + 2) % 3;
        } else if (view.page == 6) {
            moveDiscardSelection(-1);
        } else if (view.page == 1) {
            view.selected = (view.selected + 3) % 4;
        } else if (view.page == 4) {
            view.page = 1;
        } else if (view.page == 5) {
            view.settingsSelected = (view.settingsSelected + view.settingsCount - 1) % view.settingsCount;
        } else {
            view.page = 5;
        }
        Ui.requestUpdate();
        return true;
    }

    (:fullLegacyState)
    function onNextMode() {
        if (view.page == 7) {
            return onNextPage();
        }
        if (view.page == 3 && view.fitRecoveryPending()) {
            return onNextPage();
        }
        if (view.isUndoOverlayActive()) {
            return true;
        }
        if (hasPendingSetPrompt()) {
            return true;
        }
        if (view.page == 6) {
            moveDiscardSelection(1);
        } else {
            navigateContent(1);
        }
        Ui.requestUpdate();
        return true;
    }

    (:fullLegacyState)
    function onPreviousMode() {
        if (view.page == 7) {
            return onPreviousPage();
        }
        if (view.page == 3 && view.fitRecoveryPending()) {
            return onPreviousPage();
        }
        if (view.isUndoOverlayActive()) {
            return true;
        }
        if (hasPendingSetPrompt()) {
            return true;
        }
        if (view.page == 6) {
            moveDiscardSelection(-1);
        } else {
            navigateContent(-1);
        }
        Ui.requestUpdate();
        return true;
    }

    (:richRecoveryNavigation)
    function onMenu() {
        if (view.tutorialActive) {
            view.tutorialBackOrSkip();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 7) {
            openReadySettings();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 3 && view.fitRecoveryPending()) {
            deferOrCancelFitRecovery();
            Ui.requestUpdate();
            return true;
        }
        if (view.isUndoOverlayActive()) {
            return true;
        }
        if (hasPendingSetPrompt()) {
            return true;
        }
        if (view.page == 6) {
            cancelDiscardConfirmation();
        } else {
            openPauseMenu();
        }
        Ui.requestUpdate();
        return true;
    }

    (:compactRecovery96)
    function onMenu() {
        if (view.tutorialActive) {
            view.tutorialBackOrSkip();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 7) {
            openReadySettings();
            Ui.requestUpdate();
            return true;
        }
        if (view.isUndoOverlayActive() || hasPendingSetPrompt()) {
            return true;
        }
        if (view.page == 6) {
            cancelDiscardConfirmation();
        } else {
            openPauseMenu();
        }
        Ui.requestUpdate();
        return true;
    }

    (:richRecoveryNavigation)
    function onBack() {
        // Back is an undo action only while the five-second confirmation is
        // visibly active. After it disappears, Back returns to navigation.
        if (view.tutorialActive) {
            view.tutorialBackOrSkip();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 7) {
            exitReady();
            return true;
        }
        if (view.page == 3 && view.fitRecoveryPending()) {
            deferOrCancelFitRecovery();
            Ui.requestUpdate();
            return true;
        }
        if (view.isUndoOverlayActive()) {
            undoLastSet();
            Ui.requestUpdate();
            return true;
        }
        if (hasPendingSetPrompt()) {
            rejectSetPrompt();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 6) {
            cancelDiscardConfirmation();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 3) {
            if (GymStore.preparedWorkoutFitSaved()) {
                GymStore.status = "FIT SAVED";
                Ui.requestUpdate();
                return true;
            }
            view.page = 2;
            view.pauseSelected = 1;
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 2) {
            view.page = 0;
            view.pauseSelected = 0;
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 5 && !GymSession.recording) {
            view.page = 7;
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 1 || view.page == 4 || view.page == 5) {
            view.page = 0;
            Ui.requestUpdate();
            return true;
        }
        openPauseMenu();
        Ui.requestUpdate();
        return true;
    }

    (:compactRecovery96)
    function onBack() {
        if (view.tutorialActive) {
            view.tutorialBackOrSkip();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 7) {
            exitReady();
            return true;
        }
        if (view.isUndoOverlayActive()) {
            undoLastSet();
            Ui.requestUpdate();
            return true;
        }
        if (hasPendingSetPrompt()) {
            rejectSetPrompt();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 6) {
            cancelDiscardConfirmation();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 3) {
            if (GymStore.preparedWorkoutFitSaved()) {
                GymStore.status = "FIT SAVED";
                Ui.requestUpdate();
                return true;
            }
            view.page = 2;
            view.pauseSelected = 1;
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 2) {
            view.page = 0;
            view.pauseSelected = 0;
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 5 && !GymSession.recording) {
            view.page = 7;
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 1 || view.page == 4 || view.page == 5) {
            view.page = 0;
            Ui.requestUpdate();
            return true;
        }
        openPauseMenu();
        Ui.requestUpdate();
        return true;
    }

    (:fullLegacyState)
    function onTap(evt) {
        var coordinates = evt.getCoordinates();
        var x = coordinates[0];
        var y = coordinates[1];
        if (view.tutorialActive) {
            view.tutorialNext();
        } else if (view.page == 7) {
            var readyRow = view.readyActionCount() == 4 ?
                rowAt(y, 91, 38, 4) : rowAt(y, 106, 45, 3);
            if (readyRow >= 0) {
                view.selected = readyRow;
                handleReadySelection();
            }
        } else if (view.isUndoOverlayActive()) {
            if (y >= ((view.screenHeight * 62) / 100)) {
                undoLastSet();
            } else {
                view.dismissSetSavedFlash();
            }
        } else if (hasPendingSetPrompt()) {
            recordSet();
        } else if (view.page == 3) {
            if (rowAt(y, 210, 44, 1) == 0) {
                view.saveAndExit();
            }
        } else if (view.page == 6) {
            var discardRow = rowAt(y, 144, 48, 2);
            if (discardRow >= 0) {
                view.discardSelected = discardRow;
                handleDiscardConfirmation();
            }
        } else if (view.page == 2) {
            var pauseRow = rowAt(y, 82, 44, 3);
            if (pauseRow >= 0) {
                view.pauseSelected = pauseRow;
                handlePauseMenu();
            }
        } else if (view.page == 5) {
            var settingsRow = rowAt(y, 43, 28, view.settingsCount);
            if (settingsRow >= 0) {
                view.settingsSelected = settingsRow;
                handleSettings(x < (view.screenWidth / 2) ? -1 : 1);
            }
        } else if (view.page == 4) {
            view.page = 0;
        } else if (view.page == 0) {
            view.page = 1;
        } else {
            var entryRow = rowAt(y, 104, 38, 4);
            if (entryRow >= 0) {
                view.selected = entryRow;
                if (entryRow == 3) {
                    if (x < (view.screenWidth / 2)) {
                        undoLastSet();
                    } else {
                        recordSet();
                    }
                } else {
                    activate(x < (view.screenWidth / 2) ? -1 : 1);
                }
            }
        }
        Ui.requestUpdate();
        return true;
    }

    (:fullLegacyState)
    function rowAt(y, firstBaseY, step, count) {
        var contentSize = view.screenWidth < view.screenHeight ? view.screenWidth : view.screenHeight;
        var contentScale = contentSize.toFloat() / 286.0;
        var baselineY = 130.0 + ((y - (view.screenHeight / 2)) / contentScale);
        var half = step.toFloat() / 2.0;
        for (var index = 0; index < count; index += 1) {
            var center = firstBaseY + (index * step) + (step / 2);
            if (baselineY >= center - half && baselineY < center + half) {
                return index;
            }
        }
        return -1;
    }

    (:fullLegacyState)
    function onSwipe(evt) {
        var direction = evt.getDirection();
        if (view.page == 7) {
            if (direction == Ui.SWIPE_UP) {
                return onNextPage();
            } else if (direction == Ui.SWIPE_DOWN) {
                return onPreviousPage();
            } else if (direction == Ui.SWIPE_RIGHT) {
                return onBack();
            }
            return true;
        }
        if (view.isUndoOverlayActive()) {
            // The platform Back gesture keeps its documented undo behavior. Other
            // swipes cannot mutate the obscured page or selected row.
            return direction == Ui.SWIPE_RIGHT ? onBack() : true;
        }
        if (hasPendingSetPrompt()) {
            return direction == Ui.SWIPE_RIGHT ? onBack() : true;
        }
        if (direction == Ui.SWIPE_UP) {
            return onNextPage();
        } else if (direction == Ui.SWIPE_DOWN) {
            return onPreviousPage();
        } else if (direction == Ui.SWIPE_LEFT) {
            return onNextMode();
        } else if (direction == Ui.SWIPE_RIGHT) {
            return onBack();
        }
        return false;
    }

    (:richRecoveryNavigation)
    function onKey(evt) {
        var key = evt.getKey();
        if (view.page == 7) {
            if (key == Ui.KEY_UP || key == Ui.KEY_LEFT) {
                return onPreviousPage();
            } else if (key == Ui.KEY_DOWN || key == Ui.KEY_RIGHT) {
                return onNextPage();
            } else if (key == Ui.KEY_ENTER || key == Ui.KEY_START) {
                return onSelect();
            } else if (key == Ui.KEY_ESC || key == Ui.KEY_LAP) {
                return onBack();
            } else if (key == Ui.KEY_MENU) {
                return onMenu();
            }
            return true;
        }
        if (view.isUndoOverlayActive()) {
            if (key == Ui.KEY_ESC || key == Ui.KEY_LAP) {
                return onBack();
            } else if (key == Ui.KEY_ENTER || key == Ui.KEY_START) {
                return onSelect();
            }
            // Consume arrows, page keys, and Menu while the confirmation covers
            // their target. In particular RIGHT on the hidden SAVE row must not
            // record a second set.
            return true;
        }
        if (hasPendingSetPrompt()) {
            if (key == Ui.KEY_ESC || key == Ui.KEY_LAP) {
                return onBack();
            } else if (key == Ui.KEY_ENTER || key == Ui.KEY_START) {
                return onSelect();
            }
            return true;
        }
        if (key == Ui.KEY_UP) {
            return onPreviousPage();
        } else if (key == Ui.KEY_DOWN) {
            return onNextPage();
        } else if (key == Ui.KEY_LEFT) {
            if (view.page == 1) {
                activate(-1);
            } else if (view.page == 5) {
                handleSettings(-1);
            } else if (view.page == 6) {
                moveDiscardSelection(-1);
            } else if (view.page == 3 && view.fitRecoveryPending()) {
                moveFitRecovery(-1);
            } else {
                navigateContent(-1);
            }
        } else if (key == Ui.KEY_RIGHT) {
            if (view.page == 1) {
                activate(1);
            } else if (view.page == 5) {
                handleSettings(1);
            } else if (view.page == 6) {
                moveDiscardSelection(1);
            } else if (view.page == 3 && view.fitRecoveryPending()) {
                moveFitRecovery(1);
            } else {
                navigateContent(1);
            }
        } else if (key == Ui.KEY_ENTER || key == Ui.KEY_START) {
            return onSelect();
        } else if (key == Ui.KEY_ESC || key == Ui.KEY_LAP) {
            return onBack();
        } else if (key == Ui.KEY_MENU) {
            return onMenu();
        } else {
            return false;
        }
        Ui.requestUpdate();
        return true;
    }

    (:compactRecovery96)
    function onKey(evt) {
        var key = evt.getKey();
        if (view.page == 7) {
            if (key == Ui.KEY_UP || key == Ui.KEY_LEFT) {
                return onPreviousPage();
            } else if (key == Ui.KEY_DOWN || key == Ui.KEY_RIGHT) {
                return onNextPage();
            } else if (key == Ui.KEY_ENTER || key == Ui.KEY_START) {
                return onSelect();
            } else if (key == Ui.KEY_ESC || key == Ui.KEY_LAP) {
                return onBack();
            } else if (key == Ui.KEY_MENU) {
                return onMenu();
            }
            return true;
        }
        if (view.isUndoOverlayActive()) {
            if (key == Ui.KEY_ESC || key == Ui.KEY_LAP) {
                return onBack();
            } else if (key == Ui.KEY_ENTER || key == Ui.KEY_START) {
                return onSelect();
            }
            return true;
        }
        if (hasPendingSetPrompt()) {
            if (key == Ui.KEY_ESC || key == Ui.KEY_LAP) {
                return onBack();
            } else if (key == Ui.KEY_ENTER || key == Ui.KEY_START) {
                return onSelect();
            }
            return true;
        }
        if (key == Ui.KEY_UP) {
            return onPreviousPage();
        } else if (key == Ui.KEY_DOWN) {
            return onNextPage();
        } else if (key == Ui.KEY_LEFT) {
            if (view.page == 1) {
                activate(-1);
            } else if (view.page == 5) {
                handleSettings(-1);
            } else if (view.page == 6) {
                moveDiscardSelection(-1);
            } else {
                navigateContent(-1);
            }
        } else if (key == Ui.KEY_RIGHT) {
            if (view.page == 1) {
                activate(1);
            } else if (view.page == 5) {
                handleSettings(1);
            } else if (view.page == 6) {
                moveDiscardSelection(1);
            } else {
                navigateContent(1);
            }
        } else if (key == Ui.KEY_ENTER || key == Ui.KEY_START) {
            return onSelect();
        } else if (key == Ui.KEY_ESC || key == Ui.KEY_LAP) {
            return onBack();
        } else if (key == Ui.KEY_MENU) {
            return onMenu();
        } else {
            return false;
        }
        Ui.requestUpdate();
        return true;
    }

    function handleSelect() {
        if (view.page == 0) {
            view.page = 1;
        } else if (view.page == 5) {
            handleSettings(1);
        } else if (view.page == 4) {
            view.page = 0;
        } else {
            activate(1);
        }
    }

    (:richRecovery)
    function moveFitRecovery(delta) {
        if (view.discardSelected == 0) {
            view.pauseSelected = (view.pauseSelected + delta) % 3;
            if (view.pauseSelected < 0) {
                view.pauseSelected += 3;
            }
        }
    }

    (:richRecovery)
    function deferOrCancelFitRecovery() {
        if (view.discardSelected == 1) {
            view.discardSelected = 0;
            GymStore.status = "FIT CHECK";
            return;
        }
        // LATER is deliberately non-mutating. onStop() persists the same phase-0
        // marker and all sets so the decision reappears on the next launch.
        System.exit();
    }

    function handleReadySelection() {
        var resuming = view.hasWorkoutToResume();
        var hasPlanChoice = !resuming && GymStore.plan.size() > 0;
        if (view.selected == 0) {
            view.startOrResumeWorkout(hasPlanChoice);
        } else if (hasPlanChoice && view.selected == 1) {
            view.startOrResumeWorkout(false);
        } else if (view.selected == (hasPlanChoice ? 2 : 1)) {
            view.syncFromReady();
        } else {
            openReadySettings();
        }
    }

    function openReadySettings() {
        view.settingsSelected = 0;
        view.page = 5;
    }

    (:enhancedRecoveryCheckpoint)
    function openPauseMenu() {
        if (!GymSession.paused && !GymSession.pause()) {
            Ui.requestUpdate();
            return;
        }
        if (!GymStore.checkpointLiveWorkout(true)) {
            GymStore.status = "RECOVERY FAIL";
        }
        view.pauseSelected = 0;
        view.page = 2;
    }

    (:compactRecovery96)
    function openPauseMenu() {
        if (!GymSession.paused && !GymSession.pause()) {
            Ui.requestUpdate();
            return;
        }
        if (!GymStore.checkpointLiveWorkout(true)) {
            GymStore.status = "RECOVERY FAIL";
        }
        view.pauseSelected = 0;
        view.page = 2;
    }

    (:richRecoveryNavigation)
    function navigateContent(delta) {
        if (view.page == 2 || view.page == 3 || view.page == 6) {
            return;
        }
        if (delta > 0) {
            if (view.page == 0) {
                view.page = 1;
            } else if (view.page == 1) {
                view.page = 4;
            } else if (view.page == 4) {
                view.page = 5;
            } else {
                view.page = 0;
            }
        } else if (view.page == 0) {
            view.page = 5;
        } else if (view.page == 5) {
            view.page = 4;
        } else if (view.page == 4) {
            view.page = 1;
        } else {
            view.page = 0;
        }
    }

    (:compactRecovery96)
    function navigateContent(delta) {
        if (view.page == 2 || view.page == 3 || view.page == 6) {
            return;
        }
        if (delta > 0) {
            if (view.page == 0) {
                view.page = 1;
            } else if (view.page == 1) {
                view.page = 5;
            } else {
                view.page = 0;
            }
        } else if (view.page == 0) {
            view.page = 5;
        } else if (view.page == 5) {
            view.page = 1;
        } else {
            view.page = 0;
        }
    }

    function handlePauseMenu() {
        if (view.pauseSelected == 0) {
            if (GymSession.resume()) {
                view.page = 0;
            }
        } else if (view.pauseSelected == 1) {
            view.page = 3;
        } else {
            openDiscardConfirmation();
        }
    }

    function openDiscardConfirmation() {
        // The safe action is always focused first, regardless of how DISCARD was reached.
        view.discardSelected = 0;
        view.page = 6;
    }

    function cancelDiscardConfirmation() {
        view.discardSelected = 0;
        view.pauseSelected = 0;
        view.page = 2;
    }

    function moveDiscardSelection(delta) {
        if (delta != 0) {
            view.discardSelected = view.discardSelected == 0 ? 1 : 0;
        }
    }

    function handleDiscardConfirmation() {
        if (view.discardSelected == 0) {
            cancelDiscardConfirmation();
            return;
        }
        if (!GymSession.discard()) {
            Ui.requestUpdate();
            return;
        }
        if (!GymStore.clearWorkout()) {
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return;
        }
        System.exit();
    }

    function activate(delta) {
        if (view.isUndoOverlayActive()) {
            return;
        }
        if (view.selected == 0) {
            GymStore.nextExercise(delta);
        } else if (view.selected == 1) {
            GymStore.weight += GymStore.weightStep * delta;
            if (GymStore.weight < 0.0) {
                GymStore.weight = 0.0;
            } else if (GymStore.weight > GymStore.maxWeight) {
                GymStore.weight = GymStore.maxWeight;
            }
        } else if (view.selected == 2) {
            GymStore.reps += delta;
            if (GymStore.reps < 1) {
                GymStore.reps = 1;
            } else if (GymStore.reps > GymStore.maxReps) {
                GymStore.reps = GymStore.maxReps;
            }
        } else if (view.selected == 3) {
            if (delta < 0) {
                undoLastSet();
            } else {
                recordSet();
            }
            // addSet()/undoLastSet() own their atomic commit and compatibility
            // save. A second save here used to serialize the full workout again.
            return;
        }
        GymStore.saveCurrentEntry();
    }

    function recordSet() {
        if (GymStore.addSet()) {
            view.showSetSavedFlash(GymStore.sets.size());
            Attention.vibrate([new Attention.VibeProfile(60, 150)]);
        }
    }

    function rejectSetPrompt() {
        if (GymSession.rejectAutoPrompt()) {
            view.autoPromptWasActive = false;
            view.restoreSuspendedRest();
        }
    }

    function undoLastSet() {
        // Keep the previous set's undo snapshot available while a possible next
        // set is being evaluated, but never let undo restore that snapshot over
        // live detector/recovery state. A rejected false candidate restores rest
        // first, after which undo remains available if its short window is open.
        if ((GymStore.restDurationMs > 0 && GymStore.restStartedAt == null) ||
            GymSession.activeSetSeen ||
            GymSession.autoLogPrompt) {
            GymStore.status = "SET ACTIVE";
            return;
        }
        if (GymStore.undoLastSet()) {
            view.dismissSetSavedFlash();
            view.selected = 3;
            view.page = GymSession.autoLogPrompt ? 0 : 1;
            view.autoPromptWasActive = GymSession.autoLogPrompt;
            Attention.vibrate([new Attention.VibeProfile(45, 90), new Attention.VibeProfile(45, 90)]);
        }
    }

    function handleSettings(delta) {
        if (view.settingsSelected == 0) {
            GymStore.toggleAutoPrompt();
        } else if (view.settingsSelected == 1) {
            GymStore.adjustSensitivity(delta);
        } else if (view.settingsSelected == 2) {
            GymStore.adjustWeightStep(delta);
        } else if (view.settingsSelected == 3) {
            GymStore.adjustRestDefault(delta);
        } else if (view.settingsSelected == 4) {
            GymStore.reps += delta < 0 ? -1 : 1;
            if (GymStore.reps > 20) {
                GymStore.reps = 1;
            } else if (GymStore.reps < 1) {
                GymStore.reps = 20;
            }
            GymStore.save();
        } else if (view.settingsSelected == 5) {
            view.requestCloudSyncNow();
        } else if (view.settingsSelected == 6) {
            view.page = 7;
            view.startTutorial();
        }
    }

}
