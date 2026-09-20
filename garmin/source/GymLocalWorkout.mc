using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi as Ui;

// Watch-only FREE recovery has no account, device or phone queue payload.
// One atomic value: version, FIT phase (active/prepared/saved), origin, metrics.
// Never infer an account binding from this journal or include it in sync.
(:notFr55Memory, :richWorkoutMode)
class GymLocalWorkout {
    static var snapshot as Lang.Array or Null = null;
    static var readFailed = false;
    static var lastCheckpoint as Lang.Number or Null = null;

    static function isUnbound() as Lang.Boolean {
        if (GymStore.accountBinding != null) { return false; }
        if (GymStore.deviceBinding != null) { return false; }
        if (GymStore.stateOwnerBinding != null) { return false; }
        if (GymStore.pairingGeneration != null) { return false; }
        if (GymStore.legacyUnboundState) { return false; }
        if (GymStore.sets.size() != 0) { return false; }
        return GymStore.plan.size() == 0;
    }

    static function isValid(value as Lang.Object or Null) as Lang.Boolean {
        if (!(value instanceof Lang.Array)) { return false; }
        if (value.size() != 4) { return false; }
        if (!(value[0] instanceof Lang.Number) || value[0] != 1) { return false; }
        if (!GymStore.isBoundedInteger(value[1], 0, 2)) { return false; }
        if (!GymStore.isValidWorkoutStartedAtSeconds(value[2])) { return false; }
        return GymStore.isValidTimelineCheckpoint(value[3]);
    }

    static function restore() as Void {
        snapshot = null;
        readFailed = false;
        lastCheckpoint = null;
        if (!isUnbound()) {
            return;
        }
        try {
            var saved = Storage.getValue("localFreeWorkoutV1");
            if (saved == null) {
                return;
            }
            if (!isValid(saved)) {
                // Keep an unreadable journal intact; never overwrite it with a
                // new workout or silently assign it to a newly paired account.
                readFailed = true;
                GymStore.status = GymStatus.RECOVERY_FAIL;
                return;
            }
            snapshot = saved;
            GymStore.timelineBase = saved[3];
            GymWorkoutMode.state = GymWorkoutMode.MODE_FREE;
        } catch (e) {
            readFailed = true;
            GymStore.status = GymStatus.RECOVERY_FAIL;
        }
    }

    (:inline)
    static function blocksPairing() as Lang.Boolean {
        return snapshot != null || readFailed;
    }

    static function write(value as Lang.Array or Null) as Lang.Boolean {
        if (!isUnbound() || readFailed || (value != null && !isValid(value))) {
            return false;
        }
        try {
            Storage.setValue("localFreeWorkoutV1", value);
            snapshot = value;
            lastCheckpoint = System.getTimer();
            return true;
        } catch (e) {
            GymStore.status = GymStatus.RECOVERY_FAIL;
            return false;
        }
    }

    static function checkpoint(force as Lang.Boolean) as Lang.Boolean {
        if (!isUnbound() || !GymWorkoutMode.isFree() ||
            GymSession.startedAt <= 0 || GymSession.fitSaved ||
            (snapshot != null && snapshot[1] != 0)) {
            return !readFailed;
        }
        if (!force && lastCheckpoint != null &&
            GymStore.timerElapsedMs(lastCheckpoint) < 15000l) {
            return true;
        }
        return write([1, 0, snapshot == null ? GymSession.startedAt : snapshot[2],
            GymStore.currentTimelineCheckpoint(0.0)]);
    }

    static function setPhase(phase as Lang.Number) as Lang.Boolean {
        return snapshot != null && write([1, phase, snapshot[2], snapshot[3]]);
    }

    static function clear() as Lang.Boolean {
        if (snapshot == null) {
            return !readFailed;
        }
        if (!write(null)) {
            return false;
        }
        GymStore.timelineBase = null;
        return true;
    }

    static function finish() as Lang.Boolean {
        if (snapshot == null || readFailed) {
            return false;
        }
        if (snapshot[1] == 0 && (!checkpoint(true) || !setPhase(1))) {
            return false;
        }
        if (snapshot[1] != 2) {
            // An old process cannot report the result of its native FIT save.
            // Only the recovery menu may resolve this explicit crash window.
            if (GymSession.fitOutcomeUnknownAfterRestart()) {
                return false;
            }
            if (!GymSession.fitSaved && !GymSession.stopAndSave()) {
                GymStore.status = GymStatus.FIT_FAIL;
                return false;
            }
            if (!setPhase(2)) {
                return false;
            }
        }
        return GymStore.clearActiveWorkout();
    }

    static function needsDecision() as Lang.Boolean {
        return snapshot != null && snapshot[1] != 0;
    }

    static function recoveryView() as Lang.Array {
        var menu = new Ui.Menu2({:title => GymStore.tr(
            "Check watch history", "Перевірте історію", "Проверьте историю")});
        menu.addItem(new Ui.MenuItem(GymStore.tr("Later", "Пізніше", "Позже"),
            GymStore.tr("Recovery is kept", "Дані збережені", "Данные сохранены"), 0, {}));
        if (snapshot[1] == 1) {
            menu.addItem(new Ui.MenuItem(GymStore.tr(
                "Continue workout", "Продовжити", "Продолжить"), GymStore.tr(
                "Starts a new activity", "Нова активність", "Новая активность"), 1, {}));
        }
        menu.addItem(new Ui.MenuItem(GymStore.tr(
            "Already saved", "Уже збережено", "Уже сохранено"), null, 2, {}));
        return [menu, new GymLocalRecoveryDelegate()];
    }
}

// The FR55 has too little memory for a second crash-recovery journal. Keep
// the startup and workout call surface, while letting normal FIT completion
// proceed without allocating the recovery menu or writing recovery state.
(:fr55Memory)
class GymLocalWorkout {
    static var snapshot as Lang.Array or Null = null;
    static var readFailed = false;

    static function restore() as Void {
    }

    (:inline)
    static function blocksPairing() as Lang.Boolean {
        return false;
    }

    static function checkpoint(force as Lang.Boolean) as Lang.Boolean {
        return true;
    }

    static function clear() as Lang.Boolean {
        return true;
    }

    static function finish() as Lang.Boolean {
        return false;
    }

    static function needsDecision() as Lang.Boolean {
        return false;
    }

    static function recoveryView() as Lang.Array {
        return [];
    }
}

// 96 KiB products keep owner-bound active workouts and FIT state, but omit the
// separate ownerless free-workout recovery journal. Leave any released value
// untouched so this build never reassigns or silently deletes user data.
(:compactWorkoutMode96)
class GymLocalWorkout {
    static var snapshot as Lang.Array or Null = null;
    static var readFailed = false;

    static function restore() as Void {
    }

    (:inline)
    static function blocksPairing() as Lang.Boolean {
        return false;
    }

    static function checkpoint(force as Lang.Boolean) as Lang.Boolean {
        return true;
    }

    static function clear() as Lang.Boolean {
        return true;
    }

    static function finish() as Lang.Boolean {
        return false;
    }

    static function needsDecision() as Lang.Boolean {
        return false;
    }

    static function recoveryView() as Lang.Array {
        return [];
    }
}

(:notFr55Memory, :richWorkoutMode)
class GymLocalRecoveryDelegate extends Ui.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as Ui.MenuItem) as Void {
        var action = item.getId();
        if (action == 0) {
            System.exit();
        } else if (action == 1 && GymLocalWorkout.snapshot != null &&
            GymLocalWorkout.snapshot[1] == 1 && GymLocalWorkout.setPhase(0)) {
            // The athlete explicitly chooses a new FIT segment. Stay on Ready;
            // sensors and recording still require a separate Resume gesture.
            var view = new WorkoutView();
            Ui.switchToView(view, new WorkoutDelegate(view), Ui.SLIDE_IMMEDIATE);
        } else if (action == 2) {
            var confirmation = new Ui.Menu2({:title => GymStore.tr(
                "Saved in history?", "Є в історії?", "Есть в истории?")});
            confirmation.addItem(new Ui.MenuItem(GymStore.tr(
                "No, keep", "Ні, залишити", "Нет, оставить"), null, 0, {}));
            confirmation.addItem(new Ui.MenuItem(GymStore.tr(
                "Yes, close", "Так, завершити", "Да, завершить"), null, 1, {}));
            Ui.pushView(confirmation, new GymLocalFinishDelegate(confirmation),
                Ui.SLIDE_IMMEDIATE);
        }
    }

    function onBack() as Void {
        System.exit();
    }
}

(:notFr55Memory, :richWorkoutMode)
class GymLocalFinishDelegate extends Ui.Menu2InputDelegate {
    var menu;
    function initialize(confirmation) {
        Menu2InputDelegate.initialize();
        menu = confirmation;
    }

    function onSelect(item as Ui.MenuItem) as Void {
        if (item.getId() == 1) {
            if (GymLocalWorkout.clear()) {
                System.exit();
            } else {
                menu.setTitle(GymStore.tr("Save failed", "Не збережено", "Не сохранено"));
            }
        } else {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
        }
    }

    function onBack() as Void {
        Ui.popView(Ui.SLIDE_IMMEDIATE);
    }
}
