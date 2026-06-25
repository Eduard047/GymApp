using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Time as Time;

class GymStore {
    static var exercises = ["Bench Press", "Squat", "Deadlift", "Pull Up", "Overhead Press"];
    static var sets = [];
    static var plan = [];
    static var pending = [];
    static var exerciseIndex = 0;
    static var weight = 50.0;
    static var reps = 10;
    static var restEndsAt = 0;
    static var status = "READY";
    static var weightStep = 2.5;
    static var restSecondsDefault = 90;
    static var autoPromptEnabled = true;
    static var sensitivityIndex = 1;

    static function load() {
        var savedExercises = Storage.getValue("exercises");
        if (savedExercises instanceof Lang.Array && savedExercises.size() > 0) {
            exercises = savedExercises;
        }
        var savedSets = Storage.getValue("sets");
        if (savedSets instanceof Lang.Array) {
            sets = savedSets;
        }
        var savedPlan = Storage.getValue("plan");
        if (savedPlan instanceof Lang.Array) {
            plan = savedPlan;
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
        var savedWeightStep = Storage.getValue("weightStep");
        if (savedWeightStep instanceof Lang.Number || savedWeightStep instanceof Lang.Float) {
            weightStep = savedWeightStep;
        }
        var savedRest = Storage.getValue("restSecondsDefault");
        if (savedRest instanceof Lang.Number) {
            restSecondsDefault = savedRest;
        }
        var savedAuto = Storage.getValue("autoPromptEnabled");
        if (savedAuto instanceof Lang.Boolean) {
            autoPromptEnabled = savedAuto;
        }
        var savedSensitivity = Storage.getValue("sensitivityIndex");
        if (savedSensitivity instanceof Lang.Number) {
            sensitivityIndex = savedSensitivity;
            if (sensitivityIndex < 0) {
                sensitivityIndex = 0;
            } else if (sensitivityIndex > 2) {
                sensitivityIndex = 2;
            }
        }
    }

    static function save() {
        Storage.setValue("exercises", exercises);
        Storage.setValue("sets", sets);
        Storage.setValue("plan", plan);
        Storage.setValue("pending", pending);
        Storage.setValue("weight", weight);
        Storage.setValue("reps", reps);
        Storage.setValue("weightStep", weightStep);
        Storage.setValue("restSecondsDefault", restSecondsDefault);
        Storage.setValue("autoPromptEnabled", autoPromptEnabled);
        Storage.setValue("sensitivityIndex", sensitivityIndex);
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

    static function applyCurrentPlanSet() {
        if (plan.size() == 0) {
            return;
        }
        if (exerciseIndex >= plan.size()) {
            exerciseIndex = 0;
        }
        var item = plan[exerciseIndex];
        if (item instanceof Lang.Dictionary) {
            var plannedWeight = item.get("weight");
            var plannedReps = item.get("reps");
            if (plannedWeight instanceof Lang.Number || plannedWeight instanceof Lang.Float) {
                weight = plannedWeight;
            }
            if (plannedReps instanceof Lang.Number) {
                reps = plannedReps;
            }
        }
    }

    static function nextExercise(delta) {
        if (exercises.size() == 0) {
            return;
        }
        exerciseIndex = (exerciseIndex + delta) % exercises.size();
        if (exerciseIndex < 0) {
            exerciseIndex += exercises.size();
        }
        applyCurrentPlanSet();
    }

    static function addSet() {
        sets.add({
            "exerciseName" => currentExercise(),
            "weight" => weight,
            "reps" => reps
        });
        GymSession.addSetBoost(weight, reps);
        GymSession.clearAutoPrompt();
        restEndsAt = System.getTimer() + (restSecondsDefault * 1000);
        status = "SET SAVED";
        save();
    }

    static function cycleWeightStep() {
        if (weightStep < 5.0) {
            weightStep = 5.0;
        } else if (weightStep < 10.0) {
            weightStep = 10.0;
        } else {
            weightStep = 2.5;
        }
        save();
    }

    static function cycleRestDefault() {
        if (restSecondsDefault < 90) {
            restSecondsDefault = 90;
        } else if (restSecondsDefault < 120) {
            restSecondsDefault = 120;
        } else if (restSecondsDefault < 180) {
            restSecondsDefault = 180;
        } else {
            restSecondsDefault = 60;
        }
        save();
    }

    static function toggleAutoPrompt() {
        autoPromptEnabled = !autoPromptEnabled;
        if (!autoPromptEnabled) {
            GymSession.clearAutoPrompt();
        }
        save();
    }

    static function cycleSensitivity() {
        sensitivityIndex = (sensitivityIndex + 1) % 3;
        save();
    }

    static function sensitivityLabel() {
        if (sensitivityIndex == 0) {
            return "LOW";
        } else if (sensitivityIndex == 2) {
            return "HIGH";
        }
        return "NORMAL";
    }

    static function clearWorkout() {
        sets = [];
        plan = [];
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
            "durationSeconds" => GymSession.elapsedSeconds,
            "gymCalories" => GymSession.gymCalories,
            "garminCalories" => GymSession.garminCalories,
            "avgHeartRate" => GymSession.avgHr,
            "maxHeartRate" => GymSession.maxHr,
            "lastHeartRate" => GymSession.hr,
            "heartRateZone" => GymSession.zone,
            "debug" => GymSession.debugText,
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
            GymStore.plan = plan;
            var plannedExercises = [];
            for (var i = 0; i < plan.size(); i += 1) {
                var item = plan[i];
                if (item instanceof Lang.Dictionary) {
                    var name = item.get("exerciseName");
                    if (name != null) {
                        plannedExercises.add(name.toString());
                    }
                }
            }
            if (plannedExercises.size() > 0) {
                exercises = plannedExercises;
                exerciseIndex = 0;
                applyCurrentPlanSet();
            }
            status = "PLAN " + plan.size().toString();
        } else {
            status = "SYNCED";
        }
        save();
    }
}
