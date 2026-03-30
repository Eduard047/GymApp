package com.example.gymapp.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.gymapp.wear.ui.WearWorkoutApp
import com.example.gymapp.wear.ui.WearWorkoutViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            val workoutViewModel: WearWorkoutViewModel = viewModel(
                factory = WearWorkoutViewModel.factory(application)
            )

            MaterialTheme {
                Surface {
                    WearWorkoutApp(viewModel = workoutViewModel)
                }
            }
        }
    }
}
