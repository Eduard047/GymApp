package com.example.gymapp.garmin

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.example.gymapp.GymApplication
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.activeCloudSessionFor
import com.example.gymapp.auth.databaseName
import com.example.gymapp.data.repository.GarminWorkoutApplyResult
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.util.AppLanguage
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import com.garmin.android.connectiq.exception.InvalidStateException
import com.garmin.android.connectiq.exception.ServiceUnavailableException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

private const val TAG = "GarminSync"
private const val GARMIN_APP_ID = "A72A5B9F4E3D4E5A8B72C1D9F6123E40"
private const val PLAN_PREFERENCES = "garmin_sync"
private const val ACCOUNT_BINDING_KEY_PREFIX = "account_binding"
private const val PLAN_KEY_PREFIX = "cached_plan"
private const val TRUSTED_DEVICE_KEY_PREFIX = "trusted_device"
private const val GLOBAL_TRUSTED_DEVICE_KEY = "trusted_physical_device_v2"
private const val LAST_READY_AUTH_TRANSITION_KEY = "auth_transition_ready_v1"
private const val PENDING_AUTH_TRANSITION_KEY = "auth_transition_pending_key_v1"
private const val PENDING_AUTH_ACCOUNT_BINDING_KEY = "auth_transition_pending_binding_v1"
private const val ACCOUNT_DEFAULT_DEVICE_SCOPE = "account_default"
private const val MAX_CACHED_PLAN_CHARS = 64 * 1_024
private const val MAX_WATCH_EXERCISES = 60
private const val MAX_WATCH_PLAN_SETS = MAX_GARMIN_WORKOUT_SETS
private const val GARMIN_SDK_READY_TIMEOUT_MS = 60_000L
private const val GARMIN_SEND_TIMEOUT_MS = 90_000L
private const val GARMIN_SYNC_ACK_TIMEOUT_MS = 30_000L
private const val GARMIN_CONNECT_WAIT_MS = 45_000L
private val GARMIN_REVISION_PERSISTENCE_LOCK = Any()

class GarminSyncManager(
    private val application: GymApplication
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val connectIQ = ConnectIQ.getInstance(application, ConnectIQ.IQConnectType.WIRELESS)
    private val garminApp = IQApp(GARMIN_APP_ID)
    private val registeredDevices = ConcurrentHashMap.newKeySet<Long>()
    private val pendingSyncAcks = ConcurrentHashMap<String, PendingSyncAck>()
    private val inboundWorkCommands =
        newBoundedGarminInboundChannel<QueuedGarminCommand>(MAX_GARMIN_PENDING_WORK_COMMANDS)
    private val inboundAckCommands =
        newBoundedGarminInboundChannel<QueuedGarminCommand>(MAX_GARMIN_PENDING_ACK_COMMANDS)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val initializationLock = Any()
    private val accountBindingLock = Any()
    private val authObserverStarted = AtomicBoolean(false)
    private val outboundSyncMutex = Mutex()
    @Volatile var lastPlanSyncStatus: String = "Not started"
        private set
    @Volatile private var sdkReady = false
    @Volatile private var sdkInitializationRequested = false
    @Volatile private var readyAuthTransitionKey: String? = null

    private data class GarminAccountContext(
        val session: AccountSession,
        val identity: String,
        val binding: String,
        val sessionGeneration: String?,
        val authTransitionKey: String
    )

    private data class PendingSyncAck(
        val account: GarminAccountContext?,
        val authTransitionKey: String,
        val requireReadyAccount: Boolean,
        val binding: GarminBinding,
        val revision: Long,
        val deferred: CompletableDeferred<Boolean>
    )

    private data class QueuedGarminCommand(
        val device: IQDevice,
        val command: Map<Any?, Any?>
    )

    private enum class WorkoutPersistenceResult {
        Created,
        AlreadyProcessed,
        Rejected
    }

    init {
        // Garmin callbacks are attacker-controlled transport input. Keep a fixed
        // number of long-lived consumers and apply bounded channel backpressure
        // instead of launching one coroutine per message.
        scope.launch {
            for (queued in inboundWorkCommands) {
                try {
                    handleQueuedWorkCommand(queued.device, queued.command)
                } catch (error: Exception) {
                    Log.i(TAG, "Rejected Garmin work command after processing failure", error)
                }
            }
        }
        scope.launch {
            for (queued in inboundAckCommands) {
                try {
                    handleSyncAck(queued.device, queued.command)
                } catch (error: Exception) {
                    Log.i(TAG, "Rejected Garmin acknowledgement after processing failure", error)
                }
            }
        }
    }

    private val listener = object : ConnectIQ.ConnectIQListener {
        override fun onSdkReady() {
            sdkReady = true
            sdkInitializationRequested = false
            Log.i(TAG, "Connect IQ SDK ready")
            registerConnectedDevices()
            scope.launch { sendPendingAuthResetIfPossible() }
        }

        override fun onInitializeError(errStatus: ConnectIQ.IQSdkErrorStatus) {
            sdkReady = false
            sdkInitializationRequested = false
            Log.i(TAG, "Connect IQ unavailable: $errStatus")
        }

        override fun onSdkShutDown() {
            sdkReady = false
            sdkInitializationRequested = false
            registeredDevices.clear()
            Log.i(TAG, "Connect IQ SDK shut down")
        }
    }

    fun initialize() {
        startAuthObserverIfNeeded()
        synchronized(initializationLock) {
            if (sdkReady || sdkInitializationRequested) {
                Log.i(TAG, "Connect IQ initialization already requested")
                return
            }
            sdkInitializationRequested = true
        }

        val startSdk = {
            Log.i(TAG, "Initializing Connect IQ SDK")
            runCatching {
                // Never interrupt app launch with the Garmin SDK's install UI.
                // Missing Garmin Connect is surfaced only when Garmin sync is used.
                connectIQ.initialize(application, false, listener)
            }.onFailure { error ->
                sdkInitializationRequested = false
                Log.i(TAG, "Connect IQ initialization skipped", error)
            }
            Unit
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            startSdk()
        } else {
            mainHandler.post(startSdk)
        }
    }

    private fun startAuthObserverIfNeeded() {
        if (!authObserverStarted.compareAndSet(false, true)) return
        scope.launch {
            application.cloudAuthManager.authState.collect { state ->
                val target = authTransitionTargetFor(state.session)
                if (target == null) {
                    readyAuthTransitionKey = null
                    lastPlanSyncStatus = "Garmin account transition is invalid"
                    cancelStalePendingAcks()
                    return@collect
                }
                val resetRequired = recordAuthTransition(target)
                cancelStalePendingAcks()
                if (resetRequired) {
                    // Network work is intentionally detached from the collector so a
                    // newer auth state is persisted immediately and invalidates old ACKs.
                    scope.launch { sendPendingAuthResetIfPossible() }
                }
            }
        }
    }

    private fun recordAuthTransition(target: GarminAuthTransitionTarget): Boolean {
        synchronized(accountBindingLock) {
            val preferences = preferences()
            val trusted = trustedDeviceResolutionLocked(preferences, migrateLegacy = true)
            val lastReady = preferences.getStringSafely(LAST_READY_AUTH_TRANSITION_KEY)
            val existingPending = pendingAuthTransitionLocked(preferences)
            val hasStoredPending = preferences.contains(PENDING_AUTH_TRANSITION_KEY) ||
                preferences.contains(PENDING_AUTH_ACCOUNT_BINDING_KEY)
            val resetRequired = hasStoredPending || existingPending != null ||
                garminAuthTransitionNeedsReset(
                targetKey = target.key,
                lastReadyKey = lastReady,
                trustedDeviceState = trusted.state
            )

            if (trusted.state == GarminTrustedDeviceState.Unpaired) {
                val committed = preferences.edit()
                    .putString(LAST_READY_AUTH_TRANSITION_KEY, target.key)
                    .remove(PENDING_AUTH_TRANSITION_KEY)
                    .remove(PENDING_AUTH_ACCOUNT_BINDING_KEY)
                    .commit()
                readyAuthTransitionKey = target.key.takeIf { committed }
                if (!committed) {
                    lastPlanSyncStatus = "Cannot persist Garmin account state"
                }
                return !committed
            }

            if (!resetRequired && trusted.state == GarminTrustedDeviceState.Pinned) {
                readyAuthTransitionKey = target.key
                return false
            }

            readyAuthTransitionKey = null
            val committed = preferences.edit()
                .putString(PENDING_AUTH_TRANSITION_KEY, target.key)
                .putString(PENDING_AUTH_ACCOUNT_BINDING_KEY, target.accountBinding)
                .commit()
            if (!committed) {
                lastPlanSyncStatus = "Cannot persist pending Garmin account reset"
                return false
            }
            lastPlanSyncStatus = if (trusted.state == GarminTrustedDeviceState.Conflict) {
                "Garmin trusted-device state conflicts; reset is blocked"
            } else {
                "Waiting to clear Garmin data for the active account"
            }
            return trusted.state == GarminTrustedDeviceState.Pinned
        }
    }

    private fun cancelStalePendingAcks() {
        pendingSyncAcks.entries.forEach { entry ->
            val pending = entry.value
            if (!pendingContextIsCurrent(pending) && pendingSyncAcks.remove(entry.key, pending)) {
                pending.deferred.complete(false)
            }
        }
    }

    suspend fun cacheAndPushPlan(
        sets: List<NamedWorkoutSetDraft>,
        exerciseCatalog: List<String>
    ): Boolean {
        val account = rawActiveAccountContext() ?: run {
            lastPlanSyncStatus = "Sign in before Garmin sync"
            return false
        }
        if (!isStillActive(account)) {
            lastPlanSyncStatus =
                "Clearing previous Garmin account data; reconnect the trusted watch"
            scope.launch { sendPendingAuthResetIfPossible() }
            return false
        }
        val plan = validatedGarminPlanOrNull(sets) ?: run {
            lastPlanSyncStatus = "Workout plan is outside Garmin limits"
            return false
        }
        if (plan.isEmpty()) {
            lastPlanSyncStatus = "Workout plan is empty"
            return false
        }
        val syncId = newGarminMessageId()
        // An ordinary plan update must not terminate an unrelated active watch
        // workout. Only the auth-transition cleanup path sets resetWorkout=true.
        val payload = syncPayload(exerciseCatalog, plan, syncId, resetWorkout = false)
        if (!cachePlan(plan, account)) {
            lastPlanSyncStatus = "Cannot persist Garmin plan"
            return false
        }
        lastPlanSyncStatus = "Waiting for Garmin SDK"
        if (!ensureSdkReady()) {
            lastPlanSyncStatus = "Garmin SDK not ready"
            return false
        }
        if (!isStillActive(account)) {
            lastPlanSyncStatus = "Account changed before Garmin sync"
            return false
        }
        return sendToConnectedDevices(
            basePayload = payload,
            syncId = syncId,
            account = account,
            planToCache = plan
        )
    }

    private fun registerConnectedDevices() {
        val devices = try {
            connectIQ.knownDevices.orEmpty()
        } catch (error: Exception) {
            Log.i(TAG, "Cannot list Garmin devices", error)
            emptyList()
        }
        Log.i(TAG, "Known Garmin device count=${devices.size}")

        devices.forEach { device ->
            runCatching {
                connectIQ.registerForDeviceEvents(device) { changedDevice, status ->
                    Log.i(TAG, "Garmin device event status=$status")
                    if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                        registerAppEvents(changedDevice)
                        scope.launch { sendPendingAuthResetIfPossible() }
                    }
                }
                val status = connectIQ.getDeviceStatus(device)
                Log.i(TAG, "Garmin device status=$status")
                if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                    registerAppEvents(device)
                }
            }.onFailure { Log.i(TAG, "Cannot register Garmin device", it) }
        }
    }

    private suspend fun ensureSdkReady(): Boolean {
        if (!sdkReady) {
            initialize()
            withTimeoutOrNull(GARMIN_SDK_READY_TIMEOUT_MS) {
                while (!sdkReady) {
                    delay(150L)
                }
            } ?: return false
        }
        registerConnectedDevices()
        return true
    }

    private fun registerAppEvents(device: IQDevice) {
        if (!registeredDevices.add(device.deviceIdentifier)) return
        try {
            connectIQ.registerForAppEvents(device, garminApp) { source, _, messages, _ ->
                if (source.deviceIdentifier != device.deviceIdentifier) {
                    return@registerForAppEvents
                }
                val envelopes = boundedGarminInboundEnvelopes(messages)
                envelopes.forEach { envelope ->
                    if (!isPotentiallyTrustedInboundSource(source, envelope)) {
                        return@forEach
                    }
                    val queued = QueuedGarminCommand(source, envelope.command)
                    // trySend is deliberately non-blocking. A full queue drops
                    // the command; the watch must retry with its stable request ID.
                    when (envelope.kind) {
                        GarminInboundCommandKind.Work -> inboundWorkCommands.trySend(queued)
                        GarminInboundCommandKind.Acknowledgement -> inboundAckCommands.trySend(queued)
                    }
                }
            }
            Log.i(TAG, "Registered Garmin app events")
        } catch (error: Exception) {
            registeredDevices.remove(device.deviceIdentifier)
            Log.i(TAG, "Cannot listen for GymApp messages", error)
        }
    }

    private fun isPotentiallyTrustedInboundSource(
        device: IQDevice,
        envelope: GarminInboundCommandEnvelope
    ): Boolean {
        val sourceBinding = deviceBinding(device)
        if (!isValidGarminTransportDeviceBinding(sourceBinding)) return false
        return when (envelope.kind) {
            GarminInboundCommandKind.Work -> {
                val account = activeAccountContext() ?: return false
                trustedDeviceBinding(account) == sourceBinding
            }
            GarminInboundCommandKind.Acknowledgement -> {
                val syncId = envelope.command["syncId"] as? String ?: return false
                val pending = pendingSyncAcks[syncId] ?: return false
                pendingContextIsCurrent(pending) &&
                    pending.binding.device == sourceBinding &&
                    garminBindingDecision(envelope.command, pending.binding) ==
                        GarminBindingDecision.Bound &&
                    garminSyncAckMatches(
                        command = envelope.command,
                        expectedSyncId = syncId,
                        expectedRevision = pending.revision
                    )
            }
        }
    }

    private suspend fun handleQueuedWorkCommand(
        device: IQDevice,
        command: Map<Any?, Any?>
    ) {
        when (command["type"] as? String ?: return) {
            "request_sync" -> pushSync(device, command)
            "create_workout" -> createWorkout(device, command)
        }
    }

    private fun handleSyncAck(device: IQDevice, command: Map<Any?, Any?>) {
        if (command.size > MAX_GARMIN_COMMAND_ENTRIES) return
        val syncId = command["syncId"] as? String ?: return
        if (!isValidGarminMessageId(syncId, MAX_GARMIN_SYNC_ID_LENGTH)) return
        val pending = pendingSyncAcks[syncId] ?: return
        val decision = garminBindingDecision(
            command = command,
            expected = pending.binding
        )
        if (
            !pendingContextIsCurrent(pending) ||
            deviceBinding(device) != pending.binding.device ||
            decision != GarminBindingDecision.Bound ||
            !garminSyncAckMatches(
                command = command,
                expectedSyncId = syncId,
                expectedRevision = pending.revision
            )
        ) {
            Log.i(TAG, "Rejected unbound or unsuccessful Garmin sync acknowledgement")
            return
        }
        if (pendingSyncAcks.remove(syncId, pending)) {
            lastPlanSyncStatus = "Garmin plan acknowledged"
            Log.i(TAG, "Garmin sync acknowledged")
            pending.deferred.complete(true)
        }
    }

    private suspend fun pushSync(device: IQDevice, command: Map<Any?, Any?>) {
        if (command.size > MAX_GARMIN_COMMAND_ENTRIES) return
        val requestId = command["requestId"] as? String ?: return
        if (!isValidGarminMessageId(requestId, MAX_GARMIN_REQUEST_ID_LENGTH)) return
        val account = activeAccountContext() ?: return
        val sourceDeviceBinding = deviceBinding(device)
        if (trustedDeviceBinding(account) != sourceDeviceBinding) {
            Log.i(TAG, "Rejected Garmin sync request from an untrusted device")
            return
        }
        val binding = GarminBinding(account.binding, sourceDeviceBinding)
        val decision = garminBindingDecision(
            command = command,
            expected = binding
        )
        if (decision == GarminBindingDecision.Rejected) {
            Log.i(TAG, "Rejected Garmin sync request with stale account or device binding")
            return
        }
        pushSyncForContext(device, account)
    }

    private suspend fun createWorkout(device: IQDevice, command: Map<Any?, Any?>) {
        val account = activeAccountContext() ?: return
        val sourceDeviceBinding = deviceBinding(device)
        if (trustedDeviceBinding(account) != sourceDeviceBinding) {
            Log.i(TAG, "Rejected Garmin workout from an untrusted device")
            return
        }
        val binding = GarminBinding(account.binding, sourceDeviceBinding)
        if (
            garminBindingDecision(
                command = command,
                expected = binding
            ) != GarminBindingDecision.Bound
        ) {
            Log.i(TAG, "Rejected unbound Garmin workout")
            return
        }

        val workout = parseGarminWorkoutCommand(
            command = command,
            nowMillis = System.currentTimeMillis()
        ) ?: run {
            Log.i(TAG, "Rejected malformed or out-of-range Garmin workout")
            return
        }

        when (persistWorkout(account, binding, workout)) {
            WorkoutPersistenceResult.Rejected -> return
            WorkoutPersistenceResult.Created,
            WorkoutPersistenceResult.AlreadyProcessed -> {
                sendAndWait(
                    device,
                    bindPayload(
                        payload = mapOf(
                            "type" to "ack",
                            "requestId" to workout.requestId
                        ),
                        accountBinding = binding.account,
                        deviceBinding = binding.device
                    )
                )
            }
        }
        if (isStillActive(account)) {
            pushSyncForContext(device, account)
        }
    }

    private suspend fun pushSyncForContext(
        device: IQDevice,
        account: GarminAccountContext
    ) {
        outboundSyncMutex.withLock {
            if (!isStillActive(account)) return@withLock
            if (trustedDeviceBinding(account) != deviceBinding(device)) return@withLock
            val repository = application.repositoryFor(account.session)
            val exercises = repository.getExerciseNamesForSync(limit = MAX_WATCH_EXERCISES)
            if (!isStillActive(account)) return@withLock
            val deviceBinding = deviceBinding(device)
            val plan = cachedPlan(account, deviceBinding)
            val syncId = newGarminMessageId()
            val basePayload = syncPayload(exercises, plan, syncId, resetWorkout = false)
            if (!cachePlan(plan, account, deviceBinding)) return@withLock
            if (!isStillActive(account)) return@withLock
            val binding = GarminBinding(account.binding, deviceBinding)
            val revision = allocateSyncRevision(binding) ?: run {
                lastPlanSyncStatus = "Cannot persist Garmin sync revision"
                return@withLock
            }
            val payload = boundGarminSyncPayload(basePayload, binding, revision)
                ?: return@withLock
            Log.i(TAG, "Replying to Garmin sync request payload=${payloadSummary(payload)}")
            sendAndConfirmSync(
                device = device,
                payload = payload,
                syncId = syncId,
                account = account,
                authTransitionKey = account.authTransitionKey,
                requireReadyAccount = true,
                binding = binding,
                revision = revision
            )
            Unit
        }
    }

    private fun syncPayload(
        exercises: List<String>,
        plan: List<NamedWorkoutSetDraft>,
        syncId: String? = null,
        resetWorkout: Boolean = false
    ): Map<String, Any> {
        val compactPlan = checkNotNull(validatedGarminPlanOrNull(plan)) {
            "Garmin plan is outside supported limits."
        }
        val planExerciseNames = compactPlan.map { it.exerciseName }
        val exerciseSource = if (planExerciseNames.isNotEmpty()) {
            planExerciseNames
        } else {
            exercises
        }
        val compactExercises = checkNotNull(
            validatedGarminExerciseCatalog(
                exercises = exerciseSource,
                maximumCount = MAX_WATCH_EXERCISES
            )
        ) { "Garmin exercise catalog exceeds the message budget." }

        val payload = mutableMapOf<String, Any>(
            "type" to "sync",
            "resetWorkout" to resetWorkout,
            "language" to application.languageManager.currentLanguage().tag,
            "planNames" to compactPlan.map { it.exerciseName },
            "planWeights" to compactPlan.map { it.weight },
            "planReps" to compactPlan.map { it.reps }
        )
        if (compactPlan.isEmpty()) {
            payload["exercises"] = compactExercises
        }
        if (!syncId.isNullOrBlank()) {
            payload["syncId"] = syncId
            payload["requestId"] = syncId
        }
        return payload
    }

    private suspend fun sendToConnectedDevices(
        basePayload: Map<String, Any>,
        syncId: String,
        account: GarminAccountContext,
        planToCache: List<NamedWorkoutSetDraft>
    ): Boolean = outboundSyncMutex.withLock {
        sendToConnectedDevicesLocked(basePayload, syncId, account, planToCache)
    }

    private suspend fun sendToConnectedDevicesLocked(
        basePayload: Map<String, Any>,
        syncId: String,
        account: GarminAccountContext,
        planToCache: List<NamedWorkoutSetDraft>
    ): Boolean {
        if (!sdkReady) return false
        val initial = resolveGarminDevices()
        if (initial.failedStatus != null) {
            lastPlanSyncStatus = initial.failedStatus
            return false
        }
        val knownDevices = initial.known
        val trustedDevice = trustedDeviceBinding(account)
        var connectedTargets = if (trustedDevice == null) {
            initial.connected
        } else {
            initial.connected.filter { deviceBinding(it) == trustedDevice }
        }
        val knownTargets = if (trustedDevice == null) {
            emptyList()
        } else {
            knownDevices.filter { deviceBinding(it) == trustedDevice }
        }

        if (trustedDevice == null) {
            val firstPairingTarget = selectGarminDeviceTarget(
                connectedBindings = connectedTargets.map(::deviceBinding),
                knownBindings = knownDevices.map(::deviceBinding),
                trustedBinding = null
            )
            if (firstPairingTarget == null) {
                lastPlanSyncStatus = if (connectedTargets.isEmpty()) {
                    "Connect exactly one Garmin watch before first secure pairing"
                } else {
                    "Disconnect extra Garmin watches before first secure pairing"
                }
                Log.i(TAG, lastPlanSyncStatus)
                return false
            }
            connectedTargets = connectedTargets.filter {
                deviceBinding(it) == firstPairingTarget.binding
            }
        } else if (connectedTargets.isEmpty() && knownTargets.isNotEmpty()) {
            lastPlanSyncStatus = "Waiting for trusted Garmin Bluetooth connection"
            Log.i(TAG, lastPlanSyncStatus)
            val deadline = System.currentTimeMillis() + GARMIN_CONNECT_WAIT_MS
            while (connectedTargets.isEmpty() && System.currentTimeMillis() < deadline) {
                delay(1_000L)
                val retry = resolveGarminDevices()
                if (retry.failedStatus != null) {
                    lastPlanSyncStatus = retry.failedStatus
                    return false
                }
                connectedTargets = retry.connected.filter { deviceBinding(it) == trustedDevice }
            }
        }

        val selectedTarget = selectGarminDeviceTarget(
            connectedBindings = connectedTargets.map(::deviceBinding),
            knownBindings = knownTargets.map(::deviceBinding),
            trustedBinding = trustedDevice
        )
        val targets = when (selectedTarget?.source) {
            GarminDeviceTargetSource.Connected -> connectedTargets.filter {
                deviceBinding(it) == selectedTarget.binding
            }
            GarminDeviceTargetSource.KnownPinned -> knownTargets.filter {
                deviceBinding(it) == selectedTarget.binding
            }
            null -> emptyList()
        }.distinctBy { it.deviceIdentifier }
        if (targets.isEmpty()) {
            lastPlanSyncStatus = "Trusted Garmin watch is not paired"
            Log.i(TAG, lastPlanSyncStatus)
            return false
        }

        Log.i(TAG, "Sending sync to ${targets.size} Garmin device(s) payload=${payloadSummary(basePayload)}")
        targets.forEach { device ->
            if (!isStillActive(account)) {
                lastPlanSyncStatus = "Account changed before Garmin sync"
                return false
            }
            registerAppEvents(device)
            val deviceBinding = deviceBinding(device)
            val binding = GarminBinding(account.binding, deviceBinding)
            // The single physical watch pin is committed before the first
            // account-bound payload can mutate a device. A failed send keeps a
            // conservative pin and must be retried against the same watch.
            if (!trustDevice(account, binding.device)) {
                lastPlanSyncStatus = "Cannot persist trusted Garmin device"
                return false
            }
            if (!cachePlan(planToCache, account, deviceBinding)) {
                lastPlanSyncStatus = "Cannot persist Garmin plan"
                return false
            }
            if (!isStillActive(account)) {
                lastPlanSyncStatus = "Account changed before Garmin sync"
                return false
            }
            val revision = allocateSyncRevision(binding) ?: run {
                lastPlanSyncStatus = "Cannot persist Garmin sync revision"
                return false
            }
            val payload = boundGarminSyncPayload(basePayload, binding, revision) ?: return false
            if (
                sendAndConfirmSync(
                    device = device,
                    payload = payload,
                    syncId = syncId,
                    account = account,
                    authTransitionKey = account.authTransitionKey,
                    requireReadyAccount = true,
                    binding = binding,
                    revision = revision
                )
            ) {
                if (!isStillActive(account)) {
                    lastPlanSyncStatus = "Account changed before Garmin acknowledgement"
                    return false
                }
                lastPlanSyncStatus = lastPlanSyncStatus.ifBlank { "ACK" }
                Log.i(TAG, "Garmin sync completed; skipping remaining devices")
                return true
            }
        }
        return false
    }

    private suspend fun sendPendingAuthResetIfPossible() {
        if (pendingAuthTransition() == null) return
        if (!ensureSdkReady()) {
            lastPlanSyncStatus = "Reconnect the trusted Garmin watch to clear old account data"
            return
        }
        outboundSyncMutex.withLock {
            val target = pendingAuthTransition() ?: return@withLock
            if (currentAuthTransitionTarget() != target) return@withLock

            val trusted = synchronized(accountBindingLock) {
                trustedDeviceResolutionLocked(preferences(), migrateLegacy = true)
            }
            val trustedBinding = trusted.binding
            if (
                trusted.state != GarminTrustedDeviceState.Pinned ||
                trustedBinding == null
            ) {
                lastPlanSyncStatus = if (trusted.state == GarminTrustedDeviceState.Conflict) {
                    "Garmin trusted-device state conflicts; reset is blocked"
                } else {
                    "No trusted Garmin watch is paired"
                }
                return@withLock
            }

            val resolution = resolveGarminDevices()
            if (resolution.failedStatus != null) {
                lastPlanSyncStatus = resolution.failedStatus
                return@withLock
            }
            // Account cleanup is never a pairing operation and never targets an
            // offline/alternate watch. A CONNECTED callback will retry durably.
            val device = resolution.connected
                .filter { deviceBinding(it) == trustedBinding }
                .distinctBy { it.deviceIdentifier }
                .singleOrNull()
                ?: run {
                    lastPlanSyncStatus =
                        "Reconnect the trusted Garmin watch to clear old account data"
                    return@withLock
                }
            registerAppEvents(device)

            if (
                pendingAuthTransition() != target ||
                currentAuthTransitionTarget() != target
            ) {
                return@withLock
            }
            val syncId = newGarminMessageId()
            val binding = GarminBinding(target.accountBinding, trustedBinding)
            val revision = allocateSyncRevision(binding) ?: run {
                lastPlanSyncStatus = "Cannot persist Garmin reset revision"
                return@withLock
            }
            val basePayload = syncPayload(
                exercises = emptyList(),
                plan = emptyList(),
                syncId = syncId,
                resetWorkout = true
            )
            val payload = boundGarminSyncPayload(basePayload, binding, revision)
                ?: return@withLock
            if (
                pendingAuthTransition() != target ||
                currentAuthTransitionTarget() != target
            ) {
                return@withLock
            }

            lastPlanSyncStatus = "Clearing previous Garmin account data"
            val confirmed = sendAndConfirmSync(
                device = device,
                payload = payload,
                syncId = syncId,
                account = null,
                authTransitionKey = target.key,
                requireReadyAccount = false,
                binding = binding,
                revision = revision
            )
            if (confirmed && completeAuthTransitionReset(target)) {
                lastPlanSyncStatus = "Garmin account data cleared"
            }
        }
    }

    private fun completeAuthTransitionReset(target: GarminAuthTransitionTarget): Boolean {
        if (currentAuthTransitionTarget() != target) return false
        synchronized(accountBindingLock) {
            val preferences = preferences()
            if (pendingAuthTransitionLocked(preferences) != target) return false
            val committed = preferences.edit()
                .putString(LAST_READY_AUTH_TRANSITION_KEY, target.key)
                .remove(PENDING_AUTH_TRANSITION_KEY)
                .remove(PENDING_AUTH_ACCOUNT_BINDING_KEY)
                .commit()
            if (committed) {
                readyAuthTransitionKey = target.key
            } else {
                lastPlanSyncStatus = "Garmin reset acknowledged but local state was not saved"
            }
            return committed
        }
    }

    private data class GarminDeviceResolution(
        val connected: List<IQDevice>,
        val known: List<IQDevice>,
        val failedStatus: String? = null
    )

    private fun resolveGarminDevices(): GarminDeviceResolution = try {
        val connected = connectIQ.connectedDevices.orEmpty()
        val known = connectIQ.knownDevices.orEmpty()
        val connectedByStatus = known.filter { device ->
            runCatching {
                connectIQ.getDeviceStatus(device) == IQDevice.IQDeviceStatus.CONNECTED
            }.getOrDefault(false)
        }
        GarminDeviceResolution(
            connected = (connected + connectedByStatus).distinctBy { it.deviceIdentifier },
            known = known
        )
    } catch (_: InvalidStateException) {
        GarminDeviceResolution(emptyList(), emptyList(), "Garmin SDK invalid state")
    } catch (_: ServiceUnavailableException) {
        GarminDeviceResolution(emptyList(), emptyList(), "Garmin Connect service unavailable")
    } catch (error: Exception) {
        Log.i(TAG, "Cannot resolve connected Garmin devices", error)
        GarminDeviceResolution(emptyList(), emptyList(), "Cannot list Garmin devices: ${error.message.orEmpty()}")
    }

    private suspend fun sendAndConfirmSync(
        device: IQDevice,
        payload: Map<String, Any>,
        syncId: String,
        account: GarminAccountContext?,
        authTransitionKey: String,
        requireReadyAccount: Boolean,
        binding: GarminBinding,
        revision: Long
    ): Boolean {
        val ack = CompletableDeferred<Boolean>()
        val pending = PendingSyncAck(
            account = account,
            authTransitionKey = authTransitionKey,
            requireReadyAccount = requireReadyAccount,
            binding = binding,
            revision = revision,
            deferred = ack
        )
        if (pendingSyncAcks.putIfAbsent(syncId, pending) != null) return false
        return try {
            val sent = sendAndWait(device, payload)
            if (!sent) return false
            val confirmed = withTimeoutOrNull(GARMIN_SYNC_ACK_TIMEOUT_MS) { ack.await() } ?: false
            if (!confirmed) {
                lastPlanSyncStatus = "No sync_ack from watch after send SUCCESS. Open watch DEBUG screen and check SYNC status."
                Log.i(TAG, "Garmin sync acknowledgement timed out")
            }
            confirmed
        } finally {
            pendingSyncAcks.remove(syncId, pending)
        }
    }

    private suspend fun sendAndWait(device: IQDevice, payload: Map<String, Any>): Boolean {
        val result = CompletableDeferred<Boolean>()
        runCatching {
            connectIQ.sendMessage(device, garminApp, payload) { _, _, status ->
                val success = status == ConnectIQ.IQMessageStatus.SUCCESS
                Log.i(TAG, "Garmin message delivery status=$status payload=${payloadSummary(payload)}")
                if (!success) {
                    lastPlanSyncStatus = "Send status $status"
                }
                result.complete(success)
            }
        }.onFailure { error ->
            Log.i(TAG, "Cannot send message to Garmin", error)
            lastPlanSyncStatus = "Cannot send to Garmin"
            result.complete(false)
        }
        val sent = withTimeoutOrNull(GARMIN_SEND_TIMEOUT_MS) { result.await() }
        if (sent == null) {
            lastPlanSyncStatus = "Send timeout"
        }
        return sent ?: false
    }

    private fun payloadSummary(payload: Map<String, Any>): String {
        val planCount = (payload["planNames"] as? List<*>)?.size ?: 0
        val exerciseCount = (payload["exercises"] as? List<*>)?.size ?: 0
        return "type=${payload["type"]} lang=${payload["language"]} plan=$planCount exercises=$exerciseCount"
    }

    private fun buildGarminWorkoutNote(command: GarminWorkoutCommand): String {
        val language = application.languageManager.currentLanguage()
        val isUk = language == AppLanguage.UK
        val isRu = language == AppLanguage.RU
        val details = mutableListOf("Garmin")
        command.durationSeconds?.takeIf { it > 0L }?.let { seconds ->
            val minutes = seconds / 60
            val remainder = seconds % 60
            details += when {
                isUk -> "Тривалість ${minutes}:${remainder.toString().padStart(2, '0')}"
                isRu -> "Длительность ${minutes}:${remainder.toString().padStart(2, '0')}"
                else -> "Duration ${minutes}:${remainder.toString().padStart(2, '0')}"
            }
        }
        command.gymCalories?.takeIf { it > 0.0 }?.let { calories ->
            details += if (isUk) "Gym ккал ${calories.toInt()}" else "Gym kcal ${calories.toInt()}"
        }
        command.garminCalories?.takeIf { it > 0 }?.let { calories ->
            details += if (isUk) "Garmin ккал $calories" else "Garmin kcal $calories"
        }
        command.averageHeartRate?.takeIf { it > 0 }?.let { bpm ->
            details += when {
                isUk -> "Сер пульс $bpm"
                isRu -> "Средний пульс $bpm"
                else -> "Avg HR $bpm"
            }
        }
        command.maximumHeartRate?.takeIf { it > 0 }?.let { bpm ->
            details += when {
                isUk -> "Макс пульс $bpm"
                isRu -> "Макс. пульс $bpm"
                else -> "Max HR $bpm"
            }
        }
        command.endingHeartRateZone?.takeIf { it > 0 }?.let { zone ->
            details += when {
                isUk -> "Кінцева зона пульсу Z$zone"
                isRu -> "Конечная зона пульса Z$zone"
                else -> "Ending HR zone Z$zone"
            }
        }
        return details.joinToString(separator = " · ")
    }

    private suspend fun persistWorkout(
        account: GarminAccountContext,
        binding: GarminBinding,
        workout: GarminWorkoutCommand
    ): WorkoutPersistenceResult {
        if (!isStillActive(account)) return WorkoutPersistenceResult.Rejected
        val payloadDigest = canonicalGarminWorkoutPayloadDigest(workout)
        val result = runCatching {
            application.repositoryFor(account.session).applyGarminCreateWorkout(
                ownerBinding = binding.account,
                deviceBinding = binding.device,
                requestId = workout.requestId,
                payloadDigest = payloadDigest,
                date = workout.startedAtMillis,
                note = buildGarminWorkoutNote(workout),
                sets = workout.sets
            )
        }.getOrElse { error ->
            Log.i(TAG, "Cannot atomically persist Garmin workout receipt", error)
            return WorkoutPersistenceResult.Rejected
        }
        if (!isStillActive(account)) return WorkoutPersistenceResult.Rejected
        return when (result) {
            GarminWorkoutApplyResult.Applied -> WorkoutPersistenceResult.Created
            GarminWorkoutApplyResult.AlreadyApplied -> WorkoutPersistenceResult.AlreadyProcessed
            GarminWorkoutApplyResult.Rejected -> WorkoutPersistenceResult.Rejected
        }
    }

    private fun cachePlan(
        sets: List<NamedWorkoutSetDraft>,
        account: GarminAccountContext,
        deviceBinding: String = ACCOUNT_DEFAULT_DEVICE_SCOPE
    ): Boolean {
        val plan = validatedGarminPlanOrNull(sets) ?: return false
        val json = JSONArray()
        plan.forEach { set ->
            json.put(JSONObject()
                .put("exerciseName", set.exerciseName)
                .put("weight", set.weight)
                .put("reps", set.reps))
        }
        val encoded = json.toString()
        if (encoded.length > MAX_CACHED_PLAN_CHARS) return false
        val key = garminStorageKey(PLAN_KEY_PREFIX, account.binding, deviceBinding)
        return preferences().edit()
            .putString(key, encoded)
            .remove("cached_plan")
            .remove("processed_ids")
            .commit()
    }

    private fun cachedPlan(
        account: GarminAccountContext,
        deviceBinding: String
    ): List<NamedWorkoutSetDraft> {
        val deviceKey = garminStorageKey(PLAN_KEY_PREFIX, account.binding, deviceBinding)
        val accountKey = garminStorageKey(
            PLAN_KEY_PREFIX,
            account.binding,
            ACCOUNT_DEFAULT_DEVICE_SCOPE
        )
        val encoded = preferences().getString(deviceKey, null)
            ?: preferences().getString(accountKey, null)
            ?: return emptyList()
        if (encoded.length > MAX_CACHED_PLAN_CHARS) return emptyList()
        return runCatching {
            val array = JSONArray(encoded)
            require(array.length() <= MAX_WATCH_PLAN_SETS)
            val parsed = buildList {
                for (index in 0 until array.length()) {
                    val item = array.get(index) as? JSONObject ?: error("Invalid cached Garmin set")
                    require(item.length() <= 3)
                    val exerciseName = item.get("exerciseName") as? String
                        ?: error("Invalid cached Garmin exercise")
                    val weight = item.get("weight") as? Number
                        ?: error("Invalid cached Garmin weight")
                    val reps = item.get("reps") as? Number
                        ?: error("Invalid cached Garmin reps")
                    val repsDouble = reps.toDouble()
                    require(repsDouble.isFinite() && repsDouble % 1.0 == 0.0)
                    add(
                        NamedWorkoutSetDraft(
                            exerciseName = exerciseName,
                            weight = weight.toDouble(),
                            reps = repsDouble.toInt()
                        )
                    )
                }
            }
            validatedGarminPlanOrNull(parsed) ?: error("Cached Garmin plan is out of range")
        }.getOrDefault(emptyList())
    }

    private fun activeAccountContext(): GarminAccountContext? {
        val account = rawActiveAccountContext() ?: return null
        return account.takeIf(::isStillActive)
    }

    private fun rawActiveAccountContext(): GarminAccountContext? {
        val session = application.cloudAuthManager.authState.value.session ?: return null
        val identity = session.databaseName()
        val binding = accountBinding(session, identity) ?: return null
        val target = garminAuthTransitionTarget(
            accountBinding = binding,
            sessionGeneration = (session as? AccountSession.Cloud)?.sessionGeneration
        ) ?: return null
        return GarminAccountContext(
            session = session,
            identity = identity,
            binding = binding,
            sessionGeneration = (session as? AccountSession.Cloud)?.sessionGeneration,
            authTransitionKey = target.key
        )
    }

    private fun authTransitionTargetFor(session: AccountSession?): GarminAuthTransitionTarget? {
        if (session == null) return garminAuthTransitionTarget(null, null)
        val identity = session.databaseName()
        val binding = accountBinding(session, identity) ?: return null
        return garminAuthTransitionTarget(
            accountBinding = binding,
            sessionGeneration = (session as? AccountSession.Cloud)?.sessionGeneration
        )
    }

    private fun currentAuthTransitionTarget(): GarminAuthTransitionTarget? =
        authTransitionTargetFor(application.cloudAuthManager.authState.value.session)

    private fun accountBinding(session: AccountSession, identity: String): String? {
        if (session is AccountSession.Cloud) {
            return canonicalCloudGarminAccountBinding(session.userId)
        }
        val key = garminStorageKey(ACCOUNT_BINDING_KEY_PREFIX, "local", identity)
        synchronized(accountBindingLock) {
            preferences().getString(key, null)?.let { existing ->
                if (isValidGarminAccountBinding(existing)) return existing
            }
            val generated = newLocalGarminAccountBinding()
            return generated.takeIf { preferences().edit().putString(key, it).commit() }
        }
    }

    private fun isStillActive(expected: GarminAccountContext): Boolean {
        if (readyAuthTransitionKey != expected.authTransitionKey) return false
        val current = application.cloudAuthManager.authState.value.session ?: return false
        if (current.databaseName() != expected.identity) return false
        when (val expectedSession = expected.session) {
            is AccountSession.Cloud -> {
                val active = activeCloudSessionFor(current, expectedSession) ?: return false
                if (active.sessionGeneration != expected.sessionGeneration) return false
            }
            is AccountSession.Local -> if (current !is AccountSession.Local) return false
        }
        return accountBinding(current, expected.identity) == expected.binding &&
            currentAuthTransitionTarget()?.key == expected.authTransitionKey &&
            readyAuthTransitionKey == expected.authTransitionKey
    }

    private fun pendingContextIsCurrent(pending: PendingSyncAck): Boolean {
        if (currentAuthTransitionTarget()?.key != pending.authTransitionKey) return false
        if (!pending.requireReadyAccount) return pending.account == null
        val account = pending.account ?: return false
        return isStillActive(account)
    }

    private fun trustedDeviceBinding(account: GarminAccountContext): String? {
        if (!isStillActive(account)) return null
        synchronized(accountBindingLock) {
            val resolution = trustedDeviceResolutionLocked(
                preferences = preferences(),
                migrateLegacy = true
            )
            return resolution.binding.takeIf {
                resolution.state == GarminTrustedDeviceState.Pinned
            }
        }
    }

    private fun trustDevice(account: GarminAccountContext, deviceBinding: String): Boolean {
        if (!isStillActive(account) || !isValidGarminTransportDeviceBinding(deviceBinding)) {
            return false
        }
        val key = garminStorageKey(TRUSTED_DEVICE_KEY_PREFIX, account.binding)
        synchronized(accountBindingLock) {
            val preferences = preferences()
            val resolution = trustedDeviceResolutionLocked(preferences, migrateLegacy = true)
            when (resolution.state) {
                GarminTrustedDeviceState.Conflict -> return false
                GarminTrustedDeviceState.Pinned -> {
                    if (resolution.binding != deviceBinding) return false
                }
                GarminTrustedDeviceState.Unpaired -> Unit
            }
            val accountExisting = preferences.getStringSafely(key)
            if (preferences.contains(key) && accountExisting != deviceBinding) return false
            return preferences.edit()
                .putString(GLOBAL_TRUSTED_DEVICE_KEY, deviceBinding)
                .putString(key, deviceBinding)
                .commit()
        }
    }

    private fun trustedDeviceResolutionLocked(
        preferences: android.content.SharedPreferences,
        migrateLegacy: Boolean
    ): GarminTrustedDeviceResolution {
        val all = preferences.all
        val explicitRaw = all[GLOBAL_TRUSTED_DEVICE_KEY]
        val explicit = when (explicitRaw) {
            null -> null
            is String -> explicitRaw
            else -> "<invalid>"
        }
        val legacy = all.entries
            .asSequence()
            .filter { (key, _) -> key.startsWith("${TRUSTED_DEVICE_KEY_PREFIX}_") }
            .map { (_, value) -> (value as? String) ?: "<invalid>" }
            .toList()
        val resolution = resolveGlobalGarminDeviceBinding(explicit, legacy)
        if (
            migrateLegacy &&
            explicitRaw == null &&
            resolution.state == GarminTrustedDeviceState.Pinned &&
            resolution.binding != null
        ) {
            if (
                !preferences.edit()
                    .putString(GLOBAL_TRUSTED_DEVICE_KEY, resolution.binding)
                    .commit()
            ) {
                return GarminTrustedDeviceResolution(GarminTrustedDeviceState.Conflict)
            }
        }
        return resolution
    }

    private fun pendingAuthTransition(): GarminAuthTransitionTarget? =
        synchronized(accountBindingLock) {
            pendingAuthTransitionLocked(preferences())
        }

    private fun pendingAuthTransitionLocked(
        preferences: android.content.SharedPreferences
    ): GarminAuthTransitionTarget? {
        val key = preferences.getStringSafely(PENDING_AUTH_TRANSITION_KEY) ?: return null
        val binding = preferences.getStringSafely(PENDING_AUTH_ACCOUNT_BINDING_KEY) ?: return null
        if (!isValidGarminAccountBinding(key) || !isValidGarminAccountBinding(binding)) {
            return null
        }
        return GarminAuthTransitionTarget(key = key, accountBinding = binding)
    }

    private fun allocateSyncRevision(binding: GarminBinding): Long? {
        if (
            !isValidGarminAccountBinding(binding.account) ||
            !isValidGarminTransportDeviceBinding(binding.device)
        ) {
            return null
        }
        // This fence is global to the physical Connect IQ transport. Scoping it
        // by account would let a delayed account-A sync become fresh again after
        // switching to B and reset the watch back to A.
        val key = globalGarminSyncRevisionStorageKey(binding.device) ?: return null
        synchronized(GARMIN_REVISION_PERSISTENCE_LOCK) {
            val preferences = preferences()
            val lastRevision = if (preferences.contains(key)) {
                runCatching { preferences.getLong(key, 0L) }.getOrNull() ?: return null
            } else {
                null
            }
            val revision = nextGarminSyncRevision(
                lastRevision = lastRevision,
                nowMillis = System.currentTimeMillis()
            ) ?: return null
            return revision.takeIf {
                preferences.edit().putLong(key, revision).commit()
            }
        }
    }

    private fun bindPayload(
        payload: Map<String, Any>,
        accountBinding: String,
        deviceBinding: String
    ): Map<String, Any> = boundGarminPayload(
        payload = payload,
        binding = GarminBinding(accountBinding, deviceBinding)
    )

    private fun deviceBinding(device: IQDevice): String = device.deviceIdentifier.toString()

    private fun newGarminMessageId(): String = UUID.randomUUID().toString()

    private fun preferences() = application.getSharedPreferences(
        PLAN_PREFERENCES,
        Context.MODE_PRIVATE
    )
}

private fun android.content.SharedPreferences.getStringSafely(key: String): String? =
    all[key] as? String
