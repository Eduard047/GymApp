package com.example.gymapp.ui.components

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/**
 * Figure lifting a barbell overhead, matching the iPhone strength-training glyph used on the
 * Today goal chip. Drawn on the same 24dp grid as the Material icons so it tints and sizes alike.
 */
val GymIcons.Weightlifter: ImageVector by lazy {
    ImageVector.Builder(
        name = "Weightlifter",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f
    ).apply {
        path(fill = SolidColor(Color.Black), pathFillType = PathFillType.NonZero) {
            // Plates and bar.
            moveTo(1.5f, 2f); horizontalLineToRelative(2f); verticalLineToRelative(5.6f); horizontalLineToRelative(-2f); close()
            moveTo(20.5f, 2f); horizontalLineToRelative(2f); verticalLineToRelative(5.6f); horizontalLineToRelative(-2f); close()
            moveTo(3.5f, 3.9f); horizontalLineToRelative(17f); verticalLineToRelative(1.7f); horizontalLineToRelative(-17f); close()
            // Arms.
            moveTo(6f, 5.6f); horizontalLineToRelative(1.7f); lineTo(10f, 10f); horizontalLineTo(8.3f); close()
            moveTo(18f, 5.6f); horizontalLineToRelative(-1.7f); lineTo(14f, 10f); horizontalLineToRelative(1.7f); close()
            // Head.
            moveTo(12f, 6.6f)
            arcToRelative(1.6f, 1.6f, 0f, true, false, 0f, 3.2f)
            arcToRelative(1.6f, 1.6f, 0f, false, false, 0f, -3.2f)
            close()
            // Torso and legs.
            moveTo(9.5f, 10f); horizontalLineToRelative(5f); verticalLineToRelative(6f); horizontalLineToRelative(-5f); close()
            moveTo(9.5f, 16f); horizontalLineToRelative(2.3f); lineToRelative(-0.8f, 6f); horizontalLineTo(8.6f); close()
            moveTo(12.2f, 16f); horizontalLineToRelative(2.3f); lineToRelative(0.9f, 6f); horizontalLineTo(13f); close()
        }
    }.build()
}

/** Namespace for icons drawn in-app because Material ships no equivalent. */
object GymIcons
