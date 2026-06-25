package com.example.gymapp.garmin

import android.util.Log
import android.content.Context
import com.example.gymapp.GymApplication
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
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

class GarminSyncManager(
    private val application: GymApplication
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val connectIQ = ConnectIQ.getInstance(application, ConnectIQ.IQConnectType.WIRELESS)
    private val garminApp = IQApp(GARMIN_APP_ID)
    private val registeredDevices = ConcurrentHashMap.newKeySet<Long>()
    @Volatile private var sdkReady = false

    private val listener = object : ConnectIQ.ConnectIQListener {
        override fun onSdkReady() {
            sdkReady = true
            registerConnectedDevices()
        }

        override fun onInitializeError(errStatus: ConnectIQ.IQSdkErrorStatus) {
            sdkReady = false
            Log.i(TAG, "Connect IQ unavailable: $errStatus")
        }

        override fun onSdkShutDown() {
            sdkReady = false
            registeredDevices.clear()
        }
    }

    fun initialize() {
        runCatching {
            connectIQ.initialize(application, true, listener)
        }.onFailure { error ->
            Log.i(TAG, "Connect IQ initialization skipped", error)
        }
    }

    suspend fun cacheAndPushPlan(
        sets: List<NamedWorkoutSetDraft>,
        exerciseCatalog: List<String>
    ): Boolean {
        val payload = syncPayload(exerciseCatalog, sets)
        cachePlan(sets)
        if (!ensureSdkReady()) return false
        return sendToConnectedDevices(payload)
    }

    private fun registerConnectedDevices() {
        val devices = try {
            connectIQ.knownDevices.orEmpty()
        } catch (error: Exception) {
            Log.i(TAG, "Cannot list Garmin devices", error)
            emptyList()
        }

        devices.forEach { device ->
            runCatching {
                connectIQ.registerForDeviceEvents(device) { changedDevice, status ->
                    if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                        registerAppEvents(changedDevice)
                    }
                }
                if (connectIQ.getDeviceStatus(device) == IQDevice.IQDeviceStatus.CONNECTED) {
                    registerAppEvents(device)
                }
            }.onFailure { Log.i(TAG, "Cannot register ${device.friendlyName}", it) }
        }
    }

    private suspend fun ensureSdkReady(): Boolean {
        if (!sdkReady) {
            initialize()
            withTimeoutOrNull(8_000L) {
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
                messages.forEach { message ->
                    @Suppress("UNCHECKED_CAST")
                    val command = message as? Map<Any?, Any?> ?: return@forEach
                    handleCommand(source, command)
                }
            }
        } catch (error: Exception) {
            registeredDevices.remove(device.deviceIdentifier)
            Log.i(TAG, "Cannot listen for GymApp messages", error)
        }
    }

    private fun handleCommand(device: IQDevice, command: Map<Any?, Any?>) {
        when (command["type"]?.toString()) {
            "request_sync" -> scope.launch { pushSync(device) }
            "create_workout" -> scope.launch { createWorkout(device, command) }
        }
    }

    private suspend fun pushSync(device: IQDevice) {
        val repository = activeRepository()
        val exercises = repository.getExerciseNamesForSync(limit = 200)
        sendAndWait(device, syncPayload(exercises, cachedPlan()))
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
        plan: List<NamedWorkoutSetDraft>
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

        return mapOf(
            "type" to "sync",
            "language" to application.languageManager.currentLanguage().tag,
            "exercises" to compactExercises,
            "planNames" to compactPlan.map { it.exerciseName },
            "planWeights" to compactPlan.map { it.weight },
            "planReps" to compactPlan.map { it.reps },
            "plan" to compactPlan.map { set ->
                mapOf(
                    "exerciseName" to set.exerciseName,
                    "weight" to set.weight,
                    "reps" to set.reps
                )
            }
        )
    }

    private suspend fun sendToConnectedDevices(payload: Map<String, Any>): Boolean {
        if (!sdkReady) return false
        val devices = try {
            val connected = connectIQ.connectedDevices.orEmpty()
            if (connected.isNotEmpty()) {
                connected
            } else {
                connectIQ.knownDevices.orEmpty().filter { device ->
                    runCatching {
                        connectIQ.getDeviceStatus(device) == IQDevice.IQDeviceStatus.CONNECTED
                    }.getOrDefault(false)
                }
            }
        } catch (_: InvalidStateException) {
            return false
        } catch (_: ServiceUnavailableException) {
            return false
        } catch (error: Exception) {
            Log.i(TAG, "Cannot resolve connected Garmin devices", error)
            return false
        }
        var delivered = false
        devices.forEach { device ->
            registerAppEvents(device)
            if (isGymAppInstalled(device) && sendAndWait(device, payload)) {
                delivered = true
            }
        }
        return delivered
    }

    private suspend fun isGymAppInstalled(device: IQDevice): Boolean {
        val result = CompletableDeferred<Boolean>()
        runCatching {
            connectIQ.getApplicationInfo(GARMIN_APP_ID, device, object : ConnectIQ.IQApplicationInfoListener {
                override fun onApplicationInfoReceived(app: IQApp) {
                    val installed = app.status == IQApp.IQAppStatus.INSTALLED
                    if (!installed) {
                        Log.i(TAG, "GymApp ConnectIQ status on ${device.friendlyName}: ${app.status}")
                    }
                    result.complete(installed)
                }

                override fun onApplicationNotInstalled(applicationId: String) {
                    Log.i(TAG, "GymApp ConnectIQ app not installed on ${device.friendlyName}: $applicationId")
                    result.complete(false)
                }
            })
        }.onFailure { error ->
            Log.i(TAG, "Cannot read GymApp ConnectIQ install status on ${device.friendlyName}", error)
            result.complete(false)
        }
        return withTimeoutOrNull(8_000L) { result.await() } ?: false
    }

    private suspend fun sendAndWait(device: IQDevice, payload: Map<String, Any>): Boolean {
        val result = CompletableDeferred<Boolean>()
        runCatching {
            connectIQ.sendMessage(device, garminApp, payload) { _, _, status ->
                val success = status == ConnectIQ.IQMessageStatus.SUCCESS
                if (!success) {
                    Log.i(TAG, "Message delivery status: $status")
                }
                result.complete(success)
            }
        }.onFailure { error ->
            Log.i(TAG, "Cannot send message to Garmin", error)
            result.complete(false)
        }
        return withTimeoutOrNull(8_000L) { result.await() } ?: false
    }

    private fun activeRepository() = application.repositoryFor(
        application.cloudAuthManager.authState.value.session
    )

    private fun buildGarminWorkoutNote(command: Map<Any?, Any?>): String {
        val details = mutableListOf("Garmin Fenix 8")
        (command["durationSeconds"] as? Number)?.toLong()?.takeIf { it > 0L }?.let { seconds ->
            val minutes = seconds / 60
            val remainder = seconds % 60
            details += "Duration ${minutes}:${remainder.toString().padStart(2, '0')}"
        }
        (command["gymCalories"] as? Number)?.toDouble()?.takeIf { it > 0.0 }?.let { calories ->
            details += "Gym kcal ${calories.toInt()}"
        }
        (command["garminCalories"] as? Number)?.toInt()?.takeIf { it > 0 }?.let { calories ->
            details += "Garmin kcal $calories"
        }
        (command["avgHeartRate"] as? Number)?.toInt()?.takeIf { it > 0 }?.let { bpm ->
            details += "Avg HR $bpm"
        }
        (command["maxHeartRate"] as? Number)?.toInt()?.takeIf { it > 0 }?.let { bpm ->
            details += "Max HR $bpm"
        }
        (command["heartRateZone"] as? Number)?.toInt()?.takeIf { it > 0 }?.let { zone ->
            details += "HR zone Z$zone"
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
