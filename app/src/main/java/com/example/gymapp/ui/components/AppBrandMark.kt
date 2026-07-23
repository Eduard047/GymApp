package com.example.gymapp.ui.components

import androidx.compose.foundation.Image
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import com.example.gymapp.R

@Composable
fun AppBrandMark(
    modifier: Modifier = Modifier,
    scale: Float = 1f,
    alpha: Float = 1f
) {
    Image(
        painter = painterResource(R.drawable.ic_launcher_artwork),
        contentDescription = null,
        contentScale = ContentScale.Fit,
        modifier = modifier.graphicsLayer {
            scaleX = scale
            scaleY = scale
            this.alpha = alpha
        }
    )
}
