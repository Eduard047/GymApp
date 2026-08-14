using Toybox.Application as App;
using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Time as Time;

class GymStore {
    static var bindingVersion = 2;
    private static const storageSchemaVersion = 5;
    static var exercises = ["Bench Press", "Squat", "Deadlift", "Pull Up", "Overhead Press"];
    static var sets = [];
    static var plan = [];
    static var pending = [];
    static var exerciseIndex = 0;
    static var weight = 50.0;
    static var reps = 10;
    static var restDurationMs = 0;
    static var restStartedAt = null;
    static var lastSetUndoStartedAt = null;
    static var lastSetBoost = 0.0;
    static var lastSetWasAutoPrompt = false;
    static var lastSetStatistics = null;
    static var lastLoggedSetEndSeconds = 0;
    static var lastSetPreviousLoggedEnd = 0;
    static var activeWorkoutStartedAtSeconds = null;
    // The active workout is committed as one Object Store value. The legacy
    // per-key values remain as a downgrade/migration fallback, but never override
    // a valid snapshot bound to the current owner and device.
    static var activeWorkoutSnapshotValid = false;
    static var activeWorkoutTimelineValid = false;
    // Compact array restored at process start. Keeping one immutable base avoids
    // duplicating every timeline field as a separate static and keeps low-memory
    // devices within their Connect IQ program limit.
    static var timelineBase = null;
    // Full devices refresh a small owner/device-bound runtime journal while a
    // workout is live. The compact hardware tier reuses its atomic
    // active-workout snapshot so clock, calories, and completed sets still survive
    // a process termination without exceeding their executable-size ceiling.
    static var runtimeWorkoutStartedAtSeconds = null;
    (:fullLegacyState)
    static var runtimePausePending = false;
    (:fullLegacyState)
    static var lastRuntimeCheckpointTimerMs = null;
    (:enhancedCompactCheckpoint)
    static var lastCompactCheckpointElapsed = -15;
    // A validated activeWorkoutV1 checkpoint lets a restarted session shift new
    // intervals onto the durable timeline. Legacy sets without that checkpoint
    // stay fail-closed and omit optional interval diagnostics.
    static var resumedWorkoutIntervalsInvalid = false;
    static var undoWindowMs = 5000;
    static var status = "READY";
    static var weightStep = 2.5;
    static var restSecondsDefault = 90;
    static var autoPromptEnabled = true;
    static var sensitivityIndex = 1;
    static var language = "en";
    static var exerciseLabelCacheName = null;
    static var exerciseLabelCacheLanguage = null;
    static var exerciseLabelCacheValue = null;
    static var accountBinding = null;
    static var stateOwnerBinding = null;
    static var deviceBinding = null;
    static var pairingGeneration = null;
    static var cloudDeviceBinding = null;
    static var deferredSync = null;
    static var processedSyncIds = [];
    static var lastPhoneSyncRevision = 0l;
    static var lastPhoneSyncId = null;
    static var lastPhoneSyncAccountBinding = null;
    // Finishing a workout crosses two durable systems: Garmin FIT and GymApp's
    // phone queue. Keep a tiny owner/device-bound transaction marker so a crash
    // can never make an unsaved FIT activity sendable or generate a new request
    // id on retry. Phase 0 means prepared; phase 1 means FIT was saved.
    static var preparedWorkout = null;
    static var lastWorkoutSyncAtSeconds = null;
    // Tutorial completion is device-local and bounded per account. It is not
    // workout data and intentionally survives an ordinary logout/re-pair.
    static var tutorialHistory = [];
    static var lastCloudPlanRevision = 0;
    static var lastCloudPlanId = null;
    static var stagedPhoneSyncRevision = 0l;
    static var stagedPhoneSyncId = null;
    static var stagedPhoneAccountBinding = null;
    static var stagedPhoneSyncMessage = null;
    static var stagedCloudPlanRevision = 0;
    static var stagedCloudPlanId = null;
    static var stagedCloudAccountBinding = null;
    static var stagedCloudSyncMessage = null;
    static var legacyUnboundState = false;
    (:fullLegacyState)
    static var legacyQuarantineReady = false;
    (:fullLegacyState)
    static var legacyRawExercises = null;
    (:fullLegacyState)
    static var legacyRawSets = null;
    (:fullLegacyState)
    static var legacyRawPlan = null;
    (:fullLegacyState)
    static var legacyRawPending = null;
    static var legacyCompactCount = -1;
    static var requestCounter = 0;

    static var maxPlanSets = 60;
    static var maxWorkoutSets = 60;
    // Keep a bounded offline backlog, but do not block an ordinary third workout
    // merely because the phone has not acknowledged the first two yet. The byte
    // budgets below remain authoritative, so no item is evicted or silently
    // truncated when the watch is genuinely out of durable storage.
    private static const maxPendingWorkouts = 8;
    private static const maxPendingNameBytes = 12000;
    private static const maxExerciseNameLength = 160;
    private static const maxExerciseNameBytes = 640;
    private static const maxTotalNameBytes = 12000;
    static var maxBindingLength = 128;
    static var maxWeight = 1000000.0;
    static var maxReps = 10000;
    static var maxPhoneSyncRevision = 9007199254740991l;
    static var maxCloudPlanRevision = 2147483647;
    private static const maxEstimatedStoreBytes = 24000;
    private static const maxLegacyStoredValueBytes = 32768;
    (:fullLegacyState)
    private static const maxRuntimeCheckpointBytes = 2048;
    (:fullLegacyState)
    private static const runtimeCheckpointIntervalMs = 15000;
    (:fullLegacyState)
    private static const maxRuntimeClockRecoverySeconds = 30;
    private static const maxTutorialAccounts = 4;

    (:fullLegacyState)
    static function load() {
        clearTransientSetActions();
        lastLoggedSetEndSeconds = 0;
        resumedWorkoutIntervalsInvalid = false;
        resetActiveWorkoutSnapshotState();
        resetRuntimeCheckpointState();
        preparedWorkout = null;
        lastWorkoutSyncAtSeconds = null;
        tutorialHistory = [];
        var savedAccountBinding = Storage.getValue("accountBinding");
        accountBinding = isValidAccountBinding(savedAccountBinding) ? savedAccountBinding.toString() : null;
        var savedStateOwnerBinding = Storage.getValue("stateOwnerBinding");
        stateOwnerBinding = isValidAccountBinding(savedStateOwnerBinding) ?
            savedStateOwnerBinding.toString() : null;
        var savedStorageSchemaVersion = Storage.getValue("storageSchemaVersion");
        var legacyUpgrade = savedStorageSchemaVersion == null && accountBinding != null &&
            stateOwnerBinding == null;
        var savedLegacyMarker = Storage.getValue("legacyUnboundState");
        var hasLegacyMarker = savedLegacyMarker instanceof Lang.Boolean && savedLegacyMarker;
        var legacyUnboundUpgrade = savedStorageSchemaVersion == null &&
            accountBinding == null && stateOwnerBinding == null &&
            (Storage.getValue("exercises") != null || Storage.getValue("sets") != null ||
                Storage.getValue("plan") != null || Storage.getValue("pending") != null);
        legacyUnboundState = accountBinding == null &&
            (hasLegacyMarker || legacyUnboundUpgrade);
        var savedLegacyQuarantineVersion = Storage.getValue("legacyQuarantineVersion");
        legacyQuarantineReady = legacyUnboundState &&
            savedLegacyQuarantineVersion instanceof Lang.Number &&
            savedLegacyQuarantineVersion == 1;
        var scopedStateValid = accountBinding != null &&
            ((stateOwnerBinding != null &&
                accountBinding.toString().equals(stateOwnerBinding.toString())) || legacyUpgrade);
        var savedExercises = Storage.getValue("exercises");
        legacyRawExercises = legacyUnboundState ? savedExercises : null;
        if (isValidExerciseList(savedExercises, maxPlanSets) && savedExercises.size() > 0) {
            exercises = savedExercises;
        } else {
            exercises = builtInExercises();
        }
        var savedSets = Storage.getValue("sets");
        legacyRawSets = legacyUnboundState ? savedSets : null;
        if (isValidSetList(savedSets, maxWorkoutSets, true)) {
            sets = savedSets;
        } else {
            sets = [];
        }
        if (sets.size() > 0) {
            resumedWorkoutIntervalsInvalid = true;
        }
        var savedWorkoutStartedAt = Storage.getValue("activeWorkoutStartedAtSeconds");
        activeWorkoutStartedAtSeconds = sets.size() > 0 &&
            isValidWorkoutStartedAtSeconds(savedWorkoutStartedAt) ?
            savedWorkoutStartedAt : null;
        var savedPlan = Storage.getValue("plan");
        legacyRawPlan = legacyUnboundState ? savedPlan : null;
        if (isValidSetList(savedPlan, maxPlanSets, true)) {
            plan = savedPlan;
        } else {
            plan = [];
        }
        var savedPending = Storage.getValue("pending");
        legacyRawPending = legacyUnboundState ? savedPending : null;
        if (isValidPendingList(savedPending)) {
            pending = savedPending;
        } else if (legacyUnboundState && isValidLegacyPendingList(savedPending)) {
            pending = normalizedLegacyPendingList(savedPending);
        } else {
            pending = [];
        }
        var savedWeight = Storage.getValue("weight");
        if (isValidWeight(savedWeight)) {
            weight = savedWeight;
        }
        var savedReps = Storage.getValue("reps");
        if (isValidReps(savedReps)) {
            reps = savedReps;
        }
        var savedCurrentEntry = Storage.getValue("currentEntryV1");
        var savedWeightStep = Storage.getValue("weightStep");
        if (isValidWeight(savedWeightStep) && savedWeightStep > 0.0 && savedWeightStep <= 100.0) {
            weightStep = savedWeightStep;
        }
        var savedRest = Storage.getValue("restSecondsDefault");
        if (savedRest instanceof Lang.Number && savedRest >= 1 && savedRest <= 3600) {
            restSecondsDefault = savedRest;
        }
        var savedAuto = Storage.getValue("autoPromptEnabled");
        if (savedAuto instanceof Lang.Boolean) {
            autoPromptEnabled = savedAuto;
        }
        var savedSensitivity = Storage.getValue("sensitivityIndex");
        if (savedSensitivity instanceof Lang.Number) {
            sensitivityIndex = savedSensitivity;
            if (sensitivityIndex < 0) {
                sensitivityIndex = 0;
            } else if (sensitivityIndex > 2) {
                sensitivityIndex = 2;
            }
        }
        var savedLanguage = Storage.getValue("language");
        if (savedLanguage != null) {
            language = normalizedLanguage(savedLanguage.toString());
        } else {
            var systemLanguage = System.getDeviceSettings().systemLanguage;
            if (systemLanguage == System.LANGUAGE_UKR) {
                language = "uk";
            } else if (systemLanguage == System.LANGUAGE_RUS) {
                language = "ru";
            }
        }
        if (legacyUnboundState) {
            // Once present, this single-value snapshot is the atomic source of truth for
            // post-upgrade edits. The separate raw quarantine below remains an immutable
            // copy of the pre-upgrade values, including values above today's limits.
            restoreLegacyCurrentQuarantine(legacyUnboundUpgrade && !hasLegacyMarker);
        }
        var savedDeviceBinding = Storage.getValue("deviceBinding");
        deviceBinding = isBoundedText(savedDeviceBinding, maxBindingLength) ? savedDeviceBinding.toString() : null;
        var savedPairingGeneration = Storage.getValue("pairingGeneration");
        pairingGeneration = isValidAccountBinding(savedPairingGeneration) ?
            savedPairingGeneration.toString() : null;
        var savedCloudDeviceBinding = Storage.getValue("cloudDeviceBinding");
        cloudDeviceBinding = isBoundedText(savedCloudDeviceBinding, maxBindingLength) ? savedCloudDeviceBinding.toString() : null;
        restoreTutorialHistory(Storage.getValue("tutorialHistoryV1"));
        restorePreparedWorkout(Storage.getValue("preparedWorkoutV1"));
        restoreLastWorkoutSync(Storage.getValue("lastWorkoutSyncV1"));
        var savedDeferredSync = Storage.getValue("deferredSync");
        deferredSync = savedDeferredSync instanceof Lang.Dictionary ? savedDeferredSync : null;
        var savedProcessedSyncIds = Storage.getValue("processedSyncIds");
        processedSyncIds = isValidProcessedSyncIds(savedProcessedSyncIds) ? savedProcessedSyncIds : [];
        var savedActiveWorkout = Storage.getValue("activeWorkoutV1");
        var phoneFence = Storage.getValue("phoneSyncFence");
        if (phoneFence instanceof Lang.Dictionary && isValidPhoneSyncFence(phoneFence)) {
            lastPhoneSyncRevision = phoneFence.get("revision").toLong();
            lastPhoneSyncId = phoneFence.get("id").toString();
            lastPhoneSyncAccountBinding = phoneFence.get("accountBinding").toString();
        } else {
            // One-time compatibility with the pre-fence representation.
            var savedPhoneRevision = Storage.getValue("lastPhoneSyncRevision");
            var savedPhoneSyncId = Storage.getValue("lastPhoneSyncId");
            lastPhoneSyncRevision = isValidCounter(savedPhoneRevision, maxPhoneSyncRevision) &&
                isBoundedText(savedPhoneSyncId, maxBindingLength) ? savedPhoneRevision.toLong() : 0l;
            lastPhoneSyncId = lastPhoneSyncRevision > 0l ? savedPhoneSyncId.toString() : null;
            lastPhoneSyncAccountBinding = lastPhoneSyncRevision > 0l &&
                isValidAccountBinding(savedAccountBinding) ? savedAccountBinding.toString() : null;
        }
        var cloudFence = Storage.getValue("cloudSyncFence");
        if (cloudFence instanceof Lang.Dictionary &&
            isValidSyncFence(cloudFence, maxCloudPlanRevision, 36)) {
            lastCloudPlanRevision = cloudFence.get("revision").toNumber();
            lastCloudPlanId = cloudFence.get("id").toString();
        } else {
            var savedCloudRevision = Storage.getValue("lastCloudPlanRevision");
            var savedCloudPlanId = Storage.getValue("lastCloudPlanId");
            lastCloudPlanRevision = isValidCounter(savedCloudRevision, maxCloudPlanRevision) &&
                isBoundedText(savedCloudPlanId, 36) ? savedCloudRevision.toNumber() : 0;
            lastCloudPlanId = lastCloudPlanRevision > 0 ? savedCloudPlanId.toString() : null;
        }
        loadSyncStage("phone");
        loadSyncStage("cloud");
        if (legacyUpgrade && !adoptLegacyStateOwner()) {
            scopedStateValid = false;
        }
        var previousPairingGeneration = pairingGeneration;
        var pairingRecoveryTarget = scopedStateValid ? stagedPairingRecoveryTarget() : null;
        var recoveredPairing = false;
        if (pairingRecoveryTarget != null) {
            pairingGeneration = pairingRecoveryTarget;
            if (rotatePairingGenerationForPending(
                    previousPairingGeneration,
                    pairingGeneration
                )) {
                recoveredPairing = true;
            } else {
                pairingGeneration = previousPairingGeneration;
            }
        }
        if (savedActiveWorkout != null) {
            var validActiveSnapshot = scopedStateValid &&
                isValidActiveWorkoutSnapshot(savedActiveWorkout);
            var snapshotMatches = validActiveSnapshot &&
                activeWorkoutSnapshotMatchesBindings(savedActiveWorkout);
            if (!snapshotMatches && recoveredPairing && validActiveSnapshot) {
                pairingGeneration = previousPairingGeneration;
                snapshotMatches = activeWorkoutSnapshotMatchesBindings(savedActiveWorkout);
                pairingGeneration = pairingRecoveryTarget;
            }
            if (snapshotMatches) {
                restoreActiveWorkoutSnapshot(savedActiveWorkout);
            } else {
                // A present atomic snapshot is authoritative even when it is corrupt or belongs
                // to a stale device/pairing generation. Never fall back to the downgrade mirror:
                // that would resurrect a different or partially persisted active workout. The
                // mirror remains a compatibility path only for installs that truly predate the
                // atomic value.
                sets = [];
                activeWorkoutStartedAtSeconds = null;
                resumedWorkoutIntervalsInvalid = false;
            }
        }
        exerciseIndex = 0;
        var currentEntryRestored = savedCurrentEntry instanceof Lang.Array &&
            savedCurrentEntry.size() == 2 &&
            isBoundedInteger(savedCurrentEntry[0], 0, maxWorkoutSets) &&
            savedCurrentEntry[0] == sets.size() &&
            isValidExerciseName(savedCurrentEntry[1]) &&
            selectExerciseByName(savedCurrentEntry[1].toString());
        if (!currentEntryRestored &&
            !selectNextPlanSlotInGlobalOrder() && sets.size() > 0) {
            selectExerciseByName(
                sets[sets.size() - 1].get("exerciseName").toString()
            );
        }
        if (legacyUnboundState) {
            // HEAD releases had no account owner marker. Preserve their validated local
            // workout state in-place, but keep it unbound and unsendable until a trusted
            // account transition durably quarantines it.
            if (ensureLegacyQuarantine() && refreshLegacyCurrentQuarantine()) {
                try {
                    Storage.setValue("legacyUnboundState", true);
                    Storage.setValue("storageSchemaVersion", storageSchemaVersion);
                } catch (e) {
                    // Existing values and the completed quarantine remain recoverable.
                }
                status = "LEGACY SAFE";
            } else {
                // Do not allow a later save to overwrite the original HEAD values.
                status = "LEGACY FULL";
            }
        } else if (!scopedStateValid) {
            clearAccountScopedState();
        } else {
            pruneAccountScopedState();
            recoverQueuedWorkout();
            if (hasPreparedWorkout()) {
                status = preparedWorkoutFitSaved() ? "FIT SAVED" : "FIT CHECK";
            }
            if (recoveredPairing && !save()) {
                // Keep the durable stage for the next load/retry, but do not expose
                // a generation that failed to commit to outbound pending messages.
                pairingGeneration = previousPairingGeneration;
                for (var i = 0; i < pending.size(); i += 1) {
                    pending[i].put("pairingGeneration", previousPairingGeneration);
                }
                status = "SAVE FAIL";
            }
        }
    }

    (:fullLegacyState)
    static function save() {
        try {
            if (activeWorkoutStartedAtSeconds != null &&
                (!hasAccountBinding() || sets.size() == 0 ||
                    !isValidWorkoutStartedAtSeconds(activeWorkoutStartedAtSeconds))) {
                status = "SAVE FAIL";
                return false;
            }
            if (activeWorkoutSnapshotValid && hasAccountBinding()) {
                var checkpoint = sets.size() == 0 ?
                    (runtimeWorkoutStartedAtSeconds == null ?
                        emptyTimelineCheckpoint() : currentTimelineCheckpoint(0.0)) :
                    (activeWorkoutTimelineValid ? currentTimelineCheckpoint(0.0) : null);
                if (sets.size() > 0 && activeWorkoutTimelineValid && checkpoint == null) {
                    status = "SAVE FAIL";
                    return false;
                }
                if (!persistActiveWorkoutSnapshot(
                        sets,
                        sets.size() == 0 ? null : activeWorkoutStartedAtSeconds,
                        checkpoint
                    )) {
                    return false;
                }
            }
            if (legacyUnboundState && !ensureLegacyQuarantine()) {
                status = "LEGACY FULL";
                return false;
            }
            if (!isWithinStorageBudget()) {
                status = "STORE FULL";
                return false;
            }
            if (legacyUnboundState && !refreshLegacyCurrentQuarantine()) {
                // Commit the complete current legacy state as one Object Store value before
                // overwriting any compatibility keys. A crash or StorageFullException during
                // the multi-key writes below therefore cannot leave the latest edits torn.
                status = "LEGACY FULL";
                return false;
            }
            // Couple the selected exercise to the active set count in one value.
            // If a crash commits a new active snapshot first, a stale selection is
            // rejected on load instead of silently switching the next set.
            Storage.setValue("currentEntryV1", [sets.size(), currentExercise()]);
            Storage.setValue("exercises", exercises);
            // A valid snapshot is authoritative for this release. Preserve only
            // the core cross-version set fields in the per-key mirror so a user
            // who deliberately installs an older version still recovers the
            // partial workout instead of seeing an empty list.
            if (activeWorkoutSnapshotValid && hasAccountBinding()) {
                var compatibleSets = compatibilityActiveSetList(sets);
                if (!(compatibleSets instanceof Lang.Array)) {
                    status = "SAVE FAIL";
                    return false;
                }
                Storage.setValue("activeWorkoutStartedAtSeconds",
                    sets.size() == 0 ? null : activeWorkoutStartedAtSeconds);
                Storage.setValue("sets", compatibleSets);
            } else if (sets.size() > 0) {
                Storage.setValue("activeWorkoutStartedAtSeconds", activeWorkoutStartedAtSeconds);
                Storage.setValue("sets", sets);
            } else {
                Storage.setValue("sets", sets);
                Storage.setValue("activeWorkoutStartedAtSeconds", activeWorkoutStartedAtSeconds);
            }
            Storage.setValue("plan", plan);
            Storage.setValue("pending", pending);
            Storage.setValue("weight", weight);
            Storage.setValue("reps", reps);
            Storage.setValue("weightStep", weightStep);
            Storage.setValue("restSecondsDefault", restSecondsDefault);
            Storage.setValue("autoPromptEnabled", autoPromptEnabled);
            Storage.setValue("sensitivityIndex", sensitivityIndex);
            Storage.setValue("language", language);
            Storage.setValue("accountBinding", accountBinding);
            Storage.setValue("deviceBinding", deviceBinding);
            Storage.setValue("pairingGeneration", pairingGeneration);
            Storage.setValue("cloudDeviceBinding", cloudDeviceBinding);
            if (preparedWorkout != null) {
                Storage.setValue("preparedWorkoutV1", preparedWorkout);
            } else {
                Storage.deleteValue("preparedWorkoutV1");
            }
            if (lastWorkoutSyncAtSeconds != null) {
                Storage.setValue("lastWorkoutSyncV1", [
                    1, accountBinding, lastWorkoutSyncAtSeconds
                ]);
            } else {
                Storage.deleteValue("lastWorkoutSyncV1");
            }
            Storage.setValue("tutorialHistoryV1", tutorialHistory);
            Storage.setValue("deferredSync", deferredSync);
            Storage.setValue("processedSyncIds", processedSyncIds);
            // Each replay fence is one Object Store value. It is written after all
            // account-scoped values but before their owner commit point. If the owner
            // write fails, the exact durable stage is recognized below and recovered.
            Storage.setValue("phoneSyncFence", {
                "revision" => lastPhoneSyncRevision,
                "id" => lastPhoneSyncId,
                "accountBinding" => lastPhoneSyncAccountBinding
            });
            Storage.setValue("cloudSyncFence", {
                "revision" => lastCloudPlanRevision,
                "id" => lastCloudPlanId
            });
            Storage.setValue("storageSchemaVersion", storageSchemaVersion);
            if (legacyUnboundState) {
                Storage.setValue("legacyUnboundState", true);
            }
            if (isValidAccountBinding(accountBinding)) {
                // This owner marker is the commit point for all account-scoped values.
                Storage.setValue("stateOwnerBinding", accountBinding);
                stateOwnerBinding = accountBinding;
            } else {
                Storage.deleteValue("stateOwnerBinding");
                stateOwnerBinding = null;
            }
            if (!legacyUnboundState) {
                Storage.deleteValue("legacyUnboundState");
            }
            return true;
        } catch (e) {
            status = "SAVE FAIL";
            return false;
        }
    }

    // The compact hardware tier uses the same account/device fences and atomic
    // snapshots. A bounded full-v3 bridge below preserves an unfinished workout
    // when an existing product (notably fr55) moves to this lower-memory build.
    // Older ownerless values stay quarantined and unsendable instead of pulling
    // the entire historical migration graph into the process.
    (:compactLegacyState)
    static function load() {
        clearTransientSetActions();
        resetActiveWorkoutSnapshotState();
        resetRuntimeCheckpointState();
        preparedWorkout = null;
        tutorialHistory = [];
        lastWorkoutSyncAtSeconds = null;

        var savedAccount = Storage.getValue("accountBinding");
        var savedOwner = Storage.getValue("stateOwnerBinding");
        accountBinding = isValidAccountBinding(savedAccount) ? savedAccount.toString() : null;
        stateOwnerBinding = isValidAccountBinding(savedOwner) ? savedOwner.toString() : null;
        var ownerMatches = accountBinding != null && stateOwnerBinding != null &&
            accountBinding.toString().equals(stateOwnerBinding.toString());
        var schema = Storage.getValue("storageSchemaVersion");
        var legacyUpgrade = schema == null && accountBinding != null && stateOwnerBinding == null;
        var legacyMarker = Storage.getValue("legacyUnboundState");
        legacyUnboundState = accountBinding == null &&
            ((legacyMarker instanceof Lang.Boolean && legacyMarker) || schema == null);

        var value = Storage.getValue("exercises");
        exercises = isValidExerciseList(value, maxPlanSets) && value.size() > 0 ?
            value : builtInExercises();
        value = Storage.getValue("sets");
        sets = isValidSetList(value, maxWorkoutSets, true) ? value : [];
        value = Storage.getValue("plan");
        plan = isValidSetList(value, maxPlanSets, true) ? value : [];
        value = Storage.getValue("pending");
        pending = isValidPendingList(value) ? value : [];
        resumedWorkoutIntervalsInvalid = sets.size() > 0;
        value = Storage.getValue("activeWorkoutStartedAtSeconds");
        activeWorkoutStartedAtSeconds = sets.size() > 0 &&
            isValidWorkoutStartedAtSeconds(value) ? value : null;

        value = Storage.getValue("weight");
        weight = isValidWeight(value) ? value : 50.0;
        value = Storage.getValue("reps");
        reps = isValidReps(value) ? value : 10;
        value = Storage.getValue("weightStep");
        weightStep = isValidWeight(value) && value > 0.0 && value <= 100.0 ? value : 2.5;
        value = Storage.getValue("restSecondsDefault");
        restSecondsDefault = value instanceof Lang.Number && value >= 1 && value <= 3600 ? value : 90;
        value = Storage.getValue("autoPromptEnabled");
        autoPromptEnabled = value instanceof Lang.Boolean ? value : true;
        value = Storage.getValue("sensitivityIndex");
        sensitivityIndex = value instanceof Lang.Number && value >= 0 && value <= 2 ? value : 1;
        value = Storage.getValue("language");
        language = value == null ? "en" : normalizedLanguage(value.toString());

        value = Storage.getValue("deviceBinding");
        deviceBinding = isBoundedText(value, maxBindingLength) ? value.toString() : null;
        value = Storage.getValue("pairingGeneration");
        pairingGeneration = isValidAccountBinding(value) ? value.toString() : null;
        value = Storage.getValue("cloudDeviceBinding");
        cloudDeviceBinding = isBoundedText(value, maxBindingLength) ? value.toString() : null;
        restoreTutorialHistory(Storage.getValue("tutorialHistoryV1"));
        restorePreparedWorkout(Storage.getValue("preparedWorkoutV1"));
        restoreLastWorkoutSync(Storage.getValue("lastWorkoutSyncV1"));
        value = Storage.getValue("deferredSync");
        deferredSync = value instanceof Lang.Dictionary ? value : null;
        value = Storage.getValue("processedSyncIds");
        processedSyncIds = isValidProcessedSyncIds(value) ? value : [];

        var phoneFence = Storage.getValue("phoneSyncFence");
        if (phoneFence instanceof Lang.Dictionary && isValidPhoneSyncFence(phoneFence)) {
            lastPhoneSyncRevision = phoneFence.get("revision").toLong();
            lastPhoneSyncId = phoneFence.get("id").toString();
            lastPhoneSyncAccountBinding = phoneFence.get("accountBinding").toString();
        } else {
            lastPhoneSyncRevision = 0l;
            lastPhoneSyncId = null;
            lastPhoneSyncAccountBinding = null;
        }
        lastCloudPlanRevision = 0;
        lastCloudPlanId = null;
        loadSyncStage("phone");
        loadSyncStage("cloud");

        if (legacyUpgrade) {
            ownerMatches = adoptLegacyStateOwner();
        }
        var savedActive = Storage.getValue("activeWorkoutV1");
        var restoredActive = false;
        if (ownerMatches && isValidActiveWorkoutSnapshot(savedActive) &&
            activeWorkoutSnapshotMatchesBindings(savedActive)) {
            restoreActiveWorkoutSnapshot(savedActive);
            restoredActive = true;
            // Compact builds never consume the richer full-runtime journal.
            // Remove a stale copy only after the compact snapshot itself has
            // already been accepted as the durable source of truth.
            try {
                Storage.deleteValue("activeRuntimeV1");
            } catch (e) {
                // The next launch repeats this bounded cleanup.
            }
        } else if (ownerMatches && restoreMigratedActiveWorkout(savedActive)) {
            restoredActive = true;
        }
        if (!restoredActive && savedActive != null) {
            sets = [];
            activeWorkoutStartedAtSeconds = null;
        }
        exerciseIndex = 0;
        selectNextPlanSlotInGlobalOrder();
        if (legacyUnboundState) {
            restoreLegacyCurrentQuarantine(schema == null);
            status = "LEGACY SAFE";
        } else if (!ownerMatches) {
            clearAccountScopedState();
        } else {
            pruneAccountScopedState();
            recoverQueuedWorkout();
            if (hasPreparedWorkout()) {
                status = preparedWorkoutFitSaved() ? "FIT SAVED" : "FIT CHECK";
            }
        }
    }

    (:compactLegacyState)
    static function save() {
        try {
            if (activeWorkoutStartedAtSeconds != null &&
                (!hasAccountBinding() ||
                    !isValidWorkoutStartedAtSeconds(activeWorkoutStartedAtSeconds) ||
                    (sets.size() == 0 &&
                        (!activeWorkoutSnapshotValid ||
                            !activeWorkoutTimelineValid)))) {
                status = "SAVE FAIL";
                return false;
            }
            if (activeWorkoutSnapshotValid && hasAccountBinding()) {
                var checkpoint = sets.size() == 0 ?
                    (runtimeWorkoutStartedAtSeconds == null ?
                        emptyTimelineCheckpoint() : currentTimelineCheckpoint(0.0)) :
                    (activeWorkoutTimelineValid ? currentTimelineCheckpoint(0.0) : null);
                if (sets.size() > 0 && checkpoint == null) {
                    status = "SAVE FAIL";
                    return false;
                }
                if (!persistActiveWorkoutSnapshot(
                        sets,
                        activeWorkoutStartedAtSeconds,
                        checkpoint
                    )) {
                    return false;
                }
            }
            if ((legacyUnboundState && !ensureLegacyQuarantine()) ||
                !isWithinStorageBudget()) {
                status = "STORE FULL";
                return false;
            }
            Storage.setValue("currentEntryV1", [sets.size(), currentExercise()]);
            Storage.setValue("exercises", exercises);
            Storage.setValue("sets", sets);
            Storage.setValue("activeWorkoutStartedAtSeconds", activeWorkoutStartedAtSeconds);
            Storage.setValue("plan", plan);
            Storage.setValue("pending", pending);
            Storage.setValue("weight", weight);
            Storage.setValue("reps", reps);
            Storage.setValue("weightStep", weightStep);
            Storage.setValue("restSecondsDefault", restSecondsDefault);
            Storage.setValue("autoPromptEnabled", autoPromptEnabled);
            Storage.setValue("sensitivityIndex", sensitivityIndex);
            Storage.setValue("language", language);
            Storage.setValue("accountBinding", accountBinding);
            Storage.setValue("deviceBinding", deviceBinding);
            Storage.setValue("pairingGeneration", pairingGeneration);
            Storage.setValue("cloudDeviceBinding", cloudDeviceBinding);
            if (preparedWorkout == null) {
                Storage.deleteValue("preparedWorkoutV1");
            } else {
                Storage.setValue("preparedWorkoutV1", preparedWorkout);
            }
            Storage.setValue("tutorialHistoryV1", tutorialHistory);
            Storage.setValue("lastWorkoutSyncV1", lastWorkoutSyncAtSeconds == null ? null :
                [1, accountBinding, lastWorkoutSyncAtSeconds]);
            Storage.setValue("deferredSync", deferredSync);
            Storage.setValue("processedSyncIds", processedSyncIds);
            Storage.setValue("phoneSyncFence", {
                "revision" => lastPhoneSyncRevision,
                "id" => lastPhoneSyncId,
                "accountBinding" => lastPhoneSyncAccountBinding
            });
            Storage.setValue("storageSchemaVersion", storageSchemaVersion);
            if (isValidAccountBinding(accountBinding)) {
                Storage.setValue("stateOwnerBinding", accountBinding);
                stateOwnerBinding = accountBinding;
            } else {
                Storage.deleteValue("stateOwnerBinding");
                stateOwnerBinding = null;
            }
            return true;
        } catch (e) {
            status = "SAVE FAIL";
            return false;
        }
    }

    static function resetActiveWorkoutSnapshotState() {
        activeWorkoutSnapshotValid = false;
        activeWorkoutTimelineValid = false;
        timelineBase = null;
    }

    (:fullLegacyState)
    static function resetRuntimeCheckpointState() {
        runtimeWorkoutStartedAtSeconds = null;
        runtimePausePending = false;
        lastRuntimeCheckpointTimerMs = null;
    }

    (:enhancedCompactCheckpoint)
    static function resetRuntimeCheckpointState() {
        runtimeWorkoutStartedAtSeconds = null;
        lastCompactCheckpointElapsed = -15;
    }

    (:compactCheckpoint96)
    static function resetRuntimeCheckpointState() {
        runtimeWorkoutStartedAtSeconds = null;
    }

    (:fullLegacyState)
    static function isValidRuntimeCheckpoint(snapshot) {
        if (!(snapshot instanceof Lang.Array) || snapshot.size() != 11 ||
            !(snapshot[0] instanceof Lang.Number) || snapshot[0] != 1 ||
            !isValidAccountBinding(snapshot[1]) ||
            !isBoundedText(snapshot[2], maxBindingLength) ||
            !isValidOptionalAccountBinding(snapshot[3]) ||
            !isBoundedInteger(snapshot[4], 0, maxWorkoutSets) ||
            !isValidWorkoutStartedAtSeconds(snapshot[5]) ||
            !isValidWorkoutStartedAtSeconds(snapshot[6]) ||
            snapshot[6] > snapshot[5] || snapshot[5] - snapshot[6] > 604800 ||
            !isValidTimelineCheckpoint(snapshot[7]) ||
            !(snapshot[8] instanceof Lang.Boolean) ||
            !isBoundedInteger(snapshot[9], 0, 2) ||
            estimatedValueBytes(snapshot) > maxRuntimeCheckpointBytes) {
            return false;
        }
        var restMode = snapshot[9];
        var restValue = snapshot[10];
        if (restMode == 0) {
            return restValue instanceof Lang.Number && restValue == 0;
        }
        if (restMode == 1) {
            return isValidWorkoutStartedAtSeconds(restValue) &&
                restValue >= snapshot[5] && restValue - snapshot[5] <= 3600;
        }
        return isBoundedInteger(restValue, 1, 3600);
    }

    (:fullLegacyState)
    static function restoreRuntimeCheckpoint(snapshot) {
        if (!isValidRuntimeCheckpoint(snapshot) ||
            !activeWorkoutSnapshotMatchesBindings(snapshot) ||
            snapshot[4] != sets.size()) {
            return false;
        }
        var origin = snapshot[6];
        var checkpoint = snapshot[7];
        if (sets.size() > 0) {
            if (!activeWorkoutSnapshotValid ||
                !isValidWorkoutStartedAtSeconds(activeWorkoutStartedAtSeconds) ||
                activeWorkoutStartedAtSeconds != origin ||
                !areSnapshotIntervalsConsistent(sets, checkpoint)) {
                return false;
            }
        } else if (activeWorkoutStartedAtSeconds != null || snapshot[9] != 0) {
            return false;
        }

        var restoredCheckpoint = [
            checkpoint[0], checkpoint[1], checkpoint[2], checkpoint[3],
            checkpoint[4], checkpoint[5], checkpoint[6], checkpoint[7]
        ];
        var now = Time.now().value();
        var recoveryGap = now - snapshot[5];
        if (!snapshot[8] && recoveryGap >= 0 &&
            recoveryGap <= maxRuntimeClockRecoverySeconds &&
            restoredCheckpoint[0] + recoveryGap <= 604800) {
            // A short app-restart gap is part of a still-running workout. Longer
            // absences are intentionally not counted, preventing a next-day open
            // from inflating a forgotten session by hours.
            restoredCheckpoint[0] += recoveryGap;
        }
        if (!isValidTimelineCheckpoint(restoredCheckpoint)) {
            return false;
        }

        timelineBase = restoredCheckpoint;
        activeWorkoutTimelineValid = true;
        resumedWorkoutIntervalsInvalid = false;
        runtimeWorkoutStartedAtSeconds = origin;
        runtimePausePending = snapshot[8];
        restDurationMs = 0;
        restStartedAt = null;
        if (snapshot[9] == 1) {
            var remaining = snapshot[10] - now;
            if (remaining > 0 && remaining <= 3600) {
                restDurationMs = remaining * 1000;
                restStartedAt = System.getTimer();
            }
        } else if (snapshot[9] == 2) {
            restDurationMs = snapshot[10] * 1000;
        }
        lastRuntimeCheckpointTimerMs = System.getTimer();
        return true;
    }

    static function activeWorkoutSnapshotMatchesBindings(snapshot) {
        if (!(snapshot instanceof Lang.Array) || !hasAccountBinding() ||
            !accountBinding.toString().equals(snapshot[1].toString()) ||
            !deviceBinding.toString().equals(snapshot[2].toString())) {
            return false;
        }
        var snapshotGeneration = snapshot[3];
        if (isValidAccountBinding(pairingGeneration)) {
            return isValidAccountBinding(snapshotGeneration) &&
                pairingGeneration.toString().equals(snapshotGeneration.toString());
        }
        return snapshotGeneration == null;
    }

    (:fullLegacyState)
    static function isValidActiveWorkoutSnapshot(snapshot) {
        if (!(snapshot instanceof Lang.Array) ||
            (snapshot.size() != 7 && snapshot.size() != 11) ||
            !(snapshot[0] instanceof Lang.Number) ||
            ((snapshot[0] == 2 && snapshot.size() != 7) ||
                (snapshot[0] == 3 && snapshot.size() != 11)) ||
            (snapshot[0] != 2 && snapshot[0] != 3) ||
            !isValidAccountBinding(snapshot[1]) ||
            !isBoundedText(snapshot[2], maxBindingLength) ||
            !isValidOptionalAccountBinding(snapshot[3])) {
            return false;
        }
        var snapshotVersion = snapshot[0];
        var snapshotSets = snapshot[5];
        if ((snapshotVersion == 2 &&
                !isValidSetList(snapshotSets, maxWorkoutSets, true)) ||
            (snapshotVersion == 3 &&
                !isValidCompactActiveSetArrays(snapshot))) {
            return false;
        }
        var startedAtSeconds = snapshot[4];
        var checkpoint = snapshotVersion == 3 ? snapshot[10] : snapshot[6];
        if (snapshotSets.size() == 0 && startedAtSeconds != null) {
            return false;
        }
        if (snapshotSets.size() > 0 &&
            ((startedAtSeconds == null && checkpoint != null) ||
                (startedAtSeconds != null &&
                    !isValidWorkoutStartedAtSeconds(startedAtSeconds)))) {
            // Pre-origin releases can have durable account-bound sets without a
            // trustworthy start time. Preserve them atomically only in the existing
            // fail-closed mode: no persisted timeline or interval diagnostics.
            return false;
        }
        if (checkpoint == null) {
            return snapshotVersion == 2 || snapshot[9] == null;
        }
        if (!isValidTimelineCheckpoint(checkpoint)) {
            return false;
        }
        if (snapshotVersion == 3) {
            return isValidSetIntervalsList(snapshot[9], snapshotSets) &&
                areSetIntervalsConsistent(
                    snapshot[9], checkpoint[0], checkpoint[1], checkpoint[2]);
        }
        return areSnapshotIntervalsConsistent(snapshotSets, checkpoint);
    }

    // The compact hardware tier persists the same v3 owner-bound transaction with
    // a four-field set dictionary (exercise/kg/reps/interval). This keeps the
    // executable and restore heap within their hard ceiling while retaining the
    // complete workout ordering and timeline. Version 3 may also carry a valid
    // origin before the first set; the null-origin, zero checkpoint remains the
    // unambiguous durable tombstone. Already-installed v2 snapshots remain
    // accepted and are rewritten as v3 on the next successful save.
    (:enhancedCompactCheckpoint)
    static function isValidActiveWorkoutSnapshot(snapshot) {
        if (!(snapshot instanceof Lang.Array) || snapshot.size() != 7 ||
            !(snapshot[0] instanceof Lang.Number) ||
            (snapshot[0] != 2 && snapshot[0] != 3) ||
            !isValidAccountBinding(snapshot[1]) ||
            !isBoundedText(snapshot[2], maxBindingLength) ||
            !isValidOptionalAccountBinding(snapshot[3]) ||
            !isValidSetList(snapshot[5], maxWorkoutSets, true)) {
            return false;
        }
        var snapshotSets = snapshot[5];
        var startedAtSeconds = snapshot[4];
        var checkpoint = snapshot[6];
        if (snapshotSets.size() == 0 && startedAtSeconds != null &&
            (snapshot[0] != 3 || checkpoint == null ||
                !isValidWorkoutStartedAtSeconds(startedAtSeconds))) {
            return false;
        }
        if (snapshotSets.size() > 0 &&
            ((startedAtSeconds == null && checkpoint != null) ||
                (startedAtSeconds != null &&
                    !isValidWorkoutStartedAtSeconds(startedAtSeconds)))) {
            return false;
        }
        return checkpoint == null ||
            (isValidTimelineCheckpoint(checkpoint) &&
                areSnapshotIntervalsConsistent(snapshotSets, checkpoint));
    }

    // Preserve the proven low-memory validation path on the five 96 KiB
    // products. The richer zero-set checkpoint is reserved for fr55, whose
    // 128 KiB limit leaves enough loader headroom for reliable recovery UX.
    (:compactCheckpoint96)
    static function isValidActiveWorkoutSnapshot(snapshot) {
        if (!(snapshot instanceof Lang.Array) || snapshot.size() != 7 ||
            !(snapshot[0] instanceof Lang.Number) ||
            (snapshot[0] != 2 && snapshot[0] != 3) ||
            !isValidAccountBinding(snapshot[1]) ||
            !isBoundedText(snapshot[2], maxBindingLength) ||
            !isValidOptionalAccountBinding(snapshot[3]) ||
            !isValidSetList(snapshot[5], maxWorkoutSets, true)) {
            return false;
        }
        var snapshotSets = snapshot[5];
        var startedAtSeconds = snapshot[4];
        var checkpoint = snapshot[6];
        if (snapshotSets.size() == 0 && startedAtSeconds != null) {
            return false;
        }
        if (snapshotSets.size() > 0 &&
            ((startedAtSeconds == null && checkpoint != null) ||
                (startedAtSeconds != null &&
                    !isValidWorkoutStartedAtSeconds(startedAtSeconds)))) {
            return false;
        }
        return checkpoint == null ||
            (isValidTimelineCheckpoint(checkpoint) &&
                areSnapshotIntervalsConsistent(snapshotSets, checkpoint));
    }

    // fr55 used the full v3 parallel-array snapshot before it joined the compact
    // hardware tier. Convert only an exact, current-owner snapshot and validate
    // every field that will be retained or deliberately omitted. Malformed,
    // stale-account, and stale-pairing values remain fail-closed.
    (:fr55UpgradeBridge)
    static function compactActiveSnapshotFromFullV3(value) {
        if (!(value instanceof Lang.Array) || value.size() != 11 ||
            !(value[0] instanceof Lang.Number) || value[0] != 3 ||
            !isValidAccountBinding(value[1]) ||
            !isBoundedText(value[2], maxBindingLength) ||
            !isValidOptionalAccountBinding(value[3]) ||
            !activeWorkoutSnapshotMatchesBindings(value)) {
            return null;
        }

        var names = value[5];
        var weights = value[6];
        var setReps = value[7];
        var metrics = value[8];
        if (!isValidExerciseList(names, maxWorkoutSets) ||
            !(weights instanceof Lang.Array) ||
            !(setReps instanceof Lang.Array) ||
            weights.size() != names.size() || setReps.size() != names.size() ||
            !isValidSetMetricsList(metrics, names)) {
            return null;
        }
        for (var i = 0; i < names.size(); i += 1) {
            if (!isValidWeight(weights[i]) || !isValidReps(setReps[i])) {
                return null;
            }
        }

        var startedAt = value[4];
        var intervals = value[9];
        var checkpoint = value[10];
        if ((names.size() == 0 && startedAt != null) ||
            (names.size() > 0 &&
                ((startedAt == null && checkpoint != null) ||
                    (startedAt != null &&
                        !isValidWorkoutStartedAtSeconds(startedAt))))) {
            return null;
        }
        if (checkpoint == null) {
            if (intervals != null) {
                return null;
            }
        } else if (!isValidTimelineCheckpoint(checkpoint) ||
            !isValidSetIntervalsList(intervals, names) ||
            !areSetIntervalsConsistent(
                intervals, checkpoint[0], checkpoint[1], checkpoint[2])) {
            return null;
        }

        var compactSets = [];
        for (var j = 0; j < names.size(); j += 1) {
            var safe = {
                "exerciseName" => names[j].toString(),
                "weight" => weights[j],
                "reps" => setReps[j]
            };
            if (checkpoint != null) {
                safe.put("setInterval", copySetInterval(intervals[j]));
            }
            compactSets.add(safe);
        }
        var safeCheckpoint = checkpoint == null ? null : copySetInterval(checkpoint);
        var candidate = [
            3,
            value[1].toString(),
            value[2].toString(),
            value[3] == null ? null : value[3].toString(),
            startedAt,
            compactSets,
            safeCheckpoint
        ];
        return isValidActiveWorkoutSnapshot(candidate) &&
            isWithinStorageBudgetForActiveSnapshot(candidate) ? candidate : null;
    }

    (:fr55UpgradeBridge)
    static function restoreMigratedActiveWorkout(savedActive) {
        var migratedActive = compactActiveSnapshotFromFullV3(savedActive);
        if (migratedActive == null) {
            return false;
        }
        // Restore the validated copy before rewriting the single durable value.
        // If Object Store is temporarily full, the athlete keeps the workout in
        // this process and the original full snapshot remains retryable.
        restoreActiveWorkoutSnapshot(migratedActive);
        try {
            Storage.setValue("activeWorkoutV1", migratedActive);
            try {
                Storage.deleteValue("activeRuntimeV1");
            } catch (e) {
                // The compact snapshot is already durable; retry cleanup later.
            }
        } catch (e) {
            status = "SAVE FAIL";
        }
        return true;
    }

    // Products that have always used the compact schema must not carry the
    // FR55-only transition graph in their much smaller runtime budget.
    (:noFr55UpgradeBridge)
    static function compactActiveSnapshotFromFullV3(value) {
        return null;
    }

    (:noFr55UpgradeBridge)
    static function restoreMigratedActiveWorkout(savedActive) {
        return false;
    }

    // Version 3 stores set fields in parallel arrays instead of repeating eleven
    // dictionary keys. Existing compact metric/interval validators are reused to
    // keep both code and peak heap bounded on the compact products.
    (:fullLegacyState)
    static function isValidCompactActiveSetArrays(snapshot) {
        var names = snapshot[5];
        var weights = snapshot[6];
        var setReps = snapshot[7];
        if (!isValidExerciseList(names, maxWorkoutSets) ||
            !(weights instanceof Lang.Array) ||
            !(setReps instanceof Lang.Array) ||
            weights.size() != names.size() || setReps.size() != names.size() ||
            !isValidSetMetricsList(snapshot[8], names)) {
            return false;
        }
        for (var i = 0; i < names.size(); i += 1) {
            if (!isValidWeight(weights[i]) || !isValidReps(setReps[i])) {
                return false;
            }
        }
        return true;
    }

    // Older app versions ignore a version-3 activeWorkoutV1 value. Keep a
    // deliberately small per-key mirror so a deliberate downgrade can still
    // recover exercise, kg, and reps. Current versions always prefer the richer
    // account/device-bound atomic snapshot above.
    static function compatibilityActiveSetList(source) {
        if (!isValidSetList(source, maxWorkoutSets, true)) {
            return null;
        }
        var compatible = [];
        for (var i = 0; i < source.size(); i += 1) {
            var item = source[i];
            var safe = {
                "exerciseName" => item.get("exerciseName").toString(),
                "weight" => item.get("weight"),
                "reps" => item.get("reps")
            };
            if (item.get("setInterval") != null) {
                safe.put("setInterval", item.get("setInterval"));
            }
            compatible.add(safe);
        }
        return compatible;
    }


    static function isValidTimelineCheckpoint(checkpoint) {
        if (!(checkpoint instanceof Lang.Array) || checkpoint.size() != 8 ||
            !isBoundedInteger(checkpoint[0], 0, 604800) ||
            !isBoundedNumber(checkpoint[1], 0.0, 10000000.0) ||
            !isOptionalBoundedInteger(checkpoint[2], 0, 10000000) ||
            !isBoundedInteger(checkpoint[3], 0, 200000000) ||
            !isBoundedInteger(checkpoint[4], 0, 604800) ||
            !isBoundedInteger(checkpoint[5], 0, 300) ||
            !isOptionalBoundedInteger(checkpoint[6], 0, 300) ||
            !isBoundedInteger(checkpoint[7], 0, 5)) {
            return false;
        }
        var samplesValue = checkpoint[4];
        var sumValue = checkpoint[3];
        var samples = samplesValue;
        var sum = sumValue;
        return (samples > 0 || sum == 0) && sum <= samples * 240;
    }

    static function areSnapshotIntervalsConsistent(snapshotSets, checkpoint) {
        var intervals = [];
        for (var i = 0; i < snapshotSets.size(); i += 1) {
            var interval = snapshotSets[i].get("setInterval");
            if (!(interval instanceof Lang.Array)) {
                return false;
            }
            intervals.add(interval);
        }
        return areSetIntervalsConsistent(
            intervals,
            checkpoint[0],
            checkpoint[1],
            checkpoint[2]
        );
    }

    (:fullLegacyState)
    static function restoreActiveWorkoutSnapshot(snapshot) {
        if (snapshot[0] == 3) {
            var restored = [];
            var keys = [
                "activeSeconds", "restBeforeSeconds", "startHeartRate",
                "peakHeartRate", "endHeartRate", "recoveryHeartRateDrop",
                "detectionConfidence"
            ];
            for (var i = 0; i < snapshot[5].size(); i += 1) {
                var item = {
                    "exerciseName" => snapshot[5][i].toString(),
                    "weight" => snapshot[6][i],
                    "reps" => snapshot[7][i]
                };
                for (var k = 0; k < keys.size(); k += 1) {
                    if (snapshot[8][i][k] != null) {
                        item.put(keys[k], snapshot[8][i][k]);
                    }
                }
                if (snapshot[9] != null) {
                    item.put("setInterval", copySetInterval(snapshot[9][i]));
                }
                restored.add(item);
            }
            sets = restored;
        } else {
            sets = normalizedSetList(snapshot[5]);
        }
        activeWorkoutStartedAtSeconds = snapshot[4];
        activeWorkoutSnapshotValid = true;
        var checkpoint = snapshot[0] == 3 ? snapshot[10] : snapshot[6];
        // load() invokes this only after the untrusted snapshot, checkpoint, and
        // every persisted interval have passed the complete validator above.
        if (checkpoint != null) {
            activeWorkoutTimelineValid = true;
            resumedWorkoutIntervalsInvalid = false;
            timelineBase = checkpoint;
        } else {
            activeWorkoutTimelineValid = false;
            resumedWorkoutIntervalsInvalid = sets.size() > 0;
            timelineBase = null;
        }
        var runtime = Storage.getValue("activeRuntimeV1");
        if (runtime != null && isValidRuntimeCheckpoint(runtime) &&
            activeWorkoutSnapshotMatchesBindings(runtime)) {
            restoreRuntimeCheckpoint(runtime);
        }
    }

    (:enhancedCompactCheckpoint)
    static function restoreActiveWorkoutSnapshot(snapshot) {
        sets = normalizedSetList(snapshot[5]);
        activeWorkoutStartedAtSeconds = snapshot[4];
        activeWorkoutSnapshotValid = true;
        restDurationMs = 0;
        restStartedAt = null;
        var checkpoint = snapshot[6];
        if (checkpoint != null) {
            activeWorkoutTimelineValid = true;
            resumedWorkoutIntervalsInvalid = false;
            timelineBase = checkpoint;
            // Compact products derive the bounded rest remainder from the last
            // durable interval and timeline instead of carrying another runtime
            // journal. Relaunch may replay at most one checkpoint window, but it
            // never loses the completed set or rest entirely.
            if (sets.size() > 0) {
                var lastInterval = sets[sets.size() - 1].get("setInterval");
                if (isValidSetInterval(lastInterval) &&
                    checkpoint[0] >= lastInterval[1]) {
                    var elapsedSinceSet = checkpoint[0] - lastInterval[1];
                    var remainingRest = restSecondsDefault - elapsedSinceSet;
                    if (remainingRest > 0 && remainingRest <= 3600) {
                        restDurationMs = remainingRest * 1000;
                        restStartedAt = System.getTimer();
                    }
                }
            }
        } else {
            activeWorkoutTimelineValid = false;
            resumedWorkoutIntervalsInvalid = sets.size() > 0;
            timelineBase = null;
        }
    }

    (:compactCheckpoint96)
    static function restoreActiveWorkoutSnapshot(snapshot) {
        sets = normalizedSetList(snapshot[5]);
        activeWorkoutStartedAtSeconds = snapshot[4];
        activeWorkoutSnapshotValid = true;
        var checkpoint = snapshot[6];
        if (checkpoint != null) {
            activeWorkoutTimelineValid = true;
            resumedWorkoutIntervalsInvalid = false;
            timelineBase = checkpoint;
        } else {
            activeWorkoutTimelineValid = false;
            resumedWorkoutIntervalsInvalid = sets.size() > 0;
            timelineBase = null;
        }
    }

    static function currentTimelineCheckpoint(gymCalorieAdjustment) {
        if (resumedWorkoutIntervalsInvalid) {
            return null;
        }
        var elapsed = (timelineBase == null ? 0 : timelineBase[0]) + GymSession.elapsedSeconds;
        var gymTotal = (timelineBase == null ? 0.0 : timelineBase[1]) +
            GymSession.gymCalories + gymCalorieAdjustment;
        var garminTotal = timelineBase == null ? null : timelineBase[2];
        if (GymSession.garminCalories != null) {
            garminTotal = (garminTotal == null ? 0 : garminTotal) + GymSession.garminCalories;
        }
        var samples = (timelineBase == null ? 0 : timelineBase[4]) + GymSession.hrSamples;
        var sum = (timelineBase == null ? 0 : timelineBase[3]) +
            (GymSession.avgHr * GymSession.hrSamples);
        var priorMaximum = timelineBase == null ? 0 : timelineBase[5];
        var maximum = priorMaximum > GymSession.maxHr ? priorMaximum : GymSession.maxHr;
        var lastHeartRate = GymSession.hr != null ?
            GymSession.hr : (timelineBase == null ? null : timelineBase[6]);
        var lastZone = GymSession.hr != null ?
            GymSession.zone : (timelineBase == null ? 0 : timelineBase[7]);
        var checkpoint = [elapsed, gymTotal, garminTotal, sum, samples,
            maximum, lastHeartRate, lastZone];
        return isValidTimelineCheckpoint(checkpoint) ? checkpoint : null;
    }

    static function totalGymCalories() {
        return (timelineBase == null ? 0.0 : timelineBase[1]) +
            GymSession.gymCalories;
    }

    (:fullLegacyState)
    static function totalGarminCalories() {
        var base = timelineBase == null ? null : timelineBase[2];
        if (GymSession.garminCalories != null) {
            return (base == null ? 0 : base) + GymSession.garminCalories;
        }
        return base;
    }

    (:fullLegacyState)
    static function checkpointLiveWorkout(force) {
        if (runtimePausePending) {
            if (!GymSession.pause()) {
                status = "PAUSE FAIL";
                return false;
            }
            runtimePausePending = false;
        }
        if (!hasAccountBinding() || GymSession.startedAt <= 0 ||
            GymSession.fitSaved) {
            return true;
        }
        if (!force && lastRuntimeCheckpointTimerMs != null &&
            timerElapsedMs(lastRuntimeCheckpointTimerMs) <
                runtimeCheckpointIntervalMs.toLong()) {
            return true;
        }
        var checkpoint = currentTimelineCheckpoint(0.0);
        if (checkpoint == null ||
            (sets.size() > 0 && !areSnapshotIntervalsConsistent(sets, checkpoint))) {
            return false;
        }
        if (sets.size() == 0 && !activeWorkoutSnapshotValid &&
            !persistActiveWorkoutSnapshot([], null, checkpoint)) {
            return false;
        }
        var origin = activeWorkoutStartedAtSeconds;
        if (origin == null) {
            origin = runtimeWorkoutStartedAtSeconds;
        }
        if (origin == null) {
            origin = GymSession.startedAt;
        }
        if (!isValidWorkoutStartedAtSeconds(origin)) {
            return false;
        }
        var savedAt = Time.now().value();
        if (!isValidWorkoutStartedAtSeconds(savedAt) || origin > savedAt ||
            savedAt - origin > 604800) {
            return false;
        }

        var restMode = 0;
        var restValue = 0;
        if (sets.size() > 0 && restDurationMs > 0) {
            if (restStartedAt != null) {
                var remaining = restSeconds();
                if (remaining > 0) {
                    restMode = 1;
                    restValue = savedAt + remaining;
                }
            } else {
                var suspendedSeconds =
                    ((restDurationMs.toLong() + 999l) / 1000l).toNumber();
                if (suspendedSeconds > 0 && suspendedSeconds <= 3600) {
                    restMode = 2;
                    restValue = suspendedSeconds;
                }
            }
        }
        var snapshot = [
            1,
            accountBinding.toString(),
            deviceBinding.toString(),
            isValidAccountBinding(pairingGeneration) ?
                pairingGeneration.toString() : null,
            sets.size(),
            savedAt,
            origin,
            checkpoint,
            GymSession.paused,
            restMode,
            restValue
        ];
        if (!isValidRuntimeCheckpoint(snapshot)) {
            return false;
        }
        try {
            Storage.setValue("activeRuntimeV1", snapshot);
            runtimeWorkoutStartedAtSeconds = origin;
            lastRuntimeCheckpointTimerMs = System.getTimer();
            return true;
        } catch (e) {
            if (force) {
                status = "RECOVERY FAIL";
            }
            return false;
        }
    }

    (:enhancedCompactCheckpoint)
    static function checkpointLiveWorkout(force) {
        if (!hasAccountBinding() || GymSession.startedAt <= 0 ||
            GymSession.fitSaved) {
            return true;
        }
        if (!force && (GymSession.paused ||
            GymSession.elapsedSeconds - lastCompactCheckpointElapsed < 15)) {
            return true;
        }
        var checkpoint = currentTimelineCheckpoint(0.0);
        if (checkpoint == null) {
            return false;
        }
        var origin = activeWorkoutStartedAtSeconds;
        if (origin == null) {
            origin = runtimeWorkoutStartedAtSeconds;
        }
        if (origin == null) {
            origin = GymSession.startedAt;
        }
        if (!isValidWorkoutStartedAtSeconds(origin) ||
            !persistActiveWorkoutSnapshot(sets, origin, checkpoint)) {
            return false;
        }
        activeWorkoutStartedAtSeconds = origin;
        runtimeWorkoutStartedAtSeconds = origin;
        lastCompactCheckpointElapsed = GymSession.elapsedSeconds;
        return true;
    }

    (:compactCheckpoint96)
    static function checkpointLiveWorkout(force) {
        if (!hasAccountBinding() || GymSession.startedAt <= 0 ||
            GymSession.fitSaved || GymSession.paused) {
            return true;
        }
        if (GymSession.elapsedSeconds % 15 != 1) {
            return true;
        }
        var checkpoint = currentTimelineCheckpoint(0.0);
        var origin = sets.size() == 0 ? null : activeWorkoutStartedAtSeconds;
        if (checkpoint == null ||
            !persistActiveWorkoutSnapshot(sets, origin, checkpoint)) {
            return false;
        }
        if (runtimeWorkoutStartedAtSeconds == null) {
            runtimeWorkoutStartedAtSeconds = GymSession.startedAt;
        }
        return true;
    }

    (:fullLegacyState)
    static function consumeRecoveredPause() {
        var recovered = runtimePausePending;
        runtimePausePending = false;
        return recovered;
    }

    (:fullLegacyState)
    static function clearRuntimeCheckpoint() {
        try {
            Storage.deleteValue("activeRuntimeV1");
            resetRuntimeCheckpointState();
            return true;
        } catch (e) {
            status = "RECOVERY FAIL";
            return false;
        }
    }

    static function emptyTimelineCheckpoint() {
        return [0, 0.0, null, 0, 0, 0, null, 0];
    }

    static function setIntervalForCurrentTimeline(source) {
        var interval = GymSession.copySetInterval(source);
        var elapsedOffset = timelineBase == null ? 0 : timelineBase[0];
        if (!resumedWorkoutIntervalsInvalid && elapsedOffset > 0 &&
            isValidSetInterval(interval)) {
            var shiftedStart = interval[0] + elapsedOffset;
            var shiftedEnd = interval[1] + elapsedOffset;
            if (shiftedStart <= 604800 && shiftedEnd <= 604800) {
                interval[0] = shiftedStart;
                interval[1] = shiftedEnd;
            }
        }
        return interval;
    }

    (:fullLegacyState)
    static function persistActiveWorkoutSnapshot(nextSets, startedAtSeconds, checkpoint) {
        if (!hasAccountBinding()) {
            return false;
        }
        try {
            if (!isValidSetList(nextSets, maxWorkoutSets, true)) {
                status = "SAVE FAIL";
                return false;
            }
            var names = [];
            var weights = [];
            var setReps = [];
            var metrics = [];
            var intervals = checkpoint == null ? null : [];
            for (var i = 0; i < nextSets.size(); i += 1) {
                var item = nextSets[i];
                names.add(item.get("exerciseName").toString());
                weights.add(item.get("weight"));
                setReps.add(item.get("reps"));
                metrics.add(compactSetMetrics(item));
                if (intervals != null) {
                    intervals.add(item.get("setInterval"));
                }
            }
            var snapshot = [
                3,
                accountBinding.toString(),
                deviceBinding.toString(),
                isValidAccountBinding(pairingGeneration) ? pairingGeneration.toString() : null,
                startedAtSeconds,
                names,
                weights,
                setReps,
                metrics,
                intervals,
                checkpoint
            ];
            if (!isValidActiveWorkoutSnapshot(snapshot) ||
                !isWithinStorageBudgetForActiveSnapshot(snapshot)) {
                status = "STORE FULL";
                return false;
            }
            Storage.setValue("activeWorkoutV1", snapshot);
            activeWorkoutSnapshotValid = true;
            activeWorkoutTimelineValid = checkpoint != null;
            return true;
        } catch (e) {
            status = "SAVE FAIL";
            return false;
        }
    }

    (:compactLegacyState)
    static function persistActiveWorkoutSnapshot(nextSets, startedAtSeconds, checkpoint) {
        if (!hasAccountBinding()) {
            return false;
        }
        var compactSets = compatibilityActiveSetList(nextSets);
        if (!(compactSets instanceof Lang.Array)) {
            status = "SAVE FAIL";
            return false;
        }
        var snapshot = [
            3,
            accountBinding.toString(),
            deviceBinding.toString(),
            isValidAccountBinding(pairingGeneration) ? pairingGeneration.toString() : null,
            startedAtSeconds,
            compactSets,
            checkpoint
        ];
        if (!isValidActiveWorkoutSnapshot(snapshot) ||
            !isWithinStorageBudgetForActiveSnapshot(snapshot)) {
            status = "STORE FULL";
            return false;
        }
        try {
            Storage.setValue("activeWorkoutV1", snapshot);
            activeWorkoutSnapshotValid = true;
            activeWorkoutTimelineValid = checkpoint != null;
            return true;
        } catch (e) {
            status = "SAVE FAIL";
            return false;
        }
    }

    (:fullLegacyState)
    static function persistEmptyActiveWorkoutSnapshot() {
        if (!persistActiveWorkoutSnapshot([], null, emptyTimelineCheckpoint())) {
            return false;
        }
        if (!clearRuntimeCheckpoint()) {
            return false;
        }
        resetActiveWorkoutSnapshotState();
        activeWorkoutSnapshotValid = true;
        activeWorkoutTimelineValid = true;
        resumedWorkoutIntervalsInvalid = false;
        return true;
    }

    (:compactLegacyState)
    static function persistEmptyActiveWorkoutSnapshot() {
        if (!persistActiveWorkoutSnapshot([], null, emptyTimelineCheckpoint())) {
            return false;
        }
        runtimeWorkoutStartedAtSeconds = null;
        resetActiveWorkoutSnapshotState();
        activeWorkoutSnapshotValid = true;
        activeWorkoutTimelineValid = true;
        resumedWorkoutIntervalsInvalid = false;
        return true;
    }

    static function isUk() {
        return language.equals("uk");
    }

    static function isRu() {
        return language.equals("ru");
    }

    static function normalizedLanguage(value) {
        if (value != null && (value.equals("uk") || value.equals("ru"))) {
            return value;
        }
        return "en";
    }

    static function tr(en, uk, ru) {
        if (isUk()) {
            return uk;
        }
        return isRu() ? ru : en;
    }

    static function onOff(value) {
        if (isUk()) {
            return value ? "ТАК" : "НІ";
        }
        if (isRu()) {
            return value ? "ДА" : "НЕТ";
        }
        return value ? "ON" : "OFF";
    }

    static function currentExercise() {
        if (exercises.size() == 0) {
            return "Exercise";
        }
        if (exerciseIndex >= exercises.size()) {
            exerciseIndex = 0;
        }
        return exercises[exerciseIndex];
    }

    // Translate only at render time. Canonical exercise names remain unchanged in
    // storage, workout sets, phone messages, and cloud synchronization.
    static function currentExerciseLabel() {
        return localizedExerciseName(currentExercise());
    }

    static function localizedExerciseName(value) {
        var name = value == null ? "Exercise" : value.toString();
        if (exerciseLabelCacheName != null &&
            name.equals(exerciseLabelCacheName) &&
            language.equals(exerciseLabelCacheLanguage)) {
            return exerciseLabelCacheValue;
        }

        var label = name;
        if (isUk() || isRu()) {
            var table = App.loadResource(Rez.JsonData.ExerciseLabels) as Lang.Dictionary;
            var labels = table.get(name);
            if (labels instanceof Lang.Array && labels.size() == 2) {
                label = labels[isUk() ? 0 : 1].toString();
            }
        }
        exerciseLabelCacheName = name;
        exerciseLabelCacheLanguage = language;
        exerciseLabelCacheValue = label;
        return label;
    }

    static function applyCurrentPlanSet() {
        if (plan.size() == 0) {
            return false;
        }
        var exerciseName = currentExercise();
        var item = null;
        var completed = completedSetsForExercise(exerciseName);
        var matchingIndex = 0;
        for (var i = 0; i < plan.size(); i += 1) {
            var candidate = plan[i];
            if (candidate instanceof Lang.Dictionary &&
                candidate.get("exerciseName").toString().equals(exerciseName)) {
                if (matchingIndex == completed) {
                    item = candidate;
                    break;
                }
                matchingIndex += 1;
            }
        }
        return applyPlanItem(item);
    }

    static function applyPlanItem(item) {
        if (!(item instanceof Lang.Dictionary)) {
            return false;
        }
        var plannedWeight = item.get("weight");
        var plannedReps = item.get("reps");
        // The phone serializes Kotlin Double values. Validation accepts every
        // Connect IQ numeric representation, so application must use the same
        // contract or a valid plan can be ACKed while retaining stale kg.
        if (!isValidWeight(plannedWeight) || !isValidReps(plannedReps)) {
            return false;
        }
        weight = plannedWeight;
        reps = plannedReps;
        return true;
    }

    static function completedSetsForExercise(exerciseName) {
        var completed = 0;
        for (var i = 0; i < sets.size(); i += 1) {
            var item = sets[i];
            if (item instanceof Lang.Dictionary &&
                item.get("exerciseName").toString().equals(exerciseName)) {
                completed += 1;
            }
        }
        return completed;
    }

    static function remainingPlannedSetsForExercise(exerciseName) {
        var planned = 0;
        for (var i = 0; i < plan.size(); i += 1) {
            var item = plan[i];
            if (item instanceof Lang.Dictionary &&
                item.get("exerciseName").toString().equals(exerciseName)) {
                planned += 1;
            }
        }
        var remaining = planned - completedSetsForExercise(exerciseName);
        return remaining > 0 ? remaining : 0;
    }

    static function plannedSetsForExercise(exerciseName) {
        var planned = 0;
        for (var i = 0; i < plan.size(); i += 1) {
            var item = plan[i];
            if (item instanceof Lang.Dictionary &&
                item.get("exerciseName").toString().equals(exerciseName)) {
                planned += 1;
            }
        }
        return planned;
    }

    static function completedPlannedSetCount() {
        var completed = 0;
        for (var i = 0; i < sets.size(); i += 1) {
            var setItem = sets[i];
            if (!(setItem instanceof Lang.Dictionary)) {
                continue;
            }
            var exerciseName = setItem.get("exerciseName").toString();
            var earlierActual = 0;
            for (var j = 0; j < i; j += 1) {
                var earlierSet = sets[j];
                if (earlierSet instanceof Lang.Dictionary &&
                    earlierSet.get("exerciseName").toString().equals(exerciseName)) {
                    earlierActual += 1;
                }
            }
            if (earlierActual < plannedSetsForExercise(exerciseName)) {
                completed += 1;
            }
        }
        if (completed > plan.size()) {
            completed = plan.size();
        }
        return completed;
    }

    static function planSlotIsCompleted(planIndex) {
        if (planIndex < 0 || planIndex >= plan.size()) {
            return false;
        }
        var item = plan[planIndex];
        if (!(item instanceof Lang.Dictionary)) {
            return false;
        }
        var exerciseName = item.get("exerciseName").toString();
        var earlierPlanSlots = 0;
        for (var i = 0; i < planIndex; i += 1) {
            var earlier = plan[i];
            if (earlier instanceof Lang.Dictionary &&
                earlier.get("exerciseName").toString().equals(exerciseName)) {
                earlierPlanSlots += 1;
            }
        }
        return completedSetsForExercise(exerciseName) > earlierPlanSlots;
    }

    static function selectExerciseByName(exerciseName) {
        for (var i = 0; i < exercises.size(); i += 1) {
            if (exercises[i].toString().equals(exerciseName)) {
                exerciseIndex = i;
                return true;
            }
        }
        return false;
    }

    static function selectNextPlanSlotInGlobalOrder() {
        for (var i = 0; i < plan.size(); i += 1) {
            if (!planSlotIsCompleted(i)) {
                var item = plan[i];
                var exerciseName = item.get("exerciseName").toString();
                if (!selectExerciseByName(exerciseName)) {
                    return false;
                }
                return applyPlanItem(item);
            }
        }
        return false;
    }

    static function advancePlanAfterSetSaved() {
        // Preserve the exact order supplied by the phone (including circuits such
        // as A1, B1, A2, B2). Manual exercise selection can still jump to that
        // exercise's next target; automatic advancement resumes at the earliest
        // remaining global slot.
        selectNextPlanSlotInGlobalOrder();
    }

    static function nextExercise(delta) {
        if (exercises.size() == 0) {
            return;
        }
        exerciseIndex = (exerciseIndex + delta) % exercises.size();
        if (exerciseIndex < 0) {
            exerciseIndex += exercises.size();
        }
        applyCurrentPlanSet();
    }

    static function addSet() {
        if (sets.size() >= maxWorkoutSets ||
            !isValidExerciseName(currentExercise()) ||
            !isValidWeight(weight) ||
            !isValidReps(reps)) {
            status = "SET LIMIT";
            return false;
        }
        if (!hasAccountBinding() && !ensureUnboundAtomicQuarantine()) {
            // A fresh ownerless workout has no account/device tuple for activeWorkoutV1.
            // Establish the same single-value quarantine used by legacy ownerless data
            // before publishing its first mutation; it remains unsendable by design.
            status = "LEGACY FULL";
            return false;
        }
        var statistics = GymSession.captureSetStatistics();
        var setInterval = setIntervalForCurrentTimeline(statistics.get("setInterval"));
        var previousWorkoutStartedAt = activeWorkoutStartedAtSeconds;
        var nextWorkoutStartedAt = activeWorkoutStartedAtSeconds;
        if (nextWorkoutStartedAt == null &&
            !resumedWorkoutIntervalsInvalid && hasAccountBinding() &&
            (isValidWorkoutStartedAtSeconds(runtimeWorkoutStartedAtSeconds) ||
                isValidWorkoutStartedAtSeconds(GymSession.startedAt))) {
            // Commit the logical origin with the first durable set. Subsequent
            // process restarts can then label every persisted set with its real date.
            nextWorkoutStartedAt =
                isValidWorkoutStartedAtSeconds(runtimeWorkoutStartedAtSeconds) ?
                    runtimeWorkoutStartedAtSeconds : GymSession.startedAt;
        }
        var previousSets = sets;
        var nextSets = normalizedSetList(sets);
        var previousWeight = weight;
        var previousReps = reps;
        var previousExerciseIndex = exerciseIndex;
        var wasPlannedSet = remainingPlannedSetsForExercise(currentExercise()) > 0;
        // The first set has no preceding rest. After a process restart the prior
        // set end is also unknown, so do not manufacture a zero-second recovery.
        var restBefore = null;
        if (nextSets.size() > 0) {
            var previousSet = nextSets[nextSets.size() - 1];
            var currentStart = statistics.get("setStartedSeconds");
            if (lastLoggedSetEndSeconds > 0 && currentStart instanceof Lang.Number &&
                currentStart >= lastLoggedSetEndSeconds) {
                restBefore = currentStart - lastLoggedSetEndSeconds;
                if (restBefore > 86400) {
                    restBefore = 86400;
                }
            }
            var recoveryDrop = GymSession.recoveryHeartRateDrop();
            if (recoveryDrop != null) {
                previousSet.put("recoveryHeartRateDrop", recoveryDrop);
            }
        }
        var setItem = {
            "exerciseName" => currentExercise(),
            "weight" => weight,
            "reps" => reps,
            "activeSeconds" => statistics.get("activeSeconds"),
            "restBeforeSeconds" => restBefore,
            "startHeartRate" => statistics.get("startHeartRate"),
            "peakHeartRate" => statistics.get("peakHeartRate"),
            "endHeartRate" => statistics.get("endHeartRate"),
            "detectionConfidence" => statistics.get("detectionConfidence"),
            "setInterval" => setInterval
        };
        var wasAutoPrompt = GymSession.autoLogPrompt;
        var boost = GymSession.setBoostFor(weight, reps);
        setInterval[2] += boost;
        if (setInterval[2] > 100000.0) {
            setInterval[2] = 100000.0;
        }
        nextSets.add(setItem);

        var legacyOriginUnavailable = previousSets.size() > 0 &&
            previousWorkoutStartedAt == null && nextWorkoutStartedAt == null &&
            resumedWorkoutIntervalsInvalid;
        var usedAtomicSnapshot = hasAccountBinding() &&
            (isValidWorkoutStartedAtSeconds(nextWorkoutStartedAt) ||
                legacyOriginUnavailable);
        if (usedAtomicSnapshot) {
            var checkpoint = currentTimelineCheckpoint(boost);
            if (!resumedWorkoutIntervalsInvalid && checkpoint == null) {
                status = "SAVE FAIL";
                return false;
            }
            if (!persistActiveWorkoutSnapshot(nextSets, nextWorkoutStartedAt, checkpoint)) {
                return false;
            }
            // The atomic snapshot is now the rollback boundary. Release the old
            // expanded graph before building the small downgrade mirror below.
            previousSets = null;
        }

        // Only publish globals and calorie corrections after the single-value
        // snapshot commit succeeds. A thrown Object Store write leaves the old set
        // list and detector totals untouched.
        sets = nextSets;
        activeWorkoutStartedAtSeconds = nextWorkoutStartedAt;
        GymSession.restoreSetBoost(boost);
        if (wasPlannedSet) {
            advancePlanAfterSetSaved();
        }
        var compatibilitySaved = save();
        var legacySnapshotCommitted = legacyUnboundState &&
            legacyCurrentSetCount() == nextSets.size();
        if (!compatibilitySaved && !usedAtomicSnapshot && !legacySnapshotCommitted) {
            sets = previousSets;
            weight = previousWeight;
            reps = previousReps;
            exerciseIndex = previousExerciseIndex;
            activeWorkoutStartedAtSeconds = previousWorkoutStartedAt;
            GymSession.removeSetBoost(boost);
            if (!save()) {
                status = "RECOVERY FAIL";
            }
            return false;
        }
        lastSetBoost = boost;
        lastSetWasAutoPrompt = wasAutoPrompt;
        lastSetStatistics = statistics;
        lastSetPreviousLoggedEnd = lastLoggedSetEndSeconds;
        lastLoggedSetEndSeconds = statistics.get("setEndedSeconds");
        var actionTimerMs = System.getTimer();
        lastSetUndoStartedAt = actionTimerMs;
        GymSession.beginRecoveryTracking(statistics);
        GymSession.clearAutoPrompt();
        restDurationMs = restSecondsDefault * 1000;
        restStartedAt = actionTimerMs;
        // The atomic snapshot is the commit; compatibility mirror failures do
        // not turn a successfully stored athlete action into a UI error.
        status = "SET SAVED";
        return true;
    }

    static function canUndoLastSet() {
        if (sets.size() == 0 || lastSetUndoStartedAt == null) {
            return false;
        }
        if (timerElapsedMs(lastSetUndoStartedAt) > undoWindowMs) {
            clearTransientSetActions();
            return false;
        }
        return true;
    }

    static function undoLastSet() {
        if (!canUndoLastSet()) {
            status = "UNDO EXPIRED";
            return false;
        }
        if (!hasAccountBinding() && !ensureUnboundAtomicQuarantine()) {
            status = "LEGACY FULL";
            return false;
        }
        var previousSets = sets;
        var lastIndex = previousSets.size() - 1;
        var lastSet = previousSets[lastIndex];
        var nextSets = normalizedSetList(previousSets);
        nextSets.remove(nextSets[nextSets.size() - 1]);
        var boost = lastSetBoost;
        var restorePrompt = lastSetWasAutoPrompt;
        var restoreStatistics = lastSetStatistics;
        var previousLoggedEnd = lastSetPreviousLoggedEnd;
        var previousWeight = weight;
        var previousReps = reps;
        var previousExerciseIndex = exerciseIndex;
        var previousWorkoutStartedAt = activeWorkoutStartedAtSeconds;
        var nextWorkoutStartedAt = previousWorkoutStartedAt;
        if (nextSets.size() == 0) {
            nextWorkoutStartedAt = null;
        }

        var legacyOriginUnavailable = nextSets.size() > 0 &&
            previousWorkoutStartedAt == null && nextWorkoutStartedAt == null &&
            resumedWorkoutIntervalsInvalid;
        var usedAtomicSnapshot = hasAccountBinding() &&
            (nextSets.size() == 0 || isValidWorkoutStartedAtSeconds(nextWorkoutStartedAt) ||
                legacyOriginUnavailable);
        if (usedAtomicSnapshot) {
            var checkpoint = nextSets.size() == 0 ?
                emptyTimelineCheckpoint() : currentTimelineCheckpoint(-boost);
            if (!resumedWorkoutIntervalsInvalid && checkpoint == null) {
                status = "SAVE FAIL";
                return false;
            }
            if (!persistActiveWorkoutSnapshot(nextSets, nextWorkoutStartedAt, checkpoint)) {
                return false;
            }
            previousSets = null;
        }

        sets = nextSets;
        activeWorkoutStartedAtSeconds = nextWorkoutStartedAt;
        GymSession.removeSetBoost(boost);
        weight = lastSet.get("weight");
        reps = lastSet.get("reps");
        for (var e = 0; e < exercises.size(); e += 1) {
            if (exercises[e].toString().equals(lastSet.get("exerciseName").toString())) {
                exerciseIndex = e;
                break;
            }
        }
        // Undo returns the exact values the athlete saved, including deliberate
        // deviations from the plan. Removing the set already rewinds the plan cursor.
        var compatibilitySaved = save();
        var legacySnapshotCommitted = legacyUnboundState &&
            legacyCurrentSetCount() == nextSets.size();
        if (!compatibilitySaved && !usedAtomicSnapshot && !legacySnapshotCommitted) {
            sets = previousSets;
            weight = previousWeight;
            reps = previousReps;
            exerciseIndex = previousExerciseIndex;
            activeWorkoutStartedAtSeconds = previousWorkoutStartedAt;
            GymSession.restoreSetBoost(boost);
            if (!save()) {
                status = "RECOVERY FAIL";
            }
            return false;
        }
        clearTransientSetActions();
        lastLoggedSetEndSeconds = previousLoggedEnd;
        restDurationMs = 0;
        restStartedAt = null;
        // Both automatic and manual commits clear the detector after saving. Undo
        // must restore the captured interval/HR/calorie snapshot in either case;
        // only the prompt visibility differs.
        GymSession.restoreSetAfterUndo(restoreStatistics, restorePrompt);
        status = "SET UNDONE";
        return true;
    }

    static function clearTransientSetActions() {
        lastSetUndoStartedAt = null;
        lastSetBoost = 0.0;
        lastSetWasAutoPrompt = false;
        lastSetStatistics = null;
        lastSetPreviousLoggedEnd = 0;
    }

    static function adjustWeightStep(delta) {
        if (delta < 0) {
            if (weightStep > 5.0) {
                weightStep = 5.0;
            } else if (weightStep > 2.5) {
                weightStep = 2.5;
            } else {
                weightStep = 10.0;
            }
        } else if (weightStep < 5.0) {
            weightStep = 5.0;
        } else if (weightStep < 10.0) {
            weightStep = 10.0;
        } else {
            weightStep = 2.5;
        }
        save();
    }

    static function adjustRestDefault(delta) {
        if (delta < 0) {
            if (restSecondsDefault > 120) {
                restSecondsDefault = 120;
            } else if (restSecondsDefault > 90) {
                restSecondsDefault = 90;
            } else if (restSecondsDefault > 60) {
                restSecondsDefault = 60;
            } else {
                restSecondsDefault = 180;
            }
        } else if (restSecondsDefault < 90) {
            restSecondsDefault = 90;
        } else if (restSecondsDefault < 120) {
            restSecondsDefault = 120;
        } else if (restSecondsDefault < 180) {
            restSecondsDefault = 180;
        } else {
            restSecondsDefault = 60;
        }
        save();
    }

    static function toggleAutoPrompt() {
        autoPromptEnabled = !autoPromptEnabled;
        if (!autoPromptEnabled) {
            GymSession.clearAutoPrompt();
        }
        save();
    }

    static function adjustSensitivity(delta) {
        sensitivityIndex = (sensitivityIndex + (delta < 0 ? 2 : 1)) % 3;
        save();
    }

    static function sensitivityLabel() {
        if (sensitivityIndex == 0) {
            return tr("LOW", "НИЗ", "НИЗ");
        } else if (sensitivityIndex == 2) {
            return tr("HIGH", "ВИС", "ВЫС");
        }
        return tr("NORMAL", "НОРМ", "НОРМ");
    }

    static function clearWorkout() {
        if (hasAccountBinding() && !persistEmptyActiveWorkoutSnapshot()) {
            status = "SAVE FAIL";
            return false;
        }
        sets = [];
        plan = [];
        activeWorkoutStartedAtSeconds = null;
        resumedWorkoutIntervalsInvalid = false;
        restDurationMs = 0;
        restStartedAt = null;
        lastLoggedSetEndSeconds = 0;
        clearTransientSetActions();
        applyDeferredSyncIfIdle();
        var cleared = save();
        if (cleared) {
            clearPreparedWorkout(null);
        }
        return cleared;
    }

    static function markWorkoutResumed() {
        if (sets.size() > 0 && !activeWorkoutTimelineValid) {
            resumedWorkoutIntervalsInvalid = true;
        }
    }

    static function hasUnfinishedWorkout() {
        if (sets.size() > 0 || activeWorkoutStartedAtSeconds != null ||
            runtimeWorkoutStartedAtSeconds != null) {
            return true;
        }
        if (!activeWorkoutSnapshotValid ||
            !(timelineBase instanceof Lang.Array) ||
            !isValidTimelineCheckpoint(timelineBase)) {
            return false;
        }
        // The durable empty snapshot is a tombstone, not a workout. A zero-set
        // runtime becomes resumable only after it contains real elapsed/metric
        // state (or has the explicit runtime origin checked above).
        return timelineBase[0] > 0 || timelineBase[1] > 0.0 ||
            timelineBase[2] != null || timelineBase[4] > 0 ||
            timelineBase[5] > 0 || timelineBase[6] != null;
    }

    static function clearActiveWorkout() {
        var atomicallyCleared = false;
        if (hasAccountBinding()) {
            if (!persistEmptyActiveWorkoutSnapshot()) {
                status = "SAVE FAIL";
                return false;
            }
            atomicallyCleared = true;
        }
        sets = [];
        activeWorkoutStartedAtSeconds = null;
        resumedWorkoutIntervalsInvalid = false;
        restDurationMs = 0;
        restStartedAt = null;
        lastLoggedSetEndSeconds = 0;
        clearTransientSetActions();
        applyDeferredSyncIfIdle();
        var compatibilitySaved = save();
        return compatibilitySaved || atomicallyCleared;
    }

    static function restSeconds() {
        if (restDurationMs <= 0 || restStartedAt == null) {
            return 0;
        }
        var remaining = restDurationMs.toLong() - timerElapsedMs(restStartedAt);
        if (remaining <= 0) {
            restDurationMs = 0;
            restStartedAt = null;
            return 0;
        }
        return (remaining / 1000l).toNumber();
    }

    // System.getTimer() is a signed 32-bit millisecond counter. It crosses from
    // positive to negative after roughly 25 days, so deadlines based on raw
    // comparisons fail on watches that remain powered on. Compute elapsed time
    // modulo 2^32 instead; every caller uses a short bounded window.
    static function timerElapsedMs(startedAt) {
        var elapsed = System.getTimer().toLong() - startedAt.toLong();
        return elapsed < 0l ? elapsed + 4294967296l : elapsed;
    }

    static function restorePreparedWorkout(value) {
        if (isValidPreparedWorkout(value) &&
            activeWorkoutSnapshotMatchesBindings(value)) {
            preparedWorkout = value;
            return;
        }
        preparedWorkout = null;
        if (value != null) {
            try {
                Storage.deleteValue("preparedWorkoutV1");
            } catch (e) {
                // Binding checks remain authoritative even if stale storage
                // cannot be removed during this lifecycle.
            }
        }
    }

    static function isValidPreparedWorkout(value) {
        return value instanceof Lang.Array && value.size() == 6 &&
            value[0] instanceof Lang.Number && value[0] == 1 &&
            isValidAccountBinding(value[1]) &&
            isBoundedText(value[2], maxBindingLength) &&
            isValidOptionalAccountBinding(value[3]) &&
            isBoundedText(value[4], maxBindingLength) &&
            isBoundedInteger(value[5], 0, 1);
    }

    static function hasPreparedWorkout() {
        return preparedWorkout != null &&
            isValidPreparedWorkout(preparedWorkout) &&
            activeWorkoutSnapshotMatchesBindings(preparedWorkout) &&
            sets.size() > 0;
    }

    static function preparedWorkoutFitSaved() {
        return hasPreparedWorkout() && preparedWorkout[5] == 1;
    }

    (:recoveryCore)
    static function preparedWorkoutNeedsFitDecision() {
        return hasPreparedWorkout() && preparedWorkout[5] == 0;
    }

    static function prepareWorkoutCommit() {
        if (!hasAccountBinding() ||
            !isValidSetList(sets, maxWorkoutSets, false)) {
            return false;
        }
        if (hasPreparedWorkout()) {
            return true;
        }
        var marker = [
            1,
            accountBinding.toString(),
            deviceBinding.toString(),
            isValidAccountBinding(pairingGeneration) ?
                pairingGeneration.toString() : null,
            nextRequestId("workout"),
            0
        ];
        try {
            Storage.setValue("preparedWorkoutV1", marker);
            preparedWorkout = marker;
            return true;
        } catch (e) {
            status = "SAVE FAIL";
            return false;
        }
    }

    static function markPreparedWorkoutFitSaved() {
        if (!hasPreparedWorkout()) {
            return false;
        }
        if (preparedWorkout[5] == 1) {
            return true;
        }
        preparedWorkout[5] = 1;
        try {
            Storage.setValue("preparedWorkoutV1", preparedWorkout);
            status = "FIT SAVED";
            return true;
        } catch (e) {
            // FIT is already durable. Keep every GymApp set intact and make the
            // uncertainty visible; never enqueue without the phase-1 marker.
            preparedWorkout[5] = 0;
            status = "FIT CHECK";
            return false;
        }
    }

    static function clearPreparedWorkout(requestId) {
        if (preparedWorkout == null ||
            (requestId != null &&
                !preparedWorkout[4].toString().equals(requestId.toString()))) {
            return;
        }
        preparedWorkout = null;
        try {
            Storage.deleteValue("preparedWorkoutV1");
        } catch (e) {
            // A stale marker is harmless once the matching pending request is
            // durable; recoverQueuedWorkout clears it idempotently on next load.
        }
    }

    static function preparedWorkoutMessage() {
        if (!preparedWorkoutFitSaved()) {
            return null;
        }
        return workoutMessage(preparedWorkout[4].toString());
    }

    // A process can disappear after the durable phase-0 marker but before the
    // FIT API result is known. This explicit user-authorized path keeps the same
    // stable request id and relies on queueWorkout's existing marker->queue->
    // tombstone transaction. It deliberately does not mutate phase 0: a crash
    // before the durable queue simply asks again, while a crash after it is
    // recovered idempotently by queuedActiveRequestId.
    (:recoveryCore)
    static function preparedWorkoutSetsOnlyMessage() {
        if (!preparedWorkoutNeedsFitDecision() ||
            !GymSession.fitOutcomeUnknownAfterRestart()) {
            return null;
        }
        return workoutMessage(preparedWorkout[4].toString());
    }

    // Low-memory watches resolve an unknown post-restart FIT outcome only after
    // the athlete explicitly retries Save & Exit. Keep phase 0 unchanged and
    // reuse its stable request id; queueWorkout owns the durable tombstone.
    (:compactRecovery96)
    static function preparedWorkoutSetsOnlyMessage() {
        if (!hasPreparedWorkout() || preparedWorkout[5] != 0 ||
            !GymSession.fitOutcomeUnknownAfterRestart()) {
            return null;
        }
        return workoutMessage(preparedWorkout[4].toString());
    }

    static function restoreLastWorkoutSync(value) {
        if (value instanceof Lang.Array && value.size() == 3 &&
            value[0] instanceof Lang.Number && value[0] == 1 &&
            isValidAccountBinding(value[1]) && hasAccountBinding() &&
            value[1].toString().equals(accountBinding.toString()) &&
            isValidWorkoutStartedAtSeconds(value[2])) {
            lastWorkoutSyncAtSeconds = value[2];
        } else {
            lastWorkoutSyncAtSeconds = null;
        }
    }

    (:fullLegacyState)
    static function lastWorkoutSyncText() {
        if (lastWorkoutSyncAtSeconds == null) {
            return tr("NEVER", "НІКОЛИ", "НИКОГДА");
        }
        var age = Time.now().value() - lastWorkoutSyncAtSeconds;
        if (age < 0 || age < 60) {
            return tr("NOW", "ЗАРАЗ", "СЕЙЧАС");
        }
        if (age < 3600) {
            return (age / 60).toString() + tr("m", "хв", "м");
        }
        if (age < 86400) {
            return (age / 3600).toString() + tr("h", "г", "ч");
        }
        var days = age / 86400;
        if (days > 99) {
            days = 99;
        }
        return days.toString() + tr("d", "д", "д");
    }

    (:compactLegacyState)
    static function lastWorkoutSyncText() {
        if (lastWorkoutSyncAtSeconds == null) {
            return tr("NEVER", "НІК", "НИК");
        }
        var age = Time.now().value() - lastWorkoutSyncAtSeconds;
        return age >= 0 && age < 3600 ?
            tr("RECENT", "НЕДАВНО", "НЕДАВНО") :
            tr("EARLIER", "РАНІШЕ", "РАНЬШЕ");
    }

    static function restoreTutorialHistory(value) {
        tutorialHistory = [];
        if (!(value instanceof Lang.Array) || value.size() > maxTutorialAccounts) {
            return;
        }
        for (var i = 0; i < value.size(); i += 1) {
            var item = value[i];
            if (!isValidAccountBinding(item)) {
                tutorialHistory = [];
                return;
            }
            tutorialHistory.add(item.toString());
        }
    }

    static function tutorialHandledForActiveAccount() {
        if (!hasAccountBinding()) {
            return false;
        }
        for (var i = 0; i < tutorialHistory.size(); i += 1) {
            var item = tutorialHistory[i];
            if (item.toString().equals(accountBinding.toString())) {
                return true;
            }
        }
        return false;
    }

    static function shouldStartTutorial() {
        return hasAccountBinding() && !tutorialHandledForActiveAccount() &&
            !hasUnfinishedWorkout() && !hasPreparedWorkout();
    }

    static function markTutorialHandled() {
        if (!hasAccountBinding()) {
            return false;
        }
        var next = [];
        for (var i = 0; i < tutorialHistory.size(); i += 1) {
            var item = tutorialHistory[i];
            if (!item.toString().equals(accountBinding.toString())) {
                next.add(item);
            }
        }
        next.add(accountBinding.toString());
        while (next.size() > maxTutorialAccounts) {
            next.remove(next[0]);
        }
        var previous = tutorialHistory;
        tutorialHistory = next;
        if (save()) {
            return true;
        }
        tutorialHistory = previous;
        return false;
    }

    static function workoutMessage(requestId) {
        if (!hasAccountBinding() || !isValidSetList(sets, maxWorkoutSets, false)) {
            return null;
        }
        if (!isBoundedText(requestId, maxBindingLength)) {
            return null;
        }
        var setCopies = [];
        var setMetrics = [];
        var setIntervals = [];
        var messageCheckpoint = activeWorkoutTimelineValid &&
            !resumedWorkoutIntervalsInvalid ? currentTimelineCheckpoint(0.0) : null;
        var allIntervalsAvailable = messageCheckpoint != null;
        for (var i = 0; i < sets.size(); i += 1) {
            var setItem = sets[i];
            if (!(setItem instanceof Lang.Dictionary)) {
                return null;
            }
            var exerciseName = setItem.get("exerciseName");
            var setWeight = setItem.get("weight");
            var setReps = setItem.get("reps");
            if (!isValidExerciseName(exerciseName) || !isValidWeight(setWeight) || !isValidReps(setReps)) {
                return null;
            }
            var setCopy = {
                "exerciseName" => exerciseName.toString(),
                "weight" => setWeight,
                "reps" => setReps
            };
            setCopies.add(setCopy);
            setMetrics.add(compactSetMetrics(setItem));
            var setInterval = setItem.get("setInterval");
            if (isValidSetInterval(setInterval)) {
                setIntervals.add(copySetInterval(setInterval));
            } else {
                allIntervalsAvailable = false;
            }
        }
        if (setMetrics.size() > 0) {
            var latestRecovery = GymSession.recoveryHeartRateDrop();
            if (latestRecovery != null) {
                setMetrics[setMetrics.size() - 1][5] = latestRecovery;
            }
        }
        var messageStartedAt = isValidWorkoutStartedAtSeconds(activeWorkoutStartedAtSeconds) ?
            activeWorkoutStartedAtSeconds : GymSession.startedAt;
        var message = {
            "type" => "create_workout",
            "bindingVersion" => bindingVersion,
            "requestId" => requestId,
            "accountBinding" => accountBinding,
            "deviceBinding" => deviceBinding,
            // New workouts persist their logical origin with the first set. Only
            // legacy in-progress workouts without that key fall back to the honest
            // beginning of the current resumed recording segment.
            "startedAtSeconds" => messageStartedAt,
            "sets" => setCopies,
            "setMetrics" => setMetrics
        };
        if (messageCheckpoint != null) {
            message.put("durationSeconds", messageCheckpoint[0]);
            message.put("gymCalories", messageCheckpoint[1]);
            var combinedSamples = messageCheckpoint[4];
            var combinedAverage = combinedSamples > 0 ?
                (messageCheckpoint[3] / combinedSamples).toNumber() : 0;
            message.put("avgHeartRate", combinedAverage);
            message.put("maxHeartRate", messageCheckpoint[5]);
            message.put("heartRateZone", messageCheckpoint[7]);
            // Optional scalar diagnostics must be absent, rather than explicit
            // null, so released phone parsers can accept a workout when the
            // Garmin system calorie or heart-rate source is unavailable.
            if (messageCheckpoint[2] != null) {
                message.put("garminCalories", messageCheckpoint[2]);
            }
            if (messageCheckpoint[6] != null) {
                message.put("lastHeartRate", messageCheckpoint[6]);
            }
        }
        if (allIntervalsAvailable && setIntervals.size() == setCopies.size() &&
            areSetIntervalsConsistent(
                setIntervals,
                messageCheckpoint[0],
                messageCheckpoint[1],
                messageCheckpoint[2]
            )) {
            message.put("setIntervals", setIntervals);
        }
        if (plan.size() > 0) {
            var plannedTargetSetCount = plan.size();
            // Released phone parsers require the legacy field to be at least the
            // number of actual sets. Keep that compatibility envelope while the
            // exact target/progress pair carries honest plan completion for new clients.
            var plannedSetCount = plannedTargetSetCount;
            if (plannedSetCount < setCopies.size()) {
                plannedSetCount = setCopies.size();
            }
            message.put("plannedSetCount", plannedSetCount);
            message.put("plannedTargetSetCount", plannedTargetSetCount);
            message.put("completedPlannedSetCount", completedPlannedSetCount());
        }
        if (isValidAccountBinding(pairingGeneration)) {
            message.put("pairingGeneration", pairingGeneration.toString());
        }
        return message;
    }

    static function applyPhoneSync(message) {
        return applySyncFromSource(message, "phone");
    }

    (:fullLegacyState)
    static function applyCloudSync(message) {
        return applySyncFromSource(message, "cloud");
    }

    (:fullLegacyState)
    static function applySyncFromSource(message, bindingSource) {
        if (!isValidSyncMessage(message, bindingSource)) {
            status = "BAD SYNC";
            return false;
        }

        // Never retain the transport-owned dictionary. Rebuilding the message from
        // validated scalar/array fields prevents unknown or deeply nested values from
        // entering the persistent deferred-sync state.
        var safeMessage = normalizedSyncMessage(message, bindingSource);

        var nextAccountBinding = safeMessage.get("accountBinding").toString();
        var nextDeviceBinding = safeMessage.get("deviceBinding").toString();
        var nextPairingGeneration = safeMessage.get("pairingGeneration");
        var replayKey = bindingSource + ":" + safeMessage.get("requestId").toString();
        var resetValue = safeMessage.get("resetWorkout");
        var resetWorkout = bindingSource.equals("phone") &&
            resetValue instanceof Lang.Boolean && resetValue;
        var repairValue = safeMessage.get("repairPairing");
        var repairPairing = bindingSource.equals("phone") &&
            repairValue instanceof Lang.Boolean && repairValue;
        var accountChanged = accountBinding == null ||
            !accountBinding.toString().equals(nextAccountBinding);
        if (bindingSource.equals("cloud") && stagedPhoneSyncRevision > 0l &&
            !hasAccountBinding()) {
            // A phone auth transition removed the previous owner but has not committed.
            // Do not let a stale cloud token reclaim the watch during that fail-closed gap.
            status = "BAD BIND";
            return false;
        }
        if (bindingSource.equals("phone") && accountBinding != null &&
            accountChanged && !resetWorkout) {
            // Once a watch has an owner, only the exact empty auth-transition command
            // may change it. A normal plan from another account must not erase state.
            status = "BAD BIND";
            return false;
        }
        if (bindingSource.equals("cloud") && accountBinding != null && accountChanged) {
            // A stale or replaced cloud token must never switch the watch back to another
            // account. Only the bound phone flow may perform an explicit account transition.
            status = "BAD BIND";
            return false;
        }
        if (bindingSource.equals("phone") && deviceBinding != null &&
            !deviceBinding.toString().equals(nextDeviceBinding)) {
            status = "BAD BIND";
            return false;
        }
        if (bindingSource.equals("phone") && isValidAccountBinding(pairingGeneration)) {
            if (!isValidAccountBinding(nextPairingGeneration)) {
                if (!resetWorkout) {
                    status = "PAIR OLD";
                    return false;
                }
            } else if (!pairingGeneration.toString().equals(nextPairingGeneration.toString()) &&
                !resetWorkout && !repairPairing) {
                status = "PAIR OLD";
                return false;
            }
        }
        if (bindingSource.equals("cloud") && cloudDeviceBinding != null &&
            !cloudDeviceBinding.toString().equals(nextDeviceBinding)) {
            status = "BAD BIND";
            return false;
        }

        // The phone revision is global to this Garmin device and is checked before any
        // account-scoped state is cleared. A delayed message from the previous account can
        // therefore never switch the watch back after a newer account transition.
        var revisionStatus = syncRevisionStatus(safeMessage, bindingSource);
        var repairReplay = repairPairing &&
            isValidAccountBinding(pairingGeneration) &&
            isValidAccountBinding(nextPairingGeneration) &&
            pairingGeneration.toString().equals(nextPairingGeneration.toString()) &&
            (revisionStatus == 0 || isExactStagedSync(safeMessage, bindingSource));
        if (repairPairing &&
            (resetWorkout || accountChanged || !isValidAccountBinding(pairingGeneration) ||
                !isValidAccountBinding(nextPairingGeneration) ||
                (pairingGeneration.toString().equals(nextPairingGeneration.toString()) &&
                    !repairReplay))) {
            status = "BAD BIND";
            return false;
        }
        if (revisionStatus < 0) {
            status = "SYNC OLD";
            return false;
        }
        if (revisionStatus == 0) {
            if (isExactStagedSync(safeMessage, bindingSource) &&
                !syncBindingsMatch(safeMessage)) {
                // The fence committed but the owner marker did not. Reapply only this
                // exact staged message; duplicates with a valid owner remain no-op.
                revisionStatus = 1;
            } else {
                status = "SYNC DUP";
                clearSyncStageIfMatches(safeMessage, bindingSource);
                return true;
            }
        }
        // Persist the global replay barrier before destructive account-transition writes.
        if (!stageSync(safeMessage, bindingSource)) {
            status = "SAVE FAIL";
            return false;
        }

        if (accountChanged || resetWorkout) {
            if (legacyUnboundState &&
                (!ensureLegacyQuarantine() || !refreshLegacyCurrentQuarantine())) {
                // Never destroy or attach ownerless pre-upgrade data implicitly. The
                // replay stage remains durable, so only this exact/newer sync can retry.
                status = "LEGACY FULL";
                return false;
            }
            if (!beginAccountTransition()) {
                status = "SAVE FAIL";
                return false;
            }
            if (bindingSource.equals("phone") &&
                !clearCloudSyncStageForAccountTransition()) {
                // The owner marker is already gone. Keep the watch fail-closed until
                // the stale cloud stage can be removed by an exact/newer phone retry.
                clearAccountScopedState();
                GymSession.resetForAccountTransition();
                status = "SAVE FAIL";
                return false;
            }
            if (bindingSource.equals("phone") &&
                !GymComm.reconcileCloudDeviceToken(nextAccountBinding)) {
                clearAccountScopedState();
                GymSession.resetForAccountTransition();
                status = "TOKEN SAVE";
                return false;
            }
            // A new account/device, logout, or fresh authenticated session must never
            // inherit an active workout, cached plan, or unsent workout. The reset flag
            // has already been restricted to an empty, revisioned phone message, and this
            // branch runs only after its replay barrier was durably staged.
            clearAccountScopedState();
            GymSession.resetForAccountTransition();
            legacyUnboundState = false;
        }
        accountBinding = nextAccountBinding;
        if (bindingSource.equals("cloud")) {
            cloudDeviceBinding = nextDeviceBinding;
        } else {
            deviceBinding = nextDeviceBinding;
            var previousPairingGeneration = pairingGeneration;
            var shouldUpgradePending = !isValidAccountBinding(pairingGeneration) &&
                isValidAccountBinding(nextPairingGeneration);
            pairingGeneration = isValidAccountBinding(nextPairingGeneration) ?
                nextPairingGeneration.toString() : null;
            if ((shouldUpgradePending || repairPairing) &&
                !rotatePairingGenerationForPending(
                    previousPairingGeneration,
                    pairingGeneration
                )) {
                load();
                status = "SAVE FAIL";
                return false;
            }
        }
        rememberSyncRequest(replayKey);
        rememberSyncRevision(safeMessage, bindingSource);

        // Language is independent of plan replacement and is safe to apply while
        // a workout is active. The plan itself remains deferred until the set list
        // is idle, but EN/UK/RU changes immediately and durably with this sync.
        applyValidatedLanguage(safeMessage);

        if (sets.size() > 0) {
            deferredSync = safeMessage;
            status = "PLAN WAIT";
            if (save()) {
                clearSyncStageIfMatches(safeMessage, bindingSource);
                return true;
            }
            load();
            status = "SAVE FAIL";
            return false;
        }

        applyValidatedSync(safeMessage);
        if (save()) {
            clearSyncStageIfMatches(safeMessage, bindingSource);
            return true;
        }
        load();
        status = "SAVE FAIL";
        return false;
    }

    (:compactLegacyState)
    static function applySyncFromSource(message, bindingSource) {
        if (!bindingSource.equals("phone") ||
            !isValidSyncMessage(message, bindingSource)) {
            status = "BAD SYNC";
            return false;
        }
        var safeMessage = normalizedSyncMessage(message, bindingSource);
        var nextAccount = safeMessage.get("accountBinding").toString();
        var nextDevice = safeMessage.get("deviceBinding").toString();
        var nextGeneration = safeMessage.get("pairingGeneration");
        var resetValue = safeMessage.get("resetWorkout");
        var resetWorkout = resetValue instanceof Lang.Boolean && resetValue;
        var repairValue = safeMessage.get("repairPairing");
        var repairPairing = repairValue instanceof Lang.Boolean && repairValue;
        var accountChanged = accountBinding == null ||
            !accountBinding.toString().equals(nextAccount);

        if ((accountBinding != null && accountChanged && !resetWorkout) ||
            (deviceBinding != null && !deviceBinding.toString().equals(nextDevice))) {
            status = "BAD BIND";
            return false;
        }
        if (isValidAccountBinding(pairingGeneration) &&
            (!isValidAccountBinding(nextGeneration) ||
                (!pairingGeneration.toString().equals(nextGeneration.toString()) &&
                    !resetWorkout && !repairPairing))) {
            status = "PAIR OLD";
            return false;
        }
        var revisionStatus = syncRevisionStatus(safeMessage, bindingSource);
        if (revisionStatus < 0) {
            status = "SYNC OLD";
            return false;
        }
        if (revisionStatus == 0 && !isExactStagedSync(safeMessage, bindingSource)) {
            status = "SYNC DUP";
            return true;
        }
        if (!stageSync(safeMessage, bindingSource)) {
            status = "SAVE FAIL";
            return false;
        }
        if (accountChanged || resetWorkout) {
            if ((legacyUnboundState &&
                    (!ensureLegacyQuarantine() || !refreshLegacyCurrentQuarantine())) ||
                !beginAccountTransition() ||
                !clearCloudSyncStageForAccountTransition() ||
                !GymComm.reconcileCloudDeviceToken(nextAccount)) {
                status = "SAVE FAIL";
                return false;
            }
            clearAccountScopedState();
            GymSession.resetForAccountTransition();
            legacyUnboundState = false;
        }
        accountBinding = nextAccount;
        deviceBinding = nextDevice;
        var previousGeneration = pairingGeneration;
        pairingGeneration = isValidAccountBinding(nextGeneration) ?
            nextGeneration.toString() : null;
        if ((repairPairing ||
                (!isValidAccountBinding(previousGeneration) &&
                    isValidAccountBinding(pairingGeneration))) &&
            !rotatePairingGenerationForPending(previousGeneration, pairingGeneration)) {
            load();
            status = "SAVE FAIL";
            return false;
        }
        rememberSyncRequest("phone:" + safeMessage.get("requestId").toString());
        rememberSyncRevision(safeMessage, bindingSource);
        applyValidatedLanguage(safeMessage);
        if (sets.size() > 0) {
            deferredSync = safeMessage;
            status = "PLAN WAIT";
        } else {
            applyValidatedSync(safeMessage);
        }
        if (save()) {
            clearSyncStageIfMatches(safeMessage, bindingSource);
            return true;
        }
        load();
        status = "SAVE FAIL";
        return false;
    }

    static function applyValidatedSync(message) {
        applyValidatedLanguage(message);
        var flatNames = message.get("planNames");
        var flatWeights = message.get("planWeights");
        var flatReps = message.get("planReps");
        if (flatNames.size() > 0) {
            var flatPlan = [];
            var plannedExercises = [];
            for (var f = 0; f < flatNames.size(); f += 1) {
                var flatName = flatNames[f].toString();
                var flatWeight = flatWeights[f];
                var flatRep = flatReps[f];
                flatPlan.add({ "exerciseName" => flatName, "weight" => flatWeight, "reps" => flatRep });
                if (!containsName(plannedExercises, flatName)) {
                    plannedExercises.add(flatName);
                }
            }
            GymStore.plan = flatPlan;
            if (plannedExercises.size() > 0) {
                exercises = plannedExercises;
                exerciseIndex = 0;
                applyCurrentPlanSet();
            }
            status = "PLAN " + flatPlan.size().toString();
        } else {
            GymStore.plan = [];
            var syncedExercises = message.get("exercises");
            if (syncedExercises instanceof Lang.Array && syncedExercises.size() > 0) {
                var safeExercises = [];
                for (var e = 0; e < syncedExercises.size(); e += 1) {
                    var safeName = syncedExercises[e].toString();
                    if (!containsName(safeExercises, safeName)) {
                        safeExercises.add(safeName);
                    }
                }
                exercises = safeExercises;
                exerciseIndex = 0;
                status = "EX " + safeExercises.size().toString();
            } else {
                GymStore.plan = [];
                status = "EMPTY PLAN";
            }
        }
    }

    static function applyValidatedLanguage(message) {
        var syncedLanguage = message.get("language");
        if (syncedLanguage != null) {
            language = normalizedLanguage(syncedLanguage.toString());
        }
    }

    static function applyDeferredSyncIfIdle() {
        if (sets.size() != 0 || !(deferredSync instanceof Lang.Dictionary)) {
            return;
        }
        var message = deferredSync;
        deferredSync = null;
        var source = sourceForMessage(message);
        if (isValidSyncMessage(message, source) && syncBindingsMatch(message)) {
            applyValidatedSync(message);
        }
    }

    (:fullLegacyState)
    static function isValidSyncMessage(message, trustedSource) {
        if (!(message instanceof Lang.Dictionary)) {
            return false;
        }
        if (!trustedSource.equals("phone") && !trustedSource.equals("cloud")) {
            return false;
        }
        if (!hasOnlySyncKeys(message, trustedSource)) {
            return false;
        }
        var version = message.get("bindingVersion");
        var type = message.get("type");
        var requestId = message.get("requestId");
        var syncId = message.get("syncId");
        if (!(version instanceof Lang.Number) || version != bindingVersion ||
            !isBoundedText(type, 8) || !type.toString().equals("sync") ||
            !isBoundedText(requestId, maxBindingLength) ||
            !isBoundedText(syncId, maxBindingLength) ||
            !requestId.toString().equals(syncId.toString()) ||
            !isValidAccountBinding(message.get("accountBinding")) ||
            !isBoundedText(message.get("deviceBinding"), maxBindingLength)) {
            return false;
        }
        var bindingSource = message.get("bindingSource");
        if (trustedSource.equals("phone") && bindingSource != null &&
            (!isBoundedText(bindingSource, 8) || !bindingSource.toString().equals("phone"))) {
            return false;
        }
        if (trustedSource.equals("cloud") &&
            (!isBoundedText(bindingSource, 8) || !bindingSource.toString().equals("cloud"))) {
            return false;
        }
        if (trustedSource.equals("cloud")) {
            var planId = message.get("planId");
            var planRevision = message.get("planRevision");
            var expectedRequestId = isBoundedText(planId, 36) && planId.toString().length() == 36 &&
                isValidCounter(planRevision, maxCloudPlanRevision) ?
                planId.toString() + "-" + planRevision.toString() : null;
            if (expectedRequestId == null || !requestId.toString().equals(expectedRequestId)) {
                return false;
            }
        } else if (!isValidCounter(message.get("syncRevision"), maxPhoneSyncRevision)) {
            return false;
        }
        if (trustedSource.equals("phone")) {
            var messagePairingGeneration = message.get("pairingGeneration");
            if (messagePairingGeneration != null &&
                !isValidAccountBinding(messagePairingGeneration)) {
                return false;
            }
        }
        var flatNames = message.get("planNames");
        var flatWeights = message.get("planWeights");
        var flatReps = message.get("planReps");
        if (!(flatNames instanceof Lang.Array) ||
            !(flatWeights instanceof Lang.Array) ||
            !(flatReps instanceof Lang.Array) ||
            flatNames.size() != flatWeights.size() ||
            flatNames.size() != flatReps.size() ||
            !isValidExerciseList(flatNames, maxPlanSets)) {
            return false;
        }
        for (var i = 0; i < flatNames.size(); i += 1) {
            if (!isValidExerciseName(flatNames[i]) ||
                !isValidWeight(flatWeights[i]) ||
                !isValidReps(flatReps[i])) {
                return false;
            }
        }
        var syncedExercises = message.get("exercises");
        if (syncedExercises != null) {
            if (!isValidExerciseList(syncedExercises, maxPlanSets)) {
                return false;
            }
        }
        var syncedLanguage = message.get("language");
        if (syncedLanguage != null &&
            (!(syncedLanguage instanceof Lang.String) ||
                (!syncedLanguage.toString().equals("en") && !syncedLanguage.toString().equals("uk") &&
                    !syncedLanguage.toString().equals("ru")))) {
            return false;
        }
        var resetWorkout = message.get("resetWorkout");
        if (resetWorkout != null) {
            if (!(resetWorkout instanceof Lang.Boolean)) {
                return false;
            }
            if (resetWorkout &&
                (!trustedSource.equals("phone") || flatNames.size() != 0 ||
                    !(syncedExercises instanceof Lang.Array) || syncedExercises.size() != 0)) {
                // Only the bound Android auth-transition path may request destructive
                // cleanup. Requiring its exact empty shape prevents a normal plan or a
                // cloud response from terminating an unrelated active workout.
                return false;
            }
        }
        var repairPairing = message.get("repairPairing");
        if (repairPairing != null &&
            (!(repairPairing instanceof Lang.Boolean) ||
                !trustedSource.equals("phone") ||
                (repairPairing && resetWorkout instanceof Lang.Boolean && resetWorkout))) {
            return false;
        }
        return true;
    }

    (:compactLegacyState)
    static function isValidSyncMessage(message, trustedSource) {
        if (!(message instanceof Lang.Dictionary) || !trustedSource.equals("phone") ||
            !hasOnlySyncKeys(message, trustedSource) ||
            !(message.get("bindingVersion") instanceof Lang.Number) ||
            message.get("bindingVersion") != bindingVersion ||
            !isBoundedText(message.get("type"), 8) ||
            !message.get("type").toString().equals("sync") ||
            !isBoundedText(message.get("requestId"), maxBindingLength) ||
            !isBoundedText(message.get("syncId"), maxBindingLength) ||
            !message.get("requestId").toString().equals(message.get("syncId").toString()) ||
            !isValidAccountBinding(message.get("accountBinding")) ||
            !isBoundedText(message.get("deviceBinding"), maxBindingLength) ||
            !isValidCounter(message.get("syncRevision"), maxPhoneSyncRevision)) {
            return false;
        }
        var generation = message.get("pairingGeneration");
        if (generation != null && !isValidAccountBinding(generation)) {
            return false;
        }
        var names = message.get("planNames");
        var weights = message.get("planWeights");
        var setReps = message.get("planReps");
        if (!(names instanceof Lang.Array) || !(weights instanceof Lang.Array) ||
            !(setReps instanceof Lang.Array) ||
            !isValidExerciseList(names, maxPlanSets) ||
            weights.size() != names.size() || setReps.size() != names.size()) {
            return false;
        }
        for (var i = 0; i < names.size(); i += 1) {
            if (!isValidWeight(weights[i]) || !isValidReps(setReps[i])) {
                return false;
            }
        }
        var syncedExercises = message.get("exercises");
        if (syncedExercises != null &&
            !isValidExerciseList(syncedExercises, maxPlanSets)) {
            return false;
        }
        var syncedLanguage = message.get("language");
        if (syncedLanguage != null &&
            (!(syncedLanguage instanceof Lang.String) ||
                (!syncedLanguage.toString().equals("en") &&
                    !syncedLanguage.toString().equals("uk") &&
                    !syncedLanguage.toString().equals("ru")))) {
            return false;
        }
        var reset = message.get("resetWorkout");
        if (reset != null && !(reset instanceof Lang.Boolean)) {
            return false;
        }
        if (reset instanceof Lang.Boolean && reset &&
            (names.size() != 0 || !(syncedExercises instanceof Lang.Array) ||
                syncedExercises.size() != 0)) {
            return false;
        }
        var repair = message.get("repairPairing");
        return repair == null ||
            (repair instanceof Lang.Boolean &&
                !(repair && reset instanceof Lang.Boolean && reset));
    }

    static function hasOnlySyncKeys(message, trustedSource) {
        if (!(message instanceof Lang.Dictionary) || message.size() > 15) {
            return false;
        }
        var keys = message.keys();
        for (var i = 0; i < keys.size(); i += 1) {
            var key = keys[i];
            if (!(key instanceof Lang.String) || !isAllowedSyncKey(key.toString(), trustedSource)) {
                return false;
            }
        }
        return true;
    }

    (:fullLegacyState)
    static function isAllowedSyncKey(key, trustedSource) {
        if (key.equals("type") || key.equals("bindingVersion") ||
            key.equals("syncId") || key.equals("requestId") ||
            key.equals("bindingSource") || key.equals("accountBinding") ||
            key.equals("deviceBinding") || key.equals("resetWorkout") ||
            key.equals("planNames") || key.equals("planWeights") ||
            key.equals("planReps")) {
            return true;
        }
        if (trustedSource.equals("cloud")) {
            return key.equals("planId") || key.equals("planRevision");
        }
        return key.equals("syncRevision") || key.equals("language") ||
            key.equals("exercises") || key.equals("pairingGeneration") ||
            key.equals("repairPairing");
    }

    (:compactLegacyState)
    static function isAllowedSyncKey(key, trustedSource) {
        return trustedSource.equals("phone") &&
            (key.equals("type") || key.equals("bindingVersion") ||
                key.equals("syncId") || key.equals("requestId") ||
                key.equals("bindingSource") || key.equals("accountBinding") ||
                key.equals("deviceBinding") || key.equals("resetWorkout") ||
                key.equals("planNames") || key.equals("planWeights") ||
                key.equals("planReps") || key.equals("syncRevision") ||
                key.equals("language") || key.equals("exercises") ||
                key.equals("pairingGeneration") || key.equals("repairPairing"));
    }

    (:fullLegacyState)
    static function normalizedSyncMessage(message, trustedSource) {
        var normalized = {
            "type" => "sync",
            "bindingVersion" => bindingVersion,
            "syncId" => message.get("syncId").toString(),
            "requestId" => message.get("requestId").toString(),
            "bindingSource" => trustedSource,
            "accountBinding" => message.get("accountBinding").toString(),
            "deviceBinding" => message.get("deviceBinding").toString(),
            "planNames" => copySyncArray(message.get("planNames")),
            "planWeights" => copySyncArray(message.get("planWeights")),
            "planReps" => copySyncArray(message.get("planReps"))
        };
        if (trustedSource.equals("cloud")) {
            normalized.put("planId", message.get("planId").toString());
            normalized.put("planRevision", message.get("planRevision").toNumber());
        } else {
            normalized.put("syncRevision", message.get("syncRevision").toLong());
            copyOptionalAccountBinding(normalized, message, "pairingGeneration");
            var syncedLanguage = message.get("language");
            if (syncedLanguage != null) {
                normalized.put("language", syncedLanguage.toString());
            }
            var syncedExercises = message.get("exercises");
            if (syncedExercises != null) {
                normalized.put("exercises", copySyncArray(syncedExercises));
            }
            var repairPairing = message.get("repairPairing");
            if (repairPairing instanceof Lang.Boolean) {
                normalized.put("repairPairing", repairPairing);
            }
        }
        var resetWorkout = message.get("resetWorkout");
        if (resetWorkout != null) {
            normalized.put("resetWorkout", resetWorkout);
        }
        return normalized;
    }

    (:compactLegacyState)
    static function normalizedSyncMessage(message, trustedSource) {
        var normalized = {
            "type" => "sync",
            "bindingVersion" => bindingVersion,
            "syncId" => message.get("syncId").toString(),
            "requestId" => message.get("requestId").toString(),
            "bindingSource" => "phone",
            "accountBinding" => message.get("accountBinding").toString(),
            "deviceBinding" => message.get("deviceBinding").toString(),
            "syncRevision" => message.get("syncRevision").toLong(),
            "planNames" => copySyncArray(message.get("planNames")),
            "planWeights" => copySyncArray(message.get("planWeights")),
            "planReps" => copySyncArray(message.get("planReps"))
        };
        copyOptionalAccountBinding(normalized, message, "pairingGeneration");
        var value = message.get("language");
        if (value != null) {
            normalized.put("language", value.toString());
        }
        value = message.get("exercises");
        if (value != null) {
            normalized.put("exercises", copySyncArray(value));
        }
        value = message.get("resetWorkout");
        if (value instanceof Lang.Boolean) {
            normalized.put("resetWorkout", value);
        }
        value = message.get("repairPairing");
        if (value instanceof Lang.Boolean) {
            normalized.put("repairPairing", value);
        }
        return normalized;
    }

    static function copyOptionalAccountBinding(target, source, key) {
        var value = source.get(key);
        if (isValidAccountBinding(value)) {
            target.put(key, value.toString());
        }
    }

    static function copySyncArray(source) {
        var copy = [];
        for (var i = 0; i < source.size(); i += 1) {
            copy.add(source[i]);
        }
        return copy;
    }

    static function hasAccountBinding() {
        return isValidAccountBinding(accountBinding) &&
            isValidAccountBinding(stateOwnerBinding) &&
            accountBinding.toString().equals(stateOwnerBinding.toString()) &&
            isBoundedText(deviceBinding, maxBindingLength);
    }

    static function bindingsMatch(message) {
        if (!hasAccountBinding() || !(message instanceof Lang.Dictionary)) {
            return false;
        }
        var messageAccount = message.get("accountBinding");
        var messageDevice = message.get("deviceBinding");
        var version = message.get("bindingVersion");
        if (!(version instanceof Lang.Number) || version != bindingVersion ||
            !isValidAccountBinding(messageAccount) ||
            !isBoundedText(messageDevice, maxBindingLength) ||
            !accountBinding.toString().equals(messageAccount.toString()) ||
            !deviceBinding.toString().equals(messageDevice.toString())) {
            return false;
        }
        var messageGeneration = message.get("pairingGeneration");
        if (isValidAccountBinding(pairingGeneration)) {
            return isValidAccountBinding(messageGeneration) &&
                pairingGeneration.toString().equals(messageGeneration.toString());
        }
        return messageGeneration == null;
    }

    static function syncBindingsMatch(message) {
        if (!(message instanceof Lang.Dictionary) || !isValidAccountBinding(accountBinding) ||
            !isValidAccountBinding(stateOwnerBinding) ||
            !accountBinding.toString().equals(stateOwnerBinding.toString())) {
            return false;
        }
        var messageAccount = message.get("accountBinding");
        var messageDevice = message.get("deviceBinding");
        var sourceValue = message.get("bindingSource");
        var source = sourceValue == null ? "phone" : sourceValue.toString();
        if (!isValidAccountBinding(messageAccount) ||
            !accountBinding.toString().equals(messageAccount.toString()) ||
            !isBoundedText(messageDevice, maxBindingLength)) {
            return false;
        }
        if (source.equals("cloud")) {
            return isBoundedText(cloudDeviceBinding, maxBindingLength) &&
                cloudDeviceBinding.toString().equals(messageDevice.toString());
        }
        if (!isBoundedText(deviceBinding, maxBindingLength) ||
            !deviceBinding.toString().equals(messageDevice.toString())) {
            return false;
        }
        var messageGeneration = message.get("pairingGeneration");
        if (isValidAccountBinding(pairingGeneration)) {
            return isValidAccountBinding(messageGeneration) &&
                pairingGeneration.toString().equals(messageGeneration.toString());
        }
        return messageGeneration == null;
    }

    static function removePendingByRequestId(requestId) {
        // An ACK must never win the marker -> pending -> active tombstone
        // transaction. If finalization still fails, retain the queue head.
        if (!recoverQueuedWorkout() ||
            !isBoundedText(requestId, maxBindingLength) || pending.size() == 0) {
            return false;
        }
        var requestText = requestId.toString();
        var item = pending[0];
        if (!(item instanceof Lang.Dictionary)) {
            return false;
        }
        var itemRequestId = item.get("requestId");
        if (!isBoundedText(itemRequestId, maxBindingLength) ||
            !itemRequestId.toString().equals(requestText)) {
            return false;
        }
        pending.remove(item);
        lastWorkoutSyncAtSeconds = Time.now().value();
        if (save()) {
            return true;
        }
        load();
        return false;
    }

    static function rotatePairingGenerationForPending(previousGeneration, nextGeneration) {
        if (!isValidOptionalAccountBinding(previousGeneration) ||
            !isValidAccountBinding(nextGeneration) ||
            !hasAccountBinding()) {
            return false;
        }
        for (var i = 0; i < pending.size(); i += 1) {
            var item = pending[i];
            if (!(item instanceof Lang.Dictionary) || !isValidWorkoutMessage(item)) {
                return false;
            }
            var itemGeneration = item.get("pairingGeneration");
            var matchesPrevious = sameOptionalText(previousGeneration, itemGeneration);
            var matchesNext = sameOptionalText(nextGeneration, itemGeneration);
            if ((!matchesPrevious && !matchesNext) ||
                !accountBinding.toString().equals(item.get("accountBinding").toString()) ||
                !deviceBinding.toString().equals(item.get("deviceBinding").toString())) {
                return false;
            }
        }
        for (var j = 0; j < pending.size(); j += 1) {
            pending[j].put("pairingGeneration", nextGeneration.toString());
        }
        return isValidPendingList(pending);
    }

    static function queueWorkout(message) {
        if (!isValidWorkoutMessage(message) || !bindingsMatch(message)) {
            return false;
        }
        var requestId = message.get("requestId").toString();
        var alreadyQueued = false;
        for (var i = 0; i < pending.size(); i += 1) {
            var queuedItem = pending[i];
            if (queuedItem instanceof Lang.Dictionary &&
                isBoundedText(queuedItem.get("requestId"), maxBindingLength) &&
                queuedItem.get("requestId").toString().equals(requestId)) {
                if (!isValidWorkoutMessage(queuedItem) ||
                    !bindingsMatch(queuedItem)) {
                    return false;
                }
                alreadyQueued = true;
                break;
            }
        }

        if (!alreadyQueued) {
            if (!canQueueWorkout(message)) {
                status = "SYNC FULL";
                return false;
            }
            var nextPending = [];
            for (var j = 0; j < pending.size(); j += 1) {
                nextPending.add(pending[j]);
            }
            nextPending.add(message);

            var previousPending = pending;
            var withinBudget = false;
            try {
                pending = nextPending;
                withinBudget = isWithinStorageBudget();
            } catch (e) {
                withinBudget = false;
            }
            pending = previousPending;
            if (!withinBudget) {
                status = "QUEUE FULL";
                return false;
            }

            try {
                // The marker is written first and the queue second. Nothing may
                // send this request until recoverQueuedWorkout commits the empty
                // active snapshot and clears the prepared state.
                Storage.setValue("queuedActiveRequestId", requestId);
                Storage.setValue("pending", nextPending);
            } catch (e) {
                status = "SAVE FAIL";
                return false;
            }
            pending = nextPending;
        }

        if (!recoverQueuedWorkout()) {
            status = "QUEUED SAFE";
            return false;
        }
        status = "QUEUED";
        return true;
    }

    static function recoverQueuedWorkout() {
        var marker = null;
        try {
            marker = Storage.getValue("queuedActiveRequestId");
        } catch (e) {
            return false;
        }
        // A prior build may have persisted pending successfully and then lost
        // the explicit marker. The prepared request id is an equivalent,
        // owner-bound recovery fence and prevents either a duplicate append or
        // an early ACK from resurrecting the workout.
        if (!isBoundedText(marker, maxBindingLength) && hasPreparedWorkout()) {
            var preparedId = preparedWorkout[4].toString();
            for (var p = 0; p < pending.size(); p += 1) {
                var preparedItem = pending[p];
                if (preparedItem instanceof Lang.Dictionary &&
                    isValidWorkoutMessage(preparedItem) &&
                    bindingsMatch(preparedItem) &&
                    preparedItem.get("requestId").toString().equals(preparedId)) {
                    marker = preparedId;
                    break;
                }
            }
        }
        if (!isBoundedText(marker, maxBindingLength)) {
            return true;
        }
        var queued = false;
        for (var i = 0; i < pending.size(); i += 1) {
            var item = pending[i];
            if (item instanceof Lang.Dictionary &&
                isBoundedText(item.get("requestId"), maxBindingLength) &&
                item.get("requestId").toString().equals(marker.toString())) {
                queued = true;
                break;
            }
        }
        if (queued) {
            if (hasAccountBinding() && !persistEmptyActiveWorkoutSnapshot()) {
                return false;
            }
            sets = [];
            plan = [];
            activeWorkoutStartedAtSeconds = null;
            resumedWorkoutIntervalsInvalid = false;
            restDurationMs = 0;
            restStartedAt = null;
            lastLoggedSetEndSeconds = 0;
            clearTransientSetActions();
            applyDeferredSyncIfIdle();
            if (!save()) {
                return false;
            }
            clearPreparedWorkout(marker);
        }
        try {
            Storage.deleteValue("queuedActiveRequestId");
        } catch (e) {
            // Retrying recovery is safe.
        }
        return true;
    }

    static function beginAccountTransition() {
        try {
            Storage.deleteValue("stateOwnerBinding");
            stateOwnerBinding = null;
        } catch (e) {
            return false;
        }
        try {
            Storage.deleteValue("queuedActiveRequestId");
            Storage.deleteValue("preparedWorkoutV1");
            Storage.deleteValue("lastWorkoutSyncV1");
            Storage.deleteValue("activeWorkoutV1");
            Storage.deleteValue("activeRuntimeV1");
            resetActiveWorkoutSnapshotState();
            resetRuntimeCheckpointState();
            preparedWorkout = null;
            lastWorkoutSyncAtSeconds = null;
            return true;
        } catch (e) {
            // The owner deletion is the irreversible security boundary. Never allow
            // a later lifecycle save to restore the previous owner's active state.
            clearAccountScopedState();
            GymSession.resetForAccountTransition();
            return false;
        }
    }

    static function clearCloudSyncStageForAccountTransition() {
        try {
            Storage.deleteValue("cloudSyncStage");
            stagedCloudPlanRevision = 0;
            stagedCloudPlanId = null;
            stagedCloudAccountBinding = null;
            stagedCloudSyncMessage = null;
            return true;
        } catch (e) {
            return false;
        }
    }

    static function adoptLegacyStateOwner() {
        if (!isValidAccountBinding(accountBinding)) {
            return false;
        }
        try {
            // One-time compatibility adoption for installs created before owner markers.
            // Future transitions already have storageSchemaVersion and fail closed instead.
            Storage.setValue("stateOwnerBinding", accountBinding);
            stateOwnerBinding = accountBinding;
            Storage.setValue("storageSchemaVersion", storageSchemaVersion);
            return true;
        } catch (e) {
            return stateOwnerBinding != null;
        }
    }

    static function clearAccountScopedState() {
        try {
            // Invalid/missing ownership never restores this value, but remove the
            // account-bound wearable cache as well so a later lifecycle cannot revive
            // stale data even if durable owner metadata is externally repaired.
            Storage.deleteValue("activeWorkoutV1");
            Storage.deleteValue("activeRuntimeV1");
            Storage.deleteValue("preparedWorkoutV1");
            Storage.deleteValue("lastWorkoutSyncV1");
        } catch (e) {
            // Binding validation remains the fail-closed authorization boundary.
        }
        accountBinding = null;
        stateOwnerBinding = null;
        deviceBinding = null;
        pairingGeneration = null;
        cloudDeviceBinding = null;
        sets = [];
        plan = [];
        pending = [];
        preparedWorkout = null;
        lastWorkoutSyncAtSeconds = null;
        activeWorkoutStartedAtSeconds = null;
        resumedWorkoutIntervalsInvalid = false;
        resetActiveWorkoutSnapshotState();
        resetRuntimeCheckpointState();
        deferredSync = null;
        processedSyncIds = [];
        // The phone fence is device-global, not account-scoped. Keeping it prevents a
        // delayed prior-account sync from undoing a newer transition.
        lastCloudPlanRevision = 0;
        lastCloudPlanId = null;
        restDurationMs = 0;
        restStartedAt = null;
        lastLoggedSetEndSeconds = 0;
        clearTransientSetActions();
        weight = 50.0;
        reps = 10;
        exercises = builtInExercises();
        exerciseIndex = 0;
    }

    (:fullLegacyState)
    static function ensureUnboundAtomicQuarantine() {
        if (hasAccountBinding()) {
            return true;
        }
        if (legacyUnboundState) {
            return ensureLegacyQuarantine();
        }
        // Never reclassify partially bound account data as ownerless. Normal load and
        // account-transition paths clear such state; this guard keeps an unexpected
        // in-memory lifecycle interleave fail-closed.
        if (accountBinding != null || stateOwnerBinding != null) {
            return false;
        }

        // A clean install has no pre-upgrade raw values to preserve. Seed the immutable
        // quarantine copy from the current ownerless state, then commit its recovery
        // marker before add/undo is allowed to write the atomic current snapshot.
        legacyUnboundState = true;
        legacyQuarantineReady = false;
        legacyRawExercises = copyExerciseList(exercises);
        legacyRawSets = normalizedSetList(sets);
        legacyRawPlan = normalizedSetList(plan);
        legacyRawPending = normalizedLegacyPendingList(pending);
        if (!ensureLegacyQuarantine()) {
            legacyUnboundState = false;
            legacyRawExercises = null;
            legacyRawSets = null;
            legacyRawPlan = null;
            legacyRawPending = null;
            return false;
        }
        try {
            // This marker makes legacyQuarantineCurrent authoritative on the next load.
            // It must be durable before the first athlete mutation is attempted.
            Storage.setValue("legacyUnboundState", true);
        } catch (e) {
            clearPartialLegacyQuarantine();
            legacyUnboundState = false;
            legacyRawExercises = null;
            legacyRawSets = null;
            legacyRawPlan = null;
            legacyRawPending = null;
            return false;
        }
        try {
            Storage.setValue("storageSchemaVersion", storageSchemaVersion);
        } catch (e) {
            // The ownerless marker and current snapshot are already a complete recovery
            // boundary. Schema metadata is retried by the next compatibility save.
        }
        return true;
    }

    (:fullLegacyState)
    static function ensureLegacyQuarantine() {
        if (legacyQuarantineReady) {
            return true;
        }
        if (!legacyUnboundState) {
            return false;
        }
        try {
            if (!isBoundedLegacyStoredValue(legacyRawExercises) ||
                !isBoundedLegacyStoredValue(legacyRawSets) ||
                !isBoundedLegacyStoredValue(legacyRawPlan) ||
                !isBoundedLegacyStoredValue(legacyRawPending)) {
                return false;
            }
            var core = {
                "version" => 1,
                "weight" => weight,
                "reps" => reps,
                "weightStep" => weightStep,
                "restSecondsDefault" => restSecondsDefault,
                "autoPromptEnabled" => autoPromptEnabled,
                "sensitivityIndex" => sensitivityIndex,
                "language" => language
            };
            // Keep raw HEAD values in separate <=32 KiB Object Store entries. New production
            // limits may be lower than what an older release already persisted; applying those
            // limits before quarantine would silently discard a large offline queue.
            Storage.setValue("legacyQuarantineExercises",
                legacyRawExercises == null ? [] : legacyRawExercises);
            Storage.setValue("legacyQuarantineSets",
                legacyRawSets == null ? [] : legacyRawSets);
            Storage.setValue("legacyQuarantinePlan",
                legacyRawPlan == null ? [] : legacyRawPlan);
            Storage.setValue("legacyQuarantinePending",
                legacyRawPending == null ? [] : legacyRawPending);
            Storage.setValue("legacyQuarantineCore", core);
            // The atomic current snapshot is part of the same pre-commit set. If the device's
            // Object Store cannot hold both representations, remove every partial copy and
            // leave the original HEAD keys untouched so cleanup/retry cannot self-deadlock.
            if (!refreshLegacyCurrentQuarantine()) {
                clearPartialLegacyQuarantine();
                return false;
            }
            // Commit marker last. Partial copies are ignored and retried without touching the
            // original keys; a later account transition requires this marker.
            Storage.setValue("legacyQuarantineVersion", 1);
            legacyQuarantineReady = true;
            return true;
        } catch (e) {
            clearPartialLegacyQuarantine();
            return false;
        }
    }

    (:fullLegacyState)
    static function clearPartialLegacyQuarantine() {
        try {
            Storage.deleteValue("legacyQuarantineVersion");
            Storage.deleteValue("legacyQuarantineCore");
            Storage.deleteValue("legacyQuarantinePending");
            Storage.deleteValue("legacyQuarantinePlan");
            Storage.deleteValue("legacyQuarantineSets");
            Storage.deleteValue("legacyQuarantineExercises");
            Storage.deleteValue("legacyQuarantineCurrent");
        } catch (e) {
            // The original HEAD keys remain authoritative until the commit marker exists.
        }
        legacyQuarantineReady = false;
    }

    (:fullLegacyState)
    static function refreshLegacyCurrentQuarantine() {
        if (!legacyUnboundState ||
            !isValidExerciseList(exercises, maxPlanSets) ||
            !isValidSetList(sets, maxWorkoutSets, true) ||
            !isValidSetList(plan, maxPlanSets, true) ||
            !isValidLegacyPendingList(pending) ||
            !isValidWeight(weight) || !isValidReps(reps) ||
            !isValidWeight(weightStep) || weightStep <= 0.0 || weightStep > 100.0 ||
            !(restSecondsDefault instanceof Lang.Number) ||
            restSecondsDefault < 1 || restSecondsDefault > 3600 ||
            !(autoPromptEnabled instanceof Lang.Boolean) ||
            !(sensitivityIndex instanceof Lang.Number) ||
            sensitivityIndex < 0 || sensitivityIndex > 2 ||
            !(language.equals("en") || language.equals("uk") || language.equals("ru"))) {
            return false;
        }
        var snapshot = {
            "version" => 1,
            "exercises" => copyExerciseList(exercises),
            "sets" => normalizedSetList(sets),
            "plan" => normalizedSetList(plan),
            "pending" => normalizedLegacyPendingList(pending),
            "weight" => weight,
            "reps" => reps,
            "weightStep" => weightStep,
            "restSecondsDefault" => restSecondsDefault,
            "autoPromptEnabled" => autoPromptEnabled,
            "sensitivityIndex" => sensitivityIndex,
            "language" => language
        };
        if (isValidWorkoutStartedAtSeconds(activeWorkoutStartedAtSeconds)) {
            snapshot.put("activeWorkoutStartedAtSeconds", activeWorkoutStartedAtSeconds);
        }
        if (estimatedValueBytes(snapshot) > maxEstimatedStoreBytes) {
            return false;
        }
        try {
            // A single value is the commit record; no separately written revision can tear.
            Storage.setValue("legacyQuarantineCurrent", snapshot);
            return true;
        } catch (e) {
            return false;
        }
    }

    (:fullLegacyState)
    static function restoreLegacyCurrentQuarantine(allowSeed) {
        var snapshot = Storage.getValue("legacyQuarantineCurrent");
        if (!(snapshot instanceof Lang.Dictionary) ||
            !isValidLegacyCurrentQuarantine(snapshot)) {
            return false;
        }
        exercises = copyExerciseList(snapshot.get("exercises"));
        sets = normalizedSetList(snapshot.get("sets"));
        clearTransientSetActions();
        plan = normalizedSetList(snapshot.get("plan"));
        pending = normalizedLegacyPendingList(snapshot.get("pending"));
        weight = snapshot.get("weight");
        reps = snapshot.get("reps");
        weightStep = snapshot.get("weightStep");
        restSecondsDefault = snapshot.get("restSecondsDefault");
        autoPromptEnabled = snapshot.get("autoPromptEnabled");
        sensitivityIndex = snapshot.get("sensitivityIndex");
        language = snapshot.get("language").toString();
        var snapshotStartedAt = snapshot.get("activeWorkoutStartedAtSeconds");
        activeWorkoutStartedAtSeconds = sets.size() > 0 &&
            isValidWorkoutStartedAtSeconds(snapshotStartedAt) ? snapshotStartedAt : null;
        return true;
    }

    (:fullLegacyState)
    static function legacyCurrentSetCount() {
        try {
            var snapshot = Storage.getValue("legacyQuarantineCurrent");
            if (snapshot instanceof Lang.Dictionary &&
                isValidLegacyCurrentQuarantine(snapshot)) {
                var snapshotSets = snapshot.get("sets");
                if (snapshotSets instanceof Lang.Array) {
                    return snapshotSets.size();
                }
            }
        } catch (e) {
        }
        return -1;
    }

    (:fullLegacyState)
    static function isValidLegacyCurrentQuarantine(value) {
        if (!(value instanceof Lang.Dictionary) ||
            (value.size() != 12 && value.size() != 13) ||
            !(value.get("version") instanceof Lang.Number) || value.get("version") != 1 ||
            !isValidExerciseList(value.get("exercises"), maxPlanSets) ||
            !isValidSetList(value.get("sets"), maxWorkoutSets, true) ||
            !isValidSetList(value.get("plan"), maxPlanSets, true) ||
            !isValidLegacyPendingList(value.get("pending")) ||
            !isValidWeight(value.get("weight")) || !isValidReps(value.get("reps")) ||
            !isValidWeightStep(value.get("weightStep")) ||
            !isValidRestSeconds(value.get("restSecondsDefault")) ||
            !(value.get("autoPromptEnabled") instanceof Lang.Boolean) ||
            !isValidSensitivity(value.get("sensitivityIndex")) ||
            !isBoundedText(value.get("language"), 2) ||
            (value.get("activeWorkoutStartedAtSeconds") != null &&
                (!isValidWorkoutStartedAtSeconds(value.get("activeWorkoutStartedAtSeconds")) ||
                    setListCount(value.get("sets")) == 0))) {
            return false;
        }
        var savedLanguage = value.get("language").toString();
        return (savedLanguage.equals("en") || savedLanguage.equals("uk") || savedLanguage.equals("ru")) &&
            estimatedValueBytes(value) <= maxEstimatedStoreBytes;
    }

    (:fullLegacyState)
    static function copyExerciseList(source) {
        var copy = [];
        for (var i = 0; i < source.size(); i += 1) {
            copy.add(source[i].toString());
        }
        return copy;
    }

    (:fullLegacyState)
    static function isBoundedLegacyStoredValue(value) {
        return value == null || estimatedValueBytes(value) <= maxLegacyStoredValueBytes;
    }

    static function normalizedSetList(source) {
        var copy = [];
        for (var i = 0; i < source.size(); i += 1) {
            var item = source[i];
            var normalized = {
                "exerciseName" => item.get("exerciseName").toString(),
                "weight" => item.get("weight"),
                "reps" => item.get("reps")
            };
            copyOptionalSetMetrics(normalized, item);
            copy.add(normalized);
        }
        return copy;
    }

    static function compactSetMetrics(source) {
        var startHeartRate = source.get("startHeartRate");
        var peakHeartRate = source.get("peakHeartRate");
        var endHeartRate = source.get("endHeartRate");
        if (startHeartRate != null &&
            (peakHeartRate == null || startHeartRate > peakHeartRate)) {
            peakHeartRate = startHeartRate;
        }
        if (endHeartRate != null &&
            (peakHeartRate == null || endHeartRate > peakHeartRate)) {
            peakHeartRate = endHeartRate;
        }
        return [
            source.get("activeSeconds"),
            source.get("restBeforeSeconds"),
            startHeartRate,
            peakHeartRate,
            endHeartRate,
            source.get("recoveryHeartRateDrop"),
            source.get("detectionConfidence")
        ];
    }

    static function copySetInterval(source) {
        var copy = [];
        for (var i = 0; i < source.size(); i += 1) {
            copy.add(source[i]);
        }
        return copy;
    }

    static function copyOptionalSetMetrics(target, source) {
        var keys = [
            "activeSeconds", "restBeforeSeconds", "startHeartRate", "peakHeartRate",
            "endHeartRate", "recoveryHeartRateDrop", "detectionConfidence"
        ];
        for (var i = 0; i < keys.size(); i += 1) {
            var value = source.get(keys[i]);
            if (value != null) {
                target.put(keys[i], value);
            }
        }
        var setInterval = source.get("setInterval");
        if (isValidSetInterval(setInterval)) {
            target.put("setInterval", copySetInterval(setInterval));
        }
    }

    static function sourceForMessage(message) {
        if (message instanceof Lang.Dictionary) {
            var source = message.get("bindingSource");
            if (isBoundedText(source, 8) && source.toString().equals("cloud")) {
                return "cloud";
            }
        }
        return "phone";
    }

    (:fullLegacyState)
    static function stagedPairingRecoveryTarget() {
        var message = stagedPhoneSyncMessage;
        if (!(message instanceof Lang.Dictionary) || !hasAccountBinding() ||
            syncRevisionStatus(message, "phone") < 0 ||
            !accountBinding.toString().equals(message.get("accountBinding").toString()) ||
            !deviceBinding.toString().equals(message.get("deviceBinding").toString()) ||
            message.get("resetWorkout") == true ||
            !isValidAccountBinding(message.get("pairingGeneration"))) {
            return null;
        }
        var nextGeneration = message.get("pairingGeneration").toString();
        var repair = message.get("repairPairing") == true;
        if (isValidAccountBinding(pairingGeneration)) {
            if (pairingGeneration.toString().equals(nextGeneration)) {
                return null;
            }
            return repair ? nextGeneration : null;
        }
        return repair ? null : nextGeneration;
    }

    static function loadSyncStage(source) {
        var key = source.equals("cloud") ? "cloudSyncStage" : "phoneSyncStage";
        var maximum = source.equals("cloud") ? maxCloudPlanRevision : maxPhoneSyncRevision;
        var stage = Storage.getValue(key);
        if (stage instanceof Lang.Dictionary && isValidSyncStage(stage, maximum, source)) {
            var stagedMessage = normalizedSyncMessage(stage.get("message"), source);
            if (source.equals("cloud")) {
                stagedCloudPlanRevision = stage.get("revision").toNumber();
                stagedCloudPlanId = stage.get("id").toString();
                stagedCloudAccountBinding = stage.get("accountBinding").toString();
                stagedCloudSyncMessage = stagedMessage;
            } else {
                stagedPhoneSyncRevision = stage.get("revision").toLong();
                stagedPhoneSyncId = stage.get("id").toString();
                stagedPhoneAccountBinding = stage.get("accountBinding").toString();
                stagedPhoneSyncMessage = stagedMessage;
            }
            return;
        }
        if (source.equals("cloud")) {
            stagedCloudPlanRevision = 0;
            stagedCloudPlanId = null;
            stagedCloudAccountBinding = null;
            stagedCloudSyncMessage = null;
        } else {
            stagedPhoneSyncRevision = 0l;
            stagedPhoneSyncId = null;
            stagedPhoneAccountBinding = null;
            stagedPhoneSyncMessage = null;
        }
    }

    static function stageSync(message, source) {
        var revision = source.equals("cloud") ?
            message.get("planRevision") : message.get("syncRevision");
        var stagedMessage = normalizedSyncMessage(message, source);
        var stage = {
            "revision" => revision,
            "id" => message.get("requestId").toString(),
            "accountBinding" => message.get("accountBinding").toString(),
            "message" => stagedMessage
        };
        if (estimatedValueBytes(stage) > maxLegacyStoredValueBytes) {
            return false;
        }
        try {
            Storage.setValue(source.equals("cloud") ? "cloudSyncStage" : "phoneSyncStage", stage);
            if (source.equals("cloud")) {
                stagedCloudPlanRevision = revision.toNumber();
                stagedCloudPlanId = message.get("requestId").toString();
                stagedCloudAccountBinding = message.get("accountBinding").toString();
                stagedCloudSyncMessage = stagedMessage;
            } else {
                stagedPhoneSyncRevision = revision.toLong();
                stagedPhoneSyncId = message.get("requestId").toString();
                stagedPhoneAccountBinding = message.get("accountBinding").toString();
                stagedPhoneSyncMessage = stagedMessage;
            }
            return true;
        } catch (e) {
            return false;
        }
    }

    static function clearSyncStage(source) {
        try {
            Storage.deleteValue(source.equals("cloud") ? "cloudSyncStage" : "phoneSyncStage");
            if (source.equals("cloud")) {
                stagedCloudPlanRevision = 0;
                stagedCloudPlanId = null;
                stagedCloudAccountBinding = null;
                stagedCloudSyncMessage = null;
            } else {
                stagedPhoneSyncRevision = 0l;
                stagedPhoneSyncId = null;
                stagedPhoneAccountBinding = null;
                stagedPhoneSyncMessage = null;
            }
        } catch (e) {
            // A committed fence makes a leftover stage harmless and retryable.
        }
    }

    static function clearSyncStageIfMatches(message, source) {
        if (!isExactStagedSync(message, source)) {
            return;
        }
        clearSyncStage(source);
    }

    static function isExactStagedSync(message, source) {
        var revision = source.equals("cloud") ?
            message.get("planRevision").toNumber() : message.get("syncRevision").toLong();
        var requestId = message.get("requestId").toString();
        var messageAccount = message.get("accountBinding").toString();
        if (source.equals("cloud")) {
            if (stagedCloudPlanRevision != revision || stagedCloudPlanId == null ||
                stagedCloudAccountBinding == null ||
                !stagedCloudPlanId.toString().equals(requestId) ||
                !stagedCloudAccountBinding.toString().equals(messageAccount)) {
                return false;
            }
            return syncMessagesEqual(stagedCloudSyncMessage, message, source);
        } else if (stagedPhoneSyncRevision != revision || stagedPhoneSyncId == null ||
            stagedPhoneAccountBinding == null ||
            !stagedPhoneSyncId.toString().equals(requestId) ||
            !stagedPhoneAccountBinding.toString().equals(messageAccount)) {
            return false;
        }
        return syncMessagesEqual(stagedPhoneSyncMessage, message, source);
    }

    static function syncMessagesEqual(left, right, source) {
        if (!isValidSyncMessage(left, source) || !isValidSyncMessage(right, source)) {
            return false;
        }
        if (!sameOptionalText(left.get("type"), right.get("type")) ||
            left.get("bindingVersion").toNumber() != right.get("bindingVersion").toNumber() ||
            !sameOptionalText(left.get("syncId"), right.get("syncId")) ||
            !sameOptionalText(left.get("requestId"), right.get("requestId")) ||
            !sameOptionalText(left.get("bindingSource"), right.get("bindingSource")) ||
            !sameOptionalText(left.get("accountBinding"), right.get("accountBinding")) ||
            !sameOptionalText(left.get("deviceBinding"), right.get("deviceBinding")) ||
            !sameOptionalBoolean(left.get("resetWorkout"), right.get("resetWorkout")) ||
            !sameTextArray(left.get("planNames"), right.get("planNames")) ||
            !sameNumericArray(left.get("planWeights"), right.get("planWeights"), true) ||
            !sameNumericArray(left.get("planReps"), right.get("planReps"), false)) {
            return false;
        }
        if (source.equals("cloud")) {
            return sameOptionalText(left.get("planId"), right.get("planId")) &&
                left.get("planRevision").toLong() == right.get("planRevision").toLong();
        }
        return left.get("syncRevision").toLong() == right.get("syncRevision").toLong() &&
            sameOptionalText(left.get("pairingGeneration"), right.get("pairingGeneration")) &&
            sameOptionalBoolean(left.get("repairPairing"), right.get("repairPairing")) &&
            sameOptionalText(left.get("language"), right.get("language")) &&
            sameOptionalTextArray(left.get("exercises"), right.get("exercises"));
    }

    static function sameOptionalText(left, right) {
        if (left == null || right == null) {
            return left == null && right == null;
        }
        return left instanceof Lang.String && right instanceof Lang.String &&
            left.toString().equals(right.toString());
    }

    static function sameOptionalBoolean(left, right) {
        if (left == null || right == null) {
            return left == null && right == null;
        }
        return left instanceof Lang.Boolean && right instanceof Lang.Boolean && left == right;
    }

    static function sameOptionalTextArray(left, right) {
        if (left == null || right == null) {
            return left == null && right == null;
        }
        return sameTextArray(left, right);
    }

    static function sameTextArray(left, right) {
        if (!(left instanceof Lang.Array) || !(right instanceof Lang.Array) ||
            left.size() != right.size()) {
            return false;
        }
        for (var i = 0; i < left.size(); i += 1) {
            if (!(left[i] instanceof Lang.String) || !(right[i] instanceof Lang.String) ||
                !left[i].toString().equals(right[i].toString())) {
                return false;
            }
        }
        return true;
    }

    static function sameNumericArray(left, right, compareAsFloat) {
        if (!(left instanceof Lang.Array) || !(right instanceof Lang.Array) ||
            left.size() != right.size()) {
            return false;
        }
        for (var i = 0; i < left.size(); i += 1) {
            if (compareAsFloat) {
                if (!isNumeric(left[i]) || !isNumeric(right[i])) {
                    return false;
                }
                if (left[i].toFloat() != right[i].toFloat()) {
                    return false;
                }
            } else {
                if ((!(left[i] instanceof Lang.Number) && !(left[i] instanceof Lang.Long)) ||
                    (!(right[i] instanceof Lang.Number) && !(right[i] instanceof Lang.Long))) {
                    return false;
                }
                if (left[i].toLong() != right[i].toLong()) {
                    return false;
                }
            }
        }
        return true;
    }

    static function syncRevisionStatus(message, source) {
        var requestId = message.get("requestId").toString();
        var messageAccount = message.get("accountBinding").toString();
        if (source.equals("cloud")) {
            var cloudRevision = message.get("planRevision").toNumber();
            if (cloudRevision < lastCloudPlanRevision) {
                return -1;
            }
            if (cloudRevision == lastCloudPlanRevision) {
                return lastCloudPlanId != null && lastCloudPlanId.toString().equals(
                    message.get("planId").toString()
                ) ? 0 : -1;
            }
            if (stagedCloudAccountBinding != null) {
                if (!stagedCloudAccountBinding.toString().equals(messageAccount)) {
                    return -1;
                }
                if (cloudRevision < stagedCloudPlanRevision) {
                    return -1;
                }
                if (cloudRevision == stagedCloudPlanRevision &&
                    !isExactStagedSync(message, source)) {
                    return -1;
                }
            }
            return 1;
        }
        var phoneRevision = message.get("syncRevision").toLong();
        if (phoneRevision < lastPhoneSyncRevision) {
            return -1;
        }
        if (phoneRevision == lastPhoneSyncRevision) {
            return lastPhoneSyncId != null && lastPhoneSyncAccountBinding != null &&
                lastPhoneSyncId.toString().equals(requestId) &&
                lastPhoneSyncAccountBinding.toString().equals(messageAccount) ? 0 : -1;
        }
        if (stagedPhoneSyncRevision > 0l) {
            if (phoneRevision < stagedPhoneSyncRevision) {
                return -1;
            }
            if (phoneRevision == stagedPhoneSyncRevision &&
                !isExactStagedSync(message, source)) {
                return -1;
            }
        }
        return 1;
    }

    static function rememberSyncRevision(message, source) {
        if (source.equals("cloud")) {
            lastCloudPlanRevision = message.get("planRevision").toNumber();
            lastCloudPlanId = message.get("planId").toString();
        } else {
            lastPhoneSyncRevision = message.get("syncRevision").toLong();
            lastPhoneSyncId = message.get("requestId").toString();
            lastPhoneSyncAccountBinding = message.get("accountBinding").toString();
        }
    }

    static function isWithinStorageBudget() {
        var estimate = 4096 + 2048;
        estimate += estimatedValueBytes(exercises);
        // The rich active dictionaries live only in memory. Current releases
        // budget the compact atomic snapshot separately and retain only a small
        // small downgrade mirror in the per-key store.
        if (activeWorkoutSnapshotValid && hasAccountBinding()) {
            estimate += 16 + (sets.size() * 112) + setListNameBytes(sets);
        } else {
            estimate += estimatedValueBytes(sets);
        }
        estimate += estimatedValueBytes(plan);
        estimate += estimatedValueBytes(pending);
        estimate += estimatedValueBytes(deferredSync);
        estimate += estimatedValueBytes(processedSyncIds);
        estimate += estimatedValueBytes(accountBinding);
        estimate += estimatedValueBytes(deviceBinding);
        estimate += estimatedValueBytes(pairingGeneration);
        estimate += estimatedValueBytes(cloudDeviceBinding);
        estimate += estimatedValueBytes(activeWorkoutStartedAtSeconds);
        estimate += estimatedValueBytes(preparedWorkout);
        estimate += estimatedValueBytes(lastWorkoutSyncAtSeconds);
        estimate += estimatedValueBytes(tutorialHistory);
        return estimate <= maxEstimatedStoreBytes;
    }

    static function isWithinStorageBudgetForActiveSnapshot(snapshot) {
        var estimate = 4096 + 2048;
        estimate += estimatedValueBytes(exercises);
        estimate += estimatedValueBytes(snapshot);
        estimate += 16 + (snapshot[5].size() * 112) +
            estimatedValueBytes(snapshot[5]);
        estimate += estimatedValueBytes(plan);
        estimate += estimatedValueBytes(pending);
        estimate += estimatedValueBytes(deferredSync);
        estimate += estimatedValueBytes(processedSyncIds);
        estimate += estimatedValueBytes(accountBinding);
        estimate += estimatedValueBytes(deviceBinding);
        estimate += estimatedValueBytes(pairingGeneration);
        estimate += estimatedValueBytes(cloudDeviceBinding);
        estimate += estimatedValueBytes(preparedWorkout);
        estimate += estimatedValueBytes(lastWorkoutSyncAtSeconds);
        estimate += estimatedValueBytes(tutorialHistory);
        return estimate <= maxEstimatedStoreBytes;
    }

    static function isValidWorkoutStartedAtSeconds(value) {
        return isBoundedInteger(value, 946684800, 2147483647);
    }

    static function estimatedValueBytes(value) {
        if (value == null) {
            return 0;
        }
        return value.toString().toUtf8Array().size();
    }

    static function isValidCounter(value, maximum) {
        if (!(value instanceof Lang.Number) && !(value instanceof Lang.Long)) {
            return false;
        }
        var counter = value.toLong();
        return counter >= 1l && counter <= maximum.toLong();
    }

    static function isValidSyncFence(value, maximum, maxIdLength) {
        return value instanceof Lang.Dictionary &&
            isValidCounter(value.get("revision"), maximum) &&
            isBoundedText(value.get("id"), maxIdLength);
    }

    static function isValidPhoneSyncFence(value) {
        return isValidSyncFence(value, maxPhoneSyncRevision, maxBindingLength) &&
            isValidAccountBinding(value.get("accountBinding"));
    }

    static function isValidSyncStage(value, maximum, source) {
        if (!(value instanceof Lang.Dictionary) || value.size() != 4 ||
            !isValidCounter(value.get("revision"), maximum) ||
            !isBoundedText(value.get("id"), maxBindingLength) ||
            !isValidAccountBinding(value.get("accountBinding")) ||
            !isValidSyncMessage(value.get("message"), source) ||
            estimatedValueBytes(value) > maxLegacyStoredValueBytes) {
            return false;
        }
        var message = value.get("message");
        if (!(message instanceof Lang.Dictionary)) {
            return false;
        }
        var messageRevision = source.equals("cloud") ?
            counterToLong(message.get("planRevision")) :
            counterToLong(message.get("syncRevision"));
        return counterToLong(value.get("revision")) == messageRevision &&
            value.get("id").toString().equals(message.get("requestId").toString()) &&
            value.get("accountBinding").toString().equals(
                message.get("accountBinding").toString()
            );
    }

    static function pruneAccountScopedState() {
        var hasCloudBinding = isValidAccountBinding(accountBinding) &&
            isValidAccountBinding(stateOwnerBinding) &&
            accountBinding.toString().equals(stateOwnerBinding.toString()) &&
            isBoundedText(cloudDeviceBinding, maxBindingLength);
        if (!hasAccountBinding()) {
            pending = [];
        } else {
            var safePending = [];
            for (var i = 0; i < pending.size(); i += 1) {
                var item = pending[i];
                if (item instanceof Lang.Dictionary && bindingsMatch(item)) {
                    safePending.add(item);
                }
            }
            pending = safePending;
        }
        if (!hasAccountBinding() && !hasCloudBinding) {
            clearAccountScopedState();
        }
        if (deferredSync instanceof Lang.Dictionary &&
            (!isValidSyncMessage(deferredSync, sourceForMessage(deferredSync)) ||
                !syncBindingsMatch(deferredSync))) {
            deferredSync = null;
        }
    }

    static function nextRequestId(prefix) {
        requestCounter = (requestCounter + 1) % 100000;
        return prefix + "-" + Time.now().value().toString() + "-" +
            System.getTimer().toString() + "-" + requestCounter.toString();
    }

    static function rememberSyncRequest(replayKey) {
        processedSyncIds.add(replayKey);
        while (processedSyncIds.size() > 32) {
            processedSyncIds.remove(processedSyncIds[0]);
        }
    }

    static function isBoundedText(value, maxLength) {
        if (!(value instanceof Lang.String)) {
            return false;
        }
        var text = value.toString();
        return text.length() > 0 && text.length() <= maxLength;
    }

    static function isValidExerciseName(value) {
        return isBoundedText(value, maxExerciseNameLength) &&
            value.toString().toUtf8Array().size() <= maxExerciseNameBytes;
    }

    static function isValidAccountBinding(value) {
        if (!isBoundedText(value, 64) || value.toString().length() != 64) {
            return false;
        }
        var bytes = value.toString().toUtf8Array();
        for (var i = 0; i < bytes.size(); i += 1) {
            var code = bytes[i];
            if (!((code >= 48 && code <= 57) || (code >= 97 && code <= 102))) {
                return false;
            }
        }
        return true;
    }

    static function isValidWeight(value) {
        if (!isNumeric(value)) {
            return false;
        }
        var numeric = value.toFloat();
        return numeric == numeric && numeric >= 0.0 && numeric <= maxWeight;
    }

    (:fullLegacyState)
    static function isValidWeightStep(value) {
        if (!isNumeric(value)) {
            return false;
        }
        var numeric = value.toFloat();
        return numeric == numeric && numeric > 0.0 && numeric <= 100.0;
    }

    (:fullLegacyState)
    static function isValidRestSeconds(value) {
        return value instanceof Lang.Number && value >= 1 && value <= 3600;
    }

    (:fullLegacyState)
    static function isValidSensitivity(value) {
        return value instanceof Lang.Number && value >= 0 && value <= 2;
    }

    static function counterToLong(value) {
        if (!(value instanceof Lang.Number) && !(value instanceof Lang.Long)) {
            return 0l;
        }
        return value.toLong();
    }

    static function isValidReps(value) {
        return (value instanceof Lang.Number || value instanceof Lang.Long) &&
            value >= 1 && value <= maxReps;
    }

    static function isValidExerciseList(value, maximum) {
        if (!(value instanceof Lang.Array) || value.size() > maximum) {
            return false;
        }
        var totalNameBytes = 0;
        for (var i = 0; i < value.size(); i += 1) {
            if (!isValidExerciseName(value[i])) {
                return false;
            }
            totalNameBytes += value[i].toString().toUtf8Array().size();
            if (totalNameBytes > maxTotalNameBytes) {
                return false;
            }
        }
        return true;
    }

    static function isValidSetList(value, maximum, allowEmpty) {
        if (!(value instanceof Lang.Array) || value.size() > maximum || (!allowEmpty && value.size() == 0)) {
            return false;
        }
        var totalNameBytes = 0;
        for (var i = 0; i < value.size(); i += 1) {
            var item = value[i];
            if (!(item instanceof Lang.Dictionary) || item.size() > 11 ||
                !isValidExerciseName(item.get("exerciseName")) ||
                !isValidWeight(item.get("weight")) ||
                !isValidReps(item.get("reps")) ||
                !isOptionalBoundedNumber(item.get("activeSeconds"), 0.0, 7200.0) ||
                !isOptionalBoundedNumber(item.get("restBeforeSeconds"), 0.0, 86400.0) ||
                !isOptionalBoundedNumber(item.get("startHeartRate"), 0.0, 240.0) ||
                !isOptionalBoundedNumber(item.get("peakHeartRate"), 0.0, 240.0) ||
                !isOptionalBoundedNumber(item.get("endHeartRate"), 0.0, 240.0) ||
                !isOptionalBoundedNumber(item.get("recoveryHeartRateDrop"), 0.0, 240.0) ||
                !isOptionalBoundedNumber(item.get("detectionConfidence"), 0.0, 100.0) ||
                (item.get("setInterval") != null &&
                    !isValidSetInterval(item.get("setInterval")))) {
                return false;
            }
            totalNameBytes += item.get("exerciseName").toString().toUtf8Array().size();
            if (totalNameBytes > maxTotalNameBytes) {
                return false;
            }
        }
        return true;
    }

    static function isValidSetInterval(value) {
        if (!(value instanceof Lang.Array) || value.size() != 10 ||
            !isBoundedInteger(value[0], 0, 604800) ||
            !isBoundedInteger(value[1], 0, 604800) ||
            value[1] < value[0] || value[1] - value[0] > 7200 ||
            !isBoundedNumber(value[2], 0.0, 100000.0) ||
            !isOptionalBoundedInteger(value[3], 0, 100000)) {
            return false;
        }
        var zoneSeconds = 0;
        for (var i = 4; i < 10; i += 1) {
            if (!isBoundedInteger(value[i], 0, 7200)) {
                return false;
            }
            zoneSeconds += value[i];
        }
        return zoneSeconds <= value[1] - value[0];
    }

    static function isValidSetIntervalsList(value, expectedSets) {
        if (!(expectedSets instanceof Lang.Array) || !(value instanceof Lang.Array) ||
            value.size() != expectedSets.size() || value.size() > maxWorkoutSets) {
            return false;
        }
        for (var i = 0; i < value.size(); i += 1) {
            if (!isValidSetInterval(value[i])) {
                return false;
            }
        }
        return true;
    }

    static function areSetIntervalsConsistent(value, durationSeconds, gymTotal, garminTotal) {
        if (!(value instanceof Lang.Array) ||
            !isBoundedNumber(durationSeconds, 0.0, 604800.0) ||
            !isOptionalBoundedNumber(gymTotal, 0.0, 10000000.0) ||
            !isOptionalBoundedNumber(garminTotal, 0.0, 10000000.0)) {
            return false;
        }
        var previousEnd = 0;
        var gymSum = 0.0;
        var garminSum = 0.0;
        var hasGarminSlice = false;
        for (var i = 0; i < value.size(); i += 1) {
            var interval = value[i];
            if (!isValidSetInterval(interval) || interval[0] < previousEnd ||
                interval[1] > durationSeconds) {
                return false;
            }
            previousEnd = interval[1];
            gymSum += interval[2].toFloat();
            if (interval[3] != null) {
                hasGarminSlice = true;
                garminSum += interval[3].toFloat();
            }
        }
        if (value.size() > 0 && gymTotal == null) {
            return false;
        }
        if (gymTotal != null && gymSum > gymTotal.toFloat() + 0.1) {
            return false;
        }
        if (hasGarminSlice && garminTotal == null) {
            return false;
        }
        return garminTotal == null || garminSum <= garminTotal.toFloat() + 0.1;
    }

    static function isValidPlannedSetCount(value, actualSetCount) {
        return isBoundedInteger(value, 1, maxPlanSets) && value >= actualSetCount;
    }

    static function isValidPlannedTargetSetCount(value) {
        return isBoundedInteger(value, 1, maxPlanSets);
    }

    static function isValidCompletedPlannedSetCount(value, targetCount, actualSetCount) {
        if (!isValidPlannedTargetSetCount(targetCount) ||
            !isBoundedInteger(value, 0, maxPlanSets)) {
            return false;
        }
        var maximum = targetCount < actualSetCount ? targetCount : actualSetCount;
        return value <= maximum;
    }

    static function isValidExactPlannedProgress(legacyCount, targetCount, completedCount, actualSetCount) {
        if (targetCount == null && completedCount == null) {
            return true;
        }
        return isValidPlannedSetCount(legacyCount, actualSetCount) &&
            isValidPlannedTargetSetCount(targetCount) &&
            targetCount <= legacyCount &&
            completedCount != null &&
            isValidCompletedPlannedSetCount(completedCount, targetCount, actualSetCount);
    }

    static function isValidPendingList(value) {
        if (!(value instanceof Lang.Array) || value.size() > maxPendingWorkouts) {
            return false;
        }
        var totalNameBytes = 0;
        for (var i = 0; i < value.size(); i += 1) {
            var item = value[i];
            if (!isValidWorkoutMessage(item)) {
                return false;
            }
            totalNameBytes += setListNameBytes(item.get("sets"));
            if (totalNameBytes > maxPendingNameBytes) {
                return false;
            }
        }
        return true;
    }

    (:fullLegacyState)
    static function isValidLegacyPendingList(value) {
        if (!(value instanceof Lang.Array) || value.size() > maxPendingWorkouts) {
            return false;
        }
        var totalNameBytes = 0;
        for (var i = 0; i < value.size(); i += 1) {
            var item = value[i];
            if (!isValidLegacyWorkoutMessage(item)) {
                return false;
            }
            totalNameBytes += setListNameBytes(item.get("sets"));
            if (totalNameBytes > maxPendingNameBytes) {
                return false;
            }
        }
        return true;
    }

    (:fullLegacyState)
    static function isValidLegacyWorkoutMessage(message) {
        if (!(message instanceof Lang.Dictionary) || message.size() > 18) {
            return false;
        }
        var type = message.get("type");
        return isBoundedText(type, 20) && type.toString().equals("create_workout") &&
            isBoundedText(message.get("requestId"), maxBindingLength) &&
            isBoundedNumber(message.get("startedAtSeconds"), 946684800.0, 2147483647.0) &&
            isBoundedNumber(message.get("durationSeconds"), 0.0, 604800.0) &&
            isOptionalBoundedNumber(message.get("gymCalories"), 0.0, 10000000.0) &&
            isOptionalBoundedNumber(message.get("garminCalories"), 0.0, 10000000.0) &&
            isOptionalBoundedNumber(message.get("avgHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("maxHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("lastHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("heartRateZone"), 0.0, 5.0) &&
            isValidSetList(message.get("sets"), maxWorkoutSets, false) &&
            (message.get("setMetrics") == null ||
                isValidSetMetricsList(message.get("setMetrics"), message.get("sets"))) &&
            (message.get("setIntervals") == null ||
                (isValidSetIntervalsList(message.get("setIntervals"), message.get("sets")) &&
                    areSetIntervalsConsistent(
                        message.get("setIntervals"),
                        message.get("durationSeconds"),
                        message.get("gymCalories"),
                        message.get("garminCalories")
                    ))) &&
            (message.get("plannedSetCount") == null ||
                isValidPlannedSetCount(
                    message.get("plannedSetCount"),
                    setListCount(message.get("sets"))
                )) &&
            message.get("plannedTargetSetCount") == null &&
            message.get("completedPlannedSetCount") == null;
    }

    static function isValidSetMetricsList(value, expectedSets) {
        if (!(expectedSets instanceof Lang.Array) || !(value instanceof Lang.Array) ||
            value.size() != expectedSets.size() ||
            value.size() > maxWorkoutSets) {
            return false;
        }
        for (var i = 0; i < value.size(); i += 1) {
            var metrics = value[i];
            if (!(metrics instanceof Lang.Array) || metrics.size() != 7 ||
                !isOptionalBoundedNumber(metrics[0], 0.0, 7200.0) ||
                !isOptionalBoundedNumber(metrics[1], 0.0, 86400.0) ||
                !isOptionalBoundedNumber(metrics[2], 0.0, 240.0) ||
                !isOptionalBoundedNumber(metrics[3], 0.0, 240.0) ||
                !isOptionalBoundedNumber(metrics[4], 0.0, 240.0) ||
                !isOptionalBoundedNumber(metrics[5], 0.0, 240.0) ||
                !isOptionalBoundedNumber(metrics[6], 0.0, 100.0)) {
                return false;
            }
        }
        return true;
    }

    (:fullLegacyState)
    static function normalizedLegacyPendingList(source) {
        var copy = [];
        for (var i = 0; i < source.size(); i += 1) {
            var message = source[i];
            var safe = {
                "type" => "create_workout",
                "requestId" => message.get("requestId").toString(),
                "startedAtSeconds" => message.get("startedAtSeconds"),
                "durationSeconds" => message.get("durationSeconds"),
                "sets" => normalizedSetList(message.get("sets"))
            };
            copyOptionalLegacyMetric(safe, message, "gymCalories");
            copyOptionalLegacyMetric(safe, message, "garminCalories");
            copyOptionalLegacyMetric(safe, message, "avgHeartRate");
            copyOptionalLegacyMetric(safe, message, "maxHeartRate");
            copyOptionalLegacyMetric(safe, message, "lastHeartRate");
            copyOptionalLegacyMetric(safe, message, "heartRateZone");
            if (message.get("setMetrics") != null) {
                safe.put("setMetrics", message.get("setMetrics"));
            }
            if (message.get("setIntervals") != null) {
                safe.put("setIntervals", message.get("setIntervals"));
            }
            if (message.get("plannedSetCount") != null) {
                safe.put("plannedSetCount", message.get("plannedSetCount"));
            }
            copy.add(safe);
        }
        return copy;
    }

    (:fullLegacyState)
    static function copyOptionalLegacyMetric(target, source, key) {
        var value = source.get(key);
        if (value != null) {
            target.put(key, value);
        }
    }

    static function canQueueWorkout(message) {
        if (pending.size() >= maxPendingWorkouts || !isValidWorkoutMessage(message)) {
            return false;
        }
        var totalNameBytes = setListNameBytes(message.get("sets"));
        for (var i = 0; i < pending.size(); i += 1) {
            totalNameBytes += setListNameBytes(pending[i].get("sets"));
            if (totalNameBytes > maxPendingNameBytes) {
                return false;
            }
        }
        return true;
    }

    static function isValidWorkoutMessage(message) {
        if (!(message instanceof Lang.Dictionary) || message.size() > 20) {
            return false;
        }
        var version = message.get("bindingVersion");
        var type = message.get("type");
        return version instanceof Lang.Number && version == bindingVersion &&
            isBoundedText(type, 20) && type.toString().equals("create_workout") &&
            isBoundedText(message.get("requestId"), maxBindingLength) &&
            isValidAccountBinding(message.get("accountBinding")) &&
            isBoundedText(message.get("deviceBinding"), maxBindingLength) &&
            isValidOptionalAccountBinding(message.get("pairingGeneration")) &&
            isBoundedNumber(message.get("startedAtSeconds"), 946684800.0, 2147483647.0) &&
            isOptionalBoundedNumber(message.get("durationSeconds"), 0.0, 604800.0) &&
            isOptionalBoundedNumber(message.get("gymCalories"), 0.0, 10000000.0) &&
            isOptionalBoundedNumber(message.get("garminCalories"), 0.0, 10000000.0) &&
            isOptionalBoundedNumber(message.get("avgHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("maxHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("lastHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("heartRateZone"), 0.0, 5.0) &&
            isValidSetList(message.get("sets"), maxWorkoutSets, false) &&
            (message.get("setMetrics") == null ||
                isValidSetMetricsList(message.get("setMetrics"), message.get("sets"))) &&
            (message.get("setIntervals") == null ||
                (isValidSetIntervalsList(message.get("setIntervals"), message.get("sets")) &&
                    areSetIntervalsConsistent(
                        message.get("setIntervals"),
                        message.get("durationSeconds"),
                        message.get("gymCalories"),
                        message.get("garminCalories")
                    ))) &&
            (message.get("plannedSetCount") == null ||
                isValidPlannedSetCount(
                    message.get("plannedSetCount"),
                    setListCount(message.get("sets"))
                )) &&
            isValidExactPlannedProgress(
                message.get("plannedSetCount"),
                message.get("plannedTargetSetCount"),
                message.get("completedPlannedSetCount"),
                setListCount(message.get("sets"))
            );
    }

    static function isValidOptionalAccountBinding(value) {
        return value == null || isValidAccountBinding(value);
    }

    static function isBoundedNumber(value, minimum, maximum) {
        if (!isNumeric(value)) {
            return false;
        }
        var numeric = value.toFloat();
        return numeric == numeric && numeric >= minimum && numeric <= maximum;
    }

    static function isOptionalBoundedNumber(value, minimum, maximum) {
        return value == null || isBoundedNumber(value, minimum, maximum);
    }

    static function isBoundedInteger(value, minimum, maximum) {
        return (value instanceof Lang.Number || value instanceof Lang.Long) &&
            value >= minimum && value <= maximum;
    }

    static function isOptionalBoundedInteger(value, minimum, maximum) {
        return value == null || isBoundedInteger(value, minimum, maximum);
    }

    static function isNumeric(value) {
        return value instanceof Lang.Number || value instanceof Lang.Float ||
            value instanceof Lang.Long || value instanceof Lang.Double;
    }

    static function setListNameBytes(setList) {
        var total = 0;
        for (var i = 0; i < setList.size(); i += 1) {
            total += setList[i].get("exerciseName").toString().toUtf8Array().size();
        }
        return total;
    }

    static function setListCount(value) {
        return value instanceof Lang.Array ? value.size() : 0;
    }

    static function isValidProcessedSyncIds(value) {
        if (!(value instanceof Lang.Array) || value.size() > 32) {
            return false;
        }
        for (var i = 0; i < value.size(); i += 1) {
            if (!isBoundedText(value[i], maxBindingLength + 8)) {
                return false;
            }
        }
        return true;
    }

    // CIQ 3.4 products with a 96 KiB watch-app ceiling keep the current ownerless
    // set list in one bounded snapshot instead of carrying the larger pre-v2.2.8
    // quarantine copier. Account-bound workouts still use activeWorkoutV1, while
    // malformed or legacy pending ownerless payloads remain unsendable.
    (:compactLegacyState)
    static function ensureUnboundAtomicQuarantine() {
        if (hasAccountBinding()) {
            return true;
        }
        if (accountBinding != null || stateOwnerBinding != null) {
            return false;
        }
        // Once this process enters the ownerless recovery state, keep it
        // fail-closed on every write failure; a later retry may finish the marker.
        legacyUnboundState = true;
        if (!refreshLegacyCurrentQuarantine()) {
            return false;
        }
        try {
            Storage.setValue("legacyUnboundState", true);
            return true;
        } catch (e) {
            return false;
        }
    }

    (:compactLegacyState)
    static function ensureLegacyQuarantine() {
        return legacyCompactCount != -2;
    }

    (:compactLegacyState)
    static function refreshLegacyCurrentQuarantine() {
        if (legacyCompactCount == -2 ||
            !isValidSetList(sets, maxWorkoutSets, true)) {
            return false;
        }
        try {
            Storage.setValue("legacyCompactCurrentV1", [
                1,
                normalizedSetList(sets),
                activeWorkoutStartedAtSeconds
            ]);
            legacyCompactCount = sets.size();
            return true;
        } catch (e) {
            return false;
        }
    }

    (:compactLegacyState)
    static function restoreLegacyCurrentQuarantine(allowSeed) {
        var snapshot = Storage.getValue("legacyCompactCurrentV1");
        if (snapshot == null) {
            legacyCompactCount = allowSeed ? -1 : -2;
            return allowSeed;
        }
        if (!(snapshot instanceof Lang.Array) || snapshot.size() != 3 ||
            !(snapshot[0] instanceof Lang.Number) || snapshot[0] != 1 ||
            !isValidSetList(snapshot[1], maxWorkoutSets, true) ||
            (snapshot[2] != null && !isValidWorkoutStartedAtSeconds(snapshot[2]))) {
            legacyCompactCount = -2;
            return false;
        }
        sets = snapshot[1];
        activeWorkoutStartedAtSeconds = sets.size() > 0 ? snapshot[2] : null;
        legacyCompactCount = sets.size();
        return true;
    }

    (:compactLegacyState)
    static function legacyCurrentSetCount() {
        return legacyCompactCount;
    }

    (:compactLegacyState)
    static function isValidLegacyPendingList(value) {
        return false;
    }

    (:compactLegacyState)
    static function normalizedLegacyPendingList(source) {
        return [];
    }

    static function builtInExercises() {
        return ["Bench Press", "Squat", "Deadlift", "Pull Up", "Overhead Press"];
    }

    static function containsName(list, name) {
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i].toString().equals(name)) {
                return true;
            }
        }
        return false;
    }
}
