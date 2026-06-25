using Toybox.Communications as Comm;

class GymCommListener extends Comm.ConnectionListener {
    hidden var callback;

    function initialize(resultCallback) {
        ConnectionListener.initialize();
        callback = resultCallback;
    }

    function onComplete() {
        callback.invoke(true);
    }

    function onError() {
        callback.invoke(false);
    }
}

class GymComm {
    static function send(message, callback) {
        Comm.transmit(message, null, new GymCommListener(callback));
    }

    static function requestSync(callback) {
        send({ "type" => "request_sync" }, callback);
    }
}
