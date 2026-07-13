package com.example.gymapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

@Composable
fun GymBackground(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val colorScheme = MaterialTheme.colorScheme
    val darkTheme = isSystemInDarkTheme()
    val backgroundRaised = if (darkTheme) Color(0xFF09111B) else Color(0xFFF4F7F8)
    val backgroundVariant = if (darkTheme) Color(0xFF182534) else Color(0xFFDDE7EB)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        backgroundRaised,
                        colorScheme.background,
                        backgroundVariant.copy(alpha = 0.72f)
                    ),
                    start = Offset.Zero,
                    end = Offset.Infinite
                )
            )
    ) {
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
            val primarySize = (maxWidth * 0.92f).coerceAtMost(420.dp)
            val secondarySize = (maxWidth * 0.82f).coerceAtMost(360.dp)
            val tertiarySize = (maxWidth * 0.64f).coerceAtMost(290.dp)

            Box(
                modifier = Modifier
                    .align(Alignment.Center)
                    .offset(x = maxWidth * 0.34f, y = maxHeight * -0.28f)
                    .size(primarySize)
                    .blur(68.dp, edgeTreatment = BlurredEdgeTreatment.Unbounded)
                    .background(colorScheme.primary.copy(alpha = 0.17f), CircleShape)
            )
            Box(
                modifier = Modifier
                    .align(Alignment.Center)
                    .offset(x = maxWidth * -0.36f, y = maxHeight * 0.32f)
                    .size(secondarySize)
                    .blur(74.dp, edgeTreatment = BlurredEdgeTreatment.Unbounded)
                    .background(colorScheme.secondary.copy(alpha = 0.13f), CircleShape)
            )
            Box(
                modifier = Modifier
                    .align(Alignment.Center)
                    .offset(x = maxWidth * 0.36f, y = maxHeight * 0.42f)
                    .size(tertiarySize)
                    .blur(62.dp, edgeTreatment = BlurredEdgeTreatment.Unbounded)
                    .background(colorScheme.tertiary.copy(alpha = 0.09f), CircleShape)
            )
        }
        content()
    }
}
