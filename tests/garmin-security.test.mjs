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

test("Wear sync rejects malformed payloads before destructive replacement", async () => {
  const [parser, listener, client, bindingStorage, catalogStorage, planStorage, pendingStorage, stageStorage, viewModel, paths, rules, draftStorage] = await Promise.all([
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchSyncJson.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchSyncListenerService.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WearSyncClient.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchSyncBindingStorage.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchExerciseCatalogStorage.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchPlanStorage.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchPendingWorkoutStorage.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchSyncStageStorage.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/ui/WearWorkoutViewModel.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/SyncPaths.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchBindingRules.kt"),
    read("wear/src/main/java/com/example/gymapp/wear/sync/WatchWorkoutDraftStorage.kt")
  ]);

  assert.match(parser, /sealed interface WatchSyncParseResult/);
  assert.match(parser, /MAX_SYNC_TOTAL_SETS/);
  assert.match(parser, /MAX_JSON_NESTING = 32/);
  assert.doesNotMatch(parser, /parseFullSyncPayload[\s\S]{0,4000}getOrElse\s*\{\s*emptyList/);
  assert.match(listener, /parsed !is WatchSyncParseResult\.Valid/);
  // Accept/reject decisions live in the pure WatchBindingRules (JVM-tested); the listener applies them.
  assert.match(listener, /WatchBindingRules\.decideFullSync\(/);
  assert.match(rules, /envelope\.revision < previousRevision/);
  // A new phone install (authority epoch) is accepted only when it is not older than the last accepted message.
  assert.match(rules, /binding\.authorityEpoch != envelope\.authorityEpoch[\s\S]{0,400}envelope\.sentAt < binding\.lastAcceptedSentAt\) return FullSyncDecision\.Reject/);
  // Another phone node is heard only as a relink candidate and never over work held for another owner.
  assert.match(rules, /relinkCandidateNodeId != sourceNodeId[\s\S]{0,200}FullSyncDecision\.Reject/);
  assert.match(rules, /heldOwnerId == null \|\| heldOwnerId == envelope\.ownerId/);
  // Sign-out and unlink arrive as a binding state without an owner; only the pinned phone may send it.
  assert.match(listener, /SyncPaths\.BINDING_STATE -> handleBindingState/);
  assert.match(parser, /"protocolVersion", "state", "authorityEpoch", "accountGeneration", "messageId", "sentAt"/);
  assert.match(rules, /fun decideBindingState[\s\S]{0,400}binding\.sourceNodeId != sourceNodeId\) return BindingStateDecision\.Reject/);
  // Work kept on the watch is never deleted by a binding change: only Discard or a delivered send.
  assert.doesNotMatch(bindingStorage, /WatchPendingWorkoutStorage|WatchWorkoutDraftStorage/);
  assert.doesNotMatch(listener, /WatchPendingWorkoutStorage\.clear|WatchWorkoutDraftStorage\.clear/);
  assert.doesNotMatch(viewModel, /fun resetAccountScopedEditor\(\) \{[\s\S]{0,200}Storage\.clear/);
  assert.match(draftStorage, /Only an unreadable draft is dropped/);
  assert.match(viewModel, /it\.ownerId == workOwnerId/);
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
  assert.match(viewModel, /pendingMutation\?\.let \{ WatchPendingWorkoutStorage\.clearIfMatches\(appContext, it\) \}/);
  assert.match(viewModel, /currentAccountBinding\(\)/);
  // A send is bound to node, owner and generation (not to sync revisions that may move meanwhile).
  assert.match(client, /WatchBindingRules\.sameSendIdentity\(\s*expectedBinding,\s*WatchSyncBindingStorage\.load\(appContext\)/);
  assert.match(rules, /current\.sourceNodeId == expected\.sourceNodeId &&\s*current\.ownerId == expected\.ownerId &&\s*current\.accountGeneration == expected\.accountGeneration/);
  // A workout is never sent to a relink candidate: only the sync request may go there.
  assert.match(client, /path = SyncPaths\.REQUEST_FULL_SYNC,[\s\S]{0,200}allowRelinkCandidate = true/);
  assert.equal((client.match(/allowRelinkCandidate = true/g) || []).length, 1);
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

test("Phone Wear listener only accepts /gym/sync/ messages bound to the pinned node and account", async () => {
  const [manifest, listener, binding, repo] = await Promise.all([
    read("app/src/main/AndroidManifest.xml"),
    read("app/src/main/java/com/example/gymapp/wearsync/PhoneWearSyncListenerService.kt"),
    read("app/src/main/java/com/example/gymapp/wearsync/PhoneWearBindingManager.kt"),
    read("app/src/main/java/com/example/gymapp/data/repository/GymRepository.kt")
  ]);

  assert.match(manifest, /android:name="\.wearsync\.PhoneWearSyncListenerService"[\s\S]*?com\.google\.android\.gms\.wearable\.MESSAGE_RECEIVED[\s\S]*?android:pathPrefix="\/gym\/sync\/"[\s\S]*?android:scheme="wear"/);
  assert.match(listener, /fastSourceMayBeTrusted/);
  assert.match(listener, /authorizeSource/);
  assert.match(binding, /connectedNodeIds\.size != 1 \|\| currentBinding\.signedOut/);
  assert.match(repo, /wearMutationDao\.deleteOlderThan\(/);
  assert.match(listener, /isPinnedNode\(sourceNodeId\)/);
  assert.match(repo, /WearMutationApplyResult\.AlreadyApplied/);
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
  assert.match(store,
    /isBoundedText\(value, maxExerciseNameLength\) &&\s*utf8Bytes\(value\)\.size\(\) <= maxExerciseNameBytes/,
    "exercise names retain both character-count and UTF-8 byte limits"
  );
  assert.match(store, /weights\.size\(\) != names\.size\(\) \|\|\s*setReps\.size\(\) != names\.size\(\)/,
    "plan columns must keep equal lengths (isValidPlanColumns)");
  assert.match(store, /isValidPlanColumns\(flatNames, flatWeights, flatReps, maxPlanSets\)/);
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
  assert.match(store, /repairPairing &&[\s\S]*accountChanged[\s\S]*status = GymStatus\.BAD_BIND/);
  assert.match(store, /rotatePairingGenerationForPending/);
  assert.match(store, /applyValidatedLanguage\(safeMessage\)[\s\S]*sets\.size\(\) > 0 \|\| GymSession\.recording \|\| hasUnfinishedWorkout\(\)/);
  assert.doesNotMatch(store, /stageSync\(message, source\)[\s\S]*normalizedSyncMessage\(message, source\)/);
  assert.match(store, /sameTextArray\(incomingExercises, exercises\)[\s\S]*safeMessage\.put\("exercises", null\)/);
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
  assert.match(store, /bindingSource\.equals\("phone"\) && accountBinding != null &&[\s\S]*accountChanged && !resetWorkout[\s\S]*status = GymStatus\.BAD_BIND/);
  assert.match(store, /bindingSource\.equals\("cloud"\) && stagedPhoneSyncRevision > 0l &&[\s\S]*!hasAccountBinding\(\)[\s\S]*status = GymStatus\.BAD_BIND/);
  assert.match(store, /var revisionStatus = syncRevisionStatus\(safeMessage, bindingSource\)[\s\S]*stageSync\(safeMessage, bindingSource\)[\s\S]*if \(accountChanged \|\| resetWorkout\)/);
  assert.match(store, /revisionStatus == 0[\s\S]*isExactStagedSync\(safeMessage, bindingSource\)[\s\S]*!syncBindingsMatch\(safeMessage\)[\s\S]*revisionStatus = 1/);
  assert.match(store, /resetWorkout &&[\s\S]*!trustedSource\.equals\("phone"\)[\s\S]*flatNames\.size\(\) != 0[\s\S]*syncedExercises\.size\(\) != 0/);
  assert.match(store, /if \(accountChanged \|\| resetWorkout\)[\s\S]*clearAccountScopedState\(\)[\s\S]*GymSession\.resetForAccountTransition\(\)[\s\S]*sets\.size\(\) > 0 \|\| GymSession\.recording \|\| hasUnfinishedWorkout\(\)/);
  assert.match(store, /bindingSource\.equals\("phone"\) &&[\s\S]*!clearCloudSyncStageForAccountTransition\(\)[\s\S]*clearAccountScopedState\(\)[\s\S]*return false/);
  assert.match(store, /static function clearCloudSyncStageForAccountTransition\(\)[\s\S]*Storage\.deleteValue\("cloudSyncStage"\)[\s\S]*stagedCloudPlanRevision = 0/);
  const saveBody = store.match(/static function save\(\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.ok(
    saveBody.indexOf('Storage.setValue("phoneSyncFence"') >= 0 &&
      saveBody.indexOf('Storage.setValue("phoneSyncFence"') <
        saveBody.indexOf('Storage.setValue("stateOwnerBinding", accountBinding)'),
    "the replay fence must precede the owner commit point"
  );
  assert.match(store, /"message" => message/);
  assert.match(store, /isValidSyncStage\(stage, maximum, source\)/);
  assert.match(store, /stagedCloudSyncMessage = message/);
  assert.match(store, /stagedPhoneSyncMessage = message/);
  assert.match(store, /static function isExactStagedSync\(message, source\)[\s\S]*stagedCloudAccountBinding[\s\S]*syncMessagesEqual\(stagedCloudSyncMessage, message, source\)[\s\S]*stagedPhoneAccountBinding[\s\S]*syncMessagesEqual\(stagedPhoneSyncMessage, message, source\)/);
  const stagedEquality = store.match(/static function syncMessagesEqual\(left, right, source\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.match(stagedEquality, /left\.get\("deviceBinding"\), right\.get\("deviceBinding"\)/);
  assert.match(stagedEquality, /left\.get\("resetWorkout"\), right\.get\("resetWorkout"\)/);
  assert.match(stagedEquality, /left\.get\("repairPairing"\), right\.get\("repairPairing"\)/);
  assert.match(stagedEquality, /left\.get\("planNames"\), right\.get\("planNames"\)/);
  assert.match(stagedEquality, /left\.get\("planWeights"\), right\.get\("planWeights"\)/);
  assert.match(stagedEquality, /left\.get\("planReps"\), right\.get\("planReps"\)/);
  assert.match(store, /static function sameNumericArray\(left, right, compareAsFloat\)[\s\S]*if \(compareAsFloat\)[\s\S]*!isNumeric\(left\[i\]\) \|\| !isNumeric\(right\[i\]\)[\s\S]*left\[i\] as Lang\.Numeric\)\.toDouble\(\)[\s\S]*right\[i\] as Lang\.Numeric\)\.toDouble\(\)/);
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
  assert.match(sessionStart, /resetWorkoutMetrics\(\)/);
  assert.match(sessionReset, /resetWorkoutMetrics\(\)/);
  const metricReset = session.match(/static function resetWorkoutMetrics\(\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.match(metricReset, /hr = null/);
  assert.match(metricReset, /garminCalories = null/);
  const sessionTick = session.match(/static function tick\([^)]*\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.match(sessionTick, /var appliedActivityHeartRate = updateGarminActivityInfo\(\)/);
  assert.match(sessionTick, /var sampledSensorHeartRate = null/);
  assert.match(
    sessionTick,
    /if \(GymStore\.keepsSetDiagnostics \|\| !appliedActivityHeartRate\) \{\s*sampledSensorHeartRate = readHeartRateFromSensor\(\);/
  );
  assert.match(
    sessionTick,
    /if \(!appliedActivityHeartRate\)[\s\S]*applyHeartRate\(sampledSensorHeartRate\)[\s\S]*expireStaleHeartRate\(\)/
  );
  const activityInfo = session.match(/static function updateGarminActivityInfo\(\) \{[\s\S]*?\n    \}/)?.[0] || "";
  assert.match(activityInfo,
    /if \(isValidHeartRate\(info\.currentHeartRate\)\) \{\s*activityHr = info\.currentHeartRate;/,
    "only a validated activity heart rate is retained"
  );
  assert.match(activityInfo,
    /info = null;[\s\S]*if \(activityHr != null\) \{[\s\S]*appliedHeartRate = applyHeartRate\(activityHr\)/,
    "release the large activity object before applying its cached reading"
  );
  assert.match(activityInfo, /return appliedHeartRate/);
  assert.match(
    store,
    /var messageStartedAt = isValidWorkoutStartedAtSeconds\(activeWorkoutStartedAtSeconds\) \?[\s\S]*activeWorkoutStartedAtSeconds :[\s\S]*runtimeWorkoutStartedAtSeconds : GymSession\.startedAt/
  );
  assert.match(store, /"startedAtSeconds" => context\[4\]/);
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
  assert.match(view, /if \(!GymStore\.hasAccountBinding\(\) \|\| GymStore\.pendingCount\(\) == 0 \|\|[\s\S]*pendingSendInFlight\)/);
  assert.match(view, /if \(!\(saveStage == 5 \? GymStore\.appendWorkout\(message\) : GymStore\.queueWorkout\(message\)\)\)/);
  assert.match(store, /static function appendWorkout\(message\) \{\s*if \(!isValidWorkoutMessage\(message\) \|\| !bindingsMatch\(message\)\)/);
  assert.match(view, /if \(saveStage != 5\) \{\s*var queued = GymStore\.pendingMessage\(\);[\s\S]*GymComm\.send/);
  assert.match(
    view,
    /GymStore\.prepareWorkoutCommit\(\)[\s\S]*GymSession\.stopAndSave\(\)[\s\S]*GymStore\.markPreparedWorkoutFitSaved\(\)[\s\S]*finishWorkoutMessage\(saveMessage\)/
  );
  assert.doesNotMatch(view, /if \(!GymSession\.recording\) \{\s*GymStore\.clearActiveWorkout\(\)/);
  assert.match(app, /GymStore\.applyPhoneSync\(message\)/);
  assert.match(app, /"syncRevision" => syncRevision\.toLong\(\)/);
  assert.match(app, /onSyncAckSent[\s\S]*sendNextPendingWorkout\(\)[\s\S]*GymStore\.pendingCount\(\) == 0[\s\S]*GymStatus\.WAITING_ACK/);
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
    /if \(!confirmed && !ack\.isCompleted\)[\s\S]*Garmin watch did not acknowledge the sync after bounded retries/
  );
  assert.doesNotMatch(confirmation, /newGarminMessageId|allocateSyncRevision/);
  assert.match(store, /revisionStatus == 0[\s\S]*status = GymStatus\.SYNC_DUP[\s\S]*return true/);
  assert.match(app, /sendSyncAck\(message, applied, null\)/);
  assert.match(app, /sendSyncAck\(message, reason == null && applied, reason\)/);
  assert.match(app, /sendSyncAck\(message, applied\);/);

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
