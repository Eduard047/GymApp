package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.gymapp.data.entity.GarminWorkoutReceiptEntity

@Dao
interface GarminWorkoutReceiptDao {
    @Query(
        """
        SELECT *
        FROM garmin_workout_receipts
        WHERE ownerBinding = :ownerBinding
            AND deviceBinding = :deviceBinding
            AND requestId = :requestId
        LIMIT 1
        """
    )
    suspend fun get(
        ownerBinding: String,
        deviceBinding: String,
        requestId: String
    ): GarminWorkoutReceiptEntity?

    @Query("SELECT COUNT(*) FROM garmin_workout_receipts")
    suspend fun count(): Int

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(receipt: GarminWorkoutReceiptEntity)
}
