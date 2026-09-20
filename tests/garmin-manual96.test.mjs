import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const annotatedBody = (source, annotation, signature) => {
  const expected = annotation.replace(/^:/, "");
  let signatureIndex = source.indexOf(signature);
  while (signatureIndex !== -1) {
    const annotationStart = source.lastIndexOf("(:", signatureIndex);
    const annotationEnd = source.indexOf(")", annotationStart);
    if (annotationStart !== -1 && annotationEnd !== -1 &&
        /^\s*$/.test(source.slice(annotationEnd + 1, signatureIndex))) {
      const annotations = source.slice(annotationStart + 2, annotationEnd)
        .split(",").map((value) => value.trim().replace(/^:/, ""));
      if (annotations.includes(expected)) {
        return bodyAt(source, source.indexOf("{", signatureIndex + signature.length));
      }
    }
    signatureIndex = source.indexOf(signature, signatureIndex + signature.length);
  }
  assert.fail(`Missing ${annotation} ${signature}`);
};

const bodyAt = (source, openIndex) => {
  assert.notEqual(openIndex, -1, "missing function body");
  let depth = 0;
  let state = "code";
  for (let index = openIndex; index < source.length; index += 1) {
    const current = source[index];
    const next = source[index + 1];
    if (state === "line-comment") {
      if (current === "\n") state = "code";
      continue;
    }
    if (state === "block-comment") {
      if (current === "*" && next === "/") {
        state = "code";
        index += 1;
      }
      continue;
    }
    if (state === "string") {
      if (current === "\\") index += 1;
      else if (current === '"') state = "code";
      continue;
    }
    if (current === "/" && next === "/") {
      state = "line-comment";
      index += 1;
    } else if (current === "/" && next === "*") {
      state = "block-comment";
      index += 1;
    } else if (current === '"') {
      state = "string";
    } else if (current === "{") {
      depth += 1;
    } else if (current === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(openIndex, index + 1);
    }
  }
  assert.fail("unterminated Monkey C function body");
};

const functionBody = (source, signature) => {
  const signatureIndex = source.indexOf(signature);
  assert.notEqual(signatureIndex, -1, `Missing ${signature}`);
  return bodyAt(source, source.indexOf("{", signatureIndex + signature.length));
};

test("96 KiB selects manual set bookkeeping while 128 KiB keeps rich tracking", async () => {
  const [jungle, mode] = await Promise.all([
    readFile("garmin/monkey.jungle", "utf8"),
    readFile("garmin/source/GymWorkoutMode.mc", "utf8")
  ]);
  const profileAnnotations = (profile) => {
    const line = jungle.match(new RegExp(`^${profile}\\.excludeAnnotations = (.+)$`, "m"))?.[1];
    assert.ok(line, `missing ${profile} profile`);
    return new Set(line.split(";"));
  };
  const descent = profileAnnotations("descentg1");
  const enduro = profileAnnotations("enduro");
  const fr55 = profileAnnotations("fr55");

  assert.ok(descent.has("richWorkoutMode"));
  assert.ok(!descent.has("compactWorkoutMode96"),
    "descentg1 must compile the manual 96 KiB implementation");
  assert.ok(enduro.has("compactWorkoutMode96"));
  assert.ok(!enduro.has("richWorkoutMode"),
    "128 KiB products must retain rich workout code");
  assert.ok(fr55.has("compactWorkoutMode96"));
  assert.ok(!fr55.has("richWorkoutMode"),
    "FR55 remains on the unchanged 128 KiB rich profile");

  const manualTracking = annotatedBody(mode, "compactWorkoutMode96",
    "static function allowsDetailedTracking()");
  const richTracking = annotatedBody(mode, "richWorkoutMode",
    "static function allowsDetailedTracking()");
  assert.match(manualTracking, /return state == MODE_PLANNED;/,
    "96 KiB allows manual sets in planned workouts while FREE remains duration-only");
  assert.match(richTracking, /return state == MODE_PLANNED;/,
    "richer products preserve the existing detector-backed mode guard");
});

test("legacy auto-set preference remains readable but 96 KiB startup enables HR only", async () => {
  const [store, session] = await Promise.all([
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/GymSession.mc", "utf8")
  ]);
  const manualStart = annotatedBody(session, "compactWorkoutMode96", "static function startSensors()");
  const richStart = annotatedBody(session, "richWorkoutMode", "static function startSensors()");

  assert.match(store,
    /value = Storage\.getValue\("autoPromptEnabled"\);\s*autoPromptEnabled = value instanceof Lang\.Boolean \? value : true/,
    "the old saved preference still loads for compatibility");
  assert.match(session,
    /\(:compactWorkoutMode96\)\s+static const autoLogPrompt = false/,
    "an enabled legacy preference cannot turn the detector prompt on in manual mode");
  assert.match(manualStart, /Sensor\.setEnabledSensors\(\[Sensor\.SENSOR_HEARTRATE\]\)/);
  assert.doesNotMatch(manualStart,
    /autoPromptEnabled|startMotionListener|registerSensorDataListener|SENSOR_ACCEL|SENSOR_GYRO|accelerometer|gyroscope/i,
    "a saved AUTO SET preference cannot re-enable motion detection on 96 KiB devices");
  assert.match(richStart, /GymWorkoutMode\.allowsDetailedTracking\(\)[\s\S]*startMotionListener\(\)/,
    "128 KiB products retain their detector registration path");
});

test("manual 96 KiB capture omits set intervals while keeping aggregate metrics and set commits", async () => {
  const [session, store, mode, view] = await Promise.all([
    readFile("garmin/source/GymSession.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8"),
    readFile("garmin/source/GymWorkoutMode.mc", "utf8"),
    readFile("garmin/source/WorkoutView.mc", "utf8")
  ]);
  const manualCapture = annotatedBody(session, "compactWorkoutMode96",
    "static function captureSetStatistics()");
  const manualInterval = annotatedBody(session, "compactWorkoutMode96",
    "static function capturedSetInterval(started, ended)");
  const manualTracking = annotatedBody(mode, "compactWorkoutMode96",
    "static function allowsDetailedTracking()");
  const addSet = functionBody(store, "static function addSet()");
  const timeline = functionBody(store, "static function currentTimelineCheckpoint(gymCalorieAdjustment)");
  const expandMetadata = functionBody(store, "static function expandWorkoutMetadata(context)");
  const freePrepare = functionBody(store, "static function prepareWorkoutCommit()");
  const freeMessage = functionBody(store,
    "static function workoutMessageForSave(requestId, metadataOnly)");
  const freeMetadata = functionBody(store,
    "static function isValidWorkoutMetadata(message, actualSetCount)");
  const freeDashboard = annotatedBody(view, "compactWorkoutMode96",
    "function drawFreeSessionDashboard(dc, w, h, saveAction)");
  const onSelect = functionBody(view, "function onSelect()");

  assert.match(manualCapture,
    /return \[0, ended, ended, capturedHr, capturedHr, capturedHr,\s*0, interval, :capturedSetStats\]/,
    "manual capture records save-time HR without detector state");
  assert.match(manualInterval, /return null;/,
    "96 KiB manual capture leaves per-set interval detail absent");
  assert.match(manualCapture, /capturedSetInterval\(ended, ended\)/,
    "the compact capture path stores no per-set interval value");
  assert.match(manualTracking, /return state == MODE_PLANNED;/);
  assert.match(addSet,
    /if \(!GymWorkoutMode\.allowsDetailedTracking\(\)\) \{\s*status = GymStatus\.PLAN_ONLY;\s*return false;\s*\}[\s\S]*GymSession\.captureSetStatistics\(\)[\s\S]*recordedSet\([\s\S]*nextSets\.add\(setItem\)[\s\S]*persistActiveWorkoutSnapshot/,
    "FREE set input is rejected before capture while PLANNED manual sets keep the durable path");
  assert.match(timeline,
    /GymSession\.gymCalories[\s\S]*GymSession\.garminCalories[\s\S]*GymSession\.avgHr[\s\S]*GymSession\.maxHr/,
    "the committed workout checkpoint retains calories and HR totals");
  assert.match(expandMetadata,
    /message\["durationSeconds"\] = checkpoint\[0\][\s\S]*message\["gymCalories"\] = checkpoint\[1\][\s\S]*message\["avgHeartRate"\][\s\S]*message\["maxHeartRate"\]/,
    "workout-level duration, calories, and HR aggregates remain in the wire metadata");
  assert.match(store, /static function pendingCount\(\)/,
    "the manual add path keeps the existing durable pending-queue contract");

  assert.match(freePrepare,
    /if \(freeMode\) \{\s*if \(sets\.size\(\) != 0 \|\| !GymSession\.recording\)/,
    "FREE preparation remains set-free and tied to an active recording");
  assert.match(freePrepare,
    /checkpointLiveWorkout\(true\)[\s\S]*freeCheckpoint\[0\] <= 0/,
    "FREE saving requires a durable checkpoint with positive elapsed time");
  assert.match(freeMessage,
    /if \(freeMode && \(!isValidTimelineCheckpoint\(messageCheckpoint\) \|\|\s*messageCheckpoint\[0\] <= 0\)\)/,
    "outgoing FREE metadata cannot omit positive elapsed time");
  assert.match(freeMessage,
    /for \(var i = 0; !metadataOnly && !freeMode && i < sets\.size\(\)/,
    "FREE payload construction never serializes manual set details");
  assert.match(freeMetadata,
    /modeValue\.toString\(\)\.equals\("free"\)[\s\S]*actualSetCount == 0[\s\S]*isBoundedNumber\(durationValue, 1\.0, 604800\.0\)[\s\S]*setMetrics[\s\S]*setIntervals[\s\S]*plannedTargetSetCount/,
    "the established phone protocol accepts only positive-duration, sets-empty FREE payloads");
  assert.match(freeDashboard,
    /GymSession\.elapsedText\(\)[\s\S]*GymStore\.totalGymCalories\(\)[\s\S]*SELECT: PAUSE/);
  assert.doesNotMatch(freeDashboard, /currentExercise|GymStore\.sets|weight|reps|SET ENTRY/i,
    "FREE presents HR, duration and calories without set-entry controls");
  assert.match(onSelect,
    /if \(GymWorkoutMode\.isFree\(\)\) \{\s*openPauseMenu\(\);\s*\}/,
    "SELECT on the duration-only FREE dashboard opens pause controls");
});

test("96 KiB restart ignores unfinished active journals and keeps finalization recovery", async () => {
  const store = await readFile("garmin/source/GymStore.mc", "utf8");
  const beginLoad = annotatedBody(store, "compactCheckpoint96",
    "static function beginLoad()");
  const planLoader = annotatedBody(store, "compactCheckpoint96",
    "private static function loadBoundV5Plan96()");
  const load = annotatedBody(store, "compactCheckpoint96", "static function load()");
  const completeLoad = annotatedBody(store, "compactCheckpoint96",
    "static function completeLoad(startup)");
  const richCompleteLoad = annotatedBody(store, "compactLegacyState",
    "static function completeLoad(startup)");

  assert.match(beginLoad, /loadBoundV5Plan96\(\)/,
    "the bound V5 plan uses its independent reader");
  assert.match(planLoader,
    /Storage\.getValue\("plan"\)[\s\S]*new GymPlanList\(value\)[\s\S]*v5\.valid\(maxPlanSets, true\)[\s\S]*plan = v5;/,
    "the current plan remains independently validated and loadable");
  assert.match(beginLoad,
    /Storage\.getValue\("pending"\)[\s\S]*isValidPendingList\(value\)/,
    "completed workout messages load independently of the unfinished draft");
  assert.match(load,
    /beginLoad\(\)[\s\S]*GymPendingJournal\.load\(\)[\s\S]*completeLoad\(startup\)/,
    "the indexed pending journal loads before startup completion");
  assert.match(completeLoad,
    /if \(preparedWorkout != null && ownerMatches && savedExerciseCatalogValid &&[\s\S]*?restoreActiveWorkoutSnapshot\(savedActive\);/,
    "only a validated prepared transaction can hydrate its active journal for finalization");
  assert.match(completeLoad,
    /else if \(preparedWorkout != null && recoveredPairing[\s\S]*?restoreActiveWorkoutSnapshot\(savedActive\);/,
    "pairing recovery also gates active hydration on the prepared transaction");
  assert.doesNotMatch(completeLoad, /GymWorkoutMode\.restore\(\)/,
    "the 96 KiB startup path does not restore an abandoned workout mode");
  assert.doesNotMatch(completeLoad, /restoreCurrentEntry\(/,
    "the 96 KiB startup path does not reopen an abandoned exercise entry");
  assert.match(completeLoad, /GymWorkoutMode\.state = GymWorkoutMode\.MODE_IDLE;/,
    "the 96 KiB startup path leaves the workout mode idle");
  assert.match(completeLoad, /restorePreparedWorkout\(savedPreparedWorkout\)/,
    "completed FIT transactions retain their separate recovery path");
  assert.match(completeLoad, /hasPreparedWorkout\(\)/,
    "phase 0/1 recovery is evaluated against the hydrated active journal");
  assert.match(completeLoad,
    /preparedWorkoutFitSaved\(\) \? GymStatus\.FIT_SAVED : GymStatus\.FIT_CHECK/,
    "unknown FIT completion still requires an explicit decision after restart");
  assert.match(richCompleteLoad, /GymWorkoutMode\.restore\(\)/,
    "the richer profiles retain their existing active-mode restoration path");
});

test("96 KiB active and pending journals accept complete legacy intervals and null compact rows", async () => {
  const [active, pending, store] = await Promise.all([
    readFile("garmin/source/GymActiveJournal.mc", "utf8"),
    readFile("garmin/source/GymPendingJournal.mc", "utf8"),
    readFile("garmin/source/GymStore.mc", "utf8")
  ]);
  const validate = annotatedBody(active, "compactWorkoutMode96",
    "static function validate(value)");
  const commit = annotatedBody(active, "compactWorkoutMode96",
    "static function commit(next, origin, checkpoint)");
  const pendingRow = functionBody(pending, "static function row(entry, index)");
  const pendingLoad = annotatedBody(pending, "compactWorkoutMode96",
    "static function load()");
  const pendingAdvance = annotatedBody(pending, "compactWorkoutMode96",
    "static function advance()");
  const frame = functionBody(pending, "static function frame(offset, attemptId)");
  const messageBuilder = functionBody(store,
    "static function workoutMessageForSave(requestId, metadataOnly)");
  const validMessage = functionBody(store, "static function isValidWorkoutMessage(message)");
  const validMetadata = functionBody(store,
    "static function isValidWorkoutMetadata(message, actualSetCount)");
  const legacyCopy = functionBody(store, "static function normalizedLegacyPendingList(source)");
  const drain = functionBody(store, "static function removePendingByRequestId(requestId)");

  assert.match(validate,
    /var checkpoint = value\[9\][\s\S]*var intervalMode = 0[\s\S]*if \(interval == null\)[\s\S]*intervalMode == 1[\s\S]*else[\s\S]*intervalMode == 2[\s\S]*GymStore\.isValidSetInterval\(interval\)/,
    "active snapshot validation allows all-null compact rows and rejects mixed or malformed intervals");
  assert.match(commit,
    /var intervalMode = checkpoint == null && next\.size\(\) > 0 \? 2 : 0[\s\S]*if \(interval == null\)[\s\S]*intervalMode == 1[\s\S]*intervalMode == 2 \|\| !GymStore\.isValidSetInterval\(interval\)/,
    "active journal commits enforce one interval representation per workout");
  assert.match(pendingRow,
    /header\[9\] == null \? value\[4\] != null : !GymStore\.isValidSetInterval\(value\[4\]\)/,
    "pending rows validate any legacy interval before framing");
  assert.match(pendingLoad,
    /var intervalMode = 0[\s\S]*if \(item\[3\] == null\)[\s\S]*intervalMode == 1[\s\S]*else[\s\S]*intervalMode == 2/,
    "journal reload validates an all-null or all-present row set");
  assert.match(pendingAdvance,
    /if \(value\[4\] == null\)[\s\S]*stagedIntervalMode == 1[\s\S]*else[\s\S]*stagedIntervalMode == 2 \|\| staged\[1\]\[9\] == null/,
    "journal commits apply the same mixed-row and malformed-interval checks");
  assert.match(frame,
    /message\.put\("set",[\s\S]*if \(item\[3\] != null\) \{ message\.put\("interval", item\[3\]\); \}/,
    "null-interval rows frame without an interval key while legacy rows retain theirs");
  assert.match(messageBuilder,
    /var setIntervals = GymWorkoutMode\.permitsOmittedSetIntervals\(\) \? null : \[\][\s\S]*if \(setInterval != null && isValidSetInterval\(setInterval\)\)[\s\S]*allIntervalsAvailable = false[\s\S]*messageCheckpoint != null && allIntervalsAvailable[\s\S]*message\["setIntervals"\]/,
    "new 96 KiB sets omit the interval array unless every set provides valid legacy detail");
  assert.match(validMessage,
    /intervals == null \|\| \(isValidSetIntervalsList\(intervals, setsValue\)[\s\S]*areSetIntervalsConsistent/,
    "full legacy setIntervals remain accepted only after complete validation");
  assert.match(validMetadata,
    /message\.get\("setIntervals"\) == null/,
    "FREE remains duration-only while planned legacy interval messages keep the metadata path");
  assert.match(legacyCopy,
    /message\.get\("setIntervals"\)[\s\S]*safe\.put\("setIntervals"/,
    "legacy pending normalization retains the exact interval payload for retry");
  assert.match(drain,
    /restorePendingForMutation\(\)[\s\S]*pending\.remove\(item\)[\s\S]*if \(save\(\)/,
    "acknowledged legacy pending items drain through the existing durable queue path");
});
