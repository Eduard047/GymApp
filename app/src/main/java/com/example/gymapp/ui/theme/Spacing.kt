package com.example.gymapp.ui.theme

import androidx.compose.ui.unit.dp

/**
 * Fluid Focus spacing keeps dense workout controls readable without turning the journal into a
 * stack of unrelated cards. Screen code should prefer these steps over one-off dimensions.
 */
object GymSpacing {
    val Hairline = 2.dp
    val XSmall = 4.dp
    val Small = 8.dp
    val Medium = 12.dp
    val Large = 16.dp
    val XLarge = 20.dp
    val XXLarge = 24.dp
    val Section = 32.dp

    val ScreenHorizontal = Large
    val ScreenTop = Medium
    val ScreenBottom = Section
    val MinimumTouch = 48.dp
}
