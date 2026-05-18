package com.example.gymapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush

@Composable
fun GymBackground(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val colorScheme = MaterialTheme.colorScheme

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        colorScheme.background,
                        colorScheme.background,
                        colorScheme.surfaceVariant.copy(alpha = 0.78f)
                    )
                )
            )
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.linearGradient(
                        colors = listOf(
                            colorScheme.primary.copy(alpha = 0.18f),
                            colorScheme.secondary.copy(alpha = 0.08f),
                            colorScheme.tertiary.copy(alpha = 0.12f),
                            colorScheme.background.copy(alpha = 0f)
                        )
                    )
                )
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            colorScheme.surface.copy(alpha = 0.24f),
                            colorScheme.background.copy(alpha = 0.18f),
                            colorScheme.background.copy(alpha = 0.88f)
                        )
                    )
                )
        )
        content()
    }
}
