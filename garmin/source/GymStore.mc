using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Time as Time;

class GymStore {
    static var bindingVersion = 2;
    static var storageSchemaVersion = 4;
    static var exercises = ["Bench Press", "Squat", "Deadlift", "Pull Up", "Overhead Press"];
    static var sets = [];
    static var plan = [];
    static var pending = [];
    static var exerciseIndex = 0;
    static var weight = 50.0;
    static var reps = 10;
    static var restEndsAt = 0;
    static var status = "READY";
    static var weightStep = 2.5;
    static var restSecondsDefault = 90;
    static var autoPromptEnabled = true;
    static var sensitivityIndex = 1;
    static var language = "en";
    static var accountBinding = null;
    static var stateOwnerBinding = null;
    static var deviceBinding = null;
    static var cloudDeviceBinding = null;
    static var deferredSync = null;
    static var processedSyncIds = [];
    static var lastPhoneSyncRevision = 0l;
    static var lastPhoneSyncId = null;
    static var lastPhoneSyncAccountBinding = null;
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
    static var legacyQuarantineReady = false;
    static var legacyRawExercises = null;
    static var legacyRawSets = null;
    static var legacyRawPlan = null;
    static var legacyRawPending = null;
    static var requestCounter = 0;

    static var maxPlanSets = 60;
    static var maxWorkoutSets = 60;
    static var maxPendingWorkouts = 2;
    static var maxPendingNameBytes = 12000;
    static var maxExerciseNameLength = 160;
    static var maxExerciseNameBytes = 640;
    static var maxTotalNameBytes = 12000;
    static var maxBindingLength = 128;
    static var maxWeight = 1000000.0;
    static var maxReps = 10000;
    static var maxPhoneSyncRevision = 9007199254740991l;
    static var maxCloudPlanRevision = 2147483647;
    static var maxEstimatedStoreBytes = 24000;
    static var maxLegacyStoredValueBytes = 32768;

    static function load() {
        var savedAccountBinding = Storage.getValue("accountBinding");
        accountBinding = isValidAccountBinding(savedAccountBinding) ? savedAccountBinding.toString() : null;
        var savedStateOwnerBinding = Storage.getValue("stateOwnerBinding");
        stateOwnerBinding = isValidAccountBinding(savedStateOwnerBinding) ?
            savedStateOwnerBinding.toString() : null;
        var savedStorageSchemaVersion = Storage.getValue("storageSchemaVersion");
        var legacyUpgrade = savedStorageSchemaVersion == null && accountBinding != null &&
            stateOwnerBinding == null;
        var savedLegacyMarker = Storage.getValue("legacyUnboundState");
        var legacyUnboundUpgrade = savedStorageSchemaVersion == null &&
            accountBinding == null && stateOwnerBinding == null &&
            (Storage.getValue("exercises") != null || Storage.getValue("sets") != null ||
                Storage.getValue("plan") != null || Storage.getValue("pending") != null);
        legacyUnboundState = accountBinding == null &&
            ((savedLegacyMarker instanceof Lang.Boolean && savedLegacyMarker) ||
                legacyUnboundUpgrade);
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
        }
        if (legacyUnboundState) {
            // Once present, this single-value snapshot is the atomic source of truth for
            // post-upgrade edits. The separate raw quarantine below remains an immutable
            // copy of the pre-upgrade values, including values above today's limits.
            restoreLegacyCurrentQuarantine();
        }
        var savedDeviceBinding = Storage.getValue("deviceBinding");
        deviceBinding = isBoundedText(savedDeviceBinding, maxBindingLength) ? savedDeviceBinding.toString() : null;
        var savedCloudDeviceBinding = Storage.getValue("cloudDeviceBinding");
        cloudDeviceBinding = isBoundedText(savedCloudDeviceBinding, maxBindingLength) ? savedCloudDeviceBinding.toString() : null;
        var savedDeferredSync = Storage.getValue("deferredSync");
        deferredSync = savedDeferredSync instanceof Lang.Dictionary ? savedDeferredSync : null;
        var savedProcessedSyncIds = Storage.getValue("processedSyncIds");
        processedSyncIds = isValidProcessedSyncIds(savedProcessedSyncIds) ? savedProcessedSyncIds : [];
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
        }
    }

    static function save() {
        try {
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
            Storage.setValue("exercises", exercises);
            Storage.setValue("sets", sets);
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
            Storage.setValue("cloudDeviceBinding", cloudDeviceBinding);
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

    static function applyCurrentPlanSet() {
        if (plan.size() == 0) {
            return;
        }
        var exerciseName = currentExercise();
        var item = null;
        for (var i = 0; i < plan.size(); i += 1) {
            var candidate = plan[i];
            if (candidate instanceof Lang.Dictionary && candidate.get("exerciseName").toString().equals(exerciseName)) {
                item = candidate;
                break;
            }
        }
        if (item instanceof Lang.Dictionary) {
            var plannedWeight = item.get("weight");
            var plannedReps = item.get("reps");
            if (plannedWeight instanceof Lang.Number || plannedWeight instanceof Lang.Float) {
                weight = plannedWeight;
            }
            if (plannedReps instanceof Lang.Number) {
                reps = plannedReps;
            }
        }
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
            return;
        }
        sets.add({
            "exerciseName" => currentExercise(),
            "weight" => weight,
            "reps" => reps
        });
        GymSession.addSetBoost(weight, reps);
        GymSession.clearAutoPrompt();
        restEndsAt = System.getTimer() + (restSecondsDefault * 1000);
        status = "SET SAVED";
        save();
    }

    static function cycleWeightStep() {
        if (weightStep < 5.0) {
            weightStep = 5.0;
        } else if (weightStep < 10.0) {
            weightStep = 10.0;
        } else {
            weightStep = 2.5;
        }
        save();
    }

    static function cycleRestDefault() {
        if (restSecondsDefault < 90) {
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

    static function cycleSensitivity() {
        sensitivityIndex = (sensitivityIndex + 1) % 3;
        save();
    }

    static function sensitivityLabel() {
        if (isUk()) {
            if (sensitivityIndex == 0) {
                return "НИЗ";
            } else if (sensitivityIndex == 2) {
                return "ВИС";
            }
            return "НОРМ";
        }
        if (sensitivityIndex == 0) {
            return "LOW";
        } else if (sensitivityIndex == 2) {
            return "HIGH";
        }
        return "NORMAL";
    }

    static function clearWorkout() {
        sets = [];
        plan = [];
        restEndsAt = 0;
        applyDeferredSyncIfIdle();
        save();
    }

    static function clearActiveWorkout() {
        sets = [];
        restEndsAt = 0;
        applyDeferredSyncIfIdle();
        save();
    }

    static function restSeconds() {
        if (restEndsAt <= 0) {
            return 0;
        }
        var remaining = restEndsAt - System.getTimer();
        if (remaining <= 0) {
            restEndsAt = 0;
            return 0;
        }
        return (remaining / 1000).toNumber();
    }

    static function workoutMessage() {
        if (!hasAccountBinding() || !isValidSetList(sets, maxWorkoutSets, false)) {
            return null;
        }
        var requestId = nextRequestId("workout");
        var setCopies = [];
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
            setCopies.add({
                "exerciseName" => exerciseName.toString(),
                "weight" => setWeight,
                "reps" => setReps
            });
        }
        return {
            "type" => "create_workout",
            "bindingVersion" => bindingVersion,
            "requestId" => requestId,
            "accountBinding" => accountBinding,
            "deviceBinding" => deviceBinding,
            "startedAtSeconds" => Time.now().value(),
            "durationSeconds" => GymSession.elapsedSeconds,
            "gymCalories" => GymSession.gymCalories,
            "garminCalories" => GymSession.garminCalories,
            "avgHeartRate" => GymSession.avgHr,
            "maxHeartRate" => GymSession.maxHr,
            "lastHeartRate" => GymSession.hr,
            "heartRateZone" => GymSession.zone,
            "sets" => setCopies
        };
    }

    static function applyPhoneSync(message) {
        return applySyncFromSource(message, "phone");
    }

    static function applyCloudSync(message) {
        return applySyncFromSource(message, "cloud");
    }

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
        var replayKey = bindingSource + ":" + safeMessage.get("requestId").toString();
        var resetValue = safeMessage.get("resetWorkout");
        var resetWorkout = bindingSource.equals("phone") &&
            resetValue instanceof Lang.Boolean && resetValue;
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
        if (bindingSource.equals("cloud") && cloudDeviceBinding != null &&
            !cloudDeviceBinding.toString().equals(nextDeviceBinding)) {
            status = "BAD BIND";
            return false;
        }

        // The phone revision is global to this Garmin device and is checked before any
        // account-scoped state is cleared. A delayed message from the previous account can
        // therefore never switch the watch back after a newer account transition.
        var revisionStatus = syncRevisionStatus(safeMessage, bindingSource);
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
        }
        rememberSyncRequest(replayKey);
        rememberSyncRevision(safeMessage, bindingSource);

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

    static function applyValidatedSync(message) {
        var syncedLanguage = message.get("language");
        if (syncedLanguage != null) {
            language = normalizedLanguage(syncedLanguage.toString());
        }
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
        return true;
    }

    static function hasOnlySyncKeys(message, trustedSource) {
        if (!(message instanceof Lang.Dictionary) || message.size() > 14) {
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
        return key.equals("syncRevision") || key.equals("language") || key.equals("exercises");
    }

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
            var syncedLanguage = message.get("language");
            if (syncedLanguage != null) {
                normalized.put("language", syncedLanguage.toString());
            }
            var syncedExercises = message.get("exercises");
            if (syncedExercises != null) {
                normalized.put("exercises", copySyncArray(syncedExercises));
            }
        }
        var resetWorkout = message.get("resetWorkout");
        if (resetWorkout != null) {
            normalized.put("resetWorkout", resetWorkout);
        }
        return normalized;
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
        return version instanceof Lang.Number && version == bindingVersion &&
            isValidAccountBinding(messageAccount) &&
            isBoundedText(messageDevice, maxBindingLength) &&
            accountBinding.toString().equals(messageAccount.toString()) &&
            deviceBinding.toString().equals(messageDevice.toString());
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
        return isBoundedText(deviceBinding, maxBindingLength) &&
            deviceBinding.toString().equals(messageDevice.toString());
    }

    static function removePendingByRequestId(requestId) {
        if (!isBoundedText(requestId, maxBindingLength)) {
            return false;
        }
        var requestText = requestId.toString();
        for (var i = 0; i < pending.size(); i += 1) {
            var item = pending[i];
            if (item instanceof Lang.Dictionary) {
                var itemRequestId = item.get("requestId");
                if (isBoundedText(itemRequestId, maxBindingLength) &&
                    itemRequestId.toString().equals(requestText)) {
                    pending.remove(item);
                    if (save()) {
                        return true;
                    }
                    load();
                    return false;
                }
            }
        }
        return false;
    }

    static function queueWorkout(message) {
        if (!canQueueWorkout(message)) {
            return false;
        }
        var requestId = message.get("requestId").toString();
        var nextPending = [];
        for (var i = 0; i < pending.size(); i += 1) {
            nextPending.add(pending[i]);
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
            // The marker is written first and the queue second. Recovery keeps the active
            // workout when the queue write fails, and clears it when the queue is durable.
            Storage.setValue("queuedActiveRequestId", requestId);
            Storage.setValue("pending", nextPending);
        } catch (e) {
            status = "SAVE FAIL";
            return false;
        }

        pending = nextPending;
        sets = [];
        plan = [];
        restEndsAt = 0;
        applyDeferredSyncIfIdle();
        var cleaned = save();
        if (cleaned) {
            try {
                Storage.deleteValue("queuedActiveRequestId");
            } catch (e) {
                // A leftover marker is safe and idempotent on the next load.
            }
            status = "QUEUED";
        } else {
            // The pending workout was already persisted before active state was touched.
            status = "QUEUED SAFE";
        }
        return true;
    }

    static function recoverQueuedWorkout() {
        var marker = Storage.getValue("queuedActiveRequestId");
        if (!isBoundedText(marker, maxBindingLength)) {
            return;
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
            sets = [];
            plan = [];
            restEndsAt = 0;
            applyDeferredSyncIfIdle();
            if (!save()) {
                return;
            }
        }
        try {
            Storage.deleteValue("queuedActiveRequestId");
        } catch (e) {
            // Retrying recovery is safe.
        }
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
        accountBinding = null;
        stateOwnerBinding = null;
        deviceBinding = null;
        cloudDeviceBinding = null;
        sets = [];
        plan = [];
        pending = [];
        deferredSync = null;
        processedSyncIds = [];
        // The phone fence is device-global, not account-scoped. Keeping it prevents a
        // delayed prior-account sync from undoing a newer transition.
        lastCloudPlanRevision = 0;
        lastCloudPlanId = null;
        restEndsAt = 0;
        weight = 50.0;
        reps = 10;
        exercises = builtInExercises();
        exerciseIndex = 0;
    }

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

    static function restoreLegacyCurrentQuarantine() {
        var snapshot = Storage.getValue("legacyQuarantineCurrent");
        if (!(snapshot instanceof Lang.Dictionary) ||
            !isValidLegacyCurrentQuarantine(snapshot)) {
            return false;
        }
        exercises = copyExerciseList(snapshot.get("exercises"));
        sets = normalizedSetList(snapshot.get("sets"));
        plan = normalizedSetList(snapshot.get("plan"));
        pending = normalizedLegacyPendingList(snapshot.get("pending"));
        weight = snapshot.get("weight");
        reps = snapshot.get("reps");
        weightStep = snapshot.get("weightStep");
        restSecondsDefault = snapshot.get("restSecondsDefault");
        autoPromptEnabled = snapshot.get("autoPromptEnabled");
        sensitivityIndex = snapshot.get("sensitivityIndex");
        language = snapshot.get("language").toString();
        return true;
    }

    static function isValidLegacyCurrentQuarantine(value) {
        if (!(value instanceof Lang.Dictionary) || value.size() != 12 ||
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
            !isBoundedText(value.get("language"), 2)) {
            return false;
        }
        var savedLanguage = value.get("language").toString();
        return (savedLanguage.equals("en") || savedLanguage.equals("uk") || savedLanguage.equals("ru")) &&
            estimatedValueBytes(value) <= maxEstimatedStoreBytes;
    }

    static function copyExerciseList(source) {
        var copy = [];
        for (var i = 0; i < source.size(); i += 1) {
            copy.add(source[i].toString());
        }
        return copy;
    }

    static function isBoundedLegacyStoredValue(value) {
        return value == null || estimatedValueBytes(value) <= maxLegacyStoredValueBytes;
    }

    static function normalizedSetList(source) {
        var copy = [];
        for (var i = 0; i < source.size(); i += 1) {
            var item = source[i];
            copy.add({
                "exerciseName" => item.get("exerciseName").toString(),
                "weight" => item.get("weight"),
                "reps" => item.get("reps")
            });
        }
        return copy;
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
        var estimate = 4096;
        estimate += estimatedValueBytes(exercises);
        estimate += estimatedValueBytes(sets);
        estimate += estimatedValueBytes(plan);
        estimate += estimatedValueBytes(pending);
        estimate += estimatedValueBytes(deferredSync);
        estimate += estimatedValueBytes(processedSyncIds);
        estimate += estimatedValueBytes(accountBinding);
        estimate += estimatedValueBytes(deviceBinding);
        estimate += estimatedValueBytes(cloudDeviceBinding);
        return estimate <= maxEstimatedStoreBytes;
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

    static function isValidWeightStep(value) {
        if (!isNumeric(value)) {
            return false;
        }
        var numeric = value.toFloat();
        return numeric == numeric && numeric > 0.0 && numeric <= 100.0;
    }

    static function isValidRestSeconds(value) {
        return value instanceof Lang.Number && value >= 1 && value <= 3600;
    }

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
            if (!(item instanceof Lang.Dictionary) ||
                !isValidExerciseName(item.get("exerciseName")) ||
                !isValidWeight(item.get("weight")) ||
                !isValidReps(item.get("reps"))) {
                return false;
            }
            totalNameBytes += item.get("exerciseName").toString().toUtf8Array().size();
            if (totalNameBytes > maxTotalNameBytes) {
                return false;
            }
        }
        return true;
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

    static function isValidLegacyWorkoutMessage(message) {
        if (!(message instanceof Lang.Dictionary) || message.size() > 16) {
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
            isValidSetList(message.get("sets"), maxWorkoutSets, false);
    }

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
            copy.add(safe);
        }
        return copy;
    }

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
        if (!(message instanceof Lang.Dictionary)) {
            return false;
        }
        var version = message.get("bindingVersion");
        var type = message.get("type");
        return version instanceof Lang.Number && version == bindingVersion &&
            isBoundedText(type, 20) && type.toString().equals("create_workout") &&
            isBoundedText(message.get("requestId"), maxBindingLength) &&
            isValidAccountBinding(message.get("accountBinding")) &&
            isBoundedText(message.get("deviceBinding"), maxBindingLength) &&
            isBoundedNumber(message.get("startedAtSeconds"), 946684800.0, 2147483647.0) &&
            isBoundedNumber(message.get("durationSeconds"), 0.0, 604800.0) &&
            isOptionalBoundedNumber(message.get("gymCalories"), 0.0, 10000000.0) &&
            isOptionalBoundedNumber(message.get("garminCalories"), 0.0, 10000000.0) &&
            isOptionalBoundedNumber(message.get("avgHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("maxHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("lastHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("heartRateZone"), 0.0, 5.0) &&
            isValidSetList(message.get("sets"), maxWorkoutSets, false);
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
