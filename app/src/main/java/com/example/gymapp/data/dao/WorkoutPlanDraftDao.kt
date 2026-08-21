package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.gymapp.data.entity.WorkoutPlanDraftEntity

@Dao
interface WorkoutPlanDraftDao {
    @Query("SELECT * FROM workout_plan_draft WHERE id = 1 LIMIT 1")
    suspend fun get(): WorkoutPlanDraftEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun save(draft: WorkoutPlanDraftEntity)

    @Query("DELETE FROM workout_plan_draft WHERE id = 1")
    suspend fun clear()
}
