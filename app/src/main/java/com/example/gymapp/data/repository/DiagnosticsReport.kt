package com.example.gymapp.data.repository

import android.os.Build
import com.example.gymapp.BuildConfig
import java.util.Locale
import org.json.JSONObject

/**
 * Non-identifying environment facts for the diagnostics report. Mirrors the iPhone
 * `ExportService.DiagnosticsContext`: it can carry only versions, a locale tag, and three
 * cloud-sync booleans, never account ids, emails, or workout content.
 */
data class DiagnosticsContext(
    val version: String,
    val build: String,
    val operatingSystemVersion: String,
    val localeIdentifier: String,
    val cloudSyncEnabled: Boolean,
    val hasSuccessfulSync: Boolean,
    val hasError: Boolean
)

/** Collects the environment facts for [DiagnosticsContext] from the running app. */
fun currentDiagnosticsContext(
    cloudSyncEnabled: Boolean,
    hasSuccessfulSync: Boolean,
    hasError: Boolean
): DiagnosticsContext = DiagnosticsContext(
    version = BuildConfig.VERSION_NAME,
    build = BuildConfig.VERSION_CODE.toString(),
    operatingSystemVersion = "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
    localeIdentifier = Locale.getDefault().toLanguageTag(),
    cloudSyncEnabled = cloudSyncEnabled,
    hasSuccessfulSync = hasSuccessfulSync,
    hasError = hasError
)

/**
 * Builds the diagnostics JSON with the same allowlisted key layout as the iPhone report
 * (`schemaVersion`, `reportType`, `application`, `workoutData`, `cloudSync`) plus `exportedAt`.
 * Values come only from the typed arguments, so no free-form text can leak into the output.
 */
internal object DiagnosticsReportBuilder {
    fun build(
        exportedAtMillis: Long,
        context: DiagnosticsContext,
        exerciseCount: Int,
        workoutCount: Int,
        setCount: Int,
        manualMuscleMappingCount: Int
    ): JSONObject = JSONObject()
        .put("schemaVersion", 1)
        .put("reportType", "diagnostics")
        .put("exportedAt", exportedAtMillis)
        .put(
            "application",
            JSONObject()
                .put("version", context.version)
                .put("build", context.build)
                .put("operatingSystemVersion", context.operatingSystemVersion)
                .put("localeIdentifier", context.localeIdentifier)
        )
        .put(
            "workoutData",
            JSONObject()
                .put("exerciseCount", exerciseCount)
                .put("workoutCount", workoutCount)
                .put("setCount", setCount)
                .put("manualMuscleMappingCount", manualMuscleMappingCount)
        )
        .put(
            "cloudSync",
            JSONObject()
                .put("enabled", context.cloudSyncEnabled)
                .put("hasSuccessfulSync", context.hasSuccessfulSync)
                .put("hasError", context.hasError)
        )
}
