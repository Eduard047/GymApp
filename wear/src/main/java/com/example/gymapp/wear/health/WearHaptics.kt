package com.example.gymapp.wear.health

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

object WearHaptics {
    /** Three pulses, the last one longer: unmistakable on the wrist, short enough not to annoy. */
    private val REST_FINISHED = longArrayOf(0, 200, 120, 200, 120, 450)

    /**
     * Vibrates with the alarm usage: the rest timer usually ends with the screen off or the app
     * in the background, where a vibration without a usage is dropped by the system.
     */
    fun restFinished(context: Context) {
        runCatching {
            val vibrator = defaultVibrator(context)
            if (vibrator?.hasVibrator() != true) return
            val effect = VibrationEffect.createWaveform(REST_FINISHED, -1)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                vibrator.vibrate(
                    effect,
                    VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM)
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(
                    effect,
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
                )
            }
        }
    }

    private fun defaultVibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        }
}
