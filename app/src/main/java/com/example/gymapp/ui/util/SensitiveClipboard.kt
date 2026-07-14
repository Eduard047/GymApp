package com.example.gymapp.ui.util

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import com.example.gymapp.data.repository.WorkoutDataLimits
import java.security.MessageDigest
import java.util.UUID

internal object SensitiveClipboard {
    internal const val BACKUP_CLEAR_DELAY_MILLIS = 60_000L
    internal const val MAX_CLIPBOARD_BACKUP_BYTES = 256 * 1_024
    private const val SENSITIVE_CLIP_KEY = "android.content.extra.IS_SENSITIVE"
    private const val BACKUP_CLIP_PREFIX = "GymApp private backup:"

    fun copyBackup(context: Context, value: String): Boolean {
        if (!canCopyBackup(value)) return false
        val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return false
        val marker = "$BACKUP_CLIP_PREFIX${UUID.randomUUID()}"
        val expectedLength = value.length
        val expectedDigest = digest(value)
        val clip = ClipData.newPlainText(marker, value).apply {
            description.extras = PersistableBundle().apply {
                putBoolean(SENSITIVE_CLIP_KEY, true)
            }
        }

        try {
            clipboard.setPrimaryClip(clip)
        } catch (_: RuntimeException) {
            // Binder and clipboard-service failures must not crash the export surface.
            return false
        }
        Handler(Looper.getMainLooper()).postDelayed(
            {
                val current = try {
                    clipboard.primaryClip
                } catch (_: RuntimeException) {
                    null
                }
                if (
                    current != null &&
                    matchesBackupClip(
                        expectedMarker = marker,
                        expectedLength = expectedLength,
                        expectedDigest = expectedDigest,
                        currentMarker = current.description.label?.toString(),
                        currentItemCount = current.itemCount,
                        currentValue = current.takeIf { it.itemCount == 1 }
                            ?.getItemAt(0)
                            ?.text
                            ?.toString()
                    )
                ) {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            clipboard.clearPrimaryClip()
                        } else {
                            clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
                        }
                    } catch (_: RuntimeException) {
                        // Clipboard access can be revoked when the app moves to the background.
                    }
                }
            },
            BACKUP_CLEAR_DELAY_MILLIS
        )
        return true
    }

    internal fun canCopyBackup(value: String): Boolean =
        value.length <= MAX_CLIPBOARD_BACKUP_BYTES &&
            WorkoutDataLimits.utf8ByteLengthAtMost(
                value,
                MAX_CLIPBOARD_BACKUP_BYTES
            ) != null

    internal fun matchesBackupClip(
        expectedMarker: String,
        expectedLength: Int,
        expectedDigest: ByteArray,
        currentMarker: String?,
        currentItemCount: Int,
        currentValue: String?
    ): Boolean {
        if (
            currentMarker != expectedMarker ||
            currentItemCount != 1 ||
            currentValue == null ||
            currentValue.length != expectedLength
        ) {
            return false
        }
        return MessageDigest.isEqual(expectedDigest, digest(currentValue))
    }

    internal fun digest(value: String): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
}
