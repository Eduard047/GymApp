package com.example.gymapp.wearsync

import android.os.SystemClock
import com.example.gymapp.GymApplication
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.data.entity.WearSyncSetRow
import com.google.android.gms.wearable.Wearable
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal fun mayExposePhoneWearAccountData(
    session: AccountSession?,
    binding: PhoneWearAccountBinding,
    trustedSource: PhoneWearTrustedSource?,
    targetNodeId: String
): Boolean {
    val trusted = trustedSource ?: return false
    return session != null &&
        !binding.signedOut &&
        trusted.nodeId == targetNodeId &&
        trusted.ownerId == binding.ownerId
}

internal class PhoneWearSyncManager(
    private val application: GymApplication
) {
    private data class ActiveBinding(
        val session: AccountSession?,
        val binding: PhoneWearAccountBinding
    )

    private val bindingManager = PhoneWearBindingManager(application)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val initialized = AtomicBoolean(false)
    private val fullSyncMutex = Mutex()
    private val lastFullSyncCompletedAt = ConcurrentHashMap<String, Long>()

    fun initialize() {
        if (!initialized.compareAndSet(false, true)) return
        scope.launch {
            application.cloudAuthManager.authState
                .map { state ->
                    ActiveBinding(
                        session = state.session,
                        binding = bindingManager.synchronizeSession(state.session)
                    )
                }
                .distinctUntilChangedBy { it.binding }
                .collectLatest { active ->
                    // Account transitions are pushed immediately. A signed-out transition uses
                    // an opaque reserved owner and an empty payload, causing the watch to clear
                    // the previous account before accepting the new generation.
                    runCatching { pushToPinnedSource(active.session, active.binding) }
                        .onFailure { error -> if (error is CancellationException) throw error }
                }
        }
    }

    suspend fun authorizeSource(sourceNodeId: String): Boolean {
        val connected = try {
            withTimeout(NODE_LOOKUP_TIMEOUT_MS) {
                Wearable.getNodeClient(application).connectedNodes.await()
                    .map { it.id }
                    .toSet()
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            return false
        }
        val (_, binding) = currentSessionAndBinding()
        return bindingManager.authorizeSource(
            sourceNodeId = sourceNodeId,
            connectedNodeIds = connected,
            currentBinding = binding
        )
    }

    fun currentSessionAndBinding(): Pair<AccountSession?, PhoneWearAccountBinding> {
        val session = application.cloudAuthManager.authState.value.session
        return session to bindingManager.synchronizeSession(session)
    }

    fun fastSourceMayBeTrusted(sourceNodeId: String): Boolean {
        return bindingManager.fastSourceMayBeTrusted(sourceNodeId)
    }

    fun isCurrent(binding: PhoneWearAccountBinding): Boolean {
        return bindingManager.isCurrent(
            binding = binding,
            session = application.cloudAuthManager.authState.value.session
        )
    }

    fun isPinnedToCurrentOwner(sourceNodeId: String, binding: PhoneWearAccountBinding): Boolean {
        return bindingManager.isPinnedToOwner(sourceNodeId, binding.ownerId)
    }

    suspend fun sendCurrentFullSync(sourceNodeId: String, force: Boolean = false) {
        val (session, binding) = currentSessionAndBinding()
        sendFullSync(sourceNodeId, session, binding, force)
    }

    suspend fun pushCurrentStateToReconnectedPinnedSource(sourceNodeId: String) {
        if (bindingManager.pinnedSourceNodeId() != sourceNodeId) return
        sendCurrentFullSync(sourceNodeId, force = true)
    }

    suspend fun sendMutationAck(
        sourceNodeId: String,
        binding: PhoneWearAccountBinding,
        operationId: String,
        accepted: Boolean
    ) {
        if (!isCurrent(binding)) return
        val payload = PhoneWearProtocol.buildMutationAck(
            binding = binding,
            operationId = operationId,
            accepted = accepted
        )
        sendMessage(sourceNodeId, PhoneWearPaths.MUTATION_ACK, payload)
    }

    private suspend fun pushToPinnedSource(
        session: AccountSession?,
        binding: PhoneWearAccountBinding
    ) {
        val nodeId = bindingManager.pinnedSourceNodeId() ?: return
        if (!authorizeSource(nodeId)) return
        sendFullSync(nodeId, session, binding, force = true)
    }

    private suspend fun sendFullSync(
        sourceNodeId: String,
        session: AccountSession?,
        binding: PhoneWearAccountBinding,
        force: Boolean
    ) = fullSyncMutex.withLock {
        val elapsedNow = SystemClock.elapsedRealtime()
        val lastCompleted = lastFullSyncCompletedAt[sourceNodeId]
        if (!force && lastCompleted != null && elapsedNow - lastCompleted < FULL_SYNC_COOLDOWN_MS) {
            return@withLock
        }
        if (!isCurrent(binding)) return@withLock
        val mayExposeAccountData = mayExposePhoneWearAccountData(
            session = session,
            binding = binding,
            trustedSource = bindingManager.pinnedSource(),
            targetNodeId = sourceNodeId
        )
        val (sessions, catalog) = if (!mayExposeAccountData) {
            emptyList<PhoneWearOutboundSession>() to emptyList()
        } else {
            val snapshot = application.repositoryFor(session).getPhoneWearSyncSnapshot(
                maxSetRows = PhoneWearPaths.MAX_SYNC_TOTAL_SETS,
                maxExerciseNames = PhoneWearPaths.MAX_EXERCISE_CATALOG
            )
            rowsToSessions(snapshot.setRows) to snapshot.exerciseNames
        }
        if (!isCurrent(binding)) return@withLock
        val revision = bindingManager.nextFullSyncRevision(binding)
        val payload = PhoneWearProtocol.buildBoundedFullSync(
            binding = binding,
            revision = revision,
            sessions = sessions,
            exerciseCatalog = catalog
        )
        if (!isCurrent(binding)) return@withLock
        sendMessage(sourceNodeId, PhoneWearPaths.FULL_SYNC_PAYLOAD, payload)
        lastFullSyncCompletedAt[sourceNodeId] = SystemClock.elapsedRealtime()
    }

    private suspend fun sendMessage(sourceNodeId: String, path: String, payload: ByteArray) {
        require(payload.size <= PhoneWearPaths.MAX_MESSAGE_BYTES)
        withTimeout(MESSAGE_SEND_TIMEOUT_MS) {
            Wearable.getMessageClient(application)
                .sendMessage(sourceNodeId, path, payload)
                .await()
        }
    }

    private fun rowsToSessions(rows: List<WearSyncSetRow>): List<PhoneWearOutboundSession> {
        return rows.groupByTo(linkedMapOf(), WearSyncSetRow::sessionId)
            .values
            .map { sessionRows ->
                val first = sessionRows.first()
                PhoneWearOutboundSession(
                    id = first.sessionId,
                    startedAt = first.sessionDate,
                    note = first.sessionNote,
                    sets = sessionRows.mapIndexed { index, row ->
                        PhoneWearOutboundSet(
                            id = row.setId,
                            sessionId = row.sessionId,
                            exerciseName = row.exerciseName,
                            weight = row.weight,
                            reps = row.reps,
                            orderIndex = index
                        )
                    }
                )
            }
    }

    private companion object {
        const val NODE_LOOKUP_TIMEOUT_MS = 5_000L
        const val MESSAGE_SEND_TIMEOUT_MS = 10_000L
        const val FULL_SYNC_COOLDOWN_MS = 5_000L
    }
}
