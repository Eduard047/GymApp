package com.example.gymapp.push

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.example.gymapp.gymApplication
import java.util.concurrent.TimeUnit

class PushReconciliationWorker(
    applicationContext: Context,
    parameters: WorkerParameters
) : CoroutineWorker(applicationContext, parameters) {
    override suspend fun doWork(): Result = if (
        applicationContext.gymApplication.pushManager.reconcileFromWorker()
    ) {
        Result.success()
    } else {
        Result.retry()
    }
}

internal class PushWorkScheduler(context: Context) {
    private val applicationContext = context.applicationContext

    fun enqueue(replace: Boolean, awaitPersistence: Boolean = false): Boolean = runCatching {
        val operation = WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            PUSH_RECONCILIATION_WORK_NAME,
            if (replace) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP,
            pushReconciliationWorkRequest()
        )
        if (awaitPersistence) {
            // FirebaseMessagingService has a short worker-thread callback window. Waiting only
            // for WorkManager's local DB transaction makes the handoff durable before return.
            operation.result.get(PUSH_WORK_ENQUEUE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        }
        true
    }.getOrDefault(false)
}

internal data class PushWorkConfiguration(
    val requiredNetworkType: NetworkType,
    val backoffPolicy: BackoffPolicy,
    val backoffSeconds: Long,
    val containsPrivateInputData: Boolean
)

internal val PUSH_WORK_CONFIGURATION = PushWorkConfiguration(
    requiredNetworkType = NetworkType.CONNECTED,
    backoffPolicy = BackoffPolicy.EXPONENTIAL,
    backoffSeconds = PUSH_WORK_BACKOFF_SECONDS,
    containsPrivateInputData = false
)

internal fun pushReconciliationWorkRequest(): OneTimeWorkRequest =
    OneTimeWorkRequest.Builder(PushReconciliationWorker::class.java)
        .setConstraints(
            Constraints.Builder()
                .setRequiredNetworkType(PUSH_WORK_CONFIGURATION.requiredNetworkType)
                .build()
        )
        .setBackoffCriteria(
            PUSH_WORK_CONFIGURATION.backoffPolicy,
            PUSH_WORK_CONFIGURATION.backoffSeconds,
            TimeUnit.SECONDS
        )
        .addTag(PUSH_RECONCILIATION_WORK_TAG)
        .build()

internal const val PUSH_RECONCILIATION_WORK_NAME = "gymapp-push-reconciliation-v1"
internal const val PUSH_RECONCILIATION_WORK_TAG = "gymapp-push-reconciliation"
private const val PUSH_WORK_BACKOFF_SECONDS = 30L
private const val PUSH_WORK_ENQUEUE_TIMEOUT_SECONDS = 5L
