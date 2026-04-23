package com.example.gymapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.dp

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
                        colorScheme.surface,
                        colorScheme.background,
                        colorScheme.surfaceVariant.copy(alpha = 0.72f)
                    )
                )
            )
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Box(
                modifier = Modifier
                    .size(320.dp)
                    .align(Alignment.TopEnd)
                    .background(colorScheme.primary.copy(alpha = 0.08f), CircleShape)
            )
            Box(
                modifier = Modifier
                    .size(260.dp)
                    .align(Alignment.CenterStart)
                    .background(colorScheme.tertiary.copy(alpha = 0.08f), CircleShape)
            )
            Box(
                modifier = Modifier
                    .size(220.dp)
                    .align(Alignment.BottomEnd)
                    .background(colorScheme.secondary.copy(alpha = 0.06f), CircleShape)
            )
        }
        content()
    }
}
