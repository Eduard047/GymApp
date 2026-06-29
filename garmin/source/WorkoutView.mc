using Toybox.Attention as Attention;
using Toybox.Graphics as Gfx;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.WatchUi as Ui;

class WorkoutView extends Ui.View {
    var selected = 0;
    var page = 0;
    var pauseSelected = 0;
    var settingsSelected = 0;
    var settingsCount = 6;
    var ticker;
    var restWasActive = false;
    var pauseFlashUntil = 0;
    var savedSetFlashUntil = 0;
    var savedSetNumber = 0;
    var lastSyncRequestAt = 0;

    function initialize() {
        View.initialize();
        GymStore.load();
        ticker = new Timer.Timer();
    }

    function onShow() {
        ticker.start(method(:tick), 1000, true);
        if (!GymSession.recording) {
            GymStore.clearActiveWorkout();
            GymSession.start();
        } else {
            GymSession.startSensors();
        }
        getApp().pollMailbox();
        requestSyncNow();
        flushPending();
    }

    function onHide() {
        ticker.stop();
        GymSession.stopSensors();
        GymStore.save();
    }

    function tick() {
        getApp().pollMailbox();
        GymSession.tick();
        var active = GymStore.restSeconds() > 0;
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
        GymStore.status = "CLOUD...";
        GymComm.requestCloudPlan(method(:onCloudPlanFetched));
        Ui.requestUpdate();
    }

    function onCloudPlanFetched(ok, status, message) {
        if (ok && message != null) {
            try {
                GymStore.applySync(message);
                GymStore.status = status;
            } catch (e) {
                GymStore.status = "CLOUD FAIL";
            }
        } else {
            GymStore.status = status;
        }
        Ui.requestUpdate();
    }

    function onWorkoutSent(ok) {
        if (ok) {
            GymStore.clearWorkout();
            GymStore.status = "SENT";
        } else {
            GymStore.status = "QUEUED";
        }
        Ui.requestUpdate();
    }

    function flushPending() {
        if (GymStore.pending.size() == 0) {
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
        if (GymStore.sets.size() == 0) {
            GymStore.status = "NO SETS";
            Ui.requestUpdate();
            return;
        }
        var message = GymStore.workoutMessage();
        GymStore.pending.add(message);
        GymStore.clearActiveWorkout();
        GymComm.send(message, method(:onWorkoutSent));
        Attention.vibrate([new Attention.VibeProfile(80, 250)]);
    }

    function saveAndExit() {
        finishWorkout();
        GymSession.stopAndSave();
        System.exit();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
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
        } else {
            drawSettings(dc, w, h);
        }
        drawPageDots(dc, w, h);

        if (System.getTimer() < savedSetFlashUntil) {
            drawSetSavedOverlay(dc, w, h);
        }
    }

    function drawDashboard(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 22, Gfx.FONT_SMALL, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);

        var hrText = GymSession.hr == null ? "--" : GymSession.hr.toString();
        var garminKcal = GymSession.garminCalories == null ? "--" : GymSession.garminCalories.toString();

        dc.setColor(zoneColor(GymSession.zone), Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 48, Gfx.FONT_NUMBER_MEDIUM, hrText, Gfx.TEXT_JUSTIFY_CENTER);
        drawHeartRateZones(dc, w, 126);

        drawCompactValue(dc, 82, 174, "GYM", GymSession.gymCalories.format("%.0f"));
        drawCompactValue(dc, 178, 174, "GAR", garminKcal);

        var rest = GymStore.restSeconds();
        var status = GymSession.autoLogPrompt ? GymStore.tr("LOG SET?", "ПІДХІД?") : (rest > 0 ? (GymStore.tr("REST ", "ВІДП ") + rest.toString() + "s") : effortLabel(GymSession.effortState));
        dc.setColor(GymSession.autoLogPrompt ? Gfx.COLOR_GREEN : (rest > 0 ? Gfx.COLOR_YELLOW : stateColor(GymSession.effortState)), Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 204, Gfx.FONT_XTINY, status, Gfx.TEXT_JUSTIFY_CENTER);

        if (GymSession.paused) {
            drawPausedOverlay(dc, w, h);
        }
    }

    function showPauseFlash() {
        pauseFlashUntil = System.getTimer() + 1800;
    }

    function showSetSavedFlash(number) {
        savedSetNumber = number;
        savedSetFlashUntil = System.getTimer() + 1500;
    }

    function drawSetSavedOverlay(dc, w, h) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(w / 2, h / 2, 124);
        dc.drawText(w / 2, 66, Gfx.FONT_SMALL, GymStore.tr("SET", "ПІДХІД"), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 98, Gfx.FONT_NUMBER_MEDIUM, savedSetNumber.toString(), Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 176, Gfx.FONT_XTINY, fitText(GymStore.currentExercise(), 12), Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawPausedOverlay(dc, w, h) {
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(w / 2, h / 2, 124);
        if (System.getTimer() < pauseFlashUntil) {
            dc.fillRectangle((w / 2) - 14, 22, 10, 28);
            dc.fillRectangle((w / 2) + 4, 22, 10, 28);
        }
    }

    function drawCompactValue(dc, x, y, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y + 16, Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawHeartRateZones(dc, w, y) {
        var left = 48;
        var segmentWidth = 30;
        var gap = 5;
        for (var i = 1; i <= 5; i += 1) {
            var x = left + ((i - 1) * (segmentWidth + gap));
            dc.setColor(zoneColor(i), Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, segmentWidth, 12, 4);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x + (segmentWidth / 2), y + 13, Gfx.FONT_XTINY, "Z" + i.toString(), Gfx.TEXT_JUSTIFY_CENTER);
        }

        var markerZone = GymSession.zone;
        if (markerZone < 1) {
            markerZone = 1;
        } else if (markerZone > 5) {
            markerZone = 5;
        }
        var markerX = left + ((markerZone - 1) * (segmentWidth + gap)) + (segmentWidth / 2);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon([[markerX, y - 7], [markerX - 6, y - 1], [markerX + 6, y - 1]]);
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
        } else if (state.equals("REST")) {
            return Gfx.COLOR_BLUE;
        } else if (state.equals("READY")) {
            return Gfx.COLOR_YELLOW;
        }
        return Gfx.COLOR_LT_GRAY;
    }

    function effortLabel(state) {
        if (!GymStore.isUk()) {
            return state;
        }
        if (state.equals("SET ACTIVE")) {
            return "ПІДХІД";
        } else if (state.equals("REST")) {
            return "ВІДП";
        } else if (state.equals("READY")) {
            return "ГОТОВ";
        }
        return state;
    }

    function drawEntry(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        drawHeader(dc, w, GymStore.tr("SET ENTRY", "ПІДХІД"));

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 48, Gfx.FONT_XTINY, fitText(GymStore.currentExercise(), 10), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 70, Gfx.FONT_XTINY, GymStore.weight.format("%.1f") + "kg x " + GymStore.reps.toString(), Gfx.TEXT_JUSTIFY_CENTER);

        drawRow(dc, 0, 100, GymStore.tr("EX", "ВПР"), GymStore.tr("next", "далі"));
        drawRow(dc, 1, 130, "KG", "+" + GymStore.weightStep.format("%.1f"));
        drawRow(dc, 2, 160, GymStore.tr("REP", "ПОВТ"), "+1");
        drawRow(dc, 3, 190, GymStore.tr("SET", "ПІДХ"), GymStore.sets.size().toString());
    }

    function drawPauseMenu(dc, w, h) {
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        drawHeader(dc, w, GymStore.tr("PAUSED", "ПАУЗА"));

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 52, Gfx.FONT_SMALL, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);

        drawMenuRow(dc, 0, 92, GymStore.tr("RESUME", "ДАЛІ"));
        drawMenuRow(dc, 1, 130, GymStore.tr("SAVE", "ЗБЕРЕГТИ"));
        drawMenuRow(dc, 2, 168, GymStore.tr("DISCARD", "СКАСУВ"));
    }

    function drawSummary(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 30, Gfx.FONT_XTINY, GymStore.tr("SUMMARY", "ПІДСУМ"), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 54, Gfx.FONT_XTINY, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);
        drawSummaryValue(dc, 78, 86, "GYM", GymSession.gymCalories.format("%.0f"));
        var garminKcal = GymSession.garminCalories == null ? "--" : GymSession.garminCalories.toString();
        drawSummaryValue(dc, 182, 86, "GAR", garminKcal);
        drawSummaryValue(dc, 78, 132, GymStore.tr("AVG", "СЕР"), GymSession.avgHr.toString());
        drawSummaryValue(dc, 182, 132, "MAX", GymSession.maxHr.toString());
        drawSummaryValue(dc, 130, 174, GymStore.tr("SETS", "ПІДХ"), GymStore.sets.size().toString());
    }

    function drawSummaryValue(dc, x, y, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y + 16, Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawDebug(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        drawHeader(dc, w, GymStore.tr("DEBUG", "ДЕБАГ"));

        drawDebugLine(dc, 46, "HR", GymSession.hr == null ? "--" : GymSession.hr.toString());
        drawDebugLine(dc, 66, "ZN", GymSession.zone.toString());
        drawDebugLine(dc, 86, "ST", fitText(effortLabel(GymSession.effortState), 7));
        drawDebugLine(dc, 106, "MET", GymSession.lastMet.format("%.1f"));
        drawDebugLine(dc, 126, "K/M", GymSession.lastKcalPerMinute.format("%.1f"));
        drawDebugLine(dc, 146, "AUTO", GymStore.onOff(GymStore.autoPromptEnabled));
        drawDebugLine(dc, 166, "SENS", fitText(GymStore.sensitivityLabel(), 7));
        drawDebugLine(dc, 186, "SYNC", fitText(GymStore.status, 7));
    }

    function drawDebugLine(dc, y, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(72, y, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(188, y, Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_RIGHT);
    }

    function drawSettings(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        drawHeader(dc, w, GymStore.tr("SETTINGS", "НАЛАШТ"));

        drawSettingsRow(dc, 0, 48, GymStore.tr("AUTOSET", "АВТО"), GymStore.onOff(GymStore.autoPromptEnabled));
        drawSettingsRow(dc, 1, 74, GymStore.tr("DETECT", "ДЕТЕКТ"), fitText(GymStore.sensitivityLabel(), 6));
        drawSettingsRow(dc, 2, 100, GymStore.tr("KG STEP", "КРОК КГ"), GymStore.weightStep.format("%.1f"));
        drawSettingsRow(dc, 3, 126, GymStore.tr("REST", "ВІДП"), GymStore.restSecondsDefault.toString() + "s");
        drawSettingsRow(dc, 4, 152, GymStore.tr("REPS", "ПОВТ"), GymStore.reps.toString());
        drawSettingsRow(dc, 5, 178, "CLOUD", "SYNC");
    }

    function drawSettingsRow(dc, index, y, label, value) {
        var selectedRow = index == settingsSelected;
        if (selectedRow) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(62, y - 2, 136, 28, 7);
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(70, y + 6, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(190, y + 6, Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_RIGHT);
    }

    function drawMenuRow(dc, index, y, label) {
        if (index == pauseSelected) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(72, y - 2, 116, 28, 7);
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(130, y + 7, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawRow(dc, index, y, label, value) {
        var selectedRow = index == selected;
        if (selectedRow) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(70, y - 2, 120, 28, 7);
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(78, y + 6, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(182, y + 6, Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_RIGHT);
    }

    function drawHeader(dc, w, label) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 34, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
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
        var totalWidth = 50;
        var startX = (w / 2) - (totalWidth / 2);
        var y = 224;
        for (var i = 0; i < 4; i += 1) {
            var x = startX + (i * 16);
            dc.setColor(i == dotPage ? Gfx.COLOR_WHITE : Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            if (i == dotPage) {
                dc.fillCircle(x, y, 4);
            } else {
                dc.drawCircle(x, y, 3);
            }
        }
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
}

class WorkoutDelegate extends Ui.BehaviorDelegate {
    var view;

    function initialize(workoutView) {
        BehaviorDelegate.initialize();
        view = workoutView;
    }

    function onSelect() {
        if (view.page == 3) {
            view.saveAndExit();
        } else if (view.page == 2) {
            handlePauseMenu();
        } else if (view.page == 5) {
            handleSettings();
        } else if (view.page == 4) {
            view.page = 0;
        } else if (view.page == 0) {
            GymSession.togglePause();
            view.showPauseFlash();
        } else {
            handleSelect();
        }
        Ui.requestUpdate();
        return true;
    }

    function onNextPage() {
        if (view.page == 2) {
            view.pauseSelected = (view.pauseSelected + 1) % 3;
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

    function onBack() {
        if (view.page == 3) {
            view.page = 2;
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 2) {
            view.page = 0;
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 1 || view.page == 4 || view.page == 5) {
            view.page = 0;
            Ui.requestUpdate();
            return true;
        }
        if (view.page == 0 && !GymSession.paused) {
            recordSet();
            Ui.requestUpdate();
            return true;
        }
        view.page = 2;
        Ui.requestUpdate();
        return true;
    }

    function onTap(evt) {
        if (view.page == 3) {
            view.saveAndExit();
        } else if (view.page == 2) {
            view.pauseSelected = (view.pauseSelected + 1) % 3;
        } else if (view.page == 5) {
            view.settingsSelected = (view.settingsSelected + 1) % view.settingsCount;
        } else if (view.page == 4) {
            view.page = 0;
        } else if (view.page == 0) {
            view.page = 1;
        } else {
            view.selected = (view.selected + 1) % 4;
        }
        Ui.requestUpdate();
        return true;
    }

    function onSwipe(evt) {
        var direction = evt.getDirection();
        if (view.page == 3) {
            return true;
        } else if (view.page == 2 && direction == Ui.SWIPE_UP) {
            view.pauseSelected = (view.pauseSelected + 1) % 3;
        } else if (view.page == 2 && direction == Ui.SWIPE_DOWN) {
            view.pauseSelected = (view.pauseSelected + 2) % 3;
        } else if (direction == Ui.SWIPE_LEFT) {
            if (view.page == 0) {
                view.page = 5;
            } else if (view.page == 5) {
                view.page = 4;
            } else if (view.page == 4) {
                view.page = 1;
            } else if (view.page == 1) {
                view.page = 0;
            }
        } else if (direction == Ui.SWIPE_RIGHT) {
            if (view.page == 0) {
                view.page = 1;
            } else if (view.page == 1) {
                view.page = 4;
            } else if (view.page == 4) {
                view.page = 5;
            } else if (view.page == 5) {
                view.page = 0;
            }
        } else if (direction == Ui.SWIPE_UP && view.page == 1) {
            view.selected = (view.selected + 1) % 4;
        } else if (direction == Ui.SWIPE_DOWN && view.page == 1) {
            view.selected = (view.selected + 3) % 4;
        } else if (direction == Ui.SWIPE_UP && view.page == 5) {
            view.settingsSelected = (view.settingsSelected + 1) % view.settingsCount;
        } else if (direction == Ui.SWIPE_DOWN && view.page == 5) {
            view.settingsSelected = (view.settingsSelected + view.settingsCount - 1) % view.settingsCount;
        }
        Ui.requestUpdate();
        return true;
    }

    function onKey(evt) {
        var key = evt.getKey();
        if (key == Ui.KEY_UP && view.page == 2) {
            view.pauseSelected = (view.pauseSelected + 2) % 3;
        } else if (key == Ui.KEY_DOWN && view.page == 2) {
            view.pauseSelected = (view.pauseSelected + 1) % 3;
        } else if (key == Ui.KEY_UP && view.page == 1) {
            view.selected = (view.selected + 3) % 4;
        } else if (key == Ui.KEY_DOWN && view.page == 1) {
            view.selected = (view.selected + 1) % 4;
        } else if (key == Ui.KEY_UP && view.page == 5) {
            view.settingsSelected = (view.settingsSelected + view.settingsCount - 1) % view.settingsCount;
        } else if (key == Ui.KEY_DOWN && view.page == 5) {
            view.settingsSelected = (view.settingsSelected + 1) % view.settingsCount;
        } else if (key == Ui.KEY_ENTER) {
            if (view.page == 3) {
                view.saveAndExit();
            } else if (view.page == 2) {
                handlePauseMenu();
            } else if (view.page == 5) {
                handleSettings();
            } else if (view.page == 4) {
                view.page = 0;
            } else {
                handleSelect();
            }
        } else if (key == Ui.KEY_ESC) {
            onBack();
        } else if (key == Ui.KEY_START) {
            if (view.page == 3) {
                view.saveAndExit();
            } else if (view.page == 2) {
                handlePauseMenu();
            } else {
                GymSession.togglePause();
                view.showPauseFlash();
                view.page = 0;
            }
        } else if (key == Ui.KEY_MENU) {
            if (!GymSession.paused) {
                GymSession.pause();
            }
            view.page = 2;
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
            handleSettings();
        } else if (view.page == 4) {
            view.page = 0;
        } else {
            activate(1);
        }
    }

    function handlePauseMenu() {
        if (view.pauseSelected == 0) {
            GymSession.resume();
            view.page = 0;
        } else if (view.pauseSelected == 1) {
            view.page = 3;
        } else {
            GymStore.clearWorkout();
            GymSession.discard();
            System.exit();
        }
    }

    function activate(delta) {
        if (view.selected == 0) {
            GymStore.nextExercise(delta);
        } else if (view.selected == 1) {
            GymStore.weight += GymStore.weightStep * delta;
            if (GymStore.weight < 0.0) {
                GymStore.weight = 0.0;
            }
        } else if (view.selected == 2) {
            GymStore.reps += delta;
            if (GymStore.reps < 1) {
                GymStore.reps = 1;
            }
        } else if (view.selected == 3 && delta > 0) {
            recordSet();
        }
        GymStore.save();
    }

    function recordSet() {
        GymStore.addSet();
        view.showSetSavedFlash(GymStore.sets.size());
        Attention.vibrate([new Attention.VibeProfile(60, 150)]);
    }

    function handleSettings() {
        if (view.settingsSelected == 0) {
            GymStore.toggleAutoPrompt();
        } else if (view.settingsSelected == 1) {
            GymStore.cycleSensitivity();
        } else if (view.settingsSelected == 2) {
            GymStore.cycleWeightStep();
        } else if (view.settingsSelected == 3) {
            GymStore.cycleRestDefault();
        } else if (view.settingsSelected == 4) {
            GymStore.reps += 1;
            if (GymStore.reps > 20) {
                GymStore.reps = 1;
            }
            GymStore.save();
        } else if (view.settingsSelected == 5) {
            view.requestCloudSyncNow();
        }
    }

}

