import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const contract = JSON.parse(await readFile("shared/health-import-v1.json", "utf8"));
const languages = ["en", "uk", "ru"];
const reasons = [
  "invalid-record", "own-app", "not-gym-type", "duration", "in-progress", "duplicate-receipt", "overlap"
];

test("contract constants have the documented values and bounds", () => {
  assert.equal(contract.schemaVersion, 1);
  assert.equal(contract.windowDays, 30);
  assert.equal(contract.maxSessionsPerRun, 200);
  assert.equal(contract.maxRecordsScannedPerRun, 1000);
  assert.equal(contract.minDurationSeconds, 60);
  assert.equal(contract.maxDurationSeconds, 86400);
  assert.equal(contract.overlapToleranceSeconds, 120);
  assert.equal(contract.minAutoImportIntervalSeconds, 3600);
  assert.ok(contract.minDurationSeconds < contract.maxDurationSeconds);
  assert.ok(contract.maxDurationSeconds <= 7 * 24 * 3600, "must fit the workout duration limit");
  assert.ok(contract.maxSessionsPerRun <= contract.maxRecordsScannedPerRun);
  assert.equal(contract.noteSeparator, " · ");
  assert.equal(contract.maxReceiptKeyLength, 256);
  assert.equal(contract.maxHeartRateSamplesPerRun, 50000);
  assert.deepEqual(contract.decisionOrder, reasons);
});

test("heart-rate plausibility fits the activity-only sidecar limits", () => {
  const { minPlausibleBpm, maxPlausibleBpm } = contract.heartRate;
  assert.ok(Number.isInteger(minPlausibleBpm) && minPlausibleBpm >= 1);
  assert.ok(Number.isInteger(maxPlausibleBpm) && maxPlausibleBpm <= 240, "sidecar rejects heart rate above 240");
  assert.ok(minPlausibleBpm < maxPlausibleBpm);
  assert.ok(contract.calories.maxKilocalories <= 100000);
});

test("stores declare prefixes, own sources, gym types and complete labels", () => {
  assert.deepEqual(Object.keys(contract.stores).sort(), ["healthConnect", "healthKit"]);
  const prefixes = new Set();
  for (const [name, store] of Object.entries(contract.stores)) {
    assert.match(store.receiptKeyPrefix, /^[a-z_]+:$/, name);
    assert.ok(!prefixes.has(store.receiptKeyPrefix), "receipt prefixes must differ per store");
    prefixes.add(store.receiptKeyPrefix);
    assert.ok(store.notePrefix.length > 0);
    assert.ok(store.ownSourceIds.length > 0);
    assert.ok(store.gymExerciseTypes.length > 0);
    assert.equal(new Set(store.gymExerciseTypes).size, store.gymExerciseTypes.length);
    assert.deepEqual(Object.keys(store.typeLabels).sort(), [...store.gymExerciseTypes].sort(), name);
    for (const [type, label] of Object.entries(store.typeLabels)) {
      for (const language of languages) {
        assert.ok(typeof label[language] === "string" && label[language].length > 0, `${name}.${type}.${language}`);
      }
    }
  }
  assert.equal(contract.stores.healthConnect.notePrefix, "Health Connect");
  assert.equal(contract.stores.healthKit.notePrefix, "Apple Health");
  assert.deepEqual(contract.stores.healthConnect.gymExerciseTypes, [
    "STRENGTH_TRAINING", "WEIGHTLIFTING", "CALISTHENICS", "HIGH_INTENSITY_INTERVAL_TRAINING", "GYMNASTICS", "BOOT_CAMP"
  ]);
  assert.deepEqual(contract.stores.healthKit.gymExerciseTypes, [
    "traditionalStrengthTraining", "functionalStrengthTraining", "coreTraining",
    "highIntensityIntervalTraining", "crossTraining", "gymnastics"
  ]);
});

test("note segment templates exist for every language", () => {
  for (const key of ["duration", "calories", "averageHeartRate", "maximumHeartRate"]) {
    for (const language of languages) {
      assert.ok(contract.noteSegments[key][language], `${key}.${language}`);
    }
  }
  assert.ok(contract.noteSegments.duration.en.includes("{minutes}") && contract.noteSegments.duration.en.includes("{seconds}"));
});

test("golden cases are well formed and cover every outcome and boundary", () => {
  const ids = new Set();
  const seenOutcomes = new Set();
  const storesSeen = new Set();
  for (const item of contract.cases) {
    assert.ok(!ids.has(item.id), `duplicate case id ${item.id}`);
    ids.add(item.id);
    assert.ok(contract.stores[item.store], `${item.id}: unknown store`);
    storesSeen.add(item.store);
    assert.ok(languages.includes(item.language), `${item.id}: language`);
    const { session } = item;
    assert.ok(typeof session.recordId === "string", item.id);
    assert.ok(Number.isSafeInteger(item.nowMillis), `${item.id}: nowMillis`);
    assert.ok(Number.isSafeInteger(session.startMillis) && Number.isSafeInteger(session.endMillis), item.id);
    assert.ok(session.exerciseType === null || typeof session.exerciseType === "string", item.id);
    assert.ok(session.kilocalories === null || Number.isFinite(session.kilocalories), item.id);
    for (const sample of session.heartRateSamples) {
      assert.ok(Number.isSafeInteger(sample.timeMillis) && Number.isSafeInteger(sample.bpm), item.id);
    }
    for (const workout of item.existingWorkouts) {
      assert.ok(Number.isSafeInteger(workout.startMillis), item.id);
      assert.ok(workout.durationSeconds === null || Number.isSafeInteger(workout.durationSeconds), item.id);
    }
    for (const key of item.receipts) assert.equal(typeof key, "string");

    const { expected } = item;
    seenOutcomes.add(expected.outcome);
    if (expected.outcome === "imported") {
      const store = contract.stores[item.store];
      assert.equal(expected.receiptKey, store.receiptKeyPrefix + session.recordId, item.id);
      const w = expected.workout;
      assert.equal(w.workoutStartedAt, session.startMillis, item.id);
      assert.equal(w.durationSeconds, Math.floor((session.endMillis - session.startMillis) / 1000), item.id);
      assert.ok(w.durationSeconds >= contract.minDurationSeconds && w.durationSeconds <= contract.maxDurationSeconds, item.id);
      assert.ok(Number.isInteger(w.gymCalories) && w.gymCalories >= 0, item.id);
      for (const key of ["averageHeartRate", "maximumHeartRate"]) {
        assert.ok(w[key] === null || (w[key] >= contract.heartRate.minPlausibleBpm && w[key] <= contract.heartRate.maxPlausibleBpm), `${item.id}.${key}`);
      }
      assert.ok(w.averageHeartRate === null || w.averageHeartRate <= w.maximumHeartRate, item.id);
      assert.ok(w.note.startsWith(store.notePrefix), item.id);
      assert.ok(w.note.length <= 512 && Buffer.byteLength(w.note) <= 2048, "note must fit the sidecar limits");
      assert.ok(!store.ownSourceIds.includes(session.sourceId), item.id);
      assert.ok(session.endMillis <= item.nowMillis, `${item.id}: imported session must have ended`);
      assert.ok(session.recordId.length > 0 && store.receiptKeyPrefix.length + session.recordId.length <= contract.maxReceiptKeyLength, item.id);
      assert.ok(!/[\u0000-\u001f\u007f-\u009f]/.test(session.recordId), item.id);
    } else {
      assert.match(expected.outcome, /^skipped:/, item.id);
      assert.ok(reasons.includes(expected.outcome.slice("skipped:".length)), item.id);
    }
  }
  for (const reason of reasons) assert.ok(seenOutcomes.has(`skipped:${reason}`), `no case for ${reason}`);
  assert.ok(seenOutcomes.has("imported"));
  assert.deepEqual([...storesSeen].sort(), ["healthConnect", "healthKit"]);
  for (const language of languages) assert.ok(contract.cases.some(c => c.language === language && c.expected.outcome === "imported"), language);
});

test("tolerance boundary cases sit exactly on the 120 second edge", () => {
  const tolerance = contract.overlapToleranceSeconds * 1000;
  const byId = Object.fromEntries(contract.cases.map(c => [c.id, c]));
  const afterEnd = byId["hc-overlap-after-end-tolerance-inclusive"];
  assert.equal(afterEnd.existingWorkouts[0].startMillis, afterEnd.session.endMillis + tolerance);
  const beyond = byId["hc-no-overlap-after-end-beyond-tolerance"];
  assert.equal(beyond.existingWorkouts[0].startMillis, beyond.session.endMillis + tolerance + 1000);
  const before = byId["hc-overlap-before-start-tolerance-inclusive"];
  const e = before.existingWorkouts[0];
  assert.equal(e.startMillis + e.durationSeconds * 1000 + tolerance, before.session.startMillis);
});

test("rules cover the account opt-in, receipt scope, data origin and the new skips", () => {
  for (const key of ["invalidRecord", "inProgress", "accountOptIn", "dataOrigin", "heartRateBudget"]) {
    assert.ok(typeof contract.rules[key] === "string" && contract.rules[key].length > 0, key);
  }
  assert.match(contract.rules.duplicateReceipt, /per install and per account/);
  assert.match(contract.rules.accountOptIn, /notEnabled/);
  assert.match(contract.rules.dataOrigin, /never from any other source/);
});

test("record id and in-progress boundaries sit exactly on the documented edge", () => {
  const byId = Object.fromEntries(contract.cases.map(c => [c.id, c]));
  const { healthConnect, healthKit } = contract.stores;
  const hcLong = byId["hc-record-id-too-long"].session.recordId;
  assert.equal(healthConnect.receiptKeyPrefix.length + hcLong.length, contract.maxReceiptKeyLength + 1);
  const hcMax = byId["hc-record-id-max-length-imported"].session.recordId;
  assert.equal(healthConnect.receiptKeyPrefix.length + hcMax.length, contract.maxReceiptKeyLength);
  const hkLong = byId["hk-record-id-too-long"].session.recordId;
  assert.equal(healthKit.receiptKeyPrefix.length + hkLong.length, contract.maxReceiptKeyLength + 1);
  const hkMax = byId["hk-record-id-max-length-imported"].session.recordId;
  assert.equal(healthKit.receiptKeyPrefix.length + hkMax.length, contract.maxReceiptKeyLength);
  const running = byId["hc-in-progress-ends-after-now"];
  assert.equal(running.session.endMillis, running.nowMillis + 1000);
  const exact = byId["hc-ends-exactly-now-imported"];
  assert.equal(exact.session.endMillis, exact.nowMillis);
});

test("the Apple Watch app is an own HealthKit source", () => {
  const watchId = "com.setforge.gymapp.ios.watchkitapp";
  assert.deepEqual(contract.stores.healthKit.ownSourceIds, ["com.setforge.gymapp.ios", watchId]);
  const item = contract.cases.find((entry) => entry.id === "hk-own-app-apple-watch");
  assert.ok(item, "golden case hk-own-app-apple-watch");
  assert.equal(item.store, "healthKit");
  assert.equal(item.session.sourceId, watchId);
  assert.equal(item.expected.outcome, "skipped:own-app");
});
