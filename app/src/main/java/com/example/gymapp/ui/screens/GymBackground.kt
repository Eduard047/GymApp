package com.example.gymapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
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
                Brush.linearGradient(
                    colors = listOf(
                        colorScheme.surface,
                        colorScheme.background,
                        colorScheme.surfaceVariant.copy(alpha = 0.72f)
                    )
                )
            )
    ) {
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .offset(x = 150.dp, y = (-170).dp)
                .size(420.dp)
                .blur(68.dp)
                .background(colorScheme.primary.copy(alpha = 0.17f), CircleShape)
        )
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .offset(x = (-150).dp, y = 170.dp)
                .size(360.dp)
                .blur(74.dp)
                .background(colorScheme.secondary.copy(alpha = 0.13f), CircleShape)
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .offset(x = 100.dp, y = 120.dp)
                .size(290.dp)
                .blur(62.dp)
                .background(colorScheme.tertiary.copy(alpha = 0.09f), CircleShape)
        )
        content()
    }
}
