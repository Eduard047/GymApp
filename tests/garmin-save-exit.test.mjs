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

test("Garmin FIT save and exit do not depend on phone sync or manually logged sets", async () => {
  const [view, session, store] = await Promise.all([
    readFile("garmin/source/WorkoutView.mc", "utf8"),
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8")
  ]);

  const finishWorkout = section(view, "function finishWorkout()", "function saveAndExit()");
  assert.match(
    finishWorkout,
    /GymStore\.sets\.size\(\) == 0 \|\| !GymStore\.hasAccountBinding\(\)[\s\S]*return true;/
  );
  assert.ok(
    finishWorkout.indexOf("!GymStore.hasAccountBinding()") <
      finishWorkout.indexOf("GymStore.workoutMessage()"),
    "Unbound workouts must never be converted into account-scoped sync messages"
  );
  assert.match(finishWorkout, /GymStore\.canQueueWorkout\(message\)/);
  assert.match(finishWorkout, /GymStore\.queueWorkout\(message\)/);

  const saveAndExit = section(view, "function saveAndExit()", "function onUpdate(");
  assert.match(saveAndExit, /if \(!finishWorkout\(\)\)[\s\S]*return;/);
  assert.match(
    saveAndExit,
    /if \(!GymSession\.stopAndSave\(\)\)[\s\S]*GymStore\.status = "FIT FAIL";[\s\S]*return;/
  );
  assert.match(
    saveAndExit,
    /GymStore\.sets\.size\(\) > 0 && !GymStore\.clearActiveWorkout\(\)[\s\S]*return;/
  );
  assert.ok(
    saveAndExit.indexOf("GymSession.stopAndSave()") < saveAndExit.indexOf("System.exit()"),
    "The app must not exit before Garmin confirms the FIT save"
  );

  const stopAndSave = section(session, "static function stopAndSave()", "static function discard()");
  assert.match(stopAndSave, /session\.isRecording\(\) && !session\.stop\(\)/);
  assert.match(stopAndSave, /saved = session\.save\(\)/);
  assert.match(stopAndSave, /if \(!saved\)[\s\S]*return false;/);
  assert.ok(
    stopAndSave.indexOf("if (!saved)") < stopAndSave.indexOf("session = null"),
    "A failed FIT save must retain the session so the user can retry"
  );
  assert.match(stopAndSave, /status = "SAVED";[\s\S]*return true;/);

  const clearActiveWorkout = section(
    store,
    "static function clearActiveWorkout()",
    "static function restSeconds()"
  );
  assert.match(clearActiveWorkout, /sets = \[\];[\s\S]*return save\(\);/);
});
