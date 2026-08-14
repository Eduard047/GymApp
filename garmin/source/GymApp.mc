using Toybox.Application as App;
using Toybox.Communications as Comm;
using Toybox.Lang as Lang;
using Toybox.WatchUi as Ui;

class GymApp extends App.AppBase {
    hidden var phoneMessageMethod;

    function initialize() {
        AppBase.initialize();
        GymStore.load();
        phoneMessageMethod = method(:onPhoneMessage);
        if (Comm has :registerForPhoneAppMessages) {
            Comm.registerForPhoneAppMessages(phoneMessageMethod);
        } else if (Comm has :setMailboxListener) {
            Comm.setMailboxListener(method(:onMail));
        }
        if (Comm has :registerForPhoneAppMessageErrors) {
            Comm.registerForPhoneAppMessageErrors(method(:onPhoneMessageError));
        }
    }

    function onStart(state) {
    }

    function onStop(state) {
        GymStore.save();
    }

    function getInitialView() {
        var view = new WorkoutView();
        return [view, new WorkoutDelegate(view)];
    }

    function allowTrialMessage() {
        // GymApp is free and has no trial/unlock flow. Development builds report
        // isTrial() as true, so suppress Garmin's lock screen in the simulator.
        return false;
    }

    function onMail(iterator as Comm.MailboxIterator) as Void {
        var message = iterator.next();
        while (message != null) {
            handlePhonePayload(message);
            message = iterator.next();
        }
        if (Comm has :emptyMailbox) {
            Comm.emptyMailbox();
        }
        Ui.requestUpdate();
    }

    function onPhoneMessage(message as Comm.PhoneAppMessage) as Void {
        handlePhonePayload(message.data);
        Ui.requestUpdate();
    }

    function onPhoneMessageError(error as Comm.PhoneAppMessageError) as Void {
        GymStore.status = "MSG ERR";
        Ui.requestUpdate();
    }

    function pollMailbox() {
        if (!(Comm has :getMailbox)) {
            return;
        }
        try {
            onMail(Comm.getMailbox());
        } catch (e) {
            GymStore.status = "MAIL ERR";
        }
    }

    function handlePhonePayload(message) {
        if (!(message instanceof Lang.Dictionary)) {
            GymStore.status = "BAD MSG";
            return;
        }
        var type = message.get("type");
        if (!(type instanceof Lang.String) || type.toString().length() > 32) {
            GymStore.status = "BAD MSG";
            return;
        }
        var typeText = type.toString();
        if (typeText != null && typeText.equals("sync")) {
            GymStore.status = "SYNC RX";
            var applied = false;
            try {
                applied = GymStore.applyPhoneSync(message);
            } catch (e) {
                applied = false;
                GymStore.status = "SYNC FAIL";
            }
            sendSyncAck(message, applied);
        } else if (typeText != null && typeText.equals("ack")) {
            var ackRequestId = message.get("requestId");
            if (GymStore.bindingsMatch(message) && GymStore.removePendingByRequestId(ackRequestId)) {
                GymStore.status = "SAVED";
                sendNextPendingWorkout();
            } else {
                GymStore.status = "BAD ACK";
            }
        } else {
            GymStore.status = "MSG " + typeText;
        }
    }

    function sendSyncAck(message, applied) {
        var syncId = message.get("syncId");
        var requestId = message.get("requestId");
        var syncRevision = message.get("syncRevision");
        if (!GymStore.isBoundedText(syncId, GymStore.maxBindingLength) ||
            !GymStore.isBoundedText(requestId, GymStore.maxBindingLength) ||
            !GymStore.isValidCounter(syncRevision, GymStore.maxPhoneSyncRevision) ||
            !syncId.toString().equals(requestId.toString()) ||
            !GymStore.bindingsMatch(message)) {
            return;
        }
        GymStore.status = "ACKING";
        try {
            var ack = {
                "type" => "sync_ack",
                "bindingVersion" => GymStore.bindingVersion,
                "syncId" => syncId.toString(),
                "requestId" => requestId.toString(),
                "syncRevision" => syncRevision.toLong(),
                "accountBinding" => GymStore.accountBinding,
                "deviceBinding" => GymStore.deviceBinding,
                "language" => GymStore.language,
                "planCount" => GymStore.plan.size(),
                "exerciseCount" => GymStore.exercises.size(),
                "applied" => applied
            };
            if (GymStore.isValidAccountBinding(GymStore.pairingGeneration)) {
                ack.put("pairingGeneration", GymStore.pairingGeneration.toString());
            }
            GymComm.send(ack, method(:onSyncAckSent));
        } catch (e) {
            GymStore.status = "ACK FAIL";
        }
    }

    function onSyncAckSent(ok) {
        GymStore.status = ok ? "ACK OK" : "ACK ERR";
        if (ok) {
            // A queued workout may have been waiting while the phone repaired the
            // secure pairing. Retry only the oldest item and keep it until the
            // Android database acknowledgement arrives.
            sendNextPendingWorkout();
        }
        Ui.requestUpdate();
    }

    function sendNextPendingWorkout() {
        if (!GymStore.hasAccountBinding() || GymStore.pending.size() == 0) {
            return;
        }
        if (!GymStore.recoverQueuedWorkout()) {
            GymStore.status = "DATA KEPT";
            return;
        }
        // Drain exactly one oldest item per durable database acknowledgement. The
        // item remains queued until its own ack, so disconnects and retries are safe.
        GymStore.status = "SENDING NEXT";
        GymComm.send(GymStore.pending[0], method(:onPendingWorkoutSentAfterSync));
    }

    function onPendingWorkoutSentAfterSync(ok) {
        GymStore.status = ok ? "WAITING ACK" : "QUEUED";
        Ui.requestUpdate();
    }
}

function getApp() as GymApp {
    return App.getApp() as GymApp;
}
