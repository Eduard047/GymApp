package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.entity.GarminWorkoutProvenanceEntity
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ConditionalDeletionTest {
    @Test
    fun setDeletionSnapshotUsesCurrentVisibleOrdinalAfterAnEarlierSetIsDeleted() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "conditional-set-ordinal-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            val exerciseId = repository.addExercise("Conditional set ordinal")
            val sessionId = repository.createWorkoutSession(
                date = System.currentTimeMillis(),
                note = null,
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = exerciseId,
                        sets = listOf(
                            WorkoutSetDraft(weight = 40.0, reps = 10),
                            WorkoutSetDraft(weight = 42.5, reps = 8),
                            WorkoutSetDraft(weight = 45.0, reps = 6)
                        )
                    )
                )
            )
            val originalSets = checkNotNull(
                database.workoutDao().getSessionDetailsSnapshot(sessionId)
            ).workoutExercises.single().sets.sortedBy { it.orderIndex }

            repository.deleteSetById(originalSets[1].id)

            val snapshot = checkNotNull(repository.getSetDeletionSnapshot(originalSets[2].id))
            assertEquals(2, snapshot.orderIndex)
            assertEquals(2, snapshot.displayOrdinal)
            assertEquals(2, snapshot.setsInExerciseBlock)
            assertTrue(repository.deleteSetIfUnchanged(snapshot))
            assertNull(database.setDao().getById(originalSets[2].id))
            assertNotNull(database.setDao().getById(originalSets[0].id))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun exerciseDeletionFailsClosedWhenIdentityOrCascadeImpactChanges() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "conditional-exercise-delete-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            val exerciseId = repository.addExercise("Conditional exercise")
            val sessionId = repository.createWorkoutSession(
                date = System.currentTimeMillis(),
                note = "synthetic conditional deletion test",
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = exerciseId,
                        sets = listOf(WorkoutSetDraft(weight = 50.0, reps = 8))
                    )
                )
            )
            val original = checkNotNull(repository.getExerciseDeletionSnapshot(exerciseId))
            assertEquals(1, original.workoutCount)
            assertEquals(1, original.exerciseBlockCount)
            assertEquals(1, original.setCount)

            val originalDetails = checkNotNull(
                database.workoutDao().getSessionDetailsSnapshot(sessionId)
            )
            var originalBlock = originalDetails.workoutExercises.single()
            var originalSet = originalBlock.sets.single()

            repository.updateSet(originalSet.copy(weight = 51.0))
            assertFalse(repository.deleteExerciseIfUnchanged(original))
            assertNotNull(database.exerciseDao().getById(exerciseId))

            var beforeMutableCascadeChange = checkNotNull(
                repository.getExerciseDeletionSnapshot(exerciseId)
            )
            originalSet = checkNotNull(database.setDao().getById(originalSet.id))
            repository.updateSet(originalSet.copy(reps = 9))
            assertFalse(repository.deleteExerciseIfUnchanged(beforeMutableCascadeChange))

            beforeMutableCascadeChange = checkNotNull(
                repository.getExerciseDeletionSnapshot(exerciseId)
            )
            originalSet = checkNotNull(database.setDao().getById(originalSet.id))
            repository.updateSet(originalSet.copy(orderIndex = 1))
            assertFalse(repository.deleteExerciseIfUnchanged(beforeMutableCascadeChange))

            beforeMutableCascadeChange = checkNotNull(
                repository.getExerciseDeletionSnapshot(exerciseId)
            )
            originalBlock = checkNotNull(
                database.workoutDao().getSessionDetailsSnapshot(sessionId)
            ).workoutExercises.single()
            database.workoutDao().updateWorkoutExercise(
                originalBlock.workoutExercise.copy(orderIndex = 1)
            )
            assertFalse(repository.deleteExerciseIfUnchanged(beforeMutableCascadeChange))
            assertNotNull(database.setDao().getById(originalSet.id))

            repository.deleteSetById(originalSet.id)
            assertNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
            val replacementSessionId = repository.createWorkoutSession(
                date = System.currentTimeMillis(),
                note = "same counts, different cascade targets",
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = exerciseId,
                        sets = listOf(WorkoutSetDraft(weight = 50.0, reps = 8))
                    )
                )
            )
            val replacementWorkoutExerciseId = checkNotNull(
                database.workoutDao().getSessionDetailsSnapshot(replacementSessionId)
                    ?.workoutExercises
                    ?.single()
                    ?.workoutExercise
                    ?.id
            )
            val sameCountReplacement = checkNotNull(
                repository.getExerciseDeletionSnapshot(exerciseId)
            )
            assertEquals(original.workoutCount, sameCountReplacement.workoutCount)
            assertEquals(original.exerciseBlockCount, sameCountReplacement.exerciseBlockCount)
            assertEquals(original.setCount, sameCountReplacement.setCount)
            assertFalse(original.cascadeFingerprint == sameCountReplacement.cascadeFingerprint)

            assertFalse(repository.deleteExerciseIfUnchanged(original))
            assertNotNull(database.exerciseDao().getById(exerciseId))
            assertEquals(1, database.setDao().getTotalSetCount())

            repository.addSet(replacementWorkoutExerciseId, weight = 52.5, reps = 6)
            assertFalse(repository.deleteExerciseIfUnchanged(sameCountReplacement))
            assertEquals(2, database.setDao().getTotalSetCount())

            val beforeRename = checkNotNull(repository.getExerciseDeletionSnapshot(exerciseId))
            val exercise = checkNotNull(database.exerciseDao().getById(exerciseId))
            repository.renameExercise(exercise, "Renamed conditional exercise")

            assertFalse(repository.deleteExerciseIfUnchanged(beforeRename))
            assertNotNull(database.exerciseDao().getById(exerciseId))

            val current = checkNotNull(repository.getExerciseDeletionSnapshot(exerciseId))
            assertTrue(repository.deleteExerciseIfUnchanged(current))
            assertNull(database.exerciseDao().getById(exerciseId))
            assertEquals(0, database.setDao().getTotalSetCount())
            assertEquals(
                0,
                database.workoutDao().getSessionDetailsSnapshot(replacementSessionId)
                    ?.workoutExercises
                    ?.size
            )
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun setDeletionFailsClosedAndReportsActualCleanupImpact() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "conditional-set-delete-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            val firstExerciseId = repository.addExercise("Conditional set A")
            val secondExerciseId = repository.addExercise("Conditional set B")

            val singleBlockSessionId = repository.createWorkoutSession(
                date = System.currentTimeMillis(),
                note = null,
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = firstExerciseId,
                        sets = listOf(WorkoutSetDraft(weight = 40.0, reps = 10))
                    )
                )
            )
            val singleBlockDetails = checkNotNull(
                database.workoutDao().getSessionDetailsSnapshot(singleBlockSessionId)
            )
            val singleBlock = singleBlockDetails.workoutExercises.single()
            val originalSet = singleBlock.sets.single()
            val original = checkNotNull(repository.getSetDeletionSnapshot(originalSet.id))
            assertEquals(SetDeletionImpact.WorkoutSession, original.impact)
            assertEquals(singleBlock.workoutExercise, original.removedWorkoutExercise)
            assertEquals(singleBlockDetails.session, original.removedWorkoutSession)
            assertNull(original.removedGarminProvenance)

            repository.updateWorkoutSession(
                singleBlockDetails.session.copy(note = "changed after delete confirmation")
            )
            assertFalse(repository.deleteSetIfUnchanged(original))
            assertNotNull(database.setDao().getById(originalSet.id))

            var beforeRemovedParentChange = checkNotNull(
                repository.getSetDeletionSnapshot(originalSet.id)
            )
            database.workoutDao().updateWorkoutExercise(
                singleBlock.workoutExercise.copy(orderIndex = 1)
            )
            assertFalse(repository.deleteSetIfUnchanged(beforeRemovedParentChange))
            assertNotNull(database.setDao().getById(originalSet.id))

            beforeRemovedParentChange = checkNotNull(
                repository.getSetDeletionSnapshot(originalSet.id)
            )
            database.garminWorkoutReceiptDao().insertProvenance(
                GarminWorkoutProvenanceEntity(workoutSessionId = singleBlockSessionId)
            )
            assertFalse(repository.deleteSetIfUnchanged(beforeRemovedParentChange))
            assertNotNull(database.setDao().getById(originalSet.id))

            val beforeSetChange = checkNotNull(
                repository.getSetDeletionSnapshot(originalSet.id)
            )
            assertEquals(
                GarminWorkoutProvenanceEntity(workoutSessionId = singleBlockSessionId),
                beforeSetChange.removedGarminProvenance
            )
            repository.updateSet(originalSet.copy(weight = 42.5))

            assertFalse(repository.deleteSetIfUnchanged(beforeSetChange))
            assertNotNull(database.setDao().getById(originalSet.id))
            assertNotNull(database.workoutDao().getSessionDetailsSnapshot(singleBlockSessionId))

            val beforeImpactChange = checkNotNull(repository.getSetDeletionSnapshot(originalSet.id))
            val addedSetId = repository.addSet(
                workoutExerciseId = singleBlock.workoutExercise.id,
                weight = 45.0,
                reps = 6
            )

            assertFalse(repository.deleteSetIfUnchanged(beforeImpactChange))
            assertNotNull(database.setDao().getById(originalSet.id))
            assertNotNull(database.setDao().getById(addedSetId))

            val addedSetSnapshot = checkNotNull(repository.getSetDeletionSnapshot(addedSetId))
            assertEquals(SetDeletionImpact.SetOnly, addedSetSnapshot.impact)
            assertNull(addedSetSnapshot.removedWorkoutExercise)
            assertNull(addedSetSnapshot.removedWorkoutSession)
            assertNull(addedSetSnapshot.removedGarminProvenance)
            val survivingDetails = checkNotNull(
                database.workoutDao().getSessionDetailsSnapshot(singleBlockSessionId)
            )
            database.workoutDao().updateWorkoutExercise(
                survivingDetails.workoutExercises.single().workoutExercise.copy(orderIndex = 2)
            )
            repository.updateWorkoutSession(
                survivingDetails.session.copy(note = "surviving parent changed")
            )
            assertTrue(repository.deleteSetIfUnchanged(addedSetSnapshot))
            assertNotNull(database.workoutDao().getSessionDetailsSnapshot(singleBlockSessionId))

            val lastSetSnapshot = checkNotNull(repository.getSetDeletionSnapshot(originalSet.id))
            assertEquals(SetDeletionImpact.WorkoutSession, lastSetSnapshot.impact)
            assertTrue(repository.deleteSetIfUnchanged(lastSetSnapshot))
            assertNull(database.workoutDao().getSessionDetailsSnapshot(singleBlockSessionId))

            val twoBlockSessionId = repository.createWorkoutSession(
                date = System.currentTimeMillis(),
                note = null,
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = firstExerciseId,
                        sets = listOf(WorkoutSetDraft(weight = 30.0, reps = 12))
                    ),
                    WorkoutExerciseDraft(
                        exerciseId = secondExerciseId,
                        sets = listOf(WorkoutSetDraft(weight = 20.0, reps = 15))
                    )
                )
            )
            val twoBlockDetails = checkNotNull(
                database.workoutDao().getSessionDetailsSnapshot(twoBlockSessionId)
            )
            val firstBlock = twoBlockDetails.workoutExercises
                .single { it.exercise.id == firstExerciseId }
            val exerciseBlockSnapshot = checkNotNull(
                repository.getSetDeletionSnapshot(firstBlock.sets.single().id)
            )
            assertEquals(SetDeletionImpact.ExerciseBlock, exerciseBlockSnapshot.impact)
            assertEquals(firstBlock.workoutExercise, exerciseBlockSnapshot.removedWorkoutExercise)
            assertNull(exerciseBlockSnapshot.removedWorkoutSession)
            assertNull(exerciseBlockSnapshot.removedGarminProvenance)

            database.workoutDao().updateWorkoutExercise(
                firstBlock.workoutExercise.copy(orderIndex = 2)
            )
            assertFalse(repository.deleteSetIfUnchanged(exerciseBlockSnapshot))
            assertNotNull(database.setDao().getById(firstBlock.sets.single().id))

            val currentExerciseBlockSnapshot = checkNotNull(
                repository.getSetDeletionSnapshot(firstBlock.sets.single().id)
            )
            repository.updateWorkoutSession(
                twoBlockDetails.session.copy(note = "surviving workout changed")
            )
            database.garminWorkoutReceiptDao().insertProvenance(
                GarminWorkoutProvenanceEntity(workoutSessionId = twoBlockSessionId)
            )
            assertTrue(repository.deleteSetIfUnchanged(currentExerciseBlockSnapshot))
            val retainedSession = checkNotNull(
                database.workoutDao().getSessionDetailsSnapshot(twoBlockSessionId)
            )
            assertEquals(1, retainedSession.workoutExercises.size)
            assertEquals(secondExerciseId, retainedSession.workoutExercises.single().exercise.id)
            assertEquals("surviving workout changed", retainedSession.session.note)
            assertNotNull(
                database.garminWorkoutReceiptDao().getProvenance(twoBlockSessionId)
            )
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun deletionSnapshotsCannotCrossRepositoryOrStoreBoundaries() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val firstDatabaseName = "conditional-store-a-${UUID.randomUUID()}"
        val secondDatabaseName = "conditional-store-b-${UUID.randomUUID()}"
        val firstDatabase = GymDatabase.getInstance(context, firstDatabaseName)
        val secondDatabase = GymDatabase.getInstance(context, secondDatabaseName)

        try {
            val firstRepository = GymRepository(firstDatabase)
            val secondRepository = GymRepository(secondDatabase)
            val secondRepositoryForSameStore = GymRepository(firstDatabase)
            val sessionDate = System.currentTimeMillis()

            val firstExerciseId = firstRepository.addExercise("Store-bound deletion")
            val secondExerciseId = secondRepository.addExercise("Store-bound deletion")
            assertEquals(firstExerciseId, secondExerciseId)

            val firstSessionId = firstRepository.createWorkoutSession(
                date = sessionDate,
                note = "same synthetic content",
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = firstExerciseId,
                        sets = listOf(WorkoutSetDraft(weight = 72.5, reps = 7))
                    )
                )
            )
            val secondSessionId = secondRepository.createWorkoutSession(
                date = sessionDate,
                note = "same synthetic content",
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = secondExerciseId,
                        sets = listOf(WorkoutSetDraft(weight = 72.5, reps = 7))
                    )
                )
            )
            assertEquals(firstSessionId, secondSessionId)

            val firstExerciseSnapshot = checkNotNull(
                firstRepository.getExerciseDeletionSnapshot(firstExerciseId)
            )
            val secondExerciseSnapshot = checkNotNull(
                secondRepository.getExerciseDeletionSnapshot(secondExerciseId)
            )
            assertEquals(
                secondExerciseSnapshot,
                firstExerciseSnapshot.copy(
                    deletionStoreToken = secondExerciseSnapshot.deletionStoreToken
                )
            )
            assertFalse(
                secondRepositoryForSameStore.deleteExerciseIfUnchanged(firstExerciseSnapshot)
            )
            assertFalse(secondRepository.deleteExerciseIfUnchanged(firstExerciseSnapshot))
            assertNotNull(firstDatabase.exerciseDao().getById(firstExerciseId))
            assertNotNull(secondDatabase.exerciseDao().getById(secondExerciseId))

            val firstSetId = checkNotNull(
                firstDatabase.workoutDao().getSessionDetailsSnapshot(firstSessionId)
            ).workoutExercises.single().sets.single().id
            val secondSetId = checkNotNull(
                secondDatabase.workoutDao().getSessionDetailsSnapshot(secondSessionId)
            ).workoutExercises.single().sets.single().id
            assertEquals(firstSetId, secondSetId)

            val firstSetSnapshot = checkNotNull(
                firstRepository.getSetDeletionSnapshot(firstSetId)
            )
            val secondSetSnapshot = checkNotNull(
                secondRepository.getSetDeletionSnapshot(secondSetId)
            )
            assertEquals(
                secondSetSnapshot,
                firstSetSnapshot.copy(
                    deletionStoreToken = secondSetSnapshot.deletionStoreToken
                )
            )
            assertFalse(secondRepositoryForSameStore.deleteSetIfUnchanged(firstSetSnapshot))
            assertFalse(secondRepository.deleteSetIfUnchanged(firstSetSnapshot))
            assertNotNull(firstDatabase.setDao().getById(firstSetId))
            assertNotNull(secondDatabase.setDao().getById(secondSetId))
        } finally {
            firstDatabase.close()
            secondDatabase.close()
            context.deleteDatabase(firstDatabaseName)
            context.deleteDatabase(secondDatabaseName)
        }
    }
}
