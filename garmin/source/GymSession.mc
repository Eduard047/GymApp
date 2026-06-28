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
    static var paused = false;
    static var startedAt = 0;
    static var pausedAt = 0;
    static var pausedAccumSeconds = 0;
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
    static var profileAge = 30;
    static var profileGender = null;
    static var profileVo2Max = null;
    static var restingHr = 60;
    static var maxHrEstimate = 185;
    static var lastCalorieSeconds = 0;
    static var lastMet = 0.0;
    static var lastKcalPerMinute = 0.0;
    static var setBoostCalories = 0.0;
    static var status = "READY";
    static var gymKcalField = null;
    static var gymZoneField = null;
    static var effortState = "WARMUP";
    static var lastHr = null;
    static var lastHrChangeSeconds = 0;
    static var autoLogPrompt = false;
    static var activeSetSeen = false;
    static var lastPromptSeconds = 0;
    static var debugText = "";
    static var hrTrend = 0.0;
    static var activeStartSeconds = 0;
    static var lastSetEndSeconds = 0;
    static var lastAutoReason = "init";
    static var minuteBucket = -1;
    static var minuteHrSum = 0;
    static var minuteHrSamples = 0;
    static var previousMinuteHr = null;
    static var sessionBaselineHr = null;
    static var activeSignalCount = 0;

    static function start() {
        loadProfile();
        startSensors();
        startedAt = Time.now().value();
        pausedAt = 0;
        pausedAccumSeconds = 0;
        elapsedSeconds = 0;
        gymCalories = 0.0;
        lastCalorieSeconds = 0;
        lastMet = 0.0;
        lastKcalPerMinute = 0.0;
        setBoostCalories = 0.0;
        avgHr = 0;
        maxHr = 0;
        hrSamples = 0;
        zone = 0;
        effortState = "WARMUP";
        lastHr = null;
        lastHrChangeSeconds = 0;
        autoLogPrompt = false;
        activeSetSeen = false;
        lastPromptSeconds = 0;
        hrTrend = 0.0;
        activeStartSeconds = 0;
        lastSetEndSeconds = 0;
        lastAutoReason = "init";
        minuteBucket = -1;
        minuteHrSum = 0;
        minuteHrSamples = 0;
        previousMinuteHr = null;
        sessionBaselineHr = null;
        activeSignalCount = 0;
        debugText = "init";
        status = "REC";
        paused = false;

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

    static function pause() {
        if (paused) {
            return;
        }
        paused = true;
        pausedAt = Time.now().value();
        stopSensors();
        if (session != null) {
            try {
                if (session.isRecording()) {
                    session.stop();
                }
            } catch (ex) {
            }
        }
        status = "PAUSED";
        effortState = "PAUSED";
    }

    static function resume() {
        if (!paused) {
            return;
        }
        var now = Time.now().value();
        if (pausedAt > 0) {
            pausedAccumSeconds += now - pausedAt;
        }
        pausedAt = 0;
        paused = false;
        startSensors();
        if (session != null) {
            try {
                session.start();
            } catch (ex) {
            }
        }
        status = "REC";
        effortState = "READY";
    }

    static function togglePause() {
        if (paused) {
            resume();
        } else {
            pause();
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
        paused = false;
        status = "SAVED";
    }

    static function discard() {
        stopSensors();
        var discarded = false;
        if (session != null) {
            try {
                discarded = session.discard();
            } catch (ex) {
                try {
                    if (session.isRecording()) {
                        session.stop();
                    }
                    discarded = session.discard();
                } catch (ex2) {
                    discarded = false;
                }
            }
        }
        session = null;
        gymKcalField = null;
        gymZoneField = null;
        recording = false;
        paused = false;
        status = discarded ? "DISCARD" : "DISC ERR";
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
            var now = Time.now().value();
            var currentPaused = paused && pausedAt > 0 ? now - pausedAt : 0;
            elapsedSeconds = now - startedAt - pausedAccumSeconds - currentPaused;
        }
        if (paused) {
            return;
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
        trackMinuteHeartRate(value);
        zone = zoneFor(value);
        updateEffortState(value);
    }

    static function trackMinuteHeartRate(value) {
        var bucket = (elapsedSeconds / 60).toNumber();
        if (minuteBucket < 0) {
            minuteBucket = bucket;
        }
        if (bucket != minuteBucket) {
            if (minuteHrSamples > 0) {
                previousMinuteHr = (minuteHrSum / minuteHrSamples).toNumber();
            }
            minuteHrSum = 0;
            minuteHrSamples = 0;
            minuteBucket = bucket;
        }
        minuteHrSum += value;
        minuteHrSamples += 1;
    }

    static function updateEffortState(value) {
        var previous = lastHr;
        lastHr = value;
        if (sessionBaselineHr == null) {
            sessionBaselineHr = value;
        }
        if (previous == null) {
            lastAutoReason = "first hr";
            debugText = "hr " + value.toString() + " z" + zone.toString();
            return;
        }

        var delta = value - previous;
        hrTrend = ((hrTrend * 2.0) + delta.toFloat()) / 3.0;

        var riseThreshold = 5;
        var trendThreshold = 3.0;
        var minRiseFromBaseline = 10;
        var fallThreshold = -3;
        var activeZone = 3;
        var minActiveSeconds = 15;
        var restDetectSeconds = 35;
        var promptGapSeconds = 45;

        if (GymStore.sensitivityIndex == 0) {
            riseThreshold = 7;
            trendThreshold = 4.0;
            minRiseFromBaseline = 12;
            fallThreshold = -4;
            activeZone = 3;
            minActiveSeconds = 20;
            restDetectSeconds = 45;
            promptGapSeconds = 60;
        } else if (GymStore.sensitivityIndex == 2) {
            riseThreshold = 4;
            trendThreshold = 2.5;
            minRiseFromBaseline = 8;
            fallThreshold = -2;
            activeZone = 2;
            minActiveSeconds = 12;
            restDetectSeconds = 25;
            promptGapSeconds = 30;
        }

        var baselineDelta = value - sessionBaselineHr;
        var risingEnough = (delta >= riseThreshold || hrTrend >= trendThreshold) && baselineDelta >= minRiseFromBaseline;
        var zoneEnough = zone >= activeZone && baselineDelta >= (minRiseFromBaseline / 2);
        if (risingEnough || zoneEnough) {
            activeSignalCount += 1;
        } else {
            activeSignalCount = 0;
        }

        if (activeSignalCount >= 2) {
            if (!effortState.equals("SET ACTIVE")) {
                activeSetSeen = true;
                activeStartSeconds = elapsedSeconds;
                lastAutoReason = "rise +" + baselineDelta.toString();
            }
            effortState = "SET ACTIVE";
            lastHrChangeSeconds = elapsedSeconds;
        } else if (delta <= fallThreshold || hrTrend <= fallThreshold || elapsedSeconds - lastHrChangeSeconds > restDetectSeconds) {
            var activeDuration = elapsedSeconds - activeStartSeconds;
            if (
                GymStore.autoPromptEnabled &&
                activeSetSeen &&
                !autoLogPrompt &&
                activeDuration >= minActiveSeconds &&
                elapsedSeconds - lastPromptSeconds > promptGapSeconds
            ) {
                autoLogPrompt = true;
                lastPromptSeconds = elapsedSeconds;
                lastSetEndSeconds = elapsedSeconds;
                lastAutoReason = "rest after " + activeDuration.toString() + "s";
            } else {
                lastAutoReason = "rest no prompt";
            }
            effortState = "REST";
            if (value < sessionBaselineHr || (!activeSetSeen && baselineDelta < 4)) {
                sessionBaselineHr = ((sessionBaselineHr * 3) + value) / 4;
            }
        } else if (zone == 2) {
            effortState = "READY";
            lastAutoReason = "zone ready";
            if (!activeSetSeen && baselineDelta < 4) {
                sessionBaselineHr = ((sessionBaselineHr * 3) + value) / 4;
            }
        } else {
            lastAutoReason = "hold";
            if (!activeSetSeen && baselineDelta < 4) {
                sessionBaselineHr = ((sessionBaselineHr * 3) + value) / 4;
            }
        }
        debugText = "d" + delta.toString() + " b" + baselineDelta.toString() + " s" + activeSignalCount.toString() + " " + lastAutoReason;
    }

    static function clearAutoPrompt() {
        autoLogPrompt = false;
        activeSetSeen = false;
        activeSignalCount = 0;
        if (hr != null) {
            sessionBaselineHr = hr;
        }
        lastAutoReason = "set logged";
    }

    static function loadProfile() {
        try {
            var profile = UserProfile.getProfile();
            if (profile != null && profile.weight != null && profile.weight > 0) {
                // Garmin UserProfile.Profile.weight is grams.
                profileWeightKg = profile.weight / 1000.0;
            }
            if (profile != null && profile.gender != null) {
                profileGender = profile.gender;
            }
            profileVo2Max = null;
            if (profile != null && profile.vo2maxRunning != null && profile.vo2maxRunning > 0) {
                profileVo2Max = profile.vo2maxRunning;
            } else if (profile != null && profile.vo2maxCycling != null && profile.vo2maxCycling > 0) {
                profileVo2Max = profile.vo2maxCycling;
            }
            if (profile != null && profile.restingHeartRate != null && profile.restingHeartRate > 30) {
                restingHr = profile.restingHeartRate;
            } else if (profile != null && profile.averageRestingHeartRate != null && profile.averageRestingHeartRate > 30) {
                restingHr = profile.averageRestingHeartRate;
            }
            if (profile != null && profile.birthYear != null && profile.birthYear > 1900) {
                var age = Time.Gregorian.info(Time.now(), Time.FORMAT_MEDIUM).year - profile.birthYear;
                profileAge = age;
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
        var deltaSeconds = elapsedSeconds - lastCalorieSeconds;
        if (deltaSeconds <= 0) {
            return;
        }
        if (deltaSeconds > 30) {
            deltaSeconds = 30;
        }
        var met = metForHeartRate();
        lastMet = met;
        lastKcalPerMinute = met * 3.5 * profileWeightKg / 200.0;
        // Standard MET estimate: kcal/min = MET * 3.5 * kg / 200.
        // For strength work this is an estimate; Garmin's proprietary calorie
        // model is not exposed to Connect IQ apps.
        gymCalories += lastKcalPerMinute * (deltaSeconds / 60.0);
        lastCalorieSeconds = elapsedSeconds;
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
        gymCalories += boost;
    }

    static function metForHeartRate() {
        if (hr == null || maxHrEstimate <= restingHr) {
            return 1.2;
        }
        var hrr = (hr - restingHr).toFloat() / (maxHrEstimate - restingHr).toFloat();
        if (hrr < 0.0) {
            hrr = 0.0;
        } else if (hrr > 1.0) {
            hrr = 1.0;
        }

        var lowHr = (hr <= restingHr + 25 || hrr <= 0.30) && zone <= 1;
        if (lowHr && (!activeSetSeen || effortState.equals("READY") || effortState.equals("WARMUP") || effortState.equals("REST"))) {
            if (!activeSetSeen) {
                return 0.15 + (hrr * 0.25);
            }
            return 0.65 + (hrr * 0.55);
        }

        if (effortState.equals("SET ACTIVE") || zone >= 3 || hrr >= 0.45) {
            var hrrMet = hrrBasedActiveMet(hrr);
            var modelMet = researchExerciseMet();
            var activeMet = hrrMet;
            if (modelMet != null) {
                // The intermittent HR model is more specific for strength/circuit
                // work, but HRR keeps the result stable if profile data is sparse.
                activeMet = (modelMet * 0.70) + (hrrMet * 0.30);
            }
            return clampMet(activeMet, 3.8, 12.0);
        }

        if (effortState.equals("REST") || activeSetSeen) {
            var recoveryMet = 0.75 + (hrr * 2.2);
            if (previousMinuteHr != null && previousMinuteHr > hr + 10) {
                // Short strength rests still have elevated oxygen cost from the
                // previous set, but cap it so sitting/resting never explodes.
                recoveryMet += 0.20;
            }
            return clampMet(recoveryMet, 0.65, 2.6);
        }

        return clampMet(0.25 + (hrr * 0.8), 0.15, 1.4);
    }

    static function hrrBasedActiveMet(hrr) {
        var vo2Scale = 1.0;
        if (profileVo2Max != null && profileVo2Max > 20) {
            vo2Scale = profileVo2Max / 42.0;
            if (vo2Scale < 0.85) {
                vo2Scale = 0.85;
            } else if (vo2Scale > 1.25) {
                vo2Scale = 1.25;
            }
        }
        return 3.4 + (hrr * 7.8 * vo2Scale);
    }

    static function researchExerciseMet() {
        if (profileWeightKg <= 0 || hr == null) {
            return null;
        }
        var kjMin = intermittentKjPerMinute();
        if (kjMin == null) {
            kjMin = keytelKjPerMinute();
        }
        if (kjMin == null || kjMin <= 0) {
            return null;
        }
        var kcalMin = kjMin / 4.184;
        var met = kcalMin * 200.0 / (3.5 * profileWeightKg);
        return clampMet(met, 2.5, 13.0);
    }

    static function intermittentKjPerMinute() {
        if (profileVo2Max == null || previousMinuteHr == null) {
            return null;
        }
        if (profileGender == UserProfile.GENDER_MALE) {
            return -78.7
                + (0.582 * hr)
                + (0.183 * profileVo2Max)
                + (0.532 * profileAge)
                - (0.160 * previousMinuteHr)
                + (0.26975 * profileWeightKg)
                + (0.0029 * profileVo2Max * previousMinuteHr);
        } else if (profileGender == UserProfile.GENDER_FEMALE) {
            return -33.6
                + (0.379 * hr)
                + (0.066 * profileVo2Max)
                + (0.046 * profileAge)
                - (0.066 * previousMinuteHr)
                + (0.07572 * profileWeightKg)
                + (0.00216 * profileVo2Max * previousMinuteHr);
        }
        return null;
    }

    static function keytelKjPerMinute() {
        if (profileGender == UserProfile.GENDER_MALE) {
            return -55.0969
                + (0.6309 * hr)
                + (0.1988 * profileWeightKg)
                + (0.2017 * profileAge);
        } else if (profileGender == UserProfile.GENDER_FEMALE) {
            return -20.4022
                + (0.4472 * hr)
                - (0.1263 * profileWeightKg)
                + (0.074 * profileAge);
        }
        return null;
    }

    static function clampMet(value, minValue, maxValue) {
        if (value < minValue) {
            return minValue;
        } else if (value > maxValue) {
            return maxValue;
        }
        return value;
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
