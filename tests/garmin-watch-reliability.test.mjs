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

test("Garmin cloud sync is explicit on Ready and accepts only the queue head ACK", async () => {
  const [store, view] = await Promise.all([
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);

  const readySync = section(view, "function syncFromReady()", "function finishWorkout()");
  assert.match(readySync, /requestSyncNow\(\)/);
  assert.match(readySync, /flushPending\(\)/);
  assert.match(readySync, /GymComm\.hasCloudDeviceToken\(\)[\s\S]*requestCloudSyncNow\(\)/);
  assert.doesNotMatch(view, /scheduleCloudSyncOnOpen|requestCloudSyncOnOpen|cloudAuto/);

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
  const explicitStart = section(view, "function startOrResumeWorkout()", "function syncFromReady()");

  assert.match(start, /if \(session\.start\(\)\)[\s\S]*else \{[\s\S]*failStartAndCleanup\(\)/);
  assert.match(start, /catch \(ex\) \{[\s\S]*failStartAndCleanup\(\)/);
  assert.match(start, /static function failStartAndCleanup\(\)[\s\S]*cleaned = discard\(\)/);
  assert.match(start, /fitCleanupPending = !cleaned && session != null/);
  assert.match(pause, /!session\.stop\(\)[\s\S]*return false/);
  assert.ok(pause.indexOf("session.stop()") < pause.indexOf("paused = true"));
  assert.match(resume, /!session\.start\(\)[\s\S]*return false/);
  assert.ok(resume.indexOf("session.start()") < resume.indexOf("paused = false"));
  assert.match(discard, /discarded = session\.discard\(\)[\s\S]*if \(!discarded\)[\s\S]*return false/);
  assert.match(onShow, /page = 7/);
  assert.doesNotMatch(onShow, /GymSession\.(?:start|resume|startSensors)\(/);
  assert.match(explicitStart, /GymSession\.recording[\s\S]*GymSession\.paused[\s\S]*GymSession\.resume\(\)/);
  assert.match(explicitStart, /else \{[\s\S]*started = GymSession\.start\(\)/);
  assert.ok(
    explicitStart.indexOf("if (!started)") < explicitStart.indexOf("page = 0"),
    "failed FIT start must leave the Ready screen inactive"
  );
});

test("Garmin account transition retains and retries a FIT session that could not be discarded", async () => {
  const session = await readFile("garmin/source/GymSession.mc", "utf8");
  const start = section(session, "static function start()", "static function pause()");
  const reset = section(
    session,
    "static function resetForAccountTransition()",
    "static function retryAccountTransitionFitCleanup()"
  );
  const retry = section(
    session,
    "static function retryAccountTransitionFitCleanup()",
    "static function createFitFields()"
  );
  const tick = section(session, "static function tick()", "static function startSensors()");

  assert.match(session, /static var fitCleanupPending = false/);
  assert.match(start, /if \(!retryAccountTransitionFitCleanup\(\)\)[\s\S]*return false/);
  assert.match(reset, /var fitDiscarded = discard\(\)/);
  assert.match(reset, /fitCleanupPending = !fitDiscarded && session != null/);
  assert.doesNotMatch(reset, /session = null/);
  assert.match(retry, /if \(!discard\(\)\)[\s\S]*"FIT RETRY"[\s\S]*return false/);
  assert.match(retry, /fitCleanupPending = false;[\s\S]*return true/);
  assert.match(
    tick,
    /if \(fitCleanupPending\)[\s\S]*retryAccountTransitionFitCleanup\(\);[\s\S]*return;/
  );

  const state = {
    session: true,
    cleanupPending: false,
    recording: true
  };
  const resetWithDiscardResult = (discarded) => {
    state.cleanupPending = !discarded && state.session;
    state.recording = false;
  };
  const retryWithDiscardResult = (discarded) => {
    if (!state.cleanupPending) return true;
    if (!discarded) return false;
    state.session = false;
    state.cleanupPending = false;
    return true;
  };

  resetWithDiscardResult(false);
  assert.deepEqual(state, {
    session: true,
    cleanupPending: true,
    recording: false
  });
  assert.equal(retryWithDiscardResult(false), false);
  assert.equal(state.session, true, "a transient failure must keep the native session handle");
  assert.equal(retryWithDiscardResult(true), true);
  assert.deepEqual(state, {
    session: false,
    cleanupPending: false,
    recording: false
  });
});
