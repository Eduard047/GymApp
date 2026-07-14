package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.gymapp.data.entity.WearMutationReceiptEntity

@Dao
interface WearMutationDao {
    @Query(
        """
        SELECT *
        FROM wear_mutation_receipts
        WHERE ownerId = :ownerId
            AND accountGeneration = :accountGeneration
            AND operationId = :operationId
        LIMIT 1
        """
    )
    suspend fun get(
        ownerId: String,
        accountGeneration: Long,
        operationId: String
    ): WearMutationReceiptEntity?

    @Query(
        """
        SELECT COUNT(*)
        FROM wear_mutation_receipts
        WHERE ownerId = :ownerId AND accountGeneration = :accountGeneration
        """
    )
    suspend fun count(ownerId: String, accountGeneration: Long): Int

    @Query(
        """
        DELETE FROM wear_mutation_receipts
        WHERE ownerId != :ownerId OR accountGeneration != :accountGeneration
        """
    )
    suspend fun deleteObsoleteGenerations(ownerId: String, accountGeneration: Long)

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(receipt: WearMutationReceiptEntity)
}
