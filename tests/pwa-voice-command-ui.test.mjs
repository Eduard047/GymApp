// Source-level invariants for the in-workout voice set logging UI (Feature A1).
// This does not execute pwa/app.js (it's a browser script relying on `window`,
// `app`/DOM, etc.) — it asserts static properties of the source text that the
// PWA/trust-boundary rules and the task spec require, mirroring how
// tests/voice-workout-parity.test.mjs checks pwa/voice-workout.js.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const appJsPath = path.join(here, "..", "pwa", "app.js");
const source = readFileSync(appJsPath, "utf8");

function extractFunction(name) {
  const marker = `function ${name}(`;
  const start = source.indexOf(marker);
  assert.notEqual(start, -1, `expected to find function ${name} in pwa/app.js`);
  let depth = 0;
  let i = source.indexOf("{", start);
  const bodyStart = i;
  for (; i < source.length; i++) {
    if (source[i] === "{") depth++;
    else if (source[i] === "}") {
      depth--;
      if (depth === 0) return source.slice(bodyStart, i + 1);
    }
  }
  throw new Error(`unterminated function ${name}`);
}

test("voice logSet/repeatPrevious call the exact same recordActiveSet code path as the button", () => {
  const logSetBody = extractFunction("applyActiveSetVoiceLogSet");
  const repeatBody = extractFunction("applyActiveSetVoiceRepeatPrevious");
  assert.match(logSetBody, /recordActiveSet\(setId\)/);
  assert.match(repeatBody, /recordActiveSet\(setId\)/);

  // The visible "Log set" action in the active-workout screen is
  // data-action="record-active-set", which the dispatcher wires to the same
  // recordActiveSet(setId) function.
  assert.match(source, /data-action="record-active-set"/);
  assert.match(
    source,
    /if \(action === "record-active-set"\) \{[\s\S]{0,200}?return recordActiveSet\(setId\);/
  );
});

test("voice skipRest calls the same stopExerciseRestTimer path as the timer's Stop button", () => {
  const skipBody = extractFunction("applyActiveSetVoiceSkipRest");
  assert.match(skipBody, /stopExerciseRestTimer\(timerKey\)/);
  assert.match(
    source,
    /if \(action === "timer-stop"\) \{[\s\S]{0,200}?stopExerciseRestTimer\(el\.dataset\.key\)/
  );
});

test("no innerHTML assignment embeds a raw (unescaped) voice transcript", () => {
  // Every place a transcript-shaped value reaches markup, it must be escaped
  // (escapeHtml/escapeAttr) or handed to textContent (showToast), never
  // concatenated into an innerHTML string unescaped.
  const controlMarkup = extractFunction("activeSetVoiceControlMarkup");
  assert.match(controlMarkup, /escapeHtml\(listening\.transcript\)/);
  assert.match(controlMarkup, /escapeAttr\(manual\.text\)/);
  assert.doesNotMatch(controlMarkup, /\$\{listening\.transcript\}/);
  assert.doesNotMatch(controlMarkup, /\$\{manual\.text\}/);

  const commandBody = extractFunction("applyActiveSetVoiceCommand");
  // The unknown-intent transcript is shown via showToast (textContent), not innerHTML.
  assert.match(commandBody, /showToast\(/);
  assert.doesNotMatch(commandBody, /innerHTML/);
});

test("showToast (used for all voice command feedback) assigns textContent, not innerHTML", () => {
  const toastBody = extractFunction("showToast");
  assert.match(toastBody, /\.textContent\s*=/);
  assert.doesNotMatch(toastBody, /\.innerHTML\s*=/);
});

test("the voice transcript is never written to localStorage, IndexedDB, or logged", () => {
  const region = source.slice(
    source.indexOf("let activeSetVoice = null;"),
    source.indexOf("function trainingAdaptationLabels()")
  );
  assert.ok(region.length > 500, "expected the voice command region to be found");
  assert.doesNotMatch(region, /localStorage/);
  assert.doesNotMatch(region, /indexedDB/i);
  assert.doesNotMatch(region, /console\.(log|info|warn|error)/);
});

test("starting recognition reuses the on-device gate (processLocally) and availability/recognition helpers from plan dictation", () => {
  const startBody = extractFunction("startActiveSetVoiceCommand");
  assert.match(startBody, /voiceWorkoutAvailability\(\)/);
  assert.match(startBody, /voiceWorkoutRecognitionClass\(\)/);
  assert.match(startBody, /voiceWorkoutLocale\(\)/);
  assert.match(startBody, /processLocally\s*=\s*true/);
  assert.match(startBody, /availability\.status !== "available"/);
});

test("recognition and any manual-entry state are cleared when the active screen is left", () => {
  const lifecycleBody = extractFunction("syncActiveSetVoiceLifecycle");
  assert.match(lifecycleBody, /route\(\)\.name !== "active"/);
  assert.match(lifecycleBody, /clearActiveSetVoice\(\)/);

  const visibilityRegion = source.slice(
    source.indexOf('document.addEventListener?.("visibilitychange"'),
    source.indexOf('document.addEventListener?.("visibilitychange"') + 400
  );
  assert.match(visibilityRegion, /stopActiveSetVoiceRecognition\(\)/);
});

test("recognition auto-stops within the 60s command-mode limit from shared/voice-workout-command-v1.json", () => {
  const startBody = extractFunction("startActiveSetVoiceCommand");
  assert.match(startBody, /60_000/);
});

test("logSet/repeatPrevious command results are parsed with parseVoiceWorkoutCommand (in-workout contract), not parse() (plan dictation)", () => {
  const commandBody = extractFunction("applyActiveSetVoiceCommand");
  assert.match(commandBody, /window\.GymVoiceWorkout\.parseVoiceWorkoutCommand\(/);
});

test("the mic control is only rendered for the current, not-yet-completed set (same visibility as the Record set button)", () => {
  assert.match(
    source,
    /\$\{current && !set\.completed \? activeSetVoiceContainerMarkup\(setId\) : ""\}/
  );
});
