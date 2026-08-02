using Toybox.Activity as Activity;
using Toybox.ActivityRecording as Recording;
using Toybox.FitContributor as FitContributor;
using Toybox.Lang as Lang;
using Toybox.Sensor as Sensor;
using Toybox.System as System;
using Toybox.Time as Time;
using Toybox.UserProfile as UserProfile;

class GymMotionListener {
    function onSensorData(data) {
        GymSession.onSensorData(data);
    }
}

class GymSession {
    static var session = null;
    static var recording = false;
    static var paused = false;
    static var startedAt = 0;
    static var pausedAt = 0;
    static var pausedAccumSeconds = 0;
    static var elapsedSeconds = 0;
    static var hr = null;
    static var activityHr = null;
    static var sensorHr = null;
    static var hrSource = "--";
    static var filteredHr = null;
    static var previousFilterHr = null;
    static var olderFilterHr = null;
    static var lastValidHrSeconds = 0;
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
    static var motionAvailable = false;
    static var motionListenerRegistered = false;
    static var motionListener = null;
    static var motionScore = 0.0;
    static var lastMotionTimerMs = 0;
    static var lastCredibleMotionSeconds = 0;
    static var motionSignalCount = 0;
    static var setConfidence = 0;
    static var confidenceLevel = "LOW";
    static var currentSetStartHr = null;
    static var currentSetPeakHr = null;
    static var currentSetEndHr = null;
    static var currentSetMaxConfidence = 0;
    static var currentSetZoneSeconds = null;
    static var currentSetLastIntervalSeconds = 0;
    static var currentSetStartGymCalories = null;
    static var currentSetStartGarminCalories = null;
    static var currentSetEndGymCalories = null;
    static var currentSetEndGarminCalories = null;
    static var currentSetLastEvidenceGymCalories = null;
    static var currentSetLastEvidenceGarminCalories = null;
    static var restoredSetInterval = null;
    static var candidateStartSeconds = 0;
    static var candidateLastSignalSeconds = 0;
    static var candidateStartHr = null;
    static var candidateStartGymCalories = null;
    static var candidateStartGarminCalories = null;
    static var candidateZoneSeconds = null;
    static var candidateLastIntervalSeconds = 0;
    static var recoveryPeakHr = null;
    static var recoveryLowestHr = null;

    static function start() {
        resetProfileDefaults();
        loadProfile();
        startedAt = Time.now().value();
        pausedAt = 0;
        pausedAccumSeconds = 0;
        elapsedSeconds = 0;
        hr = null;
        activityHr = null;
        sensorHr = null;
        hrSource = "--";
        filteredHr = null;
        previousFilterHr = null;
        olderFilterHr = null;
        lastValidHrSeconds = 0;
        gymCalories = 0.0;
        garminCalories = null;
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
        motionScore = 0.0;
        lastMotionTimerMs = 0;
        lastCredibleMotionSeconds = 0;
        motionSignalCount = 0;
        setConfidence = 0;
        confidenceLevel = "LOW";
        currentSetStartHr = null;
        currentSetPeakHr = null;
        currentSetEndHr = null;
        currentSetMaxConfidence = 0;
        resetCurrentSetInterval();
        clearSetCandidate();
        recoveryPeakHr = null;
        recoveryLowestHr = null;
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
        // High-frequency sensor listeners are most portable after the activity
        // recording session has been created (or definitively failed).
        startSensors();
    }

    static function pause() {
        if (paused) {
            return;
        }
        if (effortState.equals("SET ACTIVE") && activeSetSeen) {
            lastSetEndSeconds = elapsedSeconds;
            currentSetEndHr = hr;
            currentSetEndGymCalories = gymCalories;
            currentSetEndGarminCalories = garminCalories;
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
        if (session == null) {
            // A successful FIT save can be followed by a retry when clearing the
            // app's local workout state failed. Treat that retry as idempotent.
            return !recording && status.equals("SAVED");
        }
        var saved = false;
        try {
            if (session.isRecording() && !session.stop()) {
                status = "STOP ERR";
                return false;
            }
            saved = session.save();
        } catch (ex) {
            saved = false;
        }
        if (!saved) {
            status = "SAVE ERR";
            return false;
        }
        session = null;
        gymKcalField = null;
        gymZoneField = null;
        recording = false;
        paused = false;
        status = "SAVED";
        return true;
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

    static function resetForAccountTransition() {
        // An account transition is a privacy boundary: stop sensors and discard the
        // active FIT recording. A new workout must be started explicitly by the user.
        discard();
        startedAt = 0;
        pausedAt = 0;
        pausedAccumSeconds = 0;
        elapsedSeconds = 0;
        hr = null;
        activityHr = null;
        sensorHr = null;
        hrSource = "--";
        filteredHr = null;
        previousFilterHr = null;
        olderFilterHr = null;
        lastValidHrSeconds = 0;
        avgHr = 0;
        maxHr = 0;
        hrSamples = 0;
        gymCalories = 0.0;
        garminCalories = null;
        zone = 0;
        recording = false;
        paused = false;
        autoLogPrompt = false;
        activeSetSeen = false;
        motionScore = 0.0;
        lastMotionTimerMs = 0;
        lastCredibleMotionSeconds = 0;
        motionSignalCount = 0;
        setConfidence = 0;
        confidenceLevel = "LOW";
        currentSetStartHr = null;
        currentSetPeakHr = null;
        currentSetEndHr = null;
        currentSetMaxConfidence = 0;
        resetCurrentSetInterval();
        clearSetCandidate();
        recoveryPeakHr = null;
        recoveryLowestHr = null;
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
        expireSetCandidate();
        // ActivityInfo and SensorInfo can expose the same watch sample. Read both for
        // diagnostics, but apply only one so averages and detection never double-count.
        var appliedActivityHeartRate = updateGarminActivityInfo();
        var sampledSensorHeartRate = readHeartRateFromSensor();
        if (!appliedActivityHeartRate) {
            if (sampledSensorHeartRate != null) {
                hrSource = "SNS";
                applyHeartRate(sampledSensorHeartRate);
            } else {
                expireStaleHeartRate();
            }
        }
        updateCalories();
        captureActiveEvidenceTotals();
        captureEndedSetTotals();
    }

    static function startSensors() {
        if (Toybox has :Sensor) {
            try {
                Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
            } catch (ex) {
            }
            startMotionListener();
        }
    }

    static function stopSensors() {
        if (Toybox has :Sensor) {
            stopMotionListener();
            try {
                Sensor.setEnabledSensors([]);
            } catch (ex) {
            }
        }
    }

    static function startMotionListener() {
        if (motionListenerRegistered || !(Sensor has :registerSensorDataListener)) {
            return;
        }
        try {
            // Ten samples per second is sufficient for wrist-motion evidence and
            // materially lighter than the 25 Hz reference rate.
            if (motionListener == null) {
                motionListener = new GymMotionListener();
            }
            Sensor.registerSensorDataListener(motionListener.method(:onSensorData), {
                :period => 1,
                :accelerometer => {
                    :enabled => true,
                    :sampleRate => 10,
                    :includePower => false,
                    :includePitch => false,
                    :includeRoll => false,
                    :includeTimestamps => false
                }
            });
            motionListenerRegistered = true;
            motionAvailable = true;
        } catch (ex) {
            // Older products may expose Sensor without supporting this stream.
            // Heart-rate-only detection remains available.
            motionListenerRegistered = false;
            motionAvailable = false;
            motionScore = 0.0;
            lastMotionTimerMs = 0;
        }
    }

    static function stopMotionListener() {
        if (motionListenerRegistered && (Sensor has :unregisterSensorDataListener)) {
            try {
                Sensor.unregisterSensorDataListener();
            } catch (ex) {
            }
        }
        motionListenerRegistered = false;
        motionScore = 0.0;
        lastMotionTimerMs = 0;
        lastCredibleMotionSeconds = 0;
        motionSignalCount = 0;
        if (!activeSetSeen) {
            clearSetCandidate();
        }
    }

    static function onSensorData(data) {
        if (data == null || !(data has :accelerometerData) || data.accelerometerData == null) {
            return;
        }
        try {
            var accel = data.accelerometerData;
            var xs = accel.x;
            var ys = accel.y;
            var zs = accel.z;
            if (!(xs instanceof Lang.Array) || !(ys instanceof Lang.Array) ||
                !(zs instanceof Lang.Array)) {
                return;
            }
            var count = xs.size();
            if (ys.size() < count) {
                count = ys.size();
            }
            if (zs.size() < count) {
                count = zs.size();
            }
            // Bound callback work even if a device returns an unexpected batch.
            if (count < 2) {
                return;
            } else if (count > 40) {
                count = 40;
            }
            var totalDelta = 0.0;
            var accepted = 0;
            for (var i = 1; i < count; i += 1) {
                if (!isFiniteSensorNumber(xs[i]) || !isFiniteSensorNumber(ys[i]) ||
                    !isFiniteSensorNumber(zs[i]) || !isFiniteSensorNumber(xs[i - 1]) ||
                    !isFiniteSensorNumber(ys[i - 1]) || !isFiniteSensorNumber(zs[i - 1])) {
                    continue;
                }
                totalDelta += absolute(xs[i] - xs[i - 1]);
                totalDelta += absolute(ys[i] - ys[i - 1]);
                totalDelta += absolute(zs[i] - zs[i - 1]);
                accepted += 1;
            }
            if (accepted > 0) {
                var sampleScore = totalDelta / accepted;
                motionScore = (motionScore * 0.55) + (sampleScore * 0.45);
                lastMotionTimerMs = System.getTimer();
                motionAvailable = true;
                if (motionScore >= motionThreshold() * 0.55) {
                    lastCredibleMotionSeconds = elapsedSeconds;
                    if (effortState.equals("SET ACTIVE") && activeSetSeen) {
                        currentSetLastEvidenceGymCalories = gymCalories;
                        currentSetLastEvidenceGarminCalories = garminCalories;
                    } else if (!activeSetSeen && !paused) {
                        beginSetCandidate(hr);
                    }
                }
            }
        } catch (ex) {
            // A malformed or temporarily unavailable batch is ignored.
        }
    }

    static function isFiniteSensorNumber(value) {
        if (!(value instanceof Lang.Number) && !(value instanceof Lang.Float) &&
            !(value instanceof Lang.Long) && !(value instanceof Lang.Double)) {
            return false;
        }
        var number = value.toFloat();
        return number == number && number >= -16000.0 && number <= 16000.0;
    }

    static function absolute(value) {
        return value < 0 ? -value : value;
    }

    static function isMotionFresh() {
        if (!motionAvailable || lastMotionTimerMs <= 0) {
            return false;
        }
        var age = System.getTimer() - lastMotionTimerMs;
        return age >= 0 && age <= 2500;
    }

    static function readHeartRateFromSensor() {
        sensorHr = null;
        if (Toybox has :Sensor) {
            try {
                var info = Sensor.getInfo();
                if (info != null && isValidHeartRate(info.heartRate)) {
                    sensorHr = info.heartRate;
                }
            } catch (ex) {
            }
        }
        return sensorHr;
    }

    static function updateGarminActivityInfo() {
        var appliedHeartRate = false;
        activityHr = null;
        if (Toybox has :Activity) {
            try {
                var info = Activity.getActivityInfo();
                if (info != null) {
                    if (isValidHeartRate(info.currentHeartRate)) {
                        activityHr = info.currentHeartRate;
                        hrSource = "ACT";
                        appliedHeartRate = applyHeartRate(info.currentHeartRate);
                    }
                    if (info.calories != null) {
                        garminCalories = info.calories;
                    }
                }
            } catch (ex) {
            }
        }
        return appliedHeartRate;
    }

    static function isValidHeartRate(value) {
        return value instanceof Lang.Number && value > 0 && value <= 240;
    }

    static function applyHeartRate(value) {
        if (!isValidHeartRate(value)) {
            return false;
        }
        // A new reading confirms at most one second after the previous reading.
        // Attribute that bounded slice to the previous zone before replacing it;
        // a multi-second sensor gap remains unassigned instead of being painted
        // with the later reading's zone.
        if (hr != null) {
            trackCandidateSetInterval(lastValidHrSeconds, zone);
            trackActiveSetInterval(lastValidHrSeconds, zone);
        }
        hr = value;
        lastValidHrSeconds = elapsedSeconds;
        hrSamples += 1;
        avgHr = (((avgHr * (hrSamples - 1)) + value) / hrSamples).toNumber();
        if (value > maxHr) {
            maxHr = value;
        }
        trackMinuteHeartRate(value);
        zone = zoneFor(value);
        filteredHr = filteredHeartRate(value);
        trackRecoveryHeartRate(value);
        updateEffortState(filteredHr);
        return true;
    }

    static function trackRecoveryHeartRate(value) {
        if (recoveryPeakHr == null || !effortState.equals("REST")) {
            return;
        }
        if (recoveryLowestHr == null || value < recoveryLowestHr) {
            recoveryLowestHr = value;
        }
    }

    static function filteredHeartRate(value) {
        if (previousFilterHr == null) {
            previousFilterHr = value;
            return value;
        } else if (olderFilterHr == null) {
            var average = ((previousFilterHr + value) / 2).toNumber();
            olderFilterHr = previousFilterHr;
            previousFilterHr = value;
            return average;
        }
        var a = olderFilterHr;
        var b = previousFilterHr;
        var c = value;
        olderFilterHr = previousFilterHr;
        previousFilterHr = value;
        if ((a >= b && a <= c) || (a <= b && a >= c)) {
            return a;
        } else if ((b >= a && b <= c) || (b <= a && b >= c)) {
            return b;
        }
        return c;
    }

    static function expireStaleHeartRate() {
        if (hr != null && elapsedSeconds - lastValidHrSeconds >= 5) {
            if (effortState.equals("SET ACTIVE") && activeSetSeen) {
                lastSetEndSeconds = activeEvidenceEndSeconds();
                currentSetEndHr = hr;
                currentSetEndGymCalories = currentSetLastEvidenceGymCalories != null ?
                    currentSetLastEvidenceGymCalories : currentSetStartGymCalories;
                currentSetEndGarminCalories = currentSetLastEvidenceGarminCalories != null ?
                    currentSetLastEvidenceGarminCalories : currentSetStartGarminCalories;
            }
            hr = null;
            activityHr = null;
            sensorHr = null;
            hrSource = "--";
            zone = 0;
            filteredHr = null;
            previousFilterHr = null;
            olderFilterHr = null;
            lastHr = null;
            hrTrend = 0.0;
            activeSignalCount = 0;
            motionSignalCount = 0;
            setConfidence = 0;
            confidenceLevel = "LOW";
            clearSetCandidate();
            if (!effortState.equals("PAUSED")) {
                effortState = "READY";
            }
            lastAutoReason = "hr missing";
            debugText = "no hr";
        }
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
        var wasSetActive = effortState.equals("SET ACTIVE");
        lastHr = value;
        if (sessionBaselineHr == null) {
            sessionBaselineHr = value;
        }
        if (previous == null) {
            if (!activeSetSeen && isMotionFresh() && motionScore >= motionThreshold()) {
                beginSetCandidate(value);
            }
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
        // A high but flat recovery heart rate is not proof that another set began.
        // Require a renewed upward signal when using zone as the entry condition.
        var zoneEntrySignal = zoneEnough && (delta >= 1 || hrTrend >= 1.0);
        updateSetConfidence(risingEnough, zoneEntrySignal);
        if (!activeSetSeen) {
            if (setConfidence >= 40) {
                beginSetCandidate(value);
                candidateLastSignalSeconds = elapsedSeconds;
            } else {
                clearSetCandidate();
            }
        }
        if (effortState.equals("SET ACTIVE")) {
            if (currentSetPeakHr == null || value > currentSetPeakHr) {
                currentSetPeakHr = value;
            }
            if (setConfidence > currentSetMaxConfidence) {
                currentSetMaxConfidence = setConfidence;
            }
        }
        if (setConfidence >= 70) {
            activeSignalCount += 1;
        } else {
            activeSignalCount = 0;
        }

        if (activeSignalCount >= 2) {
            if (!effortState.equals("SET ACTIVE")) {
                activeSetSeen = true;
                var hasCandidate = candidateZoneSeconds instanceof Lang.Array &&
                    candidateZoneSeconds.size() == 6 &&
                    candidateStartSeconds <= elapsedSeconds &&
                    elapsedSeconds - candidateStartSeconds <= 8;
                activeStartSeconds = hasCandidate ? candidateStartSeconds : elapsedSeconds;
                lastSetEndSeconds = 0;
                currentSetStartHr = hasCandidate && candidateStartHr != null ?
                    candidateStartHr : value;
                currentSetPeakHr = value;
                currentSetEndHr = null;
                currentSetMaxConfidence = setConfidence;
                beginSetInterval();
                lastAutoReason = "rise +" + baselineDelta.toString();
            }
            effortState = "SET ACTIVE";
            if (currentSetPeakHr == null || value > currentSetPeakHr) {
                currentSetPeakHr = value;
            }
            if (setConfidence > currentSetMaxConfidence) {
                currentSetMaxConfidence = setConfidence;
            }
            lastHrChangeSeconds = elapsedSeconds;
        } else if (delta <= fallThreshold || hrTrend <= fallThreshold || elapsedSeconds - lastHrChangeSeconds > restDetectSeconds) {
            if (!wasSetActive) {
                clearSetCandidate();
            }
            var activeDuration = elapsedSeconds - activeStartSeconds;
            if (wasSetActive && activeSetSeen) {
                lastSetEndSeconds = elapsedSeconds;
                currentSetEndHr = value;
            }
            if (
                GymStore.autoPromptEnabled &&
                activeSetSeen &&
                !autoLogPrompt &&
                activeDuration >= minActiveSeconds &&
                elapsedSeconds - lastPromptSeconds > promptGapSeconds
            ) {
                autoLogPrompt = true;
                lastPromptSeconds = elapsedSeconds;
                lastAutoReason = "rest after " + activeDuration.toString() + "s";
            } else {
                lastAutoReason = "rest no prompt";
            }
            effortState = "REST";
            if (value < sessionBaselineHr || (!activeSetSeen && baselineDelta < 4)) {
                sessionBaselineHr = ((sessionBaselineHr * 3) + value) / 4;
            }
        } else if (setConfidence >= 40 && !activeSetSeen) {
            effortState = "SET MAYBE";
            lastAutoReason = "uncertain";
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
        debugText = "d" + delta.toString() + " m" + motionScore.format("%.0f") +
            " c" + setConfidence.toString() + " " + lastAutoReason;
    }

    static function updateSetConfidence(risingEnough, zoneEntrySignal) {
        var score = 0;
        var freshMotion = isMotionFresh();
        if (!freshMotion) {
            motionSignalCount = 0;
            // Preserve the HR-only fallback when motion is unavailable or stale.
            if (risingEnough) {
                score = 85;
            } else if (zoneEntrySignal) {
                score = 75;
            }
        } else {
            var threshold = motionThreshold();
            var strongMotion = motionScore >= threshold;
            var moderateMotion = motionScore >= threshold * 0.55;
            if (strongMotion) {
                motionSignalCount += 1;
                if (motionSignalCount > 4) {
                    motionSignalCount = 4;
                }
            } else if (moderateMotion && motionSignalCount > 0) {
                motionSignalCount -= 1;
            } else {
                motionSignalCount = 0;
            }
            if (risingEnough) {
                score += 45;
            } else if (zoneEntrySignal) {
                score += 30;
            }
            // Heart rate often lags a short strength set. A sustained strong motion
            // burst is sufficient evidence after two bounded samples; the separate
            // activeSignalCount gate still requires confirmation on two HR ticks.
            if (strongMotion && motionSignalCount >= 2) {
                score += 75;
            } else if (strongMotion) {
                score += 45;
            } else if (moderateMotion) {
                score += 25;
            }
            if ((risingEnough || zoneEntrySignal) && moderateMotion) {
                score += 10;
            }
        }
        if (score > 100) {
            score = 100;
        }
        setConfidence = score;
        confidenceLevel = score >= 70 ? "HIGH" : (score >= 40 ? "MED" : "LOW");
    }

    static function motionThreshold() {
        if (GymStore.sensitivityIndex == 0) {
            return 180.0;
        } else if (GymStore.sensitivityIndex == 2) {
            return 95.0;
        }
        return 130.0;
    }

    static function captureSetStatistics() {
        promoteSetCandidateForCapture();
        var hasEndedInterval = (restoredSetInterval instanceof Lang.Array) ||
            (currentSetEndGymCalories != null && lastSetEndSeconds >= activeStartSeconds);
        var ended = hasEndedInterval ?
            lastSetEndSeconds :
            (currentSetZoneSeconds instanceof Lang.Array ? activeEvidenceEndSeconds() : elapsedSeconds);
        var hasDetectedInterval = currentSetZoneSeconds instanceof Lang.Array ||
            restoredSetInterval instanceof Lang.Array;
        var started = hasDetectedInterval && activeStartSeconds >= 0 && activeStartSeconds <= ended ?
            activeStartSeconds : ended;
        var duration = ended - started;
        if (duration < 0) {
            duration = 0;
        } else if (duration > 7200) {
            duration = 7200;
        }
        var startHrValue = currentSetStartHr;
        var peakHrValue = currentSetPeakHr;
        var endHrValue = currentSetEndHr != null ? currentSetEndHr : hr;
        if (peakHrValue == null && hr != null) {
            peakHrValue = hr;
        }
        if (startHrValue != null && (peakHrValue == null || startHrValue > peakHrValue)) {
            peakHrValue = startHrValue;
        }
        if (endHrValue != null && (peakHrValue == null || endHrValue > peakHrValue)) {
            peakHrValue = endHrValue;
        }
        var confidence = currentSetMaxConfidence;
        if (setConfidence > confidence) {
            confidence = setConfidence;
        }
        if (confidence < 0) {
            confidence = 0;
        } else if (confidence > 100) {
            confidence = 100;
        }
        var setInterval = restoredSetInterval != null ?
            copySetInterval(restoredSetInterval) : capturedSetInterval(started, ended);
        return {
            "activeSeconds" => duration,
            "setStartedSeconds" => started,
            "setEndedSeconds" => ended,
            "startHeartRate" => startHrValue,
            "peakHeartRate" => peakHrValue,
            "endHeartRate" => endHrValue,
            "detectionConfidence" => confidence,
            "setInterval" => setInterval
        };
    }

    static function promoteSetCandidateForCapture() {
        if (activeSetSeen || restoredSetInterval instanceof Lang.Array ||
            currentSetZoneSeconds instanceof Lang.Array ||
            !(candidateZoneSeconds instanceof Lang.Array) ||
            candidateZoneSeconds.size() != 6 ||
            candidateStartSeconds < 0 || candidateStartSeconds > elapsedSeconds ||
            elapsedSeconds - candidateStartSeconds > 8 ||
            elapsedSeconds - candidateLastSignalSeconds > 3) {
            return;
        }
        // A manual press is the athlete's confirmation. Preserve the bounded
        // first motion/HR evidence even when the automatic detector has only
        // seen one of its two confirmation ticks.
        activeSetSeen = true;
        effortState = "SET ACTIVE";
        activeStartSeconds = candidateStartSeconds;
        lastSetEndSeconds = 0;
        currentSetStartHr = candidateStartHr;
        currentSetPeakHr = isValidHeartRate(hr) ? hr : candidateStartHr;
        currentSetEndHr = null;
        currentSetMaxConfidence = setConfidence;
        beginSetInterval();
    }

    static function beginSetInterval() {
        var useCandidate = candidateZoneSeconds instanceof Lang.Array &&
            candidateZoneSeconds.size() == 6 &&
            candidateStartSeconds == activeStartSeconds;
        currentSetZoneSeconds = [0, 0, 0, 0, 0, 0];
        if (useCandidate) {
            for (var i = 0; i < 6; i += 1) {
                currentSetZoneSeconds[i] = candidateZoneSeconds[i];
            }
        }
        currentSetLastIntervalSeconds = elapsedSeconds;
        currentSetStartGymCalories = useCandidate ? candidateStartGymCalories : gymCalories;
        currentSetStartGarminCalories = useCandidate ? candidateStartGarminCalories : garminCalories;
        currentSetEndGymCalories = null;
        currentSetEndGarminCalories = null;
        currentSetLastEvidenceGymCalories = gymCalories;
        currentSetLastEvidenceGarminCalories = garminCalories;
        restoredSetInterval = null;
        clearSetCandidate();
    }

    static function resetCurrentSetInterval() {
        currentSetZoneSeconds = null;
        currentSetLastIntervalSeconds = 0;
        currentSetStartGymCalories = null;
        currentSetStartGarminCalories = null;
        currentSetEndGymCalories = null;
        currentSetEndGarminCalories = null;
        currentSetLastEvidenceGymCalories = null;
        currentSetLastEvidenceGarminCalories = null;
        restoredSetInterval = null;
    }

    static function beginSetCandidate(startHrValue) {
        if (activeSetSeen || paused) {
            return;
        }
        if (candidateZoneSeconds instanceof Lang.Array) {
            candidateLastSignalSeconds = elapsedSeconds;
            return;
        }
        candidateStartSeconds = elapsedSeconds;
        candidateLastSignalSeconds = elapsedSeconds;
        candidateStartHr = isValidHeartRate(startHrValue) ? startHrValue : null;
        candidateStartGymCalories = gymCalories;
        candidateStartGarminCalories = garminCalories;
        candidateZoneSeconds = [0, 0, 0, 0, 0, 0];
        candidateLastIntervalSeconds = elapsedSeconds;
    }

    static function clearSetCandidate() {
        candidateStartSeconds = 0;
        candidateLastSignalSeconds = 0;
        candidateStartHr = null;
        candidateStartGymCalories = null;
        candidateStartGarminCalories = null;
        candidateZoneSeconds = null;
        candidateLastIntervalSeconds = 0;
    }

    static function expireSetCandidate() {
        if (candidateZoneSeconds instanceof Lang.Array &&
            (elapsedSeconds - candidateStartSeconds > 8 ||
                elapsedSeconds - candidateLastSignalSeconds > 3)) {
            clearSetCandidate();
        }
    }

    static function trackCandidateSetInterval(sampleSeconds, sampleZone) {
        if (!(candidateZoneSeconds instanceof Lang.Array) ||
            candidateZoneSeconds.size() != 6) {
            return;
        }
        if (elapsedSeconds - candidateStartSeconds > 8 ||
            elapsedSeconds - candidateLastSignalSeconds > 3) {
            clearSetCandidate();
            return;
        }
        if (sampleSeconds < candidateStartSeconds || sampleZone < 0 || sampleZone > 5) {
            return;
        }
        var delta = elapsedSeconds - sampleSeconds;
        if (delta <= 0) {
            return;
        } else if (delta > 1) {
            delta = 1;
        }
        candidateLastIntervalSeconds = sampleSeconds + delta;
        candidateZoneSeconds[sampleZone] += delta;
        if (candidateZoneSeconds[sampleZone] > 8) {
            candidateZoneSeconds[sampleZone] = 8;
        }
    }

    static function activeEvidenceEndSeconds() {
        var evidenceEnd = lastValidHrSeconds;
        if (lastCredibleMotionSeconds > evidenceEnd) {
            evidenceEnd = lastCredibleMotionSeconds;
        }
        if (evidenceEnd < activeStartSeconds) {
            evidenceEnd = activeStartSeconds;
        } else if (evidenceEnd > elapsedSeconds) {
            evidenceEnd = elapsedSeconds;
        }
        return evidenceEnd;
    }

    static function captureActiveEvidenceTotals() {
        if (!effortState.equals("SET ACTIVE") || !activeSetSeen) {
            return;
        }
        var evidenceEnd = activeEvidenceEndSeconds();
        if (evidenceEnd == elapsedSeconds) {
            currentSetLastEvidenceGymCalories = gymCalories;
            currentSetLastEvidenceGarminCalories = garminCalories;
        }
    }

    static function captureEndedSetTotals() {
        if (!activeSetSeen || lastSetEndSeconds <= 0 ||
            currentSetEndGymCalories != null) {
            return;
        }
        currentSetEndGymCalories = gymCalories;
        currentSetEndGarminCalories = garminCalories;
    }

    static function trackActiveSetInterval(sampleSeconds, sampleZone) {
        if (!effortState.equals("SET ACTIVE") ||
            !(currentSetZoneSeconds instanceof Lang.Array) ||
            currentSetZoneSeconds.size() != 6) {
            return;
        }
        if (sampleSeconds < activeStartSeconds || sampleZone < 0 || sampleZone > 5) {
            return;
        }
        var delta = elapsedSeconds - sampleSeconds;
        if (delta <= 0) {
            return;
        }
        if (delta > 1) {
            delta = 1;
        }
        currentSetLastIntervalSeconds = sampleSeconds + delta;
        currentSetZoneSeconds[sampleZone] += delta;
        if (currentSetZoneSeconds[sampleZone] > 7200) {
            currentSetZoneSeconds[sampleZone] = 7200;
        }
    }

    static function capturedSetInterval(started, ended) {
        if (started < 0) {
            started = 0;
        } else if (started > 604800) {
            started = 604800;
        }
        if (ended < started) {
            ended = started;
        } else if (ended > started + 7200) {
            ended = started + 7200;
        }
        if (ended > 604800) {
            ended = 604800;
        }
        var duration = ended - started;
        if (duration < 0) {
            duration = 0;
        } else if (duration > 7200) {
            duration = 7200;
        }
        var gymDelta = 0.0;
        var endingGymCalories = currentSetEndGymCalories != null ?
            currentSetEndGymCalories :
            (currentSetLastEvidenceGymCalories != null ?
                currentSetLastEvidenceGymCalories : gymCalories);
        if (currentSetStartGymCalories != null &&
            endingGymCalories >= currentSetStartGymCalories) {
            gymDelta = endingGymCalories - currentSetStartGymCalories;
            if (gymDelta > 100000.0) {
                gymDelta = 100000.0;
            }
        }
        var garminDelta = null;
        var endingGarminCalories = currentSetEndGarminCalories != null ?
            currentSetEndGarminCalories :
            (currentSetLastEvidenceGarminCalories != null ?
                currentSetLastEvidenceGarminCalories : garminCalories);
        if ((currentSetStartGarminCalories instanceof Lang.Number ||
                currentSetStartGarminCalories instanceof Lang.Long) &&
            (endingGarminCalories instanceof Lang.Number ||
                endingGarminCalories instanceof Lang.Long) &&
            endingGarminCalories >= currentSetStartGarminCalories) {
            garminDelta = endingGarminCalories - currentSetStartGarminCalories;
            if (garminDelta > 100000) {
                garminDelta = 100000;
            }
        }
        var interval = [started, ended, gymDelta, garminDelta, 0, 0, 0, 0, 0, 0];
        var remaining = duration;
        if (currentSetZoneSeconds instanceof Lang.Array && currentSetZoneSeconds.size() == 6) {
            for (var i = 0; i < 6; i += 1) {
                var seconds = currentSetZoneSeconds[i];
                if (!(seconds instanceof Lang.Number) || seconds < 0) {
                    seconds = 0;
                }
                if (seconds > remaining) {
                    seconds = remaining;
                }
                interval[i + 4] = seconds;
                remaining -= seconds;
            }
        }
        return interval;
    }

    static function copySetInterval(source) {
        var copy = [];
        if (!(source instanceof Lang.Array) || source.size() != 10) {
            return [0, 0, 0.0, null, 0, 0, 0, 0, 0, 0];
        }
        for (var i = 0; i < source.size(); i += 1) {
            copy.add(source[i]);
        }
        return copy;
    }

    static function beginRecoveryTracking(statistics) {
        recoveryPeakHr = statistics == null ? null : statistics.get("peakHeartRate");
        recoveryLowestHr = statistics == null ? null : statistics.get("endHeartRate");
    }

    static function recoveryHeartRateDrop() {
        if (recoveryPeakHr == null || recoveryLowestHr == null) {
            return null;
        }
        var drop = recoveryPeakHr - recoveryLowestHr;
        if (drop < 0) {
            drop = 0;
        } else if (drop > 240) {
            drop = 240;
        }
        return drop;
    }

    static function clearRecoveryTracking() {
        recoveryPeakHr = null;
        recoveryLowestHr = null;
    }

    static function clearAutoPrompt() {
        autoLogPrompt = false;
        activeSetSeen = false;
        activeSignalCount = 0;
        // Motion sampled during the just-saved set must not count toward the next
        // set. A genuinely new callback immediately repopulates score/freshness.
        motionSignalCount = 0;
        motionScore = 0.0;
        lastMotionTimerMs = 0;
        lastCredibleMotionSeconds = 0;
        effortState = "REST";
        hrTrend = 0.0;
        lastHrChangeSeconds = elapsedSeconds;
        if (hr != null) {
            sessionBaselineHr = hr;
        }
        currentSetStartHr = null;
        currentSetPeakHr = null;
        currentSetEndHr = null;
        currentSetMaxConfidence = 0;
        resetCurrentSetInterval();
        clearSetCandidate();
        activeStartSeconds = 0;
        lastSetEndSeconds = 0;
        setConfidence = 0;
        confidenceLevel = "LOW";
        lastAutoReason = "set logged";
    }

    static function restoreSetAfterUndo(statistics, restorePrompt) {
        if (!(statistics instanceof Lang.Dictionary)) {
            clearAutoPrompt();
            return;
        }
        autoLogPrompt = restorePrompt instanceof Lang.Boolean && restorePrompt;
        activeSetSeen = true;
        activeSignalCount = 0;
        effortState = "REST";
        activeStartSeconds = statistics.get("setStartedSeconds");
        lastSetEndSeconds = statistics.get("setEndedSeconds");
        currentSetStartHr = statistics.get("startHeartRate");
        currentSetPeakHr = statistics.get("peakHeartRate");
        currentSetEndHr = statistics.get("endHeartRate");
        currentSetMaxConfidence = statistics.get("detectionConfidence");
        restoredSetInterval = copySetInterval(statistics.get("setInterval"));
        currentSetZoneSeconds = null;
        currentSetLastIntervalSeconds = 0;
        currentSetStartGymCalories = null;
        currentSetStartGarminCalories = null;
        currentSetEndGymCalories = null;
        currentSetEndGarminCalories = null;
        currentSetLastEvidenceGymCalories = null;
        currentSetLastEvidenceGarminCalories = null;
        clearSetCandidate();
        setConfidence = currentSetMaxConfidence;
        confidenceLevel = setConfidence >= 70 ? "HIGH" : (setConfidence >= 40 ? "MED" : "LOW");
        recoveryPeakHr = null;
        recoveryLowestHr = null;
        lastAutoReason = autoLogPrompt ? "auto set undo" : "manual set undo";
    }

    static function resetProfileDefaults() {
        profileWeightKg = 80.0;
        profileAge = 30;
        profileGender = null;
        profileVo2Max = null;
        restingHr = 60;
        maxHrEstimate = 185;
        zones = null;
    }

    static function loadProfile() {
        try {
            var profile = UserProfile.getProfile();
            if (profile != null && profile.weight != null && profile.weight >= 30000 && profile.weight <= 300000) {
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
            if (profile != null && profile.restingHeartRate != null && profile.restingHeartRate > 30 && profile.restingHeartRate < 120) {
                restingHr = profile.restingHeartRate;
            } else if (profile != null && profile.averageRestingHeartRate != null && profile.averageRestingHeartRate > 30 && profile.averageRestingHeartRate < 120) {
                restingHr = profile.averageRestingHeartRate;
            }
            if (profile != null && profile.birthYear != null && profile.birthYear > 1900) {
                var age = Time.Gregorian.info(Time.now(), Time.FORMAT_MEDIUM).year - profile.birthYear;
                if (age >= 12 && age <= 100) {
                    profileAge = age;
                    maxHrEstimate = (208.0 - (0.7 * age)).toNumber();
                }
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
        if (!hasValidHeartRateZones()) {
            var reserve = maxHrEstimate - restingHr;
            if (reserve < 40) {
                reserve = 100;
            }
            var hrr = (value - restingHr).toFloat() / reserve.toFloat();
            if (hrr < 0.50) {
                return 0;
            } else if (hrr < 0.60) {
                return 1;
            } else if (hrr < 0.70) {
                return 2;
            } else if (hrr < 0.80) {
                return 3;
            } else if (hrr < 0.90) {
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

    static function hasValidHeartRateZones() {
        if (!(zones instanceof Lang.Array) || zones.size() < 6) {
            return false;
        }
        var previous = 0;
        for (var i = 0; i < 6; i += 1) {
            if (!(zones[i] instanceof Lang.Number) || zones[i] <= previous || zones[i] > 240) {
                return false;
            }
            previous = zones[i];
        }
        return true;
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

    static function setBoostFor(weightKg, reps) {
        if (weightKg == null || reps == null || weightKg <= 0 || reps <= 0) {
            return 0.0;
        }
        var volume = weightKg * reps;
        // Strength-specific correction: HR lags behind short anaerobic sets.
        // Add a bounded mechanical-work/EPOC estimate per saved set.
        var boost = 1.2 + (volume / 700.0);
        if (boost > 7.0) {
            boost = 7.0;
        }
        return boost;
    }

    static function addSetBoost(weightKg, reps) {
        var boost = setBoostFor(weightKg, reps);
        setBoostCalories += boost;
        gymCalories += boost;
        return boost;
    }

    static function removeSetBoost(boost) {
        if (!(boost instanceof Lang.Float) && !(boost instanceof Lang.Double) && !(boost instanceof Lang.Number)) {
            return;
        }
        if (boost < 0.0 || boost > 7.0) {
            return;
        }
        setBoostCalories -= boost;
        gymCalories -= boost;
        if (setBoostCalories < 0.0) {
            setBoostCalories = 0.0;
        }
        if (gymCalories < 0.0) {
            gymCalories = 0.0;
        }
    }

    static function restoreSetBoost(boost) {
        if (!(boost instanceof Lang.Float) && !(boost instanceof Lang.Double) && !(boost instanceof Lang.Number)) {
            return;
        }
        if (boost < 0.0 || boost > 7.0) {
            return;
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
                return clampMet(1.0 + (hrr * 0.8), 1.0, 1.5);
            }
            return clampMet(1.15 + (hrr * 1.2), 1.15, 1.8);
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
            return clampMet(recoveryMet, 1.15, 2.6);
        }

        return clampMet(1.0 + (hrr * 1.2), 1.0, 1.8);
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
