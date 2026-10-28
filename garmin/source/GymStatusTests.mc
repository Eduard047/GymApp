using Toybox.Test;
using Toybox.Lang;

(:test)
function statusCodesPreservePhoneAndDiagnosticText(logger as Test.Logger) as Lang.Boolean {
    var rows = [
        [10, "STORE FULL"],
        [329, "SET LIMIT"],
        [615, "MSG ERR"],
        [840, "MAIL ERR"],
        [1095, "BAD MSG"],
        [1319, "SYNC RX"],
        [1545, "SYNC FAIL"],
        [1829, "SAVED"],
        [1991, "BAD ACK"],
        [2214, "ACKING"],
        [2408, "ACK FAIL"],
        [2662, "ACK OK"],
        [2855, "ACK ERR"],
        [3081, "DATA KEPT"],
        [3372, "SENDING NEXT"],
        [3755, "WAITING ACK"],
        [4102, "QUEUED"],
        [4301, "RECOVERY FAIL"],
        [4712, "FIT FAIL"],
        [4970, "PAUSE FAIL"],
        [5289, "MODE FAIL"],
        [5577, "FIT RETRY"],
        [5864, "REC FAIL"],
        [6123, "RESUME FAIL"],
        [6476, "MOTION SHORT"],
        [6856, "HR SHORT"],
        [7115, "SET SKIPPED"],
        [7461, "READY"],
        [7627, "LEGACY SAFE"],
        [7979, "LEGACY FULL"],
        [8329, "FIT SAVED"],
        [8617, "FIT CHECK"],
        [8905, "SAVE FAIL"],
        [9193, "PLAN ONLY"],
        [9481, "SET SAVED"],
        [9772, "UNDO EXPIRED"],
        [10154, "SET UNDONE"],
        [10472, "BAD SYNC"],
        [10728, "BAD BIND"],
        [10984, "PAIR OLD"],
        [11240, "SYNC OLD"],
        [11496, "SYNC DUP"],
        [11753, "PAIR WAIT"],
        [12042, "TOKEN SAVE"],
        [12359, "SYNC OK"],
        [12585, "PLAN WAIT"],
        [12874, "EMPTY PLAN"],
        [13195, "QUEUED SAFE"],
        [13545, "SYNC FULL"],
        [13834, "QUEUE FULL"],
        [14151, "NO PLAN"],
        [14374, "REOPEN"],
        [14570, "SET ACTIVE"],
        [14889, "REST DONE"],
        [15179, "CONFIRM SET"],
        [15532, "REST RESUMED"],
        [15912, "SYNC REQ"],
        [16168, "NO PHONE"],
        [16424, "CLOUD..."],
        [16682, "CLOUD FAIL"],
        [17003, "CLOUD RETRY"],
        [17351, "OFFLINE"],
        [17578, "START FAIL"],
        [17895, "RESUMED"],
        [18119, "CONFIRM"],
        [18348, "QUEUE BROKEN"],
        [18732, "PHONE SILENT"],
        [19116, "RATE LIMITED"],
        [19502, "RESET REQUIRED"],
        [19951, "WORKOUT REFUSED"]
    ];
    for (var i = 0; i < rows.size(); i += 1) {
        if (!GymStatus.text(rows[i][0]).equals(rows[i][1])) { return false; }
    }
    return GymStatus.text("HTTP 503").equals("HTTP 503") &&
        GymStatus.text("PLAN 12").equals("PLAN 12") && GymStatus.text(null) == null;
}

// A status that still says "waiting for the phone" after an own transmit turns
// into PHONE_SILENT after 60 s; an inbound phone message ends the wait.
(:test, :notFr55Memory)
function silentPhoneAfterTransmitExpiresOnlyWhileWaiting(logger as Test.Logger) as Lang.Boolean {
    var previous = GymStore.status;
    GymStore.status = GymStatus.SYNC_REQ;
    GymComm.awaitingPhoneSince = Toybox.System.getTimer() - 30000;
    var early = GymComm.expireSilence();
    GymComm.awaitingPhoneSince = Toybox.System.getTimer() - 61000;
    var late = GymComm.expireSilence();
    var ok = !early && late && (GymStore.status == GymStatus.PHONE_SILENT) &&
        GymComm.awaitingPhoneSince == null;
    GymStore.status = GymStatus.WAITING_ACK;
    GymComm.awaitingPhoneSince = Toybox.System.getTimer() - 61000;
    GymComm.noteActivity();
    ok = ok && !GymComm.expireSilence() && (GymStore.status == GymStatus.WAITING_ACK);
    GymStore.status = GymStatus.SAVED;
    GymComm.awaitingPhoneSince = Toybox.System.getTimer() - 61000;
    ok = ok && !GymComm.expireSilence() && (GymStore.status == GymStatus.SAVED);
    GymComm.awaitingPhoneSince = null;
    GymStore.status = previous;
    return ok;
}
