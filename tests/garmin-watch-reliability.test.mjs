import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const UINT32 = 4_294_967_296;
const elapsedTimerMs = (now, startedAt) => {
  const elapsed = now - startedAt;
  return elapsed < 0 ? elapsed + UINT32 : elapsed;
};

const section = (source, start, end) => {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(startIndex, -1, `Missing start anchor: ${start}`);
  assert.notEqual(endIndex, -1, `Missing end anchor: ${end}`);
  return source.slice(startIndex, endIndex);
};

test("Garmin short timers survive the signed System.getTimer rollover", async () => {
  const [store, session, view] = await Promise.all([
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const beforeRollover = 2_147_483_600;
  const afterRollover = -2_147_483_596;
  assert.equal(elapsedTimerMs(afterRollover, beforeRollover), 100);
  assert.equal(90_000 - elapsedTimerMs(afterRollover, beforeRollover), 89_900);
  assert.equal(elapsedTimerMs(afterRollover, beforeRollover) <= 5_000, true);
  assert.equal(elapsedTimerMs(afterRollover, beforeRollover) <= 20_000, true);

  const timerHelper = section(store, "static function timerElapsedMs(", "static function workoutMessage(");
  assert.match(timerHelper, /System\.getTimer\(\)\.toLong\(\) - startedAt\.toLong\(\)/);
  assert.match(timerHelper, /elapsed < 0l \? elapsed \+ 4294967296l : elapsed/);
  assert.match(session, /lastMotionTimerMs = null/);
  assert.match(session, /GymStore\.timerElapsedMs\(lastMotionTimerMs\)/);
  assert.match(view, /GymStore\.timerElapsedMs\(lastSyncRequestAt\) > 20000l/);
  assert.match(view, /GymStore\.timerElapsedMs\(savedSetFlashStartedAt\) <= GymStore\.undoWindowMs/);
  assert.match(store, /timerElapsedMs\(lastSetUndoStartedAt\) > undoWindowMs/);
});

test("Garmin retries cloud sync after the throttle and accepts only the queue head ACK", async () => {
  const [store, view] = await Promise.all([
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const cloudRequest = section(view, "function requestCloudSyncOnOpen()", "function onCloudPlanFetched(");
  assert.match(cloudRequest, /sinceLastCloudRequest < 8000l/);
  assert.match(cloudRequest, /scheduleCloudSyncOnOpen\(\(8001l - sinceLastCloudRequest\)\.toNumber\(\)\)/);
  assert.match(view, /scheduleCloudSyncOnOpen\(8000\)/);

  const removePending = section(
    store,
    "static function removePendingByRequestId(requestId)",
    "static function rotatePairingGenerationForPending("
  );
  assert.match(removePending, /var item = pending\[0\]/);
  assert.doesNotMatch(removePending, /for \(/);
  assert.ok(
    removePending.indexOf("itemRequestId.toString().equals(requestText)") <
      removePending.indexOf("pending.remove(item)"),
    "an out-of-order delayed ACK must not delete a newer queued workout"
  );
});

test("Garmin restart restores the selected exercise only for the matching active snapshot", async () => {
  const store = await readFile("garmin/source/GymStore.mc", "utf8");
  const load = section(store, "static function load()", "static function save()");
  const save = section(store, "static function save()", "static function resetActiveWorkoutSnapshotState()");

  assert.match(save, /Storage\.setValue\("currentEntryV1", \[sets\.size\(\), currentExercise\(\)\]\)/);
  assert.match(load, /savedCurrentEntry\[0\] == sets\.size\(\)/);
  assert.match(load, /isValidExerciseName\(savedCurrentEntry\[1\]\)/);
  assert.match(load, /selectNextPlanSlotInGlobalOrder\(\)/);
  assert.match(load, /sets\[sets\.size\(\) - 1\]\.get\("exerciseName"\)/);
});

test("Garmin FIT pause, resume, discard, and startup fail without false UI success", async () => {
  const [session, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);
  const start = section(session, "static function start()", "static function pause()");
  const pause = section(session, "static function pause()", "static function resume()");
  const resume = section(session, "static function resume()", "static function stopAndSave()");
  const discard = section(session, "static function discard()", "static function resetForAccountTransition()");
  const onShow = section(view, "function onShow()", "function onHide()");

  assert.match(start, /if \(session\.start\(\)\)[\s\S]*else \{[\s\S]*session\.discard\(\)[\s\S]*return recording/);
  assert.match(pause, /!session\.stop\(\)[\s\S]*return false/);
  assert.ok(pause.indexOf("session.stop()") < pause.indexOf("paused = true"));
  assert.match(resume, /!session\.start\(\)[\s\S]*return false/);
  assert.ok(resume.indexOf("session.start()") < resume.indexOf("paused = false"));
  assert.match(discard, /discarded = session\.discard\(\)[\s\S]*if \(!discarded\)[\s\S]*return false/);
  assert.match(onShow, /!GymSession\.recording && !GymSession\.fitSaved/);
  assert.match(onShow, /else if \(GymSession\.recording && !GymSession\.paused\)[\s\S]*GymSession\.startSensors\(\)/);
});
