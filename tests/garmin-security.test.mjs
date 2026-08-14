import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(path, "utf8");

test("Android release keeps Garmin broadcast Parcelable class names", async () => {
  const rules = await read("app/proguard-rules.pro");

  for (const className of ["IQDevice", "IQApp", "IQMessage"]) {
    assert.match(
      rules,
      new RegExp(`-keep class com\\.garmin\\.android\\.connectiq\\.${className} \\{ \\*; \\}`)
    );
  }
});

test("Garmin messages are bounded, account-bound, replay-aware, and acked by id", async () => {
  const [store, app, comm, view, session, androidManager] = await Promise.all([
    read("garmin/source/GymStore.mc"),
    read("garmin/source/GymApp.mc"),
    read("garmin/source/GymComm.mc"),
    read("garmin/source/WorkoutView.mc"),
    read("garmin/source/GymSession.mc"),
    read("app/src/main/java/com/example/gymapp/garmin/GarminSyncManager.kt")
  ]);

  assert.match(store, /maxPlanSets = 60/);
  assert.match(store, /maxWorkoutSets = 60/);
  assert.match(store, /maxPendingWorkouts = 8/);
  assert.match(store, /maxPendingNameBytes = 12000/);
  assert.match(store, /maxTotalNameBytes = 12000/);
  assert.match(store, /toUtf8Array\(\)\.size\(\)/);
  assert.match(store, /flatNames\.size\(\) != flatWeights\.size\(\)/);
  assert.match(store, /processedSyncIds/);
  assert.match(store, /stateOwnerBinding/);
  assert.match(store, /queuedActiveRequestId/);
  assert.match(store, /Storage\.setValue\("pending", nextPending\)/);
  assert.match(store, /maxEstimatedStoreBytes = 24000/);
  assert.match(store, /lastPhoneSyncRevision/);
  assert.match(store, /lastCloudPlanRevision/);
  assert.match(store, /phoneSyncStage/);
  assert.match(store, /cloudSyncStage/);
  assert.match(store, /if \(!stageSync\(safeMessage, bindingSource\)\)/);
  assert.match(store, /var revisionStatus = syncRevisionStatus\(safeMessage, bindingSource\)[\s\S]*stageSync\(safeMessage, bindingSource\)[\s\S]*if \(accountChanged \|\| resetWorkout\)/);
  assert.match(store, /clearSyncStageIfMatches\(safeMessage, bindingSource\)/);
  assert.match(store, /stagedPhoneSyncRevision > 0l/);
  assert.match(store, /lastPhoneSyncAccountBinding/);
  assert.doesNotMatch(
    store.match(/static function clearAccountScopedState\(\) \{[\s\S]*?\n    \}/)?.[0] || "",
    /lastPhoneSyncRevision = 0l|lastPhoneSyncId = null/
  );
  assert.match(
    store.match(/static function clearAccountScopedState\(\) \{[\s\S]*?\n    \}/)?.[0] || "",
    /Storage\.deleteValue\("activeWorkoutV1"\)/
  );
  assert.match(store, /cloudRevision < stagedCloudPlanRevision/);
  assert.match(store, /phoneRevision < stagedPhoneSyncRevision/);
  assert.doesNotMatch(store, /revisionStatus == 0 \|\| containsName/);
  assert.match(store, /applyPhoneSync/);
  assert.match(store, /applyCloudSync/);
  assert.match(store, /isValidCounter\(message\.get\("syncRevision"\), maxPhoneSyncRevision\)/);
  assert.match(store, /deferredSync = safeMessage/);
  assert.match(store, /hasOnlySyncKeys\(message, trustedSource\)/);
  assert.match(store, /message\.size\(\) > 15/);
  assert.match(store, /key\.equals\("pairingGeneration"\)/);
  assert.match(store, /key\.equals\("repairPairing"\)/);
  assert.match(store, /repairPairing &&[\s\S]*accountChanged[\s\S]*status = "BAD BIND"/);
  assert.match(store, /rotatePairingGenerationForPending/);
  assert.match(store, /applyValidatedLanguage\(safeMessage\)[\s\S]*if \(sets\.size\(\) > 0\)/);
  assert.match(comm, /"pairingGenerationSupported" => true/);
  assert.match(store, /var safeMessage = normalizedSyncMessage\(message, bindingSource\)/);
  assert.match(store, /"planNames" => copySyncArray\(message\.get\("planNames"\)\)/);
  assert.match(store, /legacyUnboundState/);
  assert.match(store, /ensureLegacyQuarantine\(\)/);
  assert.match(store, /Storage\.setValue\("legacyQuarantinePending"/);
  assert.match(store, /Storage\.setValue\("legacyQuarantineVersion", 1\)/);
  assert.match(store, /Storage\.setValue\("legacyQuarantineCurrent", snapshot\)/);
  assert.match(store, /refreshLegacyCurrentQuarantine\(\)[\s\S]*Storage\.setValue\("legacyQuarantineVersion", 1\)/);
  assert.match(store, /Storage\.deleteValue\("legacyQuarantineCurrent"\)/);
  assert.match(store, /restoreLegacyCurrentQuarantine\(legacyUnboundUpgrade && !hasLegacyMarker\)/);
  assert.match(store, /ensureLegacyQuarantine\(\) \|\| !refreshLegacyCurrentQuarantine\(\)/);
  assert.match(store, /refreshLegacyCurrentQuarantine\(\)[\s\S]*Storage\.setValue\("exercises", exercises\)/);
  assert.match(store, /legacyRawPending = legacyUnboundState \? savedPending : null/);
  assert.match(store, /maxLegacyStoredValueBytes = 32768/);
  assert.match(store, /isValidLegacyPendingList/);
  assert.match(store, /removePendingByRequestId/);
  assert.match(store, /bindingSource\.equals\("cloud"\) && accountBinding != null && accountChanged/);
  assert.match(store, /var resetWorkout = bindingSource\.equals\("phone"\)[\s\S]*resetValue instanceof Lang\.Boolean && resetValue/);
  assert.match(store, /bindingSource\.equals\("phone"\) && accountBinding != null &&[\s\S]*accountChanged && !resetWorkout[\s\S]*status = "BAD BIND"/);
  assert.match(store, /bindingSource\.equals\("cloud"\) && stagedPhoneSyncRevision > 0l &&[\s\S]*!hasAccountBinding\(\)[\s\S]*status = "BAD BIND"/);
  assert.match(store, /var revisionStatus = syncRevisionStatus\(safeMessage, bindingSource\)[\s\S]*stageSync\(safeMessage, bindingSource\)[\s\S]*if \(accountChanged \|\| resetWorkout\)/);
  assert.match(store, /revisionStatus == 0[\s\S]*isExactStagedSync\(safeMessage, bindingSource\)[\s\S]*!syncBindingsMatch\(safeMessage\)[\s\S]*revisionStatus = 1/);
  assert.match(store, /resetWorkout &&[\s\S]*!trustedSource\.equals\("phone"\)[\s\S]*flatNames\.size\(\) != 0[\s\S]*syncedExercises\.size\(\) != 0/);
  assert.match(store, /if \(accountChanged \|\| resetWorkout\)[\s\S]*clearAccountScopedState\(\)[\s\S]*GymSession\.resetForAccountTransition\(\)[\s\S]*if \(sets\.size\(\) > 0\)/);
  assert.match(store, /bindingSource\.equals\("phone"\) &&[\s\S]*!clearCloudSyncStageForAccountTransition\(\)[\s\S]*clearAccountScopedState\(\)[\s\S]*return false/);
  assert.match(store, /static function clearCloudSyncStageForAccountTransition\(\)[\s\S]*Storage\.deleteValue\("cloudSyncStage"\)[\s\S]*stagedCloudPlanRevision = 0/);
  const saveBody = store.match(/static function save\(\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.ok(
    saveBody.indexOf('Storage.setValue("phoneSyncFence"') >= 0 &&
      saveBody.indexOf('Storage.setValue("phoneSyncFence"') <
        saveBody.indexOf('Storage.setValue("stateOwnerBinding", accountBinding)'),
    "the replay fence must precede the owner commit point"
  );
  assert.match(store, /"message" => stagedMessage/);
  assert.match(store, /isValidSyncStage\(stage, maximum, source\)/);
  assert.match(store, /stagedCloudSyncMessage = stagedMessage/);
  assert.match(store, /stagedPhoneSyncMessage = stagedMessage/);
  assert.match(store, /static function isExactStagedSync\(message, source\)[\s\S]*stagedCloudAccountBinding[\s\S]*syncMessagesEqual\(stagedCloudSyncMessage, message, source\)[\s\S]*stagedPhoneAccountBinding[\s\S]*syncMessagesEqual\(stagedPhoneSyncMessage, message, source\)/);
  const stagedEquality = store.match(/static function syncMessagesEqual\(left, right, source\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.match(stagedEquality, /left\.get\("deviceBinding"\), right\.get\("deviceBinding"\)/);
  assert.match(stagedEquality, /left\.get\("resetWorkout"\), right\.get\("resetWorkout"\)/);
  assert.match(stagedEquality, /left\.get\("repairPairing"\), right\.get\("repairPairing"\)/);
  assert.match(stagedEquality, /left\.get\("planNames"\), right\.get\("planNames"\)/);
  assert.match(stagedEquality, /left\.get\("planWeights"\), right\.get\("planWeights"\)/);
  assert.match(stagedEquality, /left\.get\("planReps"\), right\.get\("planReps"\)/);
  assert.match(store, /static function sameNumericArray\(left, right, compareAsFloat\)[\s\S]*if \(compareAsFloat\)[\s\S]*!isNumeric\(left\[i\]\) \|\| !isNumeric\(right\[i\]\)[\s\S]*left\[i\]\.toFloat\(\) != right\[i\]\.toFloat\(\)/);
  assert.match(store, /static function isNumeric\(value\)[\s\S]*value instanceof Lang\.Float[\s\S]*value instanceof Lang\.Double/);
  assert.match(store, /static function isValidSyncStage\(value, maximum, source\)[\s\S]*value\.size\(\) != 4[\s\S]*isValidSyncMessage\(value\.get\("message"\), source\)[\s\S]*estimatedValueBytes\(value\) > maxLegacyStoredValueBytes/);
  const revisionStatus = store.match(/static function syncRevisionStatus\(message, source\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.match(revisionStatus, /cloudRevision == stagedCloudPlanRevision &&\s*!isExactStagedSync\(message, source\)/);
  assert.match(revisionStatus, /phoneRevision == stagedPhoneSyncRevision &&\s*!isExactStagedSync\(message, source\)/);
  assert.match(revisionStatus, /stagedCloudAccountBinding != null[\s\S]*!stagedCloudAccountBinding\.toString\(\)\.equals\(messageAccount\)[\s\S]*return -1/);
  const transitionBody = store.match(/static function beginAccountTransition\(\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.match(transitionBody, /Storage\.deleteValue\("stateOwnerBinding"\);\s*stateOwnerBinding = null/);
  assert.match(transitionBody, /catch \(e\) \{[\s\S]*clearAccountScopedState\(\)[\s\S]*GymSession\.resetForAccountTransition\(\)/);
  const sessionReset = session.match(/static function resetForAccountTransition\(\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.match(sessionReset, /discard\(\)/);
  assert.match(sessionReset, /recording = false/);
  assert.doesNotMatch(sessionReset, /start\(\)/);
  const sessionStart = session.match(/static function start\(\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.match(sessionStart, /startedAt = Time\.now\(\)\.value\(\)/);
  assert.match(sessionStart, /hr = null/);
  assert.match(sessionStart, /garminCalories = null/);
  const sessionTick = session.match(/static function tick\(\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.match(sessionTick, /var appliedActivityHeartRate = updateGarminActivityInfo\(\)/);
  assert.match(sessionTick, /var sampledSensorHeartRate = readHeartRateFromSensor\(\)/);
  assert.match(
    sessionTick,
    /if \(!appliedActivityHeartRate\)[\s\S]*applyHeartRate\(sampledSensorHeartRate\)[\s\S]*expireStaleHeartRate\(\)/
  );
  const activityInfo = session.match(/static function updateGarminActivityInfo\(\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.match(activityInfo, /appliedHeartRate = applyHeartRate\(info\.currentHeartRate\)/);
  assert.match(activityInfo, /return appliedHeartRate/);
  assert.match(
    store,
    /var messageStartedAt = isValidWorkoutStartedAtSeconds\(activeWorkoutStartedAtSeconds\) \?[\s\S]*activeWorkoutStartedAtSeconds : GymSession\.startedAt/
  );
  assert.match(store, /"startedAtSeconds" => messageStartedAt/);
  assert.doesNotMatch(store, /"startedAtSeconds" => Time\.now\(\)\.value\(\)/);
  assert.match(androidManager, /cacheAndPushPlan[\s\S]*garminPlanRequestFingerprint\([\s\S]*planSubmissionCoalescer\.submit/);
  assert.match(androidManager, /sendToConnectedDevicesLocked[\s\S]*GarminPlanSubmissionKey\([\s\S]*prepareExactPlanSubmission\(submissionKey\)[\s\S]*materializeGarminPlanSubmissionPayload/);
  assert.doesNotMatch(
    androidManager.match(/suspend fun cacheAndPushPlan\([\s\S]*?\n    \/\*\*/)?.[0] || "",
    /newGarminMessageId|allocateSyncRevision/
  );
  assert.match(androidManager, /pushSyncForContext[\s\S]*repairPairing = repairPairing/);
  assert.match(androidManager, /advertisesGeneration &&[\s\S]*garminSyncRequestCanRepairPairing[\s\S]*repairPairing = true/);
  assert.match(androidManager, /sendPendingAuthResetIfPossible[\s\S]*exercises = emptyList\(\)[\s\S]*plan = emptyList\(\)[\s\S]*resetWorkout = true/);
  assert.match(
    androidManager,
    /registerForDeviceEvents\(device\)[\s\S]*runCatching \{[\s\S]*refreshDeviceUiState\(\)[\s\S]*onFailure \{ error ->[\s\S]*Rejected malformed Garmin device callback/
  );
  assert.match(
    androidManager,
    /registerForAppEvents\(device, garminApp\)[\s\S]*runCatching \{[\s\S]*boundedGarminInboundEnvelopes\(messages\)[\s\S]*Rejected malformed Garmin app callback/
  );
  assert.match(androidManager, /MAX_PROFILE_GARMIN_DEVICES = 8/);
  assert.match(androidManager, /MAX_PROFILE_DEVICE_NAME_CHARS = 80/);
  assert.match(store, /isValidAccountBinding[\s\S]*code >= 97 && code <= 102/);
  assert.doesNotMatch(store, /pending\.remove\(i\)/);
  assert.doesNotMatch(app, /pending\.remove\(0\)/);
  assert.match(app, /GymStore\.bindingsMatch\(message\)/);
  assert.match(app, /syncId\.toString\(\)\.equals\(requestId\.toString\(\)\)/);
  assert.match(app, /"bindingVersion" => GymStore\.bindingVersion/);
  assert.match(comm, /"accountBinding" => accountBinding\.toString\(\)/);
  assert.match(comm, /"bindingSource" => "cloud"/);
  assert.match(comm, /if \(!GymStore\.hasAccountBinding\(\)\)/);
  assert.match(comm, /orderIndex != s/);
  assert.match(comm, /"action" => "ackPlan"/);
  assert.match(comm, /"planId" => planId\.toString\(\)/);
  assert.match(view, /GymComm\.acknowledgeCloudPlan\(message/);
  assert.match(store, /static function queueWorkout\(message\)[\s\S]*canQueueWorkout\(message\)/);
  assert.doesNotMatch(view, /GymStore\.canQueueWorkout\(message\)/,
    "the queue owner must recognize a durable same-id retry before applying capacity");
  assert.match(view, /if \(!GymStore\.hasAccountBinding\(\) \|\| GymStore\.pending\.size\(\) == 0 \|\|[\s\S]*pendingSendInFlight\)/);
  assert.match(view, /if \(!GymStore\.queueWorkout\(message\)\)/);
  assert.match(
    view,
    /GymStore\.prepareWorkoutCommit\(\)[\s\S]*GymSession\.stopAndSave\(\)[\s\S]*GymStore\.markPreparedWorkoutFitSaved\(\)[\s\S]*finishWorkout\(\)/
  );
  assert.doesNotMatch(view, /if \(!GymSession\.recording\) \{\s*GymStore\.clearActiveWorkout\(\)/);
  assert.match(app, /GymStore\.applyPhoneSync\(message\)/);
  assert.match(app, /"syncRevision" => syncRevision\.toLong\(\)/);
  assert.match(app, /onSyncAckSent[\s\S]*sendNextPendingWorkout\(\)[\s\S]*GymStore\.pending\.size\(\) == 0[\s\S]*WAITING ACK/);
  assert.match(view, /GymStore\.applyCloudSync\(message\)/);
});

test("Garmin phone sync retries the same revision until an idempotent watch ack", async () => {
  const [manager, store, app] = await Promise.all([
    read("app/src/main/java/com/example/gymapp/garmin/GarminSyncManager.kt"),
    read("garmin/source/GymStore.mc"),
    read("garmin/source/GymApp.mc")
  ]);
  const confirmation = manager.match(
    /private suspend fun sendAndConfirmSync\([\s\S]*?\n    private suspend fun sendAndWait/
  )?.[0] || "";

  assert.match(manager, /GARMIN_SYNC_ACK_ATTEMPTS = 3/);
  assert.match(manager, /GARMIN_SYNC_ACK_ATTEMPT_TIMEOUT_MS = 10_000L/);
  assert.match(manager, /GARMIN_SYNC_TOTAL_TIMEOUT_MS = 40_000L/);
  assert.match(confirmation, /for \(attempt in 1\.\.GARMIN_SYNC_ACK_ATTEMPTS\)/);
  assert.match(confirmation, /sendAndWait\(device, payload\)/);
  assert.match(confirmation, /withTimeoutOrNull\(GARMIN_SYNC_TOTAL_TIMEOUT_MS\)/);
  assert.match(confirmation, /pendingSyncAcks\.remove\(syncId, pending\)/);
  assert.match(
    confirmation,
    /if \(!confirmed\)[\s\S]*Garmin watch did not acknowledge the sync after bounded retries/
  );
  assert.doesNotMatch(confirmation, /newGarminMessageId|allocateSyncRevision/);
  assert.match(store, /revisionStatus == 0[\s\S]*status = "SYNC DUP"[\s\S]*return true/);
  assert.match(app, /sendSyncAck\(message, applied\)/);

  let durableMutations = 0;
  let watchFence = null;
  const stableCommand = Object.freeze({ syncId: "stable-sync-id", revision: 42 });
  const receiveOnWatch = (command) => {
    if (watchFence?.syncId === command.syncId && watchFence.revision === command.revision) {
      return { applied: true, duplicate: true };
    }
    durableMutations += 1;
    watchFence = { ...command };
    return { applied: true, duplicate: false };
  };
  const ackDelivered = [false, true];
  let attempts = 0;
  let confirmed = false;
  while (!confirmed && attempts < 3) {
    const result = receiveOnWatch(stableCommand);
    confirmed = result.applied && ackDelivered[attempts] === true;
    attempts += 1;
  }
  assert.equal(confirmed, true);
  assert.equal(attempts, 2, "one lost acknowledgement triggers one bounded resend");
  assert.equal(durableMutations, 1, "the duplicate retry never reapplies the plan");

  const totalDeadlineMs = 40_000;
  const transportCallbackDeadlineMs = 90_000;
  const externallyVisibleCompletionMs = Math.min(
    totalDeadlineMs,
    transportCallbackDeadlineMs
  );
  assert.equal(
    externallyVisibleCompletionMs,
    40_000,
    "a missing Connect IQ send callback is cancelled by the outer deadline"
  );
});
