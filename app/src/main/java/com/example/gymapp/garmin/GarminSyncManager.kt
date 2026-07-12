package com.example.gymapp.garmin

import android.util.Log
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.example.gymapp.GymApplication
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
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

private const val TAG = "GarminSync"
private const val GARMIN_APP_ID = "A72A5B9F4E3D4E5A8B72C1D9F6123E40"
private const val PLAN_PREFERENCES = "garmin_sync"
private const val PLAN_KEY = "cached_plan"
private const val PROCESSED_IDS_KEY = "processed_ids"
private const val MAX_WATCH_EXERCISES = 60
private const val MAX_WATCH_PLAN_SETS = 60
private const val GARMIN_SDK_READY_TIMEOUT_MS = 60_000L
private const val GARMIN_SEND_TIMEOUT_MS = 90_000L
private const val GARMIN_SYNC_ACK_TIMEOUT_MS = 30_000L
private const val GARMIN_CONNECT_WAIT_MS = 45_000L

class GarminSyncManager(
    private val application: GymApplication
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val connectIQ = ConnectIQ.getInstance(application, ConnectIQ.IQConnectType.WIRELESS)
    private val garminApp = IQApp(GARMIN_APP_ID)
    private val registeredDevices = ConcurrentHashMap.newKeySet<Long>()
    private val pendingSyncAcks = ConcurrentHashMap<String, CompletableDeferred<Boolean>>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val initializationLock = Any()
    @Volatile var lastPlanSyncStatus: String = "Not started"
        private set
    @Volatile private var sdkReady = false
    @Volatile private var sdkInitializationRequested = false

    private val listener = object : ConnectIQ.ConnectIQListener {
        override fun onSdkReady() {
            sdkReady = true
            sdkInitializationRequested = false
            Log.i(TAG, "Connect IQ SDK ready")
            registerConnectedDevices()
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

    suspend fun cacheAndPushPlan(
        sets: List<NamedWorkoutSetDraft>,
        exerciseCatalog: List<String>
    ): Boolean {
        val syncId = System.currentTimeMillis().toString(36)
        val payload = syncPayload(exerciseCatalog, sets, syncId, resetWorkout = true)
        cachePlan(sets)
        lastPlanSyncStatus = "Waiting for Garmin SDK"
        if (!ensureSdkReady()) {
            lastPlanSyncStatus = "Garmin SDK not ready"
            return false
        }
        return sendToConnectedDevices(payload, syncId)
    }

    private fun registerConnectedDevices() {
        val devices = try {
            connectIQ.knownDevices.orEmpty()
        } catch (error: Exception) {
            Log.i(TAG, "Cannot list Garmin devices", error)
            emptyList()
        }
        Log.i(TAG, "Known Garmin devices=${devices.joinToString { "${it.friendlyName}:${it.status}" }}")

        devices.forEach { device ->
            runCatching {
                connectIQ.registerForDeviceEvents(device) { changedDevice, status ->
                    Log.i(TAG, "Device event ${changedDevice.friendlyName}: $status")
                    if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                        registerAppEvents(changedDevice)
                    }
                }
                val status = connectIQ.getDeviceStatus(device)
                Log.i(TAG, "Device status ${device.friendlyName}: $status")
                if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                    registerAppEvents(device)
                }
            }.onFailure { Log.i(TAG, "Cannot register ${device.friendlyName}", it) }
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
                Log.i(TAG, "Received ${messages.size} Garmin message(s) from ${source.friendlyName}")
                messages.forEach { message ->
                    @Suppress("UNCHECKED_CAST")
                    val command = message as? Map<Any?, Any?> ?: return@forEach
                    Log.i(TAG, "Garmin command type=${command["type"]} payload=$command")
                    handleCommand(source, command)
                }
            }
            Log.i(TAG, "Registered Garmin app events for ${device.friendlyName}")
        } catch (error: Exception) {
            registeredDevices.remove(device.deviceIdentifier)
            Log.i(TAG, "Cannot listen for GymApp messages", error)
        }
    }

    private fun handleCommand(device: IQDevice, command: Map<Any?, Any?>) {
        when (command["type"]?.toString()) {
            "request_sync" -> scope.launch { pushSync(device) }
            "create_workout" -> scope.launch { createWorkout(device, command) }
            "sync_ack" -> handleSyncAck(command)
        }
    }

    private fun handleSyncAck(command: Map<Any?, Any?>) {
        val syncId = command["syncId"]?.toString().orEmpty()
        if (syncId.isEmpty()) return
        lastPlanSyncStatus = "ACK plan=${command["planCount"]} exercises=${command["exerciseCount"]} lang=${command["language"]}"
        Log.i(
            TAG,
            "Garmin sync ack syncId=$syncId $lastPlanSyncStatus"
        )
        pendingSyncAcks.remove(syncId)?.complete(true)
    }

    private suspend fun pushSync(device: IQDevice) {
        val repository = activeRepository()
        val exercises = repository.getExerciseNamesForSync(limit = 200)
        val syncId = "rq" + System.currentTimeMillis().toString(36)
        val payload = syncPayload(exercises, cachedPlan(), syncId, resetWorkout = false)
        Log.i(TAG, "Replying to watch request_sync payload=${payloadSummary(payload)}")
        sendAndConfirmSync(device, payload, syncId)
    }

    private suspend fun createWorkout(device: IQDevice, command: Map<Any?, Any?>) {
        val requestId = command["requestId"]?.toString().orEmpty()
        if (requestId.isNotEmpty() && requestId in processedRequestIds()) {
            sendAndWait(device, mapOf("type" to "ack", "requestId" to requestId))
            return
        }

        val rawSets = command["sets"] as? List<*> ?: emptyList<Any>()
        val sets = rawSets.mapNotNull { raw ->
            @Suppress("UNCHECKED_CAST")
            val item = raw as? Map<Any?, Any?> ?: return@mapNotNull null
            val exerciseName = item["exerciseName"]?.toString()?.trim().orEmpty()
            val weight = (item["weight"] as? Number)?.toDouble()
            val reps = (item["reps"] as? Number)?.toInt()
            if (exerciseName.isBlank() || weight == null || weight < 0.0 || reps == null || reps <= 0) {
                null
            } else {
                NamedWorkoutSetDraft(exerciseName, weight, reps)
            }
        }
        if (sets.isEmpty()) return

        val startedAtSeconds = (command["startedAtSeconds"] as? Number)?.toLong()
        val note = buildGarminWorkoutNote(command)
        activeRepository().createWorkoutSessionFromNamedSets(
            date = startedAtSeconds?.times(1000L) ?: System.currentTimeMillis(),
            note = note,
            sets = sets
        )
        rememberProcessed(requestId)
        sendAndWait(device, mapOf("type" to "ack", "requestId" to requestId))
        pushSync(device)
    }

    private fun syncPayload(
        exercises: List<String>,
        plan: List<NamedWorkoutSetDraft>,
        syncId: String? = null,
        resetWorkout: Boolean = false
    ): Map<String, Any> {
        val compactPlan = plan.take(MAX_WATCH_PLAN_SETS)
        val planExerciseNames = compactPlan.map { it.exerciseName }
        val exerciseSource = if (planExerciseNames.isNotEmpty()) {
            planExerciseNames
        } else {
            exercises
        }
        val compactExercises = exerciseSource
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .take(MAX_WATCH_EXERCISES)

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
        }
        return payload
    }

    private suspend fun sendToConnectedDevices(payload: Map<String, Any>, syncId: String? = null): Boolean {
        if (!sdkReady) return false
        val initial = resolveGarminDevices()
        if (initial.failedStatus != null) {
            lastPlanSyncStatus = initial.failedStatus
            return false
        }
        var devices = initial.connected
        val knownDevices = initial.known

        if (devices.isEmpty() && knownDevices.isNotEmpty()) {
            lastPlanSyncStatus = "Waiting for Garmin Bluetooth: ${knownDeviceStatus(knownDevices)}"
            Log.i(TAG, lastPlanSyncStatus)
            val deadline = System.currentTimeMillis() + GARMIN_CONNECT_WAIT_MS
            while (devices.isEmpty() && System.currentTimeMillis() < deadline) {
                delay(1_000L)
                val retry = resolveGarminDevices()
                if (retry.failedStatus != null) {
                    lastPlanSyncStatus = retry.failedStatus
                    return false
                }
                devices = retry.connected
            }
        }

        val targets = if (devices.isNotEmpty()) {
            devices
        } else {
            // Connect IQ can occasionally report a stale NOT_CONNECTED status even
            // when the watch app is open. Try paired devices once; sendMessage will
            // return a concrete transport status if Bluetooth is truly unavailable.
            knownDevices
        }

        if (targets.isEmpty()) {
            lastPlanSyncStatus = if (knownDevices.isEmpty()) {
                "No Garmin devices paired in Garmin Connect"
            } else {
                "Garmin Bluetooth not ready: ${knownDeviceStatus(knownDevices)}. Disconnect watch USB, open Garmin Connect, then open GymApp on watch."
            }
            Log.i(TAG, lastPlanSyncStatus)
            return false
        }

        if (devices.isEmpty()) {
            Log.i(TAG, "Trying paired Garmin devices despite no CONNECTED status: ${knownDeviceStatus(targets)}")
        }
        Log.i(TAG, "Sending sync to devices=${targets.joinToString { it.friendlyName }} payload=${payloadSummary(payload)}")
        targets.forEach { device ->
            registerAppEvents(device)
            if (sendAndConfirmSync(device, payload, syncId)) {
                lastPlanSyncStatus = lastPlanSyncStatus.ifBlank { "ACK" }
                Log.i(TAG, "Garmin sync completed on ${device.friendlyName}; skipping remaining devices")
                return true
            }
        }
        return false
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
        syncId: String?
    ): Boolean {
        if (syncId.isNullOrBlank()) {
            return sendAndWait(device, payload)
        }
        val ack = CompletableDeferred<Boolean>()
        pendingSyncAcks[syncId] = ack
        val sent = sendAndWait(device, payload)
        if (!sent) {
            pendingSyncAcks.remove(syncId)
            return false
        }
        val confirmed = withTimeoutOrNull(GARMIN_SYNC_ACK_TIMEOUT_MS) { ack.await() } ?: false
        pendingSyncAcks.remove(syncId)
        if (!confirmed) {
            lastPlanSyncStatus = "No sync_ack from watch after send SUCCESS. Open watch DEBUG screen and check SYNC status."
            Log.i(TAG, "Garmin sync ack timeout for ${device.friendlyName}, syncId=$syncId")
        }
        return confirmed
    }

    private suspend fun sendAndWait(device: IQDevice, payload: Map<String, Any>): Boolean {
        val result = CompletableDeferred<Boolean>()
        runCatching {
            connectIQ.sendMessage(device, garminApp, payload) { _, _, status ->
                val success = status == ConnectIQ.IQMessageStatus.SUCCESS
                Log.i(TAG, "Message delivery to ${device.friendlyName}: $status payload=${payloadSummary(payload)}")
                if (!success) {
                    lastPlanSyncStatus = "Send status $status"
                }
                result.complete(success)
            }
        }.onFailure { error ->
            Log.i(TAG, "Cannot send message to Garmin", error)
            lastPlanSyncStatus = "Cannot send: ${error.message.orEmpty()}"
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
        return "type=${payload["type"]} syncId=${payload["syncId"]} lang=${payload["language"]} plan=$planCount exercises=$exerciseCount"
    }

    private fun knownDeviceStatus(devices: List<IQDevice>): String = devices.joinToString { device ->
        val status = runCatching { connectIQ.getDeviceStatus(device) }
            .getOrDefault(device.status)
        "${device.friendlyName}:$status"
    }

    private fun activeRepository() = application.repositoryFor(
        application.cloudAuthManager.authState.value.session
    )

    private fun buildGarminWorkoutNote(command: Map<Any?, Any?>): String {
        val isUk = application.languageManager.currentLanguage() == AppLanguage.UK
        val details = mutableListOf("Garmin Fenix 8")
        (command["durationSeconds"] as? Number)?.toLong()?.takeIf { it > 0L }?.let { seconds ->
            val minutes = seconds / 60
            val remainder = seconds % 60
            details += if (isUk) {
                "Тривалість ${minutes}:${remainder.toString().padStart(2, '0')}"
            } else {
                "Duration ${minutes}:${remainder.toString().padStart(2, '0')}"
            }
        }
        (command["gymCalories"] as? Number)?.toDouble()?.takeIf { it > 0.0 }?.let { calories ->
            details += if (isUk) "Gym ккал ${calories.toInt()}" else "Gym kcal ${calories.toInt()}"
        }
        (command["garminCalories"] as? Number)?.toInt()?.takeIf { it > 0 }?.let { calories ->
            details += if (isUk) "Garmin ккал $calories" else "Garmin kcal $calories"
        }
        (command["avgHeartRate"] as? Number)?.toInt()?.takeIf { it > 0 }?.let { bpm ->
            details += if (isUk) "Сер пульс $bpm" else "Avg HR $bpm"
        }
        (command["maxHeartRate"] as? Number)?.toInt()?.takeIf { it > 0 }?.let { bpm ->
            details += if (isUk) "Макс пульс $bpm" else "Max HR $bpm"
        }
        (command["heartRateZone"] as? Number)?.toInt()?.takeIf { it > 0 }?.let { zone ->
            details += if (isUk) "Зона пульсу Z$zone" else "HR zone Z$zone"
        }
        return details.joinToString(separator = " · ")
    }

    private fun cachePlan(sets: List<NamedWorkoutSetDraft>) {
        val json = JSONArray()
        sets.forEach { set ->
            json.put(JSONObject()
                .put("exerciseName", set.exerciseName)
                .put("weight", set.weight)
                .put("reps", set.reps))
        }
        preferences().edit().putString(PLAN_KEY, json.toString()).apply()
    }

    private fun cachedPlan(): List<NamedWorkoutSetDraft> = runCatching {
        val array = JSONArray(preferences().getString(PLAN_KEY, "[]"))
        buildList {
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                add(NamedWorkoutSetDraft(
                    exerciseName = item.getString("exerciseName"),
                    weight = item.getDouble("weight"),
                    reps = item.getInt("reps")
                ))
            }
        }
    }.getOrDefault(emptyList())

    private fun processedRequestIds(): Set<String> = preferences()
        .getStringSet(PROCESSED_IDS_KEY, emptySet())
        .orEmpty()

    private fun rememberProcessed(requestId: String) {
        if (requestId.isEmpty()) return
        val updated = (processedRequestIds() + requestId).toList().takeLast(40).toSet()
        preferences().edit().putStringSet(PROCESSED_IDS_KEY, updated).apply()
    }

    private fun preferences() = application.getSharedPreferences(
        PLAN_PREFERENCES,
        Context.MODE_PRIVATE
    )
}
