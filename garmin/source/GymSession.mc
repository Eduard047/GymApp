using Toybox.Activity as Activity;
using Toybox.ActivityRecording as Recording;
using Toybox.FitContributor as FitContributor;
using Toybox.Lang as Lang;
using Toybox.Sensor as Sensor;
using Toybox.System as System;
using Toybox.Time as Time;
using Toybox.UserProfile as UserProfile;

class GymSession {
    static var session = null;
    static var recording = false;
    static var startedAt = 0;
    static var elapsedSeconds = 0;
    static var hr = null;
    static var avgHr = 0;
    static var maxHr = 0;
    static var hrSamples = 0;
    static var gymCalories = 0.0;
    static var garminCalories = null;
    static var zones = null;
    static var zone = 0;
    static var profileWeightKg = 80.0;
    static var restingHr = 60;
    static var maxHrEstimate = 185;
    static var setBoostCalories = 0.0;
    static var status = "READY";
    static var gymKcalField = null;
    static var gymZoneField = null;

    static function start() {
        loadProfile();
        startSensors();
        startedAt = Time.now().value();
        elapsedSeconds = 0;
        gymCalories = 0.0;
        setBoostCalories = 0.0;
        avgHr = 0;
        maxHr = 0;
        hrSamples = 0;
        zone = 0;
        status = "REC";

        if (Toybox has :ActivityRecording) {
            try {
                session = Recording.createSession({
                    :name => "GymApp Strength",
                    :sport => Activity.SPORT_TRAINING,
                    :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
                });
                createFitFields();
                session.start();
                recording = true;
            } catch (ex) {
                session = null;
                recording = false;
                status = "REC ERR";
            }
        }
    }

    static function stopAndSave() {
        stopSensors();
        if (session != null) {
            try {
                if (session.isRecording()) {
                    session.stop();
                }
                session.save();
            } catch (ex) {
            }
        }
        session = null;
        gymKcalField = null;
        gymZoneField = null;
        recording = false;
        status = "SAVED";
    }

    static function discard() {
        stopSensors();
        if (session != null) {
            try {
                if (session.isRecording()) {
                    session.stop();
                }
                session.discard();
            } catch (ex) {
            }
        }
        session = null;
        gymKcalField = null;
        gymZoneField = null;
        recording = false;
        status = "DISCARD";
    }

    static function createFitFields() {
        gymKcalField = null;
        gymZoneField = null;
        if (session == null || !(Toybox has :FitContributor)) {
            return;
        }
        try {
            gymKcalField = session.createField(
                "gym_strength_kcal",
                0,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "kcal"}
            );
            gymKcalField.setData(0.0);
        } catch (ex) {
            gymKcalField = null;
        }
        try {
            gymZoneField = session.createField(
                "gym_hr_zone",
                1,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "zone"}
            );
            gymZoneField.setData(0);
        } catch (ex2) {
            gymZoneField = null;
        }
    }

    static function tick() {
        if (startedAt > 0) {
            elapsedSeconds = Time.now().value() - startedAt;
        }
        updateHeartRateFromSensor();
        updateGarminActivityInfo();
        updateCalories();
    }

    static function startSensors() {
        if (Toybox has :Sensor) {
            try {
                Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
            } catch (ex) {
            }
        }
    }

    static function stopSensors() {
        if (Toybox has :Sensor) {
            try {
                Sensor.setEnabledSensors([]);
            } catch (ex) {
            }
        }
    }

    static function updateHeartRateFromSensor() {
        if (Toybox has :Sensor) {
            try {
                var info = Sensor.getInfo();
                if (info != null && info.heartRate != null) {
                    applyHeartRate(info.heartRate);
                }
            } catch (ex) {
            }
        }
    }

    static function updateGarminActivityInfo() {
        if (Toybox has :Activity) {
            try {
                var info = Activity.getActivityInfo();
                if (info != null) {
                    if (info.currentHeartRate != null) {
                        applyHeartRate(info.currentHeartRate);
                    }
                    if (info.calories != null) {
                        garminCalories = info.calories;
                    }
                }
            } catch (ex) {
            }
        }
    }

    static function applyHeartRate(value) {
        if (!(value instanceof Lang.Number) || value <= 0 || value > 240) {
            return;
        }
        hr = value;
        hrSamples += 1;
        avgHr = (((avgHr * (hrSamples - 1)) + value) / hrSamples).toNumber();
        if (value > maxHr) {
            maxHr = value;
        }
        zone = zoneFor(value);
    }

    static function loadProfile() {
        try {
            var profile = UserProfile.getProfile();
            if (profile != null && profile.weight != null && profile.weight > 0) {
                // Garmin UserProfile.Profile.weight is grams.
                profileWeightKg = profile.weight / 1000.0;
            }
            if (profile != null && profile.restingHeartRate != null && profile.restingHeartRate > 30) {
                restingHr = profile.restingHeartRate;
            } else if (profile != null && profile.averageRestingHeartRate != null && profile.averageRestingHeartRate > 30) {
                restingHr = profile.averageRestingHeartRate;
            }
            if (profile != null && profile.birthYear != null && profile.birthYear > 1900) {
                var age = Time.Gregorian.info(Time.now(), Time.FORMAT_MEDIUM).year - profile.birthYear;
                maxHrEstimate = (208.0 - (0.7 * age)).toNumber();
            }
        } catch (ex) {
        }

        try {
            if (UserProfile has :getHeartRateZones2) {
                zones = UserProfile.getHeartRateZones2(Activity.SPORT_TRAINING);
            } else {
                zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
            }
        } catch (ex2) {
            zones = null;
        }
    }

    static function zoneFor(value) {
        if (!(zones instanceof Lang.Array) || zones.size() < 6) {
            if (value < 110) {
                return 0;
            } else if (value < 130) {
                return 1;
            } else if (value < 150) {
                return 2;
            } else if (value < 170) {
                return 3;
            } else if (value < 185) {
                return 4;
            }
            return 5;
        }

        if (value < zones[0]) {
            return 0;
        } else if (value <= zones[1]) {
            return 1;
        } else if (value <= zones[2]) {
            return 2;
        } else if (value <= zones[3]) {
            return 3;
        } else if (value <= zones[4]) {
            return 4;
        }
        return 5;
    }

    static function updateCalories() {
        if (!recording || elapsedSeconds <= 0) {
            return;
        }
        var met = metForHeartRate();
        // Standard MET estimate: kcal/min = MET * 3.5 * kg / 200.
        // For strength work this is an estimate; Garmin's proprietary calorie
        // model is not exposed to Connect IQ apps.
        gymCalories = (met * 3.5 * profileWeightKg / 200.0 * (elapsedSeconds / 60.0)) + setBoostCalories;
        if (gymKcalField != null) {
            try {
                gymKcalField.setData(gymCalories.toFloat());
            } catch (ex) {
            }
        }
        if (gymZoneField != null) {
            try {
                gymZoneField.setData(zone);
            } catch (ex2) {
            }
        }
    }

    static function addSetBoost(weightKg, reps) {
        if (weightKg == null || reps == null || weightKg <= 0 || reps <= 0) {
            return;
        }
        var volume = weightKg * reps;
        // Strength-specific correction: HR lags behind short anaerobic sets.
        // Add a bounded mechanical-work/EPOC estimate per saved set.
        var boost = 1.2 + (volume / 700.0);
        if (boost > 7.0) {
            boost = 7.0;
        }
        setBoostCalories += boost;
    }

    static function metForHeartRate() {
        if (hr == null || hr <= restingHr || maxHrEstimate <= restingHr) {
            return 3.5;
        }
        var hrr = (hr - restingHr).toFloat() / (maxHrEstimate - restingHr).toFloat();
        if (hrr < 0.0) {
            hrr = 0.0;
        } else if (hrr > 1.0) {
            hrr = 1.0;
        }
        var met = 2.8 + (hrr * 8.5);
        // Free-weight strength rarely behaves like easy walking even when HR
        // drops during rest, so keep a realistic floor.
        if (met < 3.8) {
            met = 3.8;
        }
        return met;
    }

    static function elapsedText() {
        var h = (elapsedSeconds / 3600).toNumber();
        var m = ((elapsedSeconds % 3600) / 60).toNumber();
        var s = (elapsedSeconds % 60).toNumber();
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%02d") + ":" + s.format("%02d");
    }
}
