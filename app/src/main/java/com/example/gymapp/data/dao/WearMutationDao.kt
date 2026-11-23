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
        WHERE ownerId = :ownerId AND operationId = :operationId
        LIMIT 1
        """
    )
    suspend fun get(ownerId: String, operationId: String): WearMutationReceiptEntity?

    @Query("SELECT COUNT(*) FROM wear_mutation_receipts WHERE ownerId = :ownerId")
    suspend fun count(ownerId: String): Int

    @Query(
        """
        SELECT COUNT(*)
        FROM wear_mutation_receipts
        WHERE ownerId = :ownerId AND mutationType = :mutationType AND createdAt >= :since
        """
    )
    suspend fun countSince(ownerId: String, mutationType: String, since: Long): Int

    @Query("DELETE FROM wear_mutation_receipts WHERE createdAt < :cutoff")
    suspend fun deleteOlderThan(cutoff: Long)

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(receipt: WearMutationReceiptEntity)
}
