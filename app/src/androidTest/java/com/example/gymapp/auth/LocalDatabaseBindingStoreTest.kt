package com.example.gymapp.auth

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LocalDatabaseBindingStoreTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val databaseNames = mutableSetOf<String>()

    @After
    fun cleanUp() {
        context.getSharedPreferences(
            LOCAL_DATABASE_BINDING_PREFERENCES,
            Context.MODE_PRIVATE
        ).edit().clear().commit()
        context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
            .edit().clear().commit()
        databaseNames.forEach(::deleteDatabaseFiles)
    }

    @Test
    fun legacyDatabaseAndWalStayInPlaceBehindCollisionResistantAlias() {
        val session = localSession("Legacy/Alias")
        val logical = checkNotNull(localDatabaseLogicalName(session.displayName))
        val legacy = checkNotNull(legacyLocalDatabaseName(session.displayName))
        val legacyFile = databaseFile(legacy).apply { writeText("legacy-main") }
        val walFile = databaseFile("$legacy-wal").apply { writeText("legacy-wal") }
        val store = LocalDatabaseBindingStore(context)

        assertTrue(store.restoreStoredSession(session))
        assertEquals(legacy, store.physicalDatabaseName(session))
        assertEquals("legacy-main", legacyFile.readText())
        assertEquals("legacy-wal", walFile.readText())
        assertFalse(databaseFile(logical).exists())
    }

    @Test
    fun twoNamesThatSharedTheLegacySanitizerCannotClaimOneDatabase() {
        val first = localSession("a/b-${UUID.randomUUID()}")
        val second = localSession(first.displayName.replace("/", "_"))
        val sharedLegacy = checkNotNull(legacyLocalDatabaseName(first.displayName))
        assertEquals(sharedLegacy, legacyLocalDatabaseName(second.displayName))
        databaseFile(sharedLegacy).writeText("owner-one")
        val store = LocalDatabaseBindingStore(context)

        assertTrue(store.restoreStoredSession(first))
        assertFalse(store.restoreStoredSession(second))
        assertEquals(sharedLegacy, store.physicalDatabaseName(first))
        assertThrows(IllegalStateException::class.java) {
            store.physicalDatabaseName(second)
        }
    }

    @Test
    fun simultaneousLegacyAndV2FilesFailClosedWithoutDeletingEither() {
        val session = localSession("Both-${UUID.randomUUID()}")
        val logical = checkNotNull(localDatabaseLogicalName(session.displayName))
        val legacy = checkNotNull(legacyLocalDatabaseName(session.displayName))
        val logicalFile = databaseFile(logical).apply { writeText("new") }
        val legacyFile = databaseFile(legacy).apply { writeText("old") }

        assertFalse(LocalDatabaseBindingStore(context).restoreStoredSession(session))
        assertEquals("new", logicalFile.readText())
        assertEquals("old", legacyFile.readText())
    }

    @Test
    fun missingBoundLegacyFileNeverCreatesAnEmptyReplacement() {
        val session = localSession("Missing-${UUID.randomUUID()}")
        val legacy = checkNotNull(legacyLocalDatabaseName(session.displayName))
        val legacyFile = databaseFile(legacy).apply { writeText("private-data") }
        val store = LocalDatabaseBindingStore(context)
        assertTrue(store.restoreStoredSession(session))
        assertTrue(legacyFile.delete())

        assertFalse(store.restoreStoredSession(session))
        assertThrows(IllegalStateException::class.java) {
            store.physicalDatabaseName(session)
        }
        assertFalse(databaseFile(legacy).exists())
    }

    @Test
    fun missingEstablishedV2DatabaseNeverBecomesAnEmptyReplacement() {
        val session = localSession("Missing-v2-${UUID.randomUUID()}")
        val logical = checkNotNull(localDatabaseLogicalName(session.displayName))
        val store = LocalDatabaseBindingStore(context)
        assertTrue(store.registerNewSession(session))
        val logicalFile = databaseFile(logical).apply { writeText("private-data") }
        assertEquals(logical, store.physicalDatabaseName(session))
        assertTrue(logicalFile.delete())

        assertFalse(store.restoreStoredSession(session))
        assertThrows(IllegalStateException::class.java) {
            store.physicalDatabaseName(session)
        }
        assertFalse(databaseFile(logical).exists())
    }

    @Test
    fun registeredNewIdentitySurvivesAuthPreferenceCleanupBeforeFirstOpen() {
        val session = localSession("New-${UUID.randomUUID()}")
        val logical = checkNotNull(localDatabaseLogicalName(session.displayName))
        val store = LocalDatabaseBindingStore(context)

        assertTrue(store.registerNewSession(session))
        context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
            .edit().clear().commit()

        assertEquals(logical, LocalDatabaseBindingStore(context).physicalDatabaseName(session))
        assertFalse(databaseFile(logical).exists())
    }

    @Test
    fun grandfatheredLocalAuthSessionRestoresOnlyWhenDatabaseIsRecoverable() {
        val displayName = "Grandfathered-${UUID.randomUUID()}"
        val legacy = checkNotNull(legacyLocalDatabaseName(displayName))
        databaseFile(legacy).writeText("legacy")
        context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
            .edit()
            .putString("mode", "local")
            .putString("local_name", displayName)
            .commit()

        val state = CloudAuthManager(context).authState.value

        assertEquals(displayName, (state.session as? AccountSession.Local)?.displayName)
        assertNull(state.message)
        assertEquals(
            legacy,
            LocalDatabaseBindingStore(context).physicalDatabaseName(
                checkNotNull(state.session as? AccountSession.Local)
            )
        )
    }

    @Test
    fun unrecoverableLocalAuthSessionIsSurfacedWithoutCreatingDatabase() {
        val displayName = "Unavailable-${UUID.randomUUID()}"
        val logical = checkNotNull(localDatabaseLogicalName(displayName))
        val legacy = checkNotNull(legacyLocalDatabaseName(displayName))
        context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
            .edit()
            .putString("mode", "local")
            .putString("local_name", displayName)
            .commit()

        val state = CloudAuthManager(context).authState.value

        assertNull(state.session)
        assertNotNull(state.message)
        assertFalse(databaseFile(logical).exists())
        assertFalse(databaseFile(legacy).exists())
    }

    private fun localSession(name: String): AccountSession.Local =
        AccountSession.Local(checkNotNull(normalizedLocalDisplayNameOrNull(name)))

    private fun databaseFile(name: String) = context.getDatabasePath(name).also { file ->
        databaseNames += name.removeSuffix("-wal").removeSuffix("-shm").removeSuffix("-journal")
        check(file.parentFile?.isDirectory == true || file.parentFile?.mkdirs() == true)
    }

    private fun deleteDatabaseFiles(name: String) {
        listOf("", "-wal", "-shm", "-journal").forEach { suffix ->
            context.getDatabasePath(name + suffix).delete()
        }
    }
}
