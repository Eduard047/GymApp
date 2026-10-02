import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const bodyFrom = (source, signature, annotation) => {
  let at = source.indexOf(signature);
  while (at !== -1) {
    const lineStart = source.lastIndexOf("\n", at - 1) + 1;
    const before = source.slice(source.lastIndexOf("\n", lineStart - 2) + 1, at);
    if (!annotation || before.includes(`:${annotation}`)) {
      const start = source.indexOf("{", at);
      let depth = 0;
      for (let i = start; i < source.length; i += 1) {
        if (source[i] === "{") depth += 1;
        if (source[i] === "}" && --depth === 0) return source.slice(start, i + 1);
      }
    }
    at = source.indexOf(signature, at + signature.length);
  }
  return assert.fail(`missing ${annotation} ${signature}`);
};

const read = (name) => readFile(`garmin/source/${name}`, "utf8");

test("lite startup purges plan state blind, once, and never touches queue or ownership keys", async () => {
  const store = await read("GymStore.mc");
  const beginLoad = bodyFrom(store, "static function beginLoad()", "compactCheckpoint96");
  const purge = bodyFrom(store, "private static function purgePlanState96()", "compactCheckpoint96");

  assert.match(beginLoad, /purgePlanState96\(\)/);
  assert.doesNotMatch(beginLoad, /Storage\.getValue\("plan"\)/);
  assert.doesNotMatch(store, /loadBoundV5Plan96|preserveUnownedPlan96/);

  // Purged keys are deleted without a getValue on them.
  for (const key of ["plan", "exercises", "deferredSync", "legacyQuarantinePlan", "legacyQuarantineExercises"]) {
    assert.match(purge, new RegExp(`Storage\\.deleteValue\\("${key}"\\)`), `${key} is deleted`);
    assert.doesNotMatch(purge, new RegExp(`Storage\\.getValue\\("${key}"\\)`), `${key} is not read`);
  }

  // One-time marker: checked first, written last.
  const marker = "lite96PurgedV1";
  assert.ok(purge.indexOf(`getValue("${marker}")`) !== -1 &&
    purge.indexOf(`getValue("${marker}")`) < purge.indexOf('deleteValue("plan")'));
  assert.ok(purge.indexOf(`setValue("${marker}", 1)`) > purge.indexOf('deleteValue("legacyQuarantineExercises")'));
  assert.match(purge, /getValue\("lite96PurgedV1"\) != null\) \{ return true; \}/);

  // Never delete queued/active/owner keys.
  for (const key of ["pending", "pendingJournalV1", "activeWorkoutV1", "activeRuntimeV1",
    "preparedWorkoutV1", "accountBinding", "stateOwnerBinding", "deviceBinding",
    "pairingGeneration", "cloudDeviceBinding", "phoneSyncFence", "phoneSyncStage"]) {
    assert.doesNotMatch(purge, new RegExp(`deleteValue\\("${key}"\\)`), `${key} must survive the purge`);
  }

  // The catalog is addressed by index from queued/active rows, so the purge
  // waits while any of them exists.
  assert.match(purge, /storedActiveSnapshotHasSets\(Storage\.getValue\("activeWorkoutV1"\)\)/);
  assert.match(purge, /Storage\.getValue\("preparedWorkoutV1"\) != null/);
  assert.match(purge, /Storage\.getValue\("pendingJournalV1"\)/);
  assert.ok(purge.indexOf("return false;") < purge.indexOf('deleteValue("plan")'),
    "the dependency check returns before any delete");
});

test("96 KiB queue limits are lower than the unchanged full-profile constants", async () => {
  const store = await read("GymStore.mc");
  const journal = await read("GymPendingJournal.mc");
  assert.match(store, /private static const maxPendingWorkouts = 8;/);
  assert.match(store, /private static const maxPendingNameBytes = 12000;/);
  assert.match(store, /private static const maxTotalNameBytes = 12000;/);
  assert.match(store, /private static const maxEstimatedStoreBytes = 24000;/);
  assert.match(store, /\(:compactWorkoutMode96\)\s*static const queueLimit = 3;/);
  assert.match(store, /\(:compactWorkoutMode96\)\s*static const queueNameBudget = 4500;/);
  assert.doesNotMatch(store, /\(:richWorkoutMode\)\s*static const queueLimit/);

  const begin = bodyFrom(journal, "static function begin(metadata)", "compactWorkoutMode96");
  const advance = bodyFrom(journal, "static function advance()", "compactWorkoutMode96");
  assert.match(begin, /GymStore\.pendingCount\(\) >= GymStore\.queueLimit/);
  assert.match(advance, /> GymStore\.queueNameBudget/);

  // Full profiles keep the literal limits.
  assert.match(bodyFrom(journal, "static function begin(metadata)", "richWorkoutMode"),
    /GymStore\.pendingCount\(\) >= 8/);
  assert.match(bodyFrom(journal, "static function advance()", "richWorkoutMode"), /> 12000/);

  // Stored legacy queues stay valid: validators keep the full-profile limits.
  assert.match(bodyFrom(store, "static function isValidPendingList(value)"), /maxPendingWorkouts/);
});

test("plan UI and plan start paths are excluded from the 96 KiB build", async () => {
  const view = await read("WorkoutView.mc");
  const mode = await read("GymWorkoutMode.mc");
  const store = await read("GymStore.mc");

  assert.doesNotMatch(view, /\(:compactWorkoutMode96[^)]*\)\s*function (drawManualDashboard|drawEntry|activate|continueSetAction)\b/);
  assert.match(view, /\(:richWorkoutMode\)\s*function changeSet\(/);
  assert.match(view, /\(:richWorkoutMode\)\s*function recordSet\(/);

  const count = bodyFrom(view, "function readyActionCount()", "compactWorkoutMode96");
  assert.match(count, /return 2;/);
  const text = bodyFrom(view, "function readyActionText(index, count)", "compactWorkoutMode96");
  assert.doesNotMatch(text, /PLAN/, "no plan strings on the lite Ready card");
  assert.match(text, /FREE WORKOUT", "ВІЛЬНЕ ТРЕН\.", "СВОБ\. ТРЕН\."/, "free start has EN/UK/RU text");
  assert.match(text, /SYNC WITH PHONE", "СИНХР\. З ТЕЛ\.", "СИНХР\. С ТЕЛ\."/);
  const select = bodyFrom(view, "function handleReadySelection()", "compactWorkoutMode96");
  assert.match(select, /startOrResumeWorkout\(false\)/);
  assert.doesNotMatch(select, /startOrResumeWorkout\(true\)|hasStartablePlan/);

  assert.match(bodyFrom(mode, "static function hasValidPlan()", "compactWorkoutMode96"), /return false;/);
  assert.match(mode, /\(:richWorkoutMode\)\s*static function hasStartablePlan\(\)/);
  assert.match(bodyFrom(mode, "static function begin(usePlan)", "compactWorkoutMode96"), /state = MODE_FREE;/);
  assert.doesNotMatch(bodyFrom(mode, "static function begin(usePlan)", "compactWorkoutMode96"),
    /MODE_PLANNED|selectNextPlanSlot|saveCurrentEntry/);

  // Plan mutation code is excluded from the lite build.
  for (const name of ["addSet", "nextExercise", "applyCurrentPlanSet", "selectNextPlanSlotInGlobalOrder"]) {
    const re = new RegExp(`\\(:[^)]*\\)\\s*static function ${name}\\(`, "g");
    const defs = [...store.matchAll(re)].map((m) => m[0]);
    assert.ok(defs.length > 0, `${name} defined`);
    assert.ok(defs.every((d) => /richWorkoutMode|fullLegacyState/.test(d)), `${name} is not part of the 96 KiB build`);
  }
});
