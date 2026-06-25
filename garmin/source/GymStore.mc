using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Time as Time;

class GymStore {
    static var exercises = ["Bench Press", "Squat", "Deadlift", "Pull Up", "Overhead Press"];
    static var sets = [];
    static var pending = [];
    static var exerciseIndex = 0;
    static var weight = 50.0;
    static var reps = 10;
    static var restEndsAt = 0;
    static var status = "READY";

    static function load() {
        var savedExercises = Storage.getValue("exercises");
        if (savedExercises instanceof Lang.Array && savedExercises.size() > 0) {
            exercises = savedExercises;
        }
        var savedSets = Storage.getValue("sets");
        if (savedSets instanceof Lang.Array) {
            sets = savedSets;
        }
        var savedPending = Storage.getValue("pending");
        if (savedPending instanceof Lang.Array) {
            pending = savedPending;
        }
        var savedWeight = Storage.getValue("weight");
        if (savedWeight instanceof Lang.Number || savedWeight instanceof Lang.Float) {
            weight = savedWeight;
        }
        var savedReps = Storage.getValue("reps");
        if (savedReps instanceof Lang.Number) {
            reps = savedReps;
        }
    }

    static function save() {
        Storage.setValue("exercises", exercises);
        Storage.setValue("sets", sets);
        Storage.setValue("pending", pending);
        Storage.setValue("weight", weight);
        Storage.setValue("reps", reps);
    }

    static function currentExercise() {
        if (exercises.size() == 0) {
            return "Exercise";
        }
        if (exerciseIndex >= exercises.size()) {
            exerciseIndex = 0;
        }
        return exercises[exerciseIndex];
    }

    static function nextExercise(delta) {
        if (exercises.size() == 0) {
            return;
        }
        exerciseIndex = (exerciseIndex + delta) % exercises.size();
        if (exerciseIndex < 0) {
            exerciseIndex += exercises.size();
        }
    }

    static function addSet() {
        sets.add({
            "exerciseName" => currentExercise(),
            "weight" => weight,
            "reps" => reps
        });
        GymSession.addSetBoost(weight, reps);
        restEndsAt = System.getTimer() + 90000;
        status = "SET SAVED";
        save();
    }

    static function clearWorkout() {
        sets = [];
        restEndsAt = 0;
        save();
    }

    static function restSeconds() {
        if (restEndsAt <= 0) {
            return 0;
        }
        var remaining = restEndsAt - System.getTimer();
        if (remaining <= 0) {
            restEndsAt = 0;
            return 0;
        }
        return (remaining / 1000).toNumber();
    }

    static function workoutMessage() {
        var requestId = Time.now().value().toString();
        return {
            "type" => "create_workout",
            "requestId" => requestId,
            "startedAtSeconds" => Time.now().value(),
            "sets" => sets
        };
    }

    static function applySync(message) {
        var syncedExercises = message.get("exercises");
        if (syncedExercises instanceof Lang.Array && syncedExercises.size() > 0) {
            exercises = syncedExercises;
            exerciseIndex = 0;
        }
        var plan = message.get("plan");
        if (plan instanceof Lang.Array && plan.size() > 0) {
            sets = plan;
        }
        status = "SYNCED";
        save();
    }
}
