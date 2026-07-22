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
    var lastCloudSyncRequestAt = 0;
    var cloudAutoTimer;
    var cloudAutoAttempts = 0;
    var cloudAutoSyncActive = false;
    var screenWidth = 260;
    var screenHeight = 260;

    function initialize() {
        View.initialize();
        GymStore.load();
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
        if (GymStore.sets.size() == 0) {
            GymStore.status = "NO SETS";
            Ui.requestUpdate();
            return false;
        }
        var message = GymStore.workoutMessage();
        if (message == null) {
            GymStore.status = "SYNC FIRST";
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
        Attention.vibrate([new Attention.VibeProfile(80, 250)]);
        return true;
    }

    function saveAndExit() {
        if (finishWorkout()) {
            GymSession.stopAndSave();
            System.exit();
        }
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
        dc.drawText(w / 2, sy(h, 22), Gfx.FONT_SMALL, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);

        var hrText = GymSession.hr == null ? "--" : GymSession.hr.toString();
        var garminKcal = GymSession.garminCalories == null ? "--" : GymSession.garminCalories.toString();

        dc.setColor(zoneColor(GymSession.zone), Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 48), Gfx.FONT_NUMBER_MEDIUM, hrText, Gfx.TEXT_JUSTIFY_CENTER);
        drawHeartRateZones(dc, w, h, 126);

        drawCompactValue(dc, w, h, 82, 162, "GYM", GymSession.gymCalories.format("%.0f"));
        drawCompactValue(dc, w, h, 178, 162, "GAR", garminKcal);

        var rest = GymStore.restSeconds();
        var status = GymSession.autoLogPrompt ? GymStore.tr("LOG SET?", "ПІДХІД?", "ПОДХОД?") : (rest > 0 ? (GymStore.tr("REST ", "ВІДП ", "ОТДЫХ ") + rest.toString() + GymStore.tr("s", "с", "с")) : effortLabel(GymSession.effortState));
        dc.setColor(GymSession.autoLogPrompt ? Gfx.COLOR_GREEN : (rest > 0 ? Gfx.COLOR_YELLOW : stateColor(GymSession.effortState)), Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 202), Gfx.FONT_XTINY, status, Gfx.TEXT_JUSTIFY_CENTER);

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
        dc.drawCircle(w / 2, h / 2, sr(w, h, 124));
        dc.drawText(w / 2, sy(h, 66), Gfx.FONT_SMALL, GymStore.tr("SET", "ПІДХІД", "ПОДХОД"), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, 98), Gfx.FONT_NUMBER_MEDIUM, savedSetNumber.toString(), Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 176), Gfx.FONT_XTINY, fitText(GymStore.currentExerciseLabel(), 18), Gfx.TEXT_JUSTIFY_CENTER);
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
        var left = sx(w, 48);
        var y = sy(h, baseY);
        var segmentWidth = sr(w, h, 30);
        var gap = sr(w, h, 5);
        for (var i = 1; i <= 5; i += 1) {
            var x = left + ((i - 1) * (segmentWidth + gap));
            dc.setColor(zoneColor(i), Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, segmentWidth, sr(w, h, 12), sr(w, h, 4));
        }

        var markerZone = GymSession.zone;
        if (markerZone < 1) {
            markerZone = 1;
        } else if (markerZone > 5) {
            markerZone = 5;
        }
        var markerX = left + ((markerZone - 1) * (segmentWidth + gap)) + (segmentWidth / 2);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon([[markerX, y - sr(w, h, 7)], [markerX - sr(w, h, 6), y - sr(w, h, 1)], [markerX + sr(w, h, 6), y - sr(w, h, 1)]]);
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
        if (!GymStore.isUk() && !GymStore.isRu()) {
            return state;
        }
        if (state.equals("SET ACTIVE")) {
            return GymStore.isRu() ? "ПОДХОД" : "ПІДХІД";
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

    function drawEntry(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 28), Gfx.FONT_XTINY, GymStore.tr("SET ENTRY", "ПІДХІД", "ПОДХОД"), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 56), Gfx.FONT_XTINY, fitText(GymStore.currentExerciseLabel(), 18), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, sy(h, 78), Gfx.FONT_XTINY, setSummaryText(), Gfx.TEXT_JUSTIFY_CENTER);

        drawAdjustRow(dc, w, h, 0, 90, GymStore.tr("EXERCISE", "ВПРАВА", "УПРАЖН"), GymStore.tr("choose", "вибір", "выбор"));
        drawAdjustRow(dc, w, h, 1, 130, GymStore.tr("KG", "КГ", "КГ"), localizedDecimal(GymStore.weight));
        drawAdjustRow(dc, w, h, 2, 170, GymStore.tr("REPS", "ПОВТ", "ПОВТ"), GymStore.reps.toString());
        drawRow(dc, w, h, 3, 210, GymStore.tr("SAVE SET", "ЗБЕР ПІДХ", "СОХР ПОДХ"), GymStore.sets.size().toString());
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

        drawDebugLine(dc, w, h, 46, "HR", GymSession.hr == null ? "--" : GymSession.hr.toString());
        drawDebugLine(dc, w, h, 66, "ZN", GymSession.zone.toString());
        drawDebugLine(dc, w, h, 86, "ST", fitText(effortLabel(GymSession.effortState), 7));
        drawDebugLine(dc, w, h, 106, "MET", GymSession.lastMet.format("%.1f"));
        drawDebugLine(dc, w, h, 126, "K/M", GymSession.lastKcalPerMinute.format("%.1f"));
        drawDebugLine(dc, w, h, 146, GymStore.tr("AUTO", "АВТО", "АВТО"), GymStore.onOff(GymStore.autoPromptEnabled));
        drawDebugLine(dc, w, h, 166, GymStore.tr("SENS", "ЧУТЛ", "ЧУВСТ"), fitText(GymStore.sensitivityLabel(), 7));
        drawDebugLine(dc, w, h, 186, GymStore.tr("SYNC", "СИНХ", "СИНХ"), statusLabel(GymStore.status));
    }

    function drawDebugLine(dc, w, h, baseY, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, 72), sy(h, baseY), Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_LEFT);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(sx(w, 188), sy(h, baseY), Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_RIGHT);
    }

    function drawSettings(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, sy(h, 28), Gfx.FONT_XTINY, GymStore.tr("SETTINGS", "НАЛАШТ", "НАСТРОЙКИ"), Gfx.TEXT_JUSTIFY_CENTER);

        drawSettingsRow(dc, w, h, 0, 42, GymStore.tr("AUTO", "АВТО", "АВТО"), adjustText(GymStore.onOff(GymStore.autoPromptEnabled)));
        drawSettingsRow(dc, w, h, 1, 76, GymStore.tr("DETECT", "ЧУТЛ", "ЧУВСТ"), adjustText(fitText(GymStore.sensitivityLabel(), 6)));
        drawSettingsRow(dc, w, h, 2, 110, GymStore.tr("KG STEP", "КРОК КГ", "ШАГ КГ"), adjustText(localizedDecimal(GymStore.weightStep)));
        drawSettingsRow(dc, w, h, 3, 144, GymStore.tr("REST", "ВІДП", "ОТДЫХ"), adjustText(GymStore.restSecondsDefault.toString() + GymStore.tr("s", "с", "с")));
        drawSettingsRow(dc, w, h, 4, 178, GymStore.tr("REPS", "ПОВТ", "ПОВТ"), adjustText(GymStore.reps.toString()));
        drawSettingsRow(dc, w, h, 5, 212, GymStore.tr("CLOUD", "ХМАРА", "ОБЛАКО"), GymStore.tr("SYNC", "СИНХ", "СИНХ"));
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
        dc.drawText(sx(w, 48), sy(h, baseY + 7), Gfx.FONT_XTINY, fitText(label, 9), Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(sx(w, 212), sy(h, baseY + 7), Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_RIGHT);
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
        dc.drawText(w / 2, sy(h, baseY + 9), Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
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
        dc.drawText(sx(w, 50), sy(h, baseY + 8), Gfx.FONT_XTINY, fitText(label, 11), Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(sx(w, 210), sy(h, baseY + 8), Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_RIGHT);
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
        dc.drawText(w / 2, sy(h, baseY + 9), Gfx.FONT_XTINY, fitText(label + " " + value, 14), Gfx.TEXT_JUSTIFY_CENTER);
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
        var y = sy(h, 12);
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
        return size.toFloat() / 260.0;
    }

    function sx(w, baseX) {
        return ((w / 2) + ((baseX - 130) * (w.toFloat() / 260.0))).toNumber();
    }

    function sy(h, baseY) {
        return ((h / 2) + ((baseY - 130) * (h.toFloat() / 260.0))).toNumber();
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

    function onNextMode() {
        navigateContent(1);
        Ui.requestUpdate();
        return true;
    }

    function onPreviousMode() {
        navigateContent(-1);
        Ui.requestUpdate();
        return true;
    }

    function onMenu() {
        openPauseMenu();
        Ui.requestUpdate();
        return true;
    }

    function onBack() {
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
        if (view.page == 3) {
            if (rowAt(y, 210, 44, 1) == 0) {
                view.saveAndExit();
            }
        } else if (view.page == 2) {
            var pauseRow = rowAt(y, 82, 44, 3);
            if (pauseRow >= 0) {
                // Discard is deliberately two-step on touch to avoid losing an active workout.
                if (pauseRow == 2 && view.pauseSelected != 2) {
                    view.pauseSelected = pauseRow;
                } else {
                    view.pauseSelected = pauseRow;
                    handlePauseMenu();
                }
            }
        } else if (view.page == 5) {
            var settingsRow = rowAt(y, 42, 34, view.settingsCount);
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
            var entryRow = rowAt(y, 90, 40, 4);
            if (entryRow >= 0) {
                view.selected = entryRow;
                if (entryRow == 3) {
                    recordSet();
                } else {
                    activate(x < (view.screenWidth / 2) ? -1 : 1);
                }
            }
        }
        Ui.requestUpdate();
        return true;
    }

    function rowAt(y, firstBaseY, step, count) {
        var heightScale = view.screenHeight.toFloat() / 260.0;
        var baselineY = 130.0 + ((y - (view.screenHeight / 2)) / heightScale);
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
            } else {
                navigateContent(-1);
            }
        } else if (key == Ui.KEY_RIGHT) {
            if (view.page == 1) {
                activate(1);
            } else if (view.page == 5) {
                handleSettings(1);
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
        if (view.page == 2 || view.page == 3) {
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
