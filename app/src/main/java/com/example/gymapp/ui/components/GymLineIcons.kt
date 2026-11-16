package com.example.gymapp.ui.components

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/*
 * Line glyphs drawn in-app so Android shows the same shapes as iPhone where Material has none
 * that match (an outline bin, a level dumbbell). Original drawings on a 24dp grid: one stroke
 * weight, round caps and joins, mirrored numerically around x = 12. Coordinates are stroke
 * centrelines; the ink reaches half a stroke further and stays inside 2..22.
 */

/** The one stroke weight of the set at 24dp; it scales with the icon size. */
private const val LineIconStroke = 1.75f

private fun lineIcon(name: String, block: ImageVector.Builder.() -> Unit): ImageVector =
    ImageVector.Builder(
        name = name,
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f
    ).apply(block).build()

/** Outline part: stroke only. */
private fun ImageVector.Builder.line(block: PathBuilder.() -> Unit) {
    path(
        fill = null,
        stroke = SolidColor(Color.Black),
        strokeLineWidth = LineIconStroke,
        strokeLineCap = StrokeCap.Round,
        strokeLineJoin = StrokeJoin.Round,
        pathBuilder = block
    )
}

/** Filled twin: the same path filled and stroked, so the outer edge matches the outline. */
private fun ImageVector.Builder.solid(block: PathBuilder.() -> Unit) {
    path(
        fill = SolidColor(Color.Black),
        stroke = SolidColor(Color.Black),
        strokeLineWidth = LineIconStroke,
        strokeLineCap = StrokeCap.Round,
        strokeLineJoin = StrokeJoin.Round,
        pathBuilder = block
    )
}

/** Outline bin for "delete": lid, handle, tapered body and two slats. */
val GymIcons.Trash: ImageVector by lazy {
    lineIcon("Trash") {
        line {
            // Lid.
            moveTo(4.5f, 6.5f)
            horizontalLineTo(19.5f)
            // Handle.
            moveTo(9.5f, 6.5f)
            verticalLineTo(5f)
            arcToRelative(1.5f, 1.5f, 0f, false, true, 1.5f, -1.5f)
            horizontalLineToRelative(2f)
            arcToRelative(1.5f, 1.5f, 0f, false, true, 1.5f, 1.5f)
            verticalLineTo(6.5f)
            // Body.
            moveTo(6.5f, 6.5f)
            lineTo(7.3f, 18.7f)
            arcToRelative(2f, 2f, 0f, false, false, 2f, 1.8f)
            horizontalLineToRelative(5.4f)
            arcToRelative(2f, 2f, 0f, false, false, 2f, -1.8f)
            lineTo(17.5f, 6.5f)
            // Slats.
            moveTo(10f, 10.5f)
            verticalLineTo(16.5f)
            moveTo(14f, 10.5f)
            verticalLineTo(16.5f)
        }
    }
}

/** Outline "share": an open-topped tray with an arrow rising out of it. */
val GymIcons.ShareUp: ImageVector by lazy {
    lineIcon("ShareUp") {
        line {
            // Arrow shaft and head.
            moveTo(12f, 14.5f)
            verticalLineTo(3.5f)
            moveTo(8.25f, 7.25f)
            lineTo(12f, 3.5f)
            lineTo(15.75f, 7.25f)
            // Tray, open where the arrow passes.
            moveTo(8.5f, 10.5f)
            horizontalLineTo(7.5f)
            arcToRelative(2f, 2f, 0f, false, false, -2f, 2f)
            verticalLineTo(18.5f)
            arcToRelative(2f, 2f, 0f, false, false, 2f, 2f)
            horizontalLineTo(16.5f)
            arcToRelative(2f, 2f, 0f, false, false, 2f, -2f)
            verticalLineTo(12.5f)
            arcToRelative(2f, 2f, 0f, false, false, -2f, -2f)
            horizontalLineTo(15.5f)
        }
    }
}

/** Level dumbbell: a short outer plate and a tall inner plate on each side of the grip. */
private fun PathBuilder.dumbbellShape() {
    // Outer plates.
    moveTo(2.9f, 9.5f)
    verticalLineTo(14.5f)
    moveTo(21.1f, 9.5f)
    verticalLineTo(14.5f)
    // Inner plates.
    moveTo(6.1f, 7.75f)
    arcToRelative(1.75f, 1.75f, 0f, false, true, 3.5f, 0f)
    verticalLineTo(16.25f)
    arcToRelative(1.75f, 1.75f, 0f, false, true, -3.5f, 0f)
    close()
    moveTo(14.4f, 7.75f)
    arcToRelative(1.75f, 1.75f, 0f, false, true, 3.5f, 0f)
    verticalLineTo(16.25f)
    arcToRelative(1.75f, 1.75f, 0f, false, true, -3.5f, 0f)
    close()
    // Grip.
    moveTo(9.6f, 12f)
    horizontalLineTo(14.4f)
}

/** Exercises tab, unselected. */
val GymIcons.Dumbbell: ImageVector by lazy {
    lineIcon("Dumbbell") { line { dumbbellShape() } }
}

/** Exercises tab, selected: the same silhouette with the inner plates filled. */
val GymIcons.DumbbellFilled: ImageVector by lazy {
    lineIcon("DumbbellFilled") { solid { dumbbellShape() } }
}
