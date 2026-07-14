using Toybox.Communications as Comm;
import Toybox.Application.Properties;
using Toybox.Lang as Lang;
using Toybox.PersistedContent as PersistedContent;

class GymCloudPlanListener {
    hidden var callback;

    function initialize(resultCallback) {
        callback = resultCallback;
    }

    function onReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void {
        if (callback == null) {
            return;
        }
        if (responseCode != 200) {
            callback.invoke(false, "HTTP " + responseCode.toString(), null);
            return;
        }
        if (!(data instanceof Lang.Dictionary)) {
            callback.invoke(false, "BAD JSON", null);
            return;
        }
        var status = data.get("status");
        var statusText = status == null ? "" : status.toString();
        if (statusText.equals("empty")) {
            callback.invoke(true, "CLOUD EMPTY", null);
            return;
        }
        if (!statusText.equals("ok")) {
            var error = data.get("error");
            callback.invoke(false, error == null ? "CLOUD ERR" : error.toString(), null);
            return;
        }
        var message = GymComm.syncMessageFromCloudData(data);
        if (message == null) {
            callback.invoke(false, "BAD PLAN", null);
            return;
        }
        callback.invoke(true, "CLOUD PLAN", message);
    }
}

class GymCloudAckListener {
    hidden var callback;

    function initialize(resultCallback) {
        callback = resultCallback;
    }

    function onReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void {
        if (callback == null) {
            return;
        }
        if (responseCode != 200 || !(data instanceof Lang.Dictionary)) {
            callback.invoke(false);
            return;
        }
        var status = data.get("status");
        var acknowledged = status instanceof Lang.String &&
            (status.toString().equals("acknowledged") ||
                status.toString().equals("already_acknowledged"));
        callback.invoke(acknowledged);
    }
}

class GymCommListener extends Comm.ConnectionListener {
    hidden var callback;

    function initialize(resultCallback) {
        ConnectionListener.initialize();
        callback = resultCallback;
    }

    function onComplete() {
        if (callback != null) {
            callback.invoke(true);
        }
    }

    function onError() {
        if (callback != null) {
            callback.invoke(false);
        }
    }
}

class GymComm {
    static var watchVersion = "2026.06.29.1205";
    static var cloudSyncUrl = "https://owrcbsrectdgaotndtxy.supabase.co/functions/v1/garmin-sync";

    static function send(message, callback) {
        Comm.transmit(message, null, new GymCommListener(callback));
    }

    static function requestSync(callback) {
        if (!GymStore.hasAccountBinding()) {
            callback.invoke(false);
            return;
        }
        var requestId = GymStore.nextRequestId("sync");
        send({
            "type" => "request_sync",
            "bindingVersion" => GymStore.bindingVersion,
            "requestId" => requestId,
            "accountBinding" => GymStore.accountBinding,
            "deviceBinding" => GymStore.deviceBinding,
            "watchVersion" => watchVersion,
            "status" => GymStore.status
        }, callback);
    }

    static function requestCloudPlan(callback) {
        var token = Properties.getValue("CloudDeviceToken");
        if (!GymStore.isValidAccountBinding(token)) {
            callback.invoke(false, "NO TOKEN", null);
            return;
        }
        var listener = new GymCloudPlanListener(callback);
        Comm.makeWebRequest(
            cloudSyncUrl,
            {
                "action" => "fetchPlan",
                "deviceToken" => token.toString()
            },
            {
                :method => Comm.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            listener.method(:onReceive)
        );
    }

    static function acknowledgeCloudPlan(message, callback) {
        var token = Properties.getValue("CloudDeviceToken");
        var planId = message instanceof Lang.Dictionary ? message.get("planId") : null;
        var planRevision = message instanceof Lang.Dictionary ? message.get("planRevision") : null;
        if (!GymStore.isValidAccountBinding(token) ||
            !GymStore.syncBindingsMatch(message) ||
            !GymStore.isBoundedText(planId, 36) || planId.toString().length() != 36 ||
            !GymStore.isValidCounter(planRevision, GymStore.maxCloudPlanRevision)) {
            callback.invoke(false);
            return;
        }
        var listener = new GymCloudAckListener(callback);
        Comm.makeWebRequest(
            cloudSyncUrl,
            {
                "action" => "ackPlan",
                "deviceToken" => token.toString(),
                "planId" => planId.toString(),
                "planRevision" => planRevision
            },
            {
                :method => Comm.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            listener.method(:onReceive)
        );
    }

    static function hasCloudDeviceToken() {
        var token = Properties.getValue("CloudDeviceToken");
        return GymStore.isValidAccountBinding(token);
    }

    static function syncMessageFromCloudData(data) {
        var bindingVersion = data.get("bindingVersion");
        var accountBinding = data.get("accountBinding");
        var deviceBinding = data.get("deviceBinding");
        var planId = data.get("planId");
        var planRevision = data.get("planRevision");
        if (!(bindingVersion instanceof Lang.Number) || bindingVersion != 2 ||
            !GymStore.isValidAccountBinding(accountBinding) ||
            !GymStore.isBoundedText(deviceBinding, GymStore.maxBindingLength) ||
            !GymStore.isBoundedText(planId, 36) || planId.toString().length() != 36 ||
            !GymStore.isValidCounter(planRevision, GymStore.maxCloudPlanRevision)) {
            return null;
        }
        var plan = data.get("plan");
        if (!(plan instanceof Lang.Dictionary)) {
            return null;
        }
        var source = plan.get("source");
        var version = plan.get("version");
        var title = plan.get("title");
        var note = plan.get("note");
        var createdAt = plan.get("createdAt");
        var startedAt = plan.get("startedAt");
        if (!GymStore.isBoundedText(source, 32) ||
            !(version instanceof Lang.Number) || version != 1 ||
            !GymStore.isBoundedText(title, 120) ||
            !(note instanceof Lang.String) || note.toString().length() > 2000 ||
            !GymStore.isBoundedText(createdAt, 40) ||
            !GymStore.isBoundedText(startedAt, 40)) {
            return null;
        }
        var exercises = plan.get("exercises");
        if (!(exercises instanceof Lang.Array) || exercises.size() > GymStore.maxPlanSets) {
            return null;
        }
        var names = [];
        var weights = [];
        var reps = [];
        for (var i = 0; i < exercises.size(); i += 1) {
            var exercise = exercises[i];
            if (!(exercise instanceof Lang.Dictionary)) {
                return null;
            }
            var name = exercise.get("name");
            var sets = exercise.get("sets");
            if (!GymStore.isValidExerciseName(name) ||
                !(sets instanceof Lang.Array) ||
                sets.size() == 0 ||
                sets.size() > GymStore.maxPlanSets ||
                names.size() + sets.size() > GymStore.maxPlanSets) {
                return null;
            }
            for (var s = 0; s < sets.size(); s += 1) {
                var setItem = sets[s];
                if (!(setItem instanceof Lang.Dictionary)) {
                    return null;
                }
                var weight = setItem.get("weight");
                var rep = setItem.get("reps");
                var orderIndex = setItem.get("orderIndex");
                if (!GymStore.isValidWeight(weight) || !GymStore.isValidReps(rep) ||
                    !(orderIndex instanceof Lang.Number) || orderIndex != s) {
                    return null;
                }
                names.add(name.toString());
                weights.add(weight);
                reps.add(rep);
            }
        }
        if (names.size() == 0) {
            return null;
        }
        if (!GymStore.isValidExerciseList(names, GymStore.maxPlanSets)) {
            return null;
        }
        var requestId = planId.toString() + "-" + planRevision.toString();
        if (!GymStore.isBoundedText(requestId, GymStore.maxBindingLength)) {
            return null;
        }
        return {
            "type" => "sync",
            "bindingVersion" => GymStore.bindingVersion,
            "syncId" => requestId,
            "requestId" => requestId,
            "bindingSource" => "cloud",
            "accountBinding" => accountBinding.toString(),
            "deviceBinding" => deviceBinding.toString(),
            "planId" => planId.toString(),
            "planRevision" => planRevision,
            "resetWorkout" => false,
            "planNames" => names,
            "planWeights" => weights,
            "planReps" => reps
        };
    }
}
