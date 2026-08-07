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
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.util.AppLanguage
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import com.garmin.android.connectiq.exception.InvalidStateException
import com.garmin.android.connectiq.exception.ServiceUnavailableException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.math.RoundingMode
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
private const val PAIRING_GENERATION_KEY_PREFIX = "pairing_generation_v1"
private const val PENDING_PAIRING_GENERATION_KEY_PREFIX = "pairing_generation_pending_v1"
private const val PAIRING_GENERATION_CAPABILITY_KEY_PREFIX = "pairing_generation_capable_v1"
private const val LAST_READY_AUTH_TRANSITION_KEY = "auth_transition_ready_v1"
private const val PENDING_AUTH_TRANSITION_KEY = "auth_transition_pending_key_v1"
private const val PENDING_AUTH_ACCOUNT_BINDING_KEY = "auth_transition_pending_binding_v1"
private const val ACCOUNT_DEFAULT_DEVICE_SCOPE = "account_default"
private const val MAX_CACHED_PLAN_CHARS = 64 * 1_024
private const val MAX_WATCH_EXERCISES = 60
private const val MAX_WATCH_PLAN_SETS = MAX_GARMIN_WORKOUT_SETS
private const val GARMIN_SDK_READY_TIMEOUT_MS = 60_000L
private const val GARMIN_SEND_TIMEOUT_MS = 90_000L
private const val GARMIN_SYNC_ACK_ATTEMPTS = 3
private const val GARMIN_SYNC_ACK_ATTEMPT_TIMEOUT_MS = 10_000L
private const val GARMIN_SYNC_TOTAL_TIMEOUT_MS = 40_000L
private const val GARMIN_CONNECT_WAIT_MS = 45_000L
private const val MAX_PROFILE_GARMIN_DEVICES = 8
private const val MAX_PROFILE_DEVICE_NAME_CHARS = 80
private val GARMIN_REVISION_PERSISTENCE_LOCK = Any()

internal data class GarminCloudAccountLocalCleanupPlan(
    val accountBinding: String,
    val authTransitionKey: String,
    val preferenceKeys: Set<String>
)

/**
 * Resolves only keys attributable to one cloud owner. Global physical-device and monotonic revision
 * fences are deliberately retained because they protect transitions shared by every account.
 */
internal fun garminCloudAccountLocalCleanupPlan(
    existingPreferences: Map<String, *>,
    userId: String,
    sessionGeneration: String
): GarminCloudAccountLocalCleanupPlan? {
    val accountBinding = canonicalCloudGarminAccountBinding(userId) ?: return null
    val authTarget = garminAuthTransitionTarget(accountBinding, sessionGeneration) ?: return null
    val trustedOwnerKey = garminStorageKey(TRUSTED_DEVICE_KEY_PREFIX, accountBinding)
    val keys = linkedSetOf(
        trustedOwnerKey,
        garminStorageKey(PLAN_KEY_PREFIX, accountBinding, ACCOUNT_DEFAULT_DEVICE_SCOPE)
    )

    val ownerTrustedDevice = when (val raw = existingPreferences[trustedOwnerKey]) {
        null -> null
        is String -> raw.takeIf(::isValidGarminTransportDeviceBinding) ?: return null
        else -> return null
    }

    val pendingTargetPresent = existingPreferences.containsKey(PENDING_AUTH_TRANSITION_KEY)
    val pendingBindingPresent = existingPreferences.containsKey(PENDING_AUTH_ACCOUNT_BINDING_KEY)
    var deletedTransitionIsPending = false
    if (pendingTargetPresent || pendingBindingPresent) {
        val pendingTarget = existingPreferences[PENDING_AUTH_TRANSITION_KEY] as? String
        val pendingBinding = existingPreferences[PENDING_AUTH_ACCOUNT_BINDING_KEY] as? String
        if (pendingTarget == authTarget.key && pendingBinding == accountBinding) {
            deletedTransitionIsPending = true
            keys += PENDING_AUTH_TRANSITION_KEY
            keys += PENDING_AUTH_ACCOUNT_BINDING_KEY
        } else if (pendingTarget == authTarget.key || pendingBinding == accountBinding) {
            // Conflicting global transition state cannot be assigned to either owner safely.
            return null
        }
    }

    val lastReadyBelongsToDeletedOwner =
        existingPreferences[LAST_READY_AUTH_TRANSITION_KEY] == authTarget.key
    if (lastReadyBelongsToDeletedOwner) keys += LAST_READY_AUTH_TRANSITION_KEY

    val deviceBindings = linkedSetOf<String>()
    ownerTrustedDevice?.let(deviceBindings::add)
    if (lastReadyBelongsToDeletedOwner || deletedTransitionIsPending) {
        val globalDevice = existingPreferences[GLOBAL_TRUSTED_DEVICE_KEY]
        if (globalDevice is String && isValidGarminTransportDeviceBinding(globalDevice)) {
            deviceBindings += globalDevice
        }
    }
    deviceBindings.forEach { deviceBinding ->
        keys += garminStorageKey(PLAN_KEY_PREFIX, accountBinding, deviceBinding)
        keys += garminStorageKey(PAIRING_GENERATION_KEY_PREFIX, authTarget.key, deviceBinding)
        keys += garminStorageKey(
            PENDING_PAIRING_GENERATION_KEY_PREFIX,
            authTarget.key,
            deviceBinding
        )
        keys += garminStorageKey(
            PAIRING_GENERATION_CAPABILITY_KEY_PREFIX,
            authTarget.key,
            deviceBinding
        )
    }
    return GarminCloudAccountLocalCleanupPlan(
        accountBinding = accountBinding,
        authTransitionKey = authTarget.key,
        preferenceKeys = keys
    )
}

data class GarminDeviceSummary(
    val name: String,
    val connected: Boolean,
    val trustedForActiveAccount: Boolean
)

data class GarminDeviceUiState(
    val sdkReady: Boolean = false,
    val devices: List<GarminDeviceSummary> = emptyList()
)

/** Builds the bounded, portable note stored with a trusted Garmin workout. */
internal fun garminWorkoutNote(
    command: GarminWorkoutCommand,
    language: AppLanguage
): String {
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
    val exactPlannedSetCount = command.plannedTargetSetCount
    val exactCompletedSetCount = command.completedPlannedSetCount
    val progress = if (exactPlannedSetCount != null && exactCompletedSetCount != null) {
        exactCompletedSetCount to exactPlannedSetCount
    } else {
        command.plannedSetCount?.let { planned -> command.sets.size to planned }
    }
    progress
        ?.takeIf { (completed, planned) -> planned > completed }
        ?.let { (completed, planned) ->
            details += when {
                isUk -> "Виконано $completed/$planned підходів"
                isRu -> "Выполнено $completed/$planned подходов"
                else -> "Completed $completed/$planned sets"
            }
        }

    val perSetDetails = command.sets.indices.mapNotNull { index ->
        val metrics = mutableListOf<String>()
        command.setStatistics.getOrNull(index)?.let { statistics ->
            statistics.activeSeconds?.let { metrics += "${it}s" }
            statistics.restBeforeSeconds?.takeIf { it > 0L }?.let { metrics += "R${it}s" }
            val hrValues = listOf(
                statistics.startHeartRate,
                statistics.peakHeartRate,
                statistics.endHeartRate
            )
            if (hrValues.any { it != null }) {
                metrics += "HR${hrValues.joinToString("/") { it?.toString() ?: "-" }}"
            }
            statistics.recoveryHeartRateDrop?.let { metrics += "↓$it" }
            statistics.detectionConfidence?.let { metrics += "C$it%" }
        }
        command.setIntervals.getOrNull(index)?.let { interval ->
            metrics += "I${interval.startOffsetSeconds}-${interval.endOffsetSeconds}s"
            metrics += "K${compactGarminDecimal(interval.gymCalories)}/${interval.garminCalories ?: "-"}"
            metrics += "Z${interval.heartRateZoneSeconds.joinToString("/")}s"
        }
        metrics.takeIf { it.isNotEmpty() }?.let { "S${index + 1} ${it.joinToString(" ")}" }
    }

    val fixedDetailCount = details.size
    var omittedDetails = 0
    for (index in perSetDetails.indices) {
        val setDetail = perSetDetails[index]
        val remainingAfterCandidate = perSetDetails.lastIndex - index
        val reservedMarker = remainingAfterCandidate
            .takeIf { it > 0 }
            ?.let { "S+$it" }
        val candidate = buildList {
            addAll(details)
            add(setDetail)
            reservedMarker?.let(::add)
        }.joinToString(separator = " · ")
        if (WorkoutDataLimits.isValidNote(candidate)) {
            details += setDetail
        } else {
            omittedDetails = perSetDetails.size - index
            break
        }
    }
    if (omittedDetails > 0) {
        var marker = "S+$omittedDetails"
        var candidate = (details + marker).joinToString(separator = " · ")
        // Every accepted row reserved this marker. Keep a defensive fallback so a future change to
        // the fixed diagnostics cannot silently discard the omission count at the note boundary.
        while (!WorkoutDataLimits.isValidNote(candidate) && details.size > fixedDetailCount) {
            details.removeAt(details.lastIndex)
            omittedDetails += 1
            marker = "S+$omittedDetails"
            candidate = (details + marker).joinToString(separator = " · ")
        }
        if (WorkoutDataLimits.isValidNote(candidate)) details += marker
    }
    return details.joinToString(separator = " · ")
}

private fun compactGarminDecimal(value: Double): String =
    BigDecimal.valueOf(value)
        .setScale(2, RoundingMode.HALF_UP)
        .stripTrailingZeros()
        .toPlainString()

class GarminSyncManager(
    private val application: GymApplication
) {
    private val coroutineExceptionHandler = CoroutineExceptionHandler { _, error ->
        lastPlanSyncStatus = "Garmin operation failed"
        Log.e(TAG, "Contained asynchronous Garmin failure", error)
    }
    private val scope = CoroutineScope(
        SupervisorJob() + Dispatchers.IO + coroutineExceptionHandler
    )
    private val connectIQ = ConnectIQ.getInstance(application, ConnectIQ.IQConnectType.WIRELESS)
    private val garminApp = IQApp(GARMIN_APP_ID)
    private val registeredDeviceEvents = GarminDeviceRegistrationTracker()
    private val registeredDevices = ConcurrentHashMap.newKeySet<Long>()
    private val knownDevicesById = ConcurrentHashMap<Long, IQDevice>()
    private val latestDeviceStatuses =
        ConcurrentHashMap<Long, IQDevice.IQDeviceStatus>()
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
    private val _deviceUiState = MutableStateFlow(GarminDeviceUiState())
    val deviceUiState: StateFlow<GarminDeviceUiState> = _deviceUiState.asStateFlow()
    @Volatile var lastPlanSyncStatus: String = "Not started"
        private set
    @Volatile private var sdkReady = false
    @Volatile private var sdkInitializationRequested = false
    @Volatile private var readyAuthTransitionKey: String? = null
    private val pairingStateMutex = Mutex()

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

    private data class AcceptedGarminWorkout(
        val account: GarminAccountContext,
        val binding: GarminBinding,
        val workout: GarminWorkoutCommand
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
            runCatching { registerConnectedDevices() }
                .onFailure { Log.e(TAG, "Cannot register Garmin SDK devices", it) }
        }

        override fun onInitializeError(errStatus: ConnectIQ.IQSdkErrorStatus) {
            sdkReady = false
            sdkInitializationRequested = false
            _deviceUiState.value = GarminDeviceUiState()
            Log.i(TAG, "Connect IQ unavailable: $errStatus")
        }

        override fun onSdkShutDown() {
            sdkReady = false
            sdkInitializationRequested = false
            registeredDeviceEvents.clear()
            registeredDevices.clear()
            knownDevicesById.clear()
            latestDeviceStatuses.clear()
            _deviceUiState.value = GarminDeviceUiState()
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
                    // Fail closed without invoking the third-party transport from an
                    // authentication callback. A previous SDK/process failure must not
                    // become a crash loop after every application restart or sign-in.
                    lastPlanSyncStatus =
                        "Open Garmin pairing reset before syncing the active account"
                }
                refreshDeviceUiState()
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
                val editor = preferences.edit()
                    .putString(LAST_READY_AUTH_TRANSITION_KEY, target.key)
                    .remove(PENDING_AUTH_TRANSITION_KEY)
                    .remove(PENDING_AUTH_ACCOUNT_BINDING_KEY)
                removeStalePairingPreferences(
                    editor = editor,
                    preferences = preferences,
                    retainedTargetKey = null,
                    retainedDeviceBinding = null
                )
                val committed = editor.commit()
                readyAuthTransitionKey = target.key.takeIf { committed }
                if (!committed) {
                    lastPlanSyncStatus = "Cannot persist Garmin account state"
                }
                return !committed
            }

            if (!resetRequired && trusted.state == GarminTrustedDeviceState.Pinned) {
                val editor = preferences.edit()
                removeStalePairingPreferences(
                    editor = editor,
                    preferences = preferences,
                    retainedTargetKey = target.key,
                    retainedDeviceBinding = trusted.binding
                )
                if (!editor.commit()) {
                    lastPlanSyncStatus = "Cannot prune stale Garmin pairing state"
                }
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

    /**
     * Explicitly rotates the workout replay generation for the trusted watch.
     *
     * The new generation is staged before transport work, blocks inbound workouts while pending,
     * and becomes active only after the watch acknowledges a destructive empty reset and the old
     * receipts have been retired locally.
     */
    suspend fun resetSecureGarminPairing(): Boolean {
        // Account transitions are deliberately cleared only after an explicit user
        // action. This keeps a failing Garmin SDK call from repeating on every login.
        if (pendingAuthTransition() != null) {
            sendPendingAuthResetIfPossible(GarminPendingResetTrigger.ExplicitUserAction)
            return pendingAuthTransition() == null
        }
        val account = activeAccountContext() ?: run {
            lastPlanSyncStatus = "Sign in before Garmin pairing reset"
            return false
        }
        if (!ensureSdkReady() || !isStillActive(account)) {
            lastPlanSyncStatus = "Garmin SDK not ready"
            return false
        }
        return pairingStateMutex.withLock {
            outboundSyncMutex.withLock outbound@{
            if (!isStillActive(account)) return@outbound false
            val trustedBinding = trustedDeviceBinding(account) ?: run {
                lastPlanSyncStatus = "No trusted Garmin watch is paired"
                return@outbound false
            }
            val resolution = resolveGarminDevices()
            if (resolution.failedStatus != null) {
                lastPlanSyncStatus = resolution.failedStatus
                return@outbound false
            }
            val device = resolution.connected
                .filter { deviceBinding(it) == trustedBinding }
                .distinctBy { it.deviceIdentifier }
                .singleOrNull()
                ?: run {
                    lastPlanSyncStatus = "Reconnect the trusted Garmin watch before pairing reset"
                    return@outbound false
                }
            registerAppEvents(device)

            if (!pairingGenerationSupported(account, trustedBinding)) {
                lastPlanSyncStatus =
                    "Update GymApp on the Garmin watch before resetting secure pairing"
                return@outbound false
            }

            val currentGeneration = pairingGenerationForReset(account, trustedBinding) ?: run {
                lastPlanSyncStatus = "Cannot persist Garmin pairing generation"
                return@outbound false
            }
            val pendingGeneration = beginPairingGenerationReset(
                account = account,
                deviceBinding = trustedBinding,
                currentGeneration = currentGeneration
            ) ?: run {
                lastPlanSyncStatus = "Cannot persist pending Garmin pairing reset"
                return@outbound false
            }
            val binding = GarminBinding(
                account = account.binding,
                device = trustedBinding,
                pairingGeneration = pendingGeneration
            )
            val syncId = newGarminMessageId()
            val revision = allocateSyncRevision(binding) ?: run {
                lastPlanSyncStatus = "Cannot persist Garmin reset revision"
                return@outbound false
            }
            val payload = boundGarminSyncPayload(
                payload = syncPayload(
                    exercises = emptyList(),
                    plan = emptyList(),
                    syncId = syncId,
                    resetWorkout = true
                ),
                binding = binding,
                syncRevision = revision
            ) ?: return@outbound false

            lastPlanSyncStatus = "Resetting secure Garmin pairing"
            val confirmed = sendAndConfirmSync(
                device = device,
                payload = payload,
                syncId = syncId,
                account = account,
                authTransitionKey = account.authTransitionKey,
                requireReadyAccount = true,
                binding = binding,
                revision = revision
            )
            if (!confirmed || !isStillActive(account)) return@outbound false

            val receiptsRetired = runCatching {
                application.repositoryFor(account.session).activateGarminPairingGeneration(
                    ownerBinding = binding.account,
                    deviceBinding = binding.device,
                    pairingGeneration = binding.pairingGeneration
                )
            }.onFailure { error ->
                Log.i(TAG, "Cannot retire Garmin receipts after pairing reset", error)
            }.isSuccess
            if (!receiptsRetired) {
                lastPlanSyncStatus = "Garmin reset acknowledged but local receipts were not updated"
                return@outbound false
            }
            if (!completePairingGenerationReset(account, trustedBinding, pendingGeneration)) {
                lastPlanSyncStatus = "Garmin reset acknowledged but local state was not saved"
                return@outbound false
            }
            lastPlanSyncStatus = "Secure Garmin pairing reset"
            true
            }
        }
    }

    internal fun clearCloudAccountLocalState(
        userId: String,
        sessionGeneration: String
    ): Boolean {
        val plan = synchronized(accountBindingLock) {
            val preferences = preferences()
            val resolved = garminCloudAccountLocalCleanupPlan(
                existingPreferences = preferences.all,
                userId = userId,
                sessionGeneration = sessionGeneration
            ) ?: return@synchronized null
            val editor = preferences.edit()
            resolved.preferenceKeys.forEach(editor::remove)
            if (!editor.commit()) return@synchronized null
            if (readyAuthTransitionKey == resolved.authTransitionKey) {
                readyAuthTransitionKey = null
            }
            resolved
        } ?: return false

        pendingSyncAcks.entries.forEach { entry ->
            val pending = entry.value
            if ((pending.account?.binding == plan.accountBinding ||
                    pending.authTransitionKey == plan.authTransitionKey) &&
                pendingSyncAcks.remove(entry.key, pending)
            ) {
                pending.deferred.complete(false)
            }
        }
        lastPlanSyncStatus = "Deleted account Garmin data cleared"
        return true
    }

    private fun registerConnectedDevices() {
        val devices = try {
            connectIQ.knownDevices.orEmpty()
        } catch (error: Exception) {
            Log.i(TAG, "Cannot list Garmin devices", error)
            emptyList()
        }
        Log.i(TAG, "Known Garmin device count=${devices.size}")
        knownDevicesById.clear()
        devices.forEach { knownDevicesById[it.deviceIdentifier] = it }

        devices.forEach { device ->
            if (registeredDeviceEvents.claim(device.deviceIdentifier)) {
                runCatching {
                    connectIQ.registerForDeviceEvents(device) { changedDevice, status ->
                        runCatching {
                            Log.i(TAG, "Garmin device event status=$status")
                            latestDeviceStatuses[changedDevice.deviceIdentifier] = status
                            refreshDeviceUiState()
                            if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                                registerAppEvents(changedDevice)
                            }
                        }.onFailure { error ->
                            Log.e(TAG, "Rejected malformed Garmin device callback", error)
                        }
                    }
                }.onFailure {
                    registeredDeviceEvents.release(device.deviceIdentifier)
                    Log.i(TAG, "Cannot register Garmin device events", it)
                }
            }
            runCatching {
                val status = connectIQ.getDeviceStatus(device)
                latestDeviceStatuses[device.deviceIdentifier] = status
                Log.i(TAG, "Garmin device status=$status")
                if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                    registerAppEvents(device)
                }
            }.onFailure { Log.i(TAG, "Cannot register Garmin device", it) }
        }
        refreshDeviceUiState()
    }

    private suspend fun ensureSdkReady(): Boolean {
        if (!sdkReady) {
            initialize()
            val initialized = withTimeoutOrNull(GARMIN_SDK_READY_TIMEOUT_MS) {
                while (!sdkReady && sdkInitializationRequested) {
                    delay(150L)
                }
                sdkReady
            } ?: false
            if (!initialized) return false
        }
        registerConnectedDevices()
        return true
    }

    private fun registerAppEvents(device: IQDevice) {
        if (!registeredDevices.add(device.deviceIdentifier)) return
        try {
            connectIQ.registerForAppEvents(device, garminApp) { source, _, messages, _ ->
                runCatching {
                    if (source.deviceIdentifier != device.deviceIdentifier) {
                        return@runCatching
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
                }.onFailure { error ->
                    Log.e(TAG, "Rejected malformed Garmin app callback", error)
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
        val advertisesGeneration = garminCommandAdvertisesPairingGeneration(command)
        val supportsGeneration = advertisesGeneration ||
            pairingGenerationSupported(account, sourceDeviceBinding) ||
            command["pairingGeneration"] is String
        if (
            advertisesGeneration &&
            !recordPairingGenerationCapability(account, sourceDeviceBinding)
        ) {
            return
        }
        val pairingGeneration = if (supportsGeneration) {
            activePairingGeneration(account, sourceDeviceBinding) ?: return
        } else {
            LEGACY_GARMIN_FALLBACK_GENERATION
        }
        val binding = GarminBinding(
            account = account.binding,
            device = sourceDeviceBinding,
            pairingGeneration = pairingGeneration
        )
        val mismatch = garminSyncRequestBindingMismatch(
            command = command,
            expected = binding
        )
        if (mismatch != GarminSyncRequestBindingMismatch.None) {
            if (
                advertisesGeneration &&
                garminSyncRequestCanRepairPairing(command = command, expected = binding)
            ) {
                // The transport source is the already pinned physical watch and both
                // account/device bindings match. Rotate only the watch-side receipt
                // generation; the watch preserves its active and queued workouts.
                Log.i(TAG, "Repairing Garmin pairing generation")
                lastPlanSyncStatus = "Repairing secure Garmin pairing"
                pushSyncForContext(
                    device = device,
                    account = account,
                    generationSupportOverride = true,
                    repairPairing = true
                )
                return
            }
            // Log only the mismatch category. Bindings and device identifiers are
            // intentionally never written to diagnostics.
            Log.i(TAG, "Rejected Garmin sync request: ${mismatch.name}")
            return
        }
        pushSyncForContext(device, account, supportsGeneration)
    }

    private suspend fun createWorkout(device: IQDevice, command: Map<Any?, Any?>) {
        val accepted = pairingStateMutex.withLock {
            val account = activeAccountContext() ?: return@withLock null
            val sourceDeviceBinding = deviceBinding(device)
            if (trustedDeviceBinding(account) != sourceDeviceBinding) {
                Log.i(TAG, "Rejected Garmin workout from an untrusted device")
                return@withLock null
            }
            val rawGeneration = command["pairingGeneration"]
            val supportsGeneration = pairingGenerationSupported(account, sourceDeviceBinding)
            val pairingGeneration = when (rawGeneration) {
                null -> {
                    if (supportsGeneration) return@withLock null
                    LEGACY_GARMIN_FALLBACK_GENERATION
                }
                is String -> activePairingGeneration(account, sourceDeviceBinding)
                    ?: return@withLock null
                else -> return@withLock null
            }
            val binding = GarminBinding(
                account = account.binding,
                device = sourceDeviceBinding,
                pairingGeneration = pairingGeneration
            )
            if (
                garminBindingDecision(
                    command = command,
                    expected = binding
                ) != GarminBindingDecision.Bound
            ) {
                Log.i(TAG, "Rejected unbound Garmin workout")
                return@withLock null
            }
            if (
                rawGeneration is String &&
                !recordPairingGenerationCapability(account, sourceDeviceBinding)
            ) {
                return@withLock null
            }

            val parseResult = parseGarminWorkoutCommandResult(
                command = command,
                nowMillis = System.currentTimeMillis()
            )
            val workout = parseResult.command ?: run {
                // The category is intentionally value-free: no request identifiers,
                // exercise names, metrics, bindings, or device IDs enter diagnostics.
                Log.i(TAG, "Rejected Garmin workout: ${parseResult.issue?.name ?: "Unknown"}")
                return@withLock null
            }

            when (persistWorkout(account, binding, workout)) {
                WorkoutPersistenceResult.Rejected -> null
                WorkoutPersistenceResult.Created,
                WorkoutPersistenceResult.AlreadyProcessed ->
                    AcceptedGarminWorkout(account, binding, workout)
            }
        } ?: return

        sendAndWait(
            device,
            boundGarminPayload(
                payload = mapOf(
                    "type" to "ack",
                    "requestId" to accepted.workout.requestId
                ),
                binding = accepted.binding,
                includePairingGeneration =
                    accepted.binding.pairingGeneration != LEGACY_GARMIN_FALLBACK_GENERATION
            )
        )
        if (isStillActive(accepted.account)) {
            pushSyncForContext(device, accepted.account)
        }
    }

    private suspend fun pushSyncForContext(
        device: IQDevice,
        account: GarminAccountContext,
        generationSupportOverride: Boolean? = null,
        repairPairing: Boolean = false
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
            val basePayload = syncPayload(
                exercises = exercises,
                plan = plan,
                syncId = syncId,
                resetWorkout = false,
                repairPairing = repairPairing
            )
            if (!cachePlan(plan, account, deviceBinding)) return@withLock
            if (!isStillActive(account)) return@withLock
            val supportsGeneration = generationSupportOverride
                ?: pairingGenerationSupported(account, deviceBinding)
            val pairingGeneration = if (supportsGeneration) {
                activePairingGeneration(account, deviceBinding) ?: return@withLock
            } else {
                LEGACY_GARMIN_FALLBACK_GENERATION
            }
            val binding = GarminBinding(
                account = account.binding,
                device = deviceBinding,
                pairingGeneration = pairingGeneration
            )
            val revision = allocateSyncRevision(binding) ?: run {
                lastPlanSyncStatus = "Cannot persist Garmin sync revision"
                return@withLock
            }
            val payload = boundGarminSyncPayload(
                basePayload,
                binding,
                revision,
                includePairingGeneration = supportsGeneration
            )
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
        resetWorkout: Boolean = false,
        repairPairing: Boolean = false
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
        if (repairPairing) {
            payload["repairPairing"] = true
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
            val supportsGeneration = pairingGenerationSupported(account, deviceBinding)
            val pairingGeneration = if (supportsGeneration) {
                activePairingGeneration(account, deviceBinding) ?: run {
                    lastPlanSyncStatus = "Cannot persist Garmin pairing generation"
                    return false
                }
            } else {
                LEGACY_GARMIN_FALLBACK_GENERATION
            }
            val binding = GarminBinding(
                account = account.binding,
                device = deviceBinding,
                pairingGeneration = pairingGeneration
            )
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
            val payload = boundGarminSyncPayload(
                basePayload,
                binding,
                revision,
                includePairingGeneration = supportsGeneration
            ) ?: return false
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

    private suspend fun sendPendingAuthResetIfPossible(trigger: GarminPendingResetTrigger) {
        if (!shouldAttemptPendingGarminReset(trigger)) return
        if (pendingAuthTransition() == null) return
        if (!ensureSdkReady()) {
            lastPlanSyncStatus = "Reconnect the trusted Garmin watch to clear old account data"
            return
        }
        pairingStateMutex.withLock {
            outboundSyncMutex.withLock outbound@{
            val target = pendingAuthTransition() ?: return@outbound
            if (currentAuthTransitionTarget() != target) return@outbound

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
                return@outbound
            }

            val resolution = resolveGarminDevices()
            if (resolution.failedStatus != null) {
                lastPlanSyncStatus = resolution.failedStatus
                return@outbound
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
                    return@outbound
                }
            registerAppEvents(device)

            if (
                pendingAuthTransition() != target ||
                currentAuthTransitionTarget() != target
            ) {
                return@outbound
            }
            val syncId = newGarminMessageId()
            val supportsGeneration = pairingGenerationSupported(target, trustedBinding)
            val pairingGeneration = if (supportsGeneration) {
                activePairingGeneration(target, trustedBinding) ?: run {
                    lastPlanSyncStatus = "Cannot persist Garmin pairing generation"
                    return@outbound
                }
            } else {
                LEGACY_GARMIN_FALLBACK_GENERATION
            }
            val binding = GarminBinding(
                account = target.accountBinding,
                device = trustedBinding,
                pairingGeneration = pairingGeneration
            )
            val revision = allocateSyncRevision(binding) ?: run {
                lastPlanSyncStatus = "Cannot persist Garmin reset revision"
                return@outbound
            }
            val basePayload = syncPayload(
                exercises = emptyList(),
                plan = emptyList(),
                syncId = syncId,
                resetWorkout = true
            )
            val payload = boundGarminSyncPayload(
                basePayload,
                binding,
                revision,
                includePairingGeneration = supportsGeneration
            )
                ?: return@outbound
            if (
                pendingAuthTransition() != target ||
                currentAuthTransitionTarget() != target
            ) {
                return@outbound
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
            if (
                confirmed &&
                activatePairingGenerationForCurrentAccount(target, binding) &&
                completeAuthTransitionReset(target)
            ) {
                lastPlanSyncStatus = "Garmin account data cleared"
            }
            }
        }
    }

    private suspend fun activatePairingGenerationForCurrentAccount(
        target: GarminAuthTransitionTarget,
        binding: GarminBinding
    ): Boolean {
        val account = rawActiveAccountContext()
        if (account == null || account.authTransitionKey != target.key) {
            return true
        }
        return runCatching {
            application.repositoryFor(account.session).activateGarminPairingGeneration(
                ownerBinding = binding.account,
                deviceBinding = binding.device,
                pairingGeneration = binding.pairingGeneration
            )
        }.onFailure { error ->
            Log.i(TAG, "Cannot retire stale Garmin pairing receipts", error)
            lastPlanSyncStatus = "Garmin reset acknowledged but local receipts were not updated"
        }.isSuccess
    }

    private fun completeAuthTransitionReset(target: GarminAuthTransitionTarget): Boolean {
        if (currentAuthTransitionTarget() != target) return false
        synchronized(accountBindingLock) {
            val preferences = preferences()
            if (pendingAuthTransitionLocked(preferences) != target) return false
            val trusted = trustedDeviceResolutionLocked(preferences, migrateLegacy = true)
            val retainedDevice = trusted.binding.takeIf {
                trusted.state == GarminTrustedDeviceState.Pinned
            }
            val editor = preferences.edit()
                .putString(LAST_READY_AUTH_TRANSITION_KEY, target.key)
                .remove(PENDING_AUTH_TRANSITION_KEY)
                .remove(PENDING_AUTH_ACCOUNT_BINDING_KEY)
            removeStalePairingPreferences(
                editor = editor,
                preferences = preferences,
                retainedTargetKey = target.key,
                retainedDeviceBinding = retainedDevice
            )
            val committed = editor.commit()
            if (committed) {
                readyAuthTransitionKey = target.key
            } else {
                lastPlanSyncStatus = "Garmin reset acknowledged but local state was not saved"
            }
            return committed
        }
    }

    private fun removeStalePairingPreferences(
        editor: android.content.SharedPreferences.Editor,
        preferences: android.content.SharedPreferences,
        retainedTargetKey: String?,
        retainedDeviceBinding: String?
    ) {
        val retainedKeys = if (
            retainedTargetKey != null &&
            isValidGarminAccountBinding(retainedTargetKey) &&
            retainedDeviceBinding != null &&
            isValidGarminTransportDeviceBinding(retainedDeviceBinding)
        ) {
            setOf(
                garminStorageKey(
                    PAIRING_GENERATION_KEY_PREFIX,
                    retainedTargetKey,
                    retainedDeviceBinding
                ),
                garminStorageKey(
                    PENDING_PAIRING_GENERATION_KEY_PREFIX,
                    retainedTargetKey,
                    retainedDeviceBinding
                ),
                garminStorageKey(
                    PAIRING_GENERATION_CAPABILITY_KEY_PREFIX,
                    retainedTargetKey,
                    retainedDeviceBinding
                )
            )
        } else {
            emptySet()
        }
        val pairingPrefixes = listOf(
            "${PAIRING_GENERATION_KEY_PREFIX}_",
            "${PENDING_PAIRING_GENERATION_KEY_PREFIX}_",
            "${PAIRING_GENERATION_CAPABILITY_KEY_PREFIX}_"
        )
        garminScopedPreferenceKeysToRemove(
            existingKeys = preferences.all.keys,
            retainedKeys = retainedKeys,
            scopedPrefixes = pairingPrefixes
        ).forEach(editor::remove)
    }

    private data class GarminDeviceResolution(
        val connected: List<IQDevice>,
        val known: List<IQDevice>,
        val failedStatus: String? = null
    )

    private fun refreshDeviceUiState() {
        if (!sdkReady) {
            _deviceUiState.value = GarminDeviceUiState()
            return
        }
        val account = rawActiveAccountContext()
        val trustedBinding = account?.let(::trustedDeviceBinding)
        // Device callbacks already carry the new status. Do not call getDeviceStatus
        // from inside that callback: some Garmin Connect versions synchronously
        // dispatch another status callback and can recurse until the process dies.
        val knownDevices = knownDevicesById.values
            .sortedBy { it.deviceIdentifier }
        _deviceUiState.value = GarminDeviceUiState(
            sdkReady = true,
            devices = knownDevices
                .take(MAX_PROFILE_GARMIN_DEVICES)
                .map { device ->
                    val name = runCatching { device.friendlyName }
                        .getOrNull()
                        ?.trim()
                        ?.take(MAX_PROFILE_DEVICE_NAME_CHARS)
                        ?.takeIf { it.isNotBlank() && it.none(Char::isISOControl) }
                        ?: "Garmin watch"
                    GarminDeviceSummary(
                        name = name,
                        connected = latestDeviceStatuses[device.deviceIdentifier] ==
                            IQDevice.IQDeviceStatus.CONNECTED,
                        trustedForActiveAccount = trustedBinding == deviceBinding(device)
                    )
                }
        )
    }

    private fun resolveGarminDevices(): GarminDeviceResolution = try {
        val connected = connectIQ.connectedDevices.orEmpty()
        val known = connectIQ.knownDevices.orEmpty()
        known.forEach { knownDevicesById[it.deviceIdentifier] = it }
        val connectedByStatus = known.filter { device ->
            runCatching {
                val status = connectIQ.getDeviceStatus(device)
                latestDeviceStatuses[device.deviceIdentifier] = status
                status == IQDevice.IQDeviceStatus.CONNECTED
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
            // Connect IQ transport SUCCESS and the app-level sync_ack are separate
            // events. If the watch applied the plan but its acknowledgement was
            // dropped, resend the exact same sync ID and revision. The watch's
            // durable replay fence treats that as a successful no-op and emits the
            // acknowledgement again; no plan mutation is repeated.
            val confirmed = withTimeoutOrNull(GARMIN_SYNC_TOTAL_TIMEOUT_MS) {
                for (attempt in 1..GARMIN_SYNC_ACK_ATTEMPTS) {
                    if (!pendingContextIsCurrent(pending)) {
                        return@withTimeoutOrNull false
                    }
                    if (ack.isCompleted) {
                        return@withTimeoutOrNull ack.await()
                    }
                    val sent = sendAndWait(device, payload)
                    if (ack.isCompleted) {
                        return@withTimeoutOrNull ack.await()
                    }
                    if (!sent) {
                        if (attempt == GARMIN_SYNC_ACK_ATTEMPTS) {
                            return@withTimeoutOrNull false
                        }
                        continue
                    }
                    val acknowledged = withTimeoutOrNull(
                        GARMIN_SYNC_ACK_ATTEMPT_TIMEOUT_MS
                    ) {
                        ack.await()
                    }
                    if (acknowledged != null) {
                        return@withTimeoutOrNull acknowledged
                    }
                    if (attempt < GARMIN_SYNC_ACK_ATTEMPTS) {
                        lastPlanSyncStatus =
                            "Waiting for Garmin acknowledgement; retrying the same sync"
                        Log.i(TAG, "Garmin sync acknowledgement missed; retrying idempotently")
                    }
                }
                false
            } ?: false
            if (!confirmed) {
                lastPlanSyncStatus =
                    "Garmin watch did not acknowledge the sync after bounded retries"
                Log.i(TAG, "Garmin sync acknowledgement retries exhausted")
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
        return garminWorkoutNote(command, application.languageManager.currentLanguage())
    }

    private suspend fun persistWorkout(
        account: GarminAccountContext,
        binding: GarminBinding,
        workout: GarminWorkoutCommand
    ): WorkoutPersistenceResult {
        if (!isStillActive(account)) return WorkoutPersistenceResult.Rejected
        val payloadDigest = canonicalGarminWorkoutPayloadDigest(workout)
        val legacyPayloadDigest = legacyGarminWorkoutPayloadDigestForUpgrade(workout)
        val result = runCatching {
            application.repositoryFor(account.session).applyGarminCreateWorkout(
                ownerBinding = binding.account,
                deviceBinding = binding.device,
                pairingGeneration = binding.pairingGeneration,
                requestId = workout.requestId,
                payloadDigest = payloadDigest,
                date = workout.startedAtMillis,
                note = buildGarminWorkoutNote(workout),
                sets = workout.sets,
                legacyPayloadDigest = legacyPayloadDigest
            )
        }.getOrElse { error ->
            Log.i(TAG, "Cannot atomically persist Garmin workout receipt", error)
            return WorkoutPersistenceResult.Rejected
        }
        if (!isStillActive(account)) return WorkoutPersistenceResult.Rejected
        return when (result) {
            GarminWorkoutApplyResult.Applied -> WorkoutPersistenceResult.Created
            GarminWorkoutApplyResult.AlreadyApplied -> WorkoutPersistenceResult.AlreadyProcessed
            GarminWorkoutApplyResult.RateLimited -> {
                lastPlanSyncStatus = "Garmin workout rate limit reached; retry later"
                WorkoutPersistenceResult.Rejected
            }
            GarminWorkoutApplyResult.PairingLimitReached -> {
                lastPlanSyncStatus = "Garmin secure pairing workout limit reached; reset pairing"
                WorkoutPersistenceResult.Rejected
            }
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

    private fun activePairingGeneration(
        account: GarminAccountContext,
        deviceBinding: String
    ): String? {
        if (!isStillActive(account)) return null
        return activePairingGeneration(
            target = GarminAuthTransitionTarget(
                key = account.authTransitionKey,
                accountBinding = account.binding
            ),
            deviceBinding = deviceBinding
        )
    }

    private fun activePairingGeneration(
        target: GarminAuthTransitionTarget,
        deviceBinding: String
    ): String? {
        if (!isValidGarminTransportDeviceBinding(deviceBinding)) return null
        val activeKey = garminStorageKey(
            PAIRING_GENERATION_KEY_PREFIX,
            target.key,
            deviceBinding
        )
        val pendingKey = garminStorageKey(
            PENDING_PAIRING_GENERATION_KEY_PREFIX,
            target.key,
            deviceBinding
        )
        synchronized(accountBindingLock) {
            val preferences = preferences()
            if (preferences.contains(pendingKey)) return null
            val stored = preferences.getStringSafely(activeKey)
            if (preferences.contains(activeKey)) {
                return stored?.takeIf(::isValidGarminPairingGeneration)
            }
            val generated = newGarminPairingGeneration()
            return generated.takeIf {
                preferences.edit().putString(activeKey, generated).commit()
            }
        }
    }

    private fun pairingGenerationSupported(
        account: GarminAccountContext,
        deviceBinding: String
    ): Boolean {
        if (!isStillActive(account)) return false
        return pairingGenerationSupported(
            GarminAuthTransitionTarget(account.authTransitionKey, account.binding),
            deviceBinding
        )
    }

    private fun pairingGenerationSupported(
        target: GarminAuthTransitionTarget,
        deviceBinding: String
    ): Boolean {
        if (!isValidGarminTransportDeviceBinding(deviceBinding)) return false
        val key = garminStorageKey(
            PAIRING_GENERATION_CAPABILITY_KEY_PREFIX,
            target.key,
            deviceBinding
        )
        synchronized(accountBindingLock) {
            val preferences = preferences()
            if (!preferences.contains(key)) return false
            return runCatching { preferences.getBoolean(key, false) }.getOrDefault(false)
        }
    }

    private fun recordPairingGenerationCapability(
        account: GarminAccountContext,
        deviceBinding: String
    ): Boolean {
        if (!isStillActive(account) || !isValidGarminTransportDeviceBinding(deviceBinding)) {
            return false
        }
        val key = garminStorageKey(
            PAIRING_GENERATION_CAPABILITY_KEY_PREFIX,
            account.authTransitionKey,
            deviceBinding
        )
        synchronized(accountBindingLock) {
            val preferences = preferences()
            if (runCatching { preferences.getBoolean(key, false) }.getOrDefault(false)) {
                return true
            }
            return preferences.edit().putBoolean(key, true).commit()
        }
    }

    private fun beginPairingGenerationReset(
        account: GarminAccountContext,
        deviceBinding: String,
        currentGeneration: String
    ): String? {
        if (
            !isStillActive(account) ||
            !isValidGarminTransportDeviceBinding(deviceBinding) ||
            !isValidGarminPairingGeneration(currentGeneration)
        ) {
            return null
        }
        val pendingKey = garminStorageKey(
            PENDING_PAIRING_GENERATION_KEY_PREFIX,
            account.authTransitionKey,
            deviceBinding
        )
        synchronized(accountBindingLock) {
            val preferences = preferences()
            val existing = preferences.getStringSafely(pendingKey)
            if (preferences.contains(pendingKey)) {
                return existing?.takeIf {
                    isValidGarminPairingGeneration(it) && it != currentGeneration
                }
            }
            var generated = newGarminPairingGeneration()
            if (generated == currentGeneration) {
                generated = newGarminPairingGeneration()
            }
            if (generated == currentGeneration) return null
            return generated.takeIf {
                preferences.edit().putString(pendingKey, generated).commit()
            }
        }
    }

    private fun pairingGenerationForReset(
        account: GarminAccountContext,
        deviceBinding: String
    ): String? {
        if (!isStillActive(account) || !isValidGarminTransportDeviceBinding(deviceBinding)) {
            return null
        }
        val activeKey = garminStorageKey(
            PAIRING_GENERATION_KEY_PREFIX,
            account.authTransitionKey,
            deviceBinding
        )
        synchronized(accountBindingLock) {
            val preferences = preferences()
            val stored = preferences.getStringSafely(activeKey)
            if (preferences.contains(activeKey)) {
                return stored?.takeIf(::isValidGarminPairingGeneration)
            }
            val pendingKey = garminStorageKey(
                PENDING_PAIRING_GENERATION_KEY_PREFIX,
                account.authTransitionKey,
                deviceBinding
            )
            if (preferences.contains(pendingKey)) return null
            val generated = newGarminPairingGeneration()
            return generated.takeIf {
                preferences.edit().putString(activeKey, generated).commit()
            }
        }
    }

    private fun completePairingGenerationReset(
        account: GarminAccountContext,
        deviceBinding: String,
        expectedGeneration: String
    ): Boolean {
        if (
            !isStillActive(account) ||
            !isValidGarminTransportDeviceBinding(deviceBinding) ||
            !isValidGarminPairingGeneration(expectedGeneration)
        ) {
            return false
        }
        val activeKey = garminStorageKey(
            PAIRING_GENERATION_KEY_PREFIX,
            account.authTransitionKey,
            deviceBinding
        )
        val pendingKey = garminStorageKey(
            PENDING_PAIRING_GENERATION_KEY_PREFIX,
            account.authTransitionKey,
            deviceBinding
        )
        synchronized(accountBindingLock) {
            val preferences = preferences()
            if (preferences.getStringSafely(pendingKey) != expectedGeneration) return false
            val editor = preferences.edit()
                .putString(activeKey, expectedGeneration)
                .remove(pendingKey)
            removeStalePairingPreferences(
                editor = editor,
                preferences = preferences,
                retainedTargetKey = account.authTransitionKey,
                retainedDeviceBinding = deviceBinding
            )
            return editor.commit()
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

    private fun deviceBinding(device: IQDevice): String = device.deviceIdentifier.toString()

    private fun newGarminMessageId(): String = UUID.randomUUID().toString()

    private fun preferences() = application.getSharedPreferences(
        PLAN_PREFERENCES,
        Context.MODE_PRIVATE
    )
}

private fun android.content.SharedPreferences.getStringSafely(key: String): String? =
    all[key] as? String

internal fun garminScopedPreferenceKeysToRemove(
    existingKeys: Set<String>,
    retainedKeys: Set<String>,
    scopedPrefixes: List<String>
): Set<String> = existingKeys.filterTo(linkedSetOf()) { key ->
    key !in retainedKeys && scopedPrefixes.any(key::startsWith)
}
