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

test("Garmin saves FIT before making account-bound sets sendable while unbound FIT stays independent", async () => {
  const [view, session, store] = await Promise.all([
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8")
  ]);

  const finishWorkout = section(
    view,
    "function finishWorkoutMessage(message)",
    "(:richRecovery)\n    function finishWorkout()"
  );
  assert.match(
    finishWorkout,
    /GymStore\.sets\.size\(\) == 0 \|\| !GymStore\.hasAccountBinding\(\)[\s\S]*return true;/
  );
  assert.match(view, /finishWorkoutMessage\(GymStore\.preparedWorkoutMessage\(\)\)/);
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
    /GymStore\.queueWorkout\(message\)[\s\S]*GymComm\.send\(GymStore\.pending\[0\], method\(:onWorkoutSent\)\)/
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
  assert.match(canQueueWorkout, /pending\.size\(\) >= maxPendingWorkouts/);
  assert.match(canQueueWorkout, /totalNameBytes > maxPendingNameBytes/);

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
  assert.match(saveAndExit, /GymStore\.prepareWorkoutCommit\(\)/);
  assert.match(
    saveAndExit,
    /if \(!fitAlreadySaved && !GymSession\.stopAndSave\(\)\)[\s\S]*GymStore\.status = "FIT FAIL";[\s\S]*return;/
  );
  assert.match(saveAndExit, /GymStore\.markPreparedWorkoutFitSaved\(\)[\s\S]*if \(!finishWorkout\(\)\)/);
  assert.match(
    saveAndExit,
    /if \(!GymStore\.clearActiveWorkout\(\)\)[\s\S]*return;/
  );
  assert.doesNotMatch(
    saveAndExit,
    /GymStore\.sets\.size\(\) > 0 && !GymStore\.clearActiveWorkout\(\)/,
    "a zero-set FIT save must clear its runtime checkpoint too"
  );
  assert.ok(
    saveAndExit.indexOf("GymSession.stopAndSave()") < saveAndExit.indexOf("System.exit()"),
    "The app must not exit before Garmin confirms the FIT save"
  );
  assert.ok(
    saveAndExit.indexOf("GymSession.stopAndSave()") < saveAndExit.indexOf("finishWorkout()"),
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
  assert.match(clearActiveWorkout, /return compatibilitySaved \|\| atomicallyCleared/);
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
  assert.match(workoutMessage, /if \(plan\.size\(\) > 0\)/);
  assert.match(workoutMessage, /var plannedTargetSetCount = plan\.size\(\)/);
  assert.match(workoutMessage, /var plannedSetCount = plannedTargetSetCount/);
  assert.match(workoutMessage, /plannedSetCount < setCopies\.size\(\)[\s\S]*plannedSetCount = setCopies\.size\(\)/);
  assert.match(workoutMessage, /message\.put\("plannedSetCount", plannedSetCount\)/);
  assert.match(workoutMessage, /message\.put\("plannedTargetSetCount", plannedTargetSetCount\)/);
  assert.match(
    workoutMessage,
    /message\.put\("completedPlannedSetCount", completedPlannedSetCount\(\)\)/
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
  assert.match(drain, /GymStore\.pending\.size\(\) == 0/);
  assert.match(drain, /GymComm\.send\(GymStore\.pending\[0\]/);
  assert.doesNotMatch(drain, /for \s*\(|while \s*\(/);
});
