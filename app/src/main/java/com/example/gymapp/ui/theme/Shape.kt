package com.example.gymapp.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

val GymPanelShape = RoundedCornerShape(20.dp)
val GymCompactShape = RoundedCornerShape(16.dp)
val GymControlShape = RoundedCornerShape(14.dp)

val Shapes = Shapes(
    extraSmall = GymControlShape,
    small = GymCompactShape,
    medium = GymCompactShape,
    large = GymPanelShape,
    extraLarge = GymPanelShape
)
