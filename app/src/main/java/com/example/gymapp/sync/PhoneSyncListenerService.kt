package com.example.gymapp.sync

import com.example.gymapp.gymApplication
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

class PhoneSyncListenerService : WearableListenerService() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)
        val rawPayload = messageEvent.data.toString(Charsets.UTF_8)

        when (messageEvent.path) {
            SyncPaths.REQUEST_FULL_SYNC -> {
                serviceScope.launch {
                    pushFullSyncToNode(messageEvent.sourceNodeId)
                }
            }

            SyncPaths.CREATE_WORKOUT -> {
                val command = PhoneSyncJson.parseCreateWorkoutCommand(rawPayload) ?: return
                serviceScope.launch {
                    repository.createWorkoutSessionFromNamedSets(
                        date = command.startedAt,
                        note = command.note,
                        sets = command.sets
                    )
                    pushFullSyncToAllNodes()
                }
            }

            SyncPaths.UPDATE_SET -> {
                val command = PhoneSyncJson.parseUpdateSetCommand(rawPayload) ?: return
                serviceScope.launch {
                    repository.updateSetById(
                        setId = command.setId,
                        weight = command.weight,
                        reps = command.reps
                    )
                    pushFullSyncToAllNodes()
                }
            }

            SyncPaths.DELETE_SET -> {
                val command = PhoneSyncJson.parseDeleteSetCommand(rawPayload) ?: return
                serviceScope.launch {
                    repository.deleteSetById(command.setId)
                    pushFullSyncToAllNodes()
                }
            }
        }
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }

    private val repository
        get() = applicationContext.gymApplication.repositoryFor(
            applicationContext.gymApplication.cloudAuthManager.authState.value.session
        )

    private suspend fun pushFullSyncToNode(nodeId: String) {
        val payload = buildFullSyncPayload()
        Wearable.getMessageClient(this)
            .sendMessage(
                nodeId,
                SyncPaths.FULL_SYNC_PAYLOAD,
                payload.toByteArray(Charsets.UTF_8)
            )
            .await()
    }

    private suspend fun pushFullSyncToAllNodes() {
        val payload = buildFullSyncPayload().toByteArray(Charsets.UTF_8)
        val nodes = Wearable.getNodeClient(this).connectedNodes.await()
        nodes.forEach { node ->
            runCatching {
                Wearable.getMessageClient(this)
                    .sendMessage(node.id, SyncPaths.FULL_SYNC_PAYLOAD, payload)
                    .await()
            }
        }
    }

    private suspend fun buildFullSyncPayload(): String {
        val details = repository.getSessionDetailsForSync(limit = 160)
        val exerciseCatalog = repository.getExerciseNamesForSync(limit = 400)
        return PhoneSyncJson.encodeFullSyncPayload(
            detailsList = details,
            exerciseCatalog = exerciseCatalog
        )
    }
}
