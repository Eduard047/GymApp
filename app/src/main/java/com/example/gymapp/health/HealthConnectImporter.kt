package com.example.gymapp.health

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.activity.result.contract.ActivityResultContract
import androidx.annotation.RequiresApi
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.example.gymapp.data.repository.ActivityOnlyWorkoutItem
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.util.AppLanguage
import java.time.Instant

/** Whether Health Connect can be used on this device right now. */
enum class HealthConnectAvailability {
    AVAILABLE,
    PROVIDER_UPDATE_REQUIRED,
    UNAVAILABLE,
    UNSUPPORTED_OS
}

/**
 * Read-only import of gym-type workouts and their heart rate from Health Connect, stored as
 * activity-only workouts (see shared/health-import-v1.json). The app keeps minSdk 24: every
 * Health Connect class is reached only after [availability] confirmed API 26+ and an installed
 * provider, and the library manifest's minSdk is overridden in AndroidManifest.xml.
 *
 * Bind one instance to one account: [repository] must come from `repositoryFor(session)` and
 * [isAccountActive] must report whether that same account is still the active one. A run that
 * sees the account change stops writing and reports ABORTED_ACCOUNT_CHANGED.
 */
class HealthConnectImporter(
    context: Context,
    private val repository: GymRepository,
    private val language: () -> AppLanguage,
    private val isAccountActive: () -> Boolean,
    private val clock: () -> Long = System::currentTimeMillis
) {
    private val context: Context = context.applicationContext

    /**
     * Whether this account opted in to the import. Health Connect permission is per app, not per
     * account, so every account has to connect on its own; the default is off.
     */
    suspend fun isEnabled(): Boolean = repository.healthImportIsEnabled()

    /**
     * Connect = permissions granted (UI) + `setEnabled(true)`. Disconnect = `setEnabled(false)`;
     * revoking the Health Connect permission itself stays the UI's job.
     */
    suspend fun setEnabled(enabled: Boolean) = repository.healthImportSetEnabled(enabled)

    /** Workouts this account imported so far (later-deleted ones included). */
    suspend fun importedCount(): Int = repository.healthImportReceiptCount()

    /** Runs one import. Throws on Health Connect or database failures; the UI maps them to a message. */
    internal suspend fun run(trigger: HealthImportTrigger): HealthImportSummary {
        if (!isEnabled()) return HealthImportSummary(HealthImportStatus.NOT_ENABLED)
        when (availability(context)) {
            HealthConnectAvailability.UNSUPPORTED_OS ->
                return HealthImportSummary(HealthImportStatus.UNSUPPORTED_OS)
            HealthConnectAvailability.UNAVAILABLE ->
                return HealthImportSummary(HealthImportStatus.UNAVAILABLE)
            HealthConnectAvailability.PROVIDER_UPDATE_REQUIRED ->
                return HealthImportSummary(HealthImportStatus.PROVIDER_UPDATE_REQUIRED)
            HealthConnectAvailability.AVAILABLE -> Unit
        }
        // availability() already answers UNSUPPORTED_OS below API 26; this check repeats it where
        // the API-26 call is made.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return HealthImportSummary(HealthImportStatus.UNSUPPORTED_OS)
        }
        return runAvailable(trigger)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private suspend fun runAvailable(trigger: HealthImportTrigger): HealthImportSummary {
        val client = HealthConnectClient.getOrCreate(context)
        val granted = client.permissionController.getGrantedPermissions()
        if (EXERCISE_PERMISSION !in granted) {
            return HealthImportSummary(HealthImportStatus.NO_PERMISSION)
        }
        return HealthImportRunner(
            store = HealthImportStore.HEALTH_CONNECT,
            source = HealthConnectSessionSource(
                client = client,
                readHeartRate = HEART_RATE_PERMISSION in granted,
                readCalories = CALORIES_PERMISSION in granted
            ),
            persistence = RepositoryPersistence(repository),
            language = language,
            isAccountActive = isAccountActive,
            clock = clock
        ).run(trigger)
    }

    companion object {
        private const val EXERCISE_PERMISSION = "android.permission.health.READ_EXERCISE"
        private const val HEART_RATE_PERMISSION = "android.permission.health.READ_HEART_RATE"
        private const val CALORIES_PERMISSION = "android.permission.health.READ_TOTAL_CALORIES_BURNED"

        /** The permissions the import asks for; exercise is required, the others improve the data. */
        val REQUIRED_PERMISSIONS: Set<String> =
            setOf(EXERCISE_PERMISSION, HEART_RATE_PERMISSION, CALORIES_PERMISSION)

        fun availability(context: Context): HealthConnectAvailability {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                return HealthConnectAvailability.UNSUPPORTED_OS
            }
            return when (HealthConnectClient.getSdkStatus(context.applicationContext)) {
                HealthConnectClient.SDK_AVAILABLE -> HealthConnectAvailability.AVAILABLE
                HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED ->
                    HealthConnectAvailability.PROVIDER_UPDATE_REQUIRED
                else -> HealthConnectAvailability.UNAVAILABLE
            }
        }

        /**
         * Contract for ActivityResultLauncher: input [REQUIRED_PERMISSIONS], output the granted set.
         * Below API 26 it is an inert contract that never produces an intent worth launching and
         * always yields an empty set; callers must register and launch it only when [availability]
         * is [HealthConnectAvailability.AVAILABLE].
         */
        fun permissionRequestContract(): ActivityResultContract<Set<String>, Set<String>> =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                healthPermissionContract()
            } else {
                UnsupportedPermissionContract
            }

        @RequiresApi(Build.VERSION_CODES.O)
        private fun healthPermissionContract(): ActivityResultContract<Set<String>, Set<String>> =
            PermissionController.createRequestPermissionResultContract()

        /** True when the required exercise permission is granted; false when unavailable. */
        suspend fun hasExercisePermission(context: Context): Boolean {
            if (availability(context) != HealthConnectAvailability.AVAILABLE) return false
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
            return grantedPermissions(context).contains(EXERCISE_PERMISSION)
        }

        @RequiresApi(Build.VERSION_CODES.O)
        private suspend fun grantedPermissions(context: Context): Set<String> =
            HealthConnectClient.getOrCreate(context.applicationContext)
                .permissionController.getGrantedPermissions()

        /** Names of the contract exercise types that Health Connect reports as integers. */
        @RequiresApi(Build.VERSION_CODES.O)
        internal fun exerciseTypeName(type: Int): String? = when (type) {
            ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING -> "STRENGTH_TRAINING"
            ExerciseSessionRecord.EXERCISE_TYPE_WEIGHTLIFTING -> "WEIGHTLIFTING"
            ExerciseSessionRecord.EXERCISE_TYPE_CALISTHENICS -> "CALISTHENICS"
            ExerciseSessionRecord.EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING ->
                "HIGH_INTENSITY_INTERVAL_TRAINING"
            ExerciseSessionRecord.EXERCISE_TYPE_GYMNASTICS -> "GYMNASTICS"
            ExerciseSessionRecord.EXERCISE_TYPE_BOOT_CAMP -> "BOOT_CAMP"
            else -> null
        }
    }
}

/** Placeholder for API < 26, where no Health Connect class may be touched. */
private object UnsupportedPermissionContract : ActivityResultContract<Set<String>, Set<String>>() {
    override fun createIntent(context: Context, input: Set<String>): Intent = Intent()

    override fun parseResult(resultCode: Int, intent: Intent?): Set<String> = emptySet()
}

/** Adapts [GymRepository] to the runner's persistence interface. */
private class RepositoryPersistence(private val repository: GymRepository) : HealthImportPersistence {
    override suspend fun existingWorkouts(fromMillis: Long) =
        repository.healthImportExistingWorkouts(fromMillis)

    override suspend fun knownReceipts(keys: Collection<String>) =
        repository.healthImportKnownReceipts(keys)

    override suspend fun persist(item: ActivityOnlyWorkoutItem, receiptKey: String) =
        repository.importHealthActivity(item, receiptKey)

    override suspend fun isEnabled() = repository.healthImportIsEnabled()

    override suspend fun lastImportAt() = repository.healthImportLastImportAt()

    override suspend fun setLastImportAt(millis: Long) = repository.healthImportSetLastImportAt(millis)
}

@RequiresApi(Build.VERSION_CODES.O)
private class HealthConnectSessionSource(
    private val client: HealthConnectClient,
    private val readHeartRate: Boolean,
    private val readCalories: Boolean
) : HealthSessionSource {
    /** Heart-rate samples read so far in this run; one source instance serves exactly one run. */
    private var heartRateSamplesRead = 0

    override suspend fun listSessions(
        fromMillis: Long,
        toMillis: Long,
        maxRecords: Int
    ): HealthSessionListing {
        val sessions = ArrayList<HealthImportSession>()
        var scanned = 0
        var truncated = false
        var pageToken: String? = null
        do {
            val response = client.readRecords(
                ReadRecordsRequest(
                    recordType = ExerciseSessionRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(
                        Instant.ofEpochMilli(fromMillis),
                        Instant.ofEpochMilli(toMillis)
                    ),
                    ascendingOrder = false,
                    pageSize = PAGE_SIZE,
                    pageToken = pageToken
                )
            )
            for (record in response.records) {
                if (scanned >= maxRecords) {
                    truncated = true
                    break
                }
                scanned++
                val start = record.startTime.toEpochMilli()
                if (start < fromMillis) continue
                sessions += HealthImportSession(
                    recordId = record.metadata.id,
                    startMillis = start,
                    endMillis = record.endTime.toEpochMilli(),
                    exerciseType = HealthConnectImporter.exerciseTypeName(record.exerciseType),
                    sourceId = record.metadata.dataOrigin.packageName
                )
            }
            pageToken = response.pageToken.takeUnless { it.isNullOrEmpty() }
        } while (pageToken != null && !truncated)
        if (pageToken != null) truncated = true
        return HealthSessionListing(sessions, truncated)
    }

    override suspend fun loadDetails(session: HealthImportSession): HealthImportSession {
        // Only data written by the app that recorded the session: an empty origin filter would
        // mean "every app", and mixing sources could attribute another app's data to this workout.
        val origin = session.sourceId?.takeIf { it.isNotBlank() }?.let { setOf(DataOrigin(it)) }
            ?: return session
        val range = TimeRangeFilter.between(
            Instant.ofEpochMilli(session.startMillis),
            Instant.ofEpochMilli(session.endMillis)
        )
        val samples = if (readHeartRate) readHeartRateSamples(range, origin) else emptyList()
        val kilocalories = if (readCalories) aggregateKilocalories(range, origin) else null
        return session.copy(
            kilocalories = kilocalories,
            heartRateSamples = samples.orEmpty(),
            heartRateComplete = samples != null
        )
    }

    /**
     * Reads the session's heart-rate samples within the per-run budget. Returns null when the
     * series could not be read in full: a session that would cross the budget (and every later
     * session of the run) or one with more pages than [MAX_HEART_RATE_PAGES] gets no heart rate,
     * because an average of a truncated series would be misleading.
     */
    private suspend fun readHeartRateSamples(
        range: TimeRangeFilter,
        origin: Set<DataOrigin>
    ): List<HeartRateSample>? {
        val budget = HealthImportRules.MAX_HEART_RATE_SAMPLES_PER_RUN
        if (heartRateSamplesRead >= budget) return null
        val samples = ArrayList<HeartRateSample>()
        var pageToken: String? = null
        var pages = 0
        do {
            val response = client.readRecords(
                ReadRecordsRequest(
                    recordType = HeartRateRecord::class,
                    timeRangeFilter = range,
                    dataOriginFilter = origin,
                    pageSize = HEART_RATE_PAGE_SIZE,
                    pageToken = pageToken
                )
            )
            for (record in response.records) {
                heartRateSamplesRead += record.samples.size
                if (heartRateSamplesRead > budget) {
                    heartRateSamplesRead = budget
                    return null
                }
                for (sample in record.samples) {
                    samples += HeartRateSample(sample.time.toEpochMilli(), sample.beatsPerMinute)
                }
            }
            pageToken = response.pageToken.takeUnless { it.isNullOrEmpty() }
            pages++
        } while (pageToken != null && pages < MAX_HEART_RATE_PAGES)
        // More pages than allowed: the series is incomplete.
        return if (pageToken != null) null else samples
    }

    /**
     * Total energy (active + basal) the source app recorded for the session. iPhone imports
     * active energy; Android would need READ_ACTIVE_CALORIES_BURNED for that, which the app
     * does not declare, so Android stays on total energy (see shared/health-import-v1.json).
     */
    private suspend fun aggregateKilocalories(
        range: TimeRangeFilter,
        origin: Set<DataOrigin>
    ): Double? {
        val result = client.aggregate(
            AggregateRequest(
                metrics = setOf(TotalCaloriesBurnedRecord.ENERGY_TOTAL),
                timeRangeFilter = range,
                dataOriginFilter = origin
            )
        )
        return result[TotalCaloriesBurnedRecord.ENERGY_TOTAL]?.inKilocalories
    }

    private companion object {
        const val PAGE_SIZE = 100
        const val HEART_RATE_PAGE_SIZE = 1_000
        const val MAX_HEART_RATE_PAGES = 20
    }
}
