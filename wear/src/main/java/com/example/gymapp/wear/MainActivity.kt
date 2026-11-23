package com.example.gymapp.wear

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.ambient.AmbientModeSupport
import com.example.gymapp.wear.ui.WearWorkoutApp
import com.example.gymapp.wear.ui.WearWorkoutViewModel
import kotlinx.coroutines.launch

class MainActivity : FragmentActivity(), AmbientModeSupport.AmbientCallbackProvider {
    private var isAmbient by mutableStateOf(false)

    // Asked when a workout starts; either answer just tells the ViewModel to carry on, with or
    // without heart rate.
    private val healthPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            ViewModelProvider(this, WearWorkoutViewModel.factory(application))[WearWorkoutViewModel::class.java]
                .onHealthPermissionsResult()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AmbientModeSupport.attach(this)

        val workoutModel = ViewModelProvider(this, WearWorkoutViewModel.factory(application))[WearWorkoutViewModel::class.java]
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                workoutModel.healthPermissionRequest.collect { permissions ->
                    if (!permissions.isNullOrEmpty()) {
                        workoutModel.onHealthPermissionRequestLaunched()
                        healthPermissionLauncher.launch(permissions.toTypedArray())
                    }
                }
            }
        }

        setContent {
            val workoutViewModel: WearWorkoutViewModel = viewModel(
                factory = WearWorkoutViewModel.factory(application)
            )
            // Rotary input goes to the focused list or picker (Compose for Wear handles it).
            WearWorkoutApp(viewModel = workoutViewModel, isAmbient = isAmbient)
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
