import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const section = (source, start, end) => {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(startIndex, -1, `Missing start anchor: ${start}`);
  assert.notEqual(endIndex, -1, `Missing end anchor: ${end}`);
  return source.slice(startIndex, endIndex);
};

test("Garmin tracking prefers activity HR, diagnoses both sources, and expires stale readings", async () => {
  const [session, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const tick = section(session, "static function tick()", "static function startSensors()");
  assert.ok(
    tick.indexOf("updateGarminActivityInfo()") < tick.indexOf("readHeartRateFromSensor()"),
    "the native activity sample remains authoritative"
  );
  assert.match(tick, /if \(!appliedActivityHeartRate\)[\s\S]*applyHeartRate\(sampledSensorHeartRate\)/);
  assert.match(tick, /expireStaleHeartRate\(\)/);
  assert.match(session, /elapsedSeconds - lastValidHrSeconds >= 5/);
  assert.match(session, /var a = olderFilterHr[\s\S]*var b = previousFilterHr[\s\S]*var c = value/);
  assert.match(session, /updateEffortState\(filteredHr\)/);
  assert.match(session, /var zoneEntrySignal = zoneEnough && \(delta >= 1 \|\| hrTrend >= 1\.0\)/);
  assert.match(session, /static function hasValidHeartRateZones\(\)/);
  assert.match(view, /"ACT", GymSession\.activityHr/);
  assert.match(view, /"SNS", GymSession\.sensorHr/);
  assert.match(view, /"MOV", GymSession\.motionAvailable/);
  assert.match(view, /"CONF", GymSession\.setConfidence/);
});

test("Garmin rest countdown never blocks or hides a detected next set", async () => {
  const [session, store, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const tick = section(view, "function tick()", "function requestSyncNow()");
  assert.match(
    tick,
    /rest > 0 && GymSession\.effortState\.equals\("SET ACTIVE"\)[\s\S]*GymStore\.cancelRest\(\)/
  );
  assert.ok(
    tick.indexOf("restWasActive = false") < tick.indexOf('GymStore.status = "REST DONE"'),
    "canceling rest for a new set must not vibrate as if the timer completed"
  );
  const dashboard = section(view, "function drawDashboard(", "function showPauseFlash()");
  assert.match(dashboard, /var setActive = GymSession\.effortState\.equals\("SET ACTIVE"\)/);
  assert.ok(
    dashboard.indexOf("setActive ?") < dashboard.indexOf("rest > 0 ?"),
    "active-set status must take visual priority over the countdown"
  );
  assert.match(store, /static function cancelRest\(\) \{\s*restEndsAt = 0;/);
  assert.match(
    session,
    /static function clearAutoPrompt\(\)[\s\S]*effortState = "REST"[\s\S]*lastHrChangeSeconds = elapsedSeconds/
  );
});

test("Garmin can undo only the most recent set inside a bounded window", async () => {
  const [session, store, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  assert.match(store, /undoWindowMs = 10000/);
  assert.match(store, /static function canUndoLastSet\(\)/);
  const undo = section(store, "static function undoLastSet()", "static function cancelRest()");
  assert.match(undo, /if \(!canUndoLastSet\(\)\)[\s\S]*return false/);
  assert.match(undo, /var lastIndex = sets\.size\(\) - 1/);
  assert.match(undo, /sets\.remove\(lastSet\)/);
  assert.match(undo, /GymSession\.removeSetBoost\(boost\)/);
  assert.match(undo, /if \(!save\(\)\)[\s\S]*sets\.add\(lastSet\)[\s\S]*GymSession\.restoreSetBoost\(boost\)/);
  assert.match(undo, /restEndsAt = 0/);
  assert.match(session, /static function restoreAutoPromptAfterUndo\(statistics\)/);
  assert.match(view, /function isUndoOverlayActive\(\)/);
  assert.match(view, /GymStore\.tr\("TAP \/ BACK: UNDO"/);
  assert.match(view, /function onBack\(\)[\s\S]*if \(GymStore\.canUndoLastSet\(\)\)[\s\S]*undoLastSet\(\)/);
  assert.match(view, /if \(x < \(view\.screenWidth \/ 2\)\)[\s\S]*undoLastSet\(\)[\s\S]*recordSet\(\)/);
});

test("Garmin set save and undo keep calorie corrections consistent on failure", async () => {
  const [session, store, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");
  assert.match(addSet, /var boost = GymSession\.addSetBoost\(weight, reps\)/);
  assert.match(addSet, /if \(!save\(\)\)[\s\S]*sets\.remove\(setItem\)[\s\S]*GymSession\.removeSetBoost\(boost\)[\s\S]*return false/);
  assert.match(session, /static function removeSetBoost\(boost\)/);
  assert.match(session, /static function restoreSetBoost\(boost\)/);
  const recordSet = section(view, "function recordSet()", "function undoLastSet()");
  assert.match(recordSet, /if \(GymStore\.addSet\(\)\)[\s\S]*showSetSavedFlash[\s\S]*Attention\.vibrate/);
});

test("Garmin fuses bounded motion evidence with HR and falls back safely", async () => {
  const [session, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const listener = section(session, "static function startMotionListener()", "static function stopMotionListener()");
  assert.match(listener, /Sensor has :registerSensorDataListener/);
  assert.match(listener, /:sampleRate => 10/);
  assert.match(listener, /catch \(ex\)[\s\S]*motionAvailable = false/);
  const callback = section(session, "static function onSensorData(data)", "static function isFiniteSensorNumber");
  assert.match(callback, /count > 40/);
  assert.match(callback, /isFiniteSensorNumber/);
  assert.doesNotMatch(callback, /Storage|GymComm|setValue/);
  const confidence = section(session, "static function updateSetConfidence", "static function motionThreshold");
  assert.match(confidence, /if \(!freshMotion\)[\s\S]*score = 85/);
  assert.match(confidence, /strongMotion[\s\S]*moderateMotion/);
  assert.match(session, /if \(setConfidence >= 70\)[\s\S]*activeSignalCount \+= 1/);
  assert.match(view, /SET MAYBE/);
  assert.match(view, /confidenceLabel\(\)/);
});

test("Garmin set metrics are bounded, persisted, undo-aware, and synchronized without raw motion", async () => {
  const [session, store, androidSecurity, androidManager] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/garmin/GarminSyncSecurity.kt", "utf8"),
    readFile("app/src/main/java/com/example/gymapp/garmin/GarminSyncManager.kt", "utf8")
  ]);

  assert.match(session, /static function captureSetStatistics\(\)/);
  assert.match(session, /"activeSeconds" => duration/);
  assert.match(session, /static function recoveryHeartRateDrop\(\)/);
  const addSet = section(store, "static function addSet()", "static function canUndoLastSet()");
  assert.match(addSet, /"restBeforeSeconds" => restBefore/);
  assert.match(addSet, /"detectionConfidence" => statistics\.get\("detectionConfidence"\)/);
  assert.match(addSet, /if \(!save\(\)\)[\s\S]*previousSet\.remove\("recoveryHeartRateDrop"\)/);
  assert.match(store, /setMetrics\.add\(compactSetMetrics\(setItem\)\)/);
  assert.match(store, /"setMetrics" => setMetrics/);
  assert.match(store, /static function isValidSetMetricsList/);
  assert.doesNotMatch(store, /accelerometerData|motionScore/);
  assert.match(androidSecurity, /data class GarminSetStatistics/);
  assert.match(androidSecurity, /require\(values\.size == 7\)/);
  assert.match(androidSecurity, /optionalBoundedLong\(item, "activeSeconds", 0L, 7_200L\)/);
  assert.match(androidSecurity, /optionalBoundedInt\(item, "detectionConfidence", 0, 100\)/);
  assert.match(androidSecurity, /gymapp-garmin-workout\/v2/);
  assert.match(androidManager, /statistics\.recoveryHeartRateDrop/);
  assert.match(androidManager, /statistics\.detectionConfidence/);
});
