using Toybox.Communications as Comm;

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
}
