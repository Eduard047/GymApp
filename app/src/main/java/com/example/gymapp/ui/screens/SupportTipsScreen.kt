package com.example.gymapp.ui.screens

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.billing.SupportTipBilling
import com.example.gymapp.billing.SupportTipMessage
import com.example.gymapp.billing.SupportTipPhase
import com.example.gymapp.ui.components.GymHapticEvent
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.components.rememberGymHaptics
import com.example.gymapp.ui.components.rememberReduceMotion
import com.example.gymapp.ui.theme.Button
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.theme.TintedButton
import com.example.gymapp.util.formattedStringResource
import kotlinx.coroutines.delay

private const val ThanksVisibleMillis = 2_500L

/**
 * The optional tip jar, pushed from Profile > Help. Six store-priced amounts, one primary button and a
 * short thank-you. Nothing is unlocked or changed by a tip. The header is drawn by the Profile host.
 */
@Composable
internal fun SupportTipsScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val billing = remember { SupportTipBilling(context) }
    DisposableEffect(billing) {
        billing.open()
        onDispose { billing.close() }
    }
    val state by billing.state.collectAsState()
    val haptics = rememberGymHaptics()
    val reduceMotion = rememberReduceMotion()
    val horizontal = adaptiveScreenHorizontalPadding()

    LaunchedEffect(state.showThanks) {
        if (state.showThanks) {
            haptics.perform(GymHapticEvent.SupportThanks)
            delay(ThanksVisibleMillis)
            billing.dismissThanks()
        }
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(
                start = horizontal,
                end = horizontal,
                top = GymSpacing.ScreenTop,
                bottom = GymSpacing.ScreenBottom
            ),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.XLarge)
    ) {
        Text(
            text = stringResource(R.string.support_tips_intro),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = GymSpacing.Large)
        )
        when (state.phase) {
            SupportTipPhase.Loading -> Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(96.dp),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator(modifier = Modifier.size(28.dp), strokeWidth = 3.dp)
            }
            SupportTipPhase.Unavailable -> StatusNote(stringResource(R.string.support_tips_unavailable))
            SupportTipPhase.Offline -> StatusNote(stringResource(R.string.support_tips_offline))
            SupportTipPhase.Ready -> {
                Column(verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)) {
                    state.chips.chunked(3).forEachIndexed { rowIndex, rowChips ->
                        Row(horizontalArrangement = Arrangement.spacedBy(GymSpacing.Medium)) {
                            rowChips.forEachIndexed { columnIndex, chip ->
                                val index = rowIndex * 3 + columnIndex
                                val selected = index == state.selectedIndex
                                val chipModifier = Modifier
                                    .weight(1f)
                                    .heightIn(min = GymSpacing.MinimumTouch)
                                    .semantics { this.selected = selected }
                                val onSelect = { billing.select(index) }
                                if (selected) {
                                    Button(
                                        onClick = onSelect,
                                        modifier = chipModifier,
                                        contentPadding = PaddingValues(horizontal = GymSpacing.Small)
                                    ) { ChipLabel(chip.formattedPrice) }
                                } else {
                                    TintedButton(
                                        onClick = onSelect,
                                        modifier = chipModifier,
                                        contentPadding = PaddingValues(horizontal = GymSpacing.Small)
                                    ) { ChipLabel(chip.formattedPrice) }
                                }
                            }
                            // Keep a short last row aligned with the columns above it.
                            repeat(3 - rowChips.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
                if (state.showThanks) {
                    ThanksPanel(
                        reduceMotion = reduceMotion,
                        onDismiss = billing::dismissThanks
                    )
                } else {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
                    ) {
                        val price = state.selectedChip?.formattedPrice.orEmpty()
                        val activity = context.findActivity()
                        Button(
                            onClick = { activity?.let(billing::purchase) },
                            enabled = !state.purchaseInFlight && activity != null,
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = GymSpacing.MinimumTouch)
                        ) {
                            Text(formattedStringResource(R.string.support_tips_action, price))
                        }
                        val message = when (state.message) {
                            SupportTipMessage.NoNetwork -> stringResource(R.string.support_tips_offline)
                            SupportTipMessage.Pending -> stringResource(R.string.support_tips_pending)
                            SupportTipMessage.Generic -> stringResource(R.string.support_tips_error)
                            null -> null
                        }
                        if (message != null) {
                            Text(
                                text = message,
                                style = MaterialTheme.typography.bodySmall,
                                color = if (state.message == SupportTipMessage.Pending) {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                } else {
                                    MaterialTheme.colorScheme.error
                                },
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ChipLabel(price: String) {
    Text(text = price, maxLines = 1, style = MaterialTheme.typography.titleSmall)
}

@Composable
private fun StatusNote(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = GymSpacing.XXLarge)
    )
}

/** The thank-you that replaces the button: a heart that springs in (a fade when motion is reduced). */
@Composable
private fun ThanksPanel(reduceMotion: Boolean, onDismiss: () -> Unit) {
    val progress = remember { Animatable(0f) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) {
            progress.animateTo(1f, tween(durationMillis = 150))
        } else {
            progress.animateTo(
                1f,
                spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium)
            )
        }
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onDismiss)
            .padding(vertical = GymSpacing.Medium),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(GymSpacing.Small)
    ) {
        Icon(
            imageVector = Icons.Filled.Favorite,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier
                .size(44.dp)
                .alpha(progress.value.coerceIn(0f, 1f))
                .then(if (reduceMotion) Modifier else Modifier.scale(progress.value))
        )
        Text(
            text = stringResource(R.string.support_tips_thanks_title),
            style = MaterialTheme.typography.titleMedium
        )
        Text(
            text = stringResource(R.string.support_tips_thanks_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
