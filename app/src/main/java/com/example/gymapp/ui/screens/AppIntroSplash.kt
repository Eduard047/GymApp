package com.example.gymapp.ui.screens

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.ColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.gymapp.R

@Composable
fun AppIntroSplash(modifier: Modifier = Modifier) {
    var visible by remember { mutableStateOf(false) }
    val colorScheme = MaterialTheme.colorScheme

    val introScale by animateFloatAsState(
        targetValue = if (visible) 1f else 0.92f,
        animationSpec = tween(durationMillis = 700, easing = FastOutSlowInEasing),
        label = "introScale"
    )
    val introAlpha by animateFloatAsState(
        targetValue = if (visible) 1f else 0f,
        animationSpec = tween(durationMillis = 520),
        label = "introAlpha"
    )

    val infiniteTransition = rememberInfiniteTransition(label = "splash")
    val glowShift by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 3600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "glowShift"
    )

    LaunchedEffect(Unit) {
        visible = true
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        colorScheme.surfaceVariant,
                        colorScheme.background,
                        colorScheme.surface
                    )
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        val primaryGlow = colorScheme.primary.copy(alpha = 0.14f)
        val secondaryGlow = colorScheme.secondary.copy(alpha = 0.12f)
        val tertiaryGlow = colorScheme.tertiary.copy(alpha = 0.10f)

        Canvas(modifier = Modifier.fillMaxSize()) {
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(primaryGlow, Color.Transparent),
                    center = Offset(size.width * (0.75f + glowShift * 0.08f), size.height * 0.16f),
                    radius = size.minDimension * 0.34f
                ),
                radius = size.minDimension * 0.34f,
                center = Offset(size.width * (0.75f + glowShift * 0.08f), size.height * 0.16f)
            )
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(secondaryGlow, Color.Transparent),
                    center = Offset(size.width * 0.26f, size.height * (0.78f - glowShift * 0.08f)),
                    radius = size.minDimension * 0.28f
                ),
                radius = size.minDimension * 0.28f,
                center = Offset(size.width * 0.26f, size.height * (0.78f - glowShift * 0.08f))
            )
            drawCircle(
                color = tertiaryGlow,
                radius = size.minDimension * 0.18f,
                center = Offset(size.width * 0.58f, size.height * 0.82f)
            )
        }

        Column(
            modifier = Modifier.width(260.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            BrandMark(
                modifier = Modifier.size(96.dp),
                scale = introScale,
                alpha = introAlpha,
                colorScheme = colorScheme
            )
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = stringResource(R.string.app_name),
                    style = MaterialTheme.typography.headlineLarge,
                    color = colorScheme.onBackground.copy(alpha = introAlpha),
                    textAlign = TextAlign.Center
                )
                Text(
                    text = stringResource(R.string.splash_tagline),
                    style = MaterialTheme.typography.bodyLarge,
                    color = colorScheme.onSurfaceVariant.copy(alpha = introAlpha),
                    textAlign = TextAlign.Center
                )
                Text(
                    text = stringResource(R.string.splash_loading),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Medium,
                    color = colorScheme.primary.copy(alpha = introAlpha)
                )
            }
        }
    }
}

@Composable
private fun BrandMark(
    modifier: Modifier = Modifier,
    scale: Float,
    alpha: Float,
    colorScheme: ColorScheme
) {
    Canvas(modifier = modifier) {
        val strokeWidth = size.minDimension * 0.06f
        val inset = size.minDimension * 0.18f
        val barWidth = size.width * 0.44f * scale
        val barHeight = size.height * 0.11f
        val sideWidth = size.width * 0.1f
        val sideHeight = size.height * 0.42f
        val centerX = size.width / 2f
        val centerY = size.height / 2f

        drawRoundRect(
            color = colorScheme.primary.copy(alpha = alpha),
            topLeft = Offset(centerX - barWidth / 2f, centerY - barHeight / 2f),
            size = Size(barWidth, barHeight),
            cornerRadius = CornerRadius(barHeight / 2f, barHeight / 2f)
        )
        drawRoundRect(
            color = colorScheme.secondary.copy(alpha = alpha),
            topLeft = Offset(centerX - inset - sideWidth, centerY - sideHeight / 2f),
            size = Size(sideWidth, sideHeight),
            cornerRadius = CornerRadius(sideWidth / 2f, sideWidth / 2f)
        )
        drawRoundRect(
            color = colorScheme.secondary.copy(alpha = alpha),
            topLeft = Offset(centerX + inset, centerY - sideHeight / 2f),
            size = Size(sideWidth, sideHeight),
            cornerRadius = CornerRadius(sideWidth / 2f, sideWidth / 2f)
        )
        drawRoundRect(
            color = colorScheme.tertiary.copy(alpha = alpha),
            topLeft = Offset(centerX - inset - sideWidth * 2.1f, centerY - sideHeight * 0.38f),
            size = Size(sideWidth, sideHeight * 0.76f),
            cornerRadius = CornerRadius(sideWidth / 2f, sideWidth / 2f)
        )
        drawRoundRect(
            color = colorScheme.tertiary.copy(alpha = alpha),
            topLeft = Offset(centerX + inset + sideWidth * 1.1f, centerY - sideHeight * 0.38f),
            size = Size(sideWidth, sideHeight * 0.76f),
            cornerRadius = CornerRadius(sideWidth / 2f, sideWidth / 2f)
        )
        drawCircle(
            color = colorScheme.onBackground.copy(alpha = alpha * 0.12f),
            radius = size.minDimension * 0.4f,
            center = Offset(centerX, centerY),
            style = Stroke(width = strokeWidth)
        )
    }
}
