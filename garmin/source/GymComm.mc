using Toybox.Communications as Comm;
import Toybox.Application.Properties;
using Toybox.Lang as Lang;
using Toybox.PersistedContent as PersistedContent;

class GymCloudPlanListener {
    hidden var callback;
    hidden var expectedAccountBinding;
    hidden var expectedDeviceBinding;
    hidden var legacyCapability;

    function initialize(resultCallback, tokenAccountBinding, tokenDeviceBinding, isLegacyCapability) {
        callback = resultCallback;
        expectedAccountBinding = tokenAccountBinding;
        expectedDeviceBinding = tokenDeviceBinding;
        legacyCapability = isLegacyCapability;
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
        var responseAccountBinding = data.get("accountBinding");
        var responseDeviceBinding = data.get("deviceBinding");
        if (!GymStore.isValidAccountBinding(responseAccountBinding) ||
            expectedAccountBinding == null ||
            !expectedAccountBinding.toString().equals(responseAccountBinding.toString()) ||
            !GymComm.isValidCloudDeviceId(responseDeviceBinding) ||
            (expectedDeviceBinding != null &&
                !expectedDeviceBinding.toString().equals(responseDeviceBinding.toString()))) {
            if (legacyCapability) {
                GymComm.clearCloudDeviceToken();
            }
            callback.invoke(false, "TOKEN OWNER", null);
            return;
        }
        if (legacyCapability && !GymComm.rememberLegacyCloudTokenBinding(
                responseAccountBinding,
                responseDeviceBinding
            )) {
            callback.invoke(false, "TOKEN SAVE", null);
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
    static var legacyCapabilityLength = 64;
    static var cloudCapabilityLength = 234;
    static var signedOutAccountBinding = "ce5a39150e5fd2bd1a1adeb786fb05b39ee4e0395443a87ed7e2309796124d29";

    static function send(message, callback) {
        Comm.transmit(message, null, new GymCommListener(callback));
    }

    static function requestSync(callback) {
        if (!GymStore.hasAccountBinding()) {
            callback.invoke(false);
            return;
        }
        var requestId = GymStore.nextRequestId("sync");
        var request = {
            "type" => "request_sync",
            "bindingVersion" => GymStore.bindingVersion,
            "requestId" => requestId,
            "accountBinding" => GymStore.accountBinding,
            "deviceBinding" => GymStore.deviceBinding,
            "pairingGenerationSupported" => true,
            "watchVersion" => watchVersion,
            "status" => GymStore.status
        };
        if (GymStore.isValidAccountBinding(GymStore.pairingGeneration)) {
            request.put("pairingGeneration", GymStore.pairingGeneration.toString());
        }
        send(request, callback);
    }

    static function requestCloudPlan(callback) {
        var token = Properties.getValue("CloudDeviceToken");
        if (!GymStore.hasAccountBinding()) {
            callback.invoke(false, "TOKEN OWNER", null);
            return;
        }
        var tokenVersion = cloudTokenVersion(token);
        if (tokenVersion == null) {
            callback.invoke(false, "NO TOKEN", null);
            return;
        }
        var tokenAccountBinding = tokenVersion == 3 ?
            cloudTokenAccountBinding(token) : legacyTokenAccountBinding();
        var tokenDeviceBinding = tokenVersion == 3 ?
            cloudTokenDeviceBinding(token) : legacyTokenDeviceBinding();
        if (tokenAccountBinding == null && tokenVersion == 2) {
            tokenAccountBinding = GymStore.accountBinding;
        }
        if (!GymStore.accountBinding.toString().equals(tokenAccountBinding.toString())) {
            if (tokenVersion == 2) {
                clearCloudDeviceToken();
            }
            callback.invoke(false, "TOKEN OWNER", null);
            return;
        }
        var listener = new GymCloudPlanListener(
            callback,
            tokenAccountBinding,
            tokenDeviceBinding,
            tokenVersion == 2
        );
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
        var tokenVersion = cloudTokenVersion(token);
        var tokenAccountBinding = tokenVersion == 3 ?
            cloudTokenAccountBinding(token) : legacyTokenAccountBinding();
        var tokenDeviceBinding = tokenVersion == 3 ?
            cloudTokenDeviceBinding(token) : legacyTokenDeviceBinding();
        var messageDeviceBinding = message instanceof Lang.Dictionary ?
            message.get("deviceBinding") : null;
        var planId = message instanceof Lang.Dictionary ? message.get("planId") : null;
        var planRevision = message instanceof Lang.Dictionary ? message.get("planRevision") : null;
        if (tokenVersion == null || tokenAccountBinding == null ||
            tokenDeviceBinding == null ||
            !GymStore.hasAccountBinding() ||
            !GymStore.accountBinding.toString().equals(tokenAccountBinding.toString()) ||
            !GymStore.isBoundedText(messageDeviceBinding, 36) ||
            !tokenDeviceBinding.toString().equals(
                messageDeviceBinding.toString()
            ) ||
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
        var tokenVersion = cloudTokenVersion(token);
        if (tokenVersion == null || !GymStore.hasAccountBinding()) {
            return false;
        }
        var tokenAccountBinding = tokenVersion == 3 ?
            cloudTokenAccountBinding(token) : legacyTokenAccountBinding();
        return tokenAccountBinding == null ||
            GymStore.accountBinding.toString().equals(tokenAccountBinding.toString());
    }

    static function reconcileCloudDeviceToken(nextAccountBinding) {
        if (!GymStore.isValidAccountBinding(nextAccountBinding)) {
            return false;
        }
        var token = Properties.getValue("CloudDeviceToken");
        if (token == null || token.toString().length() == 0) {
            return true;
        }
        var tokenVersion = cloudTokenVersion(token);
        var tokenAccountBinding = tokenVersion == 3 ?
            cloudTokenAccountBinding(token) : legacyTokenAccountBinding();
        if (tokenVersion == 2 && tokenAccountBinding == null) {
            var currentAccountBinding = GymStore.accountBinding;
            if (GymStore.isValidAccountBinding(currentAccountBinding) &&
                !currentAccountBinding.toString().equals(nextAccountBinding.toString())) {
                // An unowned released v2 capability can be adopted only during the
                // watch's first account binding. Once an owner exists, every account
                // transition clears it so an empty response cannot silently rebind it.
                return clearCloudDeviceToken();
            }
            return true;
        }
        if (nextAccountBinding.toString().equals(signedOutAccountBinding) ||
            (tokenVersion != null && tokenAccountBinding != null &&
                tokenAccountBinding.toString().equals(nextAccountBinding.toString()))) {
            return true;
        }
        return clearCloudDeviceToken();
    }

    static function clearCloudDeviceToken() {
        try {
            Properties.setValue("CloudDeviceToken", "");
            Properties.setValue("CloudLegacyTokenOwner", "");
            Properties.setValue("CloudLegacyTokenDevice", "");
            return true;
        } catch (e) {
            return false;
        }
    }

    static function rememberLegacyCloudTokenBinding(accountBinding, deviceBinding) {
        if (!GymStore.isValidAccountBinding(accountBinding) ||
            !isValidCloudDeviceId(deviceBinding) ||
            !GymStore.hasAccountBinding() ||
            !GymStore.accountBinding.toString().equals(accountBinding.toString())) {
            return false;
        }
        try {
            Properties.setValue("CloudLegacyTokenOwner", accountBinding.toString());
            Properties.setValue("CloudLegacyTokenDevice", deviceBinding.toString());
            return true;
        } catch (e) {
            return false;
        }
    }

    static function legacyTokenAccountBinding() {
        var value = Properties.getValue("CloudLegacyTokenOwner");
        return GymStore.isValidAccountBinding(value) ? value.toString() : null;
    }

    static function legacyTokenDeviceBinding() {
        var value = Properties.getValue("CloudLegacyTokenDevice");
        return isValidCloudDeviceId(value) ? value.toString() : null;
    }

    static function cloudTokenVersion(value) {
        if (value instanceof Lang.String &&
            value.toString().length() == legacyCapabilityLength &&
            GymStore.isValidAccountBinding(value)) {
            return 2;
        }
        return cloudTokenAccountBinding(value) == null ? null : 3;
    }

    static function cloudTokenAccountBinding(value) {
        if (!(value instanceof Lang.String)) {
            return null;
        }
        var token = value.toString();
        if (token.length() != cloudCapabilityLength ||
            !token.substring(0, 3).equals("g3.") ||
            !token.substring(67, 68).equals(".") ||
            !token.substring(104, 105).equals(".") ||
            !token.substring(169, 170).equals(".")) {
            return null;
        }
        var account = token.substring(3, 67);
        var device = token.substring(68, 104);
        var nonce = token.substring(105, 169);
        var tag = token.substring(170, 234);
        if (!GymStore.isValidAccountBinding(account) ||
            !isValidCloudDeviceId(device) ||
            !GymStore.isValidAccountBinding(nonce) ||
            !GymStore.isValidAccountBinding(tag)) {
            return null;
        }
        return account;
    }

    static function cloudTokenDeviceBinding(value) {
        if (cloudTokenAccountBinding(value) == null) {
            return null;
        }
        return value.toString().substring(68, 104);
    }

    static function isValidCloudDeviceId(value) {
        if (!(value instanceof Lang.String) || value.toString().length() != 36) {
            return false;
        }
        var text = value.toString();
        var version = text.substring(14, 15);
        var variant = text.substring(19, 20);
        if (!text.substring(8, 9).equals("-") ||
            !text.substring(13, 14).equals("-") ||
            !text.substring(18, 19).equals("-") ||
            !text.substring(23, 24).equals("-") ||
            !(version.equals("1") || version.equals("2") ||
                version.equals("3") || version.equals("4") ||
                version.equals("5")) ||
            !(variant.equals("8") || variant.equals("9") ||
                variant.equals("a") || variant.equals("b"))) {
            return false;
        }
        var compact = text.substring(0, 8) + text.substring(9, 13) +
            text.substring(14, 18) + text.substring(19, 23) +
            text.substring(24, 36);
        return GymStore.isValidAccountBinding(compact + compact);
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
