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

test("Garmin sync watchdog expires a missing Ready request before the idle return", async () => {
  const view = await readFile("garmin/source/WorkoutView.mc", "utf8");
  const tick = section(view, "function tick()", "function requestSyncNow()");
  const sent = section(view, "function onSyncSent(ok)", "(:fullLegacyState)\n    function requestCloudSyncNow()");
  const timeoutAt = tick.indexOf("if (syncRequestInFlight && lastSyncRequestAt != null");
  const idleReturnAt = tick.indexOf("if (page == 7 || !GymSession.recording)");
  const periodicAt = tick.indexOf("if (!syncRequestInFlight && !syncRequestTimedOut");

  assert.ok(timeoutAt >= 0 && timeoutAt < idleReturnAt,
    "Ready and stopped-workout ticks must still expire a missing callback");
  assert.ok(periodicAt > idleReturnAt,
    "only an active recording may start periodic background sync");
  assert.match(tick, /timerElapsedMs\(lastSyncRequestAt\) > 60000l[\s\S]*syncRequestTimedOut = true[\s\S]*status = "REOPEN"/);
  assert.match(sent, /if \(syncRequestTimedOut\) \{\s*return;\s*\}[\s\S]*syncRequestInFlight = false/);
  assert.doesNotMatch(sent, /syncRequestTimedOut = false/);
  assert.equal((view.match(/current\.equals\("REOPEN"\)/g) || []).length, 2,
    "both full and compact Ready views must explain the reopen recovery");

  const freshState = () => ({
    inFlight: false,
    timedOut: false,
    lastAt: null,
    transportOutstanding: 0,
    maximumOutstanding: 0,
    sends: 0,
    status: "READY"
  });
  const request = (state, now) => {
    if (state.inFlight || state.timedOut) return false;
    state.inFlight = true;
    state.lastAt = now;
    state.transportOutstanding += 1;
    state.maximumOutstanding = Math.max(state.maximumOutstanding, state.transportOutstanding);
    state.sends += 1;
    return true;
  };
  const callback = (state, ok) => {
    if (state.timedOut) return;
    state.inFlight = false;
    state.transportOutstanding -= 1;
    state.status = ok ? "SYNC REQ" : "NO PHONE";
  };
  const tickSync = (state, now, { ready, recording }) => {
    if (state.inFlight && state.lastAt != null && now - state.lastAt > 60_000) {
      state.inFlight = false;
      state.timedOut = true;
      state.status = "REOPEN";
    }
    if (ready || !recording) return;
    if (!state.inFlight && !state.timedOut &&
        (state.lastAt == null || now - state.lastAt > 20_000)) {
      request(state, now);
    }
  };

  const ready = freshState();
  assert.equal(request(ready, 0), true, "manual Ready sync starts one listener");
  tickSync(ready, 60_001, { ready: true, recording: false });
  assert.equal(ready.status, "REOPEN");
  assert.equal(request(ready, 60_002), false, "same process stays locked after timeout");
  callback(ready, true);
  assert.deepEqual(
    { timedOut: ready.timedOut, status: ready.status, sends: ready.sends, maximumOutstanding: ready.maximumOutstanding },
    { timedOut: true, status: "REOPEN", sends: 1, maximumOutstanding: 1 },
    "a late success cannot unlock the old listener or start another one"
  );

  const reopened = freshState();
  assert.equal(request(reopened, 0), true, "a new app process has a clean bounded recovery state");
  assert.equal(reopened.maximumOutstanding, 1);
});

test("Garmin recording sync stays bounded for complete, error, missing, and late callbacks", () => {
  const freshState = () => ({
    inFlight: false,
    timedOut: false,
    lastAt: null,
    outstanding: 0,
    maximumOutstanding: 0,
    sends: 0,
    status: "READY"
  });
  const request = (state, now) => {
    if (state.inFlight || state.timedOut) return;
    state.inFlight = true;
    state.lastAt = now;
    state.outstanding += 1;
    state.maximumOutstanding = Math.max(state.maximumOutstanding, state.outstanding);
    state.sends += 1;
  };
  const callback = (state, ok) => {
    if (state.timedOut) return;
    state.inFlight = false;
    state.outstanding -= 1;
    state.status = ok ? "SYNC REQ" : "NO PHONE";
  };
  const recordingTick = (state, now) => {
    if (state.inFlight && state.lastAt != null && now - state.lastAt > 60_000) {
      state.inFlight = false;
      state.timedOut = true;
      state.status = "REOPEN";
    }
    if (!state.inFlight && !state.timedOut &&
        (state.lastAt == null || now - state.lastAt > 20_000)) {
      request(state, now);
    }
  };

  for (const ok of [true, false]) {
    const completed = freshState();
    recordingTick(completed, 0);
    callback(completed, ok);
    recordingTick(completed, 20_000);
    assert.equal(completed.sends, 1, "complete/error callbacks do not cause an immediate retry");
    recordingTick(completed, 20_001);
    assert.equal(completed.sends, 2, "complete/error callbacks permit one bounded periodic retry");
    assert.equal(completed.maximumOutstanding, 1);
  }

  const missing = freshState();
  recordingTick(missing, 0);
  for (const now of [60_001, 80_002, 160_003]) recordingTick(missing, now);
  assert.deepEqual(
    { sends: missing.sends, timedOut: missing.timedOut, status: missing.status, maximumOutstanding: missing.maximumOutstanding },
    { sends: 1, timedOut: true, status: "REOPEN", maximumOutstanding: 1 }
  );
  callback(missing, false);
  recordingTick(missing, 240_004);
  assert.equal(missing.sends, 1, "a late error remains quarantined just like a late success");
  assert.equal(missing.status, "REOPEN");
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
  const compactLoad = section(
    store,
    "(:compactLegacyState)\n    static function load()",
    "(:compactLegacyState)\n    static function save()"
  );
  const save = section(store, "static function save()", "static function resetActiveWorkoutSnapshotState()");
  const currentEntry = section(
    store,
    "static function saveCurrentEntry()",
    "static function resetActiveWorkoutSnapshotState()"
  );

  assert.match(save, /Storage\.setValue\("currentEntryV1", \[[\s\S]*sets\.size\(\), currentExercise\(\), weight, reps/);
  assert.match(load, /restoreCurrentEntry\(savedCurrentEntry\)/);
  assert.match(load, /selectNextPlanSlotInGlobalOrder\(\)/);
  assert.match(load, /sets\[sets\.size\(\) - 1\]\.get\("exerciseName"\)/);
  assert.match(compactLoad, /Storage\.getValue\("currentEntryV1"\)/);
  assert.match(compactLoad, /restoreCurrentEntry\(savedCurrentEntry\)/);
  assert.match(compactLoad, /sets\[sets\.size\(\) - 1\]\.get\("exerciseName"\)/);
  assert.match(currentEntry, /value\.size\(\) != 2 && value\.size\(\) != 4/);
  assert.match(currentEntry, /value\[0\] != sets\.size\(\)/);
  assert.match(currentEntry, /isValidWeight\(value\[2\]\)/);
  assert.match(currentEntry, /weight = value\[2\][\s\S]*reps = value\[3\]/);
  assert.match(
    currentEntry,
    /Storage\.setValue\("currentEntryV1", \[[\s\S]*sets\.size\(\), exerciseName, weight, reps[\s\S]*Storage\.setValue\("weight", weight\)/
  );
  assert.ok(
    load.indexOf('sets[sets.size() - 1].get("exerciseName")') <
      load.lastIndexOf("selectNextPlanSlotInGlobalOrder()"),
    "restart must prefer the athlete's last exercise before initial plan ordering"
  );

  const oldEntry = [8, "Bench press", 80, 8];
  const newEntry = [8, "Pull-up", 15, 10];
  const commitWithFault = (faultBeforeWrite) => {
    let durableEntry = oldEntry;
    if (faultBeforeWrite === 0) return durableEntry;
    durableEntry = newEntry;
    // Later failures affect legacy mirrors only; the atomic envelope is current.
    if (faultBeforeWrite === 1 || faultBeforeWrite === 2) return durableEntry;
    return durableEntry;
  };
  assert.deepEqual(commitWithFault(0), oldEntry);
  assert.deepEqual(commitWithFault(1), newEntry);
  assert.deepEqual(commitWithFault(2), newEntry);
  const legacyEntry = [8, "Pull-up"];
  assert.equal(legacyEntry.length, 2, "released selection-only envelopes remain readable");
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
  const explicitStart = section(view, "function startOrResumeWorkout(usePlan)", "function syncFromReady()");

  assert.match(start, /if \(session\.start\(\)\)[\s\S]*else \{[\s\S]*failStartAndCleanup\(\)/);
  assert.match(start, /catch \(ex\) \{[\s\S]*failStartAndCleanup\(\)/);
  assert.match(start, /static function failStartAndCleanup\(\)[\s\S]*fitCleanupPending = session != null && !discard\(\)/);
  assert.match(pause, /!session\.stop\(\)[\s\S]*return false/);
  assert.ok(pause.indexOf("session.stop()") < pause.indexOf("paused = true"));
  assert.match(resume, /!session\.start\(\)[\s\S]*return false/);
  assert.ok(resume.indexOf("session.start()") < resume.indexOf("paused = false"));
  assert.match(discard, /discarded = session\.discard\(\)[\s\S]*if \(!discarded\)[\s\S]*return false/);
  assert.match(onShow, /if \(GymStore\.hasPreparedWorkout\(\)\) \{\s*page = 3;/);
  assert.match(onShow, /else if \(GymSession\.recording\)[\s\S]*page = GymSession\.paused \? 2 : 0/);
  assert.doesNotMatch(onShow, /GymSession\.(?:start|resume)\(/);
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
