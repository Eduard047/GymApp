using Toybox.Attention as Attention;
using Toybox.Communications as Comm;
using Toybox.Graphics as Gfx;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Timer as Timer;
using Toybox.WatchUi as Ui;

class WorkoutView extends Ui.View {
    var selected = 0;
    var page = 0;
    var pauseSelected = 0;
    var ticker;
    var restWasActive = false;

    function initialize() {
        View.initialize();
        GymStore.load();
        Comm.setMailboxListener(method(:onMail));
        ticker = new Timer.Timer();
    }

    function onShow() {
        ticker.start(method(:tick), 1000, true);
        if (!GymSession.recording) {
            GymSession.start();
        } else {
            GymSession.startSensors();
        }
        GymComm.requestSync(method(:onSyncSent));
        flushPending();
    }

    function onHide() {
        ticker.stop();
        GymSession.stopSensors();
        GymStore.save();
    }

    function tick() {
        GymSession.tick();
        var active = GymStore.restSeconds() > 0;
        if (restWasActive && !active) {
            Attention.vibrate([new Attention.VibeProfile(100, 500), new Attention.VibeProfile(100, 500)]);
            GymStore.status = "REST DONE";
        }
        restWasActive = active;
        Ui.requestUpdate();
    }

    function onSyncSent(ok) {
        GymStore.status = ok ? "PHONE..." : "OFFLINE";
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
        GymStore.save();
        GymComm.send(message, method(:onWorkoutSent));
        Attention.vibrate([new Attention.VibeProfile(80, 250)]);
    }

    function saveAndExit() {
        finishWorkout();
        GymSession.stopAndSave();
        System.exit();
    }

    function onMail(iterator as Comm.MailboxIterator) as Void {
        var message = iterator.next();
        while (message != null) {
            if (message instanceof Lang.Dictionary) {
                var type = message.get("type");
                if (type == "sync") {
                    GymStore.applySync(message);
                } else if (type == "ack") {
                    if (GymStore.pending.size() > 0) {
                        GymStore.pending.remove(0);
                        GymStore.save();
                    }
                    GymStore.status = "SAVED";
                }
            }
            message = iterator.next();
        }
        Comm.emptyMailbox();
        Ui.requestUpdate();
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
        } else {
            drawSummary(dc, w, h);
        }
    }

    function drawDashboard(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 10, Gfx.FONT_XTINY, "GYMAPP STRENGTH", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 32, Gfx.FONT_MEDIUM, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);

        var hrText = GymSession.hr == null ? "--" : GymSession.hr.toString();
        var garminKcal = GymSession.garminCalories == null ? "--" : GymSession.garminCalories.toString();

        dc.setColor(zoneColor(GymSession.zone), Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 54, Gfx.FONT_NUMBER_HOT, hrText, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 120, Gfx.FONT_XTINY, "bpm  " + zoneLabel(GymSession.zone), Gfx.TEXT_JUSTIFY_CENTER);

        drawHeartRateZones(dc, w, 148);

        drawCompactValue(dc, 72, 184, "GYM", GymSession.gymCalories.format("%.0f"));
        drawCompactValue(dc, 188, 184, "GARMIN", garminKcal);

        dc.setColor(stateColor(GymSession.effortState), Gfx.COLOR_TRANSPARENT);
        var stateText = GymSession.autoLogPrompt ? "LOG SET?" : GymSession.effortState;
        dc.drawText(w / 2, 212, Gfx.FONT_XTINY, stateText, Gfx.TEXT_JUSTIFY_CENTER);

        var rest = GymStore.restSeconds();
        var footer = GymSession.autoLogPrompt ? "select: save set" : (rest > 0 ? ("REST " + rest.toString() + "s") : "start: pause  tap: edit");
        dc.setColor(rest > 0 ? Gfx.COLOR_YELLOW : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 228, Gfx.FONT_XTINY, footer, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawCompactValue(dc, x, y, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y + 16, Gfx.FONT_XTINY, value, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawHeartRateZones(dc, w, y) {
        var left = 34;
        var segmentWidth = 38;
        var gap = 4;
        for (var i = 1; i <= 5; i += 1) {
            var x = left + ((i - 1) * (segmentWidth + gap));
            dc.setColor(zoneColor(i), Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, segmentWidth, 12, 4);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x + (segmentWidth / 2), y + 15, Gfx.FONT_XTINY, "Z" + i.toString(), Gfx.TEXT_JUSTIFY_CENTER);
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
        if (state == "SET ACTIVE") {
            return Gfx.COLOR_GREEN;
        } else if (state == "REST") {
            return Gfx.COLOR_BLUE;
        } else if (state == "READY") {
            return Gfx.COLOR_YELLOW;
        }
        return Gfx.COLOR_LT_GRAY;
    }

    function drawEntry(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 10, Gfx.FONT_XTINY, "SET ENTRY", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 34, Gfx.FONT_SMALL, fitText(GymStore.currentExercise(), 18), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 72, Gfx.FONT_MEDIUM, GymStore.weight.format("%.1f") + " kg x " + GymStore.reps.toString(), Gfx.TEXT_JUSTIFY_CENTER);

        drawRow(dc, 0, 112, "EXERCISE", "next");
        drawRow(dc, 1, 150, "WEIGHT", "+/- " + GymStore.weightStep.format("%.1f"));
        drawRow(dc, 2, 188, "REPS", "+/- 1");
        drawRow(dc, 3, 212, "SAVE SET", GymStore.sets.size().toString());

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 236, Gfx.FONT_XTINY, "select row  back: main", Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawPauseMenu(dc, w, h) {
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 28, Gfx.FONT_SMALL, "PAUSED", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 58, Gfx.FONT_MEDIUM, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);

        drawMenuRow(dc, 0, 104, "RESUME");
        drawMenuRow(dc, 1, 146, "SAVE");
        drawMenuRow(dc, 2, 188, "DISCARD");

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 226, Gfx.FONT_XTINY, "up/down  start/select", Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawSummary(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 12, Gfx.FONT_XTINY, "SAVE SUMMARY", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 38, Gfx.FONT_SMALL, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);
        drawSummaryValue(dc, 70, 78, "GYM", GymSession.gymCalories.format("%.0f"));
        var garminKcal = GymSession.garminCalories == null ? "--" : GymSession.garminCalories.toString();
        drawSummaryValue(dc, 190, 78, "GARMIN", garminKcal);
        drawSummaryValue(dc, 70, 128, "AVG HR", GymSession.avgHr.toString());
        drawSummaryValue(dc, 190, 128, "MAX HR", GymSession.maxHr.toString());
        drawSummaryValue(dc, 130, 178, "SETS", GymStore.sets.size().toString());

        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 218, Gfx.FONT_XTINY, "select: save  back: pause", Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawSummaryValue(dc, x, y, label, value) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y + 17, Gfx.FONT_SMALL, value, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawMenuRow(dc, index, y, label) {
        if (index == pauseSelected) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(48, y - 6, 164, 34, 8);
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(130, y, Gfx.FONT_SMALL, label, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawRow(dc, index, y, label, value) {
        var selectedRow = index == selected;
        if (selectedRow) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(36, y - 5, 188, 36, 8);
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(46, y, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(214, y + 11, Gfx.FONT_SMALL, value, Gfx.TEXT_JUSTIFY_RIGHT);
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
        handleSelect();
        return true;
    }

    function onNextPage() {
        if (view.page == 2) {
            return true;
        }
        view.page = 1;
        Ui.requestUpdate();
        return true;
    }

    function onPreviousPage() {
        if (view.page == 3) {
            view.page = 2;
        } else if (view.page == 2) {
            view.page = 0;
        } else if (view.page == 1) {
            view.page = 0;
        } else {
            view.page = 1;
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
        if (view.page == 1) {
            view.page = 0;
            Ui.requestUpdate();
            return true;
        }
        if (!GymSession.paused) {
            GymSession.pause();
        }
        view.page = 2;
        Ui.requestUpdate();
        return true;
    }

    function onTap(evt) {
        if (view.page == 3) {
            view.saveAndExit();
        } else if (view.page == 2) {
            handlePauseMenu();
        } else if (view.page == 0 && GymSession.autoLogPrompt) {
            GymStore.addSet();
        } else if (view.page == 0) {
            view.page = 1;
        } else {
            handleSelect();
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
        } else if (direction == Ui.SWIPE_LEFT || direction == Ui.SWIPE_RIGHT) {
            view.page = view.page == 0 ? 1 : 0;
        } else if (direction == Ui.SWIPE_UP && view.page == 1) {
            view.selected = (view.selected + 1) % 4;
        } else if (direction == Ui.SWIPE_DOWN && view.page == 1) {
            view.selected = (view.selected + 3) % 4;
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
        } else if (key == Ui.KEY_ENTER) {
            if (view.page == 3) {
                view.saveAndExit();
            } else if (view.page == 2) {
                handlePauseMenu();
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
                view.page = GymSession.paused ? 2 : 0;
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
        if (view.page == 0 && GymSession.autoLogPrompt) {
            GymStore.addSet();
        } else if (view.page == 0) {
            view.page = 1;
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
            GymStore.addSet();
            Attention.vibrate([new Attention.VibeProfile(60, 150)]);
        }
        GymStore.save();
    }
}

