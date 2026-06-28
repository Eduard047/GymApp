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
        var typeText = type == null ? null : type.toString();
        if (typeText != null && typeText.equals("sync")) {
            GymStore.status = "SYNC RX";
            var applied = true;
            try {
                GymStore.applySync(message);
            } catch (e) {
                applied = false;
                GymStore.status = "SYNC FAIL";
            }
            sendSyncAck(message, applied);
        } else if (typeText != null && typeText.equals("ack")) {
            if (GymStore.pending.size() > 0) {
                GymStore.pending.remove(0);
                GymStore.save();
            }
            GymStore.status = "SAVED";
        } else if (typeText == null) {
            GymStore.status = "NO TYPE";
        } else {
            GymStore.status = "MSG " + typeText;
        }
    }

    function sendSyncAck(message, applied) {
        var syncId = message.get("syncId");
        if (syncId == null) {
            return;
        }
        GymStore.status = "ACKING";
        try {
            GymComm.send({
                "type" => "sync_ack",
                "syncId" => syncId.toString(),
                "language" => GymStore.language,
                "planCount" => GymStore.plan.size(),
                "exerciseCount" => GymStore.exercises.size(),
                "applied" => applied
            }, method(:onSyncAckSent));
        } catch (e) {
            GymStore.status = "ACK FAIL";
        }
    }

    function onSyncAckSent(ok) {
        GymStore.status = ok ? "ACK OK" : "ACK ERR";
        Ui.requestUpdate();
    }
}

function getApp() as GymApp {
    return App.getApp() as GymApp;
}
