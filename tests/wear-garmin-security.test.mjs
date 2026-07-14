import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(path, "utf8");

test("Wear sync rejects malformed payloads before destructive replacement", async () => {
  const [parser, listener, client, bindingStorage, catalogStorage, planStorage, pendingStorage, stageStorage, viewModel, paths] = await Promise.all([
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchSyncJson.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchSyncListenerService.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WearSyncClient.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchSyncBindingStorage.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchExerciseCatalogStorage.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchPlanStorage.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchPendingWorkoutStorage.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchSyncStageStorage.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/ui/WearWorkoutViewModel.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/SyncPaths.kt")
  ]);

  assert.match(parser, /sealed interface WatchSyncParseResult/);
  assert.match(parser, /MAX_SYNC_TOTAL_SETS/);
  assert.match(parser, /MAX_JSON_NESTING = 32/);
  assert.doesNotMatch(parser, /parseFullSyncPayload[\s\S]{0,4000}getOrElse\s*\{\s*emptyList/);
  assert.match(listener, /parsed !is WatchSyncParseResult\.Valid/);
  assert.match(listener, /envelope\.revision < previousRevision/);
  assert.match(listener, /binding\.sourceNodeId != sourceNodeId/);
  assert.match(listener, /WatchSyncAckRegistry\.complete/);
  assert.match(listener, /Channel<QueuedMessage>\(capacity = MAX_PENDING_MESSAGES\)/);
  assert.match(listener, /MAX_PENDING_MESSAGES = 8/);
  assert.match(listener, /binding\.sourceNodeId != messageEvent\.sourceNodeId/);
  assert.match(listener, /inboundMessages\.trySend/);
  assert.doesNotMatch(listener, /onMessageReceived[\s\S]{0,1600}serviceScope\.launch/);
  assert.doesNotMatch(client, /nodes\.forEach/);
  assert.match(client, /resolveTrustedNode/);
  assert.match(client, /withTimeout\(30_000L\)/);
  assert.match(listener, /WatchSyncStageStorage\.stageFullSync[\s\S]*replaceSessionsFromSync[\s\S]*revision = envelope\.revision[\s\S]*clearFullSyncIfMatches/);
  assert.match(listener, /WatchSyncStageStorage\.stagePlan[\s\S]*WatchPlanStorage\.save[\s\S]*acceptPlan[\s\S]*clearPlanIfMatches/);
  assert.match(stageStorage, /\.putString\(key, raw\)[\s\S]*\.commit\(\)/);
  assert.match(stageStorage, /accountGeneration in 1L\.\.SyncPaths\.MAX_PROTOCOL_COUNTER/);
  assert.match(stageStorage, /revision in 1L\.\.SyncPaths\.MAX_PROTOCOL_COUNTER/);
  assert.match(bindingStorage, /binding\.accountGeneration == accountGeneration/);
  assert.match(bindingStorage, /registerOnSharedPreferenceChangeListener\(listener\)[\s\S]*trySend\(load\(appContext\)\)/);
  assert.match(catalogStorage, /\.commit\(\)/);
  assert.doesNotMatch(catalogStorage, /\.apply\(\)/);
  assert.match(catalogStorage, /registerOnSharedPreferenceChangeListener\(listener\)[\s\S]*trySend\(load\(appContext\)\)/);
  assert.match(planStorage, /registerOnSharedPreferenceChangeListener\(listener\)[\s\S]*trySend\(prefs\.getString/);
  assert.match(paths, /MAX_PROTOCOL_COUNTER = 9_007_199_254_740_991L/);
  assert.match(parser, /accountGeneration in 1L\.\.SyncPaths\.MAX_PROTOCOL_COUNTER/);
  assert.match(pendingStorage, /KEY_DRAFT_ID/);
  assert.match(pendingStorage, /KEY_DRAFT_JSON/);
  assert.match(pendingStorage, /KEY_SOURCE_PLAN_RAW/);
  assert.match(client, /return pending/);
  assert.match(client, /sendMutation\(SyncPaths\.CREATE_WORKOUT[\s\S]*return pending[\s\S]*catch \(rejected: MutationRejectedException\)[\s\S]*clearIfMatches/);
  assert.match(viewModel, /WatchPendingWorkoutStorage\.clearIfMatches\(appContext, pendingMutation\)/);
  assert.match(viewModel, /currentAccountBinding\(\)/);
  assert.match(client, /WatchSyncBindingStorage\.load\(appContext\) == expectedBinding/);
});

test("Wear private state is excluded from backup and device transfer", async () => {
  const [manifest, extractionRules, legacyRules] = await Promise.all([
    read("wear/src/main/AndroidManifest.xml"),
    read("wear/src/main/res/xml/wear_data_extraction_rules.xml"),
    read("wear/src/main/res/xml/wear_backup_rules.xml")
  ]);

  assert.match(manifest, /android:allowBackup="false"/);
  assert.match(manifest, /com\.google\.android\.gms\.wearable\.MESSAGE_RECEIVED/);
  assert.match(manifest, /android:pathPrefix="\/gym\/sync\/"/);
  assert.match(extractionRules, /<device-transfer>/);
  assert.match(extractionRules, /domain="database" path="\."/);
  assert.match(extractionRules, /domain="sharedpref" path="\."/);
  assert.match(legacyRules, /domain="database" path="\."/);
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
  assert.match(store, /maxPendingWorkouts = 2/);
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
  assert.match(store, /cloudRevision < stagedCloudPlanRevision/);
  assert.match(store, /phoneRevision < stagedPhoneSyncRevision/);
  assert.doesNotMatch(store, /revisionStatus == 0 \|\| containsName/);
  assert.match(store, /applyPhoneSync/);
  assert.match(store, /applyCloudSync/);
  assert.match(store, /isValidCounter\(message\.get\("syncRevision"\), maxPhoneSyncRevision\)/);
  assert.match(store, /deferredSync = safeMessage/);
  assert.match(store, /hasOnlySyncKeys\(message, trustedSource\)/);
  assert.match(store, /message\.size\(\) > 14/);
  assert.match(store, /var safeMessage = normalizedSyncMessage\(message, bindingSource\)/);
  assert.match(store, /"planNames" => copySyncArray\(message\.get\("planNames"\)\)/);
  assert.match(store, /legacyUnboundState/);
  assert.match(store, /ensureLegacyQuarantine\(\)/);
  assert.match(store, /Storage\.setValue\("legacyQuarantinePending"/);
  assert.match(store, /Storage\.setValue\("legacyQuarantineVersion", 1\)/);
  assert.match(store, /Storage\.setValue\("legacyQuarantineCurrent", snapshot\)/);
  assert.match(store, /refreshLegacyCurrentQuarantine\(\)[\s\S]*Storage\.setValue\("legacyQuarantineVersion", 1\)/);
  assert.match(store, /Storage\.deleteValue\("legacyQuarantineCurrent"\)/);
  assert.match(store, /restoreLegacyCurrentQuarantine\(\)/);
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
  assert.match(androidManager, /cacheAndPushPlan[\s\S]*syncPayload\(exerciseCatalog, plan, syncId, resetWorkout = false\)/);
  assert.match(androidManager, /pushSyncForContext[\s\S]*syncPayload\(exercises, plan, syncId, resetWorkout = false\)/);
  assert.match(androidManager, /sendPendingAuthResetIfPossible[\s\S]*exercises = emptyList\(\)[\s\S]*plan = emptyList\(\)[\s\S]*resetWorkout = true/);
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
  assert.match(view, /GymStore\.canQueueWorkout\(message\)/);
  assert.match(view, /if \(!GymStore\.hasAccountBinding\(\) \|\| GymStore\.pending\.size\(\) == 0\)/);
  assert.match(view, /if \(!GymStore\.queueWorkout\(message\)\)/);
  assert.match(view, /if \(finishWorkout\(\)\) \{[\s\S]*GymSession\.stopAndSave\(\)/);
  assert.doesNotMatch(view, /if \(!GymSession\.recording\) \{\s*GymStore\.clearActiveWorkout\(\)/);
  assert.match(app, /GymStore\.applyPhoneSync\(message\)/);
  assert.match(app, /"syncRevision" => syncRevision\.toLong\(\)/);
  assert.match(view, /GymStore\.applyCloudSync\(message\)/);
});
