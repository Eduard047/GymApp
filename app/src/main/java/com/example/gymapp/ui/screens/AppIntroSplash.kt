package com.example.gymapp.ui.screens

import android.provider.Settings
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.AppBrandMark
import kotlinx.coroutines.delay

/** Brand mark size; equals the system launch screen mark (splash_brand_mark, launch_window_background) and iOS's 120pt. */
private val SplashMarkSize = 120.dp
private val SplashMarkToTextGap = 24.dp
private const val SplashFadeMillis = 250
private const val SplashSpinnerDelayMillis = 1000L

/**
 * Continues the system launch screen without a visible seam: same canvas color, same
 * brand mark, same size, same exact-center point. The mark never moves or animates;
 * the wordmark/tagline and the loading spinner are anchored independently below it.
 */
@Composable
fun AppIntroSplash(modifier: Modifier = Modifier) {
    val colorScheme = MaterialTheme.colorScheme
    val context = LocalContext.current
    val animationsEnabled = remember {
        runCatching {
            Settings.Global.getFloat(
                context.contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f
            ) > 0f
        }.getOrDefault(true)
    }
    var textVisible by remember { mutableStateOf(false) }
    var spinnerVisible by remember { mutableStateOf(false) }

    val fadeSpec = if (animationsEnabled) tween<Float>(SplashFadeMillis) else snap()
    val textAlpha by animateFloatAsState(
        targetValue = if (textVisible) 1f else 0f,
        animationSpec = fadeSpec,
        label = "splashTextAlpha"
    )
    val spinnerAlpha by animateFloatAsState(
        targetValue = if (spinnerVisible) 1f else 0f,
        animationSpec = fadeSpec,
        label = "splashSpinnerAlpha"
    )

    LaunchedEffect(Unit) {
        textVisible = true
        // A quick start never shows the spinner; leaving composition cancels this delay.
        delay(SplashSpinnerDelayMillis)
        spinnerVisible = true
    }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(colorScheme.background)
    ) {
        AppBrandMark(
            modifier = Modifier
                .align(Alignment.Center)
                .size(SplashMarkSize)
        )
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                // Anchored a fixed gap below the mark's own position, so nothing below moves it.
                .padding(top = maxHeight / 2 + SplashMarkSize / 2 + SplashMarkToTextGap)
                .widthIn(max = 440.dp)
                .padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Column(
                modifier = Modifier.graphicsLayer { alpha = textAlpha },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.splash_wordmark),
                    style = MaterialTheme.typography.headlineLarge,
                    fontWeight = FontWeight.Bold,
                    color = colorScheme.onBackground,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.semantics { heading() }
                )
                Text(
                    text = stringResource(R.string.splash_tagline),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }
            if (spinnerVisible) {
                val loadingDescription = stringResource(R.string.splash_loading)
                CircularProgressIndicator(
                    modifier = Modifier
                        .size(28.dp)
                        .graphicsLayer { alpha = spinnerAlpha }
                        .semantics { contentDescription = loadingDescription },
                    color = colorScheme.primary,
                    strokeWidth = 3.dp
                )
            }
        }
    }
}
