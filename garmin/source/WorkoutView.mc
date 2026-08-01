using Toybox.Attention as Attention;
using Toybox.Graphics as Gfx;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.WatchUi as Ui;

class WorkoutView extends Ui.View {
    var selected = 0;
    var page = 0;
    var pauseSelected = 0;
    var discardSelected = 0;
    var settingsSelected = 0;
    var settingsCount = 6;
    var ticker;
    var restWasActive = false;
    var pauseFlashUntil = 0;
    var savedSetFlashUntil = 0;
    var savedSetNumber = 0;
    var lastSyncRequestAt = 0;
    var lastCloudSyncRequestAt = 0;
    var cloudAutoTimer;
    var cloudAutoAttempts = 0;
    var cloudAutoSyncActive = false;
    var screenWidth = 260;
    var screenHeight = 260;

    function initialize() {
        View.initialize();
        ticker = new Timer.Timer();
        cloudAutoTimer = new Timer.Timer();
    }

    function onShow() {
        ticker.start(method(:tick), 1000, true);
        if (!GymSession.recording) {
            GymSession.start();
            if (GymStore.sets.size() > 0) {
                // Sets are intentionally durable. A process restart starts a fresh FIT
                // segment but never silently discards the unfinished workout.
                GymStore.status = "RESUMED";
            }
        } else {
            GymSession.startSensors();
        }
        getApp().pollMailbox();
        requestSyncNow();
        flushPending();
        cloudAutoAttempts = 0;
        cloudAutoSyncActive = false;
        scheduleCloudSyncOnOpen(2500);
    }

    function onHide() {
        ticker.stop();
        cloudAutoTimer.stop();
        GymSession.stopSensors();
        GymStore.save();
    }

    function tick() {
        getApp().pollMailbox();
        GymSession.tick();
        var rest = GymStore.restSeconds();
        if (rest > 0 && GymSession.effortState.equals("SET ACTIVE")) {
            // The countdown is guidance only. A detected new set ends rest without
            // suppressing recording or producing a false "rest complete" vibration.
            GymStore.cancelRest();
            rest = 0;
            restWasActive = false;
            GymStore.status = "SET ACTIVE";
        }
        var active = rest > 0;
        if (restWasActive && !active) {
            Attention.vibrate([new Attention.VibeProfile(100, 500), new Attention.VibeProfile(100, 500)]);
            GymStore.status = "REST DONE";
        }
        restWasActive = active;
        if ((System.getTimer() - lastSyncRequestAt) > 20000) {
            requestSyncNow();
        }
        Ui.requestUpdate();
    }

    function requestSyncNow() {
        lastSyncRequestAt = System.getTimer();
        GymComm.requestSync(method(:onSyncSent));
    }

    function onSyncSent(ok) {
        GymStore.status = ok ? "SYNC REQ" : "NO PHONE";
        Ui.requestUpdate();
    }

    function requestCloudSyncNow() {
        lastCloudSyncRequestAt = System.getTimer();
        cloudAutoSyncActive = false;
        GymStore.status = "CLOUD...";
        GymComm.requestCloudPlan(method(:onCloudPlanFetched));
        Ui.requestUpdate();
    }

    function scheduleCloudSyncOnOpen(delayMs) {
        if (!GymComm.hasCloudDeviceToken()) {
            return;
        }
        cloudAutoTimer.stop();
        cloudAutoTimer.start(method(:requestCloudSyncOnOpen), delayMs, false);
    }

    function requestCloudSyncOnOpen() {
        if (!GymComm.hasCloudDeviceToken()) {
            return;
        }
        var now = System.getTimer();
        if (lastCloudSyncRequestAt != 0 && (now - lastCloudSyncRequestAt) < 8000) {
            return;
        }
        if (cloudAutoAttempts >= 4) {
            return;
        }
        cloudAutoAttempts += 1;
        cloudAutoSyncActive = true;
        lastCloudSyncRequestAt = now;
        if (cloudAutoAttempts == 1) {
            GymStore.status = "CLOUD...";
            Ui.requestUpdate();
        }
        GymComm.requestCloudPlan(method(:onCloudPlanFetched));
    }

    function onCloudPlanFetched(ok, status, message) {
        if (ok && message == null) {
            GymStore.status = status;
            cloudAutoSyncActive = false;
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
                cloudAutoSyncActive = false;
            } catch (e) {
                GymStore.status = "CLOUD FAIL";
                cloudAutoSyncActive = false;
            }
        } else {
            if (cloudAutoSyncActive && cloudAutoAttempts < 4 && !status.equals("NO TOKEN")) {
                scheduleCloudSyncOnOpen(5000);
            } else {
                GymStore.status = status;
                cloudAutoSyncActive = false;
            }
        }
        Ui.requestUpdate();
    }

    function onCloudPlanAcknowledged(ok) {
        if (!ok) {
            GymStore.status = "CLOUD RETRY";
            if (cloudAutoAttempts < 4) {
                scheduleCloudSyncOnOpen(5000);
            }
        }
        Ui.requestUpdate();
    }

    function onWorkoutSent(ok) {
        if (ok) {
            GymStore.status = "SENT";
        } else {
            GymStore.status = "QUEUED";
        }
        Ui.requestUpdate();
    }

    function flushPending() {
        if (!GymStore.hasAccountBinding() || GymStore.pending.size() == 0) {
            return;
        }
        GymComm.send(GymStore.pending[0], method(:onPendingSent));
    }

    function onPendingSent(ok) {
        // Transport completion is not a database acknowledgement. Keep the
        // item queued until the Android app replies with an explicit ack.
        GymStore.status = ok ? "WAITING ACK" : "OFFLINE";
        Ui.requestUpdate();
    }

    function finishWorkout() {
        if (GymStore.sets.size() == 0 || !GymStore.hasAccountBinding()) {
            // FIT recording is a watch-local feature. Manual set logging and an
            // authenticated phone binding are required only for GymApp sync.
            return true;
        }
        var message = GymStore.workoutMessage();
        if (message == null) {
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return false;
        }
        if (!GymStore.canQueueWorkout(message)) {
            GymStore.status = "QUEUE FULL";
            Ui.requestUpdate();
            return false;
        }
        if (!GymStore.queueWorkout(message)) {
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return false;
        }
        GymComm.send(message, method(:onWorkoutSent));
        return true;
    }

    function saveAndExit() {
        if (!finishWorkout()) {
            return;
        }
        if (!GymSession.stopAndSave()) {
            GymStore.status = "FIT FAIL";
            Ui.requestUpdate();
            return;
        }
        if (GymStore.sets.size() > 0 && !GymStore.clearActiveWorkout()) {
            // Keep the already saved FIT session closed and retry only the local
            // cleanup. Never silently resurrect these sets as a new activity.
            GymStore.status = "SAVE FAIL";
            Ui.requestUpdate();
            return;
        }
        Attention.vibrate([new Attention.VibeProfile(80, 250)]);
        System.exit();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        screenWidth = w;
        screenHeight = h;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        if (page == 0) {
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

        if (System.getTimer() < savedSetFlashUntil) {
            drawSetSavedOverlay(dc, w, h);
        }
    }

    function drawDashboard(dc, w, h) {
        var hrText = GymSession.hr == null ? "--" : GymSession.hr.toString();
        var rest = GymStore.restSeconds();
        var setActive = GymSession.effortState.equals("SET ACTIVE");
        var setMaybe = GymSession.effortState.equals("SET MAYBE");
        var status = GymSession.autoLogPrompt ?
            (GymStore.tr("LOG SET? ", "ПІДХІД? ", "ПОДХОД? ") + confidenceLabel()) :
            (setActive ?
                (effortLabel(GymSession.effortState) + " " + confidenceLabel()) :
                (setMaybe ?
                    effortLabel(GymSession.effortState) :
                    (rest > 0 ?
                        (GymStore.tr("REST ", "ВІДП ", "ОТДЫХ ") + countdownText(rest)) :
                        effortLabel(GymSession.effortState))));

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
            GymStore.tr("CALORIES", "ККАЛ", "ККАЛ"), GymSession.gymCalories.format("%.0f"));
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

    function isCompactDashboard(w, h) {
        return w < 240 || h < 240;
    }

    function isTinyDashboard(w, h) {
        return w < 200 || h < 200;
    }

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
            GymStore.tr("KCAL", "ККАЛ", "ККАЛ"), GymSession.gymCalories.format("%.0f"));
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
            GymStore.tr("KCAL", "ККАЛ", "ККАЛ"), GymSession.gymCalories.format("%.0f"));
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

    function drawCompactHeartIcon(dc, x, y) {
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - 3, y, 3);
        dc.fillCircle(x + 3, y, 3);
        dc.fillPolygon([[x - 6, y], [x + 6, y], [x, y + 9]]);
    }

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

    function drawCompactDivider(dc, w, y) {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(35, y, w - 35, y);
    }

    function drawTinyDivider(dc, w, y) {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(28, y, w - 28, y);
    }

    function drawCompactMetric(dc, x, y, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, Gfx.FONT_SYSTEM_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y + 15, Gfx.FONT_SYSTEM_XTINY, value, Gfx.TEXT_JUSTIFY_CENTER);
    }

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

    function drawDashboardDivider(dc, w, h, baseY) {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(sx(w, 58), sy(h, baseY), sx(w, 202), sy(h, baseY));
    }

    function drawDashboardMetric(dc, w, h, baseX, baseY, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, baseX), sy(h, baseY), Gfx.FONT_SYSTEM_XTINY,
            label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, baseX), sy(h, baseY + 16), Gfx.FONT_SYSTEM_XTINY,
            value, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function dashboardSetProgressText() {
        var current = GymStore.sets.size() + 1;
        if (current > GymStore.maxWorkoutSets) {
            current = GymStore.maxWorkoutSets;
        }
        var label = GymStore.tr("SET ", "ПІДХІД ", "ПОДХОД ") + current.toString();
        if (GymStore.plan.size() > 0) {
            var total = GymStore.plan.size();
            if (total < current) {
                total = current;
            }
            label += GymStore.tr(" OF ", " З ", " ИЗ ") + total.toString();
        }
        return label;
    }

    function dashboardSetBadgeText() {
        var current = GymStore.sets.size() + 1;
        if (current > GymStore.maxWorkoutSets) {
            current = GymStore.maxWorkoutSets;
        }
        if (GymStore.plan.size() > 0) {
            var total = GymStore.plan.size();
            if (total < current) {
                total = current;
            }
            return current.toString() + "/" + total.toString();
        }
        return "SET " + current.toString();
    }

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

    function showPauseFlash() {
        pauseFlashUntil = System.getTimer() + 1800;
    }

    function showSetSavedFlash(number) {
        savedSetNumber = number;
        savedSetFlashUntil = System.getTimer() + GymStore.undoWindowMs;
    }

    function isUndoOverlayActive() {
        return System.getTimer() < savedSetFlashUntil && GymStore.canUndoLastSet();
    }

    function dismissSetSavedFlash() {
        savedSetFlashUntil = 0;
    }

    function drawSetSavedOverlay(dc, w, h) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(w / 2, h / 2, sr(w, h, 124));
        dc.drawText(w / 2, sy(h, 66), Gfx.FONT_SMALL, GymStore.tr("SET", "ПІДХІД", "ПОДХОД"), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, 98), Gfx.FONT_NUMBER_MEDIUM, savedSetNumber.toString(), Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 176), Gfx.FONT_XTINY, fitTextWidth(dc, GymStore.currentExerciseLabel(), Gfx.FONT_XTINY, sr(w, h, 184)), Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 214), Gfx.FONT_XTINY, GymStore.tr("TAP / BACK: UNDO", "ТАП / НАЗАД: СКАС", "ТАП / НАЗАД: ОТМЕНА"), Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawPausedOverlay(dc, w, h) {
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(w / 2, h / 2, sr(w, h, 124));
        if (System.getTimer() < pauseFlashUntil) {
            dc.fillRectangle((w / 2) - sr(w, h, 14), sy(h, 22), sr(w, h, 10), sr(w, h, 28));
            dc.fillRectangle((w / 2) + sr(w, h, 4), sy(h, 22), sr(w, h, 10), sr(w, h, 28));
        }
    }

    function drawCompactValue(dc, w, h, baseX, baseY, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, baseX), sy(h, baseY), Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, baseX), sy(h, baseY + 16), Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_CENTER);
    }

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

    function zoneLabel(zone) {
        if (zone == 1) {
            return "Zone 1 Easy";
        } else if (zone == 2) {
            return "Zone 2 Fat burn";
        } else if (zone == 3) {
            return "Zone 3 Tempo";
        } else if (zone == 4) {
            return "Zone 4 Hard";
        } else if (zone >= 5) {
            return "Zone 5 Max";
        }
        return "No zone";
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

    function drawPauseMenu(dc, w, h) {
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        drawHeader(dc, w, h, GymStore.tr("PAUSED", "ПАУЗА", "ПАУЗА"));

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 52), Gfx.FONT_SMALL, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);

        drawMenuRow(dc, w, h, 0, 82, GymStore.tr("RESUME", "ДАЛІ", "ПРОДОЛЖ"));
        drawMenuRow(dc, w, h, 1, 126, GymStore.tr("SAVE", "ЗБЕРЕГТИ", "СОХРАНИТЬ"));
        drawMenuRow(dc, w, h, 2, 170, GymStore.tr("DISCARD", "СКАСУВ", "СБРОСИТЬ"));
    }

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

    function drawSummary(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 30), Gfx.FONT_XTINY, GymStore.tr("SUMMARY", "ПІДСУМ", "ИТОГ"), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 54), Gfx.FONT_XTINY, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);
        drawSummaryValue(dc, w, h, 78, 86, "GYM", GymSession.gymCalories.format("%.0f"));
        var garminKcal = GymSession.garminCalories == null ? "--" : GymSession.garminCalories.toString();
        drawSummaryValue(dc, w, h, 182, 86, "GAR", garminKcal);
        drawSummaryValue(dc, w, h, 78, 132, GymStore.tr("AVG", "СЕР", "СРЕД"), GymSession.avgHr.toString());
        drawSummaryValue(dc, w, h, 182, 132, "MAX", GymSession.maxHr.toString());
        drawSummaryValue(dc, w, h, 130, 174, GymStore.tr("SETS", "ПІДХ", "ПОДХ"), GymStore.sets.size().toString());
        drawMenuRow(dc, w, h, 0, 210, GymStore.tr("SAVE & EXIT", "ЗБЕРЕГТИ", "СОХРАНИТЬ"));
    }

    function drawSummaryValue(dc, w, h, baseX, baseY, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, baseX), sy(h, baseY), Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, baseX), sy(h, baseY + 16), Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_CENTER);
    }

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
        drawDebugLine(dc, w, lineY, "MOV", GymSession.motionAvailable ? GymSession.motionScore.format("%.0f") : "--");
        lineY += lineStep;
        drawDebugLine(dc, w, lineY, "CONF", GymSession.setConfidence.toString() + "% " + GymSession.confidenceLevel);
        lineY += lineStep;
        drawDebugLine(dc, w, lineY, "ST", fitText(effortLabel(GymSession.effortState), 7));
        lineY += lineStep;
        drawDebugLine(dc, w, lineY, "K/M", GymSession.lastKcalPerMinute.format("%.1f"));
        lineY += lineStep;
        drawDebugLine(dc, w, lineY, GymStore.tr("SYNC", "СИНХ", "СИНХ"), statusLabel(GymStore.status));
    }

    function drawDebugLine(dc, w, y, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, 72), y, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, 188), y, Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_RIGHT);
    }

    function drawSettings(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 18), Gfx.FONT_XTINY, GymStore.tr("SETTINGS", "НАЛАШТ", "НАСТРОЙКИ"), Gfx.TEXT_JUSTIFY_CENTER);

        drawSettingsRow(dc, w, h, 0, 50, GymStore.tr("AUTO", "АВТО", "АВТО"), adjustText(GymStore.onOff(GymStore.autoPromptEnabled)));
        drawSettingsRow(dc, w, h, 1, 84, GymStore.tr("DETECT", "ЧУТЛ", "ЧУВСТ"), adjustText(fitText(GymStore.sensitivityLabel(), 6)));
        drawSettingsRow(dc, w, h, 2, 118, GymStore.tr("KG STEP", "КРОК КГ", "ШАГ КГ"), adjustText(localizedDecimal(GymStore.weightStep)));
        drawSettingsRow(dc, w, h, 3, 152, GymStore.tr("REST", "ВІДП", "ОТДЫХ"), adjustText(GymStore.restSecondsDefault.toString() + GymStore.tr("s", "с", "с")));
        drawSettingsRow(dc, w, h, 4, 186, GymStore.tr("REPS", "ПОВТ", "ПОВТ"), adjustText(GymStore.reps.toString()));
        drawSettingsRow(dc, w, h, 5, 220, GymStore.tr("CLOUD", "ХМАРА", "ОБЛАКО"), GymStore.tr("SYNC", "СИНХ", "СИНХ"));
    }

    function adjustText(value) {
        return "< " + value + " >";
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

    function drawHeader(dc, w, h, label) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 34), Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
    }

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

    function onSelect() {
        if (view.isUndoOverlayActive()) {
            view.dismissSetSavedFlash();
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
            if (GymSession.autoLogPrompt) {
                recordSet();
            } else {
                view.page = 1;
            }
        } else {
            handleSelect();
        }
        Ui.requestUpdate();
        return true;
    }

    function onNextPage() {
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

    function onPreviousPage() {
        if (view.page == 3) {
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

    function onNextMode() {
        if (view.page == 6) {
            moveDiscardSelection(1);
        } else {
            navigateContent(1);
        }
        Ui.requestUpdate();
        return true;
    }

    function onPreviousMode() {
        if (view.page == 6) {
            moveDiscardSelection(-1);
        } else {
            navigateContent(-1);
        }
        Ui.requestUpdate();
        return true;
    }

    function onMenu() {
        if (view.page == 6) {
            cancelDiscardConfirmation();
        } else {
            openPauseMenu();
        }
        Ui.requestUpdate();
        return true;
    }

    function onBack() {
        // Back is an undo action only while the five-second confirmation is
        // visibly active. After it disappears, Back returns to navigation.
        if (view.isUndoOverlayActive()) {
            undoLastSet();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 6) {
            cancelDiscardConfirmation();
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 3) {
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
        if (view.page == 1 || view.page == 4 || view.page == 5) {
            view.page = 0;
            Ui.requestUpdate();
            return true;
        }
        openPauseMenu();
        Ui.requestUpdate();
        return true;
    }

    function onTap(evt) {
        var coordinates = evt.getCoordinates();
        var x = coordinates[0];
        var y = coordinates[1];
        if (view.isUndoOverlayActive()) {
            if (y >= ((view.screenHeight * 62) / 100)) {
                undoLastSet();
            } else {
                view.dismissSetSavedFlash();
            }
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
            var settingsRow = rowAt(y, 50, 34, view.settingsCount);
            if (settingsRow >= 0) {
                view.settingsSelected = settingsRow;
                handleSettings(x < (view.screenWidth / 2) ? -1 : 1);
            }
        } else if (view.page == 4) {
            view.page = 0;
        } else if (view.page == 0) {
            if (GymSession.autoLogPrompt) {
                recordSet();
            } else {
                view.page = 1;
            }
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

    function onSwipe(evt) {
        var direction = evt.getDirection();
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

    function onKey(evt) {
        var key = evt.getKey();
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

    function openPauseMenu() {
        if (!GymSession.paused) {
            GymSession.pause();
        }
        view.pauseSelected = 0;
        view.page = 2;
    }

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

    function handlePauseMenu() {
        if (view.pauseSelected == 0) {
            GymSession.resume();
            view.page = 0;
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
        GymStore.clearWorkout();
        GymSession.discard();
        System.exit();
    }

    function activate(delta) {
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
        }
        GymStore.save();
    }

    function recordSet() {
        if (GymStore.addSet()) {
            view.showSetSavedFlash(GymStore.sets.size());
            Attention.vibrate([new Attention.VibeProfile(60, 150)]);
        }
    }

    function undoLastSet() {
        if (GymStore.undoLastSet()) {
            view.dismissSetSavedFlash();
            view.selected = 3;
            view.page = 1;
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
        }
    }

}
