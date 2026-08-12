package com.example.gymapp.auth

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.gymapp.data.repository.LiveWorkoutBinding
import com.example.gymapp.data.repository.LIVE_SIDECAR_PREFERENCES
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
        context.getSharedPreferences(LOCAL_PROFILE_REGISTRY_PREFERENCES, Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences(
            LOCAL_PROFILE_DELETION_JOURNAL_PREFERENCES,
            Context.MODE_PRIVATE
        ).edit().clear().commit()
        context.getSharedPreferences(LIVE_SIDECAR_PREFERENCES, Context.MODE_PRIVATE)
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
        assertTrue(store.finalizeMaterializedSession(session))
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
    fun durablePendingIdentitySurvivesProcessRecreationAndOnlyExactSavedAuthCanResumeIt() {
        val name = "Restart-${UUID.randomUUID().toString().take(8)}"
        val session = localSession(name)
        val logical = checkNotNull(localDatabaseLogicalName(name))
        val profileId = UUID.randomUUID().toString()
        val firstProcessStore = LocalDatabaseBindingStore(context)
        val registry = LocalProfileRegistry(context)
        assertTrue(firstProcessStore.registerNewSession(session))
        assertTrue(registry.ensurePresent(name, profileId))
        assertTrue(
            context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).edit()
                .putString("mode", "local")
                .putString("local_name", name)
                .putString("local_profile_id", profileId)
                .commit()
        )

        // A fresh manager/store represents a new process: no in-memory pending state is shared.
        val restarted = CloudAuthManager(context)
        assertEquals(name, (restarted.authState.value.session as? AccountSession.Local)?.displayName)
        assertEquals(logical, LocalDatabaseBindingStore(context).physicalDatabaseName(session))
        assertTrue(databaseFile(logical).isFile)
        assertFalse(LocalDatabaseBindingStore(context).isPendingSession(session))

        val wrong = localSession("Wrong-${UUID.randomUUID().toString().take(8)}")
        assertFalse(LocalDatabaseBindingStore(context).restoreStoredSession(wrong, true))
        assertFalse(databaseFile(checkNotNull(localDatabaseLogicalName(wrong.displayName))).exists())
    }

    @Test
    fun restartMaterializationFailureNeverPublishesSessionAndRollsBackExactPendingIdentity() {
        val name = "Restart-fail-${UUID.randomUUID().toString().take(8)}"
        val session = localSession(name)
        val logical = checkNotNull(localDatabaseLogicalName(name))
        val profileId = UUID.randomUUID().toString()
        assertTrue(LocalDatabaseBindingStore(context).registerNewSession(session))
        assertTrue(LocalProfileRegistry(context).ensurePresent(name, profileId))
        assertTrue(
            context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).edit()
                .putString("mode", "local")
                .putString("local_name", name)
                .putString("local_profile_id", profileId)
                .commit()
        )

        val restarted = CloudAuthManager(
            context = context,
            localDatabaseMaterializerOverride = { databaseName ->
                databaseFile(databaseName).writeText("partial")
                false
            },
            localDatabaseRollbackOverride = { databaseName ->
                deleteDatabaseFiles(databaseName)
                !context.getDatabasePath(databaseName).exists()
            }
        )

        assertNull(restarted.authState.value.session)
        assertNotNull(restarted.authState.value.message)
        assertFalse(databaseFile(logical).exists())
        assertNull(LocalProfileRegistry(context).findById(profileId))
        assertTrue(context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).all.isEmpty())
        assertThrows(IllegalStateException::class.java) {
            LocalDatabaseBindingStore(context).physicalDatabaseName(session)
        }
    }

    @Test
    fun materializedPendingIdentityFinalizesDurableJournalAndMissingFileThenFailsClosed() {
        val session = localSession("Finalize-${UUID.randomUUID().toString().take(8)}")
        val logical = checkNotNull(localDatabaseLogicalName(session.displayName))
        val store = LocalDatabaseBindingStore(context)
        assertTrue(store.registerNewSession(session))
        val logicalFile = databaseFile(logical).apply { writeText("sqlite") }

        assertTrue(store.finalizeMaterializedSession(session))
        assertTrue(logicalFile.delete())
        assertFalse(LocalDatabaseBindingStore(context).restoreStoredSession(session, true))
        assertThrows(IllegalStateException::class.java) {
            LocalDatabaseBindingStore(context).physicalDatabaseName(session)
        }
    }

    @Test
    fun pendingNewIdentityCanBeRolledBackWithoutTouchingExistingBindings() {
        val existing = localSession("Existing-${UUID.randomUUID()}")
        val rejected = localSession("Rejected-${UUID.randomUUID()}")
        val store = LocalDatabaseBindingStore(context)
        assertTrue(store.registerNewSession(existing))
        assertTrue(store.registerNewSession(rejected))

        assertTrue(store.rollbackPendingNewSession(rejected))

        assertEquals(
            checkNotNull(localDatabaseLogicalName(existing.displayName)),
            store.physicalDatabaseName(existing)
        )
        assertThrows(IllegalStateException::class.java) {
            store.physicalDatabaseName(rejected)
        }
    }

    @Test
    fun rejectedLocalCreationRollsBackBindingRegistryAuthAndPreservesLiveSidecar() {
        val rejectedName = "Reject-${UUID.randomUUID().toString().take(8)}"
        val cloud = syntheticCloudSession()
        val binding = syntheticLiveBinding(cloud)
        val rejectingRegistry = object : LocalProfileRegistry(context) {
            override fun canAdd(displayName: String): Boolean = true
            override fun ensurePresent(displayName: String, profileId: String?): Boolean = false
        }
        val manager = CloudAuthManager(context, rejectingRegistry)
        assertTrue(manager.testSeedLiveWorkoutSidecar(cloud, binding))
        val authBefore = context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).all.toMap()

        assertThrows(IllegalStateException::class.java) {
            manager.setLocal(rejectedName)
        }

        assertEquals(authBefore, context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).all)
        assertNull(manager.authState.value.session)
        assertEquals(binding, manager.testLoadLiveWorkoutSidecar(cloud))
        assertThrows(IllegalStateException::class.java) {
            LocalDatabaseBindingStore(context).physicalDatabaseName(localSession(rejectedName))
        }
    }

    @Test
    fun rejectedAuthCommitRestoresRegistryPrefsBindingSessionAndLiveSidecar() {
        val rejectedName = "Reject-${UUID.randomUUID().toString().take(8)}"
        val cloud = syntheticCloudSession()
        val binding = syntheticLiveBinding(cloud)
        val authPreferences = context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
        assertTrue(authPreferences.edit().putString("sentinel", "before").commit())
        val manager = CloudAuthManager(
            context = context,
            localAuthCommitterOverride = { editor ->
                // Exercise the Android edge where commit mutates the in-memory map
                // but reports a durable write failure.
                editor.commit()
                false
            }
        )
        assertTrue(manager.testSeedLiveWorkoutSidecar(cloud, binding))
        val authBefore = authPreferences.all.toMap()
        val bindingPreferences = context.getSharedPreferences(
            LOCAL_DATABASE_BINDING_PREFERENCES,
            Context.MODE_PRIVATE
        )
        val bindingsBefore = bindingPreferences.all.toMap()

        assertThrows(IllegalStateException::class.java) {
            manager.setLocal(rejectedName)
        }

        assertEquals(authBefore, authPreferences.all)
        assertEquals(bindingsBefore, bindingPreferences.all)
        assertNull(manager.authState.value.session)
        assertEquals(binding, manager.testLoadLiveWorkoutSidecar(cloud))
        assertFalse(LocalProfileRegistry(context).contains(rejectedName))
        assertThrows(IllegalStateException::class.java) {
            LocalDatabaseBindingStore(context).physicalDatabaseName(localSession(rejectedName))
        }
    }

    @Test
    fun rejectedResumeAuthCommitRestoresNewlyReassociatedLegacyBindingExactly() {
        val name = "Legacy-${UUID.randomUUID().toString().take(8)}"
        val legacy = checkNotNull(legacyLocalDatabaseName(name))
        databaseFile(legacy).writeText("legacy-data")
        val registry = LocalProfileRegistry(context)
        assertTrue(registry.ensurePresent(name))
        val saved = registry.list().single()
        val bindingPreferences = context.getSharedPreferences(
            LOCAL_DATABASE_BINDING_PREFERENCES,
            Context.MODE_PRIVATE
        )
        val bindingsBefore = bindingPreferences.all.toMap()
        val authPreferences = context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
        val authBefore = authPreferences.all.toMap()
        val manager = CloudAuthManager(
            context = context,
            localAuthCommitterOverride = { editor ->
                editor.commit()
                false
            }
        )

        assertThrows(IllegalStateException::class.java) {
            manager.setLocal(saved.id, resumeExisting = true)
        }

        assertEquals(bindingsBefore, bindingPreferences.all)
        assertEquals(authBefore, authPreferences.all)
        assertEquals("legacy-data", databaseFile(legacy).readText())
        assertNull(manager.authState.value.session)
        assertEquals(listOf(saved), manager.savedLocalProfiles())
    }

    @Test
    fun failedLiveSidecarClearRejectsOwnerSwitchAndRollsBackEveryAcceptedStore() {
        val name = "Local-${UUID.randomUUID().toString().take(8)}"
        val cloud = syntheticCloudSession()
        val binding = syntheticLiveBinding(cloud)
        val authPreferences = context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
        val bindingPreferences = context.getSharedPreferences(
            LOCAL_DATABASE_BINDING_PREFERENCES,
            Context.MODE_PRIVATE
        )
        val manager = CloudAuthManager(
            context = context,
            localSidecarClearerOverride = { false }
        )
        assertTrue(manager.testSeedLiveWorkoutSidecar(cloud, binding))
        val authBefore = authPreferences.all.toMap()
        val bindingsBefore = bindingPreferences.all.toMap()

        assertThrows(IllegalStateException::class.java) {
            manager.setLocal(name)
        }

        assertEquals(authBefore, authPreferences.all)
        assertEquals(bindingsBefore, bindingPreferences.all)
        assertNull(manager.authState.value.session)
        assertFalse(LocalProfileRegistry(context).contains(name))
        assertEquals(binding, manager.testLoadLiveWorkoutSidecar(cloud))
    }

    @Test
    fun failedDatabaseMaterializationLeavesNoAcceptedProfileBindingOrPartialFile() {
        val name = "Disk-fail-${UUID.randomUUID().toString().take(8)}"
        val logical = checkNotNull(localDatabaseLogicalName(name))
        val authPreferences = context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
        val bindingPreferences = context.getSharedPreferences(
            LOCAL_DATABASE_BINDING_PREFERENCES,
            Context.MODE_PRIVATE
        )
        val manager = CloudAuthManager(
            context = context,
            localDatabaseMaterializerOverride = { databaseName ->
                databaseFile(databaseName).writeText("partial")
                false
            },
            localDatabaseRollbackOverride = { databaseName ->
                deleteDatabaseFiles(databaseName)
                !context.getDatabasePath(databaseName).exists()
            }
        )
        val authBefore = authPreferences.all.toMap()
        val bindingsBefore = bindingPreferences.all.toMap()

        assertThrows(IllegalStateException::class.java) { manager.setLocal(name) }

        assertEquals(authBefore, authPreferences.all)
        assertEquals(bindingsBefore, bindingPreferences.all)
        assertNull(manager.authState.value.session)
        assertFalse(LocalProfileRegistry(context).contains(name))
        assertFalse(databaseFile(logical).exists())
    }

    @Test
    fun failedResumeMaterializationNeverDeletesExistingProfileDatabase() {
        val name = "Resume-fail-${UUID.randomUUID().toString().take(8)}"
        val legacy = checkNotNull(legacyLocalDatabaseName(name))
        val legacyFile = databaseFile(legacy).apply { writeText("owned-data") }
        val registry = LocalProfileRegistry(context)
        assertTrue(registry.ensurePresent(name))
        val saved = registry.list().single()
        var rollbackCalls = 0
        val manager = CloudAuthManager(
            context = context,
            localDatabaseMaterializerOverride = { false },
            localDatabaseRollbackOverride = {
                rollbackCalls += 1
                false
            }
        )

        assertThrows(IllegalStateException::class.java) {
            manager.setLocal(saved.id, resumeExisting = true)
        }

        assertEquals(0, rollbackCalls)
        assertEquals("owned-data", legacyFile.readText())
        assertNull(manager.authState.value.session)
        assertEquals(listOf(saved), manager.savedLocalProfiles())
    }

    @Test
    fun localDeletionIsCurrentOwnerBoundAndFinalizationCannotTouchAnotherProfile() {
        val firstName = "Delete-${UUID.randomUUID().toString().take(8)}"
        val secondName = "Keep-${UUID.randomUUID().toString().take(8)}"
        val first = localSession(firstName)
        val second = localSession(secondName)
        val firstLogical = checkNotNull(localDatabaseLogicalName(firstName))
        val secondLogical = checkNotNull(localDatabaseLogicalName(secondName))
        val store = LocalDatabaseBindingStore(context)
        assertTrue(store.registerNewSession(first))
        assertTrue(store.registerNewSession(second))
        databaseFile(firstLogical).writeText("first")
        databaseFile(secondLogical).writeText("second")
        assertTrue(store.finalizeMaterializedSession(first))
        assertTrue(store.finalizeMaterializedSession(second))
        val registry = LocalProfileRegistry(context)
        assertTrue(registry.ensurePresent(firstName))
        assertTrue(registry.ensurePresent(secondName))
        val firstSaved = registry.list().first { it.displayName == firstName }
        val secondSaved = registry.list().first { it.displayName == secondName }
        assertTrue(
            context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).edit()
                .putString("mode", "local")
                .putString("local_name", firstName)
                .putString("local_profile_id", firstSaved.id)
                .commit()
        )
        val manager = CloudAuthManager(context)

        assertThrows(IllegalStateException::class.java) {
            manager.prepareLocalProfileDeletion(second)
        }
        assertEquals(first, manager.authState.value.session)
        assertEquals(setOf(firstSaved, secondSaved), manager.savedLocalProfiles().toSet())

        val record = manager.prepareLocalProfileDeletion(first)
        val wrongRecord = PendingLocalProfileDeletion.create(secondSaved, secondLogical)!!
        assertFalse(manager.finalizeLocalProfileDeletion(wrongRecord))
        assertTrue(manager.savedLocalProfiles().isEmpty())
        assertEquals("second", databaseFile(secondLogical).readText())

        assertTrue(databaseFile(firstLogical).delete())
        assertTrue(manager.finalizeLocalProfileDeletion(record))
        assertEquals(listOf(secondSaved), manager.savedLocalProfiles())
        assertEquals(secondLogical, store.physicalDatabaseName(second))
        assertEquals("second", databaseFile(secondLogical).readText())
    }

    @Test
    fun pendingLocalDeletionSuppressesOnlyItsExactProfileAfterRestart() {
        val name = "Pending-delete-${UUID.randomUUID().toString().take(8)}"
        val session = localSession(name)
        val logical = checkNotNull(localDatabaseLogicalName(name))
        val store = LocalDatabaseBindingStore(context)
        assertTrue(store.registerNewSession(session))
        databaseFile(logical).writeText("owned")
        assertTrue(store.finalizeMaterializedSession(session))
        val registry = LocalProfileRegistry(context)
        assertTrue(registry.ensurePresent(name))
        val saved = registry.list().single()
        assertTrue(
            context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).edit()
                .putString("mode", "local")
                .putString("local_name", name)
                .putString("local_profile_id", saved.id)
                .commit()
        )
        val record = PendingLocalProfileDeletion.create(saved, logical)!!
        assertTrue(LocalProfileDeletionJournal(context).mark(record))

        val restarted = CloudAuthManager(context)

        assertNull(restarted.authState.value.session)
        assertNotNull(restarted.authState.value.message)
        assertEquals("owned", databaseFile(logical).readText())
        assertEquals(saved, LocalProfileRegistry(context).findById(saved.id))
        assertEquals(record, restarted.pendingLocalProfileDeletion())
    }

    @Test
    fun pendingDeletionHidesAndRejectsExactResumeBeforeAnyMutation() {
        val target = prepareActiveLocalProfile("Pending-resume")
        val targetRecord = PendingLocalProfileDeletion.create(target.saved, target.logical)!!
        val otherName = "Other-resume-${UUID.randomUUID().toString().take(8)}"
        val other = localSession(otherName)
        val otherLogical = checkNotNull(localDatabaseLogicalName(otherName))
        val store = LocalDatabaseBindingStore(context)
        assertTrue(store.registerNewSession(other))
        databaseFile(otherLogical).writeText("other")
        assertTrue(store.finalizeMaterializedSession(other))
        val registry = LocalProfileRegistry(context)
        assertTrue(registry.ensurePresent(otherName))
        val otherSaved = registry.list().single { it.displayName == otherName }
        assertTrue(LocalProfileDeletionJournal(context).mark(targetRecord))
        assertTrue(context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).edit().clear().commit())
        val authBefore = context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).all.toMap()
        val bindingsBefore = context.getSharedPreferences(
            LOCAL_DATABASE_BINDING_PREFERENCES,
            Context.MODE_PRIVATE
        ).all.toMap()
        val manager = CloudAuthManager(context)

        assertTrue(manager.savedLocalProfiles().isEmpty())
        assertThrows(IllegalStateException::class.java) {
            manager.setLocal(target.saved.id, resumeExisting = true)
        }
        assertEquals(authBefore, context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).all)
        assertEquals(
            bindingsBefore,
            context.getSharedPreferences(LOCAL_DATABASE_BINDING_PREFERENCES, Context.MODE_PRIVATE).all
        )
        assertEquals("owned", databaseFile(target.logical).readText())
        assertNull(manager.authState.value.session)

        assertThrows(IllegalStateException::class.java) {
            manager.setLocal(otherSaved.id, resumeExisting = true)
        }
        assertNull(manager.authState.value.session)
        assertTrue(databaseFile(otherLogical).isFile)
    }

    @Test
    fun pendingLocalDeletionSuppressesPreviouslyStoredCloudSessionAtRestart() {
        val target = prepareActiveLocalProfile("Pending-cloud")
        val record = PendingLocalProfileDeletion.create(target.saved, target.logical)!!
        assertTrue(LocalProfileDeletionJournal(context).mark(record))
        val cloud = syntheticCloudSession()
        val cloudJson = org.json.JSONObject()
            .put("userId", cloud.userId)
            .put("email", cloud.email)
            .put("displayName", cloud.displayName)
            .put("accessToken", cloud.accessToken)
            .put("refreshToken", cloud.refreshToken)
            .put("sessionGeneration", cloud.sessionGeneration)
            .toString()
        assertTrue(
            context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).edit()
                .clear()
                .putString("mode", "cloud")
                .putString("cloud", cloudJson)
                .commit()
        )

        val restarted = CloudAuthManager(context)

        assertNull(restarted.authState.value.session)
        assertNotNull(restarted.authState.value.message)
        assertTrue(context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).all.isEmpty())
        assertEquals(record, restarted.pendingLocalProfileDeletion())
        assertEquals("owned", databaseFile(target.logical).readText())
        assertNotNull(LocalProfileRegistry(context).findById(target.saved.id))
    }

    @Test
    fun deletionJournalWriteFailureLeavesActiveProfileAndSidecarByteForByteUntouched() {
        val setup = prepareActiveLocalProfile("Journal-fail")
        val cloud = syntheticCloudSession()
        val binding = syntheticLiveBinding(cloud)
        val auth = context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
        val authBefore = auth.all.toMap()
        val refusingJournal = object : LocalProfileDeletionJournal(context) {
            override fun mark(record: PendingLocalProfileDeletion): Boolean = false
        }
        val manager = CloudAuthManager(
            context = context,
            localProfileDeletionJournalOverride = refusingJournal
        )
        assertTrue(manager.testSeedLiveWorkoutSidecar(cloud, binding))

        assertThrows(IllegalStateException::class.java) {
            manager.prepareLocalProfileDeletion(setup.session)
        }

        assertEquals(setup.session, manager.authState.value.session)
        assertEquals(authBefore, auth.all)
        assertEquals(binding, manager.testLoadLiveWorkoutSidecar(cloud))
        assertNotNull(LocalProfileRegistry(context).findById(setup.saved.id))
        assertEquals("owned", databaseFile(setup.logical).readText())
    }

    @Test
    fun authClearFailureKeepsAuthoritativeDeletionJournalAndDoesNotClearSidecar() {
        val setup = prepareActiveLocalProfile("Auth-clear-fail")
        val cloud = syntheticCloudSession()
        val binding = syntheticLiveBinding(cloud)
        val manager = CloudAuthManager(
            context = context,
            localAuthClearerOverride = { false }
        )
        assertTrue(manager.testSeedLiveWorkoutSidecar(cloud, binding))

        assertThrows(IllegalStateException::class.java) {
            manager.prepareLocalProfileDeletion(setup.session)
        }

        assertNull(manager.authState.value.session)
        assertEquals(binding, manager.testLoadLiveWorkoutSidecar(cloud))
        assertNotNull(manager.pendingLocalProfileDeletion())
        val restarted = CloudAuthManager(context)
        assertNull(restarted.authState.value.session)
        assertNotNull(restarted.authState.value.message)
        assertEquals("owned", databaseFile(setup.logical).readText())
    }

    @Test
    fun deletionFinalizationRetriesAfterRegistryFailureWithoutTouchingOtherOwner() {
        val target = prepareActiveLocalProfile("Retry-delete")
        val otherName = "Other-${UUID.randomUUID().toString().take(8)}"
        val otherSession = localSession(otherName)
        val otherLogical = checkNotNull(localDatabaseLogicalName(otherName))
        val store = LocalDatabaseBindingStore(context)
        assertTrue(store.registerNewSession(otherSession))
        databaseFile(otherLogical).writeText("other")
        assertTrue(store.finalizeMaterializedSession(otherSession))
        val baseRegistry = LocalProfileRegistry(context)
        assertTrue(baseRegistry.ensurePresent(otherName))
        var failTargetRemovalOnce = true
        val retryingRegistry = object : LocalProfileRegistry(context) {
            override fun remove(profileId: String): Boolean {
                if (profileId == target.saved.id && failTargetRemovalOnce) {
                    failTargetRemovalOnce = false
                    return false
                }
                return super.remove(profileId)
            }
        }
        val manager = CloudAuthManager(context, localProfileRegistryOverride = retryingRegistry)
        val record = manager.prepareLocalProfileDeletion(target.session)
        assertTrue(databaseFile(target.logical).delete())

        assertFalse(manager.finalizeLocalProfileDeletion(record))
        assertEquals(record, manager.pendingLocalProfileDeletion())
        assertNotNull(baseRegistry.findById(target.saved.id))
        assertEquals("other", databaseFile(otherLogical).readText())

        assertTrue(manager.finalizeLocalProfileDeletion(record))
        assertNull(baseRegistry.findById(target.saved.id))
        assertNull(manager.pendingLocalProfileDeletion())
        assertEquals(otherLogical, store.physicalDatabaseName(otherSession))
        assertEquals("other", databaseFile(otherLogical).readText())
    }

    @Test
    fun deletionFinalizationRetriesJournalClearAfterIdentityWasAlreadyRemoved() {
        val target = prepareActiveLocalProfile("Journal-clear-retry")
        var clearCalls = 0
        val retryingJournal = object : LocalProfileDeletionJournal(context) {
            override fun clear(expected: PendingLocalProfileDeletion): Boolean {
                clearCalls += 1
                return if (clearCalls == 1) false else super.clear(expected)
            }
        }
        val manager = CloudAuthManager(
            context = context,
            localProfileDeletionJournalOverride = retryingJournal
        )
        val record = manager.prepareLocalProfileDeletion(target.session)
        assertTrue(databaseFile(target.logical).delete())

        assertFalse(manager.finalizeLocalProfileDeletion(record))
        assertEquals(record, manager.pendingLocalProfileDeletion())
        assertNull(LocalProfileRegistry(context).findById(target.saved.id))
        assertTrue(manager.finalizeLocalProfileDeletion(record))
        assertNull(manager.pendingLocalProfileDeletion())
    }

    @Test
    fun savedLocalProfileUsesStableOpaqueIdAndDuplicateCreateDoesNotMutate() {
        val name = "Local-${UUID.randomUUID().toString().take(8)}"
        val logical = checkNotNull(localDatabaseLogicalName(name))
        val manager = CloudAuthManager(context)

        manager.setLocal(name)
        val saved = manager.savedLocalProfiles().single()
        assertEquals(name, saved.displayName)
        assertEquals(saved.id, UUID.fromString(saved.id).toString())
        SQLiteDatabase.openDatabase(
            databaseFile(logical).path,
            null,
            SQLiteDatabase.OPEN_READWRITE
        ).use { database ->
            database.execSQL("CREATE TABLE profile_sentinel(value TEXT NOT NULL)")
            database.execSQL("INSERT INTO profile_sentinel(value) VALUES ('profile-data')")
        }
        manager.logout()

        val registryBeforeDuplicate = manager.savedLocalProfiles()
        assertThrows(IllegalStateException::class.java) {
            manager.setLocal(name.lowercase())
        }
        assertNull(manager.authState.value.session)
        assertEquals(registryBeforeDuplicate, manager.savedLocalProfiles())

        manager.setLocal(saved.id, resumeExisting = true)
        assertEquals(name, (manager.authState.value.session as AccountSession.Local).displayName)
        assertEquals(saved, manager.savedLocalProfiles().single())
        SQLiteDatabase.openDatabase(
            databaseFile(logical).path,
            null,
            SQLiteDatabase.OPEN_READONLY
        ).use { database ->
            database.rawQuery("SELECT value FROM profile_sentinel", null).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("profile-data", cursor.getString(0))
            }
        }
    }

    @Test
    fun grandfatheredLocalAuthSessionRestoresOnlyWhenDatabaseIsRecoverable() {
        val displayName = "Grandfathered-${UUID.randomUUID()}"
        val legacy = checkNotNull(legacyLocalDatabaseName(displayName))
        databaseFile(legacy).writeText("legacy")
        context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE)
            .edit()
            .clear()
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
            .clear()
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

    private data class ActiveLocalProfile(
        val session: AccountSession.Local,
        val logical: String,
        val saved: SavedLocalProfile
    )

    private fun prepareActiveLocalProfile(prefix: String): ActiveLocalProfile {
        val name = "$prefix-${UUID.randomUUID().toString().take(8)}"
        val session = localSession(name)
        val logical = checkNotNull(localDatabaseLogicalName(name))
        val store = LocalDatabaseBindingStore(context)
        assertTrue(store.registerNewSession(session))
        databaseFile(logical).writeText("owned")
        assertTrue(store.finalizeMaterializedSession(session))
        val registry = LocalProfileRegistry(context)
        assertTrue(registry.ensurePresent(name))
        val saved = registry.list().single { it.displayName == name }
        assertTrue(
            context.getSharedPreferences("gym_cloud_auth", Context.MODE_PRIVATE).edit()
                .putString("mode", "local")
                .putString("local_name", name)
                .putString("local_profile_id", saved.id)
                .commit()
        )
        return ActiveLocalProfile(session, logical, saved)
    }

    private fun syntheticCloudSession() = AccountSession.Cloud(
        userId = "42345678-1234-4123-8123-123456789abc",
        email = "synthetic@example.invalid",
        displayName = "Synthetic",
        accessToken = "synthetic-token",
        refreshToken = null,
        sessionGeneration = "52345678-1234-4123-8123-123456789abc"
    )

    private fun syntheticLiveBinding(session: AccountSession.Cloud) = LiveWorkoutBinding(
        userId = session.userId,
        sessionGeneration = session.sessionGeneration,
        roomId = "lr_0123456789abcdef0123456789abcdef",
        role = "owner",
        peerProfileId = "p_0123456789abcdef0123456789abcdef",
        peerDisplayName = "Partner",
        roomRevision = 1,
        membershipRevision = 1,
        progressRevision = 1,
        workoutStartedAt = 1_786_330_800_000L,
        serverToLocalSetIds = mapOf(
            "s_01_01" to "32345678-1234-4123-8123-123456789abc"
        )
    )

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
