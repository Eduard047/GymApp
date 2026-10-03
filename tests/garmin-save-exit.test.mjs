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

const annotatedFunction = (source, marker, name) => {
  const method = new RegExp(`\\(:[^)]*\\b${marker}\\b[^)]*\\)\\s+function ${name}\\([^)]*\\)\\s*\\{`);
  const match = method.exec(source);
  assert.ok(match, `Missing ${marker} function ${name} variant`);
  const endIndex = source.indexOf("\n    function ", match.index + match[0].length);
  assert.notEqual(endIndex, -1, `Missing end boundary for ${marker} function ${name}`);
  return source.slice(match.index, endIndex);
};

test("Garmin saves FIT before making account-bound sets sendable while unbound FIT stays independent", async () => {
  const [view, session, store] = await Promise.all([
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8")
  ]);

  const finishWorkout = section(
    view,
    "function finishWorkoutMessage(message)",
    "function buildFinishWorkoutMessage()"
  );
  assert.match(
    finishWorkout,
    /if \(!GymStore\.hasAccountBinding\(\)\)[\s\S]*return saveStage != 5;/
  );
  assert.match(view, /finishWorkoutMessage\(buildFinishWorkoutMessage\(\)\)/);
  assert.match(view, /function buildFinishWorkoutMessage\(\) \{\s*return GymStore\.preparedWorkoutMessage\(\)/);
  assert.ok(
    finishWorkout.indexOf("!GymStore.hasAccountBinding()") <
      finishWorkout.indexOf("GymStore.queueWorkout(message)"),
    "Unbound workouts must never reach the account-scoped queue boundary"
  );
  assert.doesNotMatch(finishWorkout, /GymStore\.canQueueWorkout\(message\)/,
    "same-id recovery must reach queueWorkout even when the queue is full");
  assert.match(finishWorkout, /GymStore\.queueWorkout\(message\)/);
  assert.match(
    finishWorkout,
    /GymStore\.queueWorkout\(message\)[\s\S]*GymStore\.pendingMessage\(\)[\s\S]*GymComm\.send\(queued, method\(:onWorkoutSent\)\)/
  );
  assert.doesNotMatch(finishWorkout, /GymComm\.send\(message,/);

  assert.match(store, /maxPendingWorkouts = 8/);
  assert.match(store, /maxPendingNameBytes = 12000/);
  assert.match(store, /maxEstimatedStoreBytes = 24000/);
  const canQueueWorkout = section(
    store,
    "static function canQueueWorkout(message)",
    "static function isValidWorkoutMessage(message)"
  );
  assert.match(canQueueWorkout, /pendingCount\(\) >= maxPendingWorkouts/);
  assert.match(canQueueWorkout, /totalNameBytes <= maxPendingNameBytes/);

  const queue = [];
  const canAppend = () => queue.length < 8;
  for (let index = 1; index <= 8; index += 1) {
    assert.equal(canAppend(), true, `offline workout P${index} should fit the count bound`);
    queue.push({ requestId: `P${index}` });
  }
  assert.equal(queue[0].requestId, "P1", "new workouts must not overtake durable P1");
  assert.equal(queue[2].requestId, "P3", "an ordinary third offline workout must remain queueable");
  assert.equal(canAppend(), false, "the bounded ninth workout must apply backpressure without eviction");

  const saveAndExit = section(view, "function saveAndExit()", "function onUpdate(");
  const richSaveAndExit = annotatedFunction(view, "richRecovery", "saveAndExit");
  const fr55SaveAndExit = annotatedFunction(view, "fr55Memory", "saveAndExit");
  const fr55BuildMessage = annotatedFunction(view, "fr55Memory", "buildFinishWorkoutMessage");
  const compactUnboundFreeFinish = annotatedFunction(
    view, "compactWorkoutMode96", "canFinishUnboundFreeWithoutStoreClear");
  const richUnboundFreeFinish = annotatedFunction(
    view, "richWorkoutMode", "canFinishUnboundFreeWithoutStoreClear");
  assert.match(saveAndExit, /GymStore\.prepareWorkoutCommit\(\)/);
  assert.match(
    saveAndExit,
    /if \(!fitAlreadySaved && !GymSession\.stopAndSave\(\)\)[\s\S]*GymStore\.status = GymStatus\.FIT_FAIL;[\s\S]*return;/
  );
  assert.match(
    richSaveAndExit,
    /if \(needsPhoneSync && GymStore\.preparedWorkoutNeedsFitDecision\(\) &&\s*GymSession\.fitOutcomeUnknownAfterRestart\(\)\) \{\s*handleFitRecoveryAction\(\);\s*return;/
  );
  assert.match(
    fr55SaveAndExit,
    /var fitUnknown = needsPhoneSync &&\s*!GymStore\.preparedWorkoutFitSaved\(\) &&\s*GymSession\.fitOutcomeUnknownAfterRestart\(\);/
  );
  assert.match(
    fr55SaveAndExit,
    /if \(!fitUnknown && !fitAlreadySaved && !GymSession\.stopAndSave\(\)\)/,
    "unknown FIT state must not trigger another stop/save attempt"
  );
  assert.match(
    fr55SaveAndExit,
    /if \(needsPhoneSync && !fitUnknown &&[\s\S]*?GymStore\.markPreparedWorkoutFitSaved\(\)/,
    "FR55 must never mark an unknown FIT outcome as saved"
  );
  assert.match(fr55SaveAndExit, /saveSetsOnly = fitUnknown;\s*saveStage = needsPhoneSync \? 1 : 4/);
  assert.match(
    fr55BuildMessage,
    /return GymStore\.preparedWorkoutFitSaved\(\) \?\s*GymStore\.preparedWorkoutMessage\(\) :\s*GymStore\.preparedWorkoutSetsOnlyMessage\(\);/
  );
  assert.match(saveAndExit, /GymStore\.markPreparedWorkoutFitSaved\(\)[\s\S]*saveStage = needsPhoneSync \? 1 : 4/);
  const completion = section(view, "function continueSaving()", "function onUpdate(");
  assert.match(completion, /saveStage == 1[\s\S]*saveMessage = buildFinishWorkoutMessage\(\);[\s\S]*saveStage = saveMessage != null \? 5 : 0/);
  assert.match(completion, /saveStage == 5[\s\S]*saveStage = finishWorkoutMessage\(saveMessage\) \? 2 : 0;\s*saveMessage = null/);
  assert.match(compactUnboundFreeFinish,
    /return GymWorkoutMode\.isFree\(\) && !GymStore\.hasAccountBinding\(\);/,
    "only a 96 KiB unbound FREE session may finish without owned-store cleanup");
  assert.match(richUnboundFreeFinish, /return false;/,
    "the rich path always requires the normal active-workout clear");
  assert.match(completion,
    /else if \(saveStage == 3 \|\| saveStage == 4\)[\s\S]*if \(canFinishUnboundFreeWithoutStoreClear\(\) \|\|\s*GymStore\.clearActiveWorkout\(\)\) \{[\s\S]*?exitAfterSave\(\);\s*\}\s*\} else \{\s*GymStore\.status = GymStatus\.SAVE_FAIL;/,
    "bound workouts exit only after active-state cleanup succeeds; safe unbound FREE may skip that owned-key clear");
  assert.match(completion,
    /clearActiveWorkout\(\)\) \{[\s\S]*?flushPending\(\);[\s\S]*?saveStage = 7;[\s\S]*?\} else \{\s*exitAfterSave\(\);/,
    "queued sets are sent only after the active-state clear, and the process then waits (stage 7) or exits");
  assert.match(view, /function exitAfterSave\(\) \{\s*Attention\.vibrate\([^;]*\);\s*System\.exit\(\);\s*\}/,
    "every save exit vibrates and exits through one helper");
  assert.match(completion, /saveStage == 2[\s\S]*GymStore\.recoverQueuedWorkout\(\) \? 3 : 0/);
  assert.match(completion, /else \{\s*GymStore\.status = GymStatus\.SAVE_FAIL/);
  const saveTicks = [...view.matchAll(/\(:([^)]*)\)\s+function tick\(\) \{/g)];
  const tickProfiles = new Set(saveTicks.flatMap((match) =>
    match[1].split(",").map((profile) => profile.trim().replace(/^:/, ""))));
  for (const profile of ["fullLegacyState", "compactLegacyState", "richWorkoutMode", "compactWorkoutMode96"]) {
    assert.ok(tickProfiles.has(profile), `${profile} keeps its own tick path`);
  }
  assert.equal(saveTicks.length, 3,
    "full, compact/rich, and 96 KiB profiles keep separate tick paths");
  for (const tickStart of saveTicks) {
    const nextMethod = view.indexOf("\n    function ", tickStart.index + tickStart[0].length);
    assert.notEqual(nextMethod, -1, "each tick path has a bounded method body");
    const tick = view.slice(tickStart.index, nextMethod);
    assert.match(tick, /if \(saveStage > 0\) \{\s*continueSaving\(\);\s*return;/,
      "each profile yields before mailbox work while FIT, queue or cleanup is pending");
  }
  assert.equal((saveAndExit.match(/function saveAndExit\(\) \{\s*if \(saveStage > 0\)/g) || []).length, 3,
    "rich, compact and FR55 save paths ignore repeated Save presses while completion is pending");
  assert.match(view, /function inputBlocked\(\) \{[\s\S]*?return view\.saveStage != 0;\s*\}/);
  assert.equal(
    (view.match(/function onBack\(\) \{\s*if \(inputBlocked\(\)\) \{ return true; \}/g) || []).length,
    3,
    "rich, compact and FR55 navigation block Back while any serialized action or save phase is pending"
  );
  assert.doesNotMatch(
    saveAndExit,
    /GymStore\.sets\.size\(\) > 0 && !GymStore\.clearActiveWorkout\(\)/,
    "a zero-set FIT save must clear its runtime checkpoint too"
  );
  assert.match(saveAndExit, /if \(GymLocalWorkout\.finish\(\)\) \{\s*System\.exit\(\)/);
  assert.ok(
    saveAndExit.indexOf("GymSession.stopAndSave()") < saveAndExit.indexOf("System.exit()", saveAndExit.indexOf("var fitAlreadySaved")),
    "The app must not exit before Garmin confirms the FIT save"
  );
  assert.ok(
    saveAndExit.indexOf("GymSession.stopAndSave()") < saveAndExit.indexOf("finishWorkoutMessage(saveMessage)"),
    "GymApp sync must not become sendable until Garmin confirms the FIT save"
  );
  assert.ok(
    saveAndExit.indexOf("GymStore.prepareWorkoutCommit()") <
      saveAndExit.indexOf("GymSession.stopAndSave()"),
    "the stable owner/device/request marker must be durable before crossing the FIT boundary"
  );

  const stopAndSave = section(session, "static function stopAndSave()", "static function discard()");
  assert.match(stopAndSave, /session\.isRecording\(\) && !session\.stop\(\)/);
  assert.match(stopAndSave, /saved = session\.save\(\)/);
  assert.match(stopAndSave, /if \(!saved\)[\s\S]*return false;/);
  assert.ok(
    stopAndSave.indexOf("if (!saved)") < stopAndSave.indexOf("session = null"),
    "A failed FIT save must retain the session so the user can retry"
  );
  assert.match(stopAndSave, /fitSaved = true;[\s\S]*return true;/);
  assert.match(stopAndSave, /session == null[\s\S]*return !recording && fitSaved/);

  const clearActiveWorkout = section(
    store,
    "static function clearActiveWorkout()",
    "static function restSeconds()"
  );
  assert.match(clearActiveWorkout, /persistEmptyActiveWorkoutSnapshot\(\)/);
  assert.ok(
    clearActiveWorkout.indexOf("persistEmptyActiveWorkoutSnapshot()") <
      clearActiveWorkout.indexOf("sets = []"),
    "the authoritative empty snapshot must commit before active globals are cleared"
  );
  assert.match(clearActiveWorkout, /var cleared = compatibilitySaved \|\| atomicallyCleared[\s\S]*GymWorkoutMode\.clear\(\)[\s\S]*return cleared/);
});

test("Garmin partial workouts declare plan progress and drain one queued workout per ack", async () => {
  const [store, app] = await Promise.all([
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/GymApp.mc", "utf8")
  ]);

  const workoutMessage = section(
    store,
    "static function workoutMessage(requestId)",
    "static function applyPhoneSync("
  );
  assert.match(workoutMessage, /if \(!freeMode && context\[7\] > 0\)/);
  assert.match(workoutMessage, /var target = !freeMode \? plan\.size\(\) : 0/);
  assert.match(workoutMessage, /context\[7\] < context\[9\] \? context\[9\] : context\[7\]/);
  assert.match(workoutMessage, /target > 0 \? completedPlannedSetCount\(\) : 0, sets\.size\(\)/);
  assert.match(workoutMessage, /message\["plannedSetCount"\] = context\[7\] < context\[9\] \? context\[9\] : context\[7\]/);
  assert.match(workoutMessage, /message\["plannedTargetSetCount"\] = context\[7\]/);
  assert.match(
    workoutMessage,
    /message\["completedPlannedSetCount"\] = context\[8\]/
  );

  const oldPhoneAccepts = ({ plannedSetCount, sets }) => plannedSetCount >= sets.length;
  const extraSetPayload = {
    plannedSetCount: 4,
    plannedTargetSetCount: 3,
    completedPlannedSetCount: 3,
    sets: [{}, {}, {}, {}]
  };
  assert.equal(oldPhoneAccepts(extraSetPayload), true);
  assert.equal(extraSetPayload.plannedTargetSetCount, 3);
  assert.equal(extraSetPayload.completedPlannedSetCount, 3);

  const ackHandler = section(app, "function handlePhonePayload(", "function sendSyncAck(");
  assert.match(
    ackHandler,
    /removePendingByRequestId\(ackRequestId\)[\s\S]*sendNextPendingWorkout\(\)/
  );
  const drain = section(
    app,
    "function sendNextPendingWorkout()",
    "function onPendingWorkoutSentAfterSync("
  );
  assert.match(drain, /GymStore\.pendingCount\(\) == 0/);
  assert.match(drain, /GymStore\.pendingMessage\(\)[\s\S]*GymComm\.send\(message/);
  assert.doesNotMatch(drain, /for \s*\(|while \s*\(/);
});
