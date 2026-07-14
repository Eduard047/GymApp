package com.example.gymapp.data.entity

import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "wear_mutation_receipts",
    primaryKeys = ["ownerId", "accountGeneration", "operationId"],
    indices = [Index(value = ["createdAt"])]
)
data class WearMutationReceiptEntity(
    val ownerId: String,
    val accountGeneration: Long,
    val operationId: String,
    val sourceNodeId: String,
    val mutationType: String,
    val payloadDigest: String,
    val createdAt: Long
)
