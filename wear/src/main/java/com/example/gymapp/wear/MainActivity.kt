package com.example.gymapp.wear

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.InputDevice
import android.view.MotionEvent
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.ambient.AmbientModeSupport
import com.example.gymapp.wear.ui.WearWorkoutApp
import com.example.gymapp.wear.ui.WearWorkoutViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlin.math.abs

private val WearDarkColorScheme = darkColorScheme(
    primary = Color(0xFF9AB3FF),
    onPrimary = Color(0xFF0B1121),
    secondary = Color(0xFFB9C7FF),
    onSecondary = Color(0xFF12192A),
    background = Color(0xFF05070B),
    onBackground = Color(0xFFE7EBF5),
    surface = Color(0xFF0F141D),
    onSurface = Color(0xFFE7EBF5),
    surfaceVariant = Color(0xFF1A202B),
    onSurfaceVariant = Color(0xFFBEC6D6),
    outlineVariant = Color(0xFF2B3444)
)

class MainActivity : FragmentActivity(), AmbientModeSupport.AmbientCallbackProvider {
    private val rotaryEvents = MutableSharedFlow<Float>(extraBufferCapacity = 64)
    private var lastHapticAtMs: Long = 0L
    private var isAmbient by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AmbientModeSupport.attach(this)

        setContent {
            val workoutViewModel: WearWorkoutViewModel = viewModel(
                factory = WearWorkoutViewModel.factory(application)
            )

            MaterialTheme(colorScheme = WearDarkColorScheme) {
                Surface(color = MaterialTheme.colorScheme.background) {
                    WearWorkoutApp(
                        viewModel = workoutViewModel,
                        rotaryEvents = rotaryEvents,
                        isAmbient = isAmbient
                    )
                }
            }
        }
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (isAmbient) {
            return super.onGenericMotionEvent(event)
        }

        val isRotarySource =
            (event.source and InputDevice.SOURCE_ROTARY_ENCODER) == InputDevice.SOURCE_ROTARY_ENCODER
        if (isRotarySource && event.action == MotionEvent.ACTION_SCROLL) {
            var delta = event.getAxisValue(MotionEvent.AXIS_SCROLL)
            if (abs(delta) < 0.0001f) {
                delta = event.getAxisValue(MotionEvent.AXIS_VSCROLL)
            }
            if (abs(delta) >= 0.0001f) {
                rotaryEvents.tryEmit(delta)
                performBezelHapticThrottled()
                return true
            }
        }
        return super.onGenericMotionEvent(event)
    }

    private fun performBezelHapticThrottled() {
        val now = System.currentTimeMillis()
        if (now - lastHapticAtMs < 20L) return
        lastHapticAtMs = now
        performBezelHaptic()
    }

    private fun performBezelHaptic() {
        window.decorView.performHapticFeedback(
            HapticFeedbackConstants.CLOCK_TICK,
            HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING
        )

        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

        if (vibrator?.hasVibrator() != true) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(12, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(12)
        }
    }

    override fun getAmbientCallback(): AmbientModeSupport.AmbientCallback {
        return object : AmbientModeSupport.AmbientCallback() {
            override fun onEnterAmbient(ambientDetails: Bundle?) {
                isAmbient = true
            }

            override fun onExitAmbient() {
                isAmbient = false
            }
        }
    }
}
