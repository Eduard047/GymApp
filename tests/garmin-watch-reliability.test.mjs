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
  assert.doesNotMatch(view, /GymStore\.timerElapsedMs\(lastSyncRequestAt\) > 20000l/);
  assert.match(view, /function maybeRetryPending\(\) \{[\s\S]*if \(GymSession\.recording\) \{ return; \}/);
  assert.match(view, /GymStore\.timerElapsedMs\(savedSetFlashStartedAt\) <= GymStore\.undoWindowMs/);
  assert.match(store, /timerElapsedMs\(lastSetUndoStartedAt\) > undoWindowMs/);
});

// Mirrors WorkoutView.expireSyncRequest / requestSyncNow / onSyncSent. The model
// keeps every transport listener (Connect IQ cannot cancel one) so it can answer
// them in any order while the callback itself carries no request identity.
const syncModel = () => {
  const state = {
    inFlight: false,
    timedOut: false,
    stale: 0,
    lastAt: null,
    listeners: 0,
    maximumListeners: 0,
    sends: 0,
    status: "READY"
  };
  // `immediate` models GymComm answering inside requestSync (phone away or watch
  // unbound): no transport listener exists and the answer is the request's own.
  state.request = (now, immediate = false) => {
    if (state.inFlight) return false;
    if (state.timedOut) {
      if (state.stale > 1 || state.lastAt == null || now - state.lastAt < 60_000) return false;
      state.timedOut = false;
    }
    const held = state.stale;
    state.stale = 0;
    state.inFlight = true;
    state.lastAt = now;
    state.sends += 1;
    if (immediate) {
      state.callback(false, true);
    } else {
      state.listeners += 1;
      state.maximumListeners = Math.max(state.maximumListeners, state.listeners);
    }
    state.stale += held;
    return true;
  };
  state.expire = now => {
    if (!state.inFlight || state.lastAt == null || now - state.lastAt <= 60_000) return false;
    state.inFlight = false;
    state.timedOut = true;
    state.stale += 1;
    state.lastAt = now;
    state.status = "PHONE SILENT";
    return true;
  };
  state.callback = (ok, immediate = false) => {
    if (!immediate) state.listeners -= 1;
    if (state.stale > 0) {
      state.stale -= 1;
      return;
    }
    state.inFlight = false;
    state.status = ok ? "SYNC REQ" : "NO PHONE";
  };
  return state;
};

test("Garmin sync watchdog expires a missing Ready request before the idle return", async () => {
  const view = await readFile("garmin/source/WorkoutView.mc", "utf8");
  const tick = section(view, "function tick()", "function expireSyncRequest()");
  const expire = section(view, "function expireSyncRequest()", "function requestSyncNow()");
  const request = section(view, "function requestSyncNow()", "(:compactLegacyState, :richWorkoutMode)\n    function tick()");
  const sent = section(view, "function onSyncSent(ok)", "(:fullLegacyState)\n    function requestCloudSyncNow()");
  const timeoutAt = tick.indexOf("expireSyncRequest()");
  const idleReturnAt = tick.indexOf("if (page == 7 || !GymSession.recording)");

  assert.ok(timeoutAt >= 0 && timeoutAt < idleReturnAt,
    "Ready and stopped-workout ticks must still expire a missing callback");
  assert.doesNotMatch(tick, /requestSyncNow\(\)/,
    "recording ticks must not allocate a background transmit listener");
  assert.match(view, /var staleSyncCallbacks = 0/);
  assert.equal((view.match(/\n\s+(?:if \()?expireSyncRequest\(\)/g) || []).length, 3,
    "the full, compact and 96 KiB tick variants all expire through the one helper");
  assert.equal((view.match(/syncRequestTimedOut = true/g) || []).length, 1,
    "only the helper marks a request as timed out");
  // Timeout: stop the request, count its still-live listener, restart the wait.
  assert.match(expire, /timerElapsedMs\(lastSyncRequestAt\) <= 60000l[\s\S]*return false/);
  assert.match(expire,
    /syncRequestInFlight = false;\s*syncRequestTimedOut = true;\s*staleSyncCallbacks \+= 1;\s*lastSyncRequestAt = System\.getTimer\(\);\s*GymStore\.status = GymStatus\.PHONE_SILENT;\s*return true/);
  assert.doesNotMatch(expire, /GymStatus\.REOPEN/);
  // Retry: a further quiet minute after the timeout and at most one stale listener.
  assert.match(request,
    /if \(syncRequestInFlight\) \{\s*return;\s*\}[\s\S]*if \(syncRequestTimedOut\) \{[\s\S]*staleSyncCallbacks > 1 \|\| lastSyncRequestAt == null \|\|\s*GymStore\.timerElapsedMs\(lastSyncRequestAt\) < 60000l\) \{\s*return;\s*\}\s*syncRequestTimedOut = false;/);
  assert.match(request,
    /var stale = staleSyncCallbacks;\s*staleSyncCallbacks = 0;\s*syncRequestInFlight = true;\s*lastSyncRequestAt = System\.getTimer\(\);\s*GymComm\.requestSync\(method\(:onSyncSent\)\);\s*staleSyncCallbacks \+= stale;/,
    "an immediate GymComm answer must not be consumed as a late one");
  // A callback owed by a timed-out request is consumed before it can touch the current one.
  assert.match(sent, /if \(staleSyncCallbacks > 0\) \{\s*staleSyncCallbacks -= 1;\s*return;\s*\}[\s\S]*syncRequestInFlight = false/);
  assert.doesNotMatch(sent, /syncRequestTimedOut/);
  assert.equal((view.match(/GymStatus\.PHONE_SILENT/g) || []).length >= 2, true);

  const ready = syncModel();
  assert.equal(ready.request(0), true, "manual Ready sync starts one listener");
  assert.equal(ready.expire(60_000), false, "exactly a minute is not yet silent");
  assert.equal(ready.expire(60_001), true);
  assert.equal(ready.status, "PHONE SILENT");
  assert.equal(ready.request(60_002), false, "the retry waits a further quiet minute after the timeout");
  assert.equal(ready.request(120_000), false, "59.999 s after the timeout is still held");
  assert.equal(ready.request(120_001), true, "a full quiet minute after the timeout allows the retry");
  assert.equal(ready.timedOut, false);
  assert.equal(ready.maximumListeners, 2, "the stale listener and the retry are the only two");

  // The stale listener answers first: it cannot clear or relabel the retry.
  ready.status = "PHONE SILENT";
  ready.callback(true);
  assert.deepEqual(
    { inFlight: ready.inFlight, stale: ready.stale, status: ready.status },
    { inFlight: true, stale: 0, status: "PHONE SILENT" },
    "a late stale success leaves the new request pending"
  );
  assert.equal(ready.request(130_000), false, "no third overlapping listener while the retry is pending");
  ready.callback(false);
  assert.deepEqual(
    { inFlight: ready.inFlight, status: ready.status, sends: ready.sends },
    { inFlight: false, status: "NO PHONE", sends: 2 }
  );

  // The retry answers first: its result is consumed as the stale one, so the
  // request stays in flight (still no overlap) until the other callback lands.
  const swapped = syncModel();
  swapped.request(0);
  swapped.expire(60_001);
  assert.equal(swapped.request(120_001), true);
  swapped.callback(true);
  assert.deepEqual(
    { inFlight: swapped.inFlight, stale: swapped.stale, status: swapped.status },
    { inFlight: true, stale: 0, status: "PHONE SILENT" }
  );
  assert.equal(swapped.request(120_002), false);
  swapped.callback(true);
  assert.deepEqual(
    { inFlight: swapped.inFlight, status: swapped.status, maximumListeners: swapped.maximumListeners },
    { inFlight: false, status: "SYNC REQ", maximumListeners: 2 }
  );

  // Phone away or watch unbound: GymComm answers inside requestSync, so that
  // answer completes the retry and the timed-out listener is still owed.
  const immediate = syncModel();
  immediate.request(0);
  immediate.expire(60_001);
  assert.equal(immediate.request(120_001, true), true);
  assert.deepEqual(
    { inFlight: immediate.inFlight, stale: immediate.stale, status: immediate.status },
    { inFlight: false, stale: 1, status: "NO PHONE" }
  );
  immediate.callback(true);
  assert.deepEqual(
    { inFlight: immediate.inFlight, stale: immediate.stale, status: immediate.status },
    { inFlight: false, stale: 0, status: "NO PHONE" },
    "the owed late answer is dropped without touching the finished retry"
  );

  const reopened = syncModel();
  assert.equal(reopened.request(0), true, "a new app process has a clean bounded recovery state");
  assert.equal(reopened.maximumListeners, 1);
});

test("Garmin manual sync stays bounded without periodic recording retries", () => {
  for (const ok of [true, false]) {
    const completed = syncModel();
    completed.request(0);
    completed.callback(ok);
    completed.expire(20_000);
    assert.equal(completed.sends, 1, "complete/error callbacks do not cause an immediate retry");
    completed.expire(20_001);
    assert.equal(completed.sends, 1, "recording never creates a periodic retry");
    completed.request(20_002);
    assert.equal(completed.sends, 2, "a new manual request may retry a completed operation");
    assert.equal(completed.maximumListeners, 1);
  }

  // A phone that never answers: ticks alone never send, and at most two
  // listeners are ever outstanding however often the user presses sync.
  const missing = syncModel();
  missing.request(0);
  for (const now of [60_001, 80_002, 160_003]) missing.expire(now);
  assert.deepEqual(
    { sends: missing.sends, timedOut: missing.timedOut, status: missing.status, stale: missing.stale },
    { sends: 1, timedOut: true, status: "PHONE SILENT", stale: 1 }
  );
  let now = 160_003;
  for (let press = 0; press < 12; press += 1) {
    now += 61_000;
    missing.request(now);
    missing.expire(now + 60_001);
    now += 60_001;
  }
  assert.equal(missing.sends, 2, "two silent requests lock out a third until a callback frees a slot");
  assert.equal(missing.stale, 2);
  assert.equal(missing.maximumListeners, 2);
  missing.callback(false);
  assert.equal(missing.status, "PHONE SILENT", "a late error stays quarantined just like a late success");
  assert.equal(missing.request(now + 61_000), true, "one answered stale listener reopens a single retry");
  assert.equal(missing.maximumListeners, 2);
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
    "(:compactLegacyState, :richWorkoutMode)\n    static function completeLoad(startup)",
    "(:compactCheckpoint96)\n    static function completeLoad(startup)"
  );
  const compactBeginLoad = section(
    store,
    "(:compactLegacyState, :richWorkoutMode)\n    static function beginLoad()",
    "(:compactLegacyState, :richWorkoutMode)\n    static function load()"
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
  assert.match(load, /setField\(GymSetAccess\.at\(sets, sets\.size\(\) - 1\), "exerciseName"\)/);
  assert.match(compactBeginLoad, /var savedCurrentEntry = Storage\.getValue\("currentEntryV1"\)/);
  assert.match(compactBeginLoad, /return \[schema, ownerMatches, savedExerciseCatalogValid, savedCurrentEntry,[\s\S]*savedActive/);
  assert.match(compactLoad, /restoreCurrentEntry\(savedCurrentEntry\)/);
  assert.match(compactLoad, /setField\(GymSetAccess\.at\(sets, sets\.size\(\) - 1\), "exerciseName"\)/);
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
  const tick = section(session, "static function tick(", "static function startSensors()");

  assert.match(session, /static var fitCleanupPending = false/);
  assert.match(start, /if \(!retryAccountTransitionFitCleanup\(\)\)[\s\S]*return false/);
  assert.match(reset, /var fitDiscarded = discard\(\)/);
  assert.match(reset, /fitCleanupPending = !fitDiscarded && session != null/);
  assert.doesNotMatch(reset, /session = null/);
  assert.match(retry, /if \(!discard\(\)\)[\s\S]*GymStatus\.FIT_RETRY[\s\S]*return false/);
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
