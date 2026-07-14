package com.example.gymapp.data.entity

import androidx.room.Entity

/**
 * Durable idempotency receipt for a workout received from a bound Connect IQ device.
 *
 * Receipts intentionally survive workout deletion and same-account logout/relogin so a queued
 * watch retry cannot recreate a workout that the user already handled or deleted.
 */
@Entity(
    tableName = "garmin_workout_receipts",
    primaryKeys = ["ownerBinding", "deviceBinding", "requestId"]
)
data class GarminWorkoutReceiptEntity(
    val ownerBinding: String,
    val deviceBinding: String,
    val requestId: String,
    val payloadDigest: String,
    val workoutSessionId: Long,
    val createdAt: Long
)
