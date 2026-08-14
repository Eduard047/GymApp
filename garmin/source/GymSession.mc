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
    // FIT completion is separate from the app-level workout queue. Keep only the
    // state needed to make a post-save cleanup retry idempotent; diagnostic UI
    // uses GymStore.status.
    static var fitSaved = false;
    // A failed discard during an account transition must keep the native Session
    // reachable for a later retry. Dropping or overwriting it can leave an old FIT
    // recording alive and make the next account unable to start a clean session.
    static var fitCleanupPending = false;
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
    static var gyroAvailable = false;
    static var gyroScore = 0.0;
    static var motionNoiseFloor = 0.0;
    static var lastMotionTimerMs = null;
    static var lastCredibleMotionSeconds = 0;
    static var motionSignalCount = 0;
    static var motionBurstSignals = 0;
    static var motionRhythmSignals = 0;
    static var motionBurstStartedSeconds = 0;
    static var currentSetMotionConfirmed = false;
    static var currentSetMotionOnly = false;
    static var lastLoggedSetSeconds = -10;
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
    static var currentSetLastMotionHr = null;
    static var currentSetLastMotionPeakHr = null;
    static var currentSetLastMotionZoneSeconds = null;
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
        if (!retryAccountTransitionFitCleanup()) {
            return false;
        }
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
        gyroAvailable = false;
        gyroScore = 0.0;
        motionNoiseFloor = 0.0;
        lastMotionTimerMs = null;
        lastCredibleMotionSeconds = 0;
        motionSignalCount = 0;
        motionBurstSignals = 0;
        motionRhythmSignals = 0;
        motionBurstStartedSeconds = 0;
        currentSetMotionConfirmed = false;
        currentSetMotionOnly = false;
        lastLoggedSetSeconds = -10;
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
        fitSaved = false;
        paused = false;

        if (Toybox has :ActivityRecording) {
            try {
                session = Recording.createSession({
                    :name => "GymApp Strength",
                    :sport => Activity.SPORT_TRAINING,
                    :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
                });
                createFitFields();
                if (session.start()) {
                    recording = true;
                } else {
                    failStartAndCleanup();
                }
            } catch (ex) {
                failStartAndCleanup();
            }
        } else {
            failStartAndCleanup();
        }
        // A failed FIT start must remain fail-closed on the Ready screen. Do not
        // leave motion or heart-rate listeners running when no authoritative
        // activity recording exists.
        if (recording) {
            startSensors();
        } else {
            stopSensors();
        }
        return recording;
    }

    static function failStartAndCleanup() {
        fitCleanupPending = session != null && !discard();
        recording = false;
        paused = false;
        startedAt = 0;
        pausedAt = 0;
        elapsedSeconds = 0;
        GymStore.status = fitCleanupPending ? "FIT RETRY" : "REC FAIL";
    }

    static function pause() {
        if (paused) {
            return true;
        }
        if (session != null) {
            try {
                if (session.isRecording() && !session.stop()) {
                    GymStore.status = "PAUSE FAIL";
                    return false;
                }
            } catch (ex) {
                GymStore.status = "PAUSE FAIL";
                return false;
            }
        }
        paused = true;
        pausedAt = Time.now().value();
        stopSensors();
        effortState = "PAUSED";
        return true;
    }

    static function resume() {
        if (!paused) {
            return true;
        }
        // Restart the authoritative FIT session first. Some older products reject
        // a high-frequency listener while activity recording is stopped; a failed
        // Session.start() must leave the workout visibly paused.
        if (session != null) {
            try {
                if (!session.isRecording() && !session.start()) {
                    GymStore.status = "RESUME FAIL";
                    return false;
                }
            } catch (ex) {
                GymStore.status = "RESUME FAIL";
                return false;
            }
        }
        var now = Time.now().value();
        if (pausedAt > 0) {
            pausedAccumSeconds += now - pausedAt;
        }
        pausedAt = 0;
        paused = false;
        startSensors();
        // Paused time is already removed from elapsedSeconds. It is not a set
        // boundary, so keep every active motion/HR snapshot intact across resume.
        effortState = activeSetSeen ? "SET ACTIVE" : "READY";
        return true;
    }

    static function stopAndSave() {
        stopSensors();
        if (session == null) {
            // A successful FIT save can be followed by a retry when clearing the
            // app's local workout state failed. Treat that retry as idempotent.
            return !recording && fitSaved;
        }
        var saved = false;
        try {
            if (session.isRecording() && !session.stop()) {
                return false;
            }
            saved = session.save();
        } catch (ex) {
            saved = false;
        }
        if (!saved) {
            return false;
        }
        session = null;
        gymKcalField = null;
        gymZoneField = null;
        recording = false;
        paused = false;
        fitSaved = true;
        return true;
    }

    (:recoveryCore)
    static function fitOutcomeUnknownAfterRestart() {
        return session == null && !recording && !fitSaved;
    }

    // The 96 KiB products cannot afford the richer decision screen, but they
    // still need to distinguish a live FIT handle from the phase-0 marker left
    // by a process termination. This predicate never creates, saves, or
    // discards an ActivityRecording session.
    (:compactRecovery96)
    static function fitOutcomeUnknownAfterRestart() {
        return session == null && !recording && !fitSaved;
    }

    static function discard() {
        stopSensors();
        if (session == null) {
            recording = false;
            paused = false;
            fitSaved = false;
            fitCleanupPending = false;
            return true;
        }
        var discarded = false;
        try {
            if (!session.isRecording() || session.stop()) {
                discarded = session.discard();
            }
        } catch (ex) {
            discarded = false;
        }
        if (!discarded) {
            GymStore.status = "FIT FAIL";
            return false;
        }
        session = null;
        gymKcalField = null;
        gymZoneField = null;
        recording = false;
        paused = false;
        fitSaved = false;
        fitCleanupPending = false;
        return true;
    }

    static function resetForAccountTransition() {
        // An account transition is a privacy boundary: stop sensors and discard the
        // active FIT recording. A new workout must be started explicitly by the user.
        var fitDiscarded = discard();
        // Session.stop()/discard() can fail transiently on real devices. Preserve the
        // handle and retry instead of overwriting a still-active native FIT session.
        fitCleanupPending = !fitDiscarded && session != null;
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
        fitSaved = false;
        autoLogPrompt = false;
        activeSetSeen = false;
        motionScore = 0.0;
        gyroAvailable = false;
        gyroScore = 0.0;
        motionNoiseFloor = 0.0;
        lastMotionTimerMs = null;
        lastCredibleMotionSeconds = 0;
        motionSignalCount = 0;
        motionBurstSignals = 0;
        motionRhythmSignals = 0;
        motionBurstStartedSeconds = 0;
        currentSetMotionConfirmed = false;
        currentSetMotionOnly = false;
        lastLoggedSetSeconds = -10;
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
        if (fitCleanupPending) {
            GymStore.status = "FIT RETRY";
        }
    }

    static function retryAccountTransitionFitCleanup() {
        if (!fitCleanupPending) {
            return true;
        }
        if (!discard()) {
            GymStore.status = "FIT RETRY";
            return false;
        }
        fitCleanupPending = false;
        return true;
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
        if (fitCleanupPending) {
            retryAccountTransitionFitCleanup();
            return;
        }
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
        updateMotionLifecycle();
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

    (:fullLegacyState)
    static function startMotionListener() {
        if (motionListenerRegistered || !(Sensor has :registerSensorDataListener)) {
            return;
        }
        // Connect IQ allows only one high-frequency listener. Prefer a synchronized
        // accelerometer + gyroscope request so rotation can corroborate moderate
        // wrist movement, but retry accelerometer-only when a product rejects gyro.
        // Losing optional gyro must never disable the long-supported accelerometer.
        if (motionListener == null) {
            motionListener = new GymMotionListener();
        }
        try {
            // Ten samples per second is sufficient for wrist-motion evidence and
            // materially lighter than the 25 Hz reference rate.
            Sensor.registerSensorDataListener(motionListener.method(:onSensorData), {
                :period => 1,
                :synchronous => true,
                :accelerometer => {
                    :enabled => true,
                    :sampleRate => 10,
                    :includePower => false,
                    :includePitch => false,
                    :includeRoll => false,
                    :includeTimestamps => false
                },
                :gyroscope => {
                    :enabled => true,
                    :sampleRate => 10,
                    :includeTimestamps => false
                }
            });
            motionListenerRegistered = true;
            motionAvailable = true;
        } catch (ex) {
            if (Sensor has :unregisterSensorDataListener) {
                try {
                    Sensor.unregisterSensorDataListener();
                } catch (ignored) {
                }
            }
            try {
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
                gyroAvailable = false;
                gyroScore = 0.0;
            } catch (fallbackEx) {
                // Older products may expose Sensor without supporting this stream.
                // Heart-rate-only detection remains available.
                motionListenerRegistered = false;
                motionAvailable = false;
                gyroAvailable = false;
                motionScore = 0.0;
                gyroScore = 0.0;
                lastMotionTimerMs = null;
            }
        }
    }

    // The compact hardware tier uses the proven accelerometer + HR path. The
    // synchronized gyro implementation above is excluded only to preserve its
    // loader reserve; failure still falls back to HR-only detection.
    (:compactLegacyState)
    static function startMotionListener() {
        if (motionListenerRegistered || !(Sensor has :registerSensorDataListener)) {
            return;
        }
        try {
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
            motionListenerRegistered = false;
            motionAvailable = false;
            motionScore = 0.0;
            lastMotionTimerMs = null;
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
        gyroAvailable = false;
        gyroScore = 0.0;
        lastMotionTimerMs = null;
        if (!activeSetSeen) {
            lastCredibleMotionSeconds = 0;
            motionSignalCount = 0;
            motionBurstSignals = 0;
            motionRhythmSignals = 0;
            motionBurstStartedSeconds = 0;
            clearSetCandidate();
        }
    }

    (:fullLegacyState)
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
            var priorDirection = 0;
            var reversals = 0;
            for (var i = 1; i < count; i += 1) {
                if (!isFiniteSensorNumber(xs[i]) || !isFiniteSensorNumber(ys[i]) ||
                    !isFiniteSensorNumber(zs[i]) || !isFiniteSensorNumber(xs[i - 1]) ||
                    !isFiniteSensorNumber(ys[i - 1]) || !isFiniteSensorNumber(zs[i - 1])) {
                    continue;
                }
                var dx = xs[i] - xs[i - 1];
                var dy = ys[i] - ys[i - 1];
                var dz = zs[i] - zs[i - 1];
                var adx = absolute(dx);
                var ady = absolute(dy);
                var adz = absolute(dz);
                totalDelta += adx + ady + adz;
                var dominant = adx >= ady && adx >= adz ? dx : (ady >= adz ? dy : dz);
                if (absolute(dominant) >= 10) {
                    var direction = dominant > 0 ? 1 : -1;
                    if (priorDirection != 0 && direction != priorDirection) {
                        reversals += 1;
                    }
                    priorDirection = direction;
                }
                accepted += 1;
            }
            if (accepted > 0) {
                var sampleScore = totalDelta / accepted;
                motionScore = (motionScore * 0.55) + (sampleScore * 0.45);
                var gyroRead = false;
                if ((data has :gyroscopeData) && data.gyroscopeData != null) {
                    var gyroSample = axisDeltaScore(data.gyroscopeData);
                    if (gyroSample != null) {
                        gyroScore = (gyroScore * 0.55) + (gyroSample * 0.45);
                        gyroAvailable = true;
                        gyroRead = true;
                    }
                }
                if (!gyroRead) {
                    gyroAvailable = false;
                    gyroScore = 0.0;
                }
                lastMotionTimerMs = System.getTimer();
                motionAvailable = true;
                updateMotionNoiseFloor(sampleScore);
                var threshold = adaptiveMotionThreshold();
                var accelStrong = motionScore >= threshold;
                var accelModerate = motionScore >= threshold * 0.55;
                var gyroStrong = gyroAvailable && gyroScore >= gyroThreshold();
                var strongMotion = accelStrong || (accelModerate && gyroStrong);
                var rhythmic = reversals >= 1 && reversals <= 6;
                updateMotionBurst(strongMotion, accelModerate, rhythmic);
                if (accelModerate) {
                    if (effortState.equals("SET ACTIVE") && activeSetSeen && !autoLogPrompt) {
                        if (strongMotion && rhythmic) {
                            // After promotion, only a rep-like reversal may move
                            // the boundary. Handling plates or walking must not
                            // keep extending the set through the quiet window.
                            lastCredibleMotionSeconds = elapsedSeconds;
                            currentSetLastEvidenceGymCalories = gymCalories;
                            currentSetLastEvidenceGarminCalories = garminCalories;
                            currentSetEndGymCalories = gymCalories;
                            currentSetEndGarminCalories = garminCalories;
                            if (isValidHeartRate(hr)) {
                                currentSetLastMotionHr = hr;
                            }
                            if (isValidHeartRate(currentSetPeakHr)) {
                                currentSetLastMotionPeakHr = currentSetPeakHr;
                            }
                            snapshotMotionSetZones();
                            currentSetMotionConfirmed = true;
                        }
                    } else if (!activeSetSeen && !paused && canArmMotionCandidate()) {
                        lastCredibleMotionSeconds = elapsedSeconds;
                        beginSetCandidate(hr);
                    }
                }
            }
        } catch (ex) {
            // A malformed or temporarily unavailable batch is ignored.
        }
    }

    (:fullLegacyState)
    static function axisDeltaScore(sensorData) {
        if (sensorData == null) {
            return null;
        }
        var xs = sensorData.x;
        var ys = sensorData.y;
        var zs = sensorData.z;
        if (!(xs instanceof Lang.Array) || !(ys instanceof Lang.Array) ||
            !(zs instanceof Lang.Array)) {
            return null;
        }
        var count = xs.size();
        if (ys.size() < count) {
            count = ys.size();
        }
        if (zs.size() < count) {
            count = zs.size();
        }
        if (count < 2) {
            return null;
        } else if (count > 40) {
            count = 40;
        }
        var total = 0.0;
        var accepted = 0;
        for (var i = 1; i < count; i += 1) {
            if (!isFiniteSensorNumber(xs[i]) || !isFiniteSensorNumber(ys[i]) ||
                !isFiniteSensorNumber(zs[i]) || !isFiniteSensorNumber(xs[i - 1]) ||
                !isFiniteSensorNumber(ys[i - 1]) || !isFiniteSensorNumber(zs[i - 1])) {
                continue;
            }
            total += absolute(xs[i] - xs[i - 1]);
            total += absolute(ys[i] - ys[i - 1]);
            total += absolute(zs[i] - zs[i - 1]);
            accepted += 1;
        }
        return accepted > 0 ? total / accepted : null;
    }

    (:compactLegacyState)
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
            if (count < 2) {
                return;
            }
            var last = count - 1;
            if (!isFiniteSensorNumber(xs[0]) || !isFiniteSensorNumber(ys[0]) ||
                !isFiniteSensorNumber(zs[0]) || !isFiniteSensorNumber(xs[last]) ||
                !isFiniteSensorNumber(ys[last]) || !isFiniteSensorNumber(zs[last])) {
                return;
            }
            var sampleScore = absolute(xs[last] - xs[0]) +
                absolute(ys[last] - ys[0]) + absolute(zs[last] - zs[0]);
            motionScore = (motionScore + sampleScore) / 2.0;
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
        } catch (ex) {
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
        if (!motionAvailable || lastMotionTimerMs == null) {
            return false;
        }
        var age = GymStore.timerElapsedMs(lastMotionTimerMs);
        return age >= 0 && age <= 2500;
    }

    (:fullLegacyState)
    static function updateMotionNoiseFloor(sampleScore) {
        if (paused || activeSetSeen || autoLogPrompt ||
            candidateZoneSeconds instanceof Lang.Array ||
            sampleScore < 0.0 || sampleScore > 48000.0) {
            return;
        }
        // Learn only quiet/rest movement. A large first gesture must not teach the
        // detector that a real set is background noise.
        var base = motionThreshold();
        // Keep the learner well below the actual movement band. In particular,
        // one light first repetition must not be reclassified as room noise and
        // raise the threshold for the rest of that set.
        if (sampleScore > base * 0.40) {
            return;
        }
        if (motionNoiseFloor <= 0.0) {
            motionNoiseFloor = sampleScore;
        } else {
            motionNoiseFloor = (motionNoiseFloor * 0.92) + (sampleScore * 0.08);
        }
        if (motionNoiseFloor > base) {
            motionNoiseFloor = base;
        }
    }

    (:fullLegacyState)
    static function adaptiveMotionThreshold() {
        var base = motionThreshold();
        var adaptive = (motionNoiseFloor * 2.4) + 35.0;
        if (adaptive < base) {
            return base;
        }
        var ceiling = base * 1.75;
        return adaptive > ceiling ? ceiling : adaptive;
    }

    (:fullLegacyState)
    static function gyroThreshold() {
        if (GymStore.sensitivityIndex == 0) {
            return 45.0;
        } else if (GymStore.sensitivityIndex == 2) {
            return 20.0;
        }
        return 30.0;
    }

    (:fullLegacyState)
    static function updateMotionBurst(strongMotion, moderateMotion, rhythmic) {
        if (paused || autoLogPrompt) {
            return;
        }
        if (strongMotion) {
            if (motionBurstSignals == 0) {
                motionBurstStartedSeconds = elapsedSeconds;
            }
            motionBurstSignals += 1;
            if (motionBurstSignals > 6) {
                motionBurstSignals = 6;
            }
            if (rhythmic) {
                motionRhythmSignals += 1;
                if (motionRhythmSignals > 6) {
                    motionRhythmSignals = 6;
                }
            } else if (motionRhythmSignals > 0) {
                motionRhythmSignals -= 1;
            }
        } else if (moderateMotion) {
            if (motionBurstSignals > 0) {
                motionBurstSignals -= 1;
            }
            if (motionRhythmSignals > 0) {
                motionRhythmSignals -= 1;
            }
        } else {
            motionBurstSignals = 0;
            motionRhythmSignals = 0;
            motionBurstStartedSeconds = 0;
        }
    }

    (:fullLegacyState)
    static function canArmMotionCandidate() {
        return !paused && !autoLogPrompt &&
            (GymStore.sets.size() == 0 ||
                elapsedSeconds - lastLoggedSetSeconds >=
                    10);
    }

    (:fullLegacyState)
    static function hasCredibleRestRestartEvidence(risingEnough) {
        if (GymStore.restDurationMs <= 0) {
            return true;
        }
        if (elapsedSeconds - lastLoggedSetSeconds <
            10) {
            return false;
        }
        if (risingEnough) {
            return true;
        }
        var candidateIsSustained = candidateZoneSeconds instanceof Lang.Array &&
            candidateStartSeconds >= 0 && candidateStartSeconds <= elapsedSeconds &&
            elapsedSeconds - candidateStartSeconds >= 2 &&
            elapsedSeconds - candidateLastSignalSeconds <= 2;
        var fullMotionIsRhythmic = motionBurstSignals == 0 ||
            (motionBurstSignals >= 4 && motionRhythmSignals >= 3);
        return candidateIsSustained && fullMotionIsRhythmic &&
            motionSignalCount >= 3 && motionScore >= motionThreshold();
    }

    (:compactLegacyState)
    static function hasCredibleRestRestartEvidence(risingEnough) {
        if (GymStore.restDurationMs <= 0) {
            return true;
        }
        return elapsedSeconds - lastLoggedSetSeconds >=
                10 &&
            (risingEnough ||
                (motionSignalCount >= 3 && motionScore >= motionThreshold()));
    }

    (:fullLegacyState)
    static function updateMotionLifecycle() {
        if (paused || autoLogPrompt) {
            return;
        }
        if (!activeSetSeen) {
            if (canArmMotionCandidate() &&
                candidateZoneSeconds instanceof Lang.Array &&
                motionBurstSignals >= 4 && motionRhythmSignals >= 3 &&
                elapsedSeconds - motionBurstStartedSeconds >= 2 &&
                elapsedSeconds - candidateLastSignalSeconds <= 2) {
                promoteMotionCandidate();
            }
            return;
        }
        if (!effortState.equals("SET ACTIVE") || !currentSetMotionConfirmed) {
            return;
        }
        // AUTO OFF is deliberate manual mode: keep the interval active until the
        // athlete presses save, and never create a prompt or vibration.
        if (!GymStore.autoPromptEnabled) {
            return;
        }
        var motionDuration = lastCredibleMotionSeconds - activeStartSeconds;
        if (motionDuration < 0) {
            motionDuration = 0;
        } else if (motionDuration > elapsedSeconds - activeStartSeconds) {
            motionDuration = elapsedSeconds - activeStartSeconds;
        }
        var quietSeconds = elapsedSeconds - lastCredibleMotionSeconds;
        if (quietSeconds >= motionQuietWindowSeconds()) {
            if (motionDuration >= motionMinimumSetSeconds()) {
                endSetFromMotion();
            } else if (currentSetMotionOnly) {
                discardShortMotionInterval();
            } else if (hr == null) {
                endHrCorroboratedSetAfterSignalLoss();
            }
        }
    }

    (:fullLegacyState)
    static function discardShortMotionInterval() {
        // A few strong movements can be loading plates or walking. If they stop
        // before the minimum bounded set duration, clear only transient detector
        // state—never create a set, rest timer, prompt, or durable payload.
        clearAutoPrompt();
        GymStore.status = "MOTION SHORT";
        lastAutoReason = "short motion ignored";
        debugText = "short motion";
    }

    (:fullLegacyState)
    static function endHrCorroboratedSetAfterSignalLoss() {
        if (!GymStore.autoPromptEnabled) {
            return;
        }
        var ended = activeEvidenceEndSeconds();
        if (ended < activeStartSeconds) {
            ended = activeStartSeconds;
        } else if (ended > elapsedSeconds) {
            ended = elapsedSeconds;
        }
        lastSetEndSeconds = ended;
        currentSetEndGymCalories = currentSetLastEvidenceGymCalories;
        currentSetEndGarminCalories = currentSetLastEvidenceGarminCalories;
        effortState = "REST";
        activeSignalCount = 0;
        autoLogPrompt = true;
        lastPromptSeconds = elapsedSeconds;
        lastAutoReason = "hr signal lost";
    }

    (:fullLegacyState)
    static function promoteMotionCandidate() {
        if (activeSetSeen || !(candidateZoneSeconds instanceof Lang.Array) ||
            candidateZoneSeconds.size() != 6 ||
            candidateStartSeconds < 0 || candidateStartSeconds > elapsedSeconds ||
            elapsedSeconds - candidateStartSeconds > 8) {
            return;
        }
        activeSetSeen = true;
        effortState = "SET ACTIVE";
        activeStartSeconds = candidateStartSeconds;
        lastSetEndSeconds = 0;
        currentSetStartHr = candidateStartHr;
        currentSetPeakHr = isValidHeartRate(hr) ? hr : candidateStartHr;
        currentSetEndHr = null;
        var gyroCorroborated = gyroAvailable && gyroScore >= gyroThreshold();
        setConfidence = gyroCorroborated ? 85 : 78;
        confidenceLevel = "HIGH";
        currentSetMaxConfidence = setConfidence;
        currentSetMotionConfirmed = true;
        currentSetMotionOnly = true;
        beginSetInterval();
        initializeMotionSetSnapshot();
        lastHrChangeSeconds = elapsedSeconds;
        lastAutoReason = gyroCorroborated ? "motion+gyro" : "motion rhythm";
    }

    (:fullLegacyState)
    static function endSetFromMotion() {
        if (!GymStore.autoPromptEnabled) {
            return;
        }
        // Heart rate can remain valid throughout the quiet confirmation window.
        // Motion-confirmed sets must end at their last credible movement, not at
        // the latest HR tick, otherwise duration, zones and calories include rest.
        var ended = lastCredibleMotionSeconds;
        if (ended < activeStartSeconds) {
            ended = activeStartSeconds;
        } else if (ended > elapsedSeconds) {
            ended = elapsedSeconds;
        }
        var duration = ended - activeStartSeconds;
        if (duration < motionMinimumSetSeconds()) {
            return;
        }
        lastSetEndSeconds = ended;
        currentSetEndHr = currentSetLastMotionHr;
        currentSetPeakHr = currentSetLastMotionPeakHr;
        restoreMotionSetZoneSnapshot();
        activeSignalCount = 0;
        effortState = "REST";
        // A detected boundary is never auto-saved, but it must always become a
        // pending confirmation. Suppressing it can merge the next superset into
        // this unsaved interval. The post-save deadband prevents duplicate prompts.
        autoLogPrompt = true;
        lastPromptSeconds = elapsedSeconds;
        lastAutoReason = "motion rest " + duration.toString() + "s";
    }

    (:fullLegacyState)
    static function snapshotMotionSetZones() {
        if (!(currentSetZoneSeconds instanceof Lang.Array) ||
            currentSetZoneSeconds.size() != 6) {
            return;
        }
        if (!(currentSetLastMotionZoneSeconds instanceof Lang.Array) ||
            currentSetLastMotionZoneSeconds.size() != 6) {
            currentSetLastMotionZoneSeconds = [0, 0, 0, 0, 0, 0];
        }
        for (var i = 0; i < 6; i += 1) {
            currentSetLastMotionZoneSeconds[i] = currentSetZoneSeconds[i];
        }
    }

    (:fullLegacyState)
    static function restoreMotionSetZoneSnapshot() {
        if (!(currentSetLastMotionZoneSeconds instanceof Lang.Array) ||
            currentSetLastMotionZoneSeconds.size() != 6) {
            return;
        }
        currentSetZoneSeconds = [0, 0, 0, 0, 0, 0];
        for (var i = 0; i < 6; i += 1) {
            currentSetZoneSeconds[i] = currentSetLastMotionZoneSeconds[i];
        }
    }

    (:fullLegacyState)
    static function initializeMotionSetSnapshot() {
        if (!currentSetMotionConfirmed) {
            return;
        }
        if (isValidHeartRate(hr)) {
            currentSetLastMotionHr = hr;
        }
        if (isValidHeartRate(currentSetPeakHr)) {
            currentSetLastMotionPeakHr = currentSetPeakHr;
        }
        currentSetEndGymCalories = gymCalories;
        currentSetEndGarminCalories = garminCalories;
        snapshotMotionSetZones();
    }

    (:compactLegacyState)
    static function initializeMotionSetSnapshot() {
    }

    (:fullLegacyState)
    static function hasCompleteMotionInterval() {
        if (!currentSetMotionConfirmed) {
            return false;
        }
        var ended = lastCredibleMotionSeconds;
        if (ended < activeStartSeconds) {
            ended = activeStartSeconds;
        } else if (ended > elapsedSeconds) {
            ended = elapsedSeconds;
        }
        return ended - activeStartSeconds >= motionMinimumSetSeconds();
    }

    (:compactLegacyState)
    static function hasCompleteMotionInterval() {
        return false;
    }

    (:fullLegacyState)
    static function motionMinimumSetSeconds() {
        if (GymStore.sensitivityIndex == 0) {
            return 12;
        } else if (GymStore.sensitivityIndex == 2) {
            return 8;
        }
        return 10;
    }

    (:fullLegacyState)
    static function motionQuietWindowSeconds() {
        if (GymStore.sensitivityIndex == 0) {
            return 8;
        } else if (GymStore.sensitivityIndex == 2) {
            return 5;
        }
        return 6;
    }

    (:compactLegacyState)
    static function updateMotionLifecycle() {
    }

    (:fullLegacyState)
    static function activeSetSeconds() {
        if (!activeSetSeen || activeStartSeconds < 0) {
            return 0;
        }
        var ended = lastSetEndSeconds > 0 ? lastSetEndSeconds : elapsedSeconds;
        var duration = ended - activeStartSeconds;
        if (duration < 0) {
            return 0;
        } else if (duration > 7200) {
            return 7200;
        }
        return duration;
    }

    (:fullLegacyState)
    static function activeSetText() {
        var seconds = activeSetSeconds();
        var minutes = (seconds / 60).toNumber();
        var remainder = seconds % 60;
        return minutes.toString() + ":" +
            (remainder < 10 ? "0" : "") + remainder.toString();
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

    (:fullLegacyState)
    static function expireStaleHeartRate() {
        if (hr != null && elapsedSeconds - lastValidHrSeconds >= 5) {
            // Motion lifecycle runs immediately after HR sampling in tick(). Keep
            // its active interval intact even exactly at/after the quiet boundary;
            // it will finalize, discard a short false start, or enter manual mode.
            var wasActiveSet = effortState.equals("SET ACTIVE") && activeSetSeen;
            var keepMotionSet = wasActiveSet && currentSetMotionConfirmed;
            if (wasActiveSet) {
                currentSetEndHr = hr;
                if (!keepMotionSet && GymStore.autoPromptEnabled) {
                    lastSetEndSeconds = activeEvidenceEndSeconds();
                    currentSetEndGymCalories = currentSetLastEvidenceGymCalories != null ?
                        currentSetLastEvidenceGymCalories : currentSetStartGymCalories;
                    currentSetEndGarminCalories = currentSetLastEvidenceGarminCalories != null ?
                        currentSetLastEvidenceGarminCalories : currentSetStartGarminCalories;
                }
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
            if (keepMotionSet) {
                if (setConfidence < 70) {
                    setConfidence = 70;
                }
                confidenceLevel = "HIGH";
                lastAutoReason = "motion no hr";
                debugText = "motion only";
            } else if (wasActiveSet && !GymStore.autoPromptEnabled) {
                // Manual mode retains the bounded HR interval until SAVE.
                effortState = "SET ACTIVE";
                lastAutoReason = "manual no hr";
                debugText = "no hr manual";
            } else if (wasActiveSet) {
                var minimum = GymStore.sensitivityIndex == 0 ? 20 :
                    (GymStore.sensitivityIndex == 2 ? 12 : 15);
                if (lastSetEndSeconds - activeStartSeconds >= minimum) {
                    effortState = "REST";
                    autoLogPrompt = true;
                    lastPromptSeconds = elapsedSeconds;
                    lastAutoReason = "hr signal lost";
                    debugText = "save set";
                } else {
                    clearAutoPrompt();
                    GymStore.status = "HR SHORT";
                    lastAutoReason = "short hr ignored";
                    debugText = "short hr";
                }
            } else {
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
    }

    (:compactLegacyState)
    static function expireStaleHeartRate() {
        if (hr == null || elapsedSeconds - lastValidHrSeconds < 5) {
            return;
        }
        var wasActiveSet = effortState.equals("SET ACTIVE") && activeSetSeen;
        if (wasActiveSet) {
            currentSetEndHr = hr;
            lastSetEndSeconds = activeEvidenceEndSeconds();
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
        if (wasActiveSet) {
            if (!GymStore.autoPromptEnabled) {
                effortState = "SET ACTIVE";
                return;
            }
            var minimum = GymStore.sensitivityIndex == 0 ? 20 :
                (GymStore.sensitivityIndex == 2 ? 12 : 15);
            if (lastSetEndSeconds - activeStartSeconds >= minimum) {
                effortState = "REST";
                autoLogPrompt = true;
                lastPromptSeconds = elapsedSeconds;
            } else {
                clearAutoPrompt();
                GymStore.status = "HR SHORT";
            }
            return;
        }
        motionSignalCount = 0;
        setConfidence = 0;
        confidenceLevel = "LOW";
        clearSetCandidate();
        if (!effortState.equals("PAUSED")) {
            effortState = "READY";
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

    (:fullLegacyState)
    static function updateEffortState(value) {
        var previous = lastHr;
        var wasSetActive = effortState.equals("SET ACTIVE");
        lastHr = value;
        if (sessionBaselineHr == null) {
            sessionBaselineHr = value;
        }
        if (autoLogPrompt) {
            lastAutoReason = "await confirm";
            debugText = "save set";
            return;
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

        if (GymStore.sensitivityIndex == 0) {
            riseThreshold = 7;
            trendThreshold = 4.0;
            minRiseFromBaseline = 12;
            fallThreshold = -4;
            activeZone = 3;
            minActiveSeconds = 20;
            restDetectSeconds = 45;
        } else if (GymStore.sensitivityIndex == 2) {
            riseThreshold = 4;
            trendThreshold = 2.5;
            minRiseFromBaseline = 8;
            fallThreshold = -2;
            activeZone = 2;
            minActiveSeconds = 12;
            restDetectSeconds = 25;
        }

        var baselineDelta = value - sessionBaselineHr;
        var risingEnough = (delta >= riseThreshold || hrTrend >= trendThreshold) && baselineDelta >= minRiseFromBaseline;
        var zoneEnough = zone >= activeZone && baselineDelta >= (minRiseFromBaseline / 2);
        // A high but flat recovery heart rate is not proof that another set began.
        // Require a renewed upward signal when using zone as the entry condition.
        var renewedRiseDelta = 3;
        var renewedRiseTrend = 2.0;
        if (GymStore.sensitivityIndex == 0) {
            renewedRiseDelta = 4;
            renewedRiseTrend = 2.5;
        } else if (GymStore.sensitivityIndex == 2) {
            renewedRiseDelta = 2;
            renewedRiseTrend = 1.5;
        }
        var zoneEntrySignal = zoneEnough &&
            (delta >= renewedRiseDelta || hrTrend >= renewedRiseTrend);
        updateSetConfidence(risingEnough, zoneEntrySignal);
        if (currentSetMotionOnly && activeSetSeen && setConfidence >= 70 &&
            (risingEnough || zoneEntrySignal)) {
            // Once HR independently corroborates the interval, a short set is
            // owned by the normal HR rest path rather than discarded as noise.
            currentSetMotionOnly = false;
        }
        if (!activeSetSeen) {
            if (setConfidence >= 40) {
                beginSetCandidate(value);
                candidateLastSignalSeconds = elapsedSeconds;
            } else if (!(candidateZoneSeconds instanceof Lang.Array) ||
                !isMotionFresh() || motionBurstSignals == 0) {
                clearSetCandidate();
            }
        }
        if (effortState.equals("SET ACTIVE")) {
            currentSetEndHr = value;
            if (currentSetPeakHr == null || value > currentSetPeakHr) {
                currentSetPeakHr = value;
            }
            if (setConfidence > currentSetMaxConfidence) {
                currentSetMaxConfidence = setConfidence;
            }
        }
        if (setConfidence >= 75 &&
            hasCredibleRestRestartEvidence(risingEnough)) {
            activeSignalCount += 1;
        } else {
            activeSignalCount = 0;
        }

        if (activeSignalCount >= 3) {
            if (!effortState.equals("SET ACTIVE")) {
                if (activeSetSeen) {
                    // Resume the same not-yet-saved interval after a short pause;
                    // never replace its first evidence or calorie baseline.
                    lastSetEndSeconds = 0;
                    currentSetEndHr = null;
                    currentSetEndGymCalories = null;
                    currentSetEndGarminCalories = null;
                    if (motionBurstSignals >= 2 && motionRhythmSignals >= 1) {
                        currentSetMotionConfirmed = true;
                    }
                    lastAutoReason = "set resumed";
                } else {
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
                    currentSetMotionConfirmed = motionBurstSignals >= 2 &&
                        motionRhythmSignals >= 1;
                    currentSetMotionOnly = false;
                    beginSetInterval();
                    initializeMotionSetSnapshot();
                    lastAutoReason = "rise +" + baselineDelta.toString();
                }
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
            if (wasSetActive && activeSetSeen && !GymStore.autoPromptEnabled) {
                // AUTO OFF is manual mode on every product: a transient HR fall
                // must never erase or hide the interval before the athlete saves.
                effortState = "SET ACTIVE";
                lastAutoReason = "manual hold";
                return;
            }
            if (wasSetActive && activeSetSeen && hasCompleteMotionInterval()) {
                // Let the bounded motion lifecycle own this boundary. A fast HR
                // fall inside its quiet window must not preempt the motion/zone/
                // calorie snapshots with a later recovery sample.
                effortState = "SET ACTIVE";
                lastAutoReason = "motion boundary";
                debugText = "motion quiet";
                return;
            }
            var activeDuration = elapsedSeconds - activeStartSeconds;
            if (wasSetActive && activeSetSeen && activeDuration < minActiveSeconds &&
                (!currentSetMotionConfirmed || currentSetMotionOnly)) {
                // A bounded HR spike that ends before the minimum interval is a
                // false start, not an indefinitely pending set. Clearing it also
                // lets WorkoutView restore a rest countdown suspended for it.
                clearAutoPrompt();
                GymStore.status = "HR SHORT";
                lastAutoReason = "short hr ignored";
                debugText = "short hr";
                return;
            }
            if (!wasSetActive) {
                clearSetCandidate();
            }
            if (wasSetActive && activeSetSeen) {
                lastSetEndSeconds = elapsedSeconds;
                currentSetEndHr = value;
                // captureEndedSetTotals runs after this tick's calorie update.
                currentSetEndGymCalories = null;
                currentSetEndGarminCalories = null;
            }
            if (
                GymStore.autoPromptEnabled &&
                activeSetSeen &&
                !autoLogPrompt &&
                (activeDuration >= minActiveSeconds ||
                    (currentSetMotionConfirmed && !currentSetMotionOnly))
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

    // API 3.4 watches have a 96 KiB program ceiling. Keep the same bounded
    // three-sample confirmation and manual-mode safety without the diagnostic
    // branches used by larger products.
    (:compactLegacyState)
    static function updateEffortState(value) {
        var previous = lastHr;
        var wasActive = effortState.equals("SET ACTIVE");
        lastHr = value;
        if (sessionBaselineHr == null) {
            sessionBaselineHr = value;
        }
        if (autoLogPrompt || previous == null) {
            return;
        }
        var delta = value - previous;
        hrTrend = ((hrTrend * 2.0) + delta.toFloat()) / 3.0;
        var rise = GymStore.sensitivityIndex == 0 ? 7 :
            (GymStore.sensitivityIndex == 2 ? 4 : 5);
        var minimum = GymStore.sensitivityIndex == 0 ? 20 :
            (GymStore.sensitivityIndex == 2 ? 12 : 15);
        var baselineDelta = value - sessionBaselineHr;
        var moving = isMotionFresh() && motionScore >= motionThreshold() * 0.55;
        var activeEvidence = baselineDelta >= 8 &&
            (delta >= rise || hrTrend >= 3.0 || moving);
        updateSetConfidence(activeEvidence, zone >= 3 && delta >= 2);
        if (activeEvidence && setConfidence >= 70) {
            activeSignalCount += 1;
        } else {
            activeSignalCount = 0;
        }
        if (activeSignalCount >= 3) {
            if (!activeSetSeen) {
                activeSetSeen = true;
                activeStartSeconds = elapsedSeconds;
                currentSetStartHr = value;
                currentSetPeakHr = value;
                currentSetMaxConfidence = setConfidence;
                beginSetInterval();
            }
            effortState = "SET ACTIVE";
            currentSetEndHr = value;
            if (currentSetPeakHr == null || value > currentSetPeakHr) {
                currentSetPeakHr = value;
            }
            lastHrChangeSeconds = elapsedSeconds;
            return;
        }
        if (wasActive && activeSetSeen &&
            (delta <= -3 || hrTrend <= -3.0 ||
                elapsedSeconds - lastHrChangeSeconds > 35)) {
            if (!GymStore.autoPromptEnabled) {
                effortState = "SET ACTIVE";
                return;
            }
            lastSetEndSeconds = elapsedSeconds;
            currentSetEndHr = value;
            if (elapsedSeconds - activeStartSeconds >= minimum) {
                effortState = "REST";
                autoLogPrompt = true;
                lastPromptSeconds = elapsedSeconds;
            } else {
                clearAutoPrompt();
                GymStore.status = "HR SHORT";
            }
            return;
        }
        if (!activeSetSeen && baselineDelta < 4) {
            sessionBaselineHr = ((sessionBaselineHr * 3) + value) / 4;
        }
    }

    (:fullLegacyState)
    static function updateSetConfidence(risingEnough, zoneEntrySignal) {
        var score = 0;
        var freshMotion = isMotionFresh();
        if (!freshMotion) {
            motionSignalCount = 0;
            // Preserve the HR-only fallback when motion is unavailable or stale.
            if (risingEnough) {
                score = 85;
            } else if (zoneEntrySignal) {
                // A renewed zone reading is useful candidate evidence, but without
                // motion it must not promote a set by itself.
                score = 55;
            }
        } else {
            var threshold = adaptiveMotionThreshold();
            var moderateMotion = motionScore >= threshold * 0.55;
            var strongMotion = motionScore >= threshold ||
                (moderateMotion && gyroAvailable && gyroScore >= gyroThreshold());
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
                score += 55;
            } else if (zoneEntrySignal) {
                score += 30;
            }
            // Heart rate often lags a short strength set. A sustained strong motion
            // burst is sufficient evidence after two bounded samples; the separate
            // activeSignalCount gate still requires confirmation on two HR ticks.
            if (strongMotion && motionSignalCount >= 2) {
                score += 75;
            } else if (strongMotion) {
                score += 35;
            } else if (moderateMotion) {
                score += 15;
            }
            if ((risingEnough || zoneEntrySignal) && moderateMotion) {
                score += 5;
            }
        }
        if (score > 100) {
            score = 100;
        }
        setConfidence = score;
        confidenceLevel = score >= 70 ? "HIGH" : (score >= 40 ? "MED" : "LOW");
    }

    (:compactLegacyState)
    static function updateSetConfidence(risingEnough, zoneEntrySignal) {
        var score = 0;
        var freshMotion = isMotionFresh();
        if (!freshMotion) {
            motionSignalCount = 0;
            if (risingEnough) {
                score = 85;
            } else if (zoneEntrySignal) {
                score = 55;
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
                score += 55;
            } else if (zoneEntrySignal) {
                score += 30;
            }
            if (strongMotion && motionSignalCount >= 2) {
                score += 75;
            } else if (strongMotion) {
                score += 35;
            } else if (moderateMotion) {
                score += 15;
            }
            if ((risingEnough || zoneEntrySignal) && moderateMotion) {
                score += 5;
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

    (:fullLegacyState)
    static function captureSetStatistics() {
        promoteSetCandidateForCapture();
        var hasEndedInterval = (restoredSetInterval instanceof Lang.Array) ||
            (lastSetEndSeconds > 0 && lastSetEndSeconds >= activeStartSeconds);
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
        // Once an interval has ended, a later recovery/quiet HR sample must not
        // masquerade as the set's end HR. Live/manual capture may still use `hr`.
        var endHrValue = currentSetEndHr != null ? currentSetEndHr :
            (hasEndedInterval ? null : hr);
        if (!hasEndedInterval && peakHrValue == null && hr != null) {
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

    (:compactLegacyState)
    static function captureSetStatistics() {
        promoteSetCandidateForCapture();
        var ended = lastSetEndSeconds > 0 ? lastSetEndSeconds : elapsedSeconds;
        var started = activeSetSeen && activeStartSeconds >= 0 &&
            activeStartSeconds <= ended ? activeStartSeconds : ended;
        var duration = ended - started;
        if (duration > 7200) {
            duration = 7200;
        }
        var peak = currentSetPeakHr;
        if (peak == null && isValidHeartRate(hr)) {
            peak = hr;
        }
        var confidence = currentSetMaxConfidence > setConfidence ?
            currentSetMaxConfidence : setConfidence;
        if (confidence > 100) {
            confidence = 100;
        }
        var interval = restoredSetInterval instanceof Lang.Array ?
            copySetInterval(restoredSetInterval) : capturedSetInterval(started, ended);
        return {
            "activeSeconds" => duration,
            "setStartedSeconds" => started,
            "setEndedSeconds" => ended,
            "startHeartRate" => currentSetStartHr,
            "peakHeartRate" => peak,
            "endHeartRate" => currentSetEndHr,
            "detectionConfidence" => confidence,
            "setInterval" => interval
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
        currentSetMotionConfirmed = motionBurstSignals >= 2 &&
            motionRhythmSignals >= 1;
        currentSetMotionOnly = false;
        beginSetInterval();
        initializeMotionSetSnapshot();
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
        currentSetLastMotionHr = null;
        currentSetLastMotionZoneSeconds = null;
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
        currentSetLastMotionHr = null;
        currentSetLastMotionPeakHr = null;
        currentSetLastMotionZoneSeconds = null;
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

    (:fullLegacyState)
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

    (:compactLegacyState)
    static function capturedSetInterval(started, ended) {
        if (started < 0) {
            started = 0;
        }
        if (ended < started) {
            ended = started;
        } else if (ended > started + 7200) {
            ended = started + 7200;
        }
        var gymDelta = 0.0;
        if (currentSetStartGymCalories != null &&
            gymCalories >= currentSetStartGymCalories) {
            gymDelta = gymCalories - currentSetStartGymCalories;
            if (gymDelta > 100000.0) {
                gymDelta = 100000.0;
            }
        }
        var interval = [started, ended, gymDelta, null, 0, 0, 0, 0, 0, 0];
        var remaining = ended - started;
        if (currentSetZoneSeconds instanceof Lang.Array &&
            currentSetZoneSeconds.size() == 6) {
            for (var i = 0; i < 6; i += 1) {
                var seconds = currentSetZoneSeconds[i];
                if (!(seconds instanceof Lang.Number) || seconds < 0) {
                    seconds = 0;
                } else if (seconds > remaining) {
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

    static function clearAutoPrompt() {
        autoLogPrompt = false;
        activeSetSeen = false;
        activeSignalCount = 0;
        // Motion sampled during the just-saved set must not count toward the next
        // set. A genuinely new callback immediately repopulates score/freshness.
        motionSignalCount = 0;
        motionScore = 0.0;
        gyroScore = 0.0;
        lastMotionTimerMs = null;
        lastCredibleMotionSeconds = 0;
        motionBurstSignals = 0;
        motionRhythmSignals = 0;
        motionBurstStartedSeconds = 0;
        currentSetMotionConfirmed = false;
        currentSetMotionOnly = false;
        lastLoggedSetSeconds = elapsedSeconds;
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

    static function rejectAutoPrompt() {
        if (!autoLogPrompt) {
            return false;
        }
        clearAutoPrompt();
        GymStore.status = "SET SKIPPED";
        lastAutoReason = "set rejected";
        debugText = "set rejected";
        return true;
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
        currentSetMotionConfirmed = false;
        currentSetMotionOnly = false;
        restoredSetInterval = copySetInterval(statistics.get("setInterval"));
        currentSetZoneSeconds = null;
        currentSetLastIntervalSeconds = 0;
        currentSetStartGymCalories = null;
        currentSetStartGarminCalories = null;
        currentSetEndGymCalories = null;
        currentSetEndGarminCalories = null;
        currentSetLastEvidenceGymCalories = null;
        currentSetLastEvidenceGarminCalories = null;
        currentSetLastMotionHr = null;
        currentSetLastMotionPeakHr = null;
        currentSetLastMotionZoneSeconds = null;
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

    (:fullLegacyState)
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

    (:compactLegacyState)
    static function loadProfile() {
        try {
            var profile = UserProfile.getProfile();
            if (profile != null && profile.weight != null &&
                profile.weight >= 30000 && profile.weight <= 300000) {
                profileWeightKg = profile.weight / 1000.0;
            }
            if (profile != null && profile.restingHeartRate != null &&
                profile.restingHeartRate > 30 && profile.restingHeartRate < 120) {
                restingHr = profile.restingHeartRate;
            }
        } catch (ex) {
        }
        try {
            zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
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

    static function removeSetBoost(boost) {
        changeSetBoost(boost, false);
    }

    static function restoreSetBoost(boost) {
        changeSetBoost(boost, true);
    }

    static function changeSetBoost(boost, add) {
        if (!(boost instanceof Lang.Float) && !(boost instanceof Lang.Double) && !(boost instanceof Lang.Number)) {
            return;
        }
        if (boost < 0.0 || boost > 7.0) {
            return;
        }
        if (add) {
            setBoostCalories += boost;
            gymCalories += boost;
        } else {
            setBoostCalories -= boost;
            gymCalories -= boost;
            if (setBoostCalories < 0.0) {
                setBoostCalories = 0.0;
            }
            if (gymCalories < 0.0) {
                gymCalories = 0.0;
            }
        }
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
        var totalElapsed = (GymStore.timelineBase == null ? 0 :
            GymStore.timelineBase[0]) + elapsedSeconds;
        var h = (totalElapsed / 3600).toNumber();
        var m = ((totalElapsed % 3600) / 60).toNumber();
        var s = (totalElapsed % 60).toNumber();
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%02d") + ":" + s.format("%02d");
    }
}
