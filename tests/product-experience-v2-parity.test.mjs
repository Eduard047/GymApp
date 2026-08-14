import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const [contractSource, pwaSource, pwaRussianSource] = await Promise.all([
  readFile(new URL("shared/product-experience-v2.json", root), "utf8"),
  readFile(new URL("pwa/app.js", root), "utf8"),
  readFile(new URL("pwa/russian-text.js", root), "utf8")
]);
const contract = JSON.parse(contractSource);

test("product experience v2 defines one full-client navigation and tutorial", () => {
  assert.equal(contract.schemaVersion, 2);
  assert.equal(contract.productVersion, "3.0.10");
  assert.deepEqual(contract.fullClients, ["android", "ios", "pwa"]);
  assert.deepEqual(contract.navigation.fullClientTabOrder, [
    "today",
    "exercises",
    "progress",
    "profile"
  ]);
  assert.deepEqual(
    contract.tutorial.steps.map(step => step.id),
    ["todayFocus", "todayPrimaryAction", "exercises", "progress", "profile"]
  );
  assert.equal(contract.tutorial.automaticRunsPerAccountOrLocalProfile, 1);
  assert.equal(contract.tutorial.manualReplayPath, "profile.help.showTutorial");
  assert.equal(contract.tutorial.accountBound, true);
  assert.equal(contract.tutorial.lateOldAccountResult, "ignored");
  assert.ok(contract.tutorial.deferWhile.includes("pushOrDeepLinkTarget"));
  assert.ok(contract.tutorial.deferWhile.includes("activeWorkout"));
  assert.equal(contract.tutorial.accessibility.reducedMotionDisablesHaloAnimation, true);
});

test("today, first workout, and progress use the same information architecture", () => {
  assert.deepEqual(contract.firstWorkout.entryActionsInOrder, [
    "startPlan",
    "editPlan",
    "createManually"
  ]);
  assert.deepEqual(contract.todayFocusLens.states, [
    "recommendedPlan",
    "activeWorkout",
    "recovery"
  ]);
  assert.equal(contract.todayFocusLens.lifetimeMetricsPlacement, "progress.overview");
  assert.equal(contract.todayFocusLens.heatmapPlacement, "progress.overview");
  assert.equal(contract.todayFocusLens.muscleLoadPlacement, "progress.overview");
  assert.equal(contract.terminology.missionsPlacement, "progress.goals");
});

test("live mutation recovery and push navigation preserve confirmed server work", () => {
  assert.equal(
    contract.socialAndLive.successfulMutationRefreshFailure.state,
    "confirmedRestoring"
  );
  assert.equal(
    contract.socialAndLive.successfulMutationRefreshFailure.mustNotReportMutationFailure,
    true
  );
  assert.equal(contract.socialAndLive.liveAcceptance.visibleAction, "startTogether");
  assert.equal(
    contract.socialAndLive.liveAcceptance.authoritativeRoomStatusAfterAccept,
    "active"
  );
  assert.deepEqual(
    contract.socialAndLive.liveAcceptance.legacyMutationResponseStatusesAccepted,
    ["ready", "active"]
  );
  assert.equal(contract.socialAndLive.liveAcceptance.ownerOnlyStartActionVisible, false);
  assert.deepEqual(contract.socialAndLive.pushTarget.preserve, [
    "type",
    "opaqueObjectId",
    "revision",
    "accountBinding"
  ]);
  assert.equal(contract.socialAndLive.workoutInbox.listPayload, "metadataOnly");
  assert.equal(contract.socialAndLive.workoutInbox.maximumResponseBytes, 256 * 1024);
  assert.equal(contract.socialAndLive.workoutInbox.incomingPageSize, 10);
  assert.equal(contract.socialAndLive.workoutInbox.maximumPages, 2);
  assert.equal(contract.socialAndLive.workoutInbox.maximumIncomingItems, 20);
  assert.equal(contract.socialAndLive.workoutInbox.maximumOutgoingItems, 20);
  assert.equal(contract.socialAndLive.workoutInbox.maximumRenderedItems, 40);
  assert.equal(
    contract.socialAndLive.workoutInbox.loadMoreAction,
    "visibleOnlyWhenNextCursorExists"
  );
});

test("Garmin saves FIT before sync and exposes recoverable queue state", () => {
  assert.deepEqual(contract.garmin.finishTransaction.states, [
    "active",
    "prepared",
    "fitSaved",
    "queued",
    "acknowledged"
  ]);
  assert.equal(contract.garmin.finishTransaction.fitSaveBeforeQueue, true);
  assert.equal(contract.garmin.finishTransaction.discardNeverSendsPreparedWorkout, true);
  assert.equal(contract.garmin.finishTransaction.queueFailureNeverBlocksLocalFitSave, true);
  assert.equal(contract.garmin.sync.pendingCountVisible, true);
  assert.equal(contract.garmin.sync.automaticRetry, true);
  assert.equal(contract.garmin.tutorial.manualReplayPath, "settings.tutorial");
});

test("all visible contract copy is complete for EN, UK, and RU", () => {
  const localizedObjects = [
    contract.terminology.manualPlanAction,
    contract.terminology.tutorialAction,
    contract.terminology.liveAcceptAction,
    ...contract.tutorial.steps.flatMap(step => [step.title, step.body])
  ];
  for (const copy of localizedObjects) {
    assert.deepEqual(Object.keys(copy), ["en", "uk", "ru"]);
    for (const locale of ["en", "uk", "ru"]) {
      assert.equal(typeof copy[locale], "string");
      assert.ok(copy[locale].trim().length > 0);
    }
  }
});

test("PWA visible terminology implements the shared product experience", () => {
  assert.match(pwaSource, /tx\("Start plan", "Почати план"\)/);
  assert.match(pwaSource, /tx\("Edit plan", "Редагувати план"\)/);
  assert.match(pwaSource, /tx\("Create manually", "Створити вручну"\)/);
  assert.match(pwaSource, /goals:\s*\{[\s\S]*tx\("Goals", "Цілі"\)/);
  assert.match(pwaSource, /tx\("Start together", "Почати разом"\)/);
  assert.match(pwaRussianSource, /\["Start together", "Начать вместе"\]/);
  assert.match(pwaRussianSource, /\["Goals", "Цели"\]/);
  assert.match(pwaRussianSource, /\["Create manually", "Создать вручную"\]/);
});
