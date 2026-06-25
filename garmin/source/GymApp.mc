using Toybox.Application as App;
using Toybox.WatchUi as Ui;

class GymApp extends App.AppBase {
    function initialize() {
        AppBase.initialize();
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
}

function getApp() as GymApp {
    return App.getApp() as GymApp;
}
