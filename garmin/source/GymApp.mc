using Toybox.Application as App;
using Toybox.Communications as Comm;
using Toybox.Lang as Lang;
using Toybox.WatchUi as Ui;

class GymApp extends App.AppBase {
    hidden var phoneMessageMethod;
    var finishedDurably = false;
    (:fr55Memory) var startupState = null;

    function initialize() {
        AppBase.initialize();
        if (GymWorkoutMode.recordingSetLimit == 30) {
            // Separate native lifecycle callbacks bound startup CPU work: basic
            // state, the immutable queue, then active recovery. Every validator
            // still runs before a workout view or phone listener is installed.
            startupState = GymStore.beginLoad();
        } else {
            GymStore.load();
            finishInitialization();
        }
    }

    function finishInitialization() {
        GymLocalWorkout.restore();
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
        if (GymWorkoutMode.recordingSetLimit == 30) { GymPendingJournal.load(); }
    }

    function onStop(state) {
        // Finishing already committed the queue and cleared the active snapshot.
        // Its exit-only cache release must never be written back as an empty plan.
        if (finishedDurably) { return; }
        if (!GymStore.keepsSetDiagnostics) { GymSession.stopSensors(); }
        GymStore.checkpointLiveWorkout(true);
        GymStore.save();
    }

    function getInitialView() {
        if (GymWorkoutMode.recordingSetLimit == 30 && startupState != null) {
            GymStore.completeLoad(startupState);
            startupState = null;
            finishInitialization();
        }
        if (GymLocalWorkout.needsDecision()) {
            return GymLocalWorkout.recoveryView();
        }
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
        GymStore.status = GymStatus.MSG_ERR;
        Ui.requestUpdate();
    }

    function pollMailbox() {
        // The modern listener immediately delivers queued messages at registration.
        // Polling the deprecated mailbox as well duplicates its native allocation.
        if ((Comm has :registerForPhoneAppMessages) || !(Comm has :getMailbox)) {
            return;
        }
        try {
            onMail(Comm.getMailbox());
        } catch (e) {
            GymStore.status = GymStatus.MAIL_ERR;
        }
    }

    function handlePhonePayload(message) {
        if (!(message instanceof Lang.Dictionary)) {
            GymStore.status = GymStatus.BAD_MSG;
            return;
        }
        var type = message.get("type");
        if (!(type instanceof Lang.String) || type.toString().length() > 32) {
            GymStore.status = GymStatus.BAD_MSG;
            return;
        }
        var typeText = type.toString();
        if (typeText != null && typeText.equals("sync")) {
            // After a durable finish only acks are useful; a sync is dropped.
            if (!finishedDurably) { handleSyncMessage(message); }
        } else if (typeText.equals("workout_part_ack")) {
            if (GymPendingJournal.acknowledgePart(message)) { sendNextPendingWorkout(); }
        } else if (typeText != null && typeText.equals("ack")) {
            var ackRequestId = message.get("requestId");
            if (GymStore.bindingsMatch(message) && GymStore.removePendingByRequestId(ackRequestId)) {
                GymStore.status = GymStatus.SAVED;
                sendNextPendingWorkout();
            } else {
                GymStore.status = GymStatus.BAD_ACK;
            }
        } else {
            GymStore.status = "MSG " + typeText;
        }
    }

    (:richWorkoutMode, :noMem128)
    function handleSyncMessage(message) {
        GymStore.status = GymStatus.SYNC_RX;
        var applied = false;
        try {
            applied = GymStore.applyPhoneSync(message);
        } catch (e) {
            applied = false;
            GymStore.status = GymStatus.SYNC_FAIL;
        }
        sendSyncAck(message, applied, null);
    }

    // 128 KiB watches refuse a plan larger than their tier limit before any
    // copy or replay check, so a resend is refused again. Pairing fields are
    // still applied with the lite-style empty plan, and the ack reports
    // applied=false with a reason. A catalog over the limit is trimmed to the
    // entries that fit and the sync continues.
    (:mem128)
    function handleSyncMessage(message) {
        GymStore.status = GymStatus.SYNC_RX;
        var reason = null;
        if (!GymStore.syncFitsMemory(message)) {
            reason = "plan_too_large";
            message.put("planNames", []);
            message.put("planWeights", []);
            message.put("planReps", []);
            message.put("exercises", []);
        } else {
            GymStore.trimSyncCatalog(message);
        }
        var applied = false;
        try {
            applied = GymStore.applyPhoneSync(message);
        } catch (e) {
            applied = false;
            GymStore.status = GymStatus.SYNC_FAIL;
        }
        sendSyncAck(message, reason == null && applied, reason);
    }

    // 96 KiB watches run free workouts only. A sync is applied for its pairing
    // and language fields with the same validation as every other profile; the
    // plan columns and catalog are dropped first and never copied or stored.
    (:compactWorkoutMode96)
    function handleSyncMessage(message) {
        GymStore.status = GymStatus.SYNC_RX;
        message.put("planNames", []);
        message.put("planWeights", []);
        message.put("planReps", []);
        message.remove("exercises");
        var applied = false;
        try {
            applied = GymStore.applyPhoneSync(message);
        } catch (e) {
            applied = false;
            GymStore.status = GymStatus.SYNC_FAIL;
        }
        sendSyncAck(message, applied);
    }

    // Lean acknowledgement: the correlation and binding fields plus the
    // additive lite=1 marker; no plan counts.
    (:compactWorkoutMode96)
    function sendSyncAck(message, applied) {
        var syncId = message.get("syncId");
        var syncRevision = message.get("syncRevision");
        if (!GymStore.isBoundedText(syncId, GymStore.maxBindingLength) ||
            !syncId.equals(message.get("requestId")) ||
            !GymStore.isValidCounter(syncRevision, GymStore.maxPhoneSyncRevision) ||
            !GymStore.bindingsMatch(message)) {
            return;
        }
        message = null;
        GymStore.status = GymStatus.ACKING;
        try {
            var ack = {
                "type" => "sync_ack",
                "bindingVersion" => GymStore.bindingVersion,
                "syncId" => syncId,
                "requestId" => syncId,
                "syncRevision" => syncRevision.toLong(),
                "accountBinding" => GymStore.accountBinding,
                "deviceBinding" => GymStore.deviceBinding,
                "applied" => applied,
                "lite" => 1
            };
            if (GymStore.isValidAccountBinding(GymStore.pairingGeneration)) {
                ack.put("pairingGeneration", GymStore.pairingGeneration);
            }
            GymComm.send(ack, method(:onSyncAckSent));
        } catch (e) {
            GymStore.status = GymStatus.ACK_FAIL;
        }
    }

    (:richWorkoutMode)
    function sendSyncAck(message, applied, reason) {
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
        GymStore.status = GymStatus.ACKING;
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
            if (reason != null) {
                ack.put("reason", reason);
            }
            GymComm.send(ack, method(:onSyncAckSent));
        } catch (e) {
            GymStore.status = GymStatus.ACK_FAIL;
        }
    }

    function onSyncAckSent(ok) {
        GymStore.status = ok ? GymStatus.ACK_OK : GymStatus.ACK_ERR;
        if (ok) {
            // A queued workout may have been waiting while the phone repaired the
            // secure pairing. Retry only the oldest item and keep it until the
            // Android database acknowledgement arrives.
            sendNextPendingWorkout();
        }
        Ui.requestUpdate();
    }

    function sendNextPendingWorkout() {
        if (!GymStore.hasAccountBinding() || GymStore.pendingCount() == 0) {
            return;
        }
        if (!GymStore.recoverQueuedWorkout()) {
            GymStore.status = GymStatus.DATA_KEPT;
            return;
        }
        // Drain exactly one oldest item per durable database acknowledgement. The
        // item remains queued until its own ack, so disconnects and retries are safe.
        GymStore.status = GymStatus.SENDING_NEXT;
        var message = GymStore.pendingMessage();
        if (message != null) { GymComm.send(message, method(:onPendingWorkoutSentAfterSync)); }
    }

    function onPendingWorkoutSentAfterSync(ok) {
        GymStore.status = ok ? GymStatus.WAITING_ACK : GymStatus.QUEUED;
        Ui.requestUpdate();
    }
}

function getApp() as GymApp {
    return App.getApp() as GymApp;
}
