import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import test from "node:test";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");
const contract = JSON.parse(read("shared/voice-workout-v1.json"));
const voice = require(path.join(root, "pwa", "voice-workout.js"));
const vocabulary = JSON.parse(read("shared/exercise-search-vocabulary.json"));

function fixtureExercises(caseDefinition) {
  const keys = caseDefinition.fixtures ?? contract.defaultFixtures;
  return keys.map((key) => {
    const fixture = contract.fixtureExercises[key];
    return {
      ...fixture,
      fixtureKey: key,
      aliases: fixture.catalogKey ? vocabulary.aliasesByKey[fixture.catalogKey] ?? [] : []
    };
  });
}

function transcriptFor(caseDefinition) {
  if (caseDefinition.transcriptRepeat) {
    return caseDefinition.transcriptRepeat.text.repeat(caseDefinition.transcriptRepeat.count);
  }
  return caseDefinition.transcript;
}

function expectedSets(sets) {
  if (Array.isArray(sets)) return sets;
  return Array.from({ length: sets.repeat }, () => sets.set);
}

test("voice contract fixes one on-device, bounded, cross-client format", () => {
  assert.equal(contract.version, 1);
  assert.deepEqual(contract.clients, ["android", "ios", "pwa"]);
  assert.equal(contract.privacy.recognition, "onDeviceOnly");
  assert.equal(contract.privacy.storesAudio, false);
  assert.equal(contract.privacy.storesTranscript, false);
  assert.equal(contract.privacy.unavailableFallback, "manualTextEntry");
  assert.deepEqual({ ...voice.LIMITS }, contract.limits);
  assert.deepEqual({ ...voice.LOCALES }, contract.locales);
  assert.equal(voice.CONTAINS_MATCH_MINIMUM_LENGTH, contract.rules.containsMatchMinimumLength);
});

test("PWA voice tables equal the shared contract", () => {
  const rules = contract.rules;
  assert.deepEqual([...voice.SEPARATOR_PHRASES], rules.separatorPhrases);
  assert.deepEqual([...voice.SET_WORDS], rules.setWords);
  assert.deepEqual([...voice.REP_WORDS], rules.repWords);
  assert.deepEqual([...voice.WEIGHT_WORDS], rules.weightWords);
  assert.deepEqual([...voice.WEIGHT_PREFIX_WORDS], rules.weightPrefixWords);
  assert.deepEqual([...voice.CONNECTOR_WORDS], rules.connectorWords);
  assert.deepEqual(JSON.parse(JSON.stringify(voice.NUMBER_WORDS)), rules.numberWords);
  assert.deepEqual(JSON.parse(JSON.stringify(voice.VOICE_ALIASES)), rules.voiceAliases);
});

for (const caseDefinition of contract.cases) {
  test(`PWA voice golden case ${caseDefinition.id}`, () => {
    const exercises = fixtureExercises(caseDefinition);
    const result = voice.parse(transcriptFor(caseDefinition), exercises);
    const fixtureById = new Map(exercises.map((exercise) => [exercise.id, exercise.fixtureKey]));
    const blockIndex = new Map(result.blocks.map((block, index) => [block.id, index]));

    assert.equal(result.blocks.length, caseDefinition.blocks.length, "block count");
    caseDefinition.blocks.forEach((expected, index) => {
      const block = result.blocks[index];
      assert.equal(block.exerciseId ? fixtureById.get(block.exerciseId) : null, expected.exercise, `block ${index} exercise`);
      assert.equal(block.match, expected.match, `block ${index} match`);
      if (expected.candidates) {
        assert.deepEqual(block.candidates.map((candidate) => fixtureById.get(candidate.id)).sort(), [...expected.candidates].sort());
      }
      assert.deepEqual(block.sets.map((set) => [set.weight, set.reps]), expectedSets(expected.sets), `block ${index} sets`);
    });
    const diagnostics = result.diagnostics.map((diagnostic) =>
      diagnostic.blockId === null ? diagnostic.kind : `${diagnostic.kind}:${blockIndex.get(diagnostic.blockId)}`);
    assert.deepEqual(diagnostics, caseDefinition.diagnostics);
  });
}

test("transcript truncation and weight input keep byte and number bounds", () => {
  const cyrillic = "ж".repeat(5000);
  const truncated = voice.truncateUtf8(cyrillic);
  assert.equal(voice.utf8Length(truncated) <= contract.limits.maxTranscriptBytes, true);
  assert.equal(truncated.length, 4096);
  assert.equal(voice.formatWeight(80), "80");
  assert.equal(voice.formatWeight(82.5), "82.5");
  assert.equal(voice.parseWeightInput("82,5"), 82.5);
  assert.equal(voice.parseWeightInput(""), null);
  assert.ok(Number.isNaN(voice.parseWeightInput("8a")));
  assert.equal(voice.parseRepsInput("12"), 12);
  assert.ok(Number.isNaN(voice.parseRepsInput("1.5")));
});

test("readiness ignores stale diagnostics once the user fixes a block", () => {
  const exercises = fixtureExercises({ id: "readiness" });
  const result = voice.parse("Bench press: 101 sets of 10 reps, 80 kilograms", exercises);
  assert.equal(result.blocks[0].sets.length, 100);
  assert.equal(voice.isBlockReady(result.blocks[0]), true);
  const missing = voice.parse("Mystery lift 40 for 10", exercises);
  assert.equal(voice.blockIssue(missing.blocks[0]), "chooseExercise");
  missing.blocks[0].exerciseId = exercises[0].id;
  assert.equal(voice.isBlockReady(missing.blocks[0]), true);
});

test("every client dictates on-device only and keeps the same entry point and privacy notice", () => {
  const ios = read("ios/GymApp-iOS/GymApp/Services/LocalVoiceTranscriptionService.swift");
  const iosSheet = read("ios/GymApp-iOS/GymApp/UI/Screens/VoiceWorkoutDraftSheet.swift");
  const iosEditor = read("ios/GymApp-iOS/GymApp/UI/Screens/AddWorkoutView.swift");
  const android = read("app/src/main/java/com/example/gymapp/ui/screens/VoiceWorkoutDraftSheet.kt");
  const androidEditor = read("app/src/main/java/com/example/gymapp/ui/screens/AddWorkoutScreen.kt");
  const manifest = read("app/src/main/AndroidManifest.xml");
  const pwa = read("pwa/app.js");
  const worker = read("pwa/sw.js");

  assert.match(ios, /request\.requiresOnDeviceRecognition = true/);
  assert.match(ios, /guard recognizer\.supportsOnDeviceRecognition/);
  assert.match(android, /SpeechRecognizer\.createOnDeviceSpeechRecognizer\(context\)/);
  assert.doesNotMatch(android, /SpeechRecognizer\.createSpeechRecognizer\(/);
  assert.match(manifest, /android\.permission\.RECORD_AUDIO/);
  assert.match(pwa, /recognition\.processLocally = true/);
  assert.match(pwa, /processLocally: true/);
  assert.doesNotMatch(pwa, /webkitSpeechRecognition/);
  assert.match(worker, /microphone=\(self\)/);
  assert.doesNotMatch(worker, /camera=\(self\)|geolocation=\(self\)/);

  const notice = "Audio and transcript stay on this device and are not saved.";
  assert.ok(iosSheet.includes(notice));
  assert.ok(pwa.includes(notice));
  assert.match(read("app/src/main/res/values/strings.xml"), /voice_workout_privacy">Audio and transcript stay on this device and are not saved\./);
  assert.match(iosEditor, /showingVoiceWorkoutDraft = true/);
  assert.match(androidEditor, /showVoiceWorkoutSheet = true/);
  assert.match(pwa, /data-action="open-voice-workout"/);
  for (const source of [iosSheet, android, pwa]) assert.match(source, /Replace current plan\?|voice_workout_replace_title/);
});

test("training programs stay paused behind one flag on every client while storage cleanup remains", () => {
  const androidHub = read("app/src/main/java/com/example/gymapp/ui/screens/ProgressHubScreen.kt");
  const pwa = read("pwa/app.js");
  const iosHub = read("ios/GymApp-iOS/GymApp/UI/Screens/ProgressView.swift");
  const iosStore = read("ios/GymApp-iOS/GymApp/Data/WorkoutStore.swift");
  assert.match(androidHub, /internal const val TRAINING_PROGRAM_ENABLED = false/);
  assert.match(pwa, /const TRAINING_PROGRAM_ENABLED = false;/);
  assert.doesNotMatch(iosHub, /case program\b/);
  assert.match(iosStore, /TrainingProgramStore\.storageURL\(\s*forWorkoutStorageURL: primaryURL/);
  assert.match(pwa, /const trainingProgram = trainingProgramDescriptor\(account\);/);
});
