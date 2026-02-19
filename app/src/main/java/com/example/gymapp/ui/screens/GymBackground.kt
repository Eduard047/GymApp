package com.example.gymapp.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush

@Composable
fun GymBackground(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val primaryGlow = androidx.compose.material3.MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
    val secondaryGlow = androidx.compose.material3.MaterialTheme.colorScheme.secondary.copy(alpha = 0.09f)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        androidx.compose.material3.MaterialTheme.colorScheme.surfaceVariant,
                        androidx.compose.material3.MaterialTheme.colorScheme.background,
                        androidx.compose.material3.MaterialTheme.colorScheme.surface
                    )
                )
            )
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val topRight = androidx.compose.ui.geometry.Offset(size.width * 0.92f, size.height * 0.08f)
            val bottomLeft = androidx.compose.ui.geometry.Offset(size.width * 0.12f, size.height * 0.82f)

            drawCircle(
                color = primaryGlow,
                radius = size.minDimension * 0.28f,
                center = topRight
            )
            drawCircle(
                color = secondaryGlow,
                radius = size.minDimension * 0.24f,
                center = bottomLeft
            )
        }
        content()
    }
}
