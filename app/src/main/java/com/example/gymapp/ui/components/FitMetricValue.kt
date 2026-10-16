package com.example.gymapp.ui.components

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow

private const val MinMetricValueScale = 0.6f

/**
 * Metric tile value that never ellipsizes: it keeps one line and shrinks (down to 60%) until it
 * fits its tile, as the web app does; if it still does not fit at the floor (large font sizes),
 * the unit wraps onto a second line at spaces instead of being cut off.
 */
@Composable
fun FitMetricValue(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.titleMedium,
    color: Color = Color.Unspecified,
    fontWeight: FontWeight = FontWeight.Bold
) {
    var scale by remember(text) { mutableFloatStateOf(1f) }
    val atFloor = scale <= MinMetricValueScale
    Text(
        text = text,
        modifier = modifier,
        style = style.copy(
            fontSize = style.fontSize * scale,
            lineHeight = style.lineHeight * scale
        ),
        color = color,
        fontWeight = fontWeight,
        maxLines = if (atFloor) 2 else 1,
        softWrap = atFloor,
        overflow = TextOverflow.Clip,
        onTextLayout = { layout ->
            if (layout.hasVisualOverflow && scale > MinMetricValueScale) {
                scale = (scale - 0.05f).coerceAtLeast(MinMetricValueScale)
            }
        }
    )
}
