import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const ios = "ios/GymApp-iOS";
const languages = ["en", "uk", "ru"];

test("iPhone app declares the HealthKit entitlement and read usage strings in EN/UK/RU", async () => {
  const entitlements = await readFile(`${ios}/GymApp/GymApp.entitlements`, "utf8");
  assert.match(entitlements, /<key>com\.apple\.developer\.healthkit<\/key>\s*<true\/>/);
  assert.match(entitlements, /<key>com\.apple\.developer\.healthkit\.access<\/key>\s*<array\/>/);

  const infoPlist = await readFile(`${ios}/GymApp/Resources/Info.plist`, "utf8");
  assert.match(infoPlist, /<key>NSHealthShareUsageDescription<\/key>/);
  assert.doesNotMatch(infoPlist, /NSHealthUpdateUsageDescription/);

  for (const language of languages) {
    const strings = await readFile(
      `${ios}/GymApp/Resources/${language}.lproj/InfoPlist.strings`,
      "utf8"
    );
    const match = strings.match(/"NSHealthShareUsageDescription"\s*=\s*"([^"]+)";/);
    assert.ok(match, `${language} NSHealthShareUsageDescription`);
    assert.ok(match[1].length > 40, `${language} text is a real sentence`);
  }
});

test("the import is read-only: no HealthKit write types or share requests", async () => {
  const service = await readFile(`${ios}/GymApp/Services/HealthKitImportService.swift`, "utf8");
  assert.match(service, /requestAuthorization\(toShare: \[\], read:/);
  assert.doesNotMatch(service, /HKWorkoutBuilder|HKQuantitySample\(|HKHealthStore\(\)\.save|store\.save\(\[/);
  assert.match(service, /completeFileProtectionUntilFirstUserAuthentication/);
  assert.match(service, /isExcludedFromBackupKey/);
});

test("the contract's Apple Health constants are mirrored in the rules", async () => {
  const contract = JSON.parse(await readFile("shared/health-import-v1.json", "utf8"));
  const rules = await readFile(`${ios}/GymApp/Services/HealthImportRules.swift`, "utf8");
  const kit = contract.stores.healthKit;
  assert.ok(rules.includes(`"${kit.receiptKeyPrefix}"`));
  assert.ok(rules.includes(`"${kit.notePrefix}"`));
  for (const id of kit.ownSourceIds) assert.ok(rules.includes(`"${id}"`), id);
  for (const type of kit.gymExerciseTypes) assert.ok(rules.includes(`"${type}"`), type);
});

test("privacy documents describe the opt-in read-only Apple Health import", async () => {
  const policy = await readFile(`${ios}/AppStore/privacy-policy.html`, "utf8");
  for (const phrase of ["Apple Health (HealthKit)", "Apple Health (HealthKit) лише", "Apple Health (HealthKit) только"]) {
    assert.ok(policy.includes(phrase), phrase);
  }
  assert.doesNotMatch(policy, /Motion &amp; Fitness, or HealthKit/);
  assert.doesNotMatch(policy, /Motion &amp; Fitness або HealthKit/);
  assert.doesNotMatch(policy, /«Движению и фитнесу» или HealthKit/);

  for (const file of ["APP_PRIVACY.md", "REVIEW_NOTES.md"]) {
    const text = await readFile(`${ios}/AppStore/${file}`, "utf8");
    assert.match(text, /read-only/i, file);
    assert.match(text, /Apple Health/, file);
    assert.doesNotMatch(text, /or HealthKit access\./, file);
    assert.doesNotMatch(text, /microphone, HealthKit, Motion/, file);
  }
});
