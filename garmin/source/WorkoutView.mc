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
        } else {
            drawEntry(dc, w, h);
        }
    }

    function drawDashboard(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 10, Gfx.FONT_XTINY, "GYMAPP STRENGTH", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 34, Gfx.FONT_LARGE, GymSession.elapsedText(), Gfx.TEXT_JUSTIFY_CENTER);

        var hrText = GymSession.hr == null ? "--" : GymSession.hr.toString();
        var zText = GymSession.zone == 0 ? "Z-" : "Z" + GymSession.zone.toString();
        var garminKcal = GymSession.garminCalories == null ? "--" : GymSession.garminCalories.toString();

        drawMetric(dc, 56, 94, "HR", hrText, "bpm");
        drawMetric(dc, 164, 94, "ZONE", zText, "");
        drawMetric(dc, 56, 154, "GYM KCAL", GymSession.gymCalories.format("%.0f"), "");
        drawMetric(dc, 164, 154, "GARM KCAL", garminKcal, "");

        var rest = GymStore.restSeconds();
        var footer = rest > 0 ? ("REST " + rest.toString() + "s") : "tap/right: set  back: save";
        dc.setColor(rest > 0 ? Gfx.COLOR_YELLOW : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 226, Gfx.FONT_XTINY, footer, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawMetric(dc, x, y, label, value, unit) {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - 48, y - 8, 96, 48, 10);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y - 6, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y + 10, Gfx.FONT_SMALL, value + unit, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawEntry(dc, w, h) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 10, Gfx.FONT_XTINY, "SET ENTRY  " + GymStore.status, Gfx.TEXT_JUSTIFY_CENTER);

        drawRow(dc, 0, 45, "EXERCISE", fitText(GymStore.currentExercise(), 16));
        drawRow(dc, 1, 88, "WEIGHT", GymStore.weight.format("%.1f") + "kg");
        drawRow(dc, 2, 131, "REPS", GymStore.reps.toString());
        drawRow(dc, 3, 174, "ADD SET", GymStore.sets.size().toString());

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 226, Gfx.FONT_XTINY, "swipe/tap/select  back: main", Gfx.TEXT_JUSTIFY_CENTER);
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
        return text.substring(0, maxLen - 1) + "…";
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
        view.page = 1;
        Ui.requestUpdate();
        return true;
    }

    function onPreviousPage() {
        if (view.page == 1) {
            view.page = 0;
        } else {
            view.page = 1;
        }
        Ui.requestUpdate();
        return true;
    }

    function onBack() {
        if (view.page == 1) {
            view.page = 0;
            Ui.requestUpdate();
            return true;
        }
        view.saveAndExit();
        return true;
    }

    function onTap(evt) {
        if (view.page == 0) {
            view.page = 1;
        } else {
            handleSelect();
        }
        Ui.requestUpdate();
        return true;
    }

    function onSwipe(evt) {
        var direction = evt.getDirection();
        if (direction == Ui.SWIPE_LEFT || direction == Ui.SWIPE_RIGHT) {
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
        if (key == Ui.KEY_UP && view.page == 1) {
            view.selected = (view.selected + 3) % 4;
        } else if (key == Ui.KEY_DOWN && view.page == 1) {
            view.selected = (view.selected + 1) % 4;
        } else if (key == Ui.KEY_ENTER) {
            handleSelect();
        } else if (key == Ui.KEY_ESC) {
            onBack();
        } else if (key == Ui.KEY_START) {
            handleSelect();
        } else if (key == Ui.KEY_MENU) {
            view.saveAndExit();
        } else {
            return false;
        }
        Ui.requestUpdate();
        return true;
    }

    function handleSelect() {
        if (view.page == 0) {
            view.page = 1;
        } else {
            activate(1);
        }
    }

    function activate(delta) {
        if (view.selected == 0) {
            GymStore.nextExercise(delta);
        } else if (view.selected == 1) {
            GymStore.weight += 2.5 * delta;
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
