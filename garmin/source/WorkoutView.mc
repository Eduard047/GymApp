using Toybox.Attention as Attention;
using Toybox.Communications as Comm;
using Toybox.Graphics as Gfx;
using Toybox.Lang as Lang;
using Toybox.Timer as Timer;
using Toybox.WatchUi as Ui;

class WorkoutView extends Ui.View {
    var selected = 0;
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
        GymComm.requestSync(method(:onSyncSent));
        flushPending();
    }

    function onHide() {
        ticker.stop();
        GymStore.save();
    }

    function tick() {
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
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 12, Gfx.FONT_XTINY, "GYMAPP  " + GymStore.status, Gfx.TEXT_JUSTIFY_CENTER);

        drawRow(dc, 0, 44, "EXERCISE", GymStore.currentExercise());
        drawRow(dc, 1, 86, "WEIGHT", GymStore.weight.format("%.1f") + " kg");
        drawRow(dc, 2, 128, "REPS", GymStore.reps.toString());
        drawRow(dc, 3, 170, "ADD SET", GymStore.sets.size().toString() + " saved");

        var rest = GymStore.restSeconds();
        var bottom = rest > 0 ? "REST " + rest.toString() + "s" : "FINISH / SYNC";
        drawRow(dc, 4, 212, bottom, rest > 0 ? "ENTER: finish" : "ENTER");
    }

    function drawRow(dc, index, y, label, value) {
        var selectedRow = index == selected;
        if (selectedRow) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
            dc.fillRoundedRectangle(18, y - 5, 224, 38, 8);
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        }
        dc.drawText(28, y, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(232, y + 13, Gfx.FONT_SMALL, value, Gfx.TEXT_JUSTIFY_RIGHT);
    }
}

class WorkoutDelegate extends Ui.BehaviorDelegate {
    var view;

    function initialize(workoutView) {
        BehaviorDelegate.initialize();
        view = workoutView;
    }

    function onKey(evt) {
        var key = evt.getKey();
        if (key == Ui.KEY_UP) {
            view.selected = (view.selected + 4) % 5;
        } else if (key == Ui.KEY_DOWN) {
            view.selected = (view.selected + 1) % 5;
        } else if (key == Ui.KEY_ENTER) {
            activate(1);
        } else if (key == Ui.KEY_ESC) {
            activate(-1);
        } else {
            return false;
        }
        Ui.requestUpdate();
        return true;
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
        } else if (view.selected == 4 && delta > 0) {
            view.finishWorkout();
        }
        GymStore.save();
    }
}
