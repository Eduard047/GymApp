package com.example.gymapp.auth

import android.content.Context

internal const val LOCAL_DATABASE_BINDING_PREFERENCES = "gym_local_database_bindings"

private val LOCAL_DATABASE_BINDING_LOCK = Any()
private val PENDING_LOGICAL_DATABASE_CREATIONS = mutableSetOf<String>()

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

    fun restoreStoredSession(session: AccountSession.Local): Boolean =
        synchronized(LOCAL_DATABASE_BINDING_LOCK) {
            runCatching {
                val names = namesFor(session)
                validateExistingBindingLocked(
                    names = names,
                    allowPendingLogicalCreation = false
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
                bindLocked(names.logical, names.logical).also { committed ->
                    if (committed && !databaseExists(names.logical)) {
                        PENDING_LOGICAL_DATABASE_CREATIONS += names.logical
                    }
                }
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
                PENDING_LOGICAL_DATABASE_CREATIONS -= names.logical
            } else {
                check(
                    allowPendingLogicalCreation &&
                        names.logical in PENDING_LOGICAL_DATABASE_CREATIONS
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

    private fun bindLocked(logical: String, physical: String): Boolean {
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
        return preferences.edit()
            .putString(directKey, physical)
            .putString(reverseKey, logical)
            .commit()
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

    private fun reverseKey(physical: String): String =
        "physical_${localIdentityDigest("GymAppLocalDatabaseBindingV1\u0000$physical")}"

    private data class LocalDatabaseNames(
        val logical: String,
        val legacy: String
    )
}
