package com.example.gymapp.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
fun AppPanel(
    modifier: Modifier = Modifier,
    containerColor: Color = MaterialTheme.colorScheme.surface,
    contentColor: Color = MaterialTheme.colorScheme.onSurface,
    highlighted: Boolean = false,
    content: @Composable () -> Unit
) {
    val shape = MaterialTheme.shapes.large
    val panelBrush = Brush.verticalGradient(
        colors = listOf(
            containerColor.copy(alpha = if (highlighted) 0.86f else 0.68f),
            MaterialTheme.colorScheme.surfaceVariant.copy(alpha = if (highlighted) 0.62f else 0.42f)
        )
    )
    val strokeColor = if (highlighted) {
        MaterialTheme.colorScheme.primary.copy(alpha = 0.38f)
    } else {
        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.74f)
    }

    Surface(
        modifier = modifier
            .clip(shape)
            .background(panelBrush, shape)
            .border(BorderStroke(1.dp, strokeColor), shape),
        color = Color.Transparent,
        contentColor = contentColor,
        shape = shape,
        tonalElevation = 0.dp,
        shadowElevation = if (highlighted) 16.dp else 6.dp
    ) {
        content()
    }
}

@Composable
fun HeroPanel(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val shape = MaterialTheme.shapes.extraLarge
    Surface(
        modifier = modifier
            .clip(shape)
            .background(
                brush = Brush.linearGradient(
                    colors = listOf(
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.86f),
                        MaterialTheme.colorScheme.secondary.copy(alpha = 0.68f),
                        MaterialTheme.colorScheme.tertiary.copy(alpha = 0.58f)
                    )
                ),
                shape = shape
            )
            .border(
                BorderStroke(1.dp, MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.2f)),
                shape
            ),
        color = Color.Transparent,
        contentColor = MaterialTheme.colorScheme.onPrimary,
        shape = shape,
        shadowElevation = 18.dp
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            content()
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
    val tileContainerColor = when {
        onHero && emphasized -> MaterialTheme.colorScheme.primary
        onHero -> MaterialTheme.colorScheme.primary
        emphasized -> MaterialTheme.colorScheme.surfaceVariant
        else -> MaterialTheme.colorScheme.surface
    }
    val tileContentColor = if (onHero) {
        MaterialTheme.colorScheme.onPrimary
    } else {
        MaterialTheme.colorScheme.onSurface
    }
    val labelColor = if (onHero) {
        MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.78f)
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    AppPanel(
        modifier = modifier,
        containerColor = tileContainerColor,
        contentColor = tileContentColor,
        highlighted = emphasized
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                color = labelColor,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = value,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = tileContentColor,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun InfoPill(
    text: String,
    modifier: Modifier = Modifier,
    accent: Color = MaterialTheme.colorScheme.primary
) {
    Surface(
        modifier = modifier,
        color = accent.copy(alpha = 0.1f),
        contentColor = accent,
        shape = MaterialTheme.shapes.small,
        border = BorderStroke(1.dp, accent.copy(alpha = 0.16f))
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            maxLines = 1,
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
