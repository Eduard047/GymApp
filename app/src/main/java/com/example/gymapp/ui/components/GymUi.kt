package com.example.gymapp.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gymapp.ui.theme.GymCompactShape
import com.example.gymapp.ui.theme.GymPanelShape

@Composable
fun AppPanel(
    modifier: Modifier = Modifier,
    containerColor: Color = MaterialTheme.colorScheme.surface,
    contentColor: Color = MaterialTheme.colorScheme.onSurface,
    highlighted: Boolean = false,
    content: @Composable () -> Unit
) {
    val darkTheme = isSystemInDarkTheme()
    val shape = GymPanelShape
    val panelColor = if (highlighted) {
        containerColor.withMultipliedAlpha(0.82f)
    } else {
        containerColor.withMultipliedAlpha(0.68f)
    }
    val softOutline = if (darkTheme) Color(0xFF304354) else Color.White
    val strokeColor = if (highlighted) {
        MaterialTheme.colorScheme.primary.withMultipliedAlpha(0.34f)
    } else {
        softOutline.withMultipliedAlpha(0.62f)
    }

    Box(
        modifier = modifier
            .shadow(
                elevation = if (highlighted) 20.dp else 13.dp,
                shape = shape,
                clip = false,
                ambientColor = Color.Black.copy(alpha = 0.13f),
                spotColor = Color.Black.copy(alpha = 0.13f)
            )
            .clip(shape)
            .background(panelColor, shape)
            .border(BorderStroke(1.dp, strokeColor), shape)
    ) {
        CompositionLocalProvider(LocalContentColor provides contentColor) {
            content()
        }
    }
}

@Composable
fun HeroPanel(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val darkTheme = isSystemInDarkTheme()
    val shape = GymPanelShape
    val leading = if (darkTheme) Color(0xFF132636) else Color(0xFF102A42)
    val trailing = if (darkTheme) Color(0xFF214C40) else Color(0xFF35627E)
    Box(
        modifier = modifier
            .shadow(
                elevation = 20.dp,
                shape = shape,
                clip = false,
                ambientColor = leading.copy(alpha = 0.24f),
                spotColor = leading.copy(alpha = 0.24f)
            )
            .clip(shape)
            .background(
                brush = Brush.linearGradient(
                    colors = listOf(leading, trailing),
                    start = Offset.Zero,
                    end = Offset.Infinite
                ),
                shape = shape
            )
            .border(
                BorderStroke(1.dp, Color.White.copy(alpha = 0.18f)),
                shape
            )
    ) {
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .offset(x = 52.dp, y = (-70).dp)
                .size(150.dp)
                .blur(2.dp, edgeTreatment = BlurredEdgeTreatment.Unbounded)
                .background(Color.White.copy(alpha = 0.10f), CircleShape)
        )

        CompositionLocalProvider(LocalContentColor provides Color.White) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(20.dp)
            ) {
                content()
            }
        }
    }
}

@Composable
fun SectionTitle(
    eyebrow: String,
    title: String,
    supporting: String? = null,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            text = eyebrow.uppercase(),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.secondary
        )
        Text(
            text = title,
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.onSurface
        )
        if (!supporting.isNullOrBlank()) {
            Text(
                text = supporting,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
fun MetricTile(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    emphasized: Boolean = false,
    onHero: Boolean = false
) {
    val darkTheme = isSystemInDarkTheme()
    val shape = GymCompactShape
    val tileContainerColor = if (onHero) {
        Color.White.copy(alpha = 0.11f)
    } else {
        val surfaceVariant = if (darkTheme) Color(0xFF182534) else Color(0xFFDDE7EB)
        surfaceVariant.withMultipliedAlpha(0.55f)
    }
    val tileContentColor = if (onHero) {
        Color.White
    } else {
        MaterialTheme.colorScheme.onSurface
    }
    val labelColor = if (onHero) {
        Color.White.copy(alpha = 0.76f)
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    val borderColor = if (onHero) {
        Color.White.copy(alpha = 0.14f)
    } else {
        val softOutline = if (darkTheme) Color(0xFF304354) else Color.White
        softOutline.withMultipliedAlpha(0.55f)
    }

    Column(
        modifier = modifier
            .heightIn(min = 78.dp)
            .clip(shape)
            .background(tileContainerColor, shape)
            .border(BorderStroke(1.dp, borderColor), shape)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.35.sp,
            color = labelColor,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = value,
            style = if (emphasized) MaterialTheme.typography.titleLarge else MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = tileContentColor,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

private fun Color.withMultipliedAlpha(multiplier: Float): Color =
    copy(alpha = alpha * multiplier.coerceIn(0f, 1f))

@Composable
fun InfoPill(
    text: String,
    modifier: Modifier = Modifier,
    accent: Color = MaterialTheme.colorScheme.primary
) {
    Surface(
        modifier = modifier,
        color = accent.copy(alpha = 0.12f),
        contentColor = accent,
        shape = CircleShape,
        border = BorderStroke(1.dp, accent.copy(alpha = 0.22f))
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 11.dp, vertical = 7.dp),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
fun EmptyStatePanel(
    title: String,
    supporting: String,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier,
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = supporting,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
