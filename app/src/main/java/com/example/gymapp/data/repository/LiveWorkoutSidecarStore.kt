package com.example.gymapp.data.repository

import android.content.Context
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.isValidLiveRoomId
import com.example.gymapp.auth.isValidSocialClientRequestId
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.time.Duration
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal const val LIVE_SIDECAR_PREFERENCES = "gym_live_workout_sidecar"
internal const val LIVE_MAX_PENDING_OPERATIONS = 256
private const val LIVE_SIDECAR_LEGACY_KEY = "binding"
private const val LIVE_SIDECAR_MAX_BYTES = 96 * 1_024
private const val LIVE_RESERVATION_KEY_PREFIX = "reservation:"
private const val LIVE_RESERVATION_MAX_BYTES = 2 * 1_024
internal val LIVE_RESERVATION_MAX_DURATION_MILLIS: Long = Duration.ofDays(9).toMillis()

internal enum class LiveWorkoutReservationPhase(val storageValue: String) {
    Preparing("preparing"),
    Waiting("waiting"),
    Active("active")
}

internal data class LiveWorkoutReservation(
    val userId: String,
    val sessionGeneration: String,
    val role: String,
    val operationId: String,
    val roomId: String?,
    val phase: LiveWorkoutReservationPhase,
    val createdAt: Long,
    val expiresAt: Long
)

internal object LiveWorkoutReservationCodec {
    fun encode(reservation: LiveWorkoutReservation): String {
        validate(reservation)
        return JSONObject()
            .put("version", 1)
            .put("userId", reservation.userId)
            .put("sessionGeneration", reservation.sessionGeneration)
            .put("role", reservation.role)
            .put("operationId", reservation.operationId)
            .put("roomId", reservation.roomId ?: JSONObject.NULL)
            .put("phase", reservation.phase.storageValue)
            .put("createdAt", reservation.createdAt)
            .put("expiresAt", reservation.expiresAt)
            .toString()
            .also {
                require(it.toByteArray(Charsets.UTF_8).size <= LIVE_RESERVATION_MAX_BYTES) {
                    "Live workout reservation is too large."
                }
            }
    }

    fun decode(raw: String): LiveWorkoutReservation {
        require(raw.toByteArray(Charsets.UTF_8).size <= LIVE_RESERVATION_MAX_BYTES) {
            "Live workout reservation is too large."
        }
        val tokener = JSONTokener(raw)
        val root = tokener.nextValue() as? JSONObject
            ?: throw IllegalArgumentException("Live workout reservation is invalid.")
        require(tokener.nextClean() == 0.toChar() &&
            root.keys().asSequence().toSet() == setOf(
                "version", "userId", "sessionGeneration", "role", "operationId",
                "roomId", "phase", "createdAt", "expiresAt"
            ) && root.strictInt("version", 1, 1) == 1
        ) { "Live workout reservation is invalid." }
        return LiveWorkoutReservation(
            userId = root.strictString("userId", 36),
            sessionGeneration = root.strictString("sessionGeneration", 36),
            role = root.strictString("role", 16),
            operationId = root.strictString("operationId", 36),
            roomId = root.strictNullableString("roomId", 35),
            phase = LiveWorkoutReservationPhase.entries.singleOrNull {
                it.storageValue == root.opt("phase")
            } ?: throw IllegalArgumentException("Live workout reservation is invalid."),
            createdAt = root.strictLong(
                "createdAt",
                WorkoutDataLimits.MIN_TIMESTAMP_MILLIS,
                WorkoutDataLimits.MAX_TIMESTAMP_MILLIS
            ),
            expiresAt = root.strictLong(
                "expiresAt",
                WorkoutDataLimits.MIN_TIMESTAMP_MILLIS,
                WorkoutDataLimits.MAX_TIMESTAMP_MILLIS
            )
        ).also(::validate)
    }

    fun validate(reservation: LiveWorkoutReservation) {
        require(runCatching {
            UUID.fromString(reservation.userId).toString() == reservation.userId
        }.getOrDefault(false) && runCatching {
            UUID.fromString(reservation.sessionGeneration).toString() ==
                reservation.sessionGeneration
        }.getOrDefault(false) && isValidSocialClientRequestId(reservation.operationId)) {
            "Live workout reservation identity is invalid."
        }
        require(reservation.role in setOf("owner", "participant") &&
            WorkoutDataLimits.isValidTimestamp(reservation.createdAt) &&
            WorkoutDataLimits.isValidTimestamp(reservation.expiresAt) &&
            reservation.expiresAt > reservation.createdAt &&
            reservation.expiresAt - reservation.createdAt <= LIVE_RESERVATION_MAX_DURATION_MILLIS
        ) { "Live workout reservation lifetime is invalid." }
        require(
            if (reservation.phase == LiveWorkoutReservationPhase.Preparing) {
                reservation.role == "owner" && reservation.roomId == null
            } else {
                reservation.roomId != null && isValidLiveRoomId(reservation.roomId)
            }
        ) { "Live workout reservation room is invalid." }
    }
}

internal enum class LivePendingOperationKind(val wireValue: String) {
    CompleteSet("complete_set"),
    UndoSet("undo_set"),
    Finish("finish")
}

internal enum class LivePreparedMutationKind(val storageValue: String) {
    CompleteSet("complete_set"),
    CompleteBatch("complete_batch"),
    UndoSet("undo_set"),
    Finish("finish")
}

internal data class LivePendingOperation(
    val clientOperationId: String,
    val kind: LivePendingOperationKind,
    val expectedProgressRevision: Int,
    val serverSetId: String?,
    val weight: Double?,
    val reps: Int?
)

internal data class LivePreparedMutation(
    val localMutationId: String,
    val kind: LivePreparedMutationKind,
    val expectedLocalRevision: Long,
    val operations: List<LivePendingOperation>
)

internal data class LiveWorkoutBinding(
    val userId: String,
    val sessionGeneration: String,
    val roomId: String,
    val role: String,
    val peerProfileId: String,
    val peerDisplayName: String,
    val roomRevision: Int,
    val membershipRevision: Int,
    val progressRevision: Int,
    val workoutStartedAt: Long,
    val serverToLocalSetIds: Map<String, String>,
    val localFinished: Boolean = false,
    val pendingOperations: List<LivePendingOperation> = emptyList(),
    val preparedMutation: LivePreparedMutation? = null
) {
    val localToServerSetIds: Map<String, String>
        get() = serverToLocalSetIds.entries.associate { (server, local) -> local to server }
}

internal object LiveWorkoutSidecarCodec {
    fun encode(binding: LiveWorkoutBinding): String {
        validate(binding)
        val mapping = JSONObject()
        binding.serverToLocalSetIds.toSortedMap().forEach { (serverId, localId) ->
            mapping.put(serverId, localId)
        }
        val operations = JSONArray()
        binding.pendingOperations.forEach { operation ->
            operations.put(operationJson(operation))
        }
        val preparedMutation = binding.preparedMutation?.let { prepared ->
            JSONObject()
                .put("localMutationId", prepared.localMutationId)
                .put("kind", prepared.kind.storageValue)
                .put("expectedLocalRevision", prepared.expectedLocalRevision)
                .put(
                    "operations",
                    JSONArray().also { preparedOperations ->
                        prepared.operations.forEach { operation ->
                            preparedOperations.put(operationJson(operation))
                        }
                    }
                )
        }
        return JSONObject()
            .put("version", 2)
            .put("userId", binding.userId)
            .put("sessionGeneration", binding.sessionGeneration)
            .put("roomId", binding.roomId)
            .put("role", binding.role)
            .put("peerProfileId", binding.peerProfileId)
            .put("peerDisplayName", binding.peerDisplayName)
            .put("roomRevision", binding.roomRevision)
            .put("membershipRevision", binding.membershipRevision)
            .put("progressRevision", binding.progressRevision)
            .put("workoutStartedAt", binding.workoutStartedAt)
            .put("serverToLocalSetIds", mapping)
            .put("localFinished", binding.localFinished)
            .put("pendingOperations", operations)
            .put("preparedMutation", preparedMutation ?: JSONObject.NULL)
            .toString()
            .also { require(it.toByteArray(Charsets.UTF_8).size <= LIVE_SIDECAR_MAX_BYTES) {
                "Live workout sidecar is too large."
            } }
    }

    fun decode(raw: String): LiveWorkoutBinding {
        require(raw.toByteArray(Charsets.UTF_8).size <= LIVE_SIDECAR_MAX_BYTES) {
            "Live workout sidecar is too large."
        }
        val tokener = JSONTokener(raw)
        val root = tokener.nextValue() as? JSONObject
            ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
        require(tokener.nextClean() == 0.toChar()) { "Live workout sidecar is invalid." }
        val version = root.strictInt("version", 1, 2)
        val expectedKeys = setOf(
            "version", "userId", "sessionGeneration", "roomId", "role", "peerProfileId",
            "peerDisplayName", "roomRevision", "membershipRevision", "progressRevision",
            "workoutStartedAt", "serverToLocalSetIds", "localFinished", "pendingOperations"
        ) + if (version == 2) setOf("preparedMutation") else emptySet()
        require(root.keys().asSequence().toSet() == expectedKeys) {
            "Live workout sidecar is invalid."
        }
        val mappingObject = root.optJSONObject("serverToLocalSetIds")
            ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
        require(mappingObject.length() in 1..SharedWorkoutLink.MAX_TOTAL_SETS) {
            "Live workout sidecar is invalid."
        }
        val mapping = mappingObject.keys().asSequence().associateWith { serverId ->
            mappingObject.opt(serverId) as? String
                ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
        }
        val operationArray = root.optJSONArray("pendingOperations")
            ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
        require(operationArray.length() <= LIVE_MAX_PENDING_OPERATIONS) {
            "Live workout sidecar is invalid."
        }
        val operations = parseOperations(operationArray)
        val preparedMutation = if (version == 2 && !root.isNull("preparedMutation")) {
            val prepared = root.optJSONObject("preparedMutation")
                ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
            require(prepared.keys().asSequence().toSet() == setOf(
                "localMutationId", "kind", "expectedLocalRevision", "operations"
            )) { "Live workout sidecar is invalid." }
            val preparedOperations = prepared.optJSONArray("operations")
                ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
            require(preparedOperations.length() in 1..SharedWorkoutLink.MAX_TOTAL_SETS) {
                "Live workout sidecar is invalid."
            }
            LivePreparedMutation(
                localMutationId = prepared.strictString("localMutationId", 36),
                kind = LivePreparedMutationKind.entries.singleOrNull {
                    it.storageValue == prepared.opt("kind")
                } ?: throw IllegalArgumentException("Live workout sidecar is invalid."),
                expectedLocalRevision = prepared.strictLong(
                    "expectedLocalRevision",
                    0L,
                    Long.MAX_VALUE - 1L
                ),
                operations = parseOperations(preparedOperations)
            )
        } else {
            null
        }
        return LiveWorkoutBinding(
            userId = root.strictString("userId", 36),
            sessionGeneration = root.strictString("sessionGeneration", 36),
            roomId = root.strictString("roomId", 35),
            role = root.strictString("role", 16),
            peerProfileId = root.strictString("peerProfileId", 34),
            peerDisplayName = root.strictString("peerDisplayName", 40),
            roomRevision = root.strictInt("roomRevision", 1, Int.MAX_VALUE),
            membershipRevision = root.strictInt("membershipRevision", 1, Int.MAX_VALUE),
            progressRevision = root.strictInt("progressRevision", 1, Int.MAX_VALUE),
            workoutStartedAt = root.strictLong(
                "workoutStartedAt",
                WorkoutDataLimits.MIN_TIMESTAMP_MILLIS,
                WorkoutDataLimits.MAX_TIMESTAMP_MILLIS
            ),
            serverToLocalSetIds = mapping,
            localFinished = root.strictBoolean("localFinished"),
            pendingOperations = operations,
            preparedMutation = preparedMutation
        ).also(::validate)
    }

    fun validate(binding: LiveWorkoutBinding) {
        require(runCatching { UUID.fromString(binding.userId).toString() == binding.userId }.getOrDefault(false)) {
            "Live workout account is invalid."
        }
        require(runCatching {
            UUID.fromString(binding.sessionGeneration).toString() == binding.sessionGeneration
        }.getOrDefault(false)) { "Live workout session is invalid." }
        require(isValidLiveRoomId(binding.roomId)) { "Live workout room is invalid." }
        require(binding.role in setOf("owner", "participant")) { "Live workout role is invalid." }
        require(binding.peerProfileId.matches(Regex("^p_[0-9a-f]{32}$"))) {
            "Live workout peer is invalid."
        }
        require(binding.peerDisplayName.isNotBlank() &&
            binding.peerDisplayName == binding.peerDisplayName.trim(' ') &&
            binding.peerDisplayName.codePointCount(0, binding.peerDisplayName.length) <= 40 &&
            binding.peerDisplayName.toByteArray(Charsets.UTF_8).size <= 160 &&
            binding.peerDisplayName.none {
                it.isISOControl() || Character.getType(it) == Character.FORMAT.toInt()
            }) { "Live workout peer is invalid." }
        require(binding.roomRevision > 0 && binding.membershipRevision > 0 &&
            binding.progressRevision > 0 && WorkoutDataLimits.isValidTimestamp(binding.workoutStartedAt)) {
            "Live workout revision is invalid."
        }
        require(binding.serverToLocalSetIds.size in 1..SharedWorkoutLink.MAX_TOTAL_SETS &&
            binding.serverToLocalSetIds.keys.all { it.matches(Regex("^s_[0-9]{2}_[0-9]{2}$")) } &&
            binding.serverToLocalSetIds.values.toSet().size == binding.serverToLocalSetIds.size &&
            binding.serverToLocalSetIds.values.all(::isCanonicalLocalSetId)) {
            "Live workout set mapping is invalid."
        }
        val preparedOperations = binding.preparedMutation?.operations.orEmpty()
        val allOperations = binding.pendingOperations + preparedOperations
        require(allOperations.size <= LIVE_MAX_PENDING_OPERATIONS &&
            allOperations.map { it.clientOperationId }.toSet().size == allOperations.size &&
            allOperations.size.toLong() <=
            Int.MAX_VALUE.toLong() - binding.progressRevision.toLong()) {
            "Live workout queue is invalid."
        }
        val finishIndexes = binding.pendingOperations.mapIndexedNotNull { index, operation ->
            index.takeIf { operation.kind == LivePendingOperationKind.Finish }
        }
        require(finishIndexes.size <= 1 &&
            (finishIndexes.isEmpty() || finishIndexes.single() == binding.pendingOperations.lastIndex) &&
            (finishIndexes.isEmpty() || binding.localFinished) &&
            (binding.preparedMutation == null || finishIndexes.isEmpty())) {
            "Live workout queue is invalid."
        }
        validateOperations(
            binding = binding,
            operations = binding.pendingOperations,
            firstExpectedRevision = binding.progressRevision
        )
        binding.preparedMutation?.let { prepared ->
            require(!binding.localFinished &&
                isValidSocialClientRequestId(prepared.localMutationId) &&
                prepared.expectedLocalRevision in 0 until Long.MAX_VALUE) {
                "Live workout queue is invalid."
            }
            when (prepared.kind) {
                LivePreparedMutationKind.CompleteSet -> require(
                    prepared.operations.size == 1 &&
                        prepared.operations.single().kind == LivePendingOperationKind.CompleteSet
                ) { "Live workout queue is invalid." }
                LivePreparedMutationKind.CompleteBatch -> require(
                    prepared.operations.isNotEmpty() &&
                        prepared.operations.all {
                            it.kind == LivePendingOperationKind.CompleteSet
                        }
                ) { "Live workout queue is invalid." }
                LivePreparedMutationKind.UndoSet -> require(
                    prepared.operations.size == 1 &&
                        prepared.operations.single().kind == LivePendingOperationKind.UndoSet
                ) { "Live workout queue is invalid." }
                LivePreparedMutationKind.Finish -> require(
                    prepared.operations.size == 1 &&
                        prepared.operations.single().kind == LivePendingOperationKind.Finish
                ) { "Live workout queue is invalid." }
            }
            validateOperations(
                binding = binding,
                operations = prepared.operations,
                firstExpectedRevision = binding.progressRevision +
                    binding.pendingOperations.size
            )
        }
    }

    private fun validateOperations(
        binding: LiveWorkoutBinding,
        operations: List<LivePendingOperation>,
        firstExpectedRevision: Int
    ) {
        operations.forEachIndexed { index, operation ->
            require(isValidSocialClientRequestId(operation.clientOperationId) &&
                operation.expectedProgressRevision.toLong() ==
                firstExpectedRevision.toLong() + index.toLong()) {
                "Live workout queue is invalid."
            }
            when (operation.kind) {
                LivePendingOperationKind.CompleteSet -> require(
                    operation.serverSetId in binding.serverToLocalSetIds &&
                        operation.weight != null && operation.weight.isFinite() &&
                        operation.weight in 0.0..SharedWorkoutLink.MAX_WEIGHT &&
                        operation.reps != null && operation.reps in 1..SharedWorkoutLink.MAX_REPS
                ) { "Live workout queue is invalid." }
                LivePendingOperationKind.UndoSet -> require(
                    operation.serverSetId in binding.serverToLocalSetIds &&
                        operation.weight == null && operation.reps == null
                ) { "Live workout queue is invalid." }
                LivePendingOperationKind.Finish -> require(
                    operation.serverSetId == null && operation.weight == null && operation.reps == null
                ) { "Live workout queue is invalid." }
            }
        }
    }

    private fun operationJson(operation: LivePendingOperation): JSONObject = JSONObject()
        .put("clientOperationId", operation.clientOperationId)
        .put("kind", operation.kind.wireValue)
        .put("expectedProgressRevision", operation.expectedProgressRevision)
        .put("serverSetId", operation.serverSetId ?: JSONObject.NULL)
        .put("weight", operation.weight ?: JSONObject.NULL)
        .put("reps", operation.reps ?: JSONObject.NULL)

    private fun parseOperations(operations: JSONArray): List<LivePendingOperation> =
        List(operations.length()) { index ->
            val operation = operations.optJSONObject(index)
                ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
            require(operation.keys().asSequence().toSet() == setOf(
                "clientOperationId", "kind", "expectedProgressRevision", "serverSetId",
                "weight", "reps"
            )) { "Live workout sidecar is invalid." }
            val kind = LivePendingOperationKind.entries.singleOrNull {
                it.wireValue == operation.opt("kind")
            } ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
            LivePendingOperation(
                clientOperationId = operation.strictString("clientOperationId", 36),
                kind = kind,
                expectedProgressRevision = operation.strictInt(
                    "expectedProgressRevision",
                    1,
                    Int.MAX_VALUE
                ),
                serverSetId = operation.strictNullableString("serverSetId", 9),
                weight = operation.strictNullableDouble(
                    "weight",
                    0.0,
                    SharedWorkoutLink.MAX_WEIGHT
                ),
                reps = operation.strictNullableInt("reps", 1, SharedWorkoutLink.MAX_REPS)
            )
        }

    private fun isCanonicalLocalSetId(value: String): Boolean = runCatching {
        value.length == 36 && UUID.fromString(value).toString() == value
    }.getOrDefault(false)
}

internal class LiveWorkoutSidecarStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        LIVE_SIDECAR_PREFERENCES,
        Context.MODE_PRIVATE
    )
    private val durableCache = mutableMapOf<String, LiveWorkoutBinding?>()

    suspend fun reserve(
        session: AccountSession.Cloud,
        reservation: LiveWorkoutReservation,
        nowMillis: Long = System.currentTimeMillis(),
        canReserve: suspend () -> Boolean = { true }
    ): Boolean = reservationMutex(session.userId).withLock {
        if (reservation.userId != session.userId ||
            reservation.sessionGeneration != session.sessionGeneration ||
            reservation.expiresAt <= nowMillis
        ) return@withLock false
        val current = readReservationUnlocked(session, nowMillis)
        val currentValue = current.value
        if (current.unreadable ||
            currentValue != null && currentValue.operationId != reservation.operationId
        ) return@withLock false
        if (!canReserve()) return@withLock false
        if (current.value == reservation) return@withLock true
        persistReservationUnlocked(session, reservation)
    }

    suspend fun reservation(
        session: AccountSession.Cloud,
        nowMillis: Long = System.currentTimeMillis()
    ): LiveWorkoutReservation? = reservationMutex(session.userId).withLock {
        val current = readReservationUnlocked(session, nowMillis)
        check(!current.unreadable) { "Live workout reservation could not be read safely." }
        current.value
    }

    suspend fun replaceReservation(
        session: AccountSession.Cloud,
        expectedOperationId: String,
        replacement: LiveWorkoutReservation,
        nowMillis: Long = System.currentTimeMillis()
    ): Boolean = reservationMutex(session.userId).withLock {
        val current = readReservationUnlocked(session, nowMillis)
        if (current.unreadable || current.value?.operationId != expectedOperationId ||
            replacement.userId != session.userId ||
            replacement.sessionGeneration != session.sessionGeneration ||
            replacement.operationId != expectedOperationId || replacement.expiresAt <= nowMillis
        ) return@withLock false
        persistReservationUnlocked(session, replacement)
    }

    suspend fun clearReservation(
        session: AccountSession.Cloud,
        expectedOperationId: String,
        expectedRoomId: String? = null
    ): Boolean = reservationMutex(session.userId).withLock {
        val key = reservationKey(session)
        val raw = preferences.getString(key, null) ?: return@withLock true
        val current = runCatching { LiveWorkoutReservationCodec.decode(raw) }.getOrNull()
            ?: return@withLock false
        if (current.userId != session.userId ||
            current.sessionGeneration != session.sessionGeneration ||
            current.operationId != expectedOperationId ||
            expectedRoomId != null && current.roomId != expectedRoomId
        ) return@withLock false
        preferences.edit().remove(key).commit() && !preferences.contains(key)
    }

    suspend fun sessionMismatchedReservation(
        session: AccountSession.Cloud
    ): LiveWorkoutReservation? = reservationMutex(session.userId).withLock {
        val currentKey = reservationKey(session)
        val candidates = preferences.all.filterKeys {
            it.startsWith("$LIVE_RESERVATION_KEY_PREFIX${session.userId}:") && it != currentKey
        }
        check(candidates.size <= 1) { "Multiple stale live workout reservations exist." }
        if (candidates.isEmpty()) return@withLock null
        val raw = candidates.values.single() as? String
            ?: error("Live workout reservation could not be read safely.")
        LiveWorkoutReservationCodec.decode(raw).also {
            check(it.userId == session.userId && it.sessionGeneration != session.sessionGeneration) {
                "Live workout reservation belongs to an unexpected session."
            }
        }
    }

    suspend fun reconcileSessionMismatchedReservation(
        session: AccountSession.Cloud,
        expectedSessionGeneration: String,
        expectedOperationId: String,
        replacement: LiveWorkoutReservation?
    ): Boolean = reservationMutex(session.userId).withLock {
        val oldKey = "$LIVE_RESERVATION_KEY_PREFIX${session.userId}:$expectedSessionGeneration"
        val currentKey = reservationKey(session)
        if (preferences.contains(currentKey)) return@withLock false
        val raw = preferences.getString(oldKey, null) ?: return@withLock false
        val current = runCatching { LiveWorkoutReservationCodec.decode(raw) }.getOrNull()
            ?: return@withLock false
        if (current.userId != session.userId ||
            current.sessionGeneration != expectedSessionGeneration ||
            current.operationId != expectedOperationId ||
            expectedSessionGeneration == session.sessionGeneration
        ) return@withLock false
        val editor = preferences.edit().remove(oldKey)
        if (replacement != null) {
            if (replacement.userId != session.userId ||
                replacement.sessionGeneration != session.sessionGeneration ||
                replacement.operationId != expectedOperationId
            ) return@withLock false
            val encoded = runCatching { LiveWorkoutReservationCodec.encode(replacement) }.getOrNull()
                ?: return@withLock false
            editor.putString(currentKey, encoded)
            if (!editor.commit()) return@withLock false
            preferences.getString(currentKey, null) == encoded && !preferences.contains(oldKey)
        } else {
            editor.commit() && !preferences.contains(oldKey) && !preferences.contains(currentKey)
        }
    }

    suspend fun <T> withOrdinaryStartPermit(
        userId: String,
        blockedValue: T,
        nowMillis: Long = System.currentTimeMillis(),
        block: suspend () -> T
    ): T = reservationMutex(userId).withLock {
        if (hasBlockingReservationUnlocked(userId, nowMillis)) blockedValue else block()
    }

    suspend fun <T> withLiveStartReservation(
        session: AccountSession.Cloud,
        roomId: String,
        blockedValue: T,
        nowMillis: Long = System.currentTimeMillis(),
        block: suspend (LiveWorkoutReservation) -> T
    ): T = reservationMutex(session.userId).withLock {
        val current = readReservationUnlocked(session, nowMillis)
        val reservation = current.value
        if (current.unreadable || reservation == null || reservation.roomId != roomId ||
            reservation.phase == LiveWorkoutReservationPhase.Preparing
        ) blockedValue else block(reservation)
    }

    @Synchronized
    fun load(session: AccountSession.Cloud): LiveWorkoutBinding? {
        val key = bindingKey(session)
        if (durableCache.containsKey(key)) return durableCache[key]
        val raw = preferences.getString(key, null)
        if (raw == null) {
            durableCache[key] = null
            return null
        }
        val binding = runCatching { LiveWorkoutSidecarCodec.decode(raw) }.getOrNull()
        if (binding == null || binding.userId != session.userId ||
            binding.sessionGeneration != session.sessionGeneration
        ) {
            preferences.edit().remove(key).commit()
            durableCache[key] = null
            return null
        }
        durableCache[key] = binding
        return binding
    }

    @Synchronized
    fun save(session: AccountSession.Cloud, binding: LiveWorkoutBinding): Boolean {
        require(binding.userId == session.userId &&
            binding.sessionGeneration == session.sessionGeneration) {
            "Live workout sidecar belongs to a different account."
        }
        val encoded = runCatching { LiveWorkoutSidecarCodec.encode(binding) }.getOrNull()
            ?: return false
        return runCatching {
            preferences.edit()
                .remove(LIVE_SIDECAR_LEGACY_KEY)
                .putString(bindingKey(session), encoded)
                .commit()
        }.getOrDefault(false).also { saved ->
            if (saved) durableCache[bindingKey(session)] = binding
        }
    }

    @Synchronized
    fun update(
        session: AccountSession.Cloud,
        transform: (LiveWorkoutBinding) -> LiveWorkoutBinding
    ): LiveWorkoutBinding? {
        val current = load(session) ?: return null
        val updated = transform(current)
        return updated.takeIf { save(session, it) }
    }

    @Synchronized
    fun clear(session: AccountSession.Cloud): Boolean {
        val key = bindingKey(session)
        if (!preferences.contains(key)) return false
        val cleared = preferences.edit().remove(key).commit()
        // Detach/logout is fail-closed even if durable cleanup needs another attempt after restart.
        durableCache[key] = null
        return cleared
    }

    @Synchronized
    fun clearAll(): Boolean {
        val snapshot = preferences.all.mapValues { (_, value) -> value as? String ?: return false }
        val cleared = preferences.edit().clear().commit()
        if (!cleared) {
            val restore = preferences.edit().clear()
            snapshot.forEach(restore::putString)
            restore.commit()
            return false
        }
        durableCache.clear()
        return true
    }

    private fun bindingKey(session: AccountSession.Cloud): String =
        "binding:${session.userId}:${session.sessionGeneration}"

    private data class ReservationRead(
        val value: LiveWorkoutReservation? = null,
        val unreadable: Boolean = false
    )

    private fun readReservationUnlocked(
        session: AccountSession.Cloud,
        nowMillis: Long
    ): ReservationRead {
        val key = reservationKey(session)
        val raw = preferences.getString(key, null) ?: return ReservationRead()
        val reservation = runCatching { LiveWorkoutReservationCodec.decode(raw) }.getOrNull()
            ?: return ReservationRead(unreadable = true)
        if (reservation.userId != session.userId ||
            reservation.sessionGeneration != session.sessionGeneration
        ) return ReservationRead(unreadable = true)
        if (reservation.expiresAt <= nowMillis) {
            val cleared = preferences.edit().remove(key).commit() && !preferences.contains(key)
            return if (cleared) ReservationRead() else ReservationRead(unreadable = true)
        }
        return ReservationRead(reservation)
    }

    private fun hasBlockingReservationUnlocked(userId: String, nowMillis: Long): Boolean {
        val prefix = "$LIVE_RESERVATION_KEY_PREFIX$userId:"
        val candidates = preferences.all.filterKeys { it.startsWith(prefix) }
        for ((key, rawValue) in candidates) {
            val raw = rawValue as? String ?: return true
            val reservation = runCatching { LiveWorkoutReservationCodec.decode(raw) }.getOrNull()
                ?: return true
            if (reservation.userId != userId) return true
            if (reservation.expiresAt > nowMillis) return true
            if (!preferences.edit().remove(key).commit() || preferences.contains(key)) return true
        }
        return false
    }

    private fun persistReservationUnlocked(
        session: AccountSession.Cloud,
        reservation: LiveWorkoutReservation
    ): Boolean {
        val encoded = runCatching { LiveWorkoutReservationCodec.encode(reservation) }.getOrNull()
            ?: return false
        val key = reservationKey(session)
        return preferences.edit().putString(key, encoded).commit() &&
            preferences.getString(key, null) == encoded
    }

    private fun reservationKey(session: AccountSession.Cloud): String =
        "$LIVE_RESERVATION_KEY_PREFIX${session.userId}:${session.sessionGeneration}"

    private companion object {
        val reservationMutexes = ConcurrentHashMap<String, Mutex>()

        fun reservationMutex(userId: String): Mutex =
            reservationMutexes.computeIfAbsent(userId) { Mutex() }
    }
}

private fun JSONObject.strictString(key: String, maxCodePoints: Int): String {
    val value = opt(key) as? String ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
    require(value.isNotEmpty() && value.codePointCount(0, value.length) <= maxCodePoints &&
        value.none {
            it.isISOControl() || Character.getType(it) == Character.FORMAT.toInt()
        }) { "Live workout sidecar is invalid." }
    return value
}

private fun JSONObject.strictNullableString(key: String, maxCodePoints: Int): String? {
    require(has(key)) { "Live workout sidecar is invalid." }
    return if (isNull(key)) null else strictString(key, maxCodePoints)
}

private fun JSONObject.strictBoolean(key: String): Boolean = opt(key) as? Boolean
    ?: throw IllegalArgumentException("Live workout sidecar is invalid.")

private fun JSONObject.strictInt(key: String, minimum: Int, maximum: Int): Int {
    val raw = opt(key) as? Number ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
    val value = raw.toDouble()
    require(value.isFinite() && value % 1.0 == 0.0 && value in minimum.toDouble()..maximum.toDouble()) {
        "Live workout sidecar is invalid."
    }
    return value.toInt()
}

private fun JSONObject.strictNullableInt(key: String, minimum: Int, maximum: Int): Int? {
    require(has(key)) { "Live workout sidecar is invalid." }
    return if (isNull(key)) null else strictInt(key, minimum, maximum)
}

private fun JSONObject.strictLong(key: String, minimum: Long, maximum: Long): Long {
    val raw = opt(key) as? Number ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
    val value = raw.toDouble()
    require(value.isFinite() && value % 1.0 == 0.0 && value in minimum.toDouble()..maximum.toDouble()) {
        "Live workout sidecar is invalid."
    }
    return value.toLong()
}

private fun JSONObject.strictNullableDouble(key: String, minimum: Double, maximum: Double): Double? {
    require(has(key)) { "Live workout sidecar is invalid." }
    if (isNull(key)) return null
    val raw = opt(key) as? Number ?: throw IllegalArgumentException("Live workout sidecar is invalid.")
    val value = raw.toDouble()
    require(value.isFinite() && value in minimum..maximum) { "Live workout sidecar is invalid." }
    return value
}
