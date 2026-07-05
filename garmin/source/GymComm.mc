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
        send({
            "type" => "request_sync",
            "watchVersion" => watchVersion,
            "status" => GymStore.status
        }, callback);
    }

    static function requestCloudPlan(callback) {
        var token = Properties.getValue("CloudDeviceToken");
        if (token == null || token.toString().length() == 0) {
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

    static function hasCloudDeviceToken() {
        var token = Properties.getValue("CloudDeviceToken");
        return token != null && token.toString().length() > 0;
    }

    static function syncMessageFromCloudData(data) {
        var plan = data.get("plan");
        if (!(plan instanceof Lang.Dictionary)) {
            return null;
        }
        var exercises = plan.get("exercises");
        if (!(exercises instanceof Lang.Array)) {
            return null;
        }
        var names = [];
        var weights = [];
        var reps = [];
        for (var i = 0; i < exercises.size(); i += 1) {
            var exercise = exercises[i];
            if (!(exercise instanceof Lang.Dictionary)) {
                continue;
            }
            var name = exercise.get("name");
            var sets = exercise.get("sets");
            if (name == null || !(sets instanceof Lang.Array)) {
                continue;
            }
            for (var s = 0; s < sets.size(); s += 1) {
                var setItem = sets[s];
                if (!(setItem instanceof Lang.Dictionary)) {
                    continue;
                }
                names.add(name.toString());
                var weight = setItem.get("weight");
                var rep = setItem.get("reps");
                weights.add(weight == null ? 0.0 : weight);
                reps.add(rep == null ? GymStore.reps : rep);
            }
        }
        if (names.size() == 0) {
            return null;
        }
        return {
            "type" => "sync",
            "syncId" => data.get("planId") == null ? "cloud" : data.get("planId").toString(),
            "resetWorkout" => false,
            "planNames" => names,
            "planWeights" => weights,
            "planReps" => reps
        };
    }
}
