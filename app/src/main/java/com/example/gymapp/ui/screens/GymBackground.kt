package com.example.gymapp.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.unit.dp
import androidx.compose.material3.MaterialTheme

@Composable
fun GymBackground(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val colorScheme = MaterialTheme.colorScheme
    val topGlow = colorScheme.primary.copy(alpha = 0.12f)
    val middleGlow = colorScheme.secondary.copy(alpha = 0.10f)
    val bottomGlow = colorScheme.tertiary.copy(alpha = 0.08f)
    val lineColor = colorScheme.outline.copy(alpha = 0.08f)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        colorScheme.surfaceVariant.copy(alpha = 0.92f),
                        colorScheme.background,
                        colorScheme.surface
                    )
                )
            )
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            drawCircle(
                color = topGlow,
                radius = size.minDimension * 0.34f,
                center = Offset(size.width * 0.9f, size.height * 0.08f)
            )
            drawCircle(
                color = middleGlow,
                radius = size.minDimension * 0.27f,
                center = Offset(size.width * 0.18f, size.height * 0.42f)
            )
            drawCircle(
                color = bottomGlow,
                radius = size.minDimension * 0.32f,
                center = Offset(size.width * 0.16f, size.height * 0.94f)
            )

            val spacing = 68.dp.toPx()
            var startX = -size.height
            while (startX < size.width) {
                drawLine(
                    color = lineColor,
                    start = Offset(startX, 0f),
                    end = Offset(startX + size.height, size.height),
                    strokeWidth = 1.dp.toPx(),
                    cap = StrokeCap.Round
                )
                startX += spacing
            }
        }
        content()
    }
}
