import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";

const root = path.resolve(import.meta.dirname, "..");
const contract = JSON.parse(fs.readFileSync(path.join(root, "shared/training-tools-v1.json"), "utf8"));
const pwa = fs.readFileSync(path.join(root, "pwa/app.js"), "utf8");
const android = [
  "app/src/main/java/com/example/gymapp/data/repository/TrainingTools.kt",
  "app/src/main/java/com/example/gymapp/data/repository/WeeklyReview.kt",
  "app/src/main/java/com/example/gymapp/data/repository/WorkoutAdaptation.kt",
  "app/src/main/java/com/example/gymapp/util/TrainingProgramStore.kt"
].map(file => fs.readFileSync(path.join(root, file), "utf8")).join("\n");
const ios = [
  "ios/GymApp-iOS/GymApp/Domain/TrainingTools.swift",
  "ios/GymApp-iOS/GymApp/Domain/WeeklyReview.swift",
  "ios/GymApp-iOS/GymApp/Domain/WorkoutAdaptation.swift",
  "ios/GymApp-iOS/GymApp/Services/TrainingProgramStore.swift"
].map(file => fs.readFileSync(path.join(root, file), "utf8")).join("\n");

test("training tools contract describes the four approved capabilities", () => {
  assert.equal(contract.version, 1);
  assert.deepEqual(contract.clients, ["android", "ios", "pwa"]);
  assert.deepEqual(contract.adaptation.reasons, ["equipmentUnavailable", "timeCut", "tooHard"]);
  assert.equal(contract.weeklyReview.comparison, "previousCalendarWeekSameExerciseAndExactWeightBestReps");
  assert.equal(contract.program.weeks, 4);
  assert.equal(contract.quickEntry.defaultWeightStepKg, 2.5);
});

test("all clients implement bounded account-owned program storage and adaptation preview", () => {
  for (const source of [pwa, android, ios]) {
    assert.match(source, /32[ _]?\*?[ _]?1024|32_768|32768/i);
    assert.match(source, /owner/i);
    assert.match(source, /equipmentUnavailable/);
    assert.match(source, /timeCut/);
    assert.match(source, /tooHard/);
  }
});

test("PWA quick weight step follows the configured stack", () => {
  const start = pwa.indexOf("function trainingStepWeight");
  const end = pwa.indexOf("function activePreviousValues", start);
  assert.ok(start >= 0 && end > start);
  const context = {};
  vm.createContext(context);
  vm.runInContext(pwa.slice(start, end), context);
  assert.equal(context.trainingStepWeight(5, 1, [5, 7.5, 10]), 7.5);
  assert.equal(context.trainingStepWeight(10, 1, [5, 7.5, 10]), 10);
  assert.equal(context.trainingStepWeight(20, -1, []), 17.5);
});

test("client sources keep completed work explicit during adaptation", () => {
  assert.match(pwa, /completedAt/);
  assert.match(android, /completedAt/);
  assert.match(ios, /preservesCompleted/);
});

test("PWA exposes program navigation to pointer and keyboard input", () => {
  assert.match(pwa, /\["overview", "exercises", "goals", "program"\]\.includes\(el\.dataset\.section\)/);
  assert.match(pwa, /selectedSection === "program"/);
});

test("PWA accepts bounded future program dates without accepting unbounded timestamps", () => {
  assert.match(pwa, /timestamp <= now \+ 40 \* 86_400_000/);
  assert.match(pwa, /isTrainingProgramDateAllowed\(slot\.date\)/);
});
