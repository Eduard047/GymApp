using Toybox.Application as App;
using Toybox.Application.Storage as Storage;
using Toybox.Lang as Lang;
using Toybox.System as System;
using Toybox.Time as Time;

class GymStore {
    static const bindingVersion = 2;
    private static const storageSchemaVersion = 6;
    static var exercises = ["Bench Press", "Squat", "Deadlift", "Pull Up", "Overhead Press"];
    static var sets = [];
    static var plan = [];
    (:compactLegacyState)
    static var persistedPlanSource = null;
    (:compactLegacyState)
    static var persistedPlanBytes = 0;
    (:compactLegacyState)
    static var persistedPlanNeedsV5Write = false;
    static var pending = [];
    private static var parkedPending = null;
    private static var pendingEstimateSource = null;
    private static var pendingEstimateBytes = 0;
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
    // The active workout is committed as one Object Store value. Legacy per-key
    // values remain readable only as a migration fallback; once an owner-bound
    // v4 snapshot exists they are cleared and never override that transaction.
    static var activeWorkoutSnapshotValid = false;
    static var activeWorkoutTimelineValid = false;
    // Indexed active snapshots are meaningful only beside the exact validated
    // durable catalog. A missing/corrupt catalog is repaired before any new v4
    // commit; if an unreadable snapshot cannot be removed, all writes stay
    // fail-closed so it can never be resurrected under the built-in names.
    static var exerciseCatalogNeedsWrite = true;
    static var exerciseCatalogRepairRequired = false;
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
    static var lastRuntimeCheckpointTimerMs = null;
    // A validated activeWorkoutV1 checkpoint lets a restarted session shift new
    // intervals onto the durable timeline. Legacy sets without that checkpoint
    // stay fail-closed and omit optional interval diagnostics.
    static var resumedWorkoutIntervalsInvalid = false;
    static const undoWindowMs = 5000;
    static var status = GymStatus.READY;
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
    // Strings are immutable. Reuse syntax validation for the last two exact
    // values; ownership is still checked separately against the current state.
    // This bounds retention and avoids repeated 64-byte walks in one callback.
    private static var validatedBindingA = null;
    private static var validatedBindingB = null;
    // Startup recovery temporarily makes the generation write the commit point.
    // Ordinary account transitions keep the owner marker as their commit point.
    static var pairingRecoveryCommitLast = false;
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
    (:compactLegacyState)
    static var legacyPendingUnarchived = false;
    static var requestCounter = 0;

    (:fullLegacyState)
    static const keepsSetDiagnostics = true;
    (:compactLegacyState)
    static const keepsSetDiagnostics = false;
    // New workouts and plans use a common 30-set product limit. The 60-set
    // storage and sync limits below remain for recovery of older records.
    static const maxNewWorkoutSets = 30;
    static const maxPlanSets = 60;
    static const maxWorkoutSets = 60;
    // Preserve a bounded offline backlog. New workouts wait for phone ACKs so
    // the compact watch never carries another live session beside queued data.
    // The byte budgets remain authoritative; no queued workout is evicted.
    private static const maxPendingWorkouts = 8;
    // New-queue limits for the 96 KiB lite profile (GymPendingJournal.begin and
    // advance). Stored legacy queues stay valid under the limits above and are
    // never trimmed.
    (:compactWorkoutMode96)
    static const queueLimit = 3;
    (:compactWorkoutMode96)
    static const queueNameBudget = 4500;
    // 128 KiB tier limits for an incoming phone sync, from simulator heap
    // measurements that keep a 2 KB free-heap floor. Three profiles: the tight
    // default (no plan, small catalog), the wide Instinct profile, and fr55.
    (:mem128, :notFr55Memory, :noMem128Wide)
    static const memPlanSets = 0;
    (:mem128, :notFr55Memory, :noMem128Wide)
    static const memPlanChars = 0;
    (:mem128, :notFr55Memory, :noMem128Wide)
    static const memCatalogEntries = 5;
    (:mem128, :notFr55Memory, :noMem128Wide)
    static const memCatalogChars = 100;
    (:mem128Wide)
    static const memPlanSets = 20;
    (:mem128Wide)
    static const memPlanChars = 500;
    (:mem128Wide)
    static const memCatalogEntries = 40;
    (:mem128Wide)
    static const memCatalogChars = 700;
    (:mem128, :fr55Memory)
    static const memPlanSets = 8;
    (:mem128, :fr55Memory)
    static const memPlanChars = 160;
    (:mem128, :fr55Memory)
    static const memCatalogEntries = 12;
    (:mem128, :fr55Memory)
    static const memCatalogChars = 240;

    // True when the raw incoming plan fits this tier. Runs on the transport
    // dictionary before any copy; malformed shapes return true so the normal
    // validation rejects them. The catalog is trimmed by trimSyncCatalog.
    (:mem128)
    static function syncFitsMemory(message) {
        var names = message.get("planNames");
        if (names instanceof Lang.Array) {
            var count = names.size();
            if (count > memPlanSets) { return false; }
            var chars = 0;
            for (var i = 0; i < count; i++) {
                var item = names[i];
                if (!(item instanceof Lang.String)) { return true; }
                chars += item.length();
                if (chars > memPlanChars) { return false; }
            }
        }
        return true;
    }

    // Keeps the leading catalog entries that fit the tier's entry and character
    // limits. A catalog that is not an array of strings is left for the normal
    // validation to reject.
    (:mem128)
    static function trimSyncCatalog(message) {
        var catalog = message.get("exercises");
        if (!(catalog instanceof Lang.Array)) { return; }
        var total = catalog.size();
        var keep = 0;
        var chars = 0;
        for (var i = 0; i < total; i++) {
            var entry = catalog[i];
            if (!(entry instanceof Lang.String)) { return; }
            if (i >= memCatalogEntries) { continue; }
            chars += entry.length();
            if (keep == i && chars <= memCatalogChars) { keep = i + 1; }
        }
        if (keep < total) { message.put("exercises", catalog.slice(0, keep)); }
    }
    private static const maxPendingNameBytes = 12000;
    private static const maxExerciseNameLength = 160;
    private static const maxExerciseNameBytes = 640;
    private static const maxTotalNameBytes = 12000;
    static const maxBindingLength = 128;
    static const maxWeight = 1000000.0;
    static const maxReps = 10000;
    static const maxPhoneSyncRevision = 9007199254740991l;
    static const maxCloudPlanRevision = 2147483647;
    private static const maxEstimatedStoreBytes = 24000;
    private static const maxLegacyStoredValueBytes = 32768;
    (:fullLegacyState)
    private static const maxRuntimeCheckpointBytes = 2048;
    private static const runtimeCheckpointIntervalMs = 15000;
    (:fullLegacyState)
    private static const maxRuntimeClockRecoverySeconds = 30;
    private static const maxTutorialAccounts = 4;

    // An active snapshot is authoritative whenever it is present. In particular,
    // do not materialize its duplicate compatibility mirror when snapshot cleanup
    // fails; the caller passes null only when there is no snapshot to restore.
    (:notFr55Memory, :richWorkoutMode, :inline)
    static function restoreLegacySetMirrorIfSnapshotAbsent(savedActive) {
        if (savedActive != null) { return false; }
        var savedSets = Storage.getValue("sets");
        sets = isValidSetList(savedSets, maxWorkoutSets, true) ? savedSets : [];
        resumedWorkoutIntervalsInvalid = sets.size() > 0;
        var savedStartedAt = Storage.getValue("activeWorkoutStartedAtSeconds");
        activeWorkoutStartedAtSeconds = sets.size() > 0 &&
            isValidWorkoutStartedAtSeconds(savedStartedAt) ? savedStartedAt : null;
        return true;
    }

    (:fr55Memory, :inline)
    static function restoreLegacySetMirrorIfSnapshotAbsent(savedActive) {
        return false;
    }

    // The manual 96 KiB profile also avoids reviving the old per-key set
    // mirror. The plan and pending migration paths remain independent.
    (:notFr55Memory, :richWorkoutMode, :inline)
    static function discardLegacyUnboundActiveWorkout() {
    }

    (:fr55Memory, :inline)
    static function discardLegacyUnboundActiveWorkout() {
        sets = [];
        activeWorkoutStartedAtSeconds = null;
        resumedWorkoutIntervalsInvalid = false;
        resetActiveWorkoutSnapshotState();
        resetRuntimeCheckpointState();
        if (legacyCompactCount != -2) { legacyCompactCount = 0; }
    }

    // Drop only the obsolete ownerless active set mirror after the existing
    // plan and pending values have been migrated and validated. The v6 active
    // journal path does not enter this legacy-quarantine branch.
    (:fullLegacyState)
    static function load() {
        parkedPending = null;
        pairingRecoveryCommitLast = false;
        clearTransientSetActions();
        lastLoggedSetEndSeconds = 0;
        resumedWorkoutIntervalsInvalid = false;
        resetActiveWorkoutSnapshotState();
        resetRuntimeCheckpointState();
        preparedWorkout = null;
        lastWorkoutSyncAtSeconds = null;
        tutorialHistory = [];
        exerciseCatalogRepairRequired = false;
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
                accountBinding.equals(stateOwnerBinding)) || legacyUpgrade);
        var savedExercises = Storage.getValue("exercises");
        legacyRawExercises = legacyUnboundState ? savedExercises : null;
        var savedExerciseCatalogValid =
            isValidExerciseList(savedExercises, maxPlanSets) && savedExercises.size() > 0;
        exerciseCatalogNeedsWrite = !savedExerciseCatalogValid;
        if (savedExerciseCatalogValid) {
            exercises = savedExercises;
        } else {
            exercises = builtInExercises();
        }
        // Bound installs use activeWorkoutV1 as the authority. Avoid decoding
        // the compatibility mirror until we know that no snapshot can replace
        // it; ownerless values still load early for their quarantine boundary.
        var savedSets = null;
        if (legacyUnboundState) {
            savedSets = Storage.getValue("sets");
            legacyRawSets = savedSets;
            sets = isValidSetList(savedSets, maxWorkoutSets, true) ? savedSets : [];
        } else {
            legacyRawSets = null;
            sets = [];
        }
        if (sets.size() > 0) {
            resumedWorkoutIntervalsInvalid = true;
        }
        var savedWorkoutStartedAt = legacyUnboundState ?
            Storage.getValue("activeWorkoutStartedAtSeconds") : null;
        activeWorkoutStartedAtSeconds = sets.size() > 0 &&
            isValidWorkoutStartedAtSeconds(savedWorkoutStartedAt) ? savedWorkoutStartedAt : null;
        var savedPlan = Storage.getValue("plan");
        legacyRawPlan = legacyUnboundState ? savedPlan : null;
        plan = restoredPlan(savedPlan);
        var savedPending = Storage.getValue("pending");
        legacyRawPending = legacyUnboundState ? savedPending : null;
        if (isValidPendingList(savedPending)) {
            pending = savedPending;
            pendingEstimateSource = null;
        } else if (legacyUnboundState && isValidLegacyPendingList(savedPending)) {
            pending = normalizedLegacyPendingList(savedPending);
            pendingEstimateSource = null;
        } else {
            pending = [];
            pendingEstimateSource = null;
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
        var savedPreparedWorkout = Storage.getValue("preparedWorkoutV1");
        restoreLastWorkoutSync(Storage.getValue("lastWorkoutSyncV1"));
        var savedDeferredSync = Storage.getValue("deferredSync");
        deferredSync = savedDeferredSync instanceof Lang.Dictionary ? savedDeferredSync : null;
        var savedProcessedSyncIds = Storage.getValue("processedSyncIds");
        processedSyncIds = isValidProcessedSyncIds(savedProcessedSyncIds) ? savedProcessedSyncIds : [];
        var savedActiveWorkout = Storage.getValue("activeWorkoutV1");
        if (!savedExerciseCatalogValid && savedActiveWorkout instanceof Lang.Array &&
            savedActiveWorkout.size() > 0 && (savedActiveWorkout[0] == 4 || savedActiveWorkout[0] == 6)) {
            try {
                Storage.deleteValue("activeWorkoutV1");
                savedActiveWorkout = null;
            } catch (e) {
                exerciseCatalogRepairRequired = true;
            }
        }
        if (!legacyUnboundState) {
            restoreLegacySetMirrorIfSnapshotAbsent(savedActiveWorkout);
        }
        var phoneFence = Storage.getValue("phoneSyncFence");
        if (phoneFence instanceof Lang.Dictionary && isValidPhoneSyncFence(phoneFence)) {
            lastPhoneSyncRevision = phoneFence.get("revision").toLong();
            lastPhoneSyncId = phoneFence.get("id");
            lastPhoneSyncAccountBinding = phoneFence.get("accountBinding");
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
            lastCloudPlanId = cloudFence.get("id");
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
        GymPendingJournal.load();
        var previousPairingGeneration = pairingGeneration;
        var pairingRecoveryTarget = scopedStateValid ? stagedPairingRecoveryTarget() : null;
        var activeAlreadyTargetsRecovery = false;
        var preparedAlreadyTargetsRecovery = false;
        var savedRuntimeForPairingRecovery = Storage.getValue("activeRuntimeV1");
        var savedActiveHasSets = storedActiveSnapshotHasSets(savedActiveWorkout);
        if (pairingRecoveryTarget != null) {
            pairingGeneration = pairingRecoveryTarget;
            if (savedActiveWorkout != null &&
                isValidActiveWorkoutSnapshot(savedActiveWorkout)) {
                if ((savedActiveWorkout[0] != 4 && savedActiveWorkout[0] != 6) || savedExerciseCatalogValid) {
                    activeAlreadyTargetsRecovery =
                        activeWorkoutSnapshotMatchesBindings(savedActiveWorkout);
                }
            }
            if (savedPreparedWorkout != null &&
                isValidPreparedWorkout(savedPreparedWorkout)) {
                preparedAlreadyTargetsRecovery =
                    activeWorkoutSnapshotMatchesBindings(savedPreparedWorkout);
            }
            pairingGeneration = previousPairingGeneration;
        }
        var pairingRecoveryDeferred = false;
        if (pairingRecoveryTarget != null) {
            if ((savedActiveHasSets || savedRuntimeForPairingRecovery != null) &&
                !activeAlreadyTargetsRecovery) {
                pairingRecoveryDeferred = true;
            } else if (!savedActiveHasSets && savedRuntimeForPairingRecovery == null &&
                savedPreparedWorkout != null && !preparedAlreadyTargetsRecovery) {
                pairingRecoveryDeferred = true;
            }
        }
        if (pairingRecoveryDeferred) {
            // A released build may have left an exact phone stage immediately before
            // any target-generation envelope was committed. Keep the old-bound active
            // state and the exact stage intact; the phone retries after the workout is
            // durably queued or discarded. If the active envelope already targets the
            // stage, finish that interrupted commit below instead of discarding it.
            pairingRecoveryTarget = null;
        }
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
        if (recoveredPairing && savedPreparedWorkout != null &&
            !preparedAlreadyTargetsRecovery) {
            pairingGeneration = previousPairingGeneration;
            var preparedMatchesPrevious = isValidPreparedWorkout(savedPreparedWorkout) &&
                activeWorkoutSnapshotMatchesBindings(savedPreparedWorkout);
            pairingGeneration = pairingRecoveryTarget;
            if (preparedMatchesPrevious) {
                savedPreparedWorkout[3] = pairingRecoveryTarget;
            }
        }
        if (pairingRecoveryDeferred && preparedAlreadyTargetsRecovery) {
            // This is a known target-bound half-write. Keep it dormant and durable
            // beside the exact stage while the old-bound workout finishes.
            preparedWorkout = savedPreparedWorkout;
        } else {
            restorePreparedWorkout(savedPreparedWorkout);
        }
        parkPendingForSnapshot(savedActiveWorkout);
        if (savedActiveWorkout != null) {
            var validActiveSnapshot = scopedStateValid &&
                isValidActiveWorkoutSnapshot(savedActiveWorkout) &&
                ((savedActiveWorkout[0] != 4 && savedActiveWorkout[0] != 6) || savedExerciseCatalogValid);
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
        var currentEntryRestored = restoreCurrentEntry(savedCurrentEntry);
        if (!currentEntryRestored && sets.size() > 0) {
            selectExerciseByName(
                setField(GymSetAccess.at(sets, sets.size() - 1), "exerciseName").toString());
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
                status = GymStatus.LEGACY_SAFE;
            } else {
                // Do not allow a later save to overwrite the original HEAD values.
                status = GymStatus.LEGACY_FULL;
            }
        } else if (!scopedStateValid) {
            clearAccountScopedState();
        } else {
            pruneAccountScopedState();
            recoverQueuedWorkout();
            parkPendingDuringLongWorkout(sets.size());
            if (hasPreparedWorkout()) {
                status = preparedWorkoutFitSaved() ? GymStatus.FIT_SAVED : GymStatus.FIT_CHECK;
            }
            if (recoveredPairing) {
                pairingRecoveryCommitLast = true;
                var recoverySaved = save();
                pairingRecoveryCommitLast = false;
                if (!recoverySaved) {
                    // Generation was the failed transaction's final Storage write,
                    // so a false result still means the previous generation is the
                    // durable authority and the exact stage remains retryable.
                    pairingGeneration = previousPairingGeneration;
                    for (var i = 0; i < pending.size(); i += 1) {
                        pendingEstimateSource = null;
                        pending[i].put("pairingGeneration", previousPairingGeneration);
                    }
                    if (preparedWorkout != null) {
                        preparedWorkout[3] = previousPairingGeneration;
                    }
                    status = GymStatus.SAVE_FAIL;
                }
            }
        }
        GymWorkoutMode.restore();
        if (GymWorkoutMode.isPlanned() && !currentEntryRestored) {
            if (sets.size() > 0 && selectExerciseByName(
                    setField(GymSetAccess.at(sets, sets.size() - 1), "exerciseName").toString())) {
                applyCurrentPlanSet();
            } else {
                selectNextPlanSlotInGlobalOrder();
            }
        }
    }

    (:fullLegacyState)
    static function save() {
        if (!GymPendingJournal.readable) { return false; }
        try {
            if (activeWorkoutStartedAtSeconds != null &&
                (!hasAccountBinding() || sets.size() == 0 ||
                    !isValidWorkoutStartedAtSeconds(activeWorkoutStartedAtSeconds))) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            // Every set mutation commits activeWorkoutV1 before publishing the
            // new in-memory list. This compatibility/configuration save must not
            // rebuild the same complete snapshot a second time.
            if (legacyUnboundState && !ensureLegacyQuarantine()) {
                status = GymStatus.LEGACY_FULL;
                return false;
            }
            if (!isWithinStorageBudget()) {
                status = GymStatus.STORE_FULL;
                return false;
            }
            var storedPlanValue = storedPlan();
            if (storedPlanValue == null) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            if (!ensureDurableExerciseCatalog()) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            if (legacyUnboundState && !refreshLegacyCurrentQuarantine()) {
                // Commit the complete current legacy state as one Object Store value before
                // overwriting any compatibility keys. A crash or StorageFullException during
                // the multi-key writes below therefore cannot leave the latest edits torn.
                status = GymStatus.LEGACY_FULL;
                return false;
            }
            // Couple the selected exercise to the active set count in one value.
            // If a crash commits a new active snapshot first, a stale selection is
            // rejected on load instead of silently switching the next set.
            Storage.setValue("currentEntryV1", [
                sets.size(), currentExercise(), weight, reps
            ]);
            // A valid snapshot is authoritative. Keeping a second per-key copy
            // of every completed set would duplicate the long-name graph and can
            // exhaust Object Store or transient heap on constrained watches.
            if (activeWorkoutSnapshotValid && hasAccountBinding()) {
                // The owner-bound atomic snapshot is the only current source of
                // truth. Empty downgrade keys avoid retaining a second 60-set
                // name graph beside it.
                Storage.setValue("activeWorkoutStartedAtSeconds", null);
                Storage.setValue("sets", []);
            } else if (sets.size() > 0) {
                Storage.setValue("activeWorkoutStartedAtSeconds", activeWorkoutStartedAtSeconds);
                Storage.setValue("sets", sets);
            } else {
                Storage.setValue("sets", sets);
                Storage.setValue("activeWorkoutStartedAtSeconds", activeWorkoutStartedAtSeconds);
            }
            Storage.setValue("plan", storedPlanValue);
            if (parkedPending == null) { Storage.setValue("pending", pending); }
            if (!GymPendingJournal.save()) { status = GymStatus.SAVE_FAIL; return false; }
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
            // Ordinary account/reset transitions publish their generation before
            // the owner marker, which remains the final commit point. Startup
            // same-owner pairing recovery reverses only those two commit writes.
            if (!pairingRecoveryCommitLast) {
                Storage.setValue("pairingGeneration", pairingGeneration);
            }
            if (!legacyUnboundState) {
                Storage.deleteValue("legacyUnboundState");
            }
            if (isValidAccountBinding(accountBinding)) {
                Storage.setValue("stateOwnerBinding", accountBinding);
                stateOwnerBinding = accountBinding;
            } else {
                Storage.deleteValue("stateOwnerBinding");
                stateOwnerBinding = null;
            }
            if (pairingRecoveryCommitLast) {
                // All same-owner generation-bound envelopes and the unchanged
                // owner marker are durable. A false save result therefore still
                // means this target generation was not published.
                Storage.setValue("pairingGeneration", pairingGeneration);
            }
            return true;
        } catch (e) {
            status = GymStatus.SAVE_FAIL;
            return false;
        }
    }

    // The manual 96 KiB profile reads only the current owner-bound plan and
    // active journal metadata needed for pairing and prepared-workout recovery.
    // Ordinary in-progress workouts are not restored after an app restart.
    (:compactCheckpoint96)
    static function beginLoad() {
        parkedPending = null;
        pairingRecoveryCommitLast = false;
        clearTransientSetActions();
        lastLoggedSetEndSeconds = 0;
        resumedWorkoutIntervalsInvalid = false;
        resetActiveWorkoutSnapshotState();
        resetRuntimeCheckpointState();
        GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
        preparedWorkout = null;
        tutorialHistory = [];
        lastWorkoutSyncAtSeconds = null;
        exerciseCatalogRepairRequired = false;
        restDurationMs = 0;
        restStartedAt = null;

        // Drop prior-process graphs before reading the durable full queue. The
        // current V5 plan and v6 journal are restored later in bounded stages.
        exercises = []; sets = []; plan = []; pending = [];
        pendingEstimateSource = null;
        GymPendingJournal.reset();
        persistedPlanSource = plan;
        persistedPlanBytes = 0;
        persistedPlanNeedsV5Write = false;

        var savedAccount = Storage.getValue("accountBinding");
        var savedOwner = Storage.getValue("stateOwnerBinding");
        accountBinding = isValidAccountBinding(savedAccount) ? savedAccount.toString() : null;
        stateOwnerBinding = isValidAccountBinding(savedOwner) ? savedOwner.toString() : null;
        var ownerMatches = accountBinding != null && stateOwnerBinding != null &&
            accountBinding.equals(stateOwnerBinding);
        var accountMarkersConflict = accountBinding != null && stateOwnerBinding != null &&
            !accountBinding.equals(stateOwnerBinding);
        if (ownerMatches) {
            stateOwnerBinding = accountBinding;
            validatedBindingA = accountBinding;
        }
        savedAccount = null;
        savedOwner = null;
        var schema = Storage.getValue("storageSchemaVersion");
        // This profile never adopts values without a complete owner/device bind.
        // Conflicting valid account markers still enter the privacy fence below.
        legacyUnboundState = false;

        var value = Storage.getValue("deviceBinding");
        deviceBinding = isBoundedText(value, maxBindingLength) ? value.toString() : null;
        ownerMatches = ownerMatches && deviceBinding != null;
        value = Storage.getValue("pairingGeneration");
        pairingGeneration = isValidAccountBinding(value) ? value.toString() : null;
        value = Storage.getValue("cloudDeviceBinding");
        cloudDeviceBinding = isBoundedText(value, maxBindingLength) ? value.toString() : null;

        // Lite watches hold no plan. Stale plan state is removed once without
        // being read; the catalog is the fixed built-in list unless a queued or
        // active workout still addresses a stored catalog by index.
        plan = [];
        persistedPlanSource = plan;
        persistedPlanBytes = 0;
        persistedPlanNeedsV5Write = false;
        var savedExerciseCatalogValid = true;
        exerciseCatalogNeedsWrite = false;
        if (purgePlanState96()) {
            exercises = builtInExercises();
        } else {
            value = ownerMatches ? Storage.getValue("exercises") : null;
            savedExerciseCatalogValid =
                isValidExerciseList(value, maxPlanSets) && value.size() > 0;
            exerciseCatalogNeedsWrite = !savedExerciseCatalogValid;
            exercises = savedExerciseCatalogValid ? value : builtInExercises();
            value = null;
        }

        var phoneFence = Storage.getValue("phoneSyncFence");
        if (phoneFence instanceof Lang.Dictionary && isValidPhoneSyncFence(phoneFence)) {
            lastPhoneSyncRevision = phoneFence.get("revision").toLong();
            lastPhoneSyncId = phoneFence.get("id");
            lastPhoneSyncAccountBinding = phoneFence.get("accountBinding");
        } else {
            lastPhoneSyncRevision = 0l;
            lastPhoneSyncId = null;
            lastPhoneSyncAccountBinding = null;
        }
        phoneFence = null;
        lastCloudPlanRevision = 0;
        lastCloudPlanId = null;
        stagedPhoneSyncRevision = 0l;
        stagedPhoneSyncId = null;
        stagedPhoneAccountBinding = null;
        stagedPhoneSyncMessage = null;
        if (ownerMatches) { loadSyncStage("phone"); }

        // Keep the existing full-message queue and journal. Park the validated
        // owner-bound list before the journal is decoded to reduce peak heap.
        value = ownerMatches ? Storage.getValue("pending") : null;
        pending = ownerMatches && isValidPendingList(value) ? value : [];
        value = null;
        if (ownerMatches && stagedPairingRecoveryTarget() == null) {
            parkPendingDuringLongWorkout(0);
        }
        sets = [];
        activeWorkoutStartedAtSeconds = null;

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
        if (value != null) {
            language = normalizedLanguage(value.toString());
        } else {
            var systemLanguage = System.getDeviceSettings().systemLanguage;
            language = systemLanguage == System.LANGUAGE_UKR ? "uk" :
                (systemLanguage == System.LANGUAGE_RUS ? "ru" : "en");
        }

        if (ownerMatches) {
            restoreTutorialHistory(Storage.getValue("tutorialHistoryV1"));
            restoreLastWorkoutSync(Storage.getValue("lastWorkoutSyncV1"));
            value = Storage.getValue("deferredSync");
            deferredSync = value instanceof Lang.Dictionary &&
                sourceForMessage(value).equals("phone") ? value : null;
            if (value != null && deferredSync == null) {
                try {
                    Storage.deleteValue("deferredSync");
                } catch (e) {
                    // Unsupported cloud work remains ignored and cleanup retries.
                }
            }
            value = Storage.getValue("processedSyncIds");
            processedSyncIds = isValidProcessedSyncIds(value) ? value : [];
        } else {
            lastWorkoutSyncAtSeconds = null;
            deferredSync = null;
            processedSyncIds = [];
        }

        // Compact products accept phone-bound plans only. Do not materialize a
        // possibly large full-profile cloud stage on their smaller heap.
        stagedCloudPlanRevision = 0;
        stagedCloudPlanId = null;
        stagedCloudAccountBinding = null;
        stagedCloudSyncMessage = null;
        var savedActive = ownerMatches ? Storage.getValue("activeWorkoutV1") : null;
        if (savedActive instanceof Lang.Array && savedActive.size() > 0 &&
            savedActive[0] == 6 && !savedExerciseCatalogValid) {
            // V6 rows use catalog indexes. Keep the durable header and rows
            // untouched, but fence catalog writes while they cannot be safely
            // interpreted. Pairing recovery still uses only the bounded header.
            exerciseCatalogRepairRequired = true;
        }
        if (!(savedActive instanceof Lang.Array) || savedActive.size() != 10 ||
            savedActive[0] != 6) {
            // Older or malformed snapshots remain inert in storage and are not
            // kept alive beside the current pending and catalog graphs.
            savedActive = null;
        }
        var savedPreparedWorkout = ownerMatches ? Storage.getValue("preparedWorkoutV1") : null;
        return [schema, ownerMatches, savedExerciseCatalogValid, null, savedActive,
            savedPreparedWorkout, persistedPlanBytes];
    }

    // Returns true once the plan/catalog/legacy-plan keys are gone (marker set).
    // The keys are deleted blind. Nothing is deleted while an active or prepared
    // workout row or a queued journal entry exists: those address exercises by
    // catalog index, so the purge waits for a later start with an idle store.
    (:compactCheckpoint96)
    private static function purgePlanState96() {
        try {
            if (Storage.getValue("lite96PurgedV1") != null) { return true; }
            var journal = Storage.getValue("pendingJournalV1");
            if (storedActiveSnapshotHasSets(Storage.getValue("activeWorkoutV1")) ||
                Storage.getValue("preparedWorkoutV1") != null ||
                (journal instanceof Lang.Array && journal.size() > 1 &&
                    journal[journal.size() - 1] instanceof Lang.Array &&
                    journal[journal.size() - 1].size() > 0)) {
                return false;
            }
            Storage.deleteValue("plan");
            Storage.deleteValue("exercises");
            Storage.deleteValue("deferredSync");
            Storage.deleteValue("legacyQuarantinePlan");
            Storage.deleteValue("legacyQuarantineExercises");
            Storage.setValue("lite96PurgedV1", 1);
            return true;
        } catch (e) {
            return false;
        }
    }

    // One-time cold-start cleanup for 128 KiB watches: a plan or catalog stored
    // before the tier limits existed is removed so every stored copy fits again.
    // The phone resends it through the normal sync. Queued workouts are kept
    // untouched: their rows pin their own exercise names in separate keys. The
    // purge still waits for an idle store (no active workout rows, no prepared
    // workout) because those address exercises by catalog index.
    (:mem128)
    private static function purgeOversizedPlanState128() {
        try {
            if (Storage.getValue("mem128SizedV1") != null) { return; }
            if (storedActiveSnapshotHasSets(Storage.getValue("activeWorkoutV1")) ||
                Storage.getValue("preparedWorkoutV1") != null) {
                return;
            }
            Storage.deleteValue("plan");
            Storage.deleteValue("exercises");
            Storage.deleteValue("deferredSync");
            Storage.deleteValue("legacyQuarantinePlan");
            Storage.deleteValue("legacyQuarantineExercises");
            Storage.setValue("mem128SizedV1", 1);
        } catch (e) {
        }
    }

    (:compactLegacyState, :richWorkoutMode)
    static function beginLoad() {
        parkedPending = null;
        pairingRecoveryCommitLast = false;
        clearTransientSetActions();
        resetActiveWorkoutSnapshotState();
        resetRuntimeCheckpointState();
        preparedWorkout = null;
        tutorialHistory = [];
        lastWorkoutSyncAtSeconds = null;
        exerciseCatalogRepairRequired = false;

        // Release constructor/previous-load graphs before decoding the legacy
        // queue. Its atomic value can need more transient space than live rows.
        exercises = []; sets = []; plan = []; pending = [];
        pendingEstimateSource = null;
        GymPendingJournal.reset();
        persistedPlanSource = plan;
        persistedPlanBytes = 0;
        persistedPlanNeedsV5Write = false;
        var value = null;
        // Compact beginLoad exists only on 128 KiB builds; run before any
        // plan, catalog or deferred-sync read.
        purgeOversizedPlanState128();

        var savedAccount = Storage.getValue("accountBinding");
        var savedOwner = Storage.getValue("stateOwnerBinding");
        accountBinding = isValidAccountBinding(savedAccount) ? savedAccount.toString() : null;
        stateOwnerBinding = isValidAccountBinding(savedOwner) ? savedOwner.toString() : null;
        var ownerMatches = accountBinding != null && stateOwnerBinding != null &&
            accountBinding.equals(stateOwnerBinding);
        if (ownerMatches) {
            stateOwnerBinding = accountBinding;
            validatedBindingA = accountBinding;
        }
        savedAccount = null;
        savedOwner = null;
        var schema = Storage.getValue("storageSchemaVersion");
        var legacyUpgrade = schema == null && accountBinding != null && stateOwnerBinding == null;
        var legacyMarker = Storage.getValue("legacyUnboundState");
        legacyUnboundState = accountBinding == null &&
            ((legacyMarker instanceof Lang.Boolean && legacyMarker) || schema == null);

        value = Storage.getValue("deviceBinding");
        deviceBinding = isBoundedText(value, maxBindingLength) ? value.toString() : null;
        value = Storage.getValue("pairingGeneration");
        pairingGeneration = isValidAccountBinding(value) ? value.toString() : null;
        value = Storage.getValue("cloudDeviceBinding");
        cloudDeviceBinding = isBoundedText(value, maxBindingLength) ? value.toString() : null;

        var savedExerciseCatalogValid = false;
        if (ownerMatches && !legacyUnboundState && !legacyUpgrade) {
            loadLegacyStoredPlan();
        } else if (legacyUnboundState || legacyUpgrade) {
            // Keep unowned rows on the original quarantine path until owner
            // binding is durable. In particular, do not replace their raw
            // dictionaries with a V5 descriptor during bootstrap.
            var rawLegacyPlan = null;
            var rawPlanReadable = true;
            try {
                rawLegacyPlan = Storage.getValue("plan");
            } catch (e) {
                rawPlanReadable = false;
                status = GymStatus.RECOVERY_FAIL;
            }
            plan = rawPlanReadable && isValidSetList(rawLegacyPlan, maxPlanSets, true) ?
                rawLegacyPlan : [];
            persistedPlanSource = plan;
            persistedPlanBytes = rawPlanReadable && rawLegacyPlan != null ?
                estimatedValueBytes(rawLegacyPlan) : 0;
            persistedPlanNeedsV5Write = false;
            rawLegacyPlan = null;
        } else {
            plan = [];
            persistedPlanSource = plan;
            persistedPlanBytes = 0;
        }

        // Plan v5 and the dictionary fallback are self-describing; defer the
        // exercise catalog graph until after their largest decode allocation.
        value = Storage.getValue("exercises");
        savedExerciseCatalogValid =
            isValidExerciseList(value, maxPlanSets) && value.size() > 0;
        exerciseCatalogNeedsWrite = !savedExerciseCatalogValid;
        exercises = savedExerciseCatalogValid ? value : builtInExercises();
        value = null;

        var phoneFence = Storage.getValue("phoneSyncFence");
        if (phoneFence instanceof Lang.Dictionary && isValidPhoneSyncFence(phoneFence)) {
            lastPhoneSyncRevision = phoneFence.get("revision").toLong();
            lastPhoneSyncId = phoneFence.get("id");
            lastPhoneSyncAccountBinding = phoneFence.get("accountBinding");
        } else {
            lastPhoneSyncRevision = 0l;
            lastPhoneSyncId = null;
            lastPhoneSyncAccountBinding = null;
        }
        phoneFence = null;
        lastCloudPlanRevision = 0;
        lastCloudPlanId = null;
        loadSyncStage("phone");
        // Decode the old atomic queue before allocating the catalog and plan.
        // FR55 only needs its identities while idle or recording; keep the
        // validated messages durable on disk until a send or ACK needs them.
        value = Storage.getValue("pending");
        pending = isValidPendingList(value) ? value : [];
        legacyPendingUnarchived = legacyUnboundState &&
            value instanceof Lang.Array && value.size() > 0;
        value = null;
        // Fully bound legacy messages can stay on disk while the indexed queue
        // is decoded. Pairing recovery retains its complete mutation graph.
        if (ownerMatches && stagedPairingRecoveryTarget() == null) {
            if (GymWorkoutMode.recordingSetLimit == 30) {
                parkPendingDuringLongWorkout(0);
            } else {
                parkPendingForSnapshot(Storage.getValue("activeWorkoutV1"));
            }
        }
        if (legacyUnboundState) {
            value = Storage.getValue("sets");
            sets = isValidSetList(value, maxWorkoutSets, true) ? value : [];
            resumedWorkoutIntervalsInvalid = sets.size() > 0;
            value = Storage.getValue("activeWorkoutStartedAtSeconds");
            activeWorkoutStartedAtSeconds = sets.size() > 0 &&
                isValidWorkoutStartedAtSeconds(value) ? value : null;
        } else {
            sets = [];
            activeWorkoutStartedAtSeconds = null;
            resumedWorkoutIntervalsInvalid = false;
        }

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
        if (value != null) {
            language = normalizedLanguage(value.toString());
        } else {
            var systemLanguage = System.getDeviceSettings().systemLanguage;
            language = systemLanguage == System.LANGUAGE_UKR ? "uk" :
                (systemLanguage == System.LANGUAGE_RUS ? "ru" : "en");
        }

        restoreTutorialHistory(Storage.getValue("tutorialHistoryV1"));
        var savedPreparedWorkout = Storage.getValue("preparedWorkoutV1");
        restoreLastWorkoutSync(Storage.getValue("lastWorkoutSyncV1"));
        value = Storage.getValue("deferredSync");
        deferredSync = value instanceof Lang.Dictionary &&
            sourceForMessage(value).equals("phone") ? value : null;
        if (value != null && deferredSync == null) {
            try {
                Storage.deleteValue("deferredSync");
            } catch (e) {
                // Unsupported cloud work remains ignored and cleanup retries.
            }
        }
        value = Storage.getValue("processedSyncIds");
        processedSyncIds = isValidProcessedSyncIds(value) ? value : [];

        // Compact products accept phone-bound plans only. Do not materialize a
        // possibly large full-profile cloud stage on their smaller heap.
        stagedCloudPlanRevision = 0;
        stagedCloudPlanId = null;
        stagedCloudAccountBinding = null;
        stagedCloudSyncMessage = null;
        try {
            Storage.deleteValue("cloudSyncStage");
            Storage.deleteValue("cloudSyncFence");
            Storage.deleteValue("lastCloudPlanRevision");
            Storage.deleteValue("lastCloudPlanId");
        } catch (e) {
            // It stays unsupported and is never loaded; cleanup retries later.
        }

        var savedCurrentEntry = Storage.getValue("currentEntryV1");
        if (legacyUpgrade) {
            ownerMatches = adoptLegacyStateOwner();
        }
        var savedActive = Storage.getValue("activeWorkoutV1");
        if (!savedExerciseCatalogValid && savedActive instanceof Lang.Array &&
            savedActive.size() > 0 && (savedActive[0] == 4 || savedActive[0] == 6)) {
            try {
                Storage.deleteValue("activeWorkoutV1");
                savedActive = null;
            } catch (e) {
                exerciseCatalogRepairRequired = true;
            }
        }
        if (!legacyUnboundState) {
            restoreLegacySetMirrorIfSnapshotAbsent(savedActive);
        }
        return [schema, ownerMatches, savedExerciseCatalogValid, savedCurrentEntry,
            savedActive, savedPreparedWorkout];
    }

    (:compactLegacyState, :richWorkoutMode)
    static function load() {
        var startup = beginLoad();
        GymPendingJournal.load();
        completeLoad(startup);
    }

    (:compactCheckpoint96)
    static function load() {
        var startup = beginLoad();
        if (hasAccountBinding()) { GymPendingJournal.load(); }
        completeLoad(startup);
    }

    (:compactLegacyState, :richWorkoutMode)
    static function completeLoad(startup) {
        var schema = startup[0];
        var ownerMatches = startup[1];
        var savedExerciseCatalogValid = startup[2];
        var savedCurrentEntry = startup[3];
        var savedActive = startup[4];
        var savedPreparedWorkout = startup[5];
        var previousPairingGeneration = pairingGeneration;
        var pairingRecoveryTarget = ownerMatches ? stagedPairingRecoveryTarget() : null;
        var activeAlreadyTargetsRecovery = false;
        var preparedAlreadyTargetsRecovery = false;
        var savedRuntimeForPairingRecovery = Storage.getValue("activeRuntimeV1");
        var savedActiveHasSets = storedActiveSnapshotHasSets(savedActive);
        if (pairingRecoveryTarget != null) {
            pairingGeneration = pairingRecoveryTarget;
            if (savedActive != null && isValidActiveWorkoutSnapshot(savedActive)) {
                if ((savedActive[0] != 4 && savedActive[0] != 6) || savedExerciseCatalogValid) {
                    activeAlreadyTargetsRecovery =
                        activeWorkoutSnapshotMatchesBindings(savedActive);
                }
            }
            if (!activeAlreadyTargetsRecovery && savedActive != null) {
                // Five products previously ran the full profile. Its released save
                // could commit a target-generation full-v3 snapshot immediately
                // before the global generation. Validate that exact bridge shape
                // under the staged target so the upgrade restores it immediately.
                activeAlreadyTargetsRecovery =
                    compactActiveSnapshotFromFullV3(savedActive) != null;
            }
            if (savedPreparedWorkout != null &&
                isValidPreparedWorkout(savedPreparedWorkout)) {
                preparedAlreadyTargetsRecovery =
                    activeWorkoutSnapshotMatchesBindings(savedPreparedWorkout);
            }
            pairingGeneration = previousPairingGeneration;
        }
        var pairingRecoveryDeferred = false;
        if (pairingRecoveryTarget != null) {
            if ((savedActiveHasSets || savedRuntimeForPairingRecovery != null) &&
                !activeAlreadyTargetsRecovery) {
                pairingRecoveryDeferred = true;
            } else if (!savedActiveHasSets && savedRuntimeForPairingRecovery == null &&
                savedPreparedWorkout != null && !preparedAlreadyTargetsRecovery) {
                pairingRecoveryDeferred = true;
            }
        }
        if (pairingRecoveryDeferred) {
            pairingRecoveryTarget = null;
        }
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
        if (recoveredPairing && savedPreparedWorkout != null &&
            !preparedAlreadyTargetsRecovery) {
            pairingGeneration = previousPairingGeneration;
            var preparedMatchesPrevious = isValidPreparedWorkout(savedPreparedWorkout) &&
                activeWorkoutSnapshotMatchesBindings(savedPreparedWorkout);
            pairingGeneration = pairingRecoveryTarget;
            if (preparedMatchesPrevious) {
                savedPreparedWorkout[3] = pairingRecoveryTarget;
            }
        }
        if (pairingRecoveryDeferred && preparedAlreadyTargetsRecovery) {
            preparedWorkout = savedPreparedWorkout;
        } else {
            restorePreparedWorkout(savedPreparedWorkout);
        }
        parkPendingForSnapshot(savedActive);
        var restoredActive = false;
        if (ownerMatches && isValidActiveWorkoutSnapshot(savedActive) &&
            ((savedActive[0] != 4 && savedActive[0] != 6) || savedExerciseCatalogValid) &&
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
        } else if (recoveredPairing && ownerMatches &&
            isValidActiveWorkoutSnapshot(savedActive) &&
            ((savedActive[0] != 4 && savedActive[0] != 6) || savedExerciseCatalogValid)) {
            pairingGeneration = previousPairingGeneration;
            var activeMatchesPrevious =
                activeWorkoutSnapshotMatchesBindings(savedActive);
            pairingGeneration = pairingRecoveryTarget;
            if (activeMatchesPrevious) {
                // Only an empty old tombstone can reach this path; any old-bound
                // unfinished snapshot deferred the stage above.
                restoreActiveWorkoutSnapshot(savedActive);
                restoredActive = true;
            }
        } else if (ownerMatches && restoreMigratedActiveWorkout(savedActive)) {
            restoredActive = true;
        }
        if (!restoredActive && savedActive != null) {
            sets = [];
            activeWorkoutStartedAtSeconds = null;
        }
        var fullLegacyMigrated = legacyUnboundState &&
            migrateFullLegacyQuarantineToCompact();
        exerciseIndex = 0;
        var currentEntryRestored = !fullLegacyMigrated &&
            restoreCurrentEntry(savedCurrentEntry);
        if (!currentEntryRestored && sets.size() > 0) {
            selectExerciseByName(
                setField(GymSetAccess.at(sets, sets.size() - 1), "exerciseName").toString());
        }
        if (legacyUnboundState) {
            if (!fullLegacyMigrated) {
                restoreLegacyCurrentQuarantine(schema == null);
            }
            discardLegacyUnboundActiveWorkout();
            status = GymStatus.LEGACY_SAFE;
        } else if (!ownerMatches) {
            clearAccountScopedState();
        } else {
            pruneAccountScopedState();
            recoverQueuedWorkout();
            parkPendingDuringLongWorkout(sets.size());
            if (hasPreparedWorkout()) {
                status = preparedWorkoutFitSaved() ? GymStatus.FIT_SAVED : GymStatus.FIT_CHECK;
            }
            if (recoveredPairing) {
                pairingRecoveryCommitLast = true;
                var recoverySaved = save();
                pairingRecoveryCommitLast = false;
                if (!recoverySaved) {
                    pairingGeneration = previousPairingGeneration;
                    for (var i = 0; i < pending.size(); i += 1) {
                        pendingEstimateSource = null;
                        pending[i].put("pairingGeneration", previousPairingGeneration);
                    }
                    if (preparedWorkout != null) {
                        preparedWorkout[3] = previousPairingGeneration;
                    }
                    status = GymStatus.SAVE_FAIL;
                }
            }
        }
        GymWorkoutMode.restore();
        if (GymWorkoutMode.isPlanned() && !currentEntryRestored) {
            if (sets.size() > 0 && selectExerciseByName(
                    setField(GymSetAccess.at(sets, sets.size() - 1), "exerciseName").toString())) {
                applyCurrentPlanSet();
            } else {
                selectNextPlanSlotInGlobalOrder();
            }
        }
    }

    // The 96 KiB loader restores only owner-bound V5 plans and active snapshots
    // required to finish a validated prepared workout. Legacy ownerless
    // adoption, dictionary-plan migration, and older snapshot bridges stay out.
    (:compactCheckpoint96)
    static function completeLoad(startup) {
        var ownerMatches = startup[1];
        var savedExerciseCatalogValid = startup[2];
        var savedActive = startup[4];
        var savedPreparedWorkout = startup[5];
        var preservedPlanBytes = startup[6];
        var accountMarkersConflict = isValidAccountBinding(accountBinding) &&
            isValidAccountBinding(stateOwnerBinding) &&
            !accountBinding.equals(stateOwnerBinding);
        if (!ownerMatches) {
            if (accountMarkersConflict) {
                // Retain the established account-mismatch privacy fence.
                clearAccountScopedState();
            } else {
                discardUnownedMemory96(preservedPlanBytes);
            }
            GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
            return;
        }

        var previousPairingGeneration = pairingGeneration;
        var pairingRecoveryTarget = ownerMatches ? stagedPairingRecoveryTarget() : null;
        var activeAlreadyTargetsRecovery = false;
        var preparedAlreadyTargetsRecovery = false;
        var savedActiveHasSets = storedActiveSnapshotHasSets(savedActive);

        if (pairingRecoveryTarget != null) {
            pairingGeneration = pairingRecoveryTarget;
            if (savedActive != null && savedExerciseCatalogValid &&
                isValidActiveWorkoutSnapshot(savedActive)) {
                activeAlreadyTargetsRecovery =
                    activeWorkoutSnapshotMatchesBindings(savedActive);
            }
            if (savedPreparedWorkout != null &&
                isValidPreparedWorkout(savedPreparedWorkout)) {
                preparedAlreadyTargetsRecovery =
                    activeWorkoutSnapshotMatchesBindings(savedPreparedWorkout);
            }
            pairingGeneration = previousPairingGeneration;
        }

        var pairingRecoveryDeferred = pairingRecoveryTarget != null &&
            ((savedActiveHasSets && !activeAlreadyTargetsRecovery) ||
                (!savedActiveHasSets && savedPreparedWorkout != null &&
                    !preparedAlreadyTargetsRecovery));
        if (pairingRecoveryDeferred) { pairingRecoveryTarget = null; }

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
        if (recoveredPairing && savedPreparedWorkout != null &&
            !preparedAlreadyTargetsRecovery) {
            pairingGeneration = previousPairingGeneration;
            var preparedMatchesPrevious = isValidPreparedWorkout(savedPreparedWorkout) &&
                activeWorkoutSnapshotMatchesBindings(savedPreparedWorkout);
            pairingGeneration = pairingRecoveryTarget;
            if (preparedMatchesPrevious) {
                savedPreparedWorkout[3] = pairingRecoveryTarget;
            }
        }
        if (pairingRecoveryDeferred && preparedAlreadyTargetsRecovery) {
            preparedWorkout = savedPreparedWorkout;
        } else {
            restorePreparedWorkout(savedPreparedWorkout);
        }

        var restoredActive = false;
        if (preparedWorkout != null && ownerMatches && savedExerciseCatalogValid &&
            isValidActiveWorkoutSnapshot(savedActive) &&
            activeWorkoutSnapshotMatchesBindings(savedActive)) {
            // Prepared markers contain only the transaction id and phase. The
            // matching owner-bound journal is needed to finish an interrupted
            // phase-0/phase-1 queue or FIT transaction after restart.
            restoreActiveWorkoutSnapshot(savedActive);
            restoredActive = true;
        } else if (preparedWorkout != null && recoveredPairing && ownerMatches &&
            savedExerciseCatalogValid && isValidActiveWorkoutSnapshot(savedActive)) {
            pairingGeneration = previousPairingGeneration;
            var activeMatchesPrevious =
                activeWorkoutSnapshotMatchesBindings(savedActive);
            pairingGeneration = pairingRecoveryTarget;
            if (activeMatchesPrevious) {
                // Only an empty v6 tombstone reaches this path; a saved workout
                // with sets defers the pairing transition above.
                restoreActiveWorkoutSnapshot(savedActive);
                restoredActive = true;
            }
        }
        if (!restoredActive) {
            sets = [];
            activeWorkoutStartedAtSeconds = null;
            resumedWorkoutIntervalsInvalid = false;
            resetActiveWorkoutSnapshotState();
        }

        exerciseIndex = 0;

        pruneAccountScopedState();
        recoverQueuedWorkout();
        if (hasPreparedWorkout()) {
            status = preparedWorkoutFitSaved() ? GymStatus.FIT_SAVED : GymStatus.FIT_CHECK;
        }
        if (recoveredPairing) {
            pairingRecoveryCommitLast = true;
            var recoverySaved = save();
            pairingRecoveryCommitLast = false;
            if (!recoverySaved) {
                pairingGeneration = previousPairingGeneration;
                for (var i = 0; i < pending.size(); i += 1) {
                    pendingEstimateSource = null;
                    pending[i].put("pairingGeneration", previousPairingGeneration);
                }
                if (preparedWorkout != null) {
                    preparedWorkout[3] = previousPairingGeneration;
                }
                status = GymStatus.SAVE_FAIL;
            }
        }
        // Never park a staged generation before its full-message queue and
        // journal rotation have committed. The helper repeats this fence.
        if (stagedPairingRecoveryTarget() == null) {
            parkPendingDuringLongWorkout(sets.size());
        }

        GymWorkoutMode.state = GymWorkoutMode.MODE_IDLE;
    }

    (:compactCheckpoint96)
    private static function discardUnownedMemory96(preservedPlanBytes) {
        accountBinding = null;
        stateOwnerBinding = null;
        deviceBinding = null;
        pairingGeneration = null;
        cloudDeviceBinding = null;
        validatedBindingA = null;
        validatedBindingB = null;
        sets = [];
        plan = [];
        persistedPlanSource = plan;
        persistedPlanBytes = preservedPlanBytes;
        persistedPlanNeedsV5Write = false;
        pending = [];
        parkedPending = null;
        pendingEstimateSource = null;
        pendingEstimateBytes = 0;
        GymPendingJournal.reset();
        preparedWorkout = null;
        lastWorkoutSyncAtSeconds = null;
        tutorialHistory = [];
        deferredSync = null;
        processedSyncIds = [];
        stagedPhoneSyncRevision = 0l;
        stagedPhoneSyncId = null;
        stagedPhoneAccountBinding = null;
        stagedPhoneSyncMessage = null;
        stagedCloudPlanRevision = 0;
        stagedCloudPlanId = null;
        stagedCloudAccountBinding = null;
        stagedCloudSyncMessage = null;
        lastCloudPlanRevision = 0;
        lastCloudPlanId = null;
        activeWorkoutStartedAtSeconds = null;
        resumedWorkoutIntervalsInvalid = false;
        resetActiveWorkoutSnapshotState();
        resetRuntimeCheckpointState();
        restDurationMs = 0;
        restStartedAt = null;
        exerciseIndex = 0;
        exerciseCatalogNeedsWrite = true;
        // Reuse the existing catalog write fence so ordinary Store saves cannot
        // overwrite unowned keys. A validated phone transition clears it.
        exerciseCatalogRepairRequired = true;
        clearTransientSetActions();
    }

    (:compactLegacyState)
    static function save() {
        if (!GymPendingJournal.readable) { return false; }
        try {
            if (activeWorkoutStartedAtSeconds != null &&
                ((!hasAccountBinding() && !legacyUnboundState) ||
                    !isValidWorkoutStartedAtSeconds(activeWorkoutStartedAtSeconds) ||
                    (sets.size() == 0 &&
                        (!hasAccountBinding() || !activeWorkoutSnapshotValid ||
                            !activeWorkoutTimelineValid)))) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            // activeWorkoutV1 is already the atomic commit for add/undo/clear.
            // Rewriting it here doubled the largest low-memory allocation.
            if ((legacyUnboundState && !ensureLegacyQuarantine()) ||
                !isWithinStorageBudget()) {
                status = GymStatus.STORE_FULL;
                return false;
            }
            var planChanged = plan != persistedPlanSource || persistedPlanNeedsV5Write;
            var storedPlanValue = planChanged ? storedPlan() : [];
            if (planChanged && storedPlanValue == null) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            if (!ensureDurableExerciseCatalog()) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            if (legacyUnboundState && !refreshLegacyCurrentQuarantine()) {
                status = GymStatus.LEGACY_FULL;
                return false;
            }
            Storage.setValue("currentEntryV1", [
                sets.size(), currentExercise(), weight, reps
            ]);
            var storedSets = activeWorkoutSnapshotValid && hasAccountBinding() ?
                [] : normalizedSetList(sets);
            Storage.setValue("sets", storedSets);
            Storage.setValue("activeWorkoutStartedAtSeconds",
                activeWorkoutSnapshotValid && hasAccountBinding() ?
                    null : activeWorkoutStartedAtSeconds);
            if (planChanged) {
                Storage.setValue("plan", storedPlanValue);
                persistedPlanBytes = estimatedValueBytes(storedPlanValue);
                persistedPlanSource = plan;
                persistedPlanNeedsV5Write = false;
            }
            storedPlanValue = null;
            if (parkedPending == null) { Storage.setValue("pending", pending); }
            if (!GymPendingJournal.save()) { status = GymStatus.SAVE_FAIL; return false; }
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
            if (!pairingRecoveryCommitLast) {
                Storage.setValue("pairingGeneration", pairingGeneration);
            }
            if (isValidAccountBinding(accountBinding)) {
                Storage.setValue("stateOwnerBinding", accountBinding);
                stateOwnerBinding = accountBinding;
            } else {
                Storage.deleteValue("stateOwnerBinding");
                stateOwnerBinding = null;
            }
            if (pairingRecoveryCommitLast) {
                Storage.setValue("pairingGeneration", pairingGeneration);
            }
            return true;
        } catch (e) {
            status = GymStatus.SAVE_FAIL;
            return false;
        }
    }

    (:compactLegacyState, :richWorkoutMode)
    private static function loadLegacyStoredPlan() {
        var value = null;
        try {
            value = Storage.getValue("plan");
        } catch (e) {
            plan = [];
            persistedPlanSource = plan;
            persistedPlanBytes = 0;
            persistedPlanNeedsV5Write = false;
            status = GymStatus.RECOVERY_FAIL;
            return;
        }
        var restored = restoredPlan(value);
        if (restored == null) {
            // Keep an unreadable key untouched until a validated phone sync
            // supplies a replacement; never turn a failed read into empty plan.
            plan = [];
            persistedPlanSource = plan;
            persistedPlanBytes = estimatedValueBytes(value);
            persistedPlanNeedsV5Write = false;
            status = GymStatus.RECOVERY_FAIL;
            return;
        }
        plan = restored;
        persistedPlanSource = plan;
        if (value == null) { persistedPlanBytes = 0; }
        if (persistedPlanNeedsV5Write) {
            // Migrate simple legacy dictionaries while the plan is the only
            // sizable object graph in the loader. Optional legacy fields remain
            // in their original dictionary fallback and are never discarded.
            var compactPlanValue = storedPlan();
            if (compactPlanValue != null) {
                // `plan` now owns the compact columns (and the local outer
                // array has been released where it was the legacy row spine).
                value = null;
                try {
                    Storage.setValue("plan", compactPlanValue);
                    persistedPlanBytes = estimatedValueBytes(compactPlanValue);
                    persistedPlanNeedsV5Write = false;
                } catch (e) {
                    // The old single-key value is still intact; a later save can
                    // retry the compact replacement.
                }
            }
        }
        value = null;
    }

    static function ensureDurableExerciseCatalog() {
        if (exerciseCatalogRepairRequired ||
            !isValidExerciseList(exercises, maxPlanSets) || exercises.size() == 0) {
            return false;
        }
        if (!exerciseCatalogNeedsWrite) {
            return true;
        }
        try {
            Storage.setValue("exercises", exercises);
            exerciseCatalogNeedsWrite = false;
            return true;
        } catch (e) {
            return false;
        }
    }

    (:richWorkoutMode)
    static function saveCurrentEntry() {
        GymSession.deferMotionForStorage();
        if (legacyUnboundState) {
            return save();
        }
        var exerciseName = currentExercise();
        if (!isValidExerciseName(exerciseName) ||
            !isValidWeight(weight) || !isValidReps(reps)) {
            status = GymStatus.SAVE_FAIL;
            return false;
        }
        try {
            Storage.setValue("currentEntryV1", [
                sets.size(), exerciseName, weight, reps
            ]);
        } catch (e) {
            status = GymStatus.SAVE_FAIL;
            return false;
        }
        // These two keys are a downgrade mirror only. Current versions restore
        // the exercise and its inputs from the single atomic envelope above.
        try {
            Storage.setValue("weight", weight);
            Storage.setValue("reps", reps);
        } catch (e) {
            // A mirror failure must not invalidate the committed current entry.
        }
        return true;
    }

    (:richWorkoutMode, :inline)
    static function restoreCurrentEntry(value) {
        if (!(value instanceof Lang.Array) ||
            (value.size() != 2 && value.size() != 4) ||
            !isBoundedInteger(value[0], 0, maxWorkoutSets) ||
            value[0] != sets.size() ||
            !isValidExerciseName(value[1]) ||
            (value.size() == 4 &&
                (!isValidWeight(value[2]) || !isValidReps(value[3]))) ||
            !selectExerciseByName(value[1].toString())) {
            return false;
        }
        if (value.size() == 4) {
            weight = value[2];
            reps = value[3];
        }
        return true;
    }

    static function resetActiveWorkoutSnapshotState() {
        GymActiveJournal.reset();
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
        lastRuntimeCheckpointTimerMs = null;
    }

    (:compactCheckpoint96)
    static function resetRuntimeCheckpointState() {
        runtimeWorkoutStartedAtSeconds = null;
        lastRuntimeCheckpointTimerMs = null;
    }

    (:fullLegacyState)
    static function isValidRuntimeCheckpoint(snapshot) {
        if (!(snapshot instanceof Lang.Array) || snapshot.size() != 11 ||
            !(snapshot[0] instanceof Lang.Number) || snapshot[0] != 1 ||
            !GymActiveJournal.validBindings(snapshot) ||
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
        if (!(snapshot instanceof Lang.Array) || snapshot.size() < 4 ||
            !isValidAccountBinding(snapshot[1]) ||
            !isBoundedText(snapshot[2], maxBindingLength) || !hasAccountBinding() ||
            !accountBinding.equals(snapshot[1]) ||
            !deviceBinding.equals(snapshot[2])) {
            return false;
        }
        var snapshotGeneration = snapshot[3];
        if (isValidAccountBinding(pairingGeneration)) {
            return isValidAccountBinding(snapshotGeneration) &&
                pairingGeneration.equals(snapshotGeneration);
        }
        return snapshotGeneration == null;
    }

    (:fullLegacyState)
    static function isValidActiveWorkoutSnapshot(snapshot) {
        if (snapshot instanceof Lang.Array && snapshot.size() == 10 && snapshot[0] == 6) {
            return GymActiveJournal.validate(snapshot);
        }
        if (snapshot instanceof Lang.Array && snapshot.size() > 0 &&
            snapshot[0] instanceof Lang.Number && (snapshot[0] == 4 || snapshot[0] == 6) &&
            snapshot.size() == 10) {
            return isValidCompactV4ActiveWorkoutSnapshot(snapshot);
        }
        if (!(snapshot instanceof Lang.Array) ||
            (snapshot.size() != 7 && snapshot.size() != 11) ||
            !(snapshot[0] instanceof Lang.Number) ||
            ((snapshot[0] == 2 && snapshot.size() != 7) ||
                ((snapshot[0] == 3 || snapshot[0] == 4) &&
                    snapshot.size() != 11)) ||
            (snapshot[0] != 2 && snapshot[0] != 3 && snapshot[0] != 4) ||
            !GymActiveJournal.validBindings(snapshot)) {
            return false;
        }
        var snapshotVersion = snapshot[0];
        var snapshotSets = snapshot[5];
        if ((snapshotVersion == 2 &&
                !isValidSetList(snapshotSets, maxWorkoutSets, true)) ||
            ((snapshotVersion == 3 || snapshotVersion == 4) &&
                !isValidCompactActiveSetArrays(snapshot))) {
            return false;
        }
        var startedAtSeconds = snapshot[4];
        var checkpoint = snapshotVersion >= 3 ? snapshot[10] : snapshot[6];
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
        if (snapshotVersion >= 3) {
            return isValidSetIntervalsList(snapshot[9], snapshotSets) &&
                areSetIntervalsConsistent(
                    snapshot[9], checkpoint[0], checkpoint[1], checkpoint[2]);
        }
        return areSnapshotIntervalsConsistent(snapshotSets, checkpoint);
    }

    (:richWorkoutMode)
    static function isValidCompactV4ActiveWorkoutSnapshot(snapshot) {
        if (!(snapshot instanceof Lang.Array) || !(snapshot.size() == 7 || snapshot.size() == 10) ||
            !(snapshot[0] instanceof Lang.Number) || !GymActiveJournal.validBindings(snapshot)) {
            return false;
        }
        var indexed = snapshot.size() == 10;
        var items = snapshot[5];
        if (indexed) {
            if ((snapshot[0] != 4 && snapshot[0] != 6) ||
                !isValidExerciseIndexList(items, maxWorkoutSets) ||
                !(snapshot[6] instanceof Lang.Array) || !(snapshot[7] instanceof Lang.Array) ||
                snapshot[6].size() != items.size() || snapshot[7].size() != items.size()) { return false; }
            for (var i = 0; i < items.size(); i += 1) {
                if (!isValidWeight(snapshot[6][i]) || !isValidReps(snapshot[7][i])) { return false; }
            }
        } else if ((snapshot[0] != 2 && snapshot[0] != 3) ||
            !isValidSetList(items, maxWorkoutSets, true)) { return false; }
        var origin = snapshot[4];
        var checkpoint = snapshot[indexed ? 9 : 6];
        if (items.size() == 0 && origin != null &&
            ((!indexed && snapshot[0] != 3) || checkpoint == null ||
                !isValidWorkoutStartedAtSeconds(origin))) { return false; }
        if (items.size() > 0 &&
            ((origin == null && checkpoint != null) ||
                (origin != null && !isValidWorkoutStartedAtSeconds(origin)))) { return false; }
        if (checkpoint == null) { return !indexed || snapshot[8] == null; }
        if (!isValidTimelineCheckpoint(checkpoint)) { return false; }
        return indexed ? (isValidSetIntervalsList(snapshot[8], items) &&
            areSetIntervalsConsistent(snapshot[8], checkpoint[0], checkpoint[1], checkpoint[2])) :
            areSnapshotIntervalsConsistent(items, checkpoint);
    }

    // The compact hardware tier accepts legacy v2/v3 dictionary transactions and
    // writes the indexed v4 parallel-array transaction. This keeps the executable
    // and restore heap within the hard ceiling while retaining complete workout
    // order and timeline. A valid origin/checkpoint may represent a started
    // workout before its first set; a null origin with zero checkpoint remains
    // the unambiguous durable tombstone.
    (:enhancedCompactCheckpoint)
    static function isValidActiveWorkoutSnapshot(snapshot) {
        if (snapshot instanceof Lang.Array && snapshot.size() == 10 && snapshot[0] == 6) {
            return GymActiveJournal.validate(snapshot);
        }
        return isValidCompactV4ActiveWorkoutSnapshot(snapshot);
    }

    // The five 96 KiB products keep only the current v6 row journal. Older
    // active-workout snapshots remain inert in storage instead of being restored.
    (:compactCheckpoint96)
    static function isValidActiveWorkoutSnapshot(snapshot) {
        return snapshot instanceof Lang.Array && snapshot.size() == 10 &&
            snapshot[0] == 6 && GymActiveJournal.validate(snapshot);
    }

    // These products used the full v3 parallel-array snapshot before joining the
    // compact hardware tier. Convert only an exact, current-owner snapshot and
    // validate every field that will be retained or deliberately omitted.
    // Malformed, stale-account, and stale-pairing values remain fail-closed.
    (:fr55UpgradeBridge)
    static function fullRuntimeForCompactMigration(active) {
        var runtime = null;
        try {
            runtime = Storage.getValue("activeRuntimeV1");
        } catch (e) {
            return null;
        }
        if (runtime == null) {
            return null;
        }
        if (!(runtime instanceof Lang.Array) || runtime.size() != 11 ||
            !(runtime[0] instanceof Lang.Number) || runtime[0] != 1 ||
            !GymActiveJournal.validBindings(runtime) ||
            !active[1].toString().equals(runtime[1].toString()) ||
            !active[2].toString().equals(runtime[2].toString()) ||
            !sameOptionalText(active[3], runtime[3]) ||
            !isBoundedInteger(runtime[4], 0, maxWorkoutSets) ||
            runtime[4] != active[5].size() ||
            !isValidWorkoutStartedAtSeconds(runtime[5]) ||
            !isValidWorkoutStartedAtSeconds(runtime[6]) ||
            runtime[6] > runtime[5] || runtime[5] - runtime[6] > 604800 ||
            !isValidTimelineCheckpoint(runtime[7]) ||
            !(runtime[8] instanceof Lang.Boolean) ||
            !isBoundedInteger(runtime[9], 0, 2)) {
            return null;
        }
        var restMode = runtime[9];
        var restValue = runtime[10];
        if ((restMode == 0 &&
                (!(restValue instanceof Lang.Number) || restValue != 0)) ||
            (restMode == 1 &&
                (!isValidWorkoutStartedAtSeconds(restValue) ||
                    restValue < runtime[5] || restValue - runtime[5] > 3600)) ||
            (restMode == 2 && !isBoundedInteger(restValue, 1, 3600))) {
            return null;
        }
        if (active[5].size() > 0) {
            if (active[4] != runtime[6] ||
                !isValidSetIntervalsList(active[9], active[5]) ||
                !areSetIntervalsConsistent(
                    active[9], runtime[7][0], runtime[7][1], runtime[7][2])) {
                return null;
            }
        }
        return runtime;
    }

    (:fr55UpgradeBridge)
    static function compactActiveSnapshotFromFullV3(value) {
        if (!(value instanceof Lang.Array) || value.size() != 11 ||
            !(value[0] instanceof Lang.Number) || value[0] != 3 ||
            !GymActiveJournal.validBindings(value) ||
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

        // The old full profile journaled the newest origin/timeline separately.
        // Merge that owner-bound checkpoint before dropping the full-only key;
        // otherwise a zero-set started workout becomes an empty tombstone after
        // the profile upgrade.
        var runtime = fullRuntimeForCompactMigration(value);
        if (runtime != null) {
            startedAt = runtime[6];
            checkpoint = runtime[7];
            if (names.size() == 0) {
                intervals = [];
            }
        }

        var indices = [];
        var safeWeights = [];
        var safeReps = [];
        var safeIntervals = checkpoint == null ? null : [];
        for (var j = 0; j < names.size(); j += 1) {
            var catalogIndex = exerciseIndexForName(names[j]);
            if (catalogIndex < 0) {
                return null;
            }
            indices.add(catalogIndex);
            safeWeights.add(weights[j]);
            safeReps.add(setReps[j]);
            if (safeIntervals != null) {
                safeIntervals.add(copySetInterval(intervals[j]));
            }
        }
        var safeCheckpoint = checkpoint == null ? null : copySetInterval(checkpoint);
        var candidate = [
            4,
            value[1].toString(),
            value[2].toString(),
            value[3] == null ? null : value[3].toString(),
            startedAt,
            indices,
            safeWeights,
            safeReps,
            safeIntervals,
            safeCheckpoint
        ];
        return isValidActiveWorkoutSnapshot(candidate) &&
            isWithinStorageBudgetForActiveSnapshot(candidate) ? candidate : null;
    }

    (:fr55UpgradeBridge, :inline)
    static function restoreMigratedActiveWorkout(savedActive) {
        var migratedActive = compactActiveSnapshotFromFullV3(savedActive);
        if (migratedActive == null || !ensureDurableExerciseCatalog()) {
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
            status = GymStatus.SAVE_FAIL;
        }
        return true;
    }

    // Products that have always used the compact schema must not carry the
    // FR55-only transition graph in their much smaller runtime budget.
    (:richWorkoutMode, :noFr55UpgradeBridge)
    static function compactActiveSnapshotFromFullV3(value) {
        return null;
    }

    (:richWorkoutMode, :noFr55UpgradeBridge, :inline)
    static function restoreMigratedActiveWorkout(savedActive) {
        return false;
    }

    // Version 4 keeps active-set names as bounded catalog indices. Plans remain
    // self-describing dictionaries so a separately committed catalog update can
    // never reinterpret older targets. Full loaders still accept the indexed
    // plan emitted briefly by an earlier v4 development build.
    (:inline)
    static function isValidExerciseIndexList(value, maximum) {
        if (!(value instanceof Lang.Array) || value.size() > maximum ||
            exercises.size() == 0) {
            return false;
        }
        for (var i = 0; i < value.size(); i += 1) {
            if (!isBoundedInteger(value[i], 0, exercises.size() - 1)) {
                return false;
            }
        }
        return true;
    }

    (:fullLegacyState, :inline)
    static function restoredPlan(value) {
        if (isValidSetList(value, maxPlanSets, true)) {
            return value;
        }
        if (!(value instanceof Lang.Array) || value.size() != 4 ||
            !(value[0] instanceof Lang.Number) ||
            (value[0] != 4 && value[0] != 5) ||
            !(value[1] instanceof Lang.Array) ||
            !(value[2] instanceof Lang.Array) || !(value[3] instanceof Lang.Array) ||
            value[2].size() != value[1].size() ||
            value[3].size() != value[1].size()) {
            return [];
        }
        var indexed = value[0] == 4;
        if (indexed ? (exerciseCatalogNeedsWrite ||
            !isValidExerciseIndexList(value[1], maxPlanSets)) :
            !isValidExerciseList(value[1], maxPlanSets)) { return []; }
        var restored = [];
        for (var i = 0; i < value[1].size(); i += 1) {
            if (!isValidWeight(value[2][i]) || !isValidReps(value[3][i])) {
                return [];
            }
            restored.add({
                "exerciseName" => indexed ? exercises[value[1][i]].toString() :
                    value[1][i].toString(),
                "weight" => value[2][i],
                "reps" => value[3][i]
            });
        }
        return restored;
    }

    (:fullLegacyState)
    static function storedPlan() {
        return isValidSetList(plan, maxPlanSets, true) ? plan : null;
    }

    (:compactLegacyState, :richWorkoutMode, :inline)
    static function restoredPlan(value) {
        persistedPlanNeedsV5Write = false;
        if (value == null) {
            persistedPlanBytes = 0;
            return [];
        }
        if (value instanceof Lang.Array && value.size() == 4 &&
            value[0] instanceof Lang.Number && value[0] == 5) {
            var v5 = new GymPlanList(value);
            if (!v5.valid(maxPlanSets, true)) { return null; }
            if (!persistedPlanNeedsV5Write) { persistedPlanBytes = estimatedValueBytes(value); }
            persistedPlanSource = v5;
            return v5;
        }

        if (!isValidSetList(value, maxPlanSets, true)) { return null; }
        if (value.size() == 0) {
            persistedPlanBytes = estimatedValueBytes(value);
            persistedPlanSource = value;
            return value;
        }
        var simpleRows = true;
        for (var i = 0; i < value.size(); i += 1) {
            if (!(value[i] instanceof Lang.Dictionary) || value[i].size() != 3) {
                simpleRows = false;
            }
        }
        if (simpleRows) {
            var serializedBytes = estimatedValueBytes(value);
            var weights = [];
            var setReps = [];
            for (var j = 0; j < value.size(); j += 1) {
                var row = value[j];
                weights.add(row.get("weight"));
                setReps.add(row.get("reps"));
                value[j] = row.get("exerciseName").toString();
            }
            var compact = new GymPlanList([5, value, weights, setReps]);
            // The source rows have already passed the complete storage validator.
            // Transposition preserves their names, weights, and repetitions.
            persistedPlanBytes = serializedBytes;
            persistedPlanSource = compact;
            persistedPlanNeedsV5Write = true;
            return compact;
        }
        persistedPlanBytes = estimatedValueBytes(value);
        persistedPlanSource = value;
        return value;
    }

    (:compactLegacyState)
    static function storedPlan() {
        if (GymPlanAccess.valid(plan, maxPlanSets, true)) {
            return plan.columns;
        }
        return isValidSetList(plan, maxPlanSets, true) ? plan : null;
    }

    // Version 3 stores set fields in parallel arrays instead of repeating eleven
    // dictionary keys. Existing compact metric/interval validators are reused to
    // keep both code and peak heap bounded on the compact products.
    (:fullLegacyState)
    static function isValidCompactActiveSetArrays(snapshot) {
        var names = snapshot[5];
        var weights = snapshot[6];
        var setReps = snapshot[7];
        var validNames = snapshot[0] == 4 ?
            isValidExerciseIndexList(names, maxWorkoutSets) :
            isValidExerciseList(names, maxWorkoutSets);
        if (!validNames ||
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

    (:inline)
    static function areSnapshotIntervalsConsistent(snapshotSets, checkpoint) {
        var intervals = [];
        for (var i = 0; i < snapshotSets.size(); i += 1) {
            var interval = setField(GymSetAccess.at(snapshotSets, i), "setInterval");
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
        GymActiveJournal.rememberLegacy(snapshot);
        if ((snapshot[0] == 4 || snapshot[0] == 6) && snapshot.size() == 10) {
            sets = restoredCompactV4Sets(snapshot);
        } else if (snapshot[0] >= 3) {
            var restored = [];
            var keys = [
                "activeSeconds", "restBeforeSeconds", "startHeartRate",
                "peakHeartRate", "endHeartRate", "recoveryHeartRateDrop",
                "detectionConfidence"
            ];
            for (var i = 0; i < snapshot[5].size(); i += 1) {
                var item = {
                    "exerciseName" => snapshot[0] == 4 ?
                        exercises[snapshot[5][i]].toString() :
                        snapshot[5][i].toString(),
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
        var checkpoint = (snapshot[0] == 4 || snapshot[0] == 6) && snapshot.size() == 10 ?
            snapshot[9] : (snapshot[0] >= 3 ? snapshot[10] : snapshot[6]);
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

    (:fullLegacyState)
    static function restoredSet(name, setWeight, setReps, interval) {
        return {"exerciseName" => name, "weight" => setWeight, "reps" => setReps,
            "setInterval" => interval};
    }

    (:compactLegacyState)
    static function restoredSet(name, setWeight, setReps, interval) {
        return GymRecordedSet.create(name, setWeight, setReps, interval);
    }

    (:fullLegacyState, :inline)
    static function syncedPlanRow(name, setWeight, setReps) {
        return {"exerciseName" => name, "weight" => setWeight, "reps" => setReps};
    }

    (:richWorkoutMode, :compactLegacyState, :inline)
    static function syncedPlanRow(name, setWeight, setReps) {
        return {"exerciseName" => name, "weight" => setWeight, "reps" => setReps};
    }

    (:richWorkoutMode, :inline)
    static function restoredCompactV4Sets(snapshot) {
        if (snapshot[0] == 6) { return GymActiveJournal.restored(snapshot); }
        var restored = [];
        for (var i = 0; i < snapshot[5].size(); i += 1) {
            // The validated Object Store value is process-local. Completed
            // intervals remain immutable; edits take a copy at the session boundary.
            var interval = snapshot[8] == null ? null :
                snapshot[8][i];
            restored.add(restoredSet(exercises[snapshot[5][i]].toString(),
                snapshot[6][i], snapshot[7][i], interval));
        }
        return restored;
    }

    (:enhancedCompactCheckpoint)
    static function restoreActiveWorkoutSnapshot(snapshot) {
        GymActiveJournal.rememberLegacy(snapshot);
        sets = (snapshot[0] == 4 || snapshot[0] == 6) ?
            restoredCompactV4Sets(snapshot) : normalizedSetList(snapshot[5]);
        activeWorkoutStartedAtSeconds = snapshot[4];
        activeWorkoutSnapshotValid = true;
        restDurationMs = 0;
        restStartedAt = null;
        var checkpoint = (snapshot[0] == 4 || snapshot[0] == 6) ? snapshot[9] : snapshot[6];
        if (checkpoint != null) {
            activeWorkoutTimelineValid = true;
            resumedWorkoutIntervalsInvalid = false;
            timelineBase = checkpoint;
            // Compact products derive the bounded rest remainder from the last
            // durable interval and timeline instead of carrying another runtime
            // journal. Relaunch may replay at most one checkpoint window, but it
            // never loses the completed set or rest entirely.
            if (sets.size() > 0) {
                var lastInterval = setField(GymSetAccess.at(sets, sets.size() - 1), "setInterval");
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
        sets = GymActiveJournal.restored(snapshot);
        activeWorkoutStartedAtSeconds = snapshot[4];
        activeWorkoutSnapshotValid = true;
        var checkpoint = snapshot[9];
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
        if (!hasAccountBinding()) {
            return GymLocalWorkout.checkpoint(force);
        }
        if (runtimePausePending) {
            if (!GymSession.pause()) {
                status = GymStatus.PAUSE_FAIL;
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
            accountBinding,
            deviceBinding,
            isValidAccountBinding(pairingGeneration) ?
                pairingGeneration : null,
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
                status = GymStatus.RECOVERY_FAIL;
            }
            return false;
        }
    }

    (:enhancedCompactCheckpoint)
    static function checkpointLiveWorkout(force) {
        if (!hasAccountBinding()) {
            return GymLocalWorkout.checkpoint(force);
        }
        if (!hasAccountBinding() || GymSession.startedAt <= 0 ||
            GymSession.fitSaved) {
            return true;
        }
        // Completed sets are durable already. A free workout has no rows, so
        // its bounded header can also checkpoint metrics every 15 seconds.
        if (!force && (!GymWorkoutMode.isFree() || GymSession.paused ||
            (lastRuntimeCheckpointTimerMs != null &&
                timerElapsedMs(lastRuntimeCheckpointTimerMs) < runtimeCheckpointIntervalMs.toLong()))) {
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
        lastRuntimeCheckpointTimerMs = System.getTimer();
        return true;
    }

    (:compactCheckpoint96)
    static function checkpointLiveWorkout(force) {
        if (!hasAccountBinding()) {
            return GymLocalWorkout.checkpoint(force);
        }
        if (!hasAccountBinding() || GymSession.startedAt <= 0 ||
            GymSession.fitSaved || (!force && GymSession.paused)) {
            return true;
        }
        // Free workouts only replace the bounded checkpoint header.
        if (!force && (!GymWorkoutMode.isFree() ||
            (lastRuntimeCheckpointTimerMs != null &&
                timerElapsedMs(lastRuntimeCheckpointTimerMs) < runtimeCheckpointIntervalMs.toLong()))) {
            return true;
        }
        var checkpoint = currentTimelineCheckpoint(0.0);
        var origin = activeWorkoutStartedAtSeconds;
        if (origin == null) {
            origin = runtimeWorkoutStartedAtSeconds;
        }
        if (origin == null) {
            origin = GymSession.startedAt;
        }
        if (checkpoint == null || !isValidWorkoutStartedAtSeconds(origin) ||
            !persistActiveWorkoutSnapshot(sets, origin, checkpoint)) {
            return false;
        }
        if (runtimeWorkoutStartedAtSeconds == null) {
            runtimeWorkoutStartedAtSeconds = GymSession.startedAt;
        }
        lastRuntimeCheckpointTimerMs = System.getTimer();
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
            status = GymStatus.RECOVERY_FAIL;
            return false;
        }
    }

    static function emptyTimelineCheckpoint() {
        return [0, 0.0, null, 0, 0, 0, null, 0];
    }

    (:richWorkoutMode, :inline)
    static function setIntervalForCurrentTimeline(source) {
        if (source == null && GymWorkoutMode.permitsOmittedSetIntervals()) { return null; }
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
        if (!hasAccountBinding() || !ensureDurableExerciseCatalog()) {
            return false;
        }
        try {
            if (!isValidLiveSetList(nextSets, maxWorkoutSets, true)) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            var indices = [];
            var weights = [];
            var setReps = [];
            var metrics = [];
            var intervals = checkpoint == null ? null : [];
            for (var i = 0; i < nextSets.size(); i += 1) {
                var item = GymSetAccess.at(nextSets, i);
                var exerciseCatalogIndex = exerciseIndexForName(
                    setField(item, "exerciseName")
                );
                if (exerciseCatalogIndex < 0) {
                    status = GymStatus.SAVE_FAIL;
                    return false;
                }
                indices.add(exerciseCatalogIndex);
                weights.add(setField(item, "weight"));
                setReps.add(setField(item, "reps"));
                metrics.add(compactSetMetrics(item));
                if (intervals != null) {
                    intervals.add(setField(item, "setInterval"));
                }
            }
            var snapshot = [
                4,
                accountBinding,
                deviceBinding,
                isValidAccountBinding(pairingGeneration) ? pairingGeneration : null,
                startedAtSeconds,
                indices,
                weights,
                setReps,
                metrics,
                intervals,
                checkpoint
            ];
            if (!isValidActiveWorkoutSnapshot(snapshot) ||
                !isWithinStorageBudgetForActiveSnapshot(snapshot)) {
                // Optional per-set detector/HR metrics are valuable after a
                // restart, but never more valuable than the completed sets.
                // Near the durable ceiling, release that parallel column and
                // commit the compact v4 shape used by constrained products.
                metrics = null;
                snapshot = [
                    4,
                    accountBinding,
                    deviceBinding,
                    isValidAccountBinding(pairingGeneration) ? pairingGeneration : null,
                    startedAtSeconds,
                    indices,
                    weights,
                    setReps,
                    intervals,
                    checkpoint
                ];
            }
            if (!isValidActiveWorkoutSnapshot(snapshot) ||
                !isWithinStorageBudgetForActiveSnapshot(snapshot)) {
                status = GymStatus.STORE_FULL;
                return false;
            }
            // A prior atomic snapshot is already the rollback boundary, so its
            // redundant mirror can be released before the next v4 commit. A
            // pre-snapshot installation may have only the per-key workout;
            // preserve that old state until the first atomic write succeeds.
            var canReleaseMirrorBeforeCommit = activeWorkoutSnapshotValid;
            if (canReleaseMirrorBeforeCommit) {
                Storage.setValue("sets", []);
                Storage.setValue("activeWorkoutStartedAtSeconds", null);
            }
            Storage.setValue("activeWorkoutV1", snapshot);
            activeWorkoutSnapshotValid = true;
            activeWorkoutTimelineValid = checkpoint != null;
            if (!canReleaseMirrorBeforeCommit) {
                try {
                    Storage.setValue("sets", []);
                    Storage.setValue("activeWorkoutStartedAtSeconds", null);
                } catch (e) {
                    // The committed owner-bound snapshot remains authoritative;
                    // a later compatibility save retries this bounded cleanup.
                }
            }
            return true;
        } catch (e) {
            status = GymStatus.SAVE_FAIL;
            return false;
        }
    }

    (:fullLegacyState, :inline)
    static function isImmutableLiveRecord(value) { return false; }

    (:compactLegacyState, :inline)
    static function isImmutableLiveRecord(value) {
        return GymRecordedSet.isRecord(value) || GymActiveJournal.isRecord(value);
    }

    (:compactLegacyState)
    static function persistActiveWorkoutSnapshot(nextSets, startedAtSeconds, checkpoint) {
        if (!hasAccountBinding() || !ensureDurableExerciseCatalog() ||
            !isValidLiveSetList(nextSets, maxWorkoutSets, true) ||
            (checkpoint != null && !isValidTimelineCheckpoint(checkpoint))) {
            status = GymStatus.SAVE_FAIL;
            return false;
        }
        if (!GymActiveJournal.commit(nextSets, startedAtSeconds, checkpoint)) {
            if (!(status == GymStatus.STORE_FULL)) { status = GymStatus.SAVE_FAIL; }
            return false;
        }
        activeWorkoutSnapshotValid = true;
        activeWorkoutTimelineValid = checkpoint != null;
        try {
            Storage.setValue("sets", []);
            Storage.setValue("activeWorkoutStartedAtSeconds", null);
        } catch (e) {
            // The committed header is authoritative; the old mirror cannot win.
        }
        return true;
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

    (:richWorkoutMode, :inline)
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
    (:richWorkoutMode)
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
        if ((isUk() || isRu()) && name.find("|") == null && name.find("~") == null) {
            // Native string resources avoid allocating a decoded dictionary and
            // every neighbouring label. Only the selected row survives in RAM.
            var shard = exerciseLabelShard(name);
            var shards = [
                Rez.Strings.ExerciseLabels00, Rez.Strings.ExerciseLabels01,
                Rez.Strings.ExerciseLabels02, Rez.Strings.ExerciseLabels03,
                Rez.Strings.ExerciseLabels04, Rez.Strings.ExerciseLabels05,
                Rez.Strings.ExerciseLabels06, Rez.Strings.ExerciseLabels07,
                Rez.Strings.ExerciseLabels08, Rez.Strings.ExerciseLabels09,
                Rez.Strings.ExerciseLabels10, Rez.Strings.ExerciseLabels11,
                Rez.Strings.ExerciseLabels12, Rez.Strings.ExerciseLabels13,
                Rez.Strings.ExerciseLabels14, Rez.Strings.ExerciseLabels15
            ];
            var packed = App.loadResource(shards[shard]) as Lang.String;
            shards = null;
            var marker = "~" + name + "|";
            var start = packed.find(marker);
            if (start != null) {
                start += marker.length();
                // The build verifies every translated row fits in this window.
                // Avoid copying the rest of the resource beside the full shard.
                var rowEnd = start + 192;
                if (rowEnd > packed.length()) { rowEnd = packed.length(); }
                var row = packed.substring(start, rowEnd);
                packed = null;
                if (row == null) { return name; }
                var end = row.find("~");
                if (end != null) { row = row.substring(0, end); }
                var divider = row.find("|");
                if (divider != null) {
                    label = isUk() ? row.substring(0, divider) :
                        row.substring(divider + 1, row.length());
                }
            }
        }
        exerciseLabelCacheName = name;
        exerciseLabelCacheLanguage = language;
        exerciseLabelCacheValue = label;
        return label;
    }

    (:inline)
    static function exerciseLabelShard(name) {
        var bytes = utf8Bytes(name);
        var bucket = 0;
        for (var i = 0; i < bytes.size(); i += 1) {
            bucket = (bucket + bytes[i]) % 16;
        }
        return bucket;
    }

    (:richWorkoutMode)
    static function applyCurrentPlanSet() {
        if (!GymWorkoutMode.isPlanned() || plan.size() == 0) {
            return false;
        }
        var exerciseName = currentExercise();
        var completed = completedSetsForExercise(exerciseName);
        return applyPlanItem(planItemForExerciseAfterCompleted(exerciseName, completed));
    }

    (:richWorkoutMode)
    static function planItemForExerciseAfterCompleted(exerciseName, completed) {
        var item = null;
        var matchingIndex = 0;
        for (var i = 0; i < plan.size(); i += 1) {
            var candidate = GymPlanAccess.at(plan, i);
            if (isSetRecord(candidate) &&
                setField(candidate, "exerciseName").toString().equals(exerciseName)) {
                if (matchingIndex == completed) {
                    item = candidate;
                    break;
                }
                matchingIndex += 1;
            }
        }
        return item;
    }

    (:richWorkoutMode)
    static function applyPlanItem(item) {
        if (!(isSetRecord(item))) {
            return false;
        }
        var plannedWeight = setField(item, "weight");
        var plannedReps = setField(item, "reps");
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
        if (GymSetAccess.isJournal(sets)) {
            return GymActiveJournal.countExercise(exerciseName);
        }
        var completed = 0;
        for (var i = 0; i < sets.size(); i += 1) {
            var item = GymSetAccess.at(sets, i);
            if (isSetRecord(item) &&
                setField(item, "exerciseName").toString().equals(exerciseName)) {
                completed += 1;
            }
        }
        return completed;
    }

    (:richWorkoutMode, :inline)
    static function remainingPlannedSetsForExercise(exerciseName) {
        var remaining = plannedSetsForExercise(exerciseName) - completedSetsForExercise(exerciseName);
        return remaining > 0 ? remaining : 0;
    }

    (:inline)
    static function plannedSetsForExercise(exerciseName) {
        var planned = 0;
        for (var i = 0; i < plan.size(); i += 1) {
            var name = GymPlanAccess.nameAt(plan, i);
            if (name != null && name.equals(exerciseName)) {
                planned += 1;
            }
        }
        return planned;
    }

    (:inline)
    static function completedPlannedSetCount() {
        if (plan.size() == 0 || sets.size() == 0) { return 0; }
        // Match each actual set to one unconsumed target. A byte per target
        // avoids repeatedly rescanning all earlier actual sets and names.
        var consumed = new [plan.size()]b;
        var completed = 0;
        for (var i = 0; i < sets.size(); i += 1) {
            var item = GymSetAccess.at(sets, i);
            if (!isSetRecord(item)) { continue; }
            var name = setField(item, "exerciseName");
            for (var p = 0; p < plan.size(); p += 1) {
                var targetName = GymPlanAccess.nameAt(plan, p);
                if (consumed[p] == 0 && targetName != null &&
                    targetName.equals(name)) {
                    consumed[p] = 1; completed += 1; break;
                }
            }
        }
        return completed;
    }

    static function selectExerciseByName(exerciseName) {
        var index = exerciseIndexForName(exerciseName);
        if (index >= 0) {
            exerciseIndex = index;
            return true;
        }
        return false;
    }

    static function exerciseIndexForName(exerciseName) {
        if (!(exerciseName instanceof Lang.String)) {
            return -1;
        }
        for (var i = 0; i < exercises.size(); i += 1) {
            if (exercises[i].toString().equals(exerciseName.toString())) {
                return i;
            }
        }
        return -1;
    }

    (:richWorkoutMode)
    static function selectNextPlanSlotInGlobalOrder() {
        // This is only an initial fallback when no current/last exercise exists.
        // Once a set exists, free-order recovery always prefers the athlete's
        // persisted or last selected exercise.
        if (!GymWorkoutMode.isPlanned() || plan.size() == 0) {
            return false;
        }
        var item = GymPlanAccess.at(plan, 0);
        if (!selectExerciseByName(setField(item, "exerciseName").toString())) {
            return false;
        }
        return applyPlanItem(item);
    }

    (:richWorkoutMode)
    static function nextExercise(delta) {
        if (!GymWorkoutMode.allowsDetailedTracking() || exercises.size() == 0) {
            status = GymStatus.PLAN_ONLY;
            return;
        }
        exerciseIndex = (exerciseIndex + delta) % exercises.size();
        if (exerciseIndex < 0) {
            exerciseIndex += exercises.size();
        }
        applyCurrentPlanSet();
    }

    (:richWorkoutMode)
    static function addSet() {
        GymSession.deferMotionForStorage();
        if (!GymWorkoutMode.allowsDetailedTracking()) {
            status = GymStatus.PLAN_ONLY;
            return false;
        }
        var setLimit = maxNewWorkoutSets;
        // A recovered legacy workout above today's limit may continue to the
        // historical read limit without discarding its existing set history.
        if (sets.size() > maxNewWorkoutSets && hasUnfinishedWorkout()) {
            setLimit = maxWorkoutSets;
        }
        if (sets.size() >= setLimit ||
            !isValidExerciseName(currentExercise()) ||
            !isValidWeight(weight) ||
            !isValidReps(reps)) {
            status = GymStatus.SET_LIMIT;
            return false;
        }
        if (!hasAccountBinding() && !ensureUnboundAtomicQuarantine()) {
            // A fresh ownerless workout has no account/device tuple for activeWorkoutV1.
            // Establish the same single-value quarantine used by legacy ownerless data
            // before publishing its first mutation; it remains unsendable by design.
            status = GymStatus.LEGACY_FULL;
            return false;
        }
        var statistics = GymSession.captureSetStatistics();
        var setInterval = setIntervalForCurrentTimeline(GymSession.setStatistic(statistics, 7));
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
        // Previous set dictionaries are immutable after publication. Copy only
        // the array spine here; cloning every dictionary and interval produces a
        // transient O(n) heap spike on every new set.
        var nextSets = sets.slice(null, null);
        var previousWeight = weight;
        var previousReps = reps;
        var previousExerciseIndex = exerciseIndex;
        var wasPlannedSet = GymWorkoutMode.isPlanned() &&
            remainingPlannedSetsForExercise(currentExercise()) > 0;
        var postCommitWeight = weight;
        var postCommitReps = reps;
        if (wasPlannedSet) {
            var completedAfterCommit = completedSetsForExercise(currentExercise()) + 1;
            var postCommitPlanItem = planItemForExerciseAfterCompleted(
                currentExercise(), completedAfterCommit
            );
            if (isSetRecord(postCommitPlanItem) &&
                isValidWeight(setField(postCommitPlanItem, "weight")) &&
                isValidReps(setField(postCommitPlanItem, "reps"))) {
                postCommitWeight = setField(postCommitPlanItem, "weight");
                postCommitReps = setField(postCommitPlanItem, "reps");
            }
        }
        // The first set has no preceding rest. After a process restart the prior
        // set end is also unknown, so do not manufacture a zero-second recovery.
        var restBefore = null;
        if (keepsSetDiagnostics && nextSets.size() > 0) {
            var previousSet = GymSetAccess.at(nextSets, nextSets.size() - 1);
            var currentStart = GymSession.setStatistic(statistics, 1);
            if (lastLoggedSetEndSeconds > 0 && currentStart instanceof Lang.Number &&
                currentStart >= lastLoggedSetEndSeconds) {
                restBefore = currentStart - lastLoggedSetEndSeconds;
                if (restBefore > 86400) {
                    restBefore = 86400;
                }
            }
            var recoveryDrop = GymSession.recoveryHeartRateDrop();
            if (keepsSetDiagnostics && recoveryDrop != null) {
                var previousSetSource = previousSet;
                previousSet = {
                    "exerciseName" => setField(previousSetSource, "exerciseName").toString(),
                    "weight" => setField(previousSetSource, "weight"),
                    "reps" => setField(previousSetSource, "reps")
                };
                copyOptionalSetMetrics(previousSet, previousSetSource);
                previousSet.put("recoveryHeartRateDrop", recoveryDrop);
                nextSets[nextSets.size() - 1] = previousSet;
            }
        }
        var wasAutoPrompt = GymSession.autoLogPrompt;
        var boost = GymSession.setBoostFor(weight, reps);
        if (setInterval != null) {
            setInterval[2] += boost;
            if (setInterval[2] > 100000.0) {
                setInterval[2] = 100000.0;
            }
        }
        var setItem = recordedSet(currentExercise(), weight, reps, statistics, restBefore, setInterval);
        nextSets.add(setItem);
        // recordedSet owns its private interval copy. The shifted temporary is
        // no longer needed beside Object Store's serialization buffer.
        setInterval = null;

        var legacyOriginUnavailable = previousSets.size() > 0 &&
            previousWorkoutStartedAt == null && nextWorkoutStartedAt == null &&
            resumedWorkoutIntervalsInvalid;
        var usedAtomicSnapshot = hasAccountBinding() &&
            (isValidWorkoutStartedAtSeconds(nextWorkoutStartedAt) ||
                legacyOriginUnavailable);
        if (usedAtomicSnapshot) {
            var checkpoint = currentTimelineCheckpoint(boost);
            if (!resumedWorkoutIntervalsInvalid && checkpoint == null) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            // Bind the selected exercise/input to the prospective set count.
            // A failed snapshot leaves this entry mismatched and therefore
            // ignored; a successful snapshot can never reopen on exercise 0.
            try {
                Storage.setValue("currentEntryV1", [
                    nextSets.size(), currentExercise(), postCommitWeight, postCommitReps
                ]);
            } catch (e) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            if (!persistActiveWorkoutSnapshot(nextSets, nextWorkoutStartedAt, checkpoint)) {
                return false;
            }
            // The atomic snapshot is now the rollback boundary. Release the old
            // expanded graph before publishing the remaining in-memory state.
            previousSets = null;
        }

        // Only publish globals and calorie corrections after the single-value
        // snapshot commit succeeds. A thrown Object Store write leaves the old set
        // list and detector totals untouched.
        sets = usedAtomicSnapshot ? GymSetAccess.committed(nextSets) : nextSets;
        activeWorkoutStartedAtSeconds = nextWorkoutStartedAt;
        GymSession.restoreSetBoost(boost);
        if (wasPlannedSet) {
            // A plan supplies targets, not navigation. Preserve the selected
            // exercise and load only that exercise's next target.
            weight = postCommitWeight;
            reps = postCommitReps;
        }
        var compatibilitySaved = usedAtomicSnapshot ? true : save();
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
                status = GymStatus.RECOVERY_FAIL;
            }
            return false;
        }
        lastSetBoost = boost;
        lastSetWasAutoPrompt = wasAutoPrompt;
        lastSetStatistics = statistics;
        lastSetPreviousLoggedEnd = lastLoggedSetEndSeconds;
        lastLoggedSetEndSeconds = GymSession.setStatistic(statistics, 2);
        var actionTimerMs = System.getTimer();
        lastSetUndoStartedAt = actionTimerMs;
        GymSession.beginRecoveryTracking(statistics);
        GymSession.clearAutoPrompt();
        restDurationMs = restSecondsDefault * 1000;
        restStartedAt = actionTimerMs;
        // The atomic snapshot is the commit; compatibility mirror failures do
        // not turn a successfully stored athlete action into a UI error.
        status = GymStatus.SET_SAVED;
        return true;
    }

    (:fullLegacyState, :inline)
    static function recordedSet(name, setWeight, setReps, statistics, restBefore, setInterval) {
        return {
            "exerciseName" => name,
            "weight" => setWeight,
            "reps" => setReps,
            "activeSeconds" => GymSession.setStatistic(statistics, 0),
            "restBeforeSeconds" => restBefore,
            "startHeartRate" => GymSession.setStatistic(statistics, 3),
            "peakHeartRate" => GymSession.setStatistic(statistics, 4),
            "endHeartRate" => GymSession.setStatistic(statistics, 5),
            "detectionConfidence" => GymSession.setStatistic(statistics, 6),
            "setInterval" => setInterval
        };
    }

    (:richWorkoutMode, :compactLegacyState, :inline)
    static function recordedSet(name, setWeight, setReps, statistics, restBefore, setInterval) {
        // The durable compact checkpoint already omits optional detector fields.
        // Keep the live graph equally small; undo uses lastSetStatistics separately.
        if (!hasAccountBinding()) {
            return {"exerciseName" => name, "weight" => setWeight, "reps" => setReps,
                "setInterval" => setInterval};
        }
        return restoredSet(name, setWeight, setReps, setInterval);
    }

    (:richWorkoutMode)
    static function canUndoLastSet() {
        if (!GymWorkoutMode.allowsDetailedTracking() || sets.size() == 0 ||
            lastSetUndoStartedAt == null) {
            return false;
        }
        if (timerElapsedMs(lastSetUndoStartedAt) > undoWindowMs) {
            clearTransientSetActions();
            return false;
        }
        return true;
    }

    (:richWorkoutMode)
    static function undoLastSet() {
        GymSession.deferMotionForStorage();
        if (!GymWorkoutMode.allowsDetailedTracking()) {
            status = GymStatus.PLAN_ONLY;
            return false;
        }
        if (!canUndoLastSet()) {
            status = GymStatus.UNDO_EXPIRED;
            return false;
        }
        if (!hasAccountBinding() && !ensureUnboundAtomicQuarantine()) {
            status = GymStatus.LEGACY_FULL;
            return false;
        }
        var previousSets = sets;
        var lastIndex = previousSets.size() - 1;
        var lastSet = GymSetAccess.at(previousSets, lastIndex);
        var undoneName = setField(lastSet, "exerciseName");
        var undoneWeight = setField(lastSet, "weight");
        var undoneReps = setField(lastSet, "reps");
        var nextSets = previousSets.slice(0, lastIndex);
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
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            // Publish the post-undo picker as a count-bound intent before the
            // active snapshot. If the snapshot write fails, the smaller count
            // cannot match the old snapshot and load rejects this entry. Once
            // the snapshot commits, exercise/kg/reps become recoverable as the
            // same atomic state transition instead of reverting to the last
            // remaining exercise after a process stop.
            try {
                Storage.setValue("currentEntryV1", [
                    nextSets.size(),
                    undoneName.toString(),
                    undoneWeight,
                    undoneReps
                ]);
            } catch (e) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            if (!persistActiveWorkoutSnapshot(nextSets, nextWorkoutStartedAt, checkpoint)) {
                return false;
            }
            previousSets = null;
        }

        sets = usedAtomicSnapshot ? GymSetAccess.committed(nextSets) : nextSets;
        activeWorkoutStartedAtSeconds = nextWorkoutStartedAt;
        GymSession.removeSetBoost(boost);
        weight = undoneWeight;
        reps = undoneReps;
        for (var e = 0; e < exercises.size(); e += 1) {
            if (exercises[e].toString().equals(undoneName.toString())) {
                exerciseIndex = e;
                break;
            }
        }
        // Undo returns the exact values the athlete saved, including deliberate
        // deviations from the plan. Removing the set already rewinds the plan cursor.
        var compatibilitySaved = usedAtomicSnapshot ? true : save();
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
                status = GymStatus.RECOVERY_FAIL;
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
        status = GymStatus.SET_UNDONE;
        return true;
    }

    // Keep the shared storage API available on 96 KiB products while omitting
    // the undo state and its commit path from their executable.
    static function clearTransientSetActions() {
        lastSetUndoStartedAt = null;
        lastSetBoost = 0.0;
        lastSetWasAutoPrompt = false;
        lastSetStatistics = null;
        lastSetPreviousLoggedEnd = 0;
    }

    (:richWorkoutMode, :inline)
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

    (:richWorkoutMode, :inline)
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

    (:richWorkoutMode, :inline)
    static function toggleAutoPrompt() {
        autoPromptEnabled = !autoPromptEnabled;
        if (!autoPromptEnabled) {
            GymSession.clearAutoPrompt();
        }
        save();
    }

    (:richWorkoutMode, :inline)
    static function adjustSensitivity(delta) {
        sensitivityIndex = (sensitivityIndex + (delta < 0 ? 2 : 1)) % 3;
        save();
    }

    (:richWorkoutMode, :inline)
    static function sensitivityLabel() {
        if (sensitivityIndex == 0) {
            return tr("LOW", "НИЗ", "НИЗ");
        } else if (sensitivityIndex == 2) {
            return tr("HIGH", "ВИС", "ВЫС");
        }
        return tr("NORMAL", "НОРМ", "НОРМ");
    }

    static function clearWorkout() {
        if (!GymLocalWorkout.clear()) {
            status = GymStatus.RECOVERY_FAIL;
            return false;
        }
        if (hasAccountBinding() && !persistEmptyActiveWorkoutSnapshot()) {
            status = GymStatus.SAVE_FAIL;
            return false;
        }
        sets = [];
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
            GymWorkoutMode.clear();
        }
        return cleared;
    }

    (:inline)
    static function markWorkoutResumed() {
        if (sets.size() > 0 && !activeWorkoutTimelineValid) {
            resumedWorkoutIntervalsInvalid = true;
        }
    }

    static function hasUnfinishedWorkout() {
        if (GymLocalWorkout.snapshot != null) {
            return true;
        }
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
        if (!GymLocalWorkout.clear()) {
            status = GymStatus.RECOVERY_FAIL;
            return false;
        }
        var atomicallyCleared = false;
        if (hasAccountBinding()) {
            if (!persistEmptyActiveWorkoutSnapshot()) {
                status = GymStatus.SAVE_FAIL;
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
        var cleared = compatibilitySaved || atomicallyCleared;
        if (cleared) {
            GymWorkoutMode.clear();
        }
        return cleared;
    }

    (:richWorkoutMode)
    static function restSeconds() {
        if (!GymWorkoutMode.allowsDetailedTracking() || restDurationMs <= 0 ||
            restStartedAt == null) {
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

    (:inline)
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
        if (!(value instanceof Lang.Array)) {
            return false;
        }
        var markerSize = value.size();
        if ((markerSize != 6 && markerSize != 7) ||
            !(value[0] instanceof Lang.Number) ||
            ((markerSize == 6 && value[0] != 1) ||
                (markerSize == 7 && value[0] != 2))) {
            return false;
        }
        if (!GymActiveJournal.validBindings(value) ||
            !isBoundedText(value[4], maxBindingLength) ||
            !isBoundedInteger(value[5], 0, 1)) {
            return false;
        }
        if (markerSize == 6) {
            // Released phase markers predate FREE payloads. They can only
            // represent the existing detailed/planned transaction.
            return true;
        }
        return value[6] instanceof Lang.Boolean;
    }

    static function hasPreparedWorkout() {
        if (preparedWorkout == null ||
            !isValidPreparedWorkout(preparedWorkout) ||
            !activeWorkoutSnapshotMatchesBindings(preparedWorkout)) {
            return false;
        }
        var freeMode = preparedWorkout.size() == 7 && preparedWorkout[6];
        if (!freeMode) {
            return isValidLiveSetList(sets, maxWorkoutSets, false);
        }
        // A FREE phase marker is useful only beside a real, owner-bound
        // metrics checkpoint. The empty tombstone and a forged zero-duration
        // transaction remain indistinguishable from "no workout" and fail shut.
        var freeCheckpoint = activeWorkoutTimelineValid ?
            currentTimelineCheckpoint(0.0) : null;
        return sets.size() == 0 &&
            isValidTimelineCheckpoint(freeCheckpoint) && freeCheckpoint[0] > 0;
    }

    static function preparedWorkoutFitSaved() {
        return hasPreparedWorkout() && preparedWorkout[5] == 1;
    }

    (:recoveryCore)
    static function preparedWorkoutNeedsFitDecision() {
        return hasPreparedWorkout() && preparedWorkout[5] == 0;
    }

    static function prepareWorkoutCommit() {
        if (!hasAccountBinding()) {
            return false;
        }
        if (hasPreparedWorkout()) {
            return true;
        }
        var freeMode = GymWorkoutMode.isFree();
        if (freeMode) {
            if (sets.size() != 0 || !GymSession.recording) {
                return false;
            }
            // Commit the last live metric slice before creating phase 0. A FREE
            // workout has no synthetic set to prove existence, so positive
            // elapsed time in this owner-bound snapshot is the authority.
            if (!checkpointLiveWorkout(true) || !activeWorkoutTimelineValid) {
                return false;
            }
            var freeCheckpoint = currentTimelineCheckpoint(0.0);
            if (!isValidTimelineCheckpoint(freeCheckpoint) ||
                freeCheckpoint[0] <= 0) {
                return false;
            }
        } else if (!GymWorkoutMode.isPlanned() ||
            !isValidLiveSetList(sets, maxWorkoutSets, false)) {
            return false;
        }
        var marker = [
            2,
            accountBinding,
            deviceBinding,
            isValidAccountBinding(pairingGeneration) ?
                pairingGeneration : null,
            nextRequestId("workout"),
            0,
            freeMode
        ];
        try {
            Storage.setValue("preparedWorkoutV1", marker);
            preparedWorkout = marker;
            return true;
        } catch (e) {
            status = GymStatus.SAVE_FAIL;
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
            status = GymStatus.FIT_SAVED;
            return true;
        } catch (e) {
            // FIT is already durable. Keep every GymApp set intact and make the
            // uncertainty visible; never enqueue without the phase-1 marker.
            preparedWorkout[5] = 0;
            status = GymStatus.FIT_CHECK;
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

    (:inline)
    static function preparedWorkoutJournalMetadata(allowSetsOnly) {
        if (!hasPreparedWorkout() ||
            (!preparedWorkoutFitSaved() &&
                (!allowSetsOnly || !GymSession.fitOutcomeUnknownAfterRestart()))) { return null; }
        return workoutMessageForSave(preparedWorkout[4].toString(), true);
    }

    static function pendingMessage() {
        // Loading a parked legacy queue allocates complete messages. Delay that
        // work until the phone link can actually send them; keep disk state intact.
        if (GymSession.recording || !GymComm.isPhoneConnected() ||
            !restorePendingForMutation()) { return null; }
        return pending.size() > 0 ? pending[0] : GymPendingJournal.nextMessage();
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
    (:recoveryCore, :inline)
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
    (:compactRecovery96, :inline)
    static function preparedWorkoutSetsOnlyMessage() {
        if (!hasPreparedWorkout() || preparedWorkout[5] != 0 ||
            !GymSession.fitOutcomeUnknownAfterRestart()) {
            return null;
        }
        return workoutMessage(preparedWorkout[4].toString());
    }

    (:inline)
    static function restoreLastWorkoutSync(value) {
        if (value instanceof Lang.Array && value.size() == 3 &&
            value[0] instanceof Lang.Number && value[0] == 1 &&
            isValidAccountBinding(value[1]) && hasAccountBinding() &&
            value[1].toString().equals(accountBinding) &&
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

    (:inline)
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

    (:inline)
    static function tutorialHandledForActiveAccount() {
        if (!hasAccountBinding()) {
            return false;
        }
        for (var i = 0; i < tutorialHistory.size(); i += 1) {
            var item = tutorialHistory[i];
            if (item.toString().equals(accountBinding)) {
                return true;
            }
        }
        return false;
    }

    (:richWorkoutMode, :inline)
    static function shouldStartTutorial() {
        return hasAccountBinding() && !tutorialHandledForActiveAccount() &&
            !hasUnfinishedWorkout() && !hasPreparedWorkout();
    }

    (:richWorkoutMode)
    static function markTutorialHandled() {
        if (!hasAccountBinding()) {
            return false;
        }
        var next = [];
        for (var i = 0; i < tutorialHistory.size(); i += 1) {
            var item = tutorialHistory[i];
            if (!item.toString().equals(accountBinding)) {
                next.add(item);
            }
        }
        next.add(accountBinding);
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
        return workoutMessageForSave(requestId, false);
    }

    static function workoutMessageForSave(requestId, metadataOnly) {
        if (!hasAccountBinding() || !hasPreparedWorkout() ||
            !isBoundedText(requestId, maxBindingLength) ||
            !preparedWorkout[4].toString().equals(requestId.toString())) {
            return null;
        }
        var freeMode = preparedWorkout.size() == 7 && preparedWorkout[6];
        if ((freeMode && sets.size() != 0) ||
            (!freeMode && !isValidLiveSetList(sets, maxWorkoutSets, false))) {
            return null;
        }
        var setCopies = [];
        var setMetrics = keepsSetDiagnostics ? [] : null;
        // Manual 96 KiB workouts carry no interval slices. Retain the richer
        // profiles' original empty-column shape for empty/no-interval saves.
        var setIntervals = GymWorkoutMode.permitsOmittedSetIntervals() ? null : [];
        var messageCheckpoint = activeWorkoutTimelineValid &&
            !resumedWorkoutIntervalsInvalid ? currentTimelineCheckpoint(0.0) : null;
        if (freeMode && (!isValidTimelineCheckpoint(messageCheckpoint) ||
            messageCheckpoint[0] <= 0)) {
            return null;
        }
        var allIntervalsAvailable = messageCheckpoint != null;
        for (var i = 0; !metadataOnly && !freeMode && i < sets.size(); i += 1) {
            var setItem = GymSetAccess.at(sets, i);
            if (!(isSetRecord(setItem))) {
                return null;
            }
            var exerciseName = setField(setItem, "exerciseName");
            var setWeight = setField(setItem, "weight");
            var setReps = setField(setItem, "reps");
            if (!isValidExerciseName(exerciseName) || !isValidWeight(setWeight) || !isValidReps(setReps)) {
                return null;
            }
            var setCopy = {
                "exerciseName" => exerciseName.toString(),
                "weight" => setWeight,
                "reps" => setReps
            };
            setCopies.add(setCopy);
            if (keepsSetDiagnostics && setMetrics != null) { setMetrics.add(compactSetMetrics(setItem)); }
            var setInterval = setField(setItem, "setInterval");
            if (setInterval != null && isValidSetInterval(setInterval)) {
                // Keep one immutable interval per completed set while the live
                // workout and its outgoing message coexist during durable save.
                if (setIntervals == null) { setIntervals = []; }
                setIntervals.add(setInterval);
            } else {
                allIntervalsAvailable = false;
            }
        }
        if (keepsSetDiagnostics && !freeMode && setMetrics != null && setMetrics.size() > 0) {
            var latestRecovery = GymSession.recoveryHeartRateDrop();
            if (latestRecovery != null) {
                setMetrics[setMetrics.size() - 1][5] = latestRecovery;
            }
        }
        var messageStartedAt = isValidWorkoutStartedAtSeconds(activeWorkoutStartedAtSeconds) ?
            activeWorkoutStartedAtSeconds :
            (isValidWorkoutStartedAtSeconds(runtimeWorkoutStartedAtSeconds) ?
                runtimeWorkoutStartedAtSeconds : GymSession.startedAt);
        if (!isValidWorkoutStartedAtSeconds(messageStartedAt)) {
            return null;
        }
        var target = !freeMode ? plan.size() : 0;
        var context = [requestId, accountBinding, deviceBinding, pairingGeneration,
            messageStartedAt, freeMode, messageCheckpoint, target,
            target > 0 ? completedPlannedSetCount() : 0, sets.size()];
        if (metadataOnly) { return context; }
        var message = expandWorkoutMetadata(context);
        if (message == null) { return null; }
        message["sets"] = setCopies;
        if (keepsSetDiagnostics && !freeMode && setMetrics != null) {
            message["setMetrics"] = setMetrics;
        }
        if (messageCheckpoint != null && allIntervalsAvailable && !freeMode &&
            setIntervals != null &&
            setIntervals.size() == setCopies.size() &&
            areSetIntervalsConsistent(setIntervals, messageCheckpoint[0],
                messageCheckpoint[1], messageCheckpoint[2])) {
            message["setIntervals"] = setIntervals;
        }
        return message;
    }

    // Preserve exact numeric values and optional-field absence while expanding
    // the bounded disk context into the existing phone contract. Callers still
    // validate ownership and request identity before accepting or sending it.
    static function isValidWorkoutContext(context) {
        if (!(context instanceof Lang.Array) || context.size() != 10 ||
            !(context[5] instanceof Lang.Boolean) ||
            !isBoundedText(context[0], maxBindingLength) ||
            !isValidAccountBinding(context[1]) ||
            !isBoundedText(context[2], maxBindingLength) ||
            !isValidWorkoutStartedAtSeconds(context[4]) ||
            !isValidOptionalAccountBinding(context[3]) ||
            (context[6] != null && !isValidTimelineCheckpoint(context[6])) ||
            !isBoundedInteger(context[7], 0, maxPlanSets) ||
            !isBoundedInteger(context[8], 0, context[7]) ||
            !isBoundedInteger(context[9], 0, maxWorkoutSets) ||
            context[8] > context[9] ||
            (context[5] && (context[7] != 0 || context[9] != 0))) { return false; }
        return true;
    }

    static function expandWorkoutMetadata(context) {
        if (!isValidWorkoutContext(context)) { return null; }
        var freeMode = context[5];
        var checkpoint = context[6];
        var message = {"type" => "create_workout", "bindingVersion" => bindingVersion,
            "workoutMode" => freeMode ? "free" : "planned", "requestId" => context[0],
            "accountBinding" => context[1], "deviceBinding" => context[2],
            "startedAtSeconds" => context[4]};
        if (checkpoint != null) {
            message["durationSeconds"] = checkpoint[0];
            message["gymCalories"] = checkpoint[1];
            var samples = checkpoint[4];
            if (!freeMode || samples > 0) {
                message["avgHeartRate"] = samples > 0 ? (checkpoint[3] / samples).toNumber() : 0;
                message["maxHeartRate"] = checkpoint[5];
                message["heartRateZone"] = checkpoint[7];
            }
            if (checkpoint[2] != null) { message["garminCalories"] = checkpoint[2]; }
            if (checkpoint[6] != null) { message["lastHeartRate"] = checkpoint[6]; }
        }
        if (!freeMode && context[7] > 0) {
            message["plannedSetCount"] = context[7] < context[9] ? context[9] : context[7];
            message["plannedTargetSetCount"] = context[7];
            message["completedPlannedSetCount"] = context[8];
        }
        if (context[3] != null) { message["pairingGeneration"] = context[3].toString(); }
        return message;
    }

    (:inline)
    static function applyPhoneSync(message) {
        return applySyncFromSource(message, "phone");
    }

    (:fullLegacyState)
    static function applyCloudSync(message) {
        return applySyncFromSource(message, "cloud");
    }

    (:fullLegacyState)
    static function applySyncFromSource(message, bindingSource) {
        if (GymLocalWorkout.blocksPairing()) {
            status = GymStatus.DATA_KEPT;
            return false;
        }
        if (!isValidSyncMessage(message, bindingSource)) {
            status = GymStatus.BAD_SYNC;
            return false;
        }

        // Never retain the transport-owned dictionary. Rebuilding the message from
        // validated scalar/array fields prevents unknown or deeply nested values from
        // entering the persistent deferred-sync state.
        var safeMessage = normalizedSyncMessage(message, bindingSource);

        var nextAccountBinding = safeMessage.get("accountBinding");
        var nextDeviceBinding = safeMessage.get("deviceBinding");
        var nextPairingGeneration = safeMessage.get("pairingGeneration");
        var replayKey = bindingSource + ":" + safeMessage.get("requestId");
        var resetValue = safeMessage.get("resetWorkout");
        var resetWorkout = bindingSource.equals("phone") &&
            resetValue instanceof Lang.Boolean && resetValue;
        var repairValue = safeMessage.get("repairPairing");
        var repairPairing = bindingSource.equals("phone") &&
            repairValue instanceof Lang.Boolean && repairValue;
        var accountChanged = accountBinding == null ||
            !accountBinding.equals(nextAccountBinding);
        if (bindingSource.equals("cloud") && stagedPhoneSyncRevision > 0l &&
            !hasAccountBinding()) {
            // A phone auth transition removed the previous owner but has not committed.
            // Do not let a stale cloud token reclaim the watch during that fail-closed gap.
            status = GymStatus.BAD_BIND;
            return false;
        }
        if (bindingSource.equals("phone") && accountBinding != null &&
            accountChanged && !resetWorkout) {
            // Once a watch has an owner, only the exact empty auth-transition command
            // may change it. A normal plan from another account must not erase state.
            status = GymStatus.BAD_BIND;
            return false;
        }
        if (bindingSource.equals("cloud") && accountBinding != null && accountChanged) {
            // A stale or replaced cloud token must never switch the watch back to another
            // account. Only the bound phone flow may perform an explicit account transition.
            status = GymStatus.BAD_BIND;
            return false;
        }
        if (bindingSource.equals("phone") && deviceBinding != null &&
            !deviceBinding.equals(nextDeviceBinding)) {
            status = GymStatus.BAD_BIND;
            return false;
        }
        if (bindingSource.equals("phone") && isValidAccountBinding(pairingGeneration)) {
            if (!isValidAccountBinding(nextPairingGeneration)) {
                if (!resetWorkout) {
                    status = GymStatus.PAIR_OLD;
                    return false;
                }
            } else if (!pairingGeneration.equals(nextPairingGeneration.toString()) &&
                !resetWorkout && !repairPairing) {
                status = GymStatus.PAIR_OLD;
                return false;
            }
        }
        if (bindingSource.equals("cloud") && cloudDeviceBinding != null &&
            !cloudDeviceBinding.equals(nextDeviceBinding)) {
            status = GymStatus.BAD_BIND;
            return false;
        }

        // The phone revision is global to this Garmin device and is checked before any
        // account-scoped state is cleared. A delayed message from the previous account can
        // therefore never switch the watch back after a newer account transition.
        var revisionStatus = syncRevisionStatus(safeMessage, bindingSource);
        var repairReplay = repairPairing &&
            isValidAccountBinding(pairingGeneration) &&
            isValidAccountBinding(nextPairingGeneration) &&
            pairingGeneration.equals(nextPairingGeneration.toString()) &&
            (revisionStatus == 0 || isExactStagedSync(safeMessage, bindingSource));
        if (repairPairing &&
            (resetWorkout || accountChanged || !isValidAccountBinding(pairingGeneration) ||
                !isValidAccountBinding(nextPairingGeneration) ||
                (pairingGeneration.equals(nextPairingGeneration.toString()) &&
                    !repairReplay))) {
            status = GymStatus.BAD_BIND;
            return false;
        }
        if (revisionStatus < 0) {
            status = GymStatus.SYNC_OLD;
            return false;
        }
        if (revisionStatus == 0) {
            if (isExactStagedSync(safeMessage, bindingSource) &&
                !syncBindingsMatch(safeMessage)) {
                // The fence committed but the owner marker did not. Reapply only this
                // exact staged message; duplicates with a valid owner remain no-op.
                revisionStatus = 1;
            } else {
                status = GymStatus.SYNC_DUP;
                clearSyncStageIfMatches(safeMessage, bindingSource);
                return true;
            }
        }
        // Durable stages from older builds remain recoverable at the historical
        // wire limit. A new submission must obey today's 30-target limit.
        var incomingPlanNames = safeMessage.get("planNames");
        if (!isExactStagedSync(safeMessage, bindingSource) &&
            incomingPlanNames instanceof Lang.Array &&
            incomingPlanNames.size() > maxNewWorkoutSets) {
            status = GymStatus.BAD_SYNC;
            return false;
        }
        var pairingGenerationChanges = bindingSource.equals("phone") &&
            !sameOptionalText(pairingGeneration, nextPairingGeneration);
        if (pairingGenerationChanges && !accountChanged && !resetWorkout &&
            (sets.size() > 0 || GymSession.recording || hasUnfinishedWorkout() ||
                preparedWorkout != null)) {
            // activeWorkoutV1, activeRuntimeV1, and the FIT-prepared marker are
            // owner-bound transactions. Do not partially rotate their binding;
            // the phone will retry the same revision after the workout is queued.
            status = GymStatus.PAIR_WAIT;
            return false;
        }
        if (pairingGenerationChanges && !accountChanged && !resetWorkout && !restorePendingForMutation()) {
            status = GymStatus.DATA_KEPT; return false;
        }
        // Persist the global replay barrier before destructive account-transition writes.
        if (!stageSync(safeMessage, bindingSource)) {
            status = GymStatus.SAVE_FAIL;
            return false;
        }

        if (accountChanged || resetWorkout) {
            if (legacyUnboundState &&
                (!ensureLegacyQuarantine() || !refreshLegacyCurrentQuarantine())) {
                // Never destroy or attach ownerless pre-upgrade data implicitly. The
                // replay stage remains durable, so only this exact/newer sync can retry.
                status = GymStatus.LEGACY_FULL;
                return false;
            }
            if (!beginAccountTransition()) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            if (bindingSource.equals("phone") &&
                !clearCloudSyncStageForAccountTransition()) {
                // The owner marker is already gone. Keep the watch fail-closed until
                // the stale cloud stage can be removed by an exact/newer phone retry.
                clearAccountScopedState();
                GymSession.resetForAccountTransition();
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            if (bindingSource.equals("phone") &&
                !GymComm.reconcileCloudDeviceToken(nextAccountBinding)) {
                clearAccountScopedState();
                GymSession.resetForAccountTransition();
                status = GymStatus.TOKEN_SAVE;
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
                status = GymStatus.SAVE_FAIL;
                return false;
            }
        }
        rememberSyncRequest(replayKey);
        rememberSyncRevision(safeMessage, bindingSource);

        // Language is independent of plan replacement and is safe to apply while
        // a workout is active. The plan itself remains deferred until the set list
        // is idle, but EN/UK/RU changes immediately and durably with this sync.
        applyValidatedLanguage(safeMessage);

        if (sets.size() > 0 || GymSession.recording || hasUnfinishedWorkout()) {
            // The watch polls the phone during every workout. An unchanged plan
            // must advance its replay fence without retaining another complete
            // set of plan-name/weight/reps arrays beside the active history.
            if (syncPlanMatchesCurrentState(safeMessage)) {
                // A newer revision that returns to the active plan supersedes
                // any older genuinely different plan waiting for workout end.
                deferredSync = null;
                status = GymStatus.SYNC_OK;
                if (save()) {
                    clearSyncStageIfMatches(safeMessage, bindingSource);
                    return true;
                }
                load();
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            // Reuse the current identical picker catalog instead of retaining a
            // second array for the lifetime of the active workout.
            var incomingExercises = safeMessage.get("exercises");
            if (incomingExercises instanceof Lang.Array &&
                sameTextArray(incomingExercises, exercises)) {
                safeMessage.put("exercises", null);
            }
            deferredSync = safeMessage;
            status = GymStatus.PLAN_WAIT;
            if (save()) {
                clearSyncStageIfMatches(safeMessage, bindingSource);
                return true;
            }
            load();
            status = GymStatus.SAVE_FAIL;
            return false;
        }

        applyValidatedSync(safeMessage);
        if (save()) {
            clearSyncStageIfMatches(safeMessage, bindingSource);
            return true;
        }
        load();
        status = GymStatus.SAVE_FAIL;
        return false;
    }

    (:compactLegacyState)
    static function applySyncFromSource(message, bindingSource) {
        if (GymLocalWorkout.blocksPairing()) {
            status = GymStatus.DATA_KEPT;
            return false;
        }
        if (!bindingSource.equals("phone") ||
            !isValidSyncMessage(message, bindingSource)) {
            status = GymStatus.BAD_SYNC;
            return false;
        }
        var safeMessage = normalizedSyncMessage(message, bindingSource);
        var nextAccount = safeMessage.get("accountBinding");
        var nextDevice = safeMessage.get("deviceBinding");
        var nextGeneration = safeMessage.get("pairingGeneration");
        var resetValue = safeMessage.get("resetWorkout");
        var resetWorkout = resetValue instanceof Lang.Boolean && resetValue;
        var repairValue = safeMessage.get("repairPairing");
        var repairPairing = repairValue instanceof Lang.Boolean && repairValue;
        var accountChanged = accountBinding == null ||
            !accountBinding.equals(nextAccount);

        if ((accountBinding != null && accountChanged && !resetWorkout) ||
            (deviceBinding != null && !deviceBinding.equals(nextDevice))) {
            status = GymStatus.BAD_BIND;
            return false;
        }
        if (isValidAccountBinding(pairingGeneration) &&
            (!isValidAccountBinding(nextGeneration) ||
                (!pairingGeneration.equals(nextGeneration.toString()) &&
                    !resetWorkout && !repairPairing))) {
            status = GymStatus.PAIR_OLD;
            return false;
        }
        var revisionStatus = syncRevisionStatus(safeMessage, bindingSource);
        if (revisionStatus < 0) {
            status = GymStatus.SYNC_OLD;
            return false;
        }
        if (revisionStatus == 0) {
            if (isExactStagedSync(safeMessage, bindingSource) &&
                !syncBindingsMatch(safeMessage)) {
                // A committed fence with an incomplete owner transition is the
                // only exact replay allowed to run destructively. Once bindings
                // match, the same reset is a no-op and cannot erase a workout
                // started after the successful reset.
                revisionStatus = 1;
            } else {
                status = GymStatus.SYNC_DUP;
                clearSyncStageIfMatches(safeMessage, bindingSource);
                return true;
            }
        }
        // Keep already-persisted stages recoverable at the legacy wire limit;
        // only newly received phone plans are subject to the current 30-set cap.
        var incomingPlanNames = safeMessage.get("planNames");
        if (!isExactStagedSync(safeMessage, bindingSource) &&
            incomingPlanNames instanceof Lang.Array &&
            incomingPlanNames.size() > maxNewWorkoutSets) {
            status = GymStatus.BAD_SYNC;
            return false;
        }
        var pairingGenerationChanges =
            !sameOptionalText(pairingGeneration, nextGeneration);
        if (pairingGenerationChanges && !accountChanged && !resetWorkout &&
            (sets.size() > 0 || GymSession.recording || hasUnfinishedWorkout() ||
                preparedWorkout != null)) {
            status = GymStatus.PAIR_WAIT;
            return false;
        }
        if (pairingGenerationChanges && !accountChanged && !resetWorkout && !restorePendingForMutation()) {
            status = GymStatus.DATA_KEPT; return false;
        }
        if (!stageSync(safeMessage, bindingSource)) {
            status = GymStatus.SAVE_FAIL;
            return false;
        }
        if (accountChanged || resetWorkout) {
            if ((legacyUnboundState &&
                    (!ensureLegacyQuarantine() || !refreshLegacyCurrentQuarantine())) ||
                !beginAccountTransition() ||
                !clearCloudSyncStageForAccountTransition() ||
                !GymComm.reconcileCloudDeviceToken(nextAccount)) {
                status = GymStatus.SAVE_FAIL;
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
            status = GymStatus.SAVE_FAIL;
            return false;
        }
        rememberSyncRequest("phone:" + safeMessage.get("requestId"));
        rememberSyncRevision(safeMessage, bindingSource);
        applyValidatedLanguage(safeMessage);
        if (sets.size() > 0 || GymSession.recording || hasUnfinishedWorkout()) {
            if (syncPlanMatchesCurrentState(safeMessage)) {
                deferredSync = null;
                status = GymStatus.SYNC_OK;
                if (save()) {
                    clearSyncStageIfMatches(safeMessage, bindingSource);
                    return true;
                }
                load();
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            var incomingExercises = safeMessage.get("exercises");
            if (incomingExercises instanceof Lang.Array &&
                sameTextArray(incomingExercises, exercises)) {
                safeMessage.put("exercises", null);
            }
            deferredSync = safeMessage;
            status = GymStatus.PLAN_WAIT;
        } else {
            applyValidatedSync(safeMessage);
        }
        if (save()) {
            clearSyncStageIfMatches(safeMessage, bindingSource);
            return true;
        }
        load();
        status = GymStatus.SAVE_FAIL;
        return false;
    }

    (:richWorkoutMode)
    static function applyValidatedSync(message) {
        applyValidatedLanguage(message);
        var flatNames = message.get("planNames");
        var flatWeights = message.get("planWeights");
        var flatReps = message.get("planReps");
        if (flatNames.size() > 0) {
            if (!keepsSetDiagnostics) {
                // The validated phone columns are already the V5 storage shape.
                // Keep them directly; GymPlanList creates only a cached row on access.
                plan = new GymPlanList([5, flatNames, flatWeights, flatReps]);
                persistedPlanSource = null;
                persistedPlanBytes = 0;
                persistedPlanNeedsV5Write = false;
            } else {
                var flatPlan = [];
                for (var f = 0; f < flatNames.size(); f += 1) {
                    flatPlan.add(syncedPlanRow(
                        flatNames[f].toString(), flatWeights[f], flatReps[f]
                    ));
                }
                plan = flatPlan;
            }
        } else if (sourceForMessage(message).equals("cloud")) {
            if (!keepsSetDiagnostics) {
                persistedPlanSource = null;
                persistedPlanBytes = 0;
                persistedPlanNeedsV5Write = false;
            }
            plan = [];
        }
        // Keep plan names first, then fill the picker from the synced catalog or
        // the current catalog. This preserves targets even when the picker is full.
        var availableExercises = [];
        var nameBytes = 0;
        for (var p = 0; p < plan.size(); p += 1) {
            var name = GymPlanAccess.nameAt(plan, p).toString();
            if (!containsName(availableExercises, name)) {
                availableExercises.add(name);
                nameBytes += utf8Bytes(name).size();
            }
        }
        var syncedExercises = message.get("exercises");
        var extraExercises = syncedExercises instanceof Lang.Array &&
            syncedExercises.size() > 0 ? syncedExercises : exercises;
        for (var e = 0; e < extraExercises.size() &&
            availableExercises.size() < maxPlanSets; e += 1) {
            var extraName = extraExercises[e].toString();
            if (!containsName(availableExercises, extraName)) {
                var extraBytes = utf8Bytes(extraName).size();
                if (nameBytes + extraBytes <= maxTotalNameBytes) {
                    availableExercises.add(extraName);
                    nameBytes += extraBytes;
                }
            }
        }
        if (availableExercises.size() > 0) {
            exercises = availableExercises;
            exerciseCatalogNeedsWrite = true;
            exerciseIndex = 0;
            if (plan.size() > 0) { applyCurrentPlanSet(); }
        }
        status = plan.size() > 0 ? "PLAN " + plan.size().toString() :
            (exercises.size() > 0 ? "EX " + exercises.size().toString() : GymStatus.EMPTY_PLAN);
        return true;
    }

    static function applyValidatedLanguage(message) {
        var syncedLanguage = message.get("language");
        if (syncedLanguage != null) {
            language = normalizedLanguage(syncedLanguage.toString());
        }
    }

    (:richWorkoutMode)
    static function syncPlanMatchesCurrentState(message) {
        var names = message.get("planNames");
        var weights = message.get("planWeights");
        var setReps = message.get("planReps");
        if (!(names instanceof Lang.Array) || !(weights instanceof Lang.Array) ||
            !(setReps instanceof Lang.Array) || names.size() != plan.size() ||
            weights.size() != plan.size() || setReps.size() != plan.size()) {
            return false;
        }
        for (var i = 0; i < plan.size(); i += 1) {
            var item = GymPlanAccess.at(plan, i);
            if (!(isSetRecord(item)) ||
                !setField(item, "exerciseName").toString().equals(names[i].toString()) ||
                (setField(item, "weight") as Lang.Numeric).toDouble() !=
                    (weights[i] as Lang.Numeric).toDouble() ||
                (setField(item, "reps") as Lang.Numeric).toLong() !=
                    (setReps[i] as Lang.Numeric).toLong()) {
                return false;
            }
        }
        var incomingExercises = message.get("exercises");
        return incomingExercises == null || sameTextArray(incomingExercises, exercises);
    }

    (:richWorkoutMode)
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

    (:compactWorkoutMode96)
    static function applyDeferredSyncIfIdle() { return; }

    // A 96 KiB watch keeps no plan. The pairing and language fields of a
    // validated sync are applied by applySyncFromSource; the plan columns and
    // catalog were already dropped by GymApp.handleSyncMessage.
    (:compactWorkoutMode96, :inline)
    static function applyValidatedSync(message) {
        status = GymStatus.SYNC_OK;
        return true;
    }

    (:compactWorkoutMode96, :inline)
    static function syncPlanMatchesCurrentState(message) { return true; }

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
        if (!isValidPlanColumns(flatNames, flatWeights, flatReps, maxPlanSets)) {
            return false;
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
                (!syncedLanguage.equals("en") && !syncedLanguage.equals("uk") &&
                    !syncedLanguage.equals("ru")))) {
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
            !message.get("type").equals("sync") ||
            !isBoundedText(message.get("requestId"), maxBindingLength) ||
            !isBoundedText(message.get("syncId"), maxBindingLength) ||
            !message.get("requestId").equals(message.get("syncId")) ||
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
        if (!isValidPlanColumns(names, weights, setReps, maxPlanSets)) {
            return false;
        }
        var syncedExercises = message.get("exercises");
        if (syncedExercises != null &&
            !isValidExerciseList(syncedExercises, maxPlanSets)) {
            return false;
        }
        var syncedLanguage = message.get("language");
        if (syncedLanguage != null &&
            (!(syncedLanguage instanceof Lang.String) ||
                (!syncedLanguage.equals("en") &&
                    !syncedLanguage.equals("uk") &&
                    !syncedLanguage.equals("ru")))) {
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

    (:inline)
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

    (:fullLegacyState, :inline)
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

    (:compactLegacyState, :inline)
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
            "syncId" => message.get("syncId"),
            "requestId" => message.get("requestId"),
            "bindingSource" => trustedSource,
            "accountBinding" => message.get("accountBinding"),
            "deviceBinding" => message.get("deviceBinding"),
            "planNames" => copySyncArray(message.get("planNames")),
            "planWeights" => copySyncArray(message.get("planWeights")),
            "planReps" => copySyncArray(message.get("planReps"))
        };
        if (trustedSource.equals("cloud")) {
            normalized.put("planId", message.get("planId"));
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
            "syncId" => message.get("syncId"),
            "requestId" => message.get("requestId"),
            "bindingSource" => "phone",
            "accountBinding" => message.get("accountBinding"),
            "deviceBinding" => message.get("deviceBinding"),
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

    (:inline)
    static function copyOptionalAccountBinding(target, source, key) {
        var value = source.get(key);
        if (isValidAccountBinding(value)) {
            target.put(key, value.toString());
        }
    }

    static function copySyncArray(source) {
        return source.slice(null, null);
    }

    static function hasAccountBinding() {
        return isValidAccountBinding(accountBinding) &&
            isValidAccountBinding(stateOwnerBinding) &&
            accountBinding.equals(stateOwnerBinding) &&
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
            !accountBinding.equals(messageAccount) ||
            !deviceBinding.equals(messageDevice)) {
            return false;
        }
        var messageGeneration = message.get("pairingGeneration");
        if (isValidAccountBinding(pairingGeneration)) {
            return isValidAccountBinding(messageGeneration) &&
                pairingGeneration.equals(messageGeneration);
        }
        return messageGeneration == null;
    }

    static function syncBindingsMatch(message) {
        if (!(message instanceof Lang.Dictionary) || !isValidAccountBinding(accountBinding) ||
            !isValidAccountBinding(stateOwnerBinding) ||
            !accountBinding.equals(stateOwnerBinding)) {
            return false;
        }
        var messageAccount = message.get("accountBinding");
        var messageDevice = message.get("deviceBinding");
        var sourceValue = message.get("bindingSource");
        var source = sourceValue == null ? "phone" : sourceValue.toString();
        if (!isValidAccountBinding(messageAccount) ||
            !accountBinding.equals(messageAccount) ||
            !isBoundedText(messageDevice, maxBindingLength)) {
            return false;
        }
        if (source.equals("cloud")) {
            return isBoundedText(cloudDeviceBinding, maxBindingLength) &&
                cloudDeviceBinding.equals(messageDevice);
        }
        if (!isBoundedText(deviceBinding, maxBindingLength) ||
            !deviceBinding.equals(messageDevice)) {
            return false;
        }
        var messageGeneration = message.get("pairingGeneration");
        if (isValidAccountBinding(pairingGeneration)) {
            return isValidAccountBinding(messageGeneration) &&
                pairingGeneration.equals(messageGeneration);
        }
        return messageGeneration == null;
    }

    static function pendingCount() {
        return (parkedPending == null ? pending.size() : parkedPending[0].size()) + GymPendingJournal.entries.size();
    }

    // A legacy queue is already durable and immutable during a live workout.
    // Retain only its bounded identity and budget until it is actually needed.
    (:richWorkoutMode, :inline)
    private static function parkPendingForSnapshot(value) {
        if (!(value instanceof Lang.Array) || value.size() < 6) { return; }
        parkPendingDuringLongWorkout(value[5] instanceof Lang.Array ? value[5].size() : value[5]);
    }

    (:richWorkoutMode)
    static function parkPendingDuringLongWorkout(count) {
        if (!isBoundedInteger(count, 0, maxWorkoutSets) ||
            (GymWorkoutMode.recordingSetLimit != 30 && count < 15) ||
            pending.size() == 0 || parkedPending != null) { return; }
        var ids = []; var origins = []; var names = 0;
        for (var i = 0; i < pending.size(); i += 1) {
            if (!bindingsMatch(pending[i])) { return; }
            ids.add(pending[i]["requestId"]); origins.add(pending[i]["startedAtSeconds"]);
            names += setListNameBytes(pending[i]["sets"]);
        }
        parkedPending = [ids, estimatedPendingBytes(), names, origins];
        pending = []; pendingEstimateSource = null;
    }

    (:compactCheckpoint96)
    static function parkPendingDuringLongWorkout(count) {
        if (!isBoundedInteger(count, 0, maxWorkoutSets) ||
            pending.size() == 0 || parkedPending != null ||
            stagedPairingRecoveryTarget() != null) { return; }
        var ids = []; var origins = []; var names = 0;
        for (var i = 0; i < pending.size(); i += 1) {
            if (!bindingsMatch(pending[i])) { return; }
            ids.add(pending[i]["requestId"]); origins.add(pending[i]["startedAtSeconds"]);
            names += setListNameBytes(pending[i]["sets"]);
        }
        parkedPending = [ids, estimatedPendingBytes(), names, origins];
        pending = []; pendingEstimateSource = null;
    }

    static function restorePendingForMutation() {
        if (parkedPending == null) { return true; }
        if (sets.size() > 14) { return false; }
        try {
            var saved = Storage.getValue("pending");
            if (!isValidPendingList(saved) || saved.size() != parkedPending[0].size()) { return false; }
            for (var i = 0; i < saved.size(); i += 1) {
                if (!bindingsMatch(saved[i]) ||
                    !(saved[i] as Lang.Dictionary)["requestId"].equals(parkedPending[0][i])) { return false; }
            }
            pending = saved; parkedPending = null; pendingEstimateSource = null;
            return true;
        } catch (e) { return false; }
    }

    (:inline)
    static function legacyPendingNameBytes() {
        if (parkedPending != null) { return parkedPending[2]; }
        var bytes = 0;
        for (var i = 0; i < pending.size(); i += 1) { bytes += setListNameBytes(pending[i]["sets"]); }
        return bytes;
    }

    private static function parkedPendingOrigin(requestId) {
        if (parkedPending == null) { return null; }
        for (var i = 0; i < parkedPending[0].size(); i += 1) {
            if (parkedPending[0][i].equals(requestId)) { return parkedPending[3][i]; }
        }
        return null;
    }

    static function removePendingByRequestId(requestId) {
        // An ACK must never win the marker -> pending -> active tombstone
        // transaction. If finalization still fails, retain the queue head.
        if (!recoverQueuedWorkout() ||
            !isBoundedText(requestId, maxBindingLength) || pendingCount() == 0) {
            return false;
        }
        if (!restorePendingForMutation()) { return false; }
        if (exercises.size() == 0) { return removeAckedAfterRelease(requestId); }
        if (pending.size() == 0) {
            if (!GymPendingJournal.remove(requestId)) { return false; }
            lastWorkoutSyncAtSeconds = Time.now().value();
            save();
            return true;
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
        pendingEstimateSource = null;
        pending.remove(item);
        lastWorkoutSyncAtSeconds = Time.now().value();
        if (save()) {
            return true;
        }
        load();
        return false;
    }

    // A durable finish releases the plan and catalog, so save() would fail
    // there and trigger load(). Such an ack rewrites only the queue head and
    // the last sync time, and an unwritable queue is left to resend.
    private static function removeAckedAfterRelease(requestId) {
        if (pending.size() == 0) {
            if (!GymPendingJournal.remove(requestId)) { return false; }
        } else {
            var item = pending[0];
            if (!(item instanceof Lang.Dictionary) ||
                !requestId.toString().equals(item.get("requestId"))) { return false; }
            var rest = pending.slice(1, null);
            try { Storage.setValue("pending", rest); } catch (e) { return false; }
            pendingEstimateSource = null; pending = rest;
        }
        lastWorkoutSyncAtSeconds = Time.now().value();
        try {
            Storage.setValue("lastWorkoutSyncV1", [1, accountBinding, lastWorkoutSyncAtSeconds]);
        } catch (e) { }
        return true;
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
                !accountBinding.equals(item.get("accountBinding")) ||
                !deviceBinding.equals(item.get("deviceBinding"))) {
                return false;
            }
        }
        for (var j = 0; j < pending.size(); j += 1) {
            pendingEstimateSource = null;
            pending[j].put("pairingGeneration", nextGeneration.toString());
        }
        return isValidPendingList(pending) && GymPendingJournal.rotate(previousGeneration, nextGeneration);
    }

    (:inline)
    static function queueWorkout(message) {
        if (!appendWorkout(message)) {
            return false;
        }
        if (!recoverQueuedWorkout()) {
            status = GymStatus.QUEUED_SAFE;
            return false;
        }
        status = GymStatus.QUEUED;
        return true;
    }

    // Save callbacks can yield after the durable append. The prepared marker
    // keeps this item unsendable until recoverQueuedWorkout commits cleanup.
    static function appendWorkout(message) {
        if (!isValidWorkoutMessage(message) || !bindingsMatch(message)) {
            return false;
        }
        if (!restorePendingForMutation()) { return false; }
        var requestId = message.get("requestId");
        var alreadyQueued = false;
        for (var i = 0; i < pending.size(); i += 1) {
            var queuedItem = pending[i];
            if (queuedItem instanceof Lang.Dictionary &&
                isBoundedText(queuedItem.get("requestId"), maxBindingLength) &&
                queuedItem.get("requestId").equals(requestId)) {
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
                status = GymStatus.SYNC_FULL;
                return false;
            }
            var nextPending = pending.slice(null, null);
            nextPending.add(message);

            var previousPending = pending;
            var withinBudget = false;
            try {
                pending = nextPending;
                pendingEstimateSource = null;
                withinBudget = isWithinStorageBudget();
            } catch (e) {
                withinBudget = false;
            }
            pending = previousPending;
            pendingEstimateSource = null;
            if (!withinBudget) {
                status = GymStatus.QUEUE_FULL;
                return false;
            }

            try {
                // The marker is written first and the queue second. Nothing may
                // send this request until recoverQueuedWorkout commits the empty
                // active snapshot and clears the prepared state.
                Storage.setValue("queuedActiveRequestId", requestId);
                Storage.setValue("pending", nextPending);
            } catch (e) {
                status = GymStatus.SAVE_FAIL;
                return false;
            }
            pending = nextPending;
            pendingEstimateSource = null;
        }

        status = GymStatus.QUEUED_SAFE;
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
            if (GymPendingJournal.contains(preparedId) || (parkedPendingOrigin(preparedId) != null)) { marker = preparedId; }
            for (var p = 0; p < pending.size(); p += 1) {
                var preparedItem = pending[p];
                if (preparedItem instanceof Lang.Dictionary &&
                    isValidWorkoutMessage(preparedItem) &&
                    bindingsMatch(preparedItem) &&
                    preparedItem.get("requestId").equals(preparedId)) {
                    marker = preparedId;
                    break;
                }
            }
        }
        if (!isBoundedText(marker, maxBindingLength)) {
            return true;
        }
        var queuedOrigin = GymPendingJournal.origin(marker);
        if (queuedOrigin == null) { queuedOrigin = parkedPendingOrigin(marker); }
        var queued = queuedOrigin != null;
        for (var i = 0; i < pending.size(); i += 1) {
            var item = pending[i];
            if (item instanceof Lang.Dictionary &&
                isBoundedText(item.get("requestId"), maxBindingLength) &&
                item.get("requestId").equals(marker.toString())) {
                queued = true; queuedOrigin = item.get("startedAtSeconds");
                break;
            }
        }
        var activeBelongsToMarker = preparedWorkout != null &&
            isValidPreparedWorkout(preparedWorkout) && activeWorkoutSnapshotMatchesBindings(preparedWorkout) &&
            preparedWorkout[4].equals(marker) && activeWorkoutStartedAtSeconds == queuedOrigin;
        // A failed marker deletion must never erase a newer active workout on
        // the next launch. Only the matching prepared transaction owns cleanup.
        if (queued && (!hasUnfinishedWorkout() || activeBelongsToMarker)) {
            if (hasAccountBinding() && !persistEmptyActiveWorkoutSnapshot()) {
                return false;
            }
            sets = [];
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
        if (queued && !activeBelongsToMarker) { clearPreparedWorkout(marker); }
        try {
            Storage.deleteValue("queuedActiveRequestId");
        } catch (e) {
            // A later retry still compares the marker with the active transaction.
        }
        return true;
    }

    (:inline)
    static function beginAccountTransition() {
        validatedBindingA = null;
        validatedBindingB = null;
        pendingEstimateSource = null;
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

    (:inline)
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

    (:richWorkoutMode, :inline)
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
        parkedPending = null;
        GymPendingJournal.clear();
        GymActiveJournal.clear();
        validatedBindingA = null;
        validatedBindingB = null;
        try {
            // Invalid/missing ownership never restores this value, but remove the
            // account-bound wearable cache as well so a later lifecycle cannot revive
            // stale data even if durable owner metadata is externally repaired.
            Storage.deleteValue("activeWorkoutV1");
            Storage.deleteValue("activeRuntimeV1");
            Storage.deleteValue("activeWorkoutModeV1");
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
        if (!keepsSetDiagnostics) {
            // Force save() to publish the empty plan before the new owner marker.
            persistedPlanSource = null;
            persistedPlanBytes = 0;
            persistedPlanNeedsV5Write = false;
        }
        GymWorkoutMode.clear();
        pending = [];
        pendingEstimateSource = null;
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
        exerciseCatalogNeedsWrite = true;
        exerciseCatalogRepairRequired = false;
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
            !isValidLiveSetList(sets, maxWorkoutSets, true) ||
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
        exerciseCatalogNeedsWrite = true;
        sets = normalizedSetList(snapshot.get("sets"));
        clearTransientSetActions();
        plan = normalizedSetList(snapshot.get("plan"));
        pending = normalizedLegacyPendingList(snapshot.get("pending"));
        pendingEstimateSource = null;
        weight = setField(snapshot, "weight");
        reps = setField(snapshot, "reps");
        weightStep = snapshot.get("weightStep");
        restSecondsDefault = snapshot.get("restSecondsDefault");
        autoPromptEnabled = snapshot.get("autoPromptEnabled");
        sensitivityIndex = snapshot.get("sensitivityIndex");
        language = snapshot.get("language");
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
            !isValidWeight(setField(value, "weight")) || !isValidReps(setField(value, "reps")) ||
            !isValidLegacyQuarantineSettings(value) ||
            !(value.get("autoPromptEnabled") instanceof Lang.Boolean) ||
            !isBoundedText(value.get("language"), 2) ||
            (value.get("activeWorkoutStartedAtSeconds") != null &&
                (!isValidWorkoutStartedAtSeconds(value.get("activeWorkoutStartedAtSeconds")) ||
                    setListCount(value.get("sets")) == 0))) {
            return false;
        }
        var savedLanguage = value.get("language");
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
            var item = GymSetAccess.at(source, i);
            var normalized = {
                "exerciseName" => setField(item, "exerciseName").toString(),
                "weight" => setField(item, "weight"),
                "reps" => setField(item, "reps")
            };
            copyOptionalSetMetrics(normalized, item);
            copy.add(normalized);
        }
        return copy;
    }

    static function compactSetMetrics(source) {
        var startHeartRate = setField(source, "startHeartRate");
        var peakHeartRate = setField(source, "peakHeartRate");
        var endHeartRate = setField(source, "endHeartRate");
        if (startHeartRate != null &&
            (peakHeartRate == null || startHeartRate > peakHeartRate)) {
            peakHeartRate = startHeartRate;
        }
        if (endHeartRate != null &&
            (peakHeartRate == null || endHeartRate > peakHeartRate)) {
            peakHeartRate = endHeartRate;
        }
        return [
            setField(source, "activeSeconds"),
            setField(source, "restBeforeSeconds"),
            startHeartRate,
            peakHeartRate,
            endHeartRate,
            setField(source, "recoveryHeartRateDrop"),
            setField(source, "detectionConfidence")
        ];
    }

    static function copySetInterval(source) {
        return source.slice(null, null);
    }

    (:inline)
    static function copyOptionalSetMetrics(target, source) {
        var keys = [
            "activeSeconds", "restBeforeSeconds", "startHeartRate", "peakHeartRate",
            "endHeartRate", "recoveryHeartRateDrop", "detectionConfidence"
        ];
        for (var i = 0; i < keys.size(); i += 1) {
            var value = setField(source, keys[i]);
            if (value != null) {
                target.put(keys[i], value);
            }
        }
        var setInterval = setField(source, "setInterval");
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

    static function stagedPairingRecoveryTarget() {
        var message = stagedPhoneSyncMessage;
        if (!(message instanceof Lang.Dictionary) || !hasAccountBinding() ||
            syncRevisionStatus(message, "phone") < 0 ||
            !accountBinding.equals(message.get("accountBinding")) ||
            !deviceBinding.equals(message.get("deviceBinding")) ||
            message.get("resetWorkout") == true ||
            !isValidAccountBinding(message.get("pairingGeneration"))) {
            return null;
        }
        var nextGeneration = message.get("pairingGeneration");
        var repair = message.get("repairPairing") == true;
        if (isValidAccountBinding(pairingGeneration)) {
            if (pairingGeneration.equals(nextGeneration)) {
                return null;
            }
            return repair ? nextGeneration : null;
        }
        return repair ? null : nextGeneration;
    }

    (:inline)
    static function loadSyncStage(source) {
        if (!keepsSetDiagnostics && !source.equals("phone")) { return; }
        var key = (keepsSetDiagnostics && source.equals("cloud")) ? "cloudSyncStage" : "phoneSyncStage";
        var maximum = (keepsSetDiagnostics && source.equals("cloud")) ? maxCloudPlanRevision : maxPhoneSyncRevision;
        var stage = Storage.getValue(key);
        if (stage instanceof Lang.Dictionary && isValidSyncStage(stage, maximum, source)) {
            var stagedMessage = normalizedSyncMessage(stage.get("message"), source);
            if ((keepsSetDiagnostics && source.equals("cloud"))) {
                stagedCloudPlanRevision = stage.get("revision").toNumber();
                stagedCloudPlanId = stage.get("id");
                stagedCloudAccountBinding = stage.get("accountBinding");
                stagedCloudSyncMessage = stagedMessage;
            } else {
                stagedPhoneSyncRevision = stage.get("revision").toLong();
                stagedPhoneSyncId = stage.get("id");
                stagedPhoneAccountBinding = stage.get("accountBinding");
                stagedPhoneSyncMessage = stagedMessage;
            }
            return;
        }
        if ((keepsSetDiagnostics && source.equals("cloud"))) {
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

    (:inline)
    static function stageSync(message, source) {
        if (!keepsSetDiagnostics && !source.equals("phone")) { return false; }
        // Both call sites pass a freshly normalized, fully validated dictionary;
        // rebuilding it here used to duplicate every plan/catalog array.
        var revision = (keepsSetDiagnostics && source.equals("cloud")) ?
            message.get("planRevision") : message.get("syncRevision");
        var stage = {
            "revision" => revision,
            "id" => message.get("requestId"),
            "accountBinding" => message.get("accountBinding"),
            "message" => message
        };
        if (estimatedValueBytes(stage) > maxLegacyStoredValueBytes) {
            return false;
        }
        try {
            Storage.setValue((keepsSetDiagnostics && source.equals("cloud")) ? "cloudSyncStage" : "phoneSyncStage", stage);
            if ((keepsSetDiagnostics && source.equals("cloud"))) {
                stagedCloudPlanRevision = revision.toNumber();
                stagedCloudPlanId = message.get("requestId");
                stagedCloudAccountBinding = message.get("accountBinding");
                stagedCloudSyncMessage = message;
            } else {
                stagedPhoneSyncRevision = revision.toLong();
                stagedPhoneSyncId = message.get("requestId");
                stagedPhoneAccountBinding = message.get("accountBinding");
                stagedPhoneSyncMessage = message;
            }
            return true;
        } catch (e) {
            return false;
        }
    }

    (:inline)
    static function clearSyncStage(source) {
        if (!keepsSetDiagnostics && !source.equals("phone")) { return; }
        try {
            Storage.deleteValue((keepsSetDiagnostics && source.equals("cloud")) ? "cloudSyncStage" : "phoneSyncStage");
            if ((keepsSetDiagnostics && source.equals("cloud"))) {
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
        if (!keepsSetDiagnostics && !source.equals("phone")) { return false; }
        var revision = (keepsSetDiagnostics && source.equals("cloud")) ?
            message.get("planRevision").toNumber() : message.get("syncRevision").toLong();
        var requestId = message.get("requestId");
        var messageAccount = message.get("accountBinding");
        if ((keepsSetDiagnostics && source.equals("cloud"))) {
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
        if (!keepsSetDiagnostics && !source.equals("phone")) { return false; }
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
        if ((keepsSetDiagnostics && source.equals("cloud"))) {
            return sameOptionalText(left.get("planId"), right.get("planId")) &&
                left.get("planRevision").toLong() == right.get("planRevision").toLong();
        }
        var leftExercises = left.get("exercises");
        var rightExercises = right.get("exercises");
        var exercisesMatch = (leftExercises == null || rightExercises == null) ?
            leftExercises == null && rightExercises == null :
            sameTextArray(leftExercises, rightExercises);
        return left.get("syncRevision").toLong() == right.get("syncRevision").toLong() &&
            sameOptionalText(left.get("pairingGeneration"), right.get("pairingGeneration")) &&
            sameOptionalBoolean(left.get("repairPairing"), right.get("repairPairing")) &&
            sameOptionalText(left.get("language"), right.get("language")) &&
            exercisesMatch;
    }

    static function sameOptionalText(left, right) {
        if (left == null || right == null) {
            return left == null && right == null;
        }
        return left instanceof Lang.String && right instanceof Lang.String &&
            left.equals(right);
    }

    static function sameOptionalBoolean(left, right) {
        if (left == null || right == null) {
            return left == null && right == null;
        }
        return left instanceof Lang.Boolean && right instanceof Lang.Boolean && left == right;
    }

    static function sameTextArray(left, right) {
        if (!(left instanceof Lang.Array) || !(right instanceof Lang.Array) ||
            left.size() != right.size()) {
            return false;
        }
        for (var i = 0; i < left.size(); i += 1) {
            if (!(left[i] instanceof Lang.String) || !(right[i] instanceof Lang.String) ||
                !left[i].equals(right[i])) {
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
                if ((left[i] as Lang.Numeric).toDouble() !=
                    (right[i] as Lang.Numeric).toDouble()) {
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
        if (!keepsSetDiagnostics && !source.equals("phone")) { return -1; }
        var requestId = message.get("requestId");
        var messageAccount = message.get("accountBinding");
        if ((keepsSetDiagnostics && source.equals("cloud"))) {
            var cloudRevision = message.get("planRevision").toNumber();
            if (cloudRevision < lastCloudPlanRevision) {
                return -1;
            }
            if (cloudRevision == lastCloudPlanRevision) {
                return lastCloudPlanId != null && lastCloudPlanId.toString().equals(
                    message.get("planId")
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

    (:inline)
    static function rememberSyncRevision(message, source) {
        if (!keepsSetDiagnostics && !source.equals("phone")) { return; }
        if ((keepsSetDiagnostics && source.equals("cloud"))) {
            lastCloudPlanRevision = message.get("planRevision").toNumber();
            lastCloudPlanId = message.get("planId");
        } else {
            lastPhoneSyncRevision = message.get("syncRevision").toLong();
            lastPhoneSyncId = message.get("requestId");
            lastPhoneSyncAccountBinding = message.get("accountBinding");
        }
    }

    static function isWithinStorageBudget() {
        return isWithinStorageBudgetForActiveSnapshot(null);
    }

    static function isWithinStorageBudgetForActiveSnapshot(snapshot) {
        var estimate = 4096 + 2048;
        estimate += estimatedValueBytes(exercises);
        if (snapshot == null) {
            // A committed atomic snapshot already accounts for the active sets.
            // Legacy/ownerless state still budgets its separate set collection.
            if (!activeWorkoutSnapshotValid || !hasAccountBinding()) {
                estimate += estimatedValueBytes(sets);
            }
            estimate += estimatedValueBytes(activeWorkoutStartedAtSeconds);
        } else {
            estimate += estimatedActiveSnapshotBytes(snapshot);
            // Full-v3 snapshot[5] contains only names, so add the calibrated
            // downgrade-mirror cost. Compact-v3 snapshot[5] already is that mirror;
            // adding another 112 bytes per set would reject valid long workouts.
            if (snapshot[0] != 4 && snapshot[0] != 6) {
                estimate += 16 + estimatedValueBytes(snapshot[5]);
                if (snapshot.size() == 11) {
                    estimate += snapshot[5].size() * 112;
                }
            }
        }
        if (!keepsSetDiagnostics && plan == persistedPlanSource &&
            !persistedPlanNeedsV5Write) {
            estimate += persistedPlanBytes > 0 ? persistedPlanBytes : 0;
        } else {
            if (!keepsSetDiagnostics) {
                // The original plan key is replaced atomically, so budget the
                // next serialized value without constructing a second row list.
                if (GymPlanAccess.valid(plan, maxPlanSets, true)) {
                    estimate += estimatedValueBytes(plan.columns);
                } else if (isValidLiveSetList(plan, maxPlanSets, true)) {
                    // The validated dictionary fallback can contain legacy
                    // optional fields, which remain part of the stored value.
                    estimate += estimatedValueBytes(plan);
                } else {
                    return false;
                }
            } else {
                var planValue = storedPlan();
                if (planValue == null) { return false; }
                estimate += estimatedValueBytes(planValue);
            }
        }
        estimate += estimatedPendingBytes();
        estimate += GymPendingJournal.estimatedBytes();
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

    static function estimatedActiveSnapshotBytes(snapshot) {
        if (snapshot[0] == 6) {
            // The journal header is bounded independently of its rows. Budget
            // its exact bindings/checkpoint plus object-store framing, including
            // the empty commit which releases a completed workout.
            return 256 + estimatedValueBytes(snapshot) +
                (GymPendingJournal.pins(snapshot[6]) ? 0 : snapshot[5] * 160 + GymActiveJournal.stagingBytes);
        }
        if (!keepsSetDiagnostics && snapshot[0] == 4 && snapshot.size() == 10) {
            // Called after the complete v4 validator. Indexed names and bounded
            // numeric columns need at most 160 bytes per set, including its
            // ten-field interval. Reserve another KiB for bindings/checkpoint.
            // Avoid recursively serializing every old interval just to estimate
            // the next write; it can exhaust a compact watch's callback budget.
            return 1024 + snapshot[5].size() * 160;
        }
        return estimatedValueBytes(snapshot);
    }

    static function estimatedPendingBytes() {
        if (parkedPending != null) { return parkedPending[1]; }
        // Queue entries are immutable between their explicit append, ACK, and
        // pairing transitions. Those mutations invalidate this exact-list cache.
        // Rewalking every offline workout on each live set can trip the watchdog.
        if (pendingEstimateSource != pending) {
            pendingEstimateBytes = estimatedValueBytes(pending);
            pendingEstimateSource = pending;
        }
        return pendingEstimateBytes;
    }

    static function estimatedValueBytes(value) {
        return estimatedValueBytesAtDepth(value, 0);
    }

    static function estimatedValueBytesAtDepth(value, depth) {
        if (depth > 8) {
            return maxLegacyStoredValueBytes + 1;
        }
        if (value == null) {
            return 4;
        }
        if (value instanceof Lang.String) {
            return 2 + utf8Bytes(value.toString()).size();
        }
        if (value instanceof Lang.Boolean) {
            return value ? 4 : 5;
        }
        if (isNumeric(value)) {
            // A scalar conversion is bounded and short. Avoid converting the
            // entire snapshot, which was the large transient heap allocation.
            return value.toString().length();
        }
        // Walk bounded storage values incrementally instead of materializing one
        // giant String and a second giant UTF-8 array at peak snapshot heap use.
        var dictionary = value instanceof Lang.Dictionary;
        if (!(value instanceof Lang.Array) && !dictionary) {
            return maxLegacyStoredValueBytes + 1;
        }
        if (value.size() > 512) {
            return maxLegacyStoredValueBytes + 1;
        }
        var items = dictionary ? value.keys() : value;
        var bytes = 2;
        for (var i = 0; i < items.size(); i += 1) {
            if (i > 0) {
                bytes += 1;
            }
            if (dictionary) {
                var key = items[i];
                if (!(key instanceof Lang.String) || key.toString().length() > 64) {
                    return maxLegacyStoredValueBytes + 1;
                }
                bytes += 3 + utf8Bytes(key.toString()).size();
            }
            bytes += estimatedValueBytesAtDepth(
                dictionary ? value.get(items[i]) : items[i],
                depth + 1
            );
            if (bytes > maxLegacyStoredValueBytes) {
                return bytes;
            }
        }
        return bytes;
    }

    static function isValidCounter(value, maximum) {
        if (!(value instanceof Lang.Number) && !(value instanceof Lang.Long)) {
            return false;
        }
        var counter = value.toLong();
        return counter >= 1l && counter <= maximum.toLong();
    }

    (:inline)
    static function isValidSyncFence(value, maximum, maxIdLength) {
        return value instanceof Lang.Dictionary &&
            isValidCounter(value.get("revision"), maximum) &&
            isBoundedText(value.get("id"), maxIdLength);
    }

    (:inline)
    static function isValidPhoneSyncFence(value) {
        return isValidSyncFence(value, maxPhoneSyncRevision, maxBindingLength) &&
            isValidAccountBinding(value.get("accountBinding"));
    }

    (:inline)
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
            value.get("id").equals(message.get("requestId")) &&
            value.get("accountBinding").equals(
                message.get("accountBinding")
            );
    }

    static function pruneAccountScopedState() {
        var hasCloudBinding = isValidAccountBinding(accountBinding) &&
            isValidAccountBinding(stateOwnerBinding) &&
            accountBinding.equals(stateOwnerBinding) &&
            isBoundedText(cloudDeviceBinding, maxBindingLength);
        if (!hasAccountBinding()) {
            pending = [];
            pendingEstimateSource = null;
        } else {
            var stagedGeneration = stagedPairingRecoveryTarget();
            var safePending = [];
            for (var i = 0; i < pending.size(); i += 1) {
                var item = pending[i];
                var matchesStagedGeneration =
                    pendingMatchesStagedPairing(item, stagedGeneration);
                if (item instanceof Lang.Dictionary &&
                    (bindingsMatch(item) || matchesStagedGeneration)) {
                    safePending.add(item);
                }
            }
            pending = safePending;
            pendingEstimateSource = null;
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

    (:inline)
    static function pendingMatchesStagedPairing(item, stagedGeneration) {
        if (stagedGeneration == null || !(item instanceof Lang.Dictionary) ||
            !isValidWorkoutMessage(item)) {
            return false;
        }
        return accountBinding.equals(
                item.get("accountBinding")) &&
            deviceBinding.equals(
                item.get("deviceBinding")) &&
            sameOptionalText(stagedGeneration, item.get("pairingGeneration"));
    }

    static function nextRequestId(prefix) {
        requestCounter = (requestCounter + 1) % 100000;
        return prefix + "-" + Time.now().value().toString() + "-" +
            System.getTimer().toString() + "-" + requestCounter.toString();
    }

    (:inline)
    static function rememberSyncRequest(replayKey) {
        processedSyncIds.add(replayKey);
        while (processedSyncIds.size() > 32) {
            processedSyncIds.remove(processedSyncIds[0]);
        }
    }

    // ByteArray uses one byte per UTF-8 byte. A Lang.Array stores a boxed
    // Number slot for each byte and can exhaust the small watch heap while
    // validating an otherwise valid multilingual exercise name.
    static function utf8Bytes(value as Lang.String) as Lang.ByteArray {
        return Toybox.StringUtil.convertEncodedString(value, {
            :fromRepresentation => Toybox.StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :toRepresentation => Toybox.StringUtil.REPRESENTATION_BYTE_ARRAY,
            :encoding => Toybox.StringUtil.CHAR_ENCODING_UTF8
        }) as Lang.ByteArray;
    }

    static function isBoundedText(value, maxLength) {
        if (!(value instanceof Lang.String)) {
            return false;
        }
        return value.length() > 0 && value.length() <= maxLength;
    }

    static function isValidExerciseName(value) {
        return isBoundedText(value, maxExerciseNameLength) &&
            utf8Bytes(value).size() <= maxExerciseNameBytes;
    }

    static function isValidAccountBinding(value) {
        if (!(value instanceof Lang.String) || value.length() != 64) {
            return false;
        }
        if (value.equals(validatedBindingA) || value.equals(validatedBindingB)) {
            return true;
        }
        var bytes = utf8Bytes(value);
        for (var i = 0; i < bytes.size(); i += 1) {
            var code = bytes[i];
            if (!((code >= 48 && code <= 57) || (code >= 97 && code <= 102))) {
                return false;
            }
        }
        validatedBindingB = validatedBindingA;
        validatedBindingA = value;
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
    static function isValidLegacyQuarantineSettings(value) {
        var step = value.get("weightStep");
        var rest = value.get("restSecondsDefault");
        var sensitivity = value.get("sensitivityIndex");
        if (!isNumeric(step) || !(rest instanceof Lang.Number) ||
            !(sensitivity instanceof Lang.Number)) {
            return false;
        }
        var numeric = step.toFloat();
        var restValue = rest.toNumber();
        var sensitivityValue = sensitivity.toNumber();
        return numeric == numeric && numeric > 0.0 && numeric <= 100.0 &&
            restValue >= 1 && restValue <= 3600 &&
            sensitivityValue >= 0 && sensitivityValue <= 2;
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
            totalNameBytes += utf8Bytes(value[i].toString()).size();
            if (totalNameBytes > maxTotalNameBytes) {
                return false;
            }
        }
        return true;
    }

    static function isValidPlanColumns(names, weights, setReps, maximum) {
        if (!(names instanceof Lang.Array) || !(weights instanceof Lang.Array) ||
            !(setReps instanceof Lang.Array) || weights.size() != names.size() ||
            setReps.size() != names.size() ||
            !isValidExerciseList(names, maximum)) {
            return false;
        }
        for (var i = 0; i < names.size(); i += 1) {
            if (!isValidWeight(weights[i]) || !isValidReps(setReps[i])) {
                return false;
            }
        }
        return true;
    }

    (:fullLegacyState)
    static function isSetRecord(value) {
        return value instanceof Lang.Dictionary;
    }

    (:compactLegacyState)
    static function isSetRecord(value) {
        return value instanceof Lang.Dictionary || GymRecordedSet.isRecord(value) ||
            GymActiveJournal.isRecord(value);
    }

    (:fullLegacyState)
    static function setField(value, key) { return value.get(key); }

    (:compactLegacyState)
    static function setField(value, key) {
        return value instanceof Lang.Dictionary ? value.get(key) :
            (GymActiveJournal.isRecord(value) ? GymActiveJournal.get(value, key) :
            GymRecordedSet.get(value, key));
    }

    (:fullLegacyState, :inline)
    static function validatedLiveNameBytes(value) { return null; }

    (:compactLegacyState, :inline)
    static function validatedLiveNameBytes(value) {
        return GymActiveJournal.isRecord(value) ?
            (GymActiveJournal.get(value, "exerciseName") == null ? null : utf8Bytes(value[0]).size()) :
            (isImmutableLiveRecord(value) ? value[5] : null);
    }

    static function isValidLiveSetList(value, maximum, allowEmpty) {
        if (GymPlanAccess.valid(value, maximum, allowEmpty)) {
            return true;
        }
        return validateSetList(value, maximum, allowEmpty, true);
    }

    static function isValidSetList(value, maximum, allowEmpty) {
        return validateSetList(value, maximum, allowEmpty, false);
    }

    // Only internal completed-set callers opt into the fixed-field live type.
    // Storage, imported plans, and phone messages still require dictionaries.
    static function validateSetList(value, maximum, allowEmpty, allowLiveRecord) {
        if (GymSetAccess.isJournal(value)) {
            return allowLiveRecord && value.valid(maximum, allowEmpty);
        }
        if (!(value instanceof Lang.Array) || value.size() > maximum || (!allowEmpty && value.size() == 0)) {
            return false;
        }
        var totalNameBytes = 0;
        for (var i = 0; i < value.size(); i += 1) {
            var item = GymSetAccess.at(value, i);
            var validatedBytes = allowLiveRecord ? validatedLiveNameBytes(item) : null;
            if (!keepsSetDiagnostics && validatedBytes != null) {
                // Only the internal factory emits this nonserializable tag,
                // after validating every field and copying the interval bytes.
                // Stored/imported/wire lists never take this trusted-live path.
                totalNameBytes += validatedBytes;
                if (totalNameBytes > maxTotalNameBytes) { return false; }
                continue;
            }
            if ((!(item instanceof Lang.Dictionary) &&
                    (!allowLiveRecord || !isSetRecord(item))) || item.size() > 11 ||
                !isValidExerciseName(setField(item, "exerciseName")) ||
                !isValidWeight(setField(item, "weight")) ||
                !isValidReps(setField(item, "reps"))) {
                return false;
            }
            // Internal fixed-field records cannot contain optional dictionary
            // diagnostics. Untrusted stored/wire dictionaries still validate all
            // fields; opting into the live type never widens the wire contract.
            if (item instanceof Lang.Dictionary) {
                var metricKeys = ["activeSeconds", "restBeforeSeconds", "startHeartRate",
                    "peakHeartRate", "endHeartRate", "recoveryHeartRateDrop", "detectionConfidence"];
                for (var m = 0; m < 7; m += 1) {
                    var maximumMetric = m == 0 ? 7200.0 : (m == 1 ? 86400.0 : (m == 6 ? 100.0 : 240.0));
                    if (!isOptionalBoundedNumber(item[metricKeys[m]], 0.0, maximumMetric)) { return false; }
                }
            }
            var interval = setField(item, "setInterval");
            if (interval != null && !isValidSetInterval(interval)) { return false; }
            totalNameBytes += utf8Bytes(setField(item, "exerciseName").toString()).size();
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

    (:inline)
    static function isValidExactPlannedProgress(legacyCount, targetCount, completedCount, actualSetCount) {
        if (targetCount == null && completedCount == null) {
            return true;
        }
        if (!isValidPlannedSetCount(legacyCount, actualSetCount) ||
            !isBoundedInteger(targetCount, 1, maxPlanSets) ||
            targetCount > legacyCount ||
            !isBoundedInteger(completedCount, 0, maxPlanSets)) {
            return false;
        }
        var maximum = targetCount < actualSetCount ? targetCount : actualSetCount;
        return completedCount <= maximum;
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
            if (!(metrics instanceof Lang.Array) || metrics.size() != 7) { return false; }
            for (var m = 0; m < 7; m += 1) {
                var maximumMetric = m == 0 ? 7200.0 : (m == 1 ? 86400.0 : (m == 6 ? 100.0 : 240.0));
                if (!isOptionalBoundedNumber(metrics[m], 0.0, maximumMetric)) { return false; }
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
                "requestId" => message.get("requestId"),
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

    // Only appendWorkout calls this, after validating the exact message and
    // owner/device binding in the same callback. Revalidating every interval
    // here can exhaust a small watch's callback budget on a recovered workout.
    (:inline)
    private static function canQueueWorkout(message) {
        if (pendingCount() >= maxPendingWorkouts || !GymPendingJournal.readable) {
            return false;
        }
        var totalNameBytes = setListNameBytes(message.get("sets")) + GymPendingJournal.totalNameBytes();
        return totalNameBytes <= maxPendingNameBytes;
    }

    static function isValidWorkoutMetadata(message, actualSetCount) {
        if (!(message instanceof Lang.Dictionary) || message.size() > 21) {
            return false;
        }
        var version = message.get("bindingVersion");
        var type = message.get("type");
        var modeValue = message.get("workoutMode");
        var durationValue = message.get("durationSeconds");
        var gymCaloriesValue = message.get("gymCalories");
        var garminCaloriesValue = message.get("garminCalories");
        var plannedCountValue = message.get("plannedSetCount");
        if (modeValue != null &&
            (!isBoundedText(modeValue, 7) ||
                (!modeValue.toString().equals("free") &&
                    !modeValue.toString().equals("planned")))) {
            return false;
        }
        var commonValid = version instanceof Lang.Number &&
            version == bindingVersion &&
            isBoundedText(type, 20) && type.toString().equals("create_workout") &&
            isBoundedText(message.get("requestId"), maxBindingLength) &&
            isValidAccountBinding(message.get("accountBinding")) &&
            isBoundedText(message.get("deviceBinding"), maxBindingLength) &&
            isValidOptionalAccountBinding(message.get("pairingGeneration")) &&
            isBoundedNumber(message.get("startedAtSeconds"), 946684800.0, 2147483647.0) &&
            isOptionalBoundedNumber(durationValue, 0.0, 604800.0) &&
            isOptionalBoundedNumber(gymCaloriesValue, 0.0, 10000000.0) &&
            isOptionalBoundedNumber(garminCaloriesValue, 0.0, 10000000.0) &&
            isOptionalBoundedNumber(message.get("avgHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("maxHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("lastHeartRate"), 0.0, 300.0) &&
            isOptionalBoundedNumber(message.get("heartRateZone"), 0.0, 5.0);
        if (!commonValid) {
            return false;
        }
        if (!isBoundedInteger(actualSetCount, 0, maxWorkoutSets)) { return false; }
        if (modeValue != null && modeValue.toString().equals("free")) {
            return actualSetCount == 0 &&
                isBoundedNumber(durationValue, 1.0, 604800.0) &&
                isBoundedNumber(gymCaloriesValue, 0.0, 10000000.0) &&
                message.get("setMetrics") == null && message.get("setIntervals") == null &&
                plannedCountValue == null && message.get("plannedTargetSetCount") == null &&
                message.get("completedPlannedSetCount") == null;
        }
        return actualSetCount > 0 &&
            (plannedCountValue == null || isValidPlannedSetCount(plannedCountValue, actualSetCount)) &&
            isValidExactPlannedProgress(plannedCountValue, message.get("plannedTargetSetCount"),
                message.get("completedPlannedSetCount"), actualSetCount);
    }

    static function isValidWorkoutMessage(message) {
        if (!(message instanceof Lang.Dictionary)) { return false; }
        var setsValue = message.get("sets");
        if (!isValidWorkoutMetadata(message, setListCount(setsValue))) { return false; }
        var freeMode = message.get("workoutMode") != null && message.get("workoutMode").equals("free");
        var metrics = message.get("setMetrics");
        var intervals = message.get("setIntervals");
        return isValidSetList(setsValue, maxWorkoutSets, freeMode) &&
            (metrics == null || isValidSetMetricsList(metrics, setsValue)) &&
            (intervals == null || (isValidSetIntervalsList(intervals, setsValue) &&
                areSetIntervalsConsistent(intervals, message.get("durationSeconds"),
                    message.get("gymCalories"), message.get("garminCalories"))));
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
            total += utf8Bytes(setField(GymSetAccess.at(setList, i), "exerciseName").toString()).size();
        }
        return total;
    }

    (:inline)
    static function setListCount(value) {
        return value instanceof Lang.Array ? value.size() : 0;
    }

    (:inline)
    static function storedActiveSnapshotHasSets(value) {
        if (!(value instanceof Lang.Array) || value.size() <= 5) {
            return false;
        }
        var savedSets = value[5];
        if (value[0] == 6) { return isBoundedInteger(savedSets, 1, maxWorkoutSets); }
        return savedSets instanceof Lang.Array && savedSets.size() > 0;
    }

    (:inline)
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
    (:compactRichRecovery)
    static function migrateFullLegacyQuarantineToCompact() {
        var value = null;
        try {
            value = Storage.getValue("legacyQuarantineCurrent");
        } catch (e) {
            return false;
        }
        if (!(value instanceof Lang.Dictionary) ||
            (value.size() != 12 && value.size() != 13) ||
            estimatedValueBytes(value) > maxEstimatedStoreBytes ||
            !(value.get("version") instanceof Lang.Number) ||
            value.get("version") != 1 ||
            !isValidExerciseList(value.get("exercises"), maxPlanSets) ||
            !isValidSetList(value.get("sets"), maxWorkoutSets, true) ||
            !isValidSetList(value.get("plan"), maxPlanSets, true) ||
            !(value.get("pending") instanceof Lang.Array) ||
            value.get("pending").size() > maxPendingWorkouts ||
            !isValidWeight(setField(value, "weight")) ||
            !isValidReps(setField(value, "reps")) ||
            !isValidWeight(value.get("weightStep")) ||
            value.get("weightStep") <= 0.0 || value.get("weightStep") > 100.0 ||
            !(value.get("restSecondsDefault") instanceof Lang.Number) ||
            value.get("restSecondsDefault") < 1 ||
            value.get("restSecondsDefault") > 3600 ||
            !(value.get("autoPromptEnabled") instanceof Lang.Boolean) ||
            !(value.get("sensitivityIndex") instanceof Lang.Number) ||
            value.get("sensitivityIndex") < 0 || value.get("sensitivityIndex") > 2 ||
            !isBoundedText(value.get("language"), 2)) {
            return false;
        }
        var migratedLanguage = value.get("language");
        if (!(migratedLanguage.equals("en") || migratedLanguage.equals("uk") ||
            migratedLanguage.equals("ru"))) {
            return false;
        }
        var migratedSets = value.get("sets");
        var migratedOrigin = value.get("activeWorkoutStartedAtSeconds");
        if (migratedOrigin != null &&
            (!isValidWorkoutStartedAtSeconds(migratedOrigin) ||
                migratedSets.size() == 0)) {
            return false;
        }
        try {
            // Commit the compact authority first. Old full-quarantine keys are
            // removed only after this single-value recovery boundary exists.
            Storage.setValue("legacyCompactCurrentV1", [
                1, migratedSets, migratedSets.size() > 0 ? migratedOrigin : null
            ]);
            legacyCompactCount = migratedSets.size();
        } catch (e) {
            return false;
        }

        // The full snapshot, not its possibly torn per-key mirror, is authoritative.
        // Publish every compact-supported field before the compatibility save. The
        // ownerless pending queue remains deliberately unsendable; preserve its exact
        // bounded value in the existing archive key instead of binding it implicitly.
        exercises = value.get("exercises");
        exerciseCatalogNeedsWrite = true;
        sets = migratedSets;
        clearTransientSetActions();
        plan = value.get("plan");
        persistedPlanSource = null;
        persistedPlanBytes = 0;
        pending = [];
        pendingEstimateSource = null;
        weight = setField(value, "weight");
        reps = setField(value, "reps");
        weightStep = value.get("weightStep");
        restSecondsDefault = value.get("restSecondsDefault");
        autoPromptEnabled = value.get("autoPromptEnabled");
        sensitivityIndex = value.get("sensitivityIndex");
        language = migratedLanguage;
        activeWorkoutStartedAtSeconds = migratedSets.size() > 0 ? migratedOrigin : null;
        resumedWorkoutIntervalsInvalid = migratedSets.size() > 0;
        exerciseIndex = 0;
        if (sets.size() > 0) {
            selectExerciseByName(setField(GymSetAccess.at(sets, sets.size() - 1), "exerciseName").toString());
        } else {
            selectNextPlanSlotInGlobalOrder();
        }

        if (!save()) {
            // The compact authority is already recoverable, while the complete full
            // snapshot remains available to retry every supported field next launch.
            return true;
        }
        try {
            // An empty snapshot queue keeps any archive of the raw ownerless queue.
            if (value.get("pending").size() > 0) {
                Storage.setValue("legacyQuarantinePending", value.get("pending"));
            }
        } catch (e) {
            // Retain the complete full snapshot until its unsendable queue is archived.
            return true;
        }
        try {
            Storage.deleteValue("legacyQuarantineVersion");
            Storage.deleteValue("legacyQuarantineCore");
            Storage.deleteValue("legacyQuarantinePlan");
            Storage.deleteValue("legacyQuarantineSets");
            Storage.deleteValue("legacyQuarantineExercises");
            Storage.deleteValue("legacyQuarantineCurrent");
        } catch (e) {
            // The compact commit is authoritative. Any remaining full snapshot is
            // harmless and allows the idempotent migration to repeat after a crash.
        }
        return true;
    }

    (:compactLegacyState, :richWorkoutMode)
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
        if (legacyCompactCount == -2) { return false; }
        if (legacyPendingUnarchived) {
            // The ownerless queue is unsendable here, but save and account
            // transitions replace "pending"; keep its exact value first.
            try {
                var raw = Storage.getValue("pending");
                if (raw instanceof Lang.Array) {
                    Storage.setValue("legacyQuarantinePending", raw);
                }
                legacyPendingUnarchived = false;
            } catch (e) {
                return false;
            }
        }
        return true;
    }

    (:compactLegacyState)
    static function refreshLegacyCurrentQuarantine() {
        if (legacyCompactCount == -2 ||
            !isValidLiveSetList(sets, maxWorkoutSets, true) ||
            (activeWorkoutStartedAtSeconds != null &&
                (sets.size() == 0 ||
                    !isValidWorkoutStartedAtSeconds(activeWorkoutStartedAtSeconds)))) {
            return false;
        }
        try {
            Storage.setValue("legacyCompactCurrentV1", [
                1,
                sets,
                activeWorkoutStartedAtSeconds
            ]);
            legacyCompactCount = sets.size();
            return true;
        } catch (e) {
            return false;
        }
    }

    (:richWorkoutMode, :compactLegacyState)
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

    (:richWorkoutMode, :compactLegacyState)
    static function legacyCurrentSetCount() {
        return legacyCompactCount;
    }

    static function builtInExercises() {
        return ["Bench Press", "Squat", "Deadlift", "Pull Up", "Overhead Press"];
    }

    (:richWorkoutMode)
    static function containsName(list, name) {
        for (var i = 0; i < list.size(); i += 1) {
            if (list[i].toString().equals(name)) {
                return true;
            }
        }
        return false;
    }
}
