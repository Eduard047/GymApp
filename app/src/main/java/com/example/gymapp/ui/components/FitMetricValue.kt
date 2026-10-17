package com.example.gymapp.ui.components

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints

private const val MinMetricValueScale = 0.6f
private const val WrappedMetricValueScale = 0.8f
private const val MetricValueScaleStep = 0.05f

/**
 * Metric tile value that never ellipsizes: it keeps one line and shrinks (down to 60%) until it
 * fits its tile, as the web app does; if it still does not fit at the floor (large font sizes),
 * the unit wraps onto a second line at spaces at 80% of the size instead of being cut off.
 *
 * The scale is measured in one pass from the tile width, text, style and font scale, so it also
 * grows back after a rotation, a fold or a smaller font size.
 */
@Composable
fun FitMetricValue(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.titleMedium,
    color: Color = Color.Unspecified,
    fontWeight: FontWeight = FontWeight.Bold
) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    BoxWithConstraints(modifier = modifier) {
        val maxWidthPx = constraints.maxWidth
        val fit = remember(text, style, fontWeight, maxWidthPx, density.density, density.fontScale) {
            fitMetricValue(measurer, text, style.copy(fontWeight = fontWeight), maxWidthPx)
        }
        Text(
            text = text,
            style = style.copy(
                fontSize = style.fontSize * fit.scale,
                lineHeight = style.lineHeight * fit.scale
            ),
            color = color,
            fontWeight = fontWeight,
            maxLines = if (fit.wraps) 2 else 1,
            softWrap = fit.wraps,
            overflow = TextOverflow.Clip
        )
    }
}

internal data class MetricValueFit(val scale: Float, val wraps: Boolean)

internal fun fitMetricValue(
    measurer: TextMeasurer,
    text: String,
    style: TextStyle,
    maxWidthPx: Int
): MetricValueFit {
    if (maxWidthPx <= 0 || maxWidthPx == Constraints.Infinity) return MetricValueFit(1f, wraps = false)
    var scale = 1f
    while (scale >= MinMetricValueScale - 0.0001f) {
        val width = measurer.measure(
            text = text,
            style = style.copy(
                fontSize = style.fontSize * scale,
                lineHeight = style.lineHeight * scale
            ),
            maxLines = 1,
            softWrap = false
        ).size.width
        if (width <= maxWidthPx) return MetricValueFit(scale, wraps = false)
        scale -= MetricValueScaleStep
    }
    return if (text.any { it.isWhitespace() }) {
        MetricValueFit(WrappedMetricValueScale, wraps = true)
    } else {
        MetricValueFit(MinMetricValueScale, wraps = false)
    }
}

/**
 * One-line label that follows the system text size and shrinks (to 60%) only when it would not fit
 * its slot, so a tab label never breaks mid-word and is not cut off by an ellipsis unless even the
 * smallest size does not fit.
 */
@Composable
fun FitSingleLineLabel(
    text: String,
    style: TextStyle,
    modifier: Modifier = Modifier,
    textAlign: androidx.compose.ui.text.style.TextAlign = androidx.compose.ui.text.style.TextAlign.Center
) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    BoxWithConstraints(modifier = modifier) {
        val maxWidthPx = constraints.maxWidth
        val scale = remember(text, style, maxWidthPx, density.density, density.fontScale) {
            // A one-line label never wraps: when even the smallest size does not fit, it stays at the
            // floor (fitMetricValue reports the wrap size for such text, which does not apply here).
            val fit = fitMetricValue(measurer, text, style, maxWidthPx)
            if (fit.wraps) MinMetricValueScale else fit.scale
        }
        Text(
            text = text,
            modifier = Modifier.fillMaxWidth(),
            style = style.copy(
                fontSize = style.fontSize * scale,
                lineHeight = style.lineHeight * scale
            ),
            textAlign = textAlign,
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Ellipsis
        )
    }
}
