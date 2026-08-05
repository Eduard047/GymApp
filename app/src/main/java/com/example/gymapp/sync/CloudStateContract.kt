package com.example.gymapp.sync

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.repository.BackupImportValidator
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.canonicalV229CloudWorkoutDigest
import com.example.gymapp.data.repository.validateBackupOwnerContext
import org.json.JSONObject

/**
 * The shared cloud row keeps one strict workout core that every supported client can round-trip.
 * Newer extension bags and machine load profiles remain readable, but Android deliberately omits
 * them from writes while released v2.2.9 clients must remain able to read and update the row.
 */
internal data class PreparedSharedCloudState(
    val workoutDigest: String,
    val extensions: JSONObject?,
    val source: SharedCloudStateSource
)

internal enum class SharedCloudStateSource {
    CanonicalV2,
    LegacyPwaV2
}

/**
 * Validates an authenticated cloud row before it can replace Room data or arm automatic writes.
 *
 * Already released PWA builds used top-level language/mappings/profile fields and flat workout
 * IDs. Rows with an owner require an exact Supabase binding. Truly old ownerless PWA rows are
 * accepted only through this authenticated user_states pull path, whose query and RLS already bind
 * the row to activeUserId; the next CAS write adds the canonical owner. The fields are represented
 * as extensions.pwa for the validated read result while the workout projection is interpreted by
 * the bounded validator. Compatibility writes intentionally omit that extension again.
 */
internal fun prepareSharedCloudState(
    root: JSONObject,
    activeUserId: String
): PreparedSharedCloudState {
    require(activeUserId.isNotBlank()) { "An active cloud account is required." }
    WorkoutDataLimits.requireSafeJsonEnvelope(root.toString())

    return when {
        looksLikeCanonicalV2(root) -> prepareCanonicalV2(root, activeUserId)
        looksLikeLegacyPwaV2(root) -> prepareLegacyPwaV2(root, activeUserId)
        else -> throw IllegalArgumentException("Cloud state uses an unsupported shared format.")
    }
}

internal fun isSharedCloudStateCandidate(root: JSONObject): Boolean =
    root.has("schemaVersion") ||
        root.has("owner") ||
        root.has("summary") ||
        root.has("extensions") ||
        listOf("language", "mappings", "profile").any(root::has)

internal fun isCanonicalSharedCloudEnvelope(root: JSONObject, activeUserId: String): Boolean =
    runCatching {
        prepareSharedCloudState(root, activeUserId).source == SharedCloudStateSource.CanonicalV2
    }.getOrDefault(false)

/** Historical call-site name; emits the validated v2.2.9-compatible core without extensions. */
internal fun attachSharedCloudExtensions(
    canonicalCore: JSONObject,
    extensions: JSONObject?
): JSONObject {
    // Keep validating any retained remote bag so an attacker-controlled value never becomes an
    // implicit trusted local value. The bag is intentionally not written back while v2.2.9 must
    // share this row; those clients reject or erase fields outside their exact canonical core.
    extensions?.let(::validateExtensions)
    val result = JSONObject(canonicalCore.toString())
    result.remove("extensions")
    result.remove("catalogSeedVersion")
    result.optJSONArray("exercises")?.let { exercises ->
        repeat(exercises.length()) { index ->
            exercises.optJSONObject(index)?.apply {
                remove("favorite")
                remove("loadProfile")
            }
        }
    }
    result.optJSONArray("sessions")?.let { sessions ->
        repeat(sessions.length()) { sessionIndex ->
            sessions.optJSONObject(sessionIndex)
                ?.optJSONArray("exercises")
                ?.let { blocks ->
                    repeat(blocks.length()) { blockIndex ->
                        blocks.optJSONObject(blockIndex)?.apply {
                            remove("favorite")
                            remove("loadProfile")
                        }
                    }
                }
        }
    }
    require(result.keySet() == V229_CANONICAL_ROOT_KEYS) {
        "Cloud write contains fields unsupported by v2.2.9."
    }
    val owner = result.optJSONObject("owner")
        ?: throw IllegalArgumentException("Cloud owner is missing.")
    val userId = owner.opt("userId") as? String
        ?: throw IllegalArgumentException("Cloud owner user ID is missing.")
    require(owner.opt("accountId") == userId) {
        "Cloud owner account ID is not compatible with v2.2.9."
    }
    prepareCanonicalV2(result, userId)
    WorkoutDataLimits.requireSafeJsonEnvelope(result.toString())
    return result
}

private fun prepareCanonicalV2(
    root: JSONObject,
    activeUserId: String
): PreparedSharedCloudState {
    val requiredRootKeys = setOf(
        "schemaVersion",
        "exportedAt",
        "app",
        "diagnostics",
        "owner",
        "exercises",
        "sessions",
        "summary"
    )
    requireExactKeys(
        root,
        required = requiredRootKeys,
        optional = setOf("catalogSeedVersion", "extensions"),
        path = "Cloud state"
    )
    require(root.exactLong("schemaVersion") == 2L) { "Unsupported cloud schema version." }
    val exportedAt = root.exactLong("exportedAt")
        ?: throw IllegalArgumentException("Cloud export timestamp must be an integer.")
    require(WorkoutDataLimits.isValidTimestamp(exportedAt)) {
        "Cloud export timestamp is outside the supported range."
    }
    require(root.opt("app") == "GymApp" && root.opt("diagnostics") == false) {
        "Cloud state metadata is not canonical."
    }
    if (root.has("catalogSeedVersion")) {
        require(
            root.exactLong("catalogSeedVersion") in
                0L..BuiltInExerciseCatalog.SEED_VERSION.toLong()
        ) { "Unsupported exercise catalog seed version." }
    }
    validateBoundOwner(root, activeUserId, allowLegacyRemoteMarker = false)

    val backup = BackupImportValidator.validate(root)
    validatePortableCatalogKeys(backup)
    val catalogByIdentity = backup.exercises.associateBy { it.identityKey }
    require(catalogByIdentity.size == backup.exercises.size) {
        "Cloud exercise catalog contains a duplicate identity."
    }

    val rawExercises = root.optJSONArray("exercises")
        ?: throw IllegalArgumentException("Cloud exercise catalog is missing.")
    repeat(rawExercises.length()) { index ->
        requireExerciseWire(
            rawExercises.optJSONObject(index)
                ?: throw IllegalArgumentException("Cloud exercise entry must be an object."),
            block = false
        )
    }

    val rawSessions = root.optJSONArray("sessions")
        ?: throw IllegalArgumentException("Cloud workout history is missing.")
    require(rawSessions.length() == backup.sessions.size) { "Cloud workout history is invalid." }
    require(backup.sessions.zipWithNext().all { (earlier, later) ->
        earlier.date <= later.date
    }) {
        "Cloud workout history must be ordered by date."
    }
    backup.sessions.forEachIndexed { sessionIndex, session ->
        val rawSession = rawSessions.optJSONObject(sessionIndex)
            ?: throw IllegalArgumentException("Cloud workout must be an object.")
        requireExactKeys(
            rawSession,
            required = setOf("date", "exercises"),
            optional = setOf("note"),
            path = "Cloud workout"
        )
        require(session.blocks.isNotEmpty()) { "Cloud workout must contain an exercise." }
        val rawBlocks = rawSession.optJSONArray("exercises")
            ?: throw IllegalArgumentException("Cloud workout exercises are missing.")
        require(rawBlocks.length() == session.blocks.size) { "Cloud workout exercises are invalid." }
        session.blocks.forEachIndexed { blockIndex, block ->
            val rawBlock = rawBlocks.optJSONObject(blockIndex)
                ?: throw IllegalArgumentException("Cloud workout exercise must be an object.")
            requireExerciseWire(rawBlock, block = true)
            require(block.sets.isNotEmpty()) { "Cloud workout exercise must contain a set." }
            val catalogExercise = catalogByIdentity[block.exercise.identityKey]
                ?: throw IllegalArgumentException(
                    "Cloud workout exercise is absent from the authoritative catalog."
                )
            require(
                block.exercise.loadProfile == null ||
                    block.exercise.loadProfile == catalogExercise.loadProfile
            ) { "Cloud workout exercise load profile does not match the catalog." }
        }
    }

    validateSummary(root.optJSONObject("summary"), backup)
    val extensions = root.optJSONObject("extensions")?.also(::validateExtensions)
        ?.let { JSONObject(it.toString()) }
    return PreparedSharedCloudState(
        workoutDigest = canonicalV229CloudWorkoutDigest(backup),
        extensions = extensions,
        source = SharedCloudStateSource.CanonicalV2
    )
}

private fun prepareLegacyPwaV2(
    root: JSONObject,
    activeUserId: String
): PreparedSharedCloudState {
    val ownerlessLegacyKeys = setOf("language", "exercises", "sessions", "mappings", "profile")
    val isOwnerlessLegacy = root.keySet() == ownerlessLegacyKeys
    if (isOwnerlessLegacy) {
        // The only identity available in the earliest PWA format is the authenticated
        // user_states.user_id selected by loadRemoteState. No manual backup/import calls this
        // preparation function, and the exact five-key shape prevents a partial modern envelope
        // from silently bypassing its required owner.
        require(activeUserId.isNotBlank()) { "Authenticated cloud owner is missing." }
    } else {
        requireExactKeys(
            root,
            required = setOf(
                "schemaVersion",
                "exportedAt",
                "app",
                "diagnostics",
                "owner",
                "language",
                "exercises",
                "sessions",
                "mappings",
                "profile"
            ),
            optional = emptySet(),
            path = "Legacy browser cloud state"
        )
        require(root.exactLong("schemaVersion") == 2L) { "Unsupported cloud schema version." }
        val exportedAt = root.exactLong("exportedAt")
            ?: throw IllegalArgumentException("Cloud export timestamp must be an integer.")
        require(WorkoutDataLimits.isValidTimestamp(exportedAt)) {
            "Cloud export timestamp is outside the supported range."
        }
        require(root.opt("app") == "GymApp" && root.opt("diagnostics") == false) {
            "Cloud state metadata is not canonical."
        }
        validateBoundOwner(root, activeUserId, allowLegacyRemoteMarker = true)
    }

    val language = root.opt("language") as? String
        ?: throw IllegalArgumentException("Browser language is invalid.")
    require(language in setOf("en", "uk", "ru")) { "Browser language is unsupported." }
    val mappings = root.optJSONObject("mappings")
        ?: throw IllegalArgumentException("Browser muscle mappings are invalid.")
    val profile = root.optJSONObject("profile")
        ?: throw IllegalArgumentException("Browser training profile is invalid.")
    val backup = BackupImportValidator.validate(root)
    validateLegacyPortableCatalogKeys(backup)

    val pwa = JSONObject()
        .put("version", 1)
        .put("language", language)
        .put("mappings", JSONObject(mappings.toString()))
        .put("profile", JSONObject(profile.toString()))
    val extensions = JSONObject().put("pwa", pwa)
    validateExtensions(extensions)
    return PreparedSharedCloudState(
        workoutDigest = canonicalV229CloudWorkoutDigest(backup),
        extensions = extensions,
        source = SharedCloudStateSource.LegacyPwaV2
    )
}

private fun validateBoundOwner(
    root: JSONObject,
    activeUserId: String,
    allowLegacyRemoteMarker: Boolean
) {
    val owner = root.optJSONObject("owner")
        ?: throw IllegalArgumentException("Cloud owner is missing.")
    requireExactKeys(
        owner,
        required = setOf("accountId", "userId", "remote"),
        optional = setOf("email"),
        path = "Cloud owner"
    )
    validateBackupOwnerContext(
        root = root,
        activeAccountId = null,
        activeUserId = activeUserId,
        activeRemote = true
    )
    val marker = owner.opt("remote")
    require(marker == true || (allowLegacyRemoteMarker && marker == "supabase")) {
        "Cloud owner remote marker is invalid."
    }
}

private fun validateSummary(
    summary: JSONObject?,
    backup: com.example.gymapp.data.repository.ValidatedBackup
) {
    summary ?: throw IllegalArgumentException("Cloud summary is missing.")
    requireExactKeys(
        summary,
        required = setOf("exerciseCount", "sessionCount", "setCount", "totalVolume"),
        optional = emptySet(),
        path = "Cloud summary"
    )
    val setCount = backup.sessions.sumOf { session ->
        session.blocks.sumOf { block -> block.sets.size }
    }
    val totalVolume = backup.sessions.sumOf { session ->
        session.blocks.sumOf { block ->
            block.sets.sumOf { set -> set.weight * set.reps }
        }
    }.let { if (it == 0.0) 0.0 else it }
    require(summary.exactLong("exerciseCount") == backup.exercises.size.toLong()) {
        "Cloud summary exercise count is inconsistent."
    }
    require(summary.exactLong("sessionCount") == backup.sessions.size.toLong()) {
        "Cloud summary workout count is inconsistent."
    }
    require(summary.exactLong("setCount") == setCount.toLong()) {
        "Cloud summary set count is inconsistent."
    }
    val rawVolume = summary.opt("totalVolume") as? Number
        ?: throw IllegalArgumentException("Cloud summary volume must be numeric.")
    val volume = rawVolume.toDouble().let { if (it == 0.0) 0.0 else it }
    require(volume.isFinite() && volume == totalVolume) {
        "Cloud summary volume is inconsistent."
    }
}

private fun validatePortableCatalogKeys(
    backup: com.example.gymapp.data.repository.ValidatedBackup
) {
    fun requirePortableIdentity(
        exercise: com.example.gymapp.data.repository.ValidatedBackupExercise
    ) {
        require(BuiltInExerciseCatalog.inferKey(exercise.name) == exercise.catalogKey) {
            "Cloud exercise catalog key does not match its canonical name."
        }
    }
    backup.exercises.forEach(::requirePortableIdentity)
    backup.sessions.forEach { session ->
        session.blocks.forEach { block -> requirePortableIdentity(block.exercise) }
    }
}

private fun validateLegacyPortableCatalogKeys(
    backup: com.example.gymapp.data.repository.ValidatedBackup
) {
    fun requireCompatibleIdentity(
        exercise: com.example.gymapp.data.repository.ValidatedBackupExercise
    ) {
        val inferred = BuiltInExerciseCatalog.inferKey(exercise.name)
        require(
            when {
                inferred != null -> exercise.catalogKey == null || exercise.catalogKey == inferred
                else -> exercise.catalogKey == null
            }
        ) { "Legacy browser exercise catalog key conflicts with its name." }
    }
    backup.exercises.forEach(::requireCompatibleIdentity)
    backup.sessions.forEach { session ->
        session.blocks.forEach { block -> requireCompatibleIdentity(block.exercise) }
    }
}

private fun requireExerciseWire(exercise: JSONObject, block: Boolean) {
    requireExactKeys(
        exercise,
        required = if (block) setOf("name", "sets") else setOf("name"),
        optional = setOf("catalogKey", "loadProfile"),
        path = if (block) "Cloud workout exercise" else "Cloud catalog exercise"
    )
    if (block) {
        val sets = exercise.optJSONArray("sets")
            ?: throw IllegalArgumentException("Cloud workout sets are missing.")
        repeat(sets.length()) { index ->
            requireExactKeys(
                sets.optJSONObject(index)
                    ?: throw IllegalArgumentException("Cloud workout set must be an object."),
                required = setOf("weight", "reps"),
                optional = emptySet(),
                path = "Cloud workout set"
            )
        }
    }
}

private fun validateExtensions(extensions: JSONObject) {
    val namespacePattern = Regex("^[a-z][a-z0-9_.-]{0,63}$")
    require(extensions.length() <= MAX_CLOUD_EXTENSION_NAMESPACES) {
        "Cloud state has too many extension namespaces."
    }
    extensions.keySet().forEach { namespace ->
        require(namespace.matches(namespacePattern)) { "Cloud extension namespace is invalid." }
        val value = extensions.optJSONObject(namespace)
            ?: throw IllegalArgumentException("Cloud extension namespace must contain an object.")
        if (namespace == "pwa") validatePwaExtension(value)
    }
    // Re-run the allocation and string/depth limits against the exact bag that will be retained.
    WorkoutDataLimits.requireSafeJsonEnvelope(extensions.toString())
}

private fun validatePwaExtension(pwa: JSONObject) {
    requireExactKeys(
        pwa,
        required = setOf("version", "language", "mappings", "profile"),
        optional = emptySet(),
        path = "PWA cloud extension"
    )
    require(pwa.exactLong("version") == 1L) { "Unsupported PWA cloud extension version." }
    require(pwa.opt("language") in setOf("en", "uk", "ru")) {
        "PWA cloud extension language is unsupported."
    }
    require(pwa.opt("mappings") is JSONObject && pwa.opt("profile") is JSONObject) {
        "PWA cloud extension data is invalid."
    }
    validatePwaMappings(pwa.getJSONObject("mappings"))
    validatePwaProfile(pwa.getJSONObject("profile"))
}

private fun validatePwaMappings(mappings: JSONObject) {
    val keys = mappings.keySet()
    require(keys.size <= WorkoutDataLimits.MAX_EXERCISES) {
        "PWA cloud extension has too many muscle mappings."
    }
    keys.forEach { exerciseName ->
        require(WorkoutDataLimits.isValidExerciseName(exerciseName)) {
            "PWA cloud extension contains an invalid exercise mapping."
        }
        val muscles = mappings.optJSONArray(exerciseName)
            ?: throw IllegalArgumentException("PWA muscle mapping must be an array.")
        require(muscles.length() <= MAX_PWA_MAPPING_MUSCLES) {
            "PWA muscle mapping has too many muscle identifiers."
        }
        val distinctMuscles = linkedSetOf<String>()
        repeat(muscles.length()) { index ->
            val muscle = muscles.opt(index) as? String
                ?: throw IllegalArgumentException("PWA muscle identifier must be a string.")
            require(
                muscle.isNotBlank() &&
                    muscle.length <= MAX_PWA_MUSCLE_IDENTIFIER_UTF16_UNITS &&
                    WorkoutDataLimits.utf8ByteLengthAtMost(
                        muscle,
                        MAX_PWA_MUSCLE_IDENTIFIER_BYTES
                    ) != null &&
                    muscle.none(Char::isISOControl) &&
                    distinctMuscles.add(muscle)
            ) { "PWA muscle identifier is invalid or duplicated." }
        }
    }
}

private fun validatePwaProfile(profile: JSONObject) {
    requireExactKeys(
        profile,
        required = setOf("split", "days", "goal", "calories"),
        optional = emptySet(),
        path = "PWA training profile"
    )
    require(profile.opt("split") in PWA_PROFILE_SPLITS) {
        "PWA training split is unsupported."
    }
    require(profile.exactLong("days") in 2L..6L) {
        "PWA training days are unsupported."
    }
    require(profile.opt("goal") in PWA_PROFILE_GOALS) {
        "PWA training goal is unsupported."
    }
    require(profile.opt("calories") in PWA_PROFILE_CALORIES) {
        "PWA calorie mode is unsupported."
    }
}

private fun looksLikeCanonicalV2(root: JSONObject): Boolean =
    root.has("summary") || root.has("extensions")

private fun looksLikeLegacyPwaV2(root: JSONObject): Boolean =
    listOf("language", "mappings", "profile").all(root::has) && !root.has("summary")

private fun requireExactKeys(
    value: JSONObject,
    required: Set<String>,
    optional: Set<String>,
    path: String
) {
    val keys = value.keySet()
    require(keys.containsAll(required) && keys.all { it in required || it in optional }) {
        "$path contains unsupported or missing fields."
    }
}

private fun JSONObject.keySet(): Set<String> = buildSet {
    val iterator = keys()
    while (iterator.hasNext()) add(iterator.next())
}

private fun JSONObject.exactLong(key: String): Long? {
    val value = opt(key) as? Number ?: return null
    val number = value.toDouble()
    if (!number.isFinite() || number % 1.0 != 0.0) return null
    val longValue = value.toLong()
    return longValue.takeIf { it.toDouble() == number }
}

private const val MAX_PWA_MAPPING_MUSCLES = 32
private const val MAX_PWA_MUSCLE_IDENTIFIER_UTF16_UNITS = 64
private const val MAX_PWA_MUSCLE_IDENTIFIER_BYTES = 256
private const val MAX_CLOUD_EXTENSION_NAMESPACES = 32
private val V229_CANONICAL_ROOT_KEYS = setOf(
    "schemaVersion",
    "exportedAt",
    "app",
    "diagnostics",
    "owner",
    "exercises",
    "sessions",
    "summary"
)
private val PWA_PROFILE_SPLITS = setOf("Upper / Lower", "Full Body", "Push Pull Legs", "Custom")
private val PWA_PROFILE_GOALS = setOf("Aesthetic Cut", "Muscle Gain", "Strength", "Balanced")
private val PWA_PROFILE_CALORIES = setOf("Deficit", "Maintenance", "Surplus")
