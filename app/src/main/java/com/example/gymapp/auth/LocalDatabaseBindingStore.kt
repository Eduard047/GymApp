package com.example.gymapp.auth

import android.content.Context

internal const val LOCAL_DATABASE_BINDING_PREFERENCES = "gym_local_database_bindings"

private val LOCAL_DATABASE_BINDING_LOCK = Any()

internal data class LocalDatabaseBindingSnapshot(
    val logicalName: String,
    val values: Map<String, String>,
    val relevantKeys: Set<String>
)

/**
 * Maps a collision-resistant logical local-account identity to its physical
 * SQLite filename. Legacy databases remain in place so their main/WAL/SHM
 * files are never split by a best-effort rename.
 */
internal class LocalDatabaseBindingStore(context: Context) {
    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences(
        LOCAL_DATABASE_BINDING_PREFERENCES,
        Context.MODE_PRIVATE
    )

    fun restoreStoredSession(
        session: AccountSession.Local,
        allowPendingLogicalCreation: Boolean = false
    ): Boolean =
        synchronized(LOCAL_DATABASE_BINDING_LOCK) {
            runCatching {
                val names = namesFor(session)
                validateExistingBindingLocked(
                    names = names,
                    allowPendingLogicalCreation = allowPendingLogicalCreation
                )?.let { return@synchronized true }

                val logicalExists = databaseExists(names.logical)
                val legacyExists = databaseExists(names.legacy)
                check(!(logicalExists && legacyExists)) {
                    "Both legacy and collision-resistant local databases exist."
                }
                val physical = when {
                    legacyExists -> names.legacy
                    logicalExists -> names.logical
                    else -> error("No recoverable local database is registered.")
                }
                bindLocked(names.logical, physical)
            }.getOrDefault(false)
        }

    fun snapshot(session: AccountSession.Local): LocalDatabaseBindingSnapshot? =
        synchronized(LOCAL_DATABASE_BINDING_LOCK) {
            runCatching {
                val names = namesFor(session)
                val keys = setOf(
                    directKey(names.logical),
                    reverseKey(names.logical),
                    reverseKey(names.legacy),
                    pendingKey(names.logical)
                )
                val values = keys.mapNotNull { key ->
                    if (!preferences.contains(key)) return@mapNotNull null
                    val value = preferences.all[key] as? String
                        ?: error("The local database binding is corrupt.")
                    key to value
                }.toMap()
                LocalDatabaseBindingSnapshot(
                    logicalName = names.logical,
                    values = values,
                    relevantKeys = keys
                )
            }.getOrNull()
        }

    fun restore(snapshot: LocalDatabaseBindingSnapshot): Boolean =
        synchronized(LOCAL_DATABASE_BINDING_LOCK) {
            runCatching {
                require(snapshot.relevantKeys.size == 4)
                require(snapshot.values.keys.all { it in snapshot.relevantKeys })
                val editor = preferences.edit()
                snapshot.relevantKeys.forEach(editor::remove)
                snapshot.values.forEach(editor::putString)
                editor.commit()
            }.getOrDefault(false)
        }

    fun registerNewSession(session: AccountSession.Local): Boolean =
        synchronized(LOCAL_DATABASE_BINDING_LOCK) {
            runCatching {
                val names = namesFor(session)
                validateExistingBindingLocked(
                    names = names,
                    allowPendingLogicalCreation = true
                )?.let { return@synchronized true }

                val logicalExists = databaseExists(names.logical)
                val legacyExists = databaseExists(names.legacy)
                check(!(logicalExists && legacyExists)) {
                    "Both legacy and collision-resistant local databases exist."
                }

                if (legacyExists) {
                    // An unclaimed historical filename may contain another local
                    // name that collided under the old lossy sanitizer.
                    val legacyOwner = reverseOwnerLocked(names.legacy)
                    check(
                        legacyOwner != null &&
                            legacyOwner != names.logical &&
                            isLocalDatabaseLogicalName(legacyOwner)
                    ) {
                        "An unclaimed legacy local database cannot be reassigned."
                    }
                }
                check(pendingCreationCountLocked() < MAX_PENDING_LOCAL_DATABASE_CREATIONS) {
                    "Too many pending local database creations."
                }
                bindLocked(
                    logical = names.logical,
                    physical = names.logical,
                    pendingCreation = !databaseExists(names.logical)
                )
            }.getOrDefault(false)
        }

    fun rollbackPendingNewSession(session: AccountSession.Local): Boolean =
        synchronized(LOCAL_DATABASE_BINDING_LOCK) {
            runCatching {
                val names = namesFor(session)
                check(!databaseExists(names.logical) && !databaseExists(names.legacy)) {
                    "A materialized local database cannot be rolled back as a pending identity."
                }
                check(pendingOwnerLocked(names.logical) == names.logical) {
                    "The local identity was not created by a pending registration."
                }
                val direct = directKey(names.logical)
                val reverse = reverseKey(names.logical)
                check(preferences.all[direct] == names.logical)
                check(preferences.all[reverse] == names.logical)
                preferences.edit()
                    .remove(direct)
                    .remove(reverse)
                    .remove(pendingKey(names.logical))
                    .commit()
            }.getOrDefault(false)
        }

    fun finalizeMaterializedSession(session: AccountSession.Local): Boolean =
        synchronized(LOCAL_DATABASE_BINDING_LOCK) {
            runCatching {
                val names = namesFor(session)
                check(databaseExists(names.logical)) {
                    "The local database was not materialized."
                }
                check(preferences.all[directKey(names.logical)] == names.logical)
                check(preferences.all[reverseKey(names.logical)] == names.logical)
                val pendingKey = pendingKey(names.logical)
                when {
                    !preferences.contains(pendingKey) -> true
                    pendingOwnerLocked(names.logical) != names.logical -> false
                    else -> preferences.edit().remove(pendingKey).commit()
                }
            }.getOrDefault(false)
        }

    fun hasRecoverableIdentity(session: AccountSession.Local): Boolean =
        synchronized(LOCAL_DATABASE_BINDING_LOCK) {
            runCatching {
                val names = namesFor(session)
                databaseExists(names.logical) ||
                    databaseExists(names.legacy) ||
                    pendingBindingIsConsistentLocked(names.logical)
            }.getOrDefault(false)
        }

    fun isPendingSession(session: AccountSession.Local): Boolean =
        synchronized(LOCAL_DATABASE_BINDING_LOCK) {
            runCatching {
                val names = namesFor(session)
                pendingBindingIsConsistentLocked(names.logical) &&
                    !databaseExists(names.logical) &&
                    !databaseExists(names.legacy)
            }.getOrDefault(false)
        }

    /** Returns a pending owner marker even if first-open left a partial DB file. */
    fun requiresActivationFinalization(session: AccountSession.Local): Boolean =
        synchronized(LOCAL_DATABASE_BINDING_LOCK) {
            runCatching {
                val names = namesFor(session)
                pendingBindingIsConsistentLocked(names.logical) &&
                    !databaseExists(names.legacy)
            }.getOrDefault(false)
        }

    fun removeDeletedSession(
        session: AccountSession.Local,
        expectedPhysicalDatabaseName: String
    ): Boolean = synchronized(LOCAL_DATABASE_BINDING_LOCK) {
        runCatching {
            val names = namesFor(session)
            check(
                expectedPhysicalDatabaseName == names.logical ||
                    expectedPhysicalDatabaseName == names.legacy
            )
            val direct = directKey(names.logical)
            val reverse = reverseKey(expectedPhysicalDatabaseName)
            val currentPhysical = preferences.all[direct]
            val currentOwner = preferences.all[reverse]
            if (currentPhysical == null && currentOwner == null) return@synchronized true
            check(currentPhysical == expectedPhysicalDatabaseName)
            check(currentOwner == names.logical)
            preferences.edit()
                .remove(direct)
                .remove(reverse)
                .remove(pendingKey(names.logical))
                .commit()
        }.getOrDefault(false)
    }

    fun physicalDatabaseName(session: AccountSession.Local): String =
        synchronized(LOCAL_DATABASE_BINDING_LOCK) {
            val names = namesFor(session)
            validateExistingBindingLocked(
                names = names,
                allowPendingLogicalCreation = true
            )
                ?: error("The local database identity is not registered.")
        }

    private fun validateExistingBindingLocked(
        names: LocalDatabaseNames,
        allowPendingLogicalCreation: Boolean
    ): String? {
        val directKey = directKey(names.logical)
        if (!preferences.contains(directKey)) return null
        val physical = preferences.all[directKey] as? String
            ?: error("The local database binding is corrupt.")
        check(physical == names.logical || physical == names.legacy) {
            "The local database binding points outside its allowed filenames."
        }
        check(reverseOwnerLocked(physical) == names.logical) {
            "The local database reverse binding is missing or inconsistent."
        }

        if (physical == names.legacy) {
            check(databaseExists(names.legacy)) {
                "The bound legacy database is missing; refusing to create an empty replacement."
            }
            check(!databaseExists(names.logical)) {
                "Both legacy and collision-resistant local databases exist."
            }
        } else {
            if (databaseExists(names.logical)) {
                val pendingKey = pendingKey(names.logical)
                if (preferences.contains(pendingKey)) {
                    check(pendingOwnerLocked(names.logical) == names.logical)
                }
            } else {
                check(
                    allowPendingLogicalCreation &&
                        pendingBindingIsConsistentLocked(names.logical)
                ) {
                    "The bound local database is missing; refusing to create an empty replacement."
                }
            }
            if (databaseExists(names.legacy)) {
                val legacyOwner = reverseOwnerLocked(names.legacy)
                check(
                    legacyOwner != null &&
                        legacyOwner != names.logical &&
                        isLocalDatabaseLogicalName(legacyOwner)
                ) {
                    "An ambiguous legacy local database exists beside the bound database."
                }
            }
        }
        return physical
    }

    private fun bindLocked(
        logical: String,
        physical: String,
        pendingCreation: Boolean = false
    ): Boolean {
        val directKey = directKey(logical)
        val reverseKey = reverseKey(physical)
        val existingPhysical = preferences.all[directKey]
        check(existingPhysical == null || existingPhysical == physical) {
            "The local account is already bound to another database."
        }
        val existingOwner = preferences.all[reverseKey]
        check(existingOwner == null || existingOwner == logical) {
            "The physical local database is already owned by another account."
        }
        val editor = preferences.edit()
            .putString(directKey, physical)
            .putString(reverseKey, logical)
        if (pendingCreation) {
            editor.putString(pendingKey(logical), logical)
        } else {
            editor.remove(pendingKey(logical))
        }
        return editor.commit()
    }

    private fun reverseOwnerLocked(physical: String): String? {
        val key = reverseKey(physical)
        if (!preferences.contains(key)) return null
        return preferences.all[key] as? String
            ?: error("The local database reverse binding is corrupt.")
    }

    private fun namesFor(session: AccountSession.Local): LocalDatabaseNames {
        val logical = localDatabaseLogicalName(session.displayName)
            ?: error("The local account name is invalid.")
        val legacy = legacyLocalDatabaseName(session.displayName)
            ?: error("The legacy local database name is invalid.")
        return LocalDatabaseNames(logical = logical, legacy = legacy)
    }

    private fun databaseExists(name: String): Boolean =
        appContext.getDatabasePath(name).isFile

    private fun directKey(logical: String): String = "logical_$logical"

    private fun pendingKey(logical: String): String = "pending_$logical"

    private fun pendingOwnerLocked(logical: String): String? {
        val key = pendingKey(logical)
        if (!preferences.contains(key)) return null
        return preferences.all[key] as? String
            ?: error("The local database creation journal is corrupt.")
    }

    private fun pendingBindingIsConsistentLocked(logical: String): Boolean =
        pendingOwnerLocked(logical) == logical &&
            preferences.all[directKey(logical)] == logical &&
            preferences.all[reverseKey(logical)] == logical

    private fun pendingCreationCountLocked(): Int = preferences.all.keys.count {
        it.startsWith(PENDING_KEY_PREFIX)
    }

    private fun reverseKey(physical: String): String =
        "physical_${localIdentityDigest("GymAppLocalDatabaseBindingV1\u0000$physical")}"

    private data class LocalDatabaseNames(
        val logical: String,
        val legacy: String
    )

    private companion object {
        const val PENDING_KEY_PREFIX = "pending_"
        const val MAX_PENDING_LOCAL_DATABASE_CREATIONS = 32
    }
}
