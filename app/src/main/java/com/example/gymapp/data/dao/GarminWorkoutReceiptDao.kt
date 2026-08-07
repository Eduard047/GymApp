package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.gymapp.data.entity.GarminWorkoutProvenanceEntity
import com.example.gymapp.data.entity.GarminWorkoutReceiptEntity

@Dao
interface GarminWorkoutReceiptDao {
    @Query(
        """
        SELECT *
        FROM garmin_workout_receipts
        WHERE ownerBinding = :ownerBinding
            AND deviceBinding = :deviceBinding
            AND pairingGeneration = :pairingGeneration
            AND requestId = :requestId
        LIMIT 1
        """
    )
    suspend fun get(
        ownerBinding: String,
        deviceBinding: String,
        pairingGeneration: String,
        requestId: String
    ): GarminWorkoutReceiptEntity?

    @Query(
        """
        SELECT *
        FROM garmin_workout_receipts
        WHERE ownerBinding = :ownerBinding
            AND deviceBinding = :deviceBinding
            AND requestId = :requestId
        ORDER BY createdAt DESC
        LIMIT 1
        """
    )
    suspend fun getAcrossGenerations(
        ownerBinding: String,
        deviceBinding: String,
        requestId: String
    ): GarminWorkoutReceiptEntity?

    @Query(
        """
        UPDATE garmin_workout_receipts
        SET payloadDigest = :replacementDigest
        WHERE ownerBinding = :ownerBinding
            AND deviceBinding = :deviceBinding
            AND pairingGeneration = :pairingGeneration
            AND requestId = :requestId
            AND payloadDigest = :expectedLegacyDigest
        """
    )
    suspend fun upgradePayloadDigest(
        ownerBinding: String,
        deviceBinding: String,
        pairingGeneration: String,
        requestId: String,
        expectedLegacyDigest: String,
        replacementDigest: String
    ): Int

    @Query("SELECT COUNT(*) FROM garmin_workout_receipts")
    suspend fun count(): Int

    @Query("SELECT workoutSessionId FROM garmin_workout_provenance")
    suspend fun getProvenanceSessionIds(): List<Long>

    @Query(
        "SELECT * FROM garmin_workout_provenance " +
            "WHERE workoutSessionId = :workoutSessionId LIMIT 1"
    )
    suspend fun getProvenance(
        workoutSessionId: Long
    ): GarminWorkoutProvenanceEntity?

    @Query(
        """
        SELECT COUNT(*)
        FROM garmin_workout_receipts
        WHERE ownerBinding = :ownerBinding
            AND deviceBinding = :deviceBinding
            AND pairingGeneration = :pairingGeneration
        """
    )
    suspend fun countForPairingGeneration(
        ownerBinding: String,
        deviceBinding: String,
        pairingGeneration: String
    ): Int

    @Query(
        """
        SELECT COUNT(*)
        FROM garmin_workout_receipts
        WHERE ownerBinding = :ownerBinding
            AND deviceBinding = :deviceBinding
            AND pairingGeneration = :pairingGeneration
            AND createdAt >= :notBefore
        """
    )
    suspend fun countForPairingGenerationSince(
        ownerBinding: String,
        deviceBinding: String,
        pairingGeneration: String,
        notBefore: Long
    ): Int

    @Query(
        """
        DELETE FROM garmin_workout_receipts
        WHERE (pairingGeneration = :migratedLegacyGeneration
                OR pairingGeneration = :generationlessFallbackGeneration)
            AND createdAt < :expiresBefore
        """
    )
    suspend fun deleteExpiredLegacyReceipts(
        migratedLegacyGeneration: String,
        generationlessFallbackGeneration: String,
        expiresBefore: Long
    ): Int

    @Query(
        """
        DELETE FROM garmin_workout_receipts
        WHERE ownerBinding = :ownerBinding
            AND deviceBinding = :deviceBinding
            AND pairingGeneration != :activePairingGeneration
        """
    )
    suspend fun deleteOtherPairingGenerations(
        ownerBinding: String,
        deviceBinding: String,
        activePairingGeneration: String
    ): Int

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(receipt: GarminWorkoutReceiptEntity)

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertProvenance(provenance: GarminWorkoutProvenanceEntity)

}
