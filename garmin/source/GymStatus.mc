using Toybox.Application;
using Toybox.Lang;

// Internal codes keep repeated state names out of resident program data.
// UI diagnostics and phone messages expand the original text only on demand.
module GymStatus {
    const STORE_FULL = 10;
    const SET_LIMIT = 329;
    const MSG_ERR = 615;
    const MAIL_ERR = 840;
    const BAD_MSG = 1095;
    const SYNC_RX = 1319;
    const SYNC_FAIL = 1545;
    const SAVED = 1829;
    const BAD_ACK = 1991;
    const ACKING = 2214;
    const ACK_FAIL = 2408;
    const ACK_OK = 2662;
    const ACK_ERR = 2855;
    const DATA_KEPT = 3081;
    const SENDING_NEXT = 3372;
    const WAITING_ACK = 3755;
    const QUEUED = 4102;
    const RECOVERY_FAIL = 4301;
    const FIT_FAIL = 4712;
    const PAUSE_FAIL = 4970;
    const MODE_FAIL = 5289;
    const FIT_RETRY = 5577;
    const REC_FAIL = 5864;
    const RESUME_FAIL = 6123;
    const MOTION_SHORT = 6476;
    const HR_SHORT = 6856;
    const SET_SKIPPED = 7115;
    const READY = 7461;
    const LEGACY_SAFE = 7627;
    const LEGACY_FULL = 7979;
    const FIT_SAVED = 8329;
    const FIT_CHECK = 8617;
    const SAVE_FAIL = 8905;
    const PLAN_ONLY = 9193;
    const SET_SAVED = 9481;
    const UNDO_EXPIRED = 9772;
    const SET_UNDONE = 10154;
    const BAD_SYNC = 10472;
    const BAD_BIND = 10728;
    const PAIR_OLD = 10984;
    const SYNC_OLD = 11240;
    const SYNC_DUP = 11496;
    const PAIR_WAIT = 11753;
    const TOKEN_SAVE = 12042;
    const SYNC_OK = 12359;
    const PLAN_WAIT = 12585;
    const EMPTY_PLAN = 12874;
    const QUEUED_SAFE = 13195;
    const SYNC_FULL = 13545;
    const QUEUE_FULL = 13834;
    const NO_PLAN = 14151;
    const REOPEN = 14374;
    const SET_ACTIVE = 14570;
    const REST_DONE = 14889;
    const CONFIRM_SET = 15179;
    const REST_RESUMED = 15532;
    const SYNC_REQ = 15912;
    const NO_PHONE = 16168;
    const CLOUD = 16424;
    const CLOUD_FAIL = 16682;
    const CLOUD_RETRY = 17003;
    const OFFLINE = 17351;
    const START_FAIL = 17578;
    const RESUMED = 17895;
    const CONFIRM = 18119;
    function text(value) {
        if (!(value instanceof Lang.Number)) { return value; }
        var start = value >> 5;
        var packed = Application.loadResource(Rez.Strings.WorkoutStatusNames);
        return packed.substring(start, start + (value & 31));
    }
}
