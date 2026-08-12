package com.example.gymapp.auth

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LocalProfileRegistryTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val createdNames = mutableListOf<String>()

    @After
    fun cleanUp() {
        context.getSharedPreferences(LOCAL_PROFILE_REGISTRY_PREFERENCES, Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences(LOCAL_DATABASE_BINDING_PREFERENCES, Context.MODE_PRIVATE)
            .edit().clear().commit()
        createdNames.forEach { name ->
            localDatabaseLogicalName(name)?.let(context::deleteDatabase)
            legacyLocalDatabaseName(name)?.let(context::deleteDatabase)
        }
    }

    @Test
    fun savedProfilesAreBoundedValidatedAndDuplicateSafe() {
        val name = "Profile-${UUID.randomUUID().toString().take(8)}".also(createdNames::add)
        val session = AccountSession.Local(name)
        assertTrue(LocalDatabaseBindingStore(context).registerNewSession(session))
        val registry = LocalProfileRegistry(context)

        assertTrue(registry.ensurePresent(name))
        assertTrue(registry.ensurePresent(name.lowercase()))
        assertFalse(registry.ensurePresent("bad\u0000name"))
        val saved = registry.list().single()
        assertEquals(name, saved.displayName)
        assertEquals(saved.id, UUID.fromString(saved.id).toString())
    }

    @Test
    fun malformedAndOrphanedEntriesFailNeutral() {
        context.getSharedPreferences(LOCAL_PROFILE_REGISTRY_PREFERENCES, Context.MODE_PRIVATE)
            .edit().putString("profiles", "not-json").commit()
        val malformedRegistry = LocalProfileRegistry(context)
        assertTrue(malformedRegistry.list().isEmpty())
        assertFalse(malformedRegistry.canAdd("Safe name"))
        assertFalse(malformedRegistry.ensurePresent("Safe name"))
        assertEquals(
            "not-json",
            context.getSharedPreferences(LOCAL_PROFILE_REGISTRY_PREFERENCES, Context.MODE_PRIVATE)
                .getString("profiles", null)
        )

        val orphan = "Orphan-${UUID.randomUUID()}"
        context.getSharedPreferences(LOCAL_PROFILE_REGISTRY_PREFERENCES, Context.MODE_PRIVATE)
            .edit().putString("profiles", "[\"$orphan\"]").commit()
        assertTrue(LocalProfileRegistry(context).list().isEmpty())
    }
}
