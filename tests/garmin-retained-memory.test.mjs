import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile("garmin/source/GymStore.mc", "utf8");
const planAccess = await readFile("garmin/source/GymPlanAccess.mc", "utf8");
const fullLoad = source.slice(
  source.indexOf("static function load() {"),
  source.indexOf("static function save() {", source.indexOf("static function load() {"))
);
const compactLoad = source.slice(
  source.indexOf("static function beginLoad() {"),
  source.indexOf("static function load() {", source.indexOf("static function beginLoad() {"))
);

test("bound Garmin loads defer the legacy sets mirror until snapshot repair is resolved", () => {
  const helper = source.slice(
    source.indexOf("static function restoreLegacySetMirrorIfSnapshotAbsent("),
    source.indexOf("(:fullLegacyState)\n    static function load()")
  );
  assert.ok(helper.indexOf("if (savedActive != null) { return false; }") >= 0);
  assert.ok(helper.indexOf('Storage.getValue("sets")') > helper.indexOf("savedActive != null"));
  assert.ok(helper.indexOf('Storage.getValue("activeWorkoutStartedAtSeconds")') > helper.indexOf("savedActive != null"));

  const fullActive = fullLoad.indexOf('var savedActiveWorkout = Storage.getValue("activeWorkoutV1");');
  const fullRepair = fullLoad.indexOf('Storage.deleteValue("activeWorkoutV1");', fullActive);
  const fullFallback = fullLoad.indexOf("restoreLegacySetMirrorIfSnapshotAbsent(savedActiveWorkout)", fullActive);
  assert.ok(fullActive >= 0 && fullRepair > fullActive && fullFallback > fullRepair);
  assert.ok(fullLoad.slice(fullRepair, fullFallback).includes("savedActiveWorkout = null;"));
  assert.match(fullLoad, /if \(!legacyUnboundState\) \{\s*restoreLegacySetMirrorIfSnapshotAbsent\(savedActiveWorkout\);/);

  const compactActive = compactLoad.indexOf('var savedActive = Storage.getValue("activeWorkoutV1");');
  const compactRepair = compactLoad.indexOf('Storage.deleteValue("activeWorkoutV1");', compactActive);
  const compactFallback = compactLoad.indexOf("restoreLegacySetMirrorIfSnapshotAbsent(savedActive)", compactActive);
  assert.ok(compactActive >= 0 && compactRepair > compactActive && compactFallback > compactRepair);
  assert.ok(compactLoad.slice(compactRepair, compactFallback).includes("savedActive = null;"));
  assert.match(compactLoad, /if \(!legacyUnboundState\) \{\s*restoreLegacySetMirrorIfSnapshotAbsent\(savedActive\);/);

  assert.match(fullLoad, /if \(legacyUnboundState\) \{\s*savedSets = Storage.getValue\("sets"\);/);
  assert.match(compactLoad, /if \(legacyUnboundState\) \{\s*value = Storage.getValue\("sets"\);/);
});

test("compact plan restore stays columnar and cannot overwrite an unreadable legacy value", () => {
  const compactLoadPlanIndex = compactLoad.indexOf("loadLegacyStoredPlan();");
  const compactCatalogIndex = compactLoad.indexOf('Storage.getValue("exercises")');
  assert.ok(compactLoadPlanIndex >= 0 && compactCatalogIndex > compactLoadPlanIndex);

  assert.match(planAccess, /if \(cachedIndex != index\) \{\s*cachedRow = \{[\s\S]*?"exerciseName" => columns\[1\]\[index\],[\s\S]*?"weight" => columns\[2\]\[index\],[\s\S]*?"reps" => columns\[3\]\[index\][\s\S]*?cachedIndex = index;[\s\S]*?return cachedRow;/);
  assert.match(planAccess, /if \(value instanceof GymPlanList\) \{ return value\.columns\[1\]\[index\]; \}/);

  const restoreStart = source.indexOf("(:compactLegacyState, :inline)\n    static function restoredPlan(value)");
  const restoreEnd = source.indexOf("(:compactLegacyState)\n    static function storedPlan()", restoreStart);
  assert.ok(restoreStart >= 0 && restoreEnd > restoreStart);
  const compactRestore = source.slice(restoreStart, restoreEnd);
  assert.ok(compactRestore.includes("new GymPlanList(value)"));
  assert.ok(compactRestore.includes("value[i].size() != 3"));
  assert.ok(compactRestore.includes('value[j] = row.get("exerciseName").toString();'));
  assert.ok(compactRestore.includes("persistedPlanNeedsV5Write = true;"));
  assert.ok(compactRestore.includes("persistedPlanSource = value;"));

  const compactStoreStart = source.indexOf("(:compactLegacyState)\n    static function storedPlan()");
  const compactStoreEnd = source.indexOf("// Version 3 stores set fields", compactStoreStart);
  assert.ok(compactStoreStart >= 0 && compactStoreEnd > compactStoreStart);
  assert.ok(source.slice(compactStoreStart, compactStoreEnd).includes("return plan.columns;"));

  const loaderStart = source.indexOf("private static function loadLegacyStoredPlan()");
  const loaderEnd = source.indexOf("static function ensureDurableExerciseCatalog()", loaderStart);
  assert.ok(loaderStart >= 0 && loaderEnd > loaderStart);
  const planLoader = source.slice(loaderStart, loaderEnd);
  const malformedStart = planLoader.indexOf("if (restored == null)");
  const malformedEnd = planLoader.indexOf("plan = restored;", malformedStart);
  assert.ok(malformedStart >= 0 && malformedEnd > malformedStart);
  const malformedBranch = planLoader.slice(malformedStart, malformedEnd);
  assert.ok(malformedBranch.includes("persistedPlanSource = plan;"));
  assert.ok(malformedBranch.includes("persistedPlanNeedsV5Write = false;"));
  assert.ok(malformedBranch.includes("status = GymStatus.RECOVERY_FAIL;"));
  assert.doesNotMatch(malformedBranch, /Storage\.setValue\("plan"/);

  const migrationStart = planLoader.indexOf("if (persistedPlanNeedsV5Write)");
  const migrationEnd = planLoader.indexOf("\n        value = null;\n    }", migrationStart);
  assert.ok(migrationStart >= 0 && migrationEnd > migrationStart);
  const migration = planLoader.slice(migrationStart, migrationEnd);
  const migrationWrite = migration.indexOf('Storage.setValue("plan", compactPlanValue);');
  const retryReset = migration.indexOf("persistedPlanNeedsV5Write = false;", migrationWrite);
  const migrationCatch = migration.indexOf("catch (e)", migrationWrite);
  assert.ok(migrationWrite >= 0 && retryReset > migrationWrite && migrationCatch > retryReset);
  assert.match(migration.slice(migrationCatch), /old single-key value is still intact/);
  assert.doesNotMatch(migration.slice(migrationCatch), /persistedPlanNeedsV5Write\s*=\s*false/);

  const compactSaveStart = source.indexOf("(:compactLegacyState)\n    static function save() {");
  const compactSaveEnd = source.indexOf("(:compactLegacyState)\n    private static function loadLegacyStoredPlan()", compactSaveStart);
  assert.ok(compactSaveStart >= 0 && compactSaveEnd > compactSaveStart);
  const compactSave = source.slice(compactSaveStart, compactSaveEnd);
  assert.match(compactSave, /var planChanged = plan != persistedPlanSource \|\| persistedPlanNeedsV5Write;/);
  const guardedPlanWrite = compactSave.indexOf('Storage.setValue("plan", storedPlanValue);');
  const planChangeGate = compactSave.indexOf("if (planChanged)", compactSave.indexOf("var planChanged"));
  assert.ok(planChangeGate >= 0 && guardedPlanWrite > planChangeGate);

  // Historical wire/storage validation still permits 60; only a new, unstaged
  // phone submission is rejected when it exceeds today's 30-target product cap.
  const compactApplyStart = source.indexOf("(:compactLegacyState)\n    static function applySyncFromSource(message, bindingSource)");
  const compactValidatorStart = source.indexOf("(:compactLegacyState)\n    static function isValidSyncMessage(message, trustedSource)", compactApplyStart);
  const compactValidatorEnd = source.indexOf("(:inline)\n    static function hasOnlySyncKeys", compactValidatorStart);
  assert.ok(compactApplyStart >= 0 && compactValidatorStart > compactApplyStart && compactValidatorEnd > compactValidatorStart);
  const compactApply = source.slice(compactApplyStart, compactValidatorStart);
  const compactValidator = source.slice(compactValidatorStart, compactValidatorEnd);
  assert.match(compactValidator, /isValidPlanColumns\(names, weights, setReps, maxPlanSets\)/);
  assert.match(compactApply, /!isExactStagedSync\(safeMessage, bindingSource\)[\s\S]*?incomingPlanNames\.size\(\) > maxNewWorkoutSets/);

  const planColumnsStart = source.indexOf("static function isValidPlanColumns(names, weights, setReps, maximum)");
  const planColumnsEnd = source.indexOf("(:fullLegacyState)\n    static function isSetRecord(value)", planColumnsStart);
  assert.ok(planColumnsStart >= 0 && planColumnsEnd > planColumnsStart);
  const planColumnsValidator = source.slice(planColumnsStart, planColumnsEnd);
  assert.match(planColumnsValidator, /weights\.size\(\) != names\.size\(\)/);
  assert.match(planColumnsValidator, /setReps\.size\(\) != names\.size\(\)/);
  assert.match(planColumnsValidator, /!isValidExerciseList\(names, maximum\)/,
    "the columnar wire validator retains the historical 60-target bound and name budget");
  assert.match(planColumnsValidator, /!isValidWeight\(weights\[i\]\) \|\| !isValidReps\(setReps\[i\]\)/);
});
