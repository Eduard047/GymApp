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

test("fresh Garmin launch is Ready and performs no workout or outbound sync mutation", async () => {
  const view = await readFile("garmin/source/WorkoutView.mc", "utf8");
  const onShow = section(view, "function onShow()", "function onHide()");
  const tick = section(view, "function tick()", "function requestSyncNow()");

  assert.match(view, /var page = 7/);
  assert.match(onShow, /page = 7/);
  assert.match(onShow, /selected = 0/);
  assert.match(onShow, /getApp\(\)\.pollMailbox\(\)/);
  assert.doesNotMatch(
    onShow,
    /GymSession\.(?:start|resume|startSensors)\(|requestSyncNow\(|flushPending\(|requestCloudSyncNow\(|GymComm\.(?:requestSync|requestCloudPlan|send)\(/
  );
  assert.ok(
    tick.indexOf("if (page == 7 || !GymSession.recording)") < tick.indexOf("GymSession.tick()"),
    "the idle tick must return before recording logic"
  );
  assert.ok(
    tick.indexOf("return;") < tick.indexOf("requestSyncNow()"),
    "the idle tick must return before periodic phone sync"
  );
  assert.doesNotMatch(view, /scheduleCloudSyncOnOpen|requestCloudSyncOnOpen|cloudAuto/);
});

test("Start and Resume are explicit, single-shot, and fail closed", async () => {
  const [view, session] = await Promise.all([
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/source/GymSession.mc", "utf8")
  ]);
  const start = section(view, "function startOrResumeWorkout()", "function syncFromReady()");
  const fitStart = section(session, "static function start()", "static function failStartAndCleanup()");
  const failedFitStart = section(session, "static function failStartAndCleanup()", "static function pause()");

  assert.match(start, /if \(page != 7 \|\| GymSession\.fitSaved\)/);
  assert.match(start, /var resuming = hasWorkoutToResume\(\)/);
  assert.match(start, /GymSession\.recording[\s\S]*GymSession\.paused[\s\S]*GymSession\.resume\(\)/);
  assert.equal((start.match(/GymSession\.start\(\)/g) || []).length, 1);
  assert.ok(start.indexOf("if (!started)") < start.indexOf("page = 0"));
  assert.match(fitStart, /if \(recording\) \{\s*startSensors\(\);\s*\} else \{\s*stopSensors\(\);/);
  assert.ok(
    fitStart.indexOf("if (recording)") > fitStart.indexOf("session.start()"),
    "sensor listeners must be gated by the authoritative FIT start result"
  );
  assert.equal((fitStart.match(/failStartAndCleanup\(\)/g) || []).length, 3);
  assert.match(failedFitStart, /fitCleanupPending = session != null && !discard\(\)/);
  assert.match(failedFitStart, /recording = false[\s\S]*startedAt = 0/);
  assert.match(failedFitStart, /fitCleanupPending \? "FIT RETRY" : "REC FAIL"/);

  const transition = (state, fitStartResult) => {
    if (state.active || state.fitSaved) return { ...state, starts: 0 };
    if (!fitStartResult) return { ...state, starts: 1, active: false, page: 7 };
    return { ...state, starts: 1, active: true, page: 0 };
  };
  assert.deepEqual(
    transition({ active: false, fitSaved: false, page: 7 }, false),
    { active: false, fitSaved: false, page: 7, starts: 1 }
  );
  const started = transition({ active: false, fitSaved: false, page: 7 }, true);
  assert.equal(started.active, true);
  assert.equal(transition(started, true).starts, 0, "a second tap cannot create another FIT session");
});

test("durable unfinished state is resumable while an empty snapshot remains a tombstone", async () => {
  const [store, view] = await Promise.all([
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);
  const unfinished = section(
    store,
    "static function hasUnfinishedWorkout()",
    "static function clearActiveWorkout()"
  );
  assert.match(unfinished, /sets\.size\(\) > 0/);
  assert.match(unfinished, /runtimeWorkoutStartedAtSeconds != null/);
  assert.match(unfinished, /activeWorkoutSnapshotValid/);
  assert.match(unfinished, /timelineBase\[0\] > 0/);
  assert.doesNotMatch(unfinished, /return activeWorkoutSnapshotValid;/);
  assert.match(view, /function readyPrimaryText\(\)[\s\S]*hasWorkoutToResume\(\)/);
  assert.match(view, /"RESUME WORKOUT", "ПРОДОВЖИТИ", "ПРОДОЛЖИТЬ"/);
});

test("Ready manual Sync is the only launch-surface outbound action", async () => {
  const [view, app] = await Promise.all([
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/source/GymApp.mc", "utf8")
  ]);
  const readySync = section(view, "function syncFromReady()", "function finishWorkout()");
  assert.match(readySync, /requestSyncNow\(\)/);
  assert.match(readySync, /flushPending\(\)/);
  assert.match(readySync, /GymComm\.hasCloudDeviceToken\(\)[\s\S]*requestCloudSyncNow\(\)/);
  assert.match(app, /Comm\.registerForPhoneAppMessages\(phoneMessageMethod\)/);
  assert.match(app, /typeText\.equals\("sync"\)[\s\S]*GymStore\.applyPhoneSync\(message\)/);
});

test("Back from Ready exits without falling through to pause or workout navigation", async () => {
  const view = await readFile("garmin/source/WorkoutView.mc", "utf8");
  const back = section(view, "function onBack()", "(:fullLegacyState)\n    function onTap(evt)");
  const readyExit = back.match(/if \(view\.page == 7\) \{([\s\S]*?)\n        \}/)?.[1] || "";
  const exitHelper = section(view, "function exitReady()", "function onSelect()");

  assert.match(exitHelper, /System\.exit\(\);/);
  assert.match(readyExit, /exitReady\(\);\s*return true;/);
  assert.doesNotMatch(readyExit, /openPauseMenu|GymSession\.(?:pause|resume|start)/);
  assert.ok(
    readyExit.indexOf("return true;") < back.indexOf("openPauseMenu();"),
    "Ready exit must return before every pause and workout-navigation branch"
  );
});

test("Ready copy, order, version, and redacted pairing status stay compact in EN UK RU", async () => {
  const [view, manifest] = await Promise.all([
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/manifest.xml", "utf8")
  ]);
  const version = manifest.match(/version="(\d+\.\d+\.\d+)"/)?.[1];
  assert.ok(version);

  const ready = section(view, "(:fullLegacyState)\n    function drawReady(dc, w, h)", "(:compactLegacyState)\n    function drawReady(dc, w, h)");
  assert.ok(ready.indexOf("readyPrimaryText()") < ready.indexOf('"SYNC PLAN"'));
  assert.ok(ready.indexOf('"SYNC PLAN"') < ready.indexOf('"SETTINGS"'));
  const compactReady = section(view, "(:compactLegacyState)\n    function drawReady(dc, w, h)", "(:fullLegacyState)\n    function drawReadyRow(");
  assert.ok(compactReady.indexOf("readyPrimaryText()") < compactReady.indexOf('"SYNC"'));
  assert.ok(compactReady.indexOf('"SYNC"') < compactReady.indexOf('"SETTINGS"'));
  assert.match(view, /"START WORKOUT", "ПОЧАТИ ТРЕН\.", "НАЧАТЬ ТРЕН\."/);
  assert.match(view, /"SYNC PLAN", "СИНХ\. ПЛАН", "СИНХ\. ПЛАН"/);
  assert.match(view, /"PAIRED", "ПРИВ'ЯЗАНО", "СОПРЯЖЕНО"/);
  assert.match(view, /"NOT PAIRED", "НЕ ПРИВ'ЯЗАНО", "НЕ СОПРЯЖЕНО"/);
  const binding = section(view, "function readyBindingText()", "function readyPrimaryText()");
  assert.match(binding, /GymStore\.hasAccountBinding\(\)/);
  assert.doesNotMatch(binding, /accountBinding|deviceBinding|CloudDeviceToken/);
  assert.match(compactReady, /"GYMAPP READY", "GYMAPP ГОТОВ", "GYMAPP ГОТОВО"/);
});
